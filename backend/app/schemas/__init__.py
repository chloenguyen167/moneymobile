from datetime import date, datetime
from enum import Enum
from typing import Optional

from pydantic import BaseModel, EmailStr, Field


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class UserRegister(BaseModel):
    email: EmailStr
    password: str = Field(min_length=6)
    display_name: Optional[str] = None


class UserLogin(BaseModel):
    email: EmailStr
    password: str


class UserOut(BaseModel):
    id: int
    email: str
    display_name: Optional[str]

    model_config = {"from_attributes": True}


class CategoryOut(BaseModel):
    id: int
    name: str
    icon: Optional[str]
    is_user_defined: bool
    parent_id: Optional[int]

    model_config = {"from_attributes": True}


class ReceiptItem(BaseModel):
    name: str
    price: float  # đơn giá (unit price)
    qty: float = 1  # số lượng — có thể thập phân (kg)
    line_total: Optional[float] = None  # thành tiền dòng (nếu có)


class OcrResult(BaseModel):
    merchant: Optional[str] = None
    items: list[ReceiptItem] = []
    total_amount: Optional[float] = None
    transaction_date: Optional[date] = None
    ocr_track_used: str = "fast"
    ocr_confidence: float = 0.0
    raw_text: Optional[str] = None


class ClassificationResult(BaseModel):
    category_id: Optional[int] = None
    category_name: Optional[str] = None
    confidence: float = 0.0
    track_used: str = "fast"
    reason: Optional[str] = None
    needs_confirmation: bool = True


class TransactionCreate(BaseModel):
    merchant_name: Optional[str] = None
    amount: float
    items: Optional[list[ReceiptItem]] = None
    category_id: Optional[int] = None
    source: str = "manual"
    transaction_date: Optional[date] = None
    ocr_track_used: Optional[str] = None
    confidence: Optional[float] = None
    classification_reason: Optional[str] = None


class TransactionUpdate(BaseModel):
    category_id: Optional[int] = None
    merchant_name: Optional[str] = None
    amount: Optional[float] = None


class TransactionOut(BaseModel):
    id: int
    merchant_name: Optional[str]
    amount: float
    items: Optional[list] = None
    category_id: Optional[int]
    category_name: Optional[str] = None
    source: str
    confidence: Optional[float]
    ocr_track_used: Optional[str]
    transaction_date: date
    created_at: datetime
    classification_reason: Optional[str]

    model_config = {"from_attributes": True}


class BudgetCreate(BaseModel):
    category_id: int
    limit_amount: float
    period: str = "monthly"


class BudgetOut(BaseModel):
    id: int
    category_id: int
    category_name: Optional[str] = None
    limit_amount: float
    period: str
    spent: float = 0
    percent_used: float = 0

    model_config = {"from_attributes": True}


class NotificationFieldsIn(BaseModel):
    package_name: str
    amount: float
    merchant: Optional[str] = None
    transaction_time: Optional[datetime] = None
    sign: str = "-"
    category_id: Optional[int] = None
    category_name: Optional[str] = None


class NotificationTemplateOut(BaseModel):
    id: int
    package_name: str
    regex_pattern: str
    template_type: str
    version: int

    model_config = {"from_attributes": True}


class AnalyticsSummary(BaseModel):
    total_spent: float
    by_category: list[dict]
    daily_trend: list[dict]
    forecast_end_of_month: float
    on_pace_percent: float
    category_forecasts: list[dict] = []


class CategoryForecastOut(BaseModel):
    category_id: int
    category_name: str
    forecast_amount: float
    current_spent: float = 0
    method: str = "holt_winters"
    historical_months: int = 0
    on_track: bool = True


class EmailConnectIn(BaseModel):
    authorization_code: str


class EmailStatusOut(BaseModel):
    connected: bool
    email: str | None = None
    last_sync_at: str | None = None


class AlertOut(BaseModel):
    id: int
    type: str
    payload: dict
    created_at: datetime
    read_at: Optional[datetime]

    model_config = {"from_attributes": True}


class ProcessReceiptResponse(BaseModel):
    ocr: OcrResult
    classification: ClassificationResult
    transaction_id: Optional[int] = None


class SubscriptionOut(BaseModel):
    id: int
    merchant_name: str
    amount: float
    cycle_days: int
    occurrence_count: int
    last_charge_date: date
    next_expected_date: Optional[date]
    monthly_cost: float

    model_config = {"from_attributes": True}


class PipelineHealthOut(BaseModel):
    status: str
    period_days: int
    ocr_total: int
    ocr_smart_track_pct: float
    classify_total: int
    classify_smart_track_pct: float
    target_smart_track_pct: float
    recommendations: list[str]
    daily_breakdown: list[dict]
    current_thresholds: dict
