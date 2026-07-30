import enum
from datetime import date, datetime
from typing import Optional

from pgvector.sqlalchemy import Vector
from sqlalchemy import (
    Boolean,
    Date,
    DateTime,
    Enum,
    Float,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.session import Base


class TransactionSource(str, enum.Enum):
    ocr = "ocr"
    notification = "notification"
    manual = "manual"
    email = "email"


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    hashed_password: Mapped[str] = mapped_column(String(255))
    display_name: Mapped[Optional[str]] = mapped_column(String(100))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    transactions: Mapped[list["Transaction"]] = relationship(back_populates="user")
    categories: Mapped[list["Category"]] = relationship(back_populates="user")
    budgets: Mapped[list["Budget"]] = relationship(back_populates="user")
    cashflow_profile: Mapped[Optional["UserCashflowProfile"]] = relationship(
        back_populates="user",
        uselist=False,
    )


class Category(Base):
    __tablename__ = "categories"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[Optional[int]] = mapped_column(ForeignKey("users.id"), nullable=True)
    parent_id: Mapped[Optional[int]] = mapped_column(ForeignKey("categories.id"), nullable=True)
    name: Mapped[str] = mapped_column(String(100))
    icon: Mapped[Optional[str]] = mapped_column(String(50))
    is_user_defined: Mapped[bool] = mapped_column(Boolean, default=False)

    user: Mapped[Optional["User"]] = relationship(back_populates="categories")
    transactions: Mapped[list["Transaction"]] = relationship(back_populates="category")


class Merchant(Base):
    __tablename__ = "merchants"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(255))
    normalized_name: Mapped[str] = mapped_column(String(255), index=True)
    default_category_id: Mapped[Optional[int]] = mapped_column(ForeignKey("categories.id"))
    occurrence_count: Mapped[int] = mapped_column(Integer, default=1)

    __table_args__ = (UniqueConstraint("normalized_name", name="uq_merchant_normalized"),)


class Transaction(Base):
    __tablename__ = "transactions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    merchant_id: Mapped[Optional[int]] = mapped_column(ForeignKey("merchants.id"))
    merchant_name: Mapped[Optional[str]] = mapped_column(String(255))
    amount: Mapped[float] = mapped_column(Float)
    items: Mapped[Optional[dict]] = mapped_column(JSONB)
    category_id: Mapped[Optional[int]] = mapped_column(ForeignKey("categories.id"))
    source: Mapped[TransactionSource] = mapped_column(Enum(TransactionSource))
    confidence: Mapped[Optional[float]] = mapped_column(Float)
    ocr_track_used: Mapped[Optional[str]] = mapped_column(String(20))
    transaction_date: Mapped[date] = mapped_column(Date)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    classification_reason: Mapped[Optional[str]] = mapped_column(Text)

    user: Mapped["User"] = relationship(back_populates="transactions")
    category: Mapped[Optional["Category"]] = relationship(back_populates="transactions")
    embedding: Mapped[Optional["TransactionEmbedding"]] = relationship(
        back_populates="transaction", uselist=False
    )


class TransactionEmbedding(Base):
    __tablename__ = "transaction_embeddings"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    transaction_id: Mapped[int] = mapped_column(ForeignKey("transactions.id"), unique=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    embedding = mapped_column(Vector(768))

    transaction: Mapped["Transaction"] = relationship(back_populates="embedding")


class Budget(Base):
    __tablename__ = "budgets"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    category_id: Mapped[int] = mapped_column(ForeignKey("categories.id"))
    period: Mapped[str] = mapped_column(String(20), default="monthly")
    limit_amount: Mapped[float] = mapped_column(Float)

    user: Mapped["User"] = relationship(back_populates="budgets")


class Alert(Base):
    __tablename__ = "alerts"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    type: Mapped[str] = mapped_column(String(50))
    payload: Mapped[dict] = mapped_column(JSONB)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    read_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))


class NotificationTemplate(Base):
    __tablename__ = "notification_templates"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    package_name: Mapped[str] = mapped_column(String(255), index=True)
    regex_pattern: Mapped[str] = mapped_column(Text)
    template_type: Mapped[str] = mapped_column(String(50), default="bank_sms_style")
    version: Mapped[int] = mapped_column(Integer, default=1)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)


class MerchantReference(Base):
    """Personal merchant reference for OCR post-correction."""

    __tablename__ = "merchant_references"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    merchant_name: Mapped[str] = mapped_column(String(255))
    normalized_name: Mapped[str] = mapped_column(String(255))

    __table_args__ = (UniqueConstraint("user_id", "normalized_name", name="uq_user_merchant_ref"),)


