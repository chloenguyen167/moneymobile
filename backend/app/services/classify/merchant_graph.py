"""Global Merchant-Category Graph — cold-start + weekly community aggregation (Phase 3)."""

import logging
from collections import Counter

from rapidfuzz import fuzz
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Category, Merchant, Transaction
from app.schemas import ClassificationResult
from app.services.ocr.reference_correction import normalize_vietnamese

logger = logging.getLogger(__name__)

FUZZY_THRESHOLD = 82


async def lookup_merchant_graph(db: AsyncSession, merchant_name: str) -> ClassificationResult | None:
    """Exact match first, then fuzzy match against global graph."""
    normalized = normalize_vietnamese(merchant_name)

    exact = await _exact_lookup(db, normalized)
    if exact:
        return exact

    return await _fuzzy_lookup(db, normalized, merchant_name)


async def _exact_lookup(db: AsyncSession, normalized: str) -> ClassificationResult | None:
    result = await db.execute(
        select(Merchant, Category)
        .join(Category, Merchant.default_category_id == Category.id)
        .where(Merchant.normalized_name == normalized)
    )
    row = result.first()
    if not row:
        return None
    merchant, category = row
    confidence = min(0.92, 0.75 + merchant.occurrence_count * 0.01)
    return ClassificationResult(
        category_id=category.id,
        category_name=category.name,
        confidence=confidence,
        track_used="global_graph",
        reason=f"Cửa hàng phổ biến ({merchant.occurrence_count} lần): {merchant.name}",
        needs_confirmation=confidence < 0.85,
    )


async def _fuzzy_lookup(db: AsyncSession, normalized: str, original_name: str) -> ClassificationResult | None:
    result = await db.execute(
        select(Merchant, Category)
        .join(Category, Merchant.default_category_id == Category.id)
        .where(Merchant.occurrence_count >= 2)
        .limit(500)
    )
    best_score = 0.0
    best_row = None
    for merchant, category in result.all():
        score = fuzz.token_sort_ratio(normalized, merchant.normalized_name)
        if score > best_score:
            best_score = score
            best_row = (merchant, category)

    if not best_row or best_score < FUZZY_THRESHOLD:
        return None

    merchant, category = best_row
    return ClassificationResult(
        category_id=category.id,
        category_name=category.name,
        confidence=best_score / 100 * 0.85,
        track_used="global_graph_fuzzy",
        reason=f"Gần giống '{merchant.name}' ({best_score:.0f}% khớp)",
        needs_confirmation=True,
    )


async def rebuild_merchant_graph(db: AsyncSession) -> int:
    """
    Weekly job: aggregate confirmed transactions across all users (anonymous).
    Updates Merchant.default_category_id by majority vote.
    """
    result = await db.execute(
        select(
            Transaction.merchant_name,
            Transaction.category_id,
            func.count(Transaction.id).label("cnt"),
        )
        .where(
            Transaction.merchant_name.isnot(None),
            Transaction.category_id.isnot(None),
        )
        .group_by(Transaction.merchant_name, Transaction.category_id)
    )
    rows = result.all()

    # Group by normalized merchant → category votes
    merchant_votes: dict[str, Counter] = {}
    merchant_display: dict[str, str] = {}
    for row in rows:
        if not row.merchant_name or not row.category_id:
            continue
        norm = normalize_vietnamese(row.merchant_name)
        merchant_votes.setdefault(norm, Counter())[row.category_id] += row.cnt
        if norm not in merchant_display or len(row.merchant_name) > len(merchant_display[norm]):
            merchant_display[norm] = row.merchant_name

    updated = 0
    for norm, votes in merchant_votes.items():
        if not votes:
            continue
        best_cat_id, total = votes.most_common(1)[0]
        total_all = sum(votes.values())

        existing = await db.execute(select(Merchant).where(Merchant.normalized_name == norm))
        merchant = existing.scalar_one_or_none()
        if merchant:
            merchant.default_category_id = best_cat_id
            merchant.occurrence_count = total_all
            merchant.name = merchant_display.get(norm, merchant.name)
        else:
            db.add(
                Merchant(
                    name=merchant_display.get(norm, norm),
                    normalized_name=norm,
                    default_category_id=best_cat_id,
                    occurrence_count=total_all,
                )
            )
        updated += 1

    logger.info("Merchant graph rebuilt: %d merchants", updated)

    from app.services.classify.community_graph import apply_community_signals_to_graph
    community_updated = await apply_community_signals_to_graph(db)
    logger.info("Community signals applied: %d merchants", community_updated)

    return updated + community_updated
