"""PVC-Class cascade classification — Phase 2: top-k kNN + merchant vector store."""

from collections import Counter
from datetime import date

import numpy as np
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models import Category, PersonalMerchantEmbedding, TransactionEmbedding
from app.schemas import ClassificationResult, OcrResult
from app.services.classify.embedding import build_feature_vector
from app.services.ocr.reference_correction import normalize_vietnamese

DEFAULT_CATEGORIES = [
    ("Ăn uống", "restaurant"),
    ("Mua sắm", "shopping_bag"),
    ("Di chuyển", "directions_car"),
    ("Giải trí", "movie"),
    ("Hóa đơn & Tiện ích", "receipt"),
    ("Sức khỏe", "health_and_safety"),
    ("Giáo dục", "school"),
    ("Khác", "category"),
]


async def seed_default_categories(db: AsyncSession) -> None:
    result = await db.execute(select(Category).where(Category.user_id.is_(None)))
    if result.scalars().first():
        return
    for name, icon in DEFAULT_CATEGORIES:
        db.add(Category(name=name, icon=icon, is_user_defined=False, user_id=None))
    await db.flush()


async def classify_transaction(
    db: AsyncSession,
    user_id: int,
    ocr: OcrResult,
    amount: float | None = None,
    transaction_date: date | None = None,
) -> ClassificationResult:
    from app.services.metrics.pipeline import record_classify_track

    async def _finish(result: ClassificationResult) -> ClassificationResult:
        await record_classify_track(db, result.track_used)
        return result

    await seed_default_categories(db)

    amount = amount or ocr.total_amount or 0
    tx_date = transaction_date or ocr.transaction_date or date.today()
    feature_vec = build_feature_vector(ocr.merchant, [i.model_dump() for i in ocr.items], amount, tx_date)

    if ocr.merchant:
        merchant_match = await _merchant_vector_lookup(db, user_id, ocr.merchant)
        if merchant_match:
            return await _finish(merchant_match)

    knn = await _knn_classify(db, user_id, feature_vec)
    if knn and knn.confidence >= settings.classify_knn_threshold:
        return await _finish(knn)

    if ocr.merchant:
        from app.services.classify.merchant_graph import lookup_merchant_graph

        graph = await lookup_merchant_graph(db, ocr.merchant)
        if graph:
            return await _finish(graph)

    result = await _smart_classify(db, user_id, ocr, amount)
    return await _finish(result)


async def _merchant_vector_lookup(
    db: AsyncSession, user_id: int, merchant_name: str
) -> ClassificationResult | None:
    normalized = normalize_vietnamese(merchant_name)
    result = await db.execute(
        select(PersonalMerchantEmbedding, Category)
        .join(Category, PersonalMerchantEmbedding.category_id == Category.id)
        .where(
            PersonalMerchantEmbedding.user_id == user_id,
            PersonalMerchantEmbedding.normalized_name == normalized,
        )
    )
    row = result.first()
    if not row:
        return None

    emb, category = row
    return ClassificationResult(
        category_id=category.id,
        category_name=category.name,
        confidence=min(0.95, 0.85 + emb.confirm_count * 0.02),
        track_used="merchant_vector",
        reason=f"Bạn đã phân loại '{emb.merchant_name}' trước đó",
        needs_confirmation=False,
    )


async def _knn_classify(db: AsyncSession, user_id: int, vector: list[float]) -> ClassificationResult | None:
    vec_str = "[" + ",".join(str(v) for v in vector) + "]"
    k = settings.classify_knn_top_k
    # CAST(... AS vector) — avoid :vec::vector which breaks SQLAlchemy bind parsing
    sql = text("""
        SELECT t.category_id, c.name,
               1 - (te.embedding <=> CAST(:vec AS vector)) AS similarity
        FROM transaction_embeddings te
        JOIN transactions t ON t.id = te.transaction_id
        JOIN categories c ON c.id = t.category_id
        WHERE te.user_id = :user_id AND t.category_id IS NOT NULL
        ORDER BY te.embedding <=> CAST(:vec AS vector)
        LIMIT :k
    """)
    try:
        result = await db.execute(sql, {"vec": vec_str, "user_id": user_id, "k": k})
        rows = result.all()
    except Exception:
        await db.rollback()
        return None

    if not rows:
        return None

    # Weighted vote: sum similarity scores per category
    votes: Counter[int] = Counter()
    names: dict[int, str] = {}
    for row in rows:
        if row.similarity < settings.classify_knn_min_similarity:
            continue
        votes[row.category_id] += float(row.similarity)
        names[row.category_id] = row.name

    if not votes:
        return None

    best_cat_id, score = votes.most_common(1)[0]
    max_possible = sum(votes.values())
    confidence = score / max_possible if max_possible else 0

    if confidence < settings.classify_knn_threshold:
        return None

    return ClassificationResult(
        category_id=best_cat_id,
        category_name=names[best_cat_id],
        confidence=round(confidence, 3),
        track_used="vector_knn",
        reason=f"Khớp {len(rows)} giao dịch tương tự (top-{k} vote)",
        needs_confirmation=False,
    )


