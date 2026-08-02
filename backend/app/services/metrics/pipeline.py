"""Pipeline metrics & GPU cost optimization (Phase 4)."""

import logging
from datetime import date, timedelta

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models import PipelineMetricDaily, Transaction

logger = logging.getLogger(__name__)

# Tracks that incur GPU/API cost
EXPENSIVE_OCR_TRACKS = {"qwen_vl", "payment_qwen_vl", "vintern", "gemini", "openai", "smart"}
EXPENSIVE_CLASSIFY_TRACKS = {"llm", "llm_taxonomy", "smart"}


async def record_ocr_track(db: AsyncSession, track: str) -> None:
    await _increment(db, ocr_track=track)


async def record_classify_track(db: AsyncSession, track: str) -> None:
    await _increment(db, classify_track=track)


async def _increment(db: AsyncSession, ocr_track: str | None = None, classify_track: str | None = None) -> None:
    today = date.today()
    result = await db.execute(select(PipelineMetricDaily).where(PipelineMetricDaily.metric_date == today))
    metric = result.scalar_one_or_none()
    if not metric:
        metric = PipelineMetricDaily(metric_date=today)
        db.add(metric)
        await db.flush()

    if ocr_track:
        # Map self-hosted VLMs to ocr_vintern counter (no DB migration)
        if ocr_track in ("qwen_vl", "payment_qwen_vl", "vintern"):
            field = "ocr_vintern"
        elif ocr_track == "gemini" or ocr_track == "payment_gemini":
            field = "ocr_gemini"
        elif ocr_track == "openai" or ocr_track == "payment_openai":
            field = "ocr_openai"
        elif ocr_track == "fast":
            field = "ocr_fast"
        else:
            field = "ocr_smart"
        current = getattr(metric, field, 0) or 0
        setattr(metric, field, current + 1)
        metric.ocr_total = (metric.ocr_total or 0) + 1

    if classify_track:
        field_map = {
            "vector_knn": "cls_vector_knn",
            "merchant_vector": "cls_merchant_vector",
            "global_graph": "cls_global_graph",
            "global_graph_fuzzy": "cls_global_graph",
            "llm": "cls_llm",
            "llm_taxonomy": "cls_llm",
            "smart": "cls_smart",
        }
        field = field_map.get(classify_track, "cls_smart")
        current = getattr(metric, field, 0) or 0
        setattr(metric, field, current + 1)
        metric.classify_total = (metric.classify_total or 0) + 1


async def get_pipeline_health(db: AsyncSession, days: int = 7) -> dict:
    """System health metrics for GPU cost monitoring."""
    since = date.today() - timedelta(days=days)
    result = await db.execute(
        select(PipelineMetricDaily).where(PipelineMetricDaily.metric_date >= since).order_by(PipelineMetricDaily.metric_date)
    )
    metrics = result.scalars().all()

    ocr_total = sum(m.ocr_total or 0 for m in metrics)
    ocr_expensive = sum(
        (m.ocr_vintern or 0) + (m.ocr_gemini or 0) + (m.ocr_openai or 0) + (m.ocr_smart or 0) for m in metrics
    )
    cls_total = sum(m.classify_total or 0 for m in metrics)
    cls_expensive = sum((m.cls_llm or 0) + (m.cls_smart or 0) for m in metrics)

    ocr_smart_pct = (ocr_expensive / ocr_total * 100) if ocr_total else 0
    cls_smart_pct = (cls_expensive / cls_total * 100) if cls_total else 0

    target = settings.smart_track_target_pct
    status = "healthy"
    recommendations: list[str] = []

    if ocr_smart_pct > target * 1.5:
        status = "warning"
        recommendations.append(
            f"OCR smart track {ocr_smart_pct:.1f}% vượt mục tiêu {target}% — "
            "cân nhắc tăng ocr_fast_confidence_threshold hoặc cải thiện merchant references"
        )
    if cls_smart_pct > target * 1.5:
        status = "warning"
        recommendations.append(
            f"Classification LLM {cls_smart_pct:.1f}% cao — "
            "personalization đang học chậm, kiểm tra vector store coverage"
        )

    daily_breakdown = [
        {
            "date": str(m.metric_date),
            "ocr_total": m.ocr_total or 0,
            "ocr_expensive": (m.ocr_vintern or 0) + (m.ocr_gemini or 0) + (m.ocr_openai or 0) + (m.ocr_smart or 0),
            "classify_total": m.classify_total or 0,
            "classify_expensive": (m.cls_llm or 0) + (m.cls_smart or 0),
        }
        for m in metrics
    ]

    return {
        "status": status,
        "period_days": days,
        "ocr_total": ocr_total,
        "ocr_smart_track_pct": round(ocr_smart_pct, 1),
        "classify_total": cls_total,
        "classify_smart_track_pct": round(cls_smart_pct, 1),
        "target_smart_track_pct": target,
        "recommendations": recommendations,
        "daily_breakdown": daily_breakdown,
        "current_thresholds": {
            "ocr_fast_confidence": settings.ocr_fast_confidence_threshold,
            "ocr_smart_confidence": settings.ocr_smart_confidence_threshold,
            "classify_knn_threshold": settings.classify_knn_threshold,
        },
    }


async def auto_tune_thresholds(db: AsyncSession) -> dict | None:
    """
    Auto-adjust OCR fast track threshold if smart track rate exceeds target.
    Runs weekly via Celery — conservative adjustments only.
    """
    health = await get_pipeline_health(db, days=7)
    ocr_pct = health["ocr_smart_track_pct"]
    target = settings.smart_track_target_pct
    changes = {}

    if ocr_pct > target * 1.3 and settings.ocr_fast_confidence_threshold < 0.92:
        # Don't actually mutate settings object in prod — store in DB or log recommendation
        suggested = min(settings.ocr_fast_confidence_threshold + 0.02, 0.92)
        changes["suggested_ocr_fast_threshold"] = suggested
        logger.info(
            "GPU optimization: OCR smart track %.1f%% > target %.1f%%, suggest threshold %.2f → %.2f",
            ocr_pct, target, settings.ocr_fast_confidence_threshold, suggested,
        )

    if ocr_pct < target * 0.5 and settings.ocr_fast_confidence_threshold > 0.75:
        suggested = max(settings.ocr_fast_confidence_threshold - 0.02, 0.75)
        changes["suggested_ocr_fast_threshold_lower"] = suggested

    return changes or None
