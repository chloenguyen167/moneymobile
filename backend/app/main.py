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
