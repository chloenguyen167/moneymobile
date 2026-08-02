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
    price: float
    qty: int = 1
    raw_name: Optional[str] = None
    normalized_name: Optional[str] = None
    canonical_name: Optional[str] = None
    brand: Optional[str] = None
    size_value: Optional[float] = None
    size_unit: Optional[str] = None
    removed_tokens: Optional[list[str]] = None
    category_id: Optional[int] = None
    category_name: Optional[str] = None
    classification_confidence: Optional[float] = None
    classification_reason: Optional[str] = None


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
    category_breakdown: list["CategoryBreakdown"] = []


class CategoryBreakdown(BaseModel):
    category_id: Optional[int] = None
    category_name: str
    total_amount: float
    item_count: int


class TransactionCreate(BaseModel):
    merchant_name: Optional[str] = None
    description: Optional[str] = None
    amount: float
    items: Optional[list[ReceiptItem]] = None
    category_id: Optional[int] = None
    source: str = "manual"
    transaction_date: Optional[date] = None
    transaction_time: Optional[datetime] = None
    ocr_track_used: Optional[str] = None
    confidence: Optional[float] = None
    classification_reason: Optional[str] = None


class TransactionUpdate(BaseModel):
    category_id: Optional[int] = None
    merchant_name: Optional[str] = None
    description: Optional[str] = None
    amount: Optional[float] = None
    transaction_time: Optional[datetime] = None


class TransactionOut(BaseModel):
    id: int
    merchant_name: Optional[str]
    description: Optional[str] = None
    amount: float
    items: Optional[list] = None
    category_id: Optional[int]
    category_name: Optional[str] = None
    source: str
    confidence: Optional[float]
    ocr_track_used: Optional[str]
    transaction_date: date
    transaction_time: Optional[datetime] = None
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
    classification: Optional[ClassificationResult] = None
    transaction_id: Optional[int] = None


class ClassifyReceiptRequest(BaseModel):
    ocr: OcrResult
    auto_save: bool = True


class ClassifyReceiptResponse(BaseModel):
    classification: ClassificationResult
    transaction_id: Optional[int] = None


class PaymentScreenshotExtract(BaseModel):
    merchant: Optional[str] = None
    total_amount: Optional[float] = None
    transaction_date: Optional[date] = None
    payment_source: Optional[str] = None
    description: Optional[str] = None
    reference_code: Optional[str] = None
    ocr_track_used: str = "payment_smart"
    ocr_confidence: float = 0.0
    raw_text: Optional[str] = None


class ProcessPaymentScreenshotResponse(BaseModel):
    extraction: PaymentScreenshotExtract
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


class CashflowProfileIn(BaseModel):
    starting_balance: float
    monthly_income: Optional[float] = None


class CashflowProfileOut(BaseModel):
    starting_balance: float
    monthly_income: Optional[float] = None
    currency: str = "VND"
    updated_at: Optional[datetime] = None

    model_config = {"from_attributes": True}


class CashflowForecastOut(BaseModel):
    month: str
    starting_balance: float
    monthly_income: Optional[float] = None
    spent_so_far: float
    remaining_balance: float
    days_elapsed: int
    days_remaining: int
    daily_burn_rate: float
    forecast_end_of_month_spend: float
    projected_end_balance: float
    depletion_date: Optional[str] = None
    can_predict_depletion_date: bool = False


class CashflowDriverOut(BaseModel):
    category_name: str
    spent_so_far: float
    forecast_end_of_month: float
    safe_amount: float
    excess_amount: float
    pace_ratio: float


class CashflowRecommendationOut(BaseModel):
    category_name: str
    suggested_cut_amount: float
    suggested_cut_count: Optional[int] = None
    basis: str
    message: str
    priority: str


class CashflowInsightsOut(BaseModel):
    forecast: CashflowForecastOut
    drivers: list[CashflowDriverOut]
    recommendations: list[CashflowRecommendationOut]
