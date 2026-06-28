"""Anomaly detection — Z-score on category spending (Phase 4)."""

import logging
from datetime import date, timedelta

import numpy as np
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Alert, Category, Transaction

logger = logging.getLogger(__name__)

ZSCORE_THRESHOLD = 2.5
LOOKBACK_DAYS = 90


async def detect_spending_anomalies(db: AsyncSession, user_id: int) -> list[Alert]:
    """Flag categories where recent spending exceeds historical norm."""
    today = date.today()
    alerts_created = []

    cats_result = await db.execute(
        select(Category.id, Category.name).where(Category.user_id.is_(None))
    )
    categories = cats_result.all()

    for cat_id, cat_name in categories:
        history_start = today - timedelta(days=LOOKBACK_DAYS)
        weekly_totals = await _weekly_totals(db, user_id, cat_id, history_start, today)

        if len(weekly_totals) < 4:
            continue

        mean = float(np.mean(weekly_totals))
        std = float(np.std(weekly_totals))
        if std < 1:
            continue

        current_week = weekly_totals[-1] if weekly_totals else 0
        zscore = (current_week - mean) / std

        if zscore >= ZSCORE_THRESHOLD:
            alert = Alert(
                user_id=user_id,
                type="spending_anomaly",
                payload={
                    "category": cat_name,
                    "current_week_spent": round(current_week, 0),
                    "average_weekly": round(mean, 0),
                    "zscore": round(zscore, 2),
                },
            )
            db.add(alert)
            alerts_created.append(alert)

    return alerts_created


async def _weekly_totals(
    db: AsyncSession, user_id: int, category_id: int, start: date, end: date
) -> list[float]:
    result = await db.execute(
        select(Transaction.transaction_date, Transaction.amount)
        .where(
            Transaction.user_id == user_id,
            Transaction.category_id == category_id,
            Transaction.transaction_date >= start,
            Transaction.transaction_date <= end,
        )
        .order_by(Transaction.transaction_date)
    )
    rows = result.all()
    if not rows:
        return []

    weeks: dict[int, float] = {}
    for tx_date, amount in rows:
        week_num = tx_date.isocalendar()[1] + tx_date.year * 100
        weeks[week_num] = weeks.get(week_num, 0) + amount

    return list(weeks.values())
