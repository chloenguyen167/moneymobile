from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.deps import get_current_user
from app.models import User, UserDevice

router = APIRouter(prefix="/devices", tags=["devices"])


class DeviceRegister(BaseModel):
    fcm_token: str
    platform: str = "android"


@router.post("/register")
async def register_device(
    body: DeviceRegister,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(UserDevice).where(
            UserDevice.user_id == user.id,
            UserDevice.fcm_token == body.fcm_token,
        )
    )
    device = result.scalar_one_or_none()
    if device:
        device.platform = body.platform
    else:
        db.add(UserDevice(user_id=user.id, fcm_token=body.fcm_token, platform=body.platform))
    return {"status": "registered"}


@router.delete("/unregister")
async def unregister_device(
    body: DeviceRegister,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(UserDevice).where(
            UserDevice.user_id == user.id,
            UserDevice.fcm_token == body.fcm_token,
        )
    )
    device = result.scalar_one_or_none()
    if device:
        await db.delete(device)
    return {"status": "unregistered"}
