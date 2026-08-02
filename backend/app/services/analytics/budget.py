"""Analytics: budget tracking, alerts with FCM push."""

from calendar import monthrange
from datetime import date, datetime

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Alert, Budget, BudgetAlertSent, Category, Transaction, TransactionType, UserDevice
from app.schemas import AnalyticsSummary
from app.services.push.fcm import send_push_to_tokens

ALERT_MESSAGES = {
    "budget_80": ("⚠️ Sắp vượt ngân sách", "Bạn đã dùng {pct}% ngân sách {category}"),
    "budget_100": ("🚨 Vượt ngân sách", "Đã dùng hết ngân sách {category} ({pct}%)"),
    "budget_120": ("🔴 Vượt ngân sách nghiêm trọng", "{category}: {pct}% ngân sách"),
}


async def get_analytics_summary(db: AsyncSession, user_id: int, month: date | None = None) -> AnalyticsSummary:
    from app.services.analytics.forecast import get_stored_forecasts

    today = date.today()
    ref = month or today.replace(day=1)
    last_day = monthrange(ref.year, ref.month)[1]
    start = ref.replace(day=1)
    end = ref.replace(day=last_day)

    spent_result = await db.execute(
        select(func.coalesce(func.sum(Transaction.amount), 0)).where(
            Transaction.user_id == user_id,
            Transaction.transaction_date >= start,
            Transaction.transaction_date <= end,
            Transaction.transaction_type == TransactionType.expense,
        )
    )
    total_spent = float(spent_result.scalar() or 0)

    by_cat_result = await db.execute(
        select(Category.name, func.sum(Transaction.amount).label("total"))
        .join(Category, Transaction.category_id == Category.id)
        .where(
            Transaction.user_id == user_id,
            Transaction.transaction_date >= start,
            Transaction.transaction_date <= end,
            Transaction.transaction_type == TransactionType.expense,
        )
        .group_by(Category.name)
        .order_by(func.sum(Transaction.amount).desc())
    )
    by_category = [{"category": r.name, "amount": float(r.total)} for r in by_cat_result.all()]

    daily_result = await db.execute(
        select(Transaction.transaction_date, func.sum(Transaction.amount).label("total"))
        .where(
            Transaction.user_id == user_id,
            Transaction.transaction_date >= start,
            Transaction.transaction_date <= end,
            Transaction.transaction_type == TransactionType.expense,
        )
        .group_by(Transaction.transaction_date)
        .order_by(Transaction.transaction_date)
    )
    daily_trend = [{"date": str(r.transaction_date), "amount": float(r.total)} for r in daily_result.all()]

    days_elapsed = max(today.day, 1) if ref.month == today.month and ref.year == today.year else last_day
    days_in_month = last_day
    forecast = (total_spent / days_elapsed) * days_in_month if days_elapsed else total_spent
    on_pace = (total_spent / days_elapsed * days_in_month / max(total_spent, 1)) * 100 if total_spent else 0

    return AnalyticsSummary(
        total_spent=total_spent,
        by_category=by_category,
        daily_trend=daily_trend,
        forecast_end_of_month=round(forecast, 0),
        on_pace_percent=round(min(on_pace, 200), 1),
        category_forecasts=await get_stored_forecasts(db, user_id),
    )


async def check_budget_alerts(db: AsyncSession, user_id: int) -> list[Alert]:
    today = date.today()
    start = today.replace(day=1)
    period_key = today.strftime("%Y-%m")
    alerts_created = []

    budgets_result = await db.execute(select(Budget).where(Budget.user_id == user_id))
    for budget in budgets_result.scalars().all():
        spent_result = await db.execute(
            select(func.coalesce(func.sum(Transaction.amount), 0)).where(
                Transaction.user_id == user_id,
                Transaction.category_id == budget.category_id,
                Transaction.transaction_date >= start,
                Transaction.transaction_type == TransactionType.expense,
            )
        )
        spent = float(spent_result.scalar() or 0)
        if budget.limit_amount <= 0:
            continue

        pct = spent / budget.limit_amount * 100
        cat_result = await db.execute(select(Category).where(Category.id == budget.category_id))
        cat = cat_result.scalar_one_or_none()
        cat_name = cat.name if cat else ""

        for threshold, alert_type in [(80, "budget_80"), (100, "budget_100"), (120, "budget_120")]:
            if pct < threshold:
                continue

            sent_check = await db.execute(
                select(BudgetAlertSent).where(
                    BudgetAlertSent.user_id == user_id,
                    BudgetAlertSent.category_id == budget.category_id,
                    BudgetAlertSent.alert_type == alert_type,
                    BudgetAlertSent.period_key == period_key,
                )
            )
            if sent_check.scalar_one_or_none():
                continue

            payload = {
                "category": cat_name,
                "spent": spent,
                "limit": budget.limit_amount,
                "percent": round(pct, 1),
            }
            alert = Alert(user_id=user_id, type=alert_type, payload=payload)
            db.add(alert)
            db.add(
                BudgetAlertSent(
                    user_id=user_id,
                    category_id=budget.category_id,
                    alert_type=alert_type,
                    period_key=period_key,
                )
            )
            alerts_created.append(alert)
            await _push_budget_alert(db, user_id, alert_type, cat_name, round(pct, 1), payload)

    return alerts_created


async def _push_budget_alert(
    db: AsyncSession,
    user_id: int,
    alert_type: str,
    category: str,
    pct: float,
    payload: dict,
) -> None:
    tokens_result = await db.execute(select(UserDevice.fcm_token).where(UserDevice.user_id == user_id))
    tokens = [r[0] for r in tokens_result.all()]
    if not tokens:
        return

    title_tpl, body_tpl = ALERT_MESSAGES.get(alert_type, ("Tuchi", "Cảnh báo ngân sách"))
    await send_push_to_tokens(
        tokens, title_tpl, body_tpl.format(category=category, pct=pct),
        data={"type": alert_type, **{k: str(v) for k, v in payload.items()}},
    )


async def get_budget_status(db: AsyncSession, user_id: int) -> list[dict]:
    today = date.today()
    start = today.replace(day=1)
    result = []

    budgets_result = await db.execute(
        select(Budget, Category)
        .join(Category, Budget.category_id == Category.id)
        .where(Budget.user_id == user_id)
    )
    for budget, category in budgets_result.all():
        spent_result = await db.execute(
            select(func.coalesce(func.sum(Transaction.amount), 0)).where(
                Transaction.user_id == user_id,
                Transaction.category_id == budget.category_id,
                Transaction.transaction_date >= start,
                Transaction.transaction_type == TransactionType.expense,
            )
        )
        spent = float(spent_result.scalar() or 0)
        pct = (spent / budget.limit_amount * 100) if budget.limit_amount else 0
        result.append(
            {
                "id": budget.id,
                "category_id": budget.category_id,
                "category_name": category.name,
                "limit_amount": budget.limit_amount,
                "period": budget.period,
                "spent": spent,
                "percent_used": round(pct, 1),
            }
        )
    return result
