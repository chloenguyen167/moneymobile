"""PVC-Class cascade classification — Phase 2: top-k kNN + merchant vector store."""

from collections import Counter
from datetime import date

import numpy as np
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models import Category, PersonalMerchantEmbedding, TransactionEmbedding
from app.schemas import CategoryBreakdown, ClassificationResult, OcrResult, ReceiptItem
from app.services.classify.embedding import build_feature_vector
from app.services.ocr.reference_correction import normalize_vietnamese

DEFAULT_CATEGORIES = [
    ("Ăn uống", "restaurant"),
    ("Mua sắm", "shopping_bag"),
    ("Chăm sóc cá nhân", "self_improvement"),
    ("Di chuyển", "directions_car"),
    ("Giải trí", "movie"),
    ("Hóa đơn & Tiện ích", "receipt"),
    ("Sức khỏe", "health_and_safety"),
    ("Giáo dục", "school"),
    ("Khác", "category"),
]


async def seed_default_categories(db: AsyncSession) -> None:
    result = await db.execute(select(Category).where(Category.user_id.is_(None)))
    existing = {category.name for category in result.scalars().all()}
    for name, icon in DEFAULT_CATEGORIES:
        if name in existing:
            continue
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

    if ocr.items:
        ocr.items = await classify_receipt_items(db, user_id, ocr)
        item_result = await _aggregate_item_categories(db, ocr.items)
        if item_result:
            return await _finish(item_result)

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

ITEM_RULES: dict[str, list[str]] = {
    "Ăn uống": [
        "tao", "le", "cam", "quyt", "chuoi", "nho", "xoai", "dua hau", "trai cay",
        "rau", "cu", "qua", "cai", "cai thia", "cai be", "cai ngot", "xalach", "rau muong",
        "thit", "thit heo", "thit bo", "thit ga", "heo xay", "ga xay", "ca", "tom", "muc", "hai san",
        "trung", "gao", "gao te", "mi", "mi goi", "mi tom", "mi an lien", "hao hao", "omachi", "reeva",
        "pho", "bun", "hu tieu", "banh mi", "banh", "com",
        "sua", "sua tuoi", "sua chua", "sua bot", "sua bau", "pho mai", "bot ngot", "nuoc mam", "dau an", "gia vi",
        "nuoc", "pepsi", "coca", "coffee", "cafe", "tra", "tra sua", "sinh to",
        "vissan", "cp", "meatdeli", "vinamilk", "milac",
    ],
    "Mua sắm": [
        "nuoc rua chen", "nuoc giat", "giay ve sinh", "ta bim", "moc ao", "hop dung do", "do gia dung",
        "quan ao", "tui rac", "nuoc lau san", "bot giat", "nuoc xa vai", "downy",
    ],
    "Chăm sóc cá nhân": [
        "dau goi", "sua tam", "xa phong", "ban chai", "kem danh rang", "chi nha khoa",
        "my pham", "son", "kem duong", "tam bong", "rua mat", "tay trang", "lan khu mui",
        "dau xa", "sua rua mat", "bong tay trang", "khan uot", "chong nang", "kem chong nang", "dau nang",
    ],
    "Di chuyển": ["xang", "ve xe", "phi gui xe", "grab", "taxi", "tram thu phi"],
    "Giải trí": ["ve phim", "bap rang", "netflix", "spotify", "game", "karaoke"],
    "Hóa đơn & Tiện ích": ["tien dien", "tien nuoc", "wifi", "internet", "cuoc dt", "gas"],
    "Sức khỏe": ["thuoc", "vitamin", "khau trang", "nhiet ke", "dau gio", "thuoc boi"],
    "Giáo dục": ["sach", "but", "vo", "hoc phi", "tap", "balo"],
}


def _tokenize_normalized(text: str) -> set[str]:
    return {token for token in text.split() if token}


def _score_item_category(text_blob: str, tokens: set[str], keywords: list[str]) -> tuple[int, list[str]]:
    score = 0
    matched: list[str] = []
    for keyword in keywords:
        keyword_norm = normalize_vietnamese(keyword)
        if not keyword_norm:
            continue
        if " " in keyword_norm:
            if keyword_norm in text_blob:
                score += 3
                matched.append(keyword)
            continue
        if keyword_norm in tokens:
            score += 2
            matched.append(keyword)
    return score, matched


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


