"""Subscription detection — recurring (merchant, amount, ~30 day cycle)."""

import logging
from collections import defaultdict
from datetime import date, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Alert, DetectedSubscription, Transaction
from app.services.ocr.reference_correction import normalize_vietnamese

logger = logging.getLogger(__name__)

AMOUNT_TOLERANCE = 0.05  # ±5%
MIN_INTERVAL_DAYS = 25
MAX_INTERVAL_DAYS = 35
MIN_OCCURRENCES = 2


async def detect_subscriptions(db: AsyncSession, user_id: int) -> list[DetectedSubscription]:
    """Detect active subscriptions from transaction history."""
    cutoff = date.today() - timedelta(days=365)
    result = await db.execute(
        select(Transaction)
        .where(
            Transaction.user_id == user_id,
            Transaction.merchant_name.isnot(None),
            Transaction.transaction_date >= cutoff,
        )
        .order_by(Transaction.transaction_date)
    )
    txs = result.scalars().all()

    # Group by normalized merchant
    groups: dict[str, list[Transaction]] = defaultdict(list)
    for tx in txs:
        norm = normalize_vietnamese(tx.merchant_name or "")
        if norm:
            groups[norm].append(tx)

    detected: list[DetectedSubscription] = []

    for norm, group_txs in groups.items():
        sub = _find_recurring_pattern(norm, group_txs)
        if not sub:
            continue

        existing = await db.execute(
            select(DetectedSubscription).where(
                DetectedSubscription.user_id == user_id,
                DetectedSubscription.normalized_merchant == norm,
                DetectedSubscription.is_dismissed.is_(False),
            )
        )
        record = existing.scalar_one_or_none()
        if record:
            record.amount = sub["amount"]
            record.merchant_name = sub["merchant_name"]
            record.cycle_days = sub["cycle_days"]
            record.occurrence_count = sub["occurrence_count"]
            record.last_charge_date = sub["last_charge_date"]
            record.next_expected_date = sub["next_expected_date"]
            record.monthly_cost = sub["monthly_cost"]
        else:
            record = DetectedSubscription(
                user_id=user_id,
                merchant_name=sub["merchant_name"],
                normalized_merchant=norm,
                amount=sub["amount"],
                cycle_days=sub["cycle_days"],
                occurrence_count=sub["occurrence_count"],
                last_charge_date=sub["last_charge_date"],
                next_expected_date=sub["next_expected_date"],
                monthly_cost=sub["monthly_cost"],
            )
            db.add(record)
            db.add(
                Alert(
                    user_id=user_id,
                    type="subscription_detected",
                    payload={
                        "merchant": sub["merchant_name"],
                        "amount": sub["amount"],
                        "monthly_cost": sub["monthly_cost"],
                        "cycle_days": sub["cycle_days"],
                    },
                )
            )
        detected.append(record)

    return detected


def _find_recurring_pattern(norm: str, txs: list[Transaction]) -> dict | None:
    if len(txs) < MIN_OCCURRENCES:
        return None

    # Cluster by similar amount
    amount_clusters: dict[int, list[Transaction]] = defaultdict(list)
    for tx in txs:
        bucket = round(tx.amount / 1000)  # group within ~1000 VND
        amount_clusters[bucket].append(tx)

    best_pattern = None
    best_score = 0

    for cluster_txs in amount_clusters.values():
        if len(cluster_txs) < MIN_OCCURRENCES:
            continue

        avg_amount = sum(t.amount for t in cluster_txs) / len(cluster_txs)
        filtered = [t for t in cluster_txs if abs(t.amount - avg_amount) / avg_amount <= AMOUNT_TOLERANCE]
        if len(filtered) < MIN_OCCURRENCES:
            continue

        filtered.sort(key=lambda t: t.transaction_date)
        intervals = [
            (filtered[i].transaction_date - filtered[i - 1].transaction_date).days
            for i in range(1, len(filtered))
        ]
        if not intervals:
            continue

        avg_interval = sum(intervals) / len(intervals)
        if not (MIN_INTERVAL_DAYS <= avg_interval <= MAX_INTERVAL_DAYS):
            # Also accept ~7 (weekly) or ~365 (yearly) with wider tolerance
            if not (6 <= avg_interval <= 8) and not (350 <= avg_interval <= 380):
                continue

        # Score: more occurrences + consistent intervals
        interval_variance = sum((d - avg_interval) ** 2 for d in intervals) / len(intervals)
        score = len(filtered) * 10 - interval_variance
        if score > best_score:
            best_score = score
            last_date = filtered[-1].transaction_date
            cycle = round(avg_interval)
            monthly = avg_amount * (30 / cycle) if cycle > 0 else avg_amount
            best_pattern = {
                "merchant_name": filtered[-1].merchant_name or norm,
                "amount": round(avg_amount, 0),
                "cycle_days": cycle,
                "occurrence_count": len(filtered),
                "last_charge_date": last_date,
                "next_expected_date": last_date + timedelta(days=cycle),
                "monthly_cost": round(monthly, 0),
            }

    return best_pattern


async def get_user_subscriptions(db: AsyncSession, user_id: int) -> list[DetectedSubscription]:
    result = await db.execute(
        select(DetectedSubscription)
        .where(DetectedSubscription.user_id == user_id, DetectedSubscription.is_dismissed.is_(False))
        .order_by(DetectedSubscription.monthly_cost.desc())
    )
    return list(result.scalars().all())
