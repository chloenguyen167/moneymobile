import math
from calendar import monthrange
from datetime import date

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Budget, Category, Transaction, UserCashflowProfile
from app.schemas import (
    CashflowDriverOut,
    CashflowForecastOut,
    CashflowInsightsOut,
    CashflowRecommendationOut,
)
from app.services.analytics.cashflow import compute_cashflow_forecast

FLEXIBLE_CATEGORIES = {"Ăn uống", "Mua sắm", "Chăm sóc cá nhân", "Giải trí"}
MIN_DRIVER_RATIO = 1.15


async def build_cashflow_insights(
    db: AsyncSession,
    user_id: int,
    profile: UserCashflowProfile,
) -> CashflowInsightsOut:
    forecast = await compute_cashflow_forecast(db, user_id, profile)
    drivers = await _build_drivers(db, user_id)
    recommendations = await _build_recommendations(db, user_id, forecast, drivers)
    return CashflowInsightsOut(
        forecast=forecast,
        drivers=drivers,
        recommendations=recommendations,
    )


async def _build_drivers(db: AsyncSession, user_id: int) -> list[CashflowDriverOut]:
    today = date.today()
    start = today.replace(day=1)
    last_day = monthrange(today.year, today.month)[1]
    days_elapsed = max(today.day, 1)
    days_in_month = last_day

    result = await db.execute(
        select(Category.id, Category.name, func.coalesce(func.sum(Transaction.amount), 0).label("spent"))
        .join(Transaction, Transaction.category_id == Category.id)
        .where(
            Transaction.user_id == user_id,
            Transaction.transaction_date >= start,
            Transaction.transaction_date <= today,
        )
        .group_by(Category.id, Category.name)
    )

    drivers: list[CashflowDriverOut] = []
    for category_id, category_name, spent in result.all():
        if category_name not in FLEXIBLE_CATEGORIES:
            continue
        spent_so_far = float(spent or 0)
        forecast_end_of_month = (spent_so_far / days_elapsed) * days_in_month if days_elapsed else spent_so_far
        safe_amount = await _safe_amount_for_category(db, user_id, category_id)
        if safe_amount <= 0:
            continue
        pace_ratio = forecast_end_of_month / safe_amount if safe_amount else 0.0
        excess_amount = max(forecast_end_of_month - safe_amount, 0.0)
        if pace_ratio < MIN_DRIVER_RATIO:
            continue
        drivers.append(
            CashflowDriverOut(
                category_name=category_name,
                spent_so_far=round(spent_so_far, 0),
                forecast_end_of_month=round(forecast_end_of_month, 0),
                safe_amount=round(safe_amount, 0),
                excess_amount=round(excess_amount, 0),
                pace_ratio=round(pace_ratio, 2),
            )
        )
    drivers.sort(key=lambda row: row.excess_amount, reverse=True)
    return drivers


async def _safe_amount_for_category(db: AsyncSession, user_id: int, category_id: int) -> float:
    budget_result = await db.execute(
        select(Budget.limit_amount).where(Budget.user_id == user_id, Budget.category_id == category_id)
    )
    budget_limit = budget_result.scalar_one_or_none()
    if budget_limit:
        return float(budget_limit)

    monthly = []
    today = date.today()
    for offset in range(1, 4):
        month = today.month - offset
        year = today.year
        while month <= 0:
            month += 12
            year -= 1
        last_day = monthrange(year, month)[1]
        start = date(year, month, 1)
        end = date(year, month, last_day)
        result = await db.execute(
            select(func.coalesce(func.sum(Transaction.amount), 0)).where(
                Transaction.user_id == user_id,
                Transaction.category_id == category_id,
                Transaction.transaction_date >= start,
                Transaction.transaction_date <= end,
            )
        )
        total = float(result.scalar() or 0)
        if total > 0:
            monthly.append(total)
    if monthly:
        return sum(monthly) / len(monthly)

    return 0.0


async def _build_recommendations(
    db: AsyncSession,
    user_id: int,
    forecast: CashflowForecastOut,
    drivers: list[CashflowDriverOut],
) -> list[CashflowRecommendationOut]:
    recommendations: list[CashflowRecommendationOut] = []
    negative_gap = max(-forecast.projected_end_balance, 0.0)

    for driver in drivers[:3]:
        suggested_cut_amount = driver.excess_amount
        if negative_gap > 0:
            suggested_cut_amount = min(driver.excess_amount, negative_gap) or driver.excess_amount

        median_ticket = await _median_ticket_amount(db, user_id, driver.category_name)
        suggested_cut_count = None
        basis = "safe_amount"
        if median_ticket and median_ticket > 0:
            suggested_cut_count = max(1, math.ceil(suggested_cut_amount / median_ticket))
            basis = "median_ticket"

        priority = "high" if forecast.projected_end_balance < 0 or driver.pace_ratio >= 1.4 else "medium"
        message = (
            f"{driver.category_name} đang vượt nhịp an toàn. "
            f"Nên giảm khoảng {int(round(suggested_cut_amount, 0)):,}đ".replace(",", ".")
        )
        if suggested_cut_count:
            message += f", tương đương khoảng {suggested_cut_count} lần chi tiêu trong nhóm này"
        message += "."

        recommendations.append(
            CashflowRecommendationOut(
                category_name=driver.category_name,
                suggested_cut_amount=round(suggested_cut_amount, 0),
                suggested_cut_count=suggested_cut_count,
                basis=basis,
                message=message,
                priority=priority,
            )
        )

    return recommendations


async def _median_ticket_amount(db: AsyncSession, user_id: int, category_name: str) -> float | None:
    result = await db.execute(
        select(Transaction.amount)
        .join(Category, Transaction.category_id == Category.id)
        .where(Transaction.user_id == user_id, Category.name == category_name)
        .order_by(Transaction.amount)
    )
    amounts = [float(row[0]) for row in result.all() if float(row[0]) > 0]
    if not amounts:
        return None
    mid = len(amounts) // 2
    if len(amounts) % 2 == 1:
        return amounts[mid]
    return (amounts[mid - 1] + amounts[mid]) / 2
