from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import RedirectResponse
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.deps import get_current_user
from app.models import EmailConnection, User
from app.services.email.gmail import sync_user_emails
from app.services.email.oauth import exchange_code_for_tokens, get_oauth_url

router = APIRouter(prefix="/email", tags=["email"])


class EmailConnectIn(BaseModel):
    authorization_code: str


class EmailStatusOut(BaseModel):
    connected: bool
    email: str | None = None
    last_sync_at: str | None = None


@router.get("/oauth/url")
async def get_gmail_oauth_url(user: User = Depends(get_current_user)):
    from app.config import settings

    if not settings.gmail_client_id:
        raise HTTPException(status_code=503, detail="Gmail OAuth chưa được cấu hình trên server")
    url = get_oauth_url(state=str(user.id))
    return {"url": url}


@router.post("/connect", response_model=EmailStatusOut)
async def connect_gmail(
    body: EmailConnectIn,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    tokens = await exchange_code_for_tokens(body.authorization_code)
    if not tokens or not tokens.get("refresh_token"):
        raise HTTPException(status_code=400, detail="Không lấy được refresh token từ Google")

    # Get user email from token
    email = await _get_gmail_address(tokens.get("access_token", ""))

    result = await db.execute(select(EmailConnection).where(EmailConnection.user_id == user.id))
    conn = result.scalar_one_or_none()
    if conn:
        conn.refresh_token = tokens["refresh_token"]
        conn.email = email or conn.email
        conn.is_active = True
    else:
        db.add(
            EmailConnection(
                user_id=user.id,
                email=email or user.email,
                refresh_token=tokens["refresh_token"],
            )
        )

    return EmailStatusOut(connected=True, email=email)


@router.get("/oauth/callback")
async def oauth_callback(
    code: str = Query(...),
    state: str = Query(...),
    db: AsyncSession = Depends(get_db),
):
    """Browser redirect callback for Gmail OAuth."""
    tokens = await exchange_code_for_tokens(code)
    if not tokens or not tokens.get("refresh_token"):
        return RedirectResponse(url="tuchi://email/error")

    user_id = int(state)
    email = await _get_gmail_address(tokens.get("access_token", ""))

    result = await db.execute(select(EmailConnection).where(EmailConnection.user_id == user_id))
    conn = result.scalar_one_or_none()
    if conn:
        conn.refresh_token = tokens["refresh_token"]
        conn.email = email or conn.email
        conn.is_active = True
    else:
        db.add(
            EmailConnection(
                user_id=user_id,
                email=email or "",
                refresh_token=tokens["refresh_token"],
            )
        )
    await db.commit()
    return RedirectResponse(url="tuchi://email/connected")


@router.get("/status", response_model=EmailStatusOut)
async def email_status(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(EmailConnection).where(EmailConnection.user_id == user.id))
    conn = result.scalar_one_or_none()
    if not conn or not conn.is_active:
        return EmailStatusOut(connected=False)
    return EmailStatusOut(
        connected=True,
        email=conn.email,
        last_sync_at=conn.last_sync_at.isoformat() if conn.last_sync_at else None,
    )


@router.post("/sync")
async def sync_emails(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    created = await sync_user_emails(db, user.id)
    return {"synced": len(created), "transaction_ids": [t.id for t in created]}


@router.delete("/disconnect")
async def disconnect_email(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(EmailConnection).where(EmailConnection.user_id == user.id))
    conn = result.scalar_one_or_none()
    if conn:
        conn.is_active = False
    return {"status": "disconnected"}


async def _get_gmail_address(access_token: str) -> str | None:
    if not access_token:
        return None
    import httpx

    try:
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.get(
                "https://www.googleapis.com/oauth2/v2/userinfo",
                headers={"Authorization": f"Bearer {access_token}"},
            )
            resp.raise_for_status()
            return resp.json().get("email")
    except Exception:
        return None
