from datetime import date, datetime

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.deps import get_current_user
from app.models import User
from app.schemas import NotificationFieldsIn, OcrResult, TransactionCreate, TransactionOut
from app.services.analytics import check_budget_alerts
from app.services.classify.pipeline import classify_transaction
from app.services.notification import find_duplicate, merge_notification_with_ocr
from app.services.transactions import save_transaction, to_transaction_out

router = APIRouter(prefix="/notifications", tags=["notifications"])


@router.post("/ingest", response_model=TransactionOut)
async def ingest_notification(
    body: NotificationFieldsIn,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    tx_time = body.transaction_time or datetime.utcnow()
    duplicate = await find_duplicate(db, user.id, body.amount, body.merchant, tx_time)

    if duplicate:
        await merge_notification_with_ocr(db, duplicate, body.merchant)
        return await to_transaction_out(db, duplicate)

    ocr = OcrResult(
        merchant=body.merchant,
        total_amount=body.amount,
        transaction_date=tx_time.date() if isinstance(tx_time, datetime) else date.today(),
    )
    classification = await classify_transaction(db, user.id, ocr, amount=body.amount)

    tx_body = TransactionCreate(
        merchant_name=body.merchant,
        amount=body.amount,
        category_id=classification.category_id,
        source="notification",
        transaction_date=ocr.transaction_date,
        confidence=classification.confidence,
        classification_reason=classification.reason,
    )
    tx = await save_transaction(db, user.id, tx_body)
    await check_budget_alerts(db, user.id)
    return await to_transaction_out(db, tx)
