from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from sqlalchemy import text

from app.config import settings
from app.db.session import Base, engine
from app.routers import analytics, auth, devices, email, notification_templates, notifications, subscriptions, transactions


@asynccontextmanager
async def lifespan(app: FastAPI):
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        # Additive columns for existing DBs (create_all does not ALTER)
        for stmt in (
            "DO $$ BEGIN CREATE TYPE transactiontype AS ENUM ('expense', 'income'); EXCEPTION WHEN duplicate_object THEN NULL; END $$",
            "ALTER TABLE transactions ADD COLUMN IF NOT EXISTS transaction_type transactiontype DEFAULT 'expense'",
            "ALTER TABLE transactions ADD COLUMN IF NOT EXISTS image_path VARCHAR(500)",
            "UPDATE transactions SET transaction_type = 'expense' WHERE transaction_type IS NULL",
        ):
            try:
                await conn.execute(text(stmt))
            except Exception:
                pass
        try:
            await conn.execute(text("""
                CREATE INDEX IF NOT EXISTS idx_transaction_embeddings_vector
                ON transaction_embeddings USING hnsw (embedding vector_cosine_ops)
            """))
            await conn.execute(text("""
                CREATE INDEX IF NOT EXISTS idx_personal_merchant_embeddings_vector
                ON personal_merchant_embeddings USING hnsw (embedding vector_cosine_ops)
            """))
        except Exception:
            pass
    from app.services.storage import ensure_upload_dir
    ensure_upload_dir()
    yield


app = FastAPI(
    title="Tuchi API",
    description="Expense management app — OCR + AI Classification pipeline",
    version="0.1.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router, prefix="/api/v1")
app.include_router(transactions.router, prefix="/api/v1")
app.include_router(notifications.router, prefix="/api/v1")
app.include_router(notification_templates.router, prefix="/api/v1")
app.include_router(analytics.router, prefix="/api/v1")
app.include_router(devices.router, prefix="/api/v1")
app.include_router(email.router, prefix="/api/v1")
app.include_router(subscriptions.router, prefix="/api/v1")


@app.get("/health")
async def health():
    return {"status": "ok", "service": "tuchi-gateway-api"}