async def classify_receipt_items(db: AsyncSession, user_id: int, ocr: OcrResult) -> list[ReceiptItem]:
    from app.services.classify.taxonomy import llm_classify_receipt_items

    await seed_default_categories(db)
    categories_result = await db.execute(select(Category).where(Category.user_id.is_(None)))
    categories = {c.name: c for c in categories_result.scalars().all()}
    classified: list[ReceiptItem] = []

    merchant_norm = normalize_vietnamese(ocr.merchant or "")
    for item in ocr.items:
        item_text = item.canonical_name or item.normalized_name or normalize_vietnamese(item.name)
        brand_norm = normalize_vietnamese(item.brand or "")
        text_blob = " ".join(part for part in [merchant_norm, item_text, brand_norm] if part).strip()
        tokens = _tokenize_normalized(text_blob)

        matched_name = "Khác"
        confidence = 0.55
        reason = "Không đủ tín hiệu rõ, gán nhóm Khác"
        best_score = 0
        best_matches: list[str] = []

        for category_name, keywords in ITEM_RULES.items():
            score, matches = _score_item_category(text_blob, tokens, keywords)
            if score > best_score:
                matched_name = category_name
                best_score = score
                best_matches = matches

        if best_score > 0:
            confidence = min(0.92, 0.62 + best_score * 0.08)
            reason = f"Khớp từ khóa: {', '.join(best_matches[:3])}"

        category = categories.get(matched_name)
        classified.append(
            ReceiptItem(
                name=item.name,
                price=item.price,
                qty=item.qty,
                raw_name=item.raw_name,
                normalized_name=item.normalized_name,
                canonical_name=item.canonical_name,
                brand=item.brand,
                size_value=item.size_value,
                size_unit=item.size_unit,
                removed_tokens=item.removed_tokens,
                category_id=category.id if category else None,
                category_name=matched_name if category else None,
                classification_confidence=confidence,
                classification_reason=reason,
            )
        )

    llm_candidates = [
        (index, item)
        for index, item in enumerate(classified)
        if (item.category_name == "Khác" or (item.classification_confidence or 0.0) < settings.classify_item_llm_confidence_threshold)
    ]
    if llm_candidates and (settings.openai_api_key or settings.gemini_api_key):
        batch_size = max(1, settings.classify_item_llm_max_items)
        for start in range(0, len(llm_candidates), batch_size):
            batch = llm_candidates[start : start + batch_size]
            llm_result = await llm_classify_receipt_items(
                db,
                user_id,
                ocr.merchant,
                [item for _, item in batch],
            )
            for local_index, (item_index, item) in enumerate(batch):
                payload = llm_result.get(local_index)
                if not payload:
                    continue
                category = categories.get(payload["category"])
                if not category:
                    continue
                classified[item_index] = item.model_copy(
                    update={
                        "category_id": category.id,
                        "category_name": category.name,
                        "classification_confidence": max(item.classification_confidence or 0.0, payload["confidence"]),
                        "classification_reason": payload["reason"],
                    }
                )

    return classified


async def _aggregate_item_categories(db: AsyncSession, items: list[ReceiptItem]) -> ClassificationResult | None:
    weighted: Counter[int] = Counter()
    names: dict[int, str] = {}
    item_counts: Counter[int] = Counter()

    for item in items:
        if item.category_id is None or item.category_name is None:
            continue
        weight = max(item.price, 1.0) * max(item.qty, 1)
        weighted[item.category_id] += weight
        names[item.category_id] = item.category_name
        item_counts[item.category_id] += max(item.qty, 1)

    if not weighted:
        return None

    breakdown = [
        CategoryBreakdown(
            category_id=category_id,
            category_name=names[category_id],
            total_amount=round(total_amount, 2),
            item_count=item_counts[category_id],
        )
        for category_id, total_amount in weighted.most_common()
    ]
    best_cat_id, best_weight = weighted.most_common(1)[0]
    total = sum(weighted.values())
    confidence = min(0.95, max(0.6, best_weight / total))
    return ClassificationResult(
        category_id=best_cat_id,
        category_name=names[best_cat_id],
        confidence=round(confidence, 3),
        track_used="item_aggregate",
        reason=f"Suy ra từ phân loại {len(items)} sản phẩm",
        needs_confirmation=True,
        category_breakdown=breakdown,
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
