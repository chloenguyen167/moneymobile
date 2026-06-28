from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.deps import get_current_user
from app.models import NotificationTemplate, User
from app.schemas import NotificationTemplateOut

router = APIRouter(prefix="/notification-templates", tags=["notification-templates"])

DEFAULT_TEMPLATES = [
    {
        "package_name": "com.VCB",
        "regex_pattern": r"TK (?<account>\d+).*(?<sign>[+-])(?<amount>[\d,]+)VND.*luc (?<time>\d{2}:\d{2})",
        "template_type": "bank_sms_style",
    },
    {
        "package_name": "com.mbmobile",
        "regex_pattern": r"(?<sign>[+-])(?<amount>[\d,]+)\s*VND.*(?<merchant>.+)",
        "template_type": "bank_sms_style",
    },
    {
        "package_name": "com.mservice.momotransfer",
        "regex_pattern": r"Ban vua (?<sign>chi|nhan) (?<amount>[\d.,]+)\s*đ.*?(?<merchant>.+?)(?:\.|$)",
        "template_type": "wallet_style",
    },
    {
        "package_name": "com.vietinbank.ipay",
        "regex_pattern": r"(?<sign>[+-])(?<amount>[\d,]+)\s*VND.*",
        "template_type": "bank_sms_style",
    },
    {
        "package_name": "com.tpb.mobilebanking",
        "regex_pattern": r"(?<sign>[+-])(?<amount>[\d,]+)\s*VND.*(?<merchant>.+)",
        "template_type": "bank_sms_style",
    },
    {
        "package_name": "vn.com.techcombank.bb.app",
        "regex_pattern": r"(?<sign>[+-])(?<amount>[\d,]+)\s*VND.*",
        "template_type": "bank_sms_style",
    },
]


async def seed_templates(db: AsyncSession):
    result = await db.execute(select(NotificationTemplate).limit(1))
    if result.scalar_one_or_none():
        return
    for tpl in DEFAULT_TEMPLATES:
        db.add(NotificationTemplate(**tpl, version=1))
    await db.flush()


@router.get("", response_model=list[NotificationTemplateOut])
async def list_templates(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await seed_templates(db)
    result = await db.execute(
        select(NotificationTemplate).where(NotificationTemplate.is_active.is_(True))
    )
    return result.scalars().all()
