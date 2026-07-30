from calendar import monthrange
from datetime import date, timedelta

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Transaction, UserCashflowProfile
from app.schemas import CashflowForecastOut


async def get_cashflow_profile(db: AsyncSession, user_id: int) -> UserCashflowProfile | None:
    result = await db.execute(
        select(UserCashflowProfile).where(UserCashflowProfile.user_id == user_id)
    )
    return result.scalar_one_or_none()


async def upsert_cashflow_profile(
    db: AsyncSession,
    user_id: int,
    starting_balance: float,
    monthly_income: float | None,
) -> UserCashflowProfile:
    profile = await get_cashflow_profile(db, user_id)
    if profile:
        profile.starting_balance = starting_balance
        profile.monthly_income = monthly_income
    else:
        profile = UserCashflowProfile(
            user_id=user_id,
            starting_balance=starting_balance,
            monthly_income=monthly_income,
            currency="VND",
        )
        db.add(profile)
    await db.flush()
    return profile


async def compute_cashflow_forecast(
    db: AsyncSession,
    user_id: int,
    profile: UserCashflowProfile,
    month: date | None = None,
) -> CashflowForecastOut:
    today = date.today()
    ref = month or today
    last_day = monthrange(ref.year, ref.month)[1]
    start = ref.replace(day=1)
    end = ref.replace(day=last_day)

    spent_result = await db.execute(
        select(func.coalesce(func.sum(Transaction.amount), 0)).where(
            Transaction.user_id == user_id,
            Transaction.transaction_date >= start,
            Transaction.transaction_date <= end,
        )
    )
    spent_so_far = float(spent_result.scalar() or 0)

    days_elapsed = max(
        1,
        ref.day if (ref.year == today.year and ref.month == today.month) else last_day,
    )
    days_remaining = max(last_day - days_elapsed, 0)
    daily_burn_rate = spent_so_far / days_elapsed if days_elapsed else 0.0
    forecast_end_of_month_spend = daily_burn_rate * last_day
    remaining_balance = profile.starting_balance - spent_so_far
    projected_end_balance = profile.starting_balance + (profile.monthly_income or 0.0) - forecast_end_of_month_spend

    depletion_date = None
    can_predict_depletion_date = False
    if profile.starting_balance > 0 and remaining_balance > 0 and daily_burn_rate > 0:
        days_until_depletion = int(remaining_balance / daily_burn_rate)
        depletion = today + timedelta(days=days_until_depletion)
        depletion_date = depletion.isoformat()
        can_predict_depletion_date = True

    return CashflowForecastOut(
        month=start.strftime("%Y-%m"),
        starting_balance=round(profile.starting_balance, 0),
        monthly_income=round(profile.monthly_income, 0) if profile.monthly_income is not None else None,
        spent_so_far=round(spent_so_far, 0),
        remaining_balance=round(remaining_balance, 0),
        days_elapsed=days_elapsed,
        days_remaining=days_remaining,
        daily_burn_rate=round(daily_burn_rate, 0),
        forecast_end_of_month_spend=round(forecast_end_of_month_spend, 0),
        projected_end_balance=round(projected_end_balance, 0),
        depletion_date=depletion_date,
        can_predict_depletion_date=can_predict_depletion_date,
    )
