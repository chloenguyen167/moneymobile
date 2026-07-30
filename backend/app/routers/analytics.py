from datetime import datetime

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.deps import get_current_user
from app.models import Alert, Budget, Category, User
from app.schemas import (
    AlertOut,
    AnalyticsSummary,
    BudgetCreate,
    BudgetOut,
    CashflowInsightsOut,
    CashflowProfileIn,
    CashflowProfileOut,
    PipelineHealthOut,
    SubscriptionOut,
)
from app.services.analytics.cashflow import get_cashflow_profile, upsert_cashflow_profile
from app.services.analytics.forecast import compute_category_forecasts, get_stored_forecasts
from app.services.analytics.recommendations import build_cashflow_insights
from app.services.analytics.subscriptions import get_user_subscriptions
from app.services.metrics.pipeline import get_pipeline_health
from app.services.analytics.budget import get_analytics_summary, get_budget_status

router = APIRouter(tags=["analytics"])


@router.get("/analytics/summary", response_model=AnalyticsSummary)
async def analytics_summary(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await get_analytics_summary(db, user.id)


@router.get("/budgets", response_model=list[BudgetOut])
async def list_budgets(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    statuses = await get_budget_status(db, user.id)
    return [BudgetOut(**s) for s in statuses]


@router.post("/budgets", response_model=BudgetOut)
async def create_budget(
    body: BudgetCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    budget = Budget(user_id=user.id, category_id=body.category_id, limit_amount=body.limit_amount, period=body.period)
    db.add(budget)
    await db.flush()

    statuses = await get_budget_status(db, user.id)
    match = next((s for s in statuses if s["id"] == budget.id), None)
    return BudgetOut(**match) if match else BudgetOut(
        id=budget.id,
        category_id=budget.category_id,
        limit_amount=budget.limit_amount,
        period=budget.period,
    )


@router.get("/alerts", response_model=list[AlertOut])
async def list_alerts(
    unread_only: bool = Query(False),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    query = select(Alert).where(Alert.user_id == user.id)
    if unread_only:
        query = query.where(Alert.read_at.is_(None))
    result = await db.execute(query.order_by(Alert.created_at.desc()).limit(50))
    return result.scalars().all()


@router.post("/alerts/{alert_id}/read", response_model=AlertOut)
async def mark_alert_read(
    alert_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(Alert).where(Alert.id == alert_id, Alert.user_id == user.id))
    alert = result.scalar_one_or_none()
    if not alert:
        from fastapi import HTTPException

        raise HTTPException(status_code=404, detail="Alert not found")
    alert.read_at = datetime.utcnow()
    return alert


@router.get("/analytics/forecasts")
async def category_forecasts(
    refresh: bool = Query(False),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    if refresh:
        forecasts = await compute_category_forecasts(db, user.id)
    else:
        forecasts = await get_stored_forecasts(db, user.id)
        if not forecasts:
            forecasts = await compute_category_forecasts(db, user.id)
    return forecasts


@router.get("/analytics/pipeline-health", response_model=PipelineHealthOut)
async def pipeline_health(
    days: int = 7,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await get_pipeline_health(db, days)


@router.get("/analytics/subscriptions-summary")
async def subscriptions_summary(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    subs = await get_user_subscriptions(db, user.id)
    total_monthly = sum(s.monthly_cost for s in subs)
    return {
        "count": len(subs),
        "total_monthly_cost": round(total_monthly, 0),
        "subscriptions": [SubscriptionOut.model_validate(s) for s in subs],
    }


@router.get("/categories", response_model=list)
async def list_categories(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    from app.schemas import CategoryOut
    from app.services.classify.pipeline import seed_default_categories

    await seed_default_categories(db)
    result = await db.execute(
        select(Category).where((Category.user_id.is_(None)) | (Category.user_id == user.id))
    )
    return [CategoryOut.model_validate(c) for c in result.scalars().all()]


@router.post("/cashflow/profile", response_model=CashflowProfileOut)
async def save_cashflow_profile(
    body: CashflowProfileIn,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    profile = await upsert_cashflow_profile(db, user.id, body.starting_balance, body.monthly_income)
    return CashflowProfileOut.model_validate(profile)


@router.get("/cashflow/profile", response_model=CashflowProfileOut)
async def read_cashflow_profile(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    from fastapi import HTTPException

    profile = await get_cashflow_profile(db, user.id)
    if not profile:
        raise HTTPException(status_code=404, detail="Cashflow profile not configured")
    return CashflowProfileOut.model_validate(profile)


@router.get("/analytics/cashflow-insights", response_model=CashflowInsightsOut)
async def cashflow_insights(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    from fastapi import HTTPException

    profile = await get_cashflow_profile(db, user.id)
    if not profile:
        raise HTTPException(status_code=404, detail="Cashflow profile not configured")
    return await build_cashflow_insights(db, user.id, profile)