class PersonalMerchantEmbedding(Base):
    """Personal Vector Store — merchant-level embeddings for fast classification."""

    __tablename__ = "personal_merchant_embeddings"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    merchant_name: Mapped[str] = mapped_column(String(255))
    normalized_name: Mapped[str] = mapped_column(String(255), index=True)
    category_id: Mapped[int] = mapped_column(ForeignKey("categories.id"))
    embedding = mapped_column(Vector(768))
    confirm_count: Mapped[int] = mapped_column(Integer, default=1)

    __table_args__ = (UniqueConstraint("user_id", "normalized_name", name="uq_user_merchant_emb"),)


class UserDevice(Base):
    __tablename__ = "user_devices"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    fcm_token: Mapped[str] = mapped_column(String(512))
    platform: Mapped[str] = mapped_column(String(20), default="android")
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    __table_args__ = (UniqueConstraint("user_id", "fcm_token", name="uq_user_device_token"),)


class BudgetAlertSent(Base):
    """Dedup budget push alerts per category/threshold/month."""

    __tablename__ = "budget_alerts_sent"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    category_id: Mapped[int] = mapped_column(ForeignKey("categories.id"))
    alert_type: Mapped[str] = mapped_column(String(20))
    period_key: Mapped[str] = mapped_column(String(7))  # YYYY-MM
    sent_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    __table_args__ = (
        UniqueConstraint("user_id", "category_id", "alert_type", "period_key", name="uq_budget_alert_sent"),
    )


class CategoryForecast(Base):
    __tablename__ = "category_forecasts"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    category_id: Mapped[int] = mapped_column(ForeignKey("categories.id"))
    period: Mapped[str] = mapped_column(String(7))  # YYYY-MM
    forecast_amount: Mapped[float] = mapped_column(Float)
    method: Mapped[str] = mapped_column(String(30), default="holt_winters")
    historical_months: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    __table_args__ = (
        UniqueConstraint("user_id", "category_id", "period", name="uq_category_forecast"),
    )


class EmailConnection(Base):
    __tablename__ = "email_connections"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), unique=True)
    email: Mapped[str] = mapped_column(String(255))
    refresh_token: Mapped[str] = mapped_column(Text)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    connected_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    last_sync_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))


class DetectedSubscription(Base):
    __tablename__ = "detected_subscriptions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    merchant_name: Mapped[str] = mapped_column(String(255))
    normalized_merchant: Mapped[str] = mapped_column(String(255), index=True)
    amount: Mapped[float] = mapped_column(Float)
    cycle_days: Mapped[int] = mapped_column(Integer, default=30)
    occurrence_count: Mapped[int] = mapped_column(Integer, default=2)
    last_charge_date: Mapped[date] = mapped_column(Date)
    next_expected_date: Mapped[Optional[date]] = mapped_column(Date)
    monthly_cost: Mapped[float] = mapped_column(Float)
    is_dismissed: Mapped[bool] = mapped_column(Boolean, default=False)
    detected_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    __table_args__ = (
        UniqueConstraint("user_id", "normalized_merchant", name="uq_user_subscription"),
    )


class CommunityMerchantSignal(Base):
    """Anonymous aggregated merchant→category signals from community."""

    __tablename__ = "community_merchant_signals"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    normalized_merchant: Mapped[str] = mapped_column(String(255), index=True)
    display_name: Mapped[str] = mapped_column(String(255))
    category_id: Mapped[int] = mapped_column(ForeignKey("categories.id"))
    vote_count: Mapped[int] = mapped_column(Integer, default=1)
    distinct_user_count: Mapped[int] = mapped_column(Integer, default=1)
    last_updated: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    __table_args__ = (
        UniqueConstraint("normalized_merchant", "category_id", name="uq_community_signal"),
    )


class UserCashflowProfile(Base):
    __tablename__ = "user_cashflow_profiles"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), unique=True, index=True)
    starting_balance: Mapped[float] = mapped_column(Float)
    monthly_income: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    currency: Mapped[str] = mapped_column(String(10), default="VND")
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    user: Mapped["User"] = relationship(back_populates="cashflow_profile")


class PipelineMetricDaily(Base):
    __tablename__ = "pipeline_metrics_daily"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    metric_date: Mapped[date] = mapped_column(Date, unique=True, index=True)
    ocr_total: Mapped[int] = mapped_column(Integer, default=0)
    ocr_fast: Mapped[int] = mapped_column(Integer, default=0)
    ocr_vintern: Mapped[int] = mapped_column(Integer, default=0)
    ocr_gemini: Mapped[int] = mapped_column(Integer, default=0)
    ocr_openai: Mapped[int] = mapped_column(Integer, default=0)
    ocr_smart: Mapped[int] = mapped_column(Integer, default=0)
    classify_total: Mapped[int] = mapped_column(Integer, default=0)
    cls_vector_knn: Mapped[int] = mapped_column(Integer, default=0)
    cls_merchant_vector: Mapped[int] = mapped_column(Integer, default=0)
    cls_global_graph: Mapped[int] = mapped_column(Integer, default=0)
    cls_llm: Mapped[int] = mapped_column(Integer, default=0)
    cls_smart: Mapped[int] = mapped_column(Integer, default=0)
