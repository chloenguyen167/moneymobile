from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile
from fastapi.responses import FileResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.deps import get_current_user
from app.models import Transaction, TransactionEmbedding, TransactionType, User
from app.schemas import (
    ClassificationResult,
    OcrResult,
    ProcessImageResponse,
    ProcessPaymentScreenshotResponse,
    ProcessReceiptResponse,
    TransactionCreate,
    TransactionOut,
    TransactionUpdate,
)
from app.services.analytics import check_budget_alerts
from app.services.classify.pipeline import classify_transaction
from app.services.ocr.document_detect import detect_document_kind
from app.services.ocr.pipeline import process_receipt
from app.services.ocr.vietocr_engine import run_vietocr_sync, vietocr_available
from app.services.payment_screenshot.pipeline import (
    payment_extract_to_ocr_result,
    process_payment_screenshot,
)
from app.services.storage import resolve_image_path, save_transaction_image
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
    image_path = save_transaction_image(user.id, image_bytes, file.filename)
    ocr: OcrResult = await process_receipt(db, user.id, image_bytes, is_low_quality, raw_text_hint)
    classification: ClassificationResult = await classify_transaction(db, user.id, ocr)

    tx_id = None
    if auto_save and ocr.total_amount:
        tx = await create_transaction_from_ocr(
            db, user.id, ocr, classification, image_path=image_path
        )
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
    image_path = save_transaction_image(user.id, image_bytes, file.filename)
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
            image_path=image_path,
        )
        tx_id = tx.id

    return ProcessPaymentScreenshotResponse(
        extraction=extraction,
        classification=classification,
        transaction_id=tx_id,
    )


@router.post("/process-image", response_model=ProcessImageResponse)
async def process_image_endpoint(
    file: UploadFile = File(...),
    is_low_quality: bool = Form(False),
    auto_save: bool = Form(True),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Single capture entry: VietOCR → auto-detect kind → receipt or payment pipeline."""
    import asyncio

    image_bytes = await file.read()
    image_path = save_transaction_image(user.id, image_bytes, file.filename)

    raw_text = ""
    if vietocr_available():
        raw_text = await asyncio.to_thread(run_vietocr_sync, image_bytes) or ""

    kind = await detect_document_kind(raw_text)

    if kind == "payment_screenshot":
        extraction = await process_payment_screenshot(
            image_bytes, raw_text_hint=raw_text or None
        )
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
                image_path=image_path,
            )
            tx_id = tx.id
            await check_budget_alerts(db, user.id)
        return ProcessImageResponse(
            kind=kind,
            transaction_id=tx_id,
            extraction=extraction,
            classification=classification,
        )

    ocr: OcrResult = await process_receipt(
        db,
        user.id,
        image_bytes,
        is_low_quality,
        raw_text or None,
    )
    classification = await classify_transaction(db, user.id, ocr)
    tx_id = None
    if auto_save and ocr.total_amount:
        tx = await create_transaction_from_ocr(
            db, user.id, ocr, classification, image_path=image_path
        )
        tx_id = tx.id
        await check_budget_alerts(db, user.id)
    return ProcessImageResponse(
        kind="receipt",
        transaction_id=tx_id,
        ocr=ocr,
        classification=classification,
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


@router.get("/{transaction_id}", response_model=TransactionOut)
async def get_transaction(
    transaction_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(Transaction).where(Transaction.id == transaction_id, Transaction.user_id == user.id)
    )
    tx = result.scalar_one_or_none()
    if not tx:
        raise HTTPException(status_code=404, detail="Transaction not found")
    return await to_transaction_out(db, tx)


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

    category_changed = body.category_id is not None and body.category_id != tx.category_id

    if body.merchant_name is not None:
        tx.merchant_name = body.merchant_name
    if body.amount is not None:
        tx.amount = body.amount
    if body.transaction_date is not None:
        tx.transaction_date = body.transaction_date
    if body.category_id is not None:
        tx.category_id = body.category_id
    if body.transaction_type is not None:
        tx.transaction_type = (
            TransactionType.income
            if body.transaction_type == "income"
            else TransactionType.expense
        )

    if category_changed and tx.category_id is not None:
        from app.services.classify.pipeline import store_embedding

        await store_embedding(
            db,
            user.id,
            tx.id,
            tx.merchant_name,
            tx.items,
            tx.amount,
            tx.transaction_date,
            category_id=tx.category_id,
        )
        await update_merchant_graph(db, tx.merchant_name, tx.category_id, user.id)
        if tx.merchant_name:
            await add_merchant_reference(db, user.id, tx.merchant_name)

    await db.flush()
    await check_budget_alerts(db, user.id)
    return await to_transaction_out(db, tx)


@router.get("/{transaction_id}/image")
async def get_transaction_image(
    transaction_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(Transaction).where(Transaction.id == transaction_id, Transaction.user_id == user.id)
    )
    tx = result.scalar_one_or_none()
    if not tx or not tx.image_path:
        raise HTTPException(status_code=404, detail="Image not found")
    path = resolve_image_path(tx.image_path)
    if path is None:
        raise HTTPException(status_code=404, detail="Image not found")
    media = "image/jpeg"
    if path.suffix.lower() == ".png":
        media = "image/png"
    elif path.suffix.lower() == ".webp":
        media = "image/webp"
    return FileResponse(path, media_type=media)


@router.delete("/{transaction_id}", status_code=204)
async def delete_transaction(
    transaction_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(Transaction).where(Transaction.id == transaction_id, Transaction.user_id == user.id)
    )
    tx = result.scalar_one_or_none()
    if not tx:
        raise HTTPException(status_code=404, detail="Transaction not found")

    emb = await db.execute(
        select(TransactionEmbedding).where(TransactionEmbedding.transaction_id == transaction_id)
    )
    embedding = emb.scalar_one_or_none()
    if embedding:
        await db.delete(embedding)

    await db.delete(tx)
    await db.flush()
    await check_budget_alerts(db, user.id)


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
