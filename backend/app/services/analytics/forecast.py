"""Holt-Winters / Exponential Smoothing forecast per category (Phase 3)."""

import logging
from calendar import monthrange
from datetime import date

import numpy as np
import pandas as pd
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Category, CategoryForecast, Transaction

logger = logging.getLogger(__name__)

MIN_MONTHS = 3


async def compute_category_forecasts(db: AsyncSession, user_id: int) -> list[dict]:
    """Compute next-month forecast for each category with enough history."""
    today = date.today()
    forecasts = []

    cats_result = await db.execute(
        select(Category).where((Category.user_id.is_(None)) | (Category.user_id == user_id))
    )
    categories = cats_result.scalars().all()

    for cat in categories:
        monthly = await _monthly_totals(db, user_id, cat.id, months=12)
        if len(monthly) < MIN_MONTHS:
            continue

        forecast_amount, method = _holt_winters_forecast(monthly)
        if forecast_amount is None:
            continue

        # Upsert forecast record
        period = today.strftime("%Y-%m")
        existing = await db.execute(
            select(CategoryForecast).where(
                CategoryForecast.user_id == user_id,
                CategoryForecast.category_id == cat.id,
                CategoryForecast.period == period,
            )
        )
        record = existing.scalar_one_or_none()
        if record:
            record.forecast_amount = forecast_amount
            record.method = method
            record.historical_months = len(monthly)
        else:
            db.add(
                CategoryForecast(
                    user_id=user_id,
                    category_id=cat.id,
                    period=period,
                    forecast_amount=forecast_amount,
                    method=method,
                    historical_months=len(monthly),
                )
            )

        # Current month spent so far
        start = today.replace(day=1)
        spent_result = await db.execute(
            select(func.coalesce(func.sum(Transaction.amount), 0)).where(
                Transaction.user_id == user_id,
                Transaction.category_id == cat.id,
                Transaction.transaction_date >= start,
            )
        )
        current_spent = float(spent_result.scalar() or 0)

        forecasts.append(
            {
                "category_id": cat.id,
                "category_name": cat.name,
                "forecast_amount": round(forecast_amount, 0),
                "current_spent": current_spent,
                "method": method,
                "historical_months": len(monthly),
                "on_track": current_spent <= forecast_amount * (today.day / monthrange(today.year, today.month)[1]),
            }
        )

    return forecasts


async def _monthly_totals(db: AsyncSession, user_id: int, category_id: int, months: int = 12) -> list[float]:
    today = date.today()
    totals = []
    for i in range(months - 1, -1, -1):
        month = today.month - i
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
        totals.append(float(result.scalar() or 0))
    return totals


def _holt_winters_forecast(monthly: list[float]) -> tuple[float | None, str]:
    """Holt-Winters with fallback to simple exponential smoothing."""
    series = pd.Series(monthly, dtype=float)

    # Skip if all zeros
    if series.sum() == 0:
        return None, "none"

    try:
        from statsmodels.tsa.holtwinters import ExponentialSmoothing

        if len(series) >= 6:
            model = ExponentialSmoothing(
                series,
                trend="add",
                seasonal="add" if len(series) >= 12 else None,
                seasonal_periods=12 if len(series) >= 12 else None,
            )
            fit = model.fit(optimized=True)
            forecast = float(fit.forecast(1).iloc[0])
            method = "holt_winters"
        else:
            model = ExponentialSmoothing(series, trend="add")
            fit = model.fit(optimized=True)
            forecast = float(fit.forecast(1).iloc[0])
            method = "exponential_smoothing"
    except Exception as exc:
        logger.debug("Holt-Winters failed, using linear extrapolation: %s", exc)
        # Simple linear extrapolation fallback
        x = np.arange(len(series))
        if len(x) < 2:
            return float(series.iloc[-1]), "last_value"
        coef = np.polyfit(x, series.values, 1)
        forecast = float(np.polyval(coef, len(series)))
        method = "linear"

    return max(forecast, 0), method


async def get_stored_forecasts(db: AsyncSession, user_id: int) -> list[dict]:
    period = date.today().strftime("%Y-%m")
    result = await db.execute(
        select(CategoryForecast, Category)
        .join(Category, CategoryForecast.category_id == Category.id)
        .where(CategoryForecast.user_id == user_id, CategoryForecast.period == period)
    )
    return [
        {
            "category_id": f.category_id,
            "category_name": c.name,
            "forecast_amount": f.forecast_amount,
            "method": f.method,
            "historical_months": f.historical_months,
        }
        for f, c in result.all()
    ]
