"""Community merchant signals — anonymous aggregated learning (Phase 4)."""

import logging
from datetime import datetime

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models import Category, CommunityMerchantSignal, Merchant, Transaction
from app.services.ocr.reference_correction import normalize_vietnamese

logger = logging.getLogger(__name__)


async def record_community_signal(
    db: AsyncSession,
    merchant_name: str,
    category_id: int,
    user_id: int,
) -> None:
    """
    Record anonymous category confirmation signal.
    Uses distinct user count internally — never exposes individual user data.
    """
    if not merchant_name:
        return

    norm = normalize_vietnamese(merchant_name)
    result = await db.execute(
        select(CommunityMerchantSignal).where(
            CommunityMerchantSignal.normalized_merchant == norm,
            CommunityMerchantSignal.category_id == category_id,
        )
    )
    signal = result.scalar_one_or_none()

    if signal:
        signal.vote_count += 1
        signal.last_updated = datetime.utcnow()
    else:
        signal = CommunityMerchantSignal(
            normalized_merchant=norm,
            display_name=merchant_name,
            category_id=category_id,
            vote_count=1,
            distinct_user_count=1,
        )
        db.add(signal)

    await db.flush()
    await _update_distinct_users(db, norm, category_id)


async def _update_distinct_users(db: AsyncSession, norm: str, category_id: int) -> None:
    """Count distinct users who confirmed this merchant→category mapping."""
    from app.models import Transaction

    # Match transactions where normalized merchant name aligns
    result = await db.execute(select(Transaction.user_id, Transaction.merchant_name, Transaction.category_id))
    distinct_users = set()
    for uid, mname, cid in result.all():
        if cid == category_id and mname and normalize_vietnamese(mname) == norm:
            distinct_users.add(uid)
    distinct = len(distinct_users) or 1

    sig_result = await db.execute(
        select(CommunityMerchantSignal).where(
            CommunityMerchantSignal.normalized_merchant == norm,
            CommunityMerchantSignal.category_id == category_id,
        )
    )
    signal = sig_result.scalar_one_or_none()
    if signal:
        signal.distinct_user_count = distinct


async def apply_community_signals_to_graph(db: AsyncSession) -> int:
    """
    Promote community signals to global Merchant graph when threshold met.
    Requires MIN_DISTINCT_USERS confirmations from different users.
    """
    min_users = settings.community_min_distinct_users
    result = await db.execute(
        select(CommunityMerchantSignal, Category)
        .join(Category, CommunityMerchantSignal.category_id == Category.id)
        .where(CommunityMerchantSignal.distinct_user_count >= min_users)
        .where(CommunityMerchantSignal.vote_count >= min_users * 2)
    )

    updated = 0
    for signal, category in result.all():
        existing = await db.execute(
            select(Merchant).where(Merchant.normalized_name == signal.normalized_merchant)
        )
        merchant = existing.scalar_one_or_none()
        if merchant:
            if merchant.occurrence_count < signal.vote_count:
                merchant.default_category_id = signal.category_id
                merchant.occurrence_count = signal.vote_count
                merchant.name = signal.display_name
                updated += 1
        else:
            db.add(
                Merchant(
                    name=signal.display_name,
                    normalized_name=signal.normalized_merchant,
                    default_category_id=signal.category_id,
                    occurrence_count=signal.vote_count,
                )
            )
            updated += 1

    logger.info("Community signals applied: %d merchants promoted", updated)
    return updated