MERCHANT_RULES: list[tuple[list[str], str]] = [
    (["phuc long", "highlands", "starbucks", "trasua", "tra sua", "coffee", "cafe", "com", "banh mi", "food"], "Ăn uống"),
    (["circle k", "familymart", "ministop", "winmart", "coopmart", "big c", "aeon", "lotte"], "Mua sắm"),
    (["grab", "be ", "gojek", "xang", "petrolimex", "shell"], "Di chuyển"),
    (["netflix", "spotify", "cgv", "game"], "Giải trí"),
    (["dien luc", "evn", "nuoc", "internet", "fpt", "viettel"], "Hóa đơn & Tiện ích"),
    (["pharmacy", "nhathuoc", "benh vien", "pkdk"], "Sức khỏe"),
]


async def _smart_classify(db: AsyncSession, user_id: int, ocr: OcrResult, amount: float) -> ClassificationResult:
    from app.services.classify.taxonomy import llm_classify_with_taxonomy

    if settings.openai_api_key or settings.gemini_api_key:
        llm_result = await llm_classify_with_taxonomy(db, user_id, ocr, amount)
        if llm_result:
            return llm_result

    text_blob = normalize_vietnamese(
        " ".join(filter(None, [ocr.merchant, " ".join(i.name for i in ocr.items)]))
    )

    category_name = "Khác"
    for keywords, cat in MERCHANT_RULES:
        if any(kw in text_blob for kw in keywords):
            category_name = cat
            break

    cat_result = await db.execute(
        select(Category).where(Category.name == category_name, Category.user_id.is_(None))
    )
    category = cat_result.scalar_one_or_none()

    return ClassificationResult(
        category_id=category.id if category else None,
        category_name=category_name,
        confidence=0.65,
        track_used="smart",
        reason="Phân loại tự động dựa trên merchant/món hàng",
        needs_confirmation=True,
    )


async def store_embedding(
    db: AsyncSession,
    user_id: int,
    transaction_id: int,
    merchant: str | None,
    items: list | None,
    amount: float,
    transaction_date: date,
    category_id: int | None = None,
) -> None:
    vec = build_feature_vector(merchant, items, amount, transaction_date)

    # Upsert transaction embedding
    existing = await db.execute(
        select(TransactionEmbedding).where(TransactionEmbedding.transaction_id == transaction_id)
    )
    row = existing.scalar_one_or_none()
    if row:
        row.embedding = vec
    else:
        db.add(TransactionEmbedding(transaction_id=transaction_id, user_id=user_id, embedding=vec))

    # Update personal merchant vector store when category confirmed
    if merchant and category_id:
        await _upsert_merchant_embedding(db, user_id, merchant, category_id, vec)


async def _upsert_merchant_embedding(
    db: AsyncSession,
    user_id: int,
    merchant_name: str,
    category_id: int,
    vec: list[float],
) -> None:
    normalized = normalize_vietnamese(merchant_name)
    result = await db.execute(
        select(PersonalMerchantEmbedding).where(
            PersonalMerchantEmbedding.user_id == user_id,
            PersonalMerchantEmbedding.normalized_name == normalized,
        )
    )
    existing = result.scalar_one_or_none()
    if existing:
        existing.confirm_count += 1
        existing.category_id = category_id
        # Running average of embeddings
        old = np.array(existing.embedding)  # type: ignore
        new = np.array(vec)
        blended = (old * (existing.confirm_count - 1) + new) / existing.confirm_count
        norm = np.linalg.norm(blended)
        existing.embedding = (blended / norm).tolist() if norm > 0 else vec
    else:
        db.add(
            PersonalMerchantEmbedding(
                user_id=user_id,
                merchant_name=merchant_name,
                normalized_name=normalized,
                category_id=category_id,
                embedding=vec,
                confirm_count=1,
            )
        )
