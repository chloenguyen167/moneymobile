from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.deps import get_current_user
from app.models import DetectedSubscription, User
from app.schemas import SubscriptionOut
from app.services.analytics.subscriptions import detect_subscriptions, get_user_subscriptions

router = APIRouter(prefix="/subscriptions", tags=["subscriptions"])


@router.get("", response_model=list[SubscriptionOut])
async def list_subscriptions(
    refresh: bool = False,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    if refresh:
        await detect_subscriptions(db, user.id)
    return await get_user_subscriptions(db, user.id)


@router.post("/detect", response_model=list[SubscriptionOut])
async def run_detection(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await detect_subscriptions(db, user.id)


@router.post("/{subscription_id}/dismiss")
async def dismiss_subscription(
    subscription_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(DetectedSubscription).where(
            DetectedSubscription.id == subscription_id,
            DetectedSubscription.user_id == user.id,
        )
    )
    sub = result.scalar_one_or_none()
    if not sub:
        from fastapi import HTTPException
        raise HTTPException(status_code=404, detail="Subscription not found")
    sub.is_dismissed = True
    return {"status": "dismissed"}
