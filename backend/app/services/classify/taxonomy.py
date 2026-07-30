"""TELEClass-style taxonomy enrichment + dynamic category creation (Phase 3)."""

import json
import logging
from collections.abc import Iterable

import httpx
import numpy as np
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models import Category
from app.schemas import ClassificationResult, OcrResult, ReceiptItem
from app.services.classify.embedding import build_feature_text, build_feature_vector

logger = logging.getLogger(__name__)

# Keywords associated with each system category for TELEClass enrichment
CATEGORY_KEYWORDS: dict[str, list[str]] = {
    "Ăn uống": ["cơm", "phở", "cafe", "trà sữa", "nhà hàng", "food", "grab food", "highlands", "starbucks"],
    "Mua sắm": ["siêu thị", "winmart", "coopmart", "shopee", "lazada", "quần áo", "điện máy"],
    "Chăm sóc cá nhân": ["mỹ phẩm", "dầu gội", "sữa tắm", "kem đánh răng", "sữa rửa mặt", "son", "chăm sóc da"],
    "Di chuyển": ["grab", "be", "xăng", "petrolimex", "vé xe", "taxi", "gửi xe"],
    "Giải trí": ["netflix", "spotify", "cgv", "game", "karaoke", "phim"],
    "Hóa đơn & Tiện ích": ["điện", "evn", "nước", "internet", "fpt", "viettel", "mobifone", "tiền nhà"],
    "Sức khỏe": ["nhà thuốc", "bệnh viện", "pharmacy", "khám", "thuốc"],
    "Giáo dục": ["học phí", "sách", "khóa học", "udemy", "coursera"],
    "Khác": ["khác", "misc", "other"],
}

async def get_user_taxonomy(db: AsyncSession, user_id: int) -> list[Category]:
    result = await db.execute(
        select(Category).where((Category.user_id.is_(None)) | (Category.user_id == user_id))
    )
    return list(result.scalars().all())


def enrich_taxonomy_context(categories: list[Category], ocr: OcrResult, amount: float) -> str:
    """TELEClass: pick relevant category keywords via embedding similarity."""
    query_text = build_feature_text(ocr.merchant, [i.model_dump() for i in ocr.items])
    query_vec = np.array(build_feature_vector(ocr.merchant, [i.model_dump() for i in ocr.items], amount, ocr.transaction_date or __import__("datetime").date.today()))

    enriched_lines = []
    for cat in categories:
        keywords = CATEGORY_KEYWORDS.get(cat.name, [cat.name.lower()])
        kw_text = ", ".join(keywords[:8])
        cat_vec = np.array(build_feature_vector(cat.name, None, amount, ocr.transaction_date or __import__("datetime").date.today()))
        sim = float(np.dot(query_vec, cat_vec))
        if sim > 0.3 or cat.name in query_text.lower():
            enriched_lines.append(f"- {cat.name} (từ khóa: {kw_text})")

    if not enriched_lines:
        enriched_lines = [f"- {c.name}" for c in categories]

    return "\n".join(enriched_lines)


async def llm_classify_with_taxonomy(
    db: AsyncSession,
    user_id: int,
    ocr: OcrResult,
    amount: float,
) -> ClassificationResult | None:
    categories = await get_user_taxonomy(db, user_id)
    if not categories:
        return None

    taxonomy_ctx = enrich_taxonomy_context(categories, ocr, amount)
    cat_names = [c.name for c in categories]

    prompt = f"""Phân loại giao dịch chi tiêu Việt Nam.

Taxonomy hiện tại (chọn 1 category có sẵn HOẶC đề xuất category con mới nếu thực sự cần):
{taxonomy_ctx}

Giao dịch:
- Merchant: {ocr.merchant}
- Items: {[i.name for i in ocr.items]}
- Amount: {amount:,.0f} VND

Quy tắc:
1. Ưu tiên category có sẵn
2. Chỉ tạo category mới nếu không phù hợp category nào (is_new_category: true)
3. Category mới phải là category con, ngắn gọn, tiếng Việt

Trả JSON:
{{"category": "...", "is_new_category": false, "parent_category": null, "reason": "..."}}"""

    data = await _call_llm(prompt)
    if not data:
        return None

    category_name = data.get("category", "Khác")
    is_new = data.get("is_new_category", False)

    if is_new and category_name not in cat_names:
        parent_name = data.get("parent_category")
        parent_id = None
        if parent_name:
            parent = next((c for c in categories if c.name == parent_name), None)
            parent_id = parent.id if parent else None
        new_cat = Category(
            name=category_name,
            user_id=user_id,
            parent_id=parent_id,
            is_user_defined=True,
            icon="label",
        )
        db.add(new_cat)
        await db.flush()
        category = new_cat
    else:
        result = await db.execute(
            select(Category).where(
                Category.name == category_name,
                (Category.user_id.is_(None)) | (Category.user_id == user_id),
            )
        )
        category = result.scalar_one_or_none()
        if not category:
            return None

    return ClassificationResult(
        category_id=category.id,
        category_name=category.name,
        confidence=0.82,
        track_used="llm_taxonomy",
        reason=data.get("reason", "LLM phân loại với taxonomy enrichment"),
        needs_confirmation=True,
    )


