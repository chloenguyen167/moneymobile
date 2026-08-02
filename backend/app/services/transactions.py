from datetime import date, datetime, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Category, Merchant, MerchantReference, Transaction, TransactionSource
from app.schemas import (
    ClassificationResult,
    OcrResult,
    PaymentScreenshotExtract,
    TransactionCreate,
    TransactionOut,
)
from app.services.classify.pipeline import store_embedding
from app.services.ocr.reference_correction import normalize_vietnamese


async def save_transaction(db: AsyncSession, user_id: int, body: TransactionCreate) -> Transaction:
    tx_date = body.transaction_date or (
        body.transaction_time.date() if body.transaction_time else date.today()
    )
    tx = Transaction(
        user_id=user_id,
        merchant_name=body.merchant_name,
        description=body.description,
        amount=body.amount,
        items=[i.model_dump() for i in body.items] if body.items else None,
        category_id=body.category_id,
        source=TransactionSource(body.source),
        confidence=body.confidence,
        ocr_track_used=body.ocr_track_used,
        transaction_date=tx_date,
        transaction_time=body.transaction_time,
        classification_reason=body.classification_reason,
    )
    db.add(tx)
    await db.flush()

    if body.category_id:
        await store_embedding(
            db,
            user_id,
            tx.id,
            body.merchant_name,
            tx.items,
            body.amount,
            tx.transaction_date,
            category_id=body.category_id,
        )

    return tx


async def to_transaction_out(db: AsyncSession, tx: Transaction) -> TransactionOut:
    category_name = None
    if tx.category_id:
        result = await db.execute(select(Category).where(Category.id == tx.category_id))
        cat = result.scalar_one_or_none()
        category_name = cat.name if cat else None

    return TransactionOut(
        id=tx.id,
        merchant_name=tx.merchant_name,
        description=tx.description,
        amount=tx.amount,
        items=tx.items,
        category_id=tx.category_id,
        category_name=category_name,
        source=tx.source.value,
        confidence=tx.confidence,
        ocr_track_used=tx.ocr_track_used,
        transaction_date=tx.transaction_date,
        transaction_time=tx.transaction_time,
        created_at=tx.created_at,
        classification_reason=tx.classification_reason,
    )


async def create_transaction_from_ocr(
    db: AsyncSession, user_id: int, ocr: OcrResult, classification: ClassificationResult
) -> Transaction:
    captured_at = datetime.now(timezone.utc)
    body = TransactionCreate(
        merchant_name=ocr.merchant,
        amount=ocr.total_amount or 0,
        items=ocr.items,
        category_id=classification.category_id,
        source="ocr",
        transaction_date=ocr.transaction_date,
        transaction_time=captured_at,
        ocr_track_used=ocr.ocr_track_used,
        confidence=classification.confidence,
        classification_reason=classification.reason,
    )
    return await save_transaction(db, user_id, body)


async def create_transaction_from_payment_screenshot(
    db: AsyncSession,
    user_id: int,
    extract: PaymentScreenshotExtract,
    classification: ClassificationResult,
) -> Transaction:
    captured_at = datetime.now(timezone.utc)
    reason_parts = [classification.reason] if classification.reason else []
    if extract.payment_source:
        reason_parts.append(f"Nguồn ảnh: {extract.payment_source}")
    if extract.description:
        reason_parts.append(f"Nội dung: {extract.description}")
    if extract.reference_code:
        reason_parts.append(f"Mã GD: {extract.reference_code}")

    body = TransactionCreate(
        merchant_name=extract.merchant or extract.payment_source,
        description=extract.description,
        amount=extract.total_amount or 0,
        items=None,
        category_id=classification.category_id,
        source="ocr",
        transaction_date=extract.transaction_date,
        transaction_time=captured_at,
        ocr_track_used=extract.ocr_track_used,
        confidence=classification.confidence,
        classification_reason=" | ".join(reason_parts) if reason_parts else None,
    )
    return await save_transaction(db, user_id, body)


async def update_merchant_graph(db: AsyncSession, merchant_name: str | None, category_id: int, user_id: int | None = None):
    if not merchant_name:
        return
    normalized = normalize_vietnamese(merchant_name)
    result = await db.execute(select(Merchant).where(Merchant.normalized_name == normalized))
    merchant = result.scalar_one_or_none()
    if merchant:
        merchant.default_category_id = category_id
        merchant.occurrence_count += 1
    else:
        db.add(
            Merchant(
                name=merchant_name,
                normalized_name=normalized,
                default_category_id=category_id,
            )
        )

    if user_id:
        from app.services.classify.community_graph import record_community_signal
        await record_community_signal(db, merchant_name, category_id, user_id)


async def add_merchant_reference(db: AsyncSession, user_id: int, merchant_name: str):
    normalized = normalize_vietnamese(merchant_name)
    result = await db.execute(
        select(MerchantReference).where(
            MerchantReference.user_id == user_id,
            MerchantReference.normalized_name == normalized,
        )
    )
    if not result.scalar_one_or_none():
        db.add(
            MerchantReference(
                user_id=user_id,
                merchant_name=merchant_name,
                normalized_name=normalized,
            )
        )
