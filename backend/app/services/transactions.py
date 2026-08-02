from datetime import date

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Category, Merchant, MerchantReference, Transaction, TransactionSource, TransactionType
from app.schemas import (
    ClassificationResult,
    ItemCategoryOut,
    OcrResult,
    PaymentScreenshotExtract,
    TransactionCreate,
    TransactionOut,
)
from app.services.classify.pipeline import store_embedding
from app.services.ocr.reference_correction import normalize_vietnamese


def _parse_transaction_type(raw: str | None) -> TransactionType:
    if raw == "income":
        return TransactionType.income
    return TransactionType.expense


def unique_item_categories(items: list | dict | None) -> list[ItemCategoryOut]:
    if not items or not isinstance(items, list):
        return []
    seen: set[str] = set()
    out: list[ItemCategoryOut] = []
    for entry in items:
        if not isinstance(entry, dict):
            continue
        name = (entry.get("category_name") or "").strip()
        if not name or name in seen:
            continue
        seen.add(name)
        cid = entry.get("category_id")
        out.append(ItemCategoryOut(id=cid if isinstance(cid, int) else None, name=name))
    return out


async def save_transaction(db: AsyncSession, user_id: int, body: TransactionCreate) -> Transaction:
    tx = Transaction(
        user_id=user_id,
        merchant_name=body.merchant_name,
        amount=body.amount,
        items=[i.model_dump() for i in body.items] if body.items else None,
        category_id=body.category_id,
        transaction_type=_parse_transaction_type(body.transaction_type),
        image_path=body.image_path,
        source=TransactionSource(body.source),
        confidence=body.confidence,
        ocr_track_used=body.ocr_track_used,
        transaction_date=body.transaction_date or date.today(),
        classification_reason=body.classification_reason,
    )
    db.add(tx)
    await db.flush()

    if body.category_id and tx.transaction_type == TransactionType.expense:
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

    item_cats = unique_item_categories(tx.items)
    # Receipt txs: categories = unique from items; fall back to primary category
    if not item_cats and category_name:
        item_cats = [ItemCategoryOut(id=tx.category_id, name=category_name)]

    tx_type = tx.transaction_type.value if hasattr(tx.transaction_type, "value") else (tx.transaction_type or "expense")

    return TransactionOut(
        id=tx.id,
        merchant_name=tx.merchant_name,
        amount=tx.amount,
        items=tx.items,
        category_id=tx.category_id,
        category_name=category_name,
        item_categories=item_cats,
        transaction_type=tx_type,
        has_image=bool(tx.image_path),
        source=tx.source.value,
        confidence=tx.confidence,
        ocr_track_used=tx.ocr_track_used,
        transaction_date=tx.transaction_date,
        created_at=tx.created_at,
        classification_reason=tx.classification_reason,
    )


async def create_transaction_from_ocr(
    db: AsyncSession,
    user_id: int,
    ocr: OcrResult,
    classification: ClassificationResult,
    image_path: str | None = None,
) -> Transaction:
    body = TransactionCreate(
        merchant_name=ocr.merchant,
        amount=ocr.total_amount or 0,
        items=ocr.items,
        category_id=classification.category_id,
        transaction_type="expense",
        image_path=image_path,
        source="ocr",
        transaction_date=ocr.transaction_date,
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
    image_path: str | None = None,
) -> Transaction:
    reason_parts = [classification.reason] if classification.reason else []
    if extract.payment_source:
        reason_parts.append(f"Nguồn ảnh: {extract.payment_source}")
    if extract.description:
        reason_parts.append(f"Nội dung: {extract.description}")
    if extract.reference_code:
        reason_parts.append(f"Mã GD: {extract.reference_code}")

    body = TransactionCreate(
        merchant_name=extract.merchant or extract.payment_source,
        amount=extract.total_amount or 0,
        items=None,
        category_id=classification.category_id,
        transaction_type="expense",
        image_path=image_path,
        source="ocr",
        transaction_date=extract.transaction_date,
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