async def llm_classify_receipt_items(
    db: AsyncSession,
    user_id: int,
    merchant: str | None,
    items: list[ReceiptItem],
) -> dict[int, dict]:
    if not items:
        return {}

    categories = await get_user_taxonomy(db, user_id)
    if not categories:
        return {}

    category_names = [c.name for c in categories]
    taxonomy_ctx = "\n".join(f"- {name}" for name in category_names)
    item_lines = []
    for index, item in enumerate(items):
        item_lines.append(
            f'{index}. name="{item.name}", canonical="{item.canonical_name or ""}", '
            f'brand="{item.brand or ""}", price={item.price}, qty={item.qty}'
        )

    prompt = f"""Phân loại từng sản phẩm trong hóa đơn vào đúng category có sẵn.

Taxonomy hiện tại:
{taxonomy_ctx}

Merchant: {merchant or "Unknown"}

Danh sách item:
{chr(10).join(item_lines)}

Quy tắc:
1. Chỉ được chọn category có sẵn trong taxonomy
2. Ưu tiên nghĩa thực tế của sản phẩm, không ưu tiên merchant
3. Nếu không chắc thì chọn "Khác"
4. Trả JSON object với key là index item

Trả JSON đúng dạng:
{{
  "0": {{"category": "Ăn uống", "confidence": 0.91, "reason": "..." }},
  "1": {{"category": "Khác", "confidence": 0.45, "reason": "..." }}
}}"""

    data = await _call_llm(prompt)
    if not isinstance(data, dict):
        return {}

    valid_names = set(category_names)
    parsed: dict[int, dict] = {}
    for raw_index, payload in data.items():
        try:
            index = int(raw_index)
        except (TypeError, ValueError):
            continue
        if not isinstance(payload, dict):
            continue
        category_name = str(payload.get("category", "Khác"))
        if category_name not in valid_names:
            continue
        try:
            confidence = float(payload.get("confidence", 0.0))
        except (TypeError, ValueError):
            confidence = 0.0
        parsed[index] = {
            "category": category_name,
            "confidence": max(0.0, min(confidence, 1.0)),
            "reason": str(payload.get("reason", "LLM phân loại item")),
        }
    return parsed


async def _call_llm(prompt: str) -> dict | None:
    if settings.openai_api_key:
        try:
            async with httpx.AsyncClient(timeout=30) as client:
                resp = await client.post(
                    "https://api.openai.com/v1/chat/completions",
                    headers={"Authorization": f"Bearer {settings.openai_api_key}"},
                    json={
                        "model": "gpt-4o-mini",
                        "messages": [{"role": "user", "content": prompt}],
                        "response_format": {"type": "json_object"},
                    },
                )
                resp.raise_for_status()
                return json.loads(resp.json()["choices"][0]["message"]["content"])
        except Exception as exc:
            logger.warning("OpenAI taxonomy classify failed: %s", exc)

    if settings.gemini_api_key:
        try:
            url = (
                f"https://generativelanguage.googleapis.com/v1beta/models/"
                f"{settings.gemini_model}:generateContent?key={settings.gemini_api_key}"
            )
            async with httpx.AsyncClient(timeout=30) as client:
                resp = await client.post(
                    url,
                    json={
                        "contents": [{"parts": [{"text": prompt}]}],
                        "generationConfig": {"responseMimeType": "application/json"},
                    },
                )
                resp.raise_for_status()
                text = resp.json()["candidates"][0]["content"]["parts"][0]["text"]
                return json.loads(text)
        except Exception as exc:
            logger.warning("Gemini taxonomy classify failed: %s", exc)

    return None
