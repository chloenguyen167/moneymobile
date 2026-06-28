from celery import Celery
from celery.schedules import crontab

from app.config import settings

celery_app = Celery("tuchi", broker=settings.redis_url, backend=settings.redis_url)
celery_app.conf.update(
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",
    timezone="Asia/Ho_Chi_Minh",
    beat_schedule={
        "nightly-analytics": {
            "task": "app.worker.run_nightly_analytics",
            "schedule": crontab(hour=2, minute=0),
        },
        "nightly-forecasts": {
            "task": "app.worker.run_nightly_forecasts",
            "schedule": crontab(hour=2, minute=30),
        },
        "weekly-merchant-graph": {
            "task": "app.worker.rebuild_merchant_graph",
            "schedule": crontab(hour=3, minute=0, day_of_week=0),
        },
        "email-sync": {
            "task": "app.worker.sync_all_emails",
            "schedule": crontab(minute=0, hour="*/6"),
        },
        "detect-subscriptions": {
            "task": "app.worker.detect_all_subscriptions",
            "schedule": crontab(hour=4, minute=0),
        },
        "gpu-auto-tune": {
            "task": "app.worker.gpu_auto_tune",
            "schedule": crontab(hour=5, minute=0, day_of_week=1),
        },
    },
)


def _run_async(coro):
    import asyncio

    try:
        loop = asyncio.get_event_loop()
    except RuntimeError:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
    return loop.run_until_complete(coro)


@celery_app.task(name="app.worker.run_nightly_analytics")
def run_nightly_analytics():
    _run_async(_nightly_analytics())


@celery_app.task(name="app.worker.rebuild_merchant_graph")
def rebuild_merchant_graph():
    _run_async(_rebuild_graph())


@celery_app.task(name="app.worker.run_nightly_forecasts")
def run_nightly_forecasts():
    _run_async(_nightly_forecasts())


@celery_app.task(name="app.worker.sync_all_emails")
def sync_all_emails():
    _run_async(_sync_emails())


@celery_app.task(name="app.worker.detect_all_subscriptions")
def detect_all_subscriptions():
    _run_async(_detect_subscriptions())


@celery_app.task(name="app.worker.gpu_auto_tune")
def gpu_auto_tune():
    _run_async(_gpu_tune())


async def _nightly_analytics():
    from sqlalchemy import select

    from app.db.session import async_session
    from app.models import User
    from app.services.analytics.anomaly import detect_spending_anomalies
    from app.services.analytics.budget import check_budget_alerts

    async with async_session() as db:
        result = await db.execute(select(User.id))
        for (user_id,) in result.all():
            await check_budget_alerts(db, user_id)
            await detect_spending_anomalies(db, user_id)
        await db.commit()


async def _rebuild_graph():
    from app.db.session import async_session
    from app.services.classify.merchant_graph import rebuild_merchant_graph

    async with async_session() as db:
        count = await rebuild_merchant_graph(db)
        await db.commit()
        return count


async def _nightly_forecasts():
    from sqlalchemy import select

    from app.db.session import async_session
    from app.models import User
    from app.services.analytics.forecast import compute_category_forecasts

    async with async_session() as db:
        result = await db.execute(select(User.id))
        for (user_id,) in result.all():
            await compute_category_forecasts(db, user_id)
        await db.commit()


async def _sync_emails():
    from sqlalchemy import select

    from app.db.session import async_session
    from app.models import EmailConnection
    from app.services.email.gmail import sync_user_emails

    async with async_session() as db:
        result = await db.execute(
            select(EmailConnection.user_id).where(EmailConnection.is_active.is_(True))
        )
        for (user_id,) in result.all():
            await sync_user_emails(db, user_id)
        await db.commit()


async def _detect_subscriptions():
    from sqlalchemy import select

    from app.db.session import async_session
    from app.models import User
    from app.services.analytics.subscriptions import detect_subscriptions

    async with async_session() as db:
        result = await db.execute(select(User.id))
        for (user_id,) in result.all():
            await detect_subscriptions(db, user_id)
        await db.commit()


async def _gpu_tune():
    from app.db.session import async_session
    from app.services.metrics.pipeline import auto_tune_thresholds

    async with async_session() as db:
        return await auto_tune_thresholds(db)
