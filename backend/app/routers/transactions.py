import os
from datetime import date

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.deps import get_current_user
from app.models import Transaction, User
from app.schemas import (
    ClassificationResult,
    OcrResult,
    ProcessPaymentScreenshotResponse,
    ProcessReceiptResponse,
    TransactionCreate,
    TransactionOut,
    TransactionUpdate,
)
from app.services.analytics import check_budget_alerts
from app.services.classify.pipeline import classify_transaction
from app.services.ocr.pipeline import process_receipt
from app.services.payment_screenshot.pipeline import (
    payment_extract_to_ocr_result,
    process_payment_screenshot,
)
from app.services.transactions import (
    add_merchant_reference,
    create_transaction_from_payment_screenshot,
    create_transaction_from_ocr,
    save_transaction,
    to_transaction_out,
    update_merchant_graph,
)

router = APIRouter(prefix="/transactions", tags=["transactions"])


@router.post("/process-receipt", response_model=ProcessReceiptResponse)
async def process_receipt_endpoint(
    file: UploadFile = File(...),
    is_low_quality: bool = Form(False),
    raw_text_hint: str | None = Form(None),
    auto_save: bool = Form(False),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    image_bytes = await file.read()
    ocr: OcrResult = await process_receipt(db, user.id, image_bytes, is_low_quality, raw_text_hint)
    classification: ClassificationResult = await classify_transaction(db, user.id, ocr)

    tx_id = None
    if auto_save and ocr.total_amount:
        tx = await create_transaction_from_ocr(db, user.id, ocr, classification)
        tx_id = tx.id

    return ProcessReceiptResponse(ocr=ocr, classification=classification, transaction_id=tx_id)


@router.post("/process-payment-screenshot", response_model=ProcessPaymentScreenshotResponse)
async def process_payment_screenshot_endpoint(
    file: UploadFile = File(...),
    raw_text_hint: str | None = Form(None),
    auto_save: bool = Form(False),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    image_bytes = await file.read()
    extraction = await process_payment_screenshot(image_bytes, raw_text_hint)
    pseudo_ocr: OcrResult = payment_extract_to_ocr_result(extraction)
    classification: ClassificationResult = await classify_transaction(
        db,
        user.id,
        pseudo_ocr,
        amount=extraction.total_amount,
        transaction_date=extraction.transaction_date,
    )

    tx_id = None
    if auto_save and extraction.total_amount:
        tx = await create_transaction_from_payment_screenshot(
            db,
            user.id,
            extraction,
            classification,
        )
        tx_id = tx.id

    return ProcessPaymentScreenshotResponse(
        extraction=extraction,
        classification=classification,
        transaction_id=tx_id,
    )


@router.post("", response_model=TransactionOut)
async def create_transaction(
    body: TransactionCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    tx = await save_transaction(db, user.id, body)
    await check_budget_alerts(db, user.id)
    return await to_transaction_out(db, tx)


@router.get("", response_model=list[TransactionOut])
async def list_transactions(
    limit: int = 50,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(Transaction)
        .where(Transaction.user_id == user.id)
        .order_by(Transaction.created_at.desc(), Transaction.id.desc())
        .limit(limit)
        .offset(offset)
    )
    txs = result.scalars().all()
    return [await to_transaction_out(db, tx) for tx in txs]


@router.patch("/{transaction_id}", response_model=TransactionOut)
async def update_transaction(
    transaction_id: int,
    body: TransactionUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(Transaction).where(Transaction.id == transaction_id, Transaction.user_id == user.id)
    )
    tx = result.scalar_one_or_none()
    if not tx:
        raise HTTPException(status_code=404, detail="Transaction not found")

    if body.category_id is not None:
        tx.category_id = body.category_id
        from app.services.classify.pipeline import store_embedding

        await store_embedding(
            db,
            user.id,
            tx.id,
            tx.merchant_name,
            tx.items,
            tx.amount,
            tx.transaction_date,
            category_id=body.category_id,
        )
        await update_merchant_graph(db, tx.merchant_name, body.category_id, user.id)
        if tx.merchant_name:
            await add_merchant_reference(db, user.id, tx.merchant_name)

    if body.merchant_name is not None:
        tx.merchant_name = body.merchant_name
    if body.amount is not None:
        tx.amount = body.amount

    return await to_transaction_out(db, tx)


@router.post("/{transaction_id}/confirm", response_model=TransactionOut)
async def confirm_category(
    transaction_id: int,
    category_id: int = Query(...),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await update_transaction(
        transaction_id,
        TransactionUpdate(category_id=category_id),
        db,
        user,
    )
