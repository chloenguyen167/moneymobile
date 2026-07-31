from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "postgresql+asyncpg://tuchi:tuchi_dev@localhost:5432/tuchi"
    redis_url: str = "redis://localhost:6379/0"
    jwt_secret: str = "dev-secret-change-in-production"
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 60 * 24 * 7

    openai_api_key: str = ""
    gemini_api_key: str = ""

    upload_dir: str = "uploads"
    ocr_fast_confidence_threshold: float = 0.85
    ocr_smart_confidence_threshold: float = 0.6
    classify_knn_threshold: float = 0.85
    classify_knn_top_k: int = 5
    classify_knn_min_similarity: float = 0.6

    use_sentence_embeddings: bool = False
    embedding_model_name: str = "paraphrase-multilingual-mpnet-base-v2"

    firebase_credentials_path: str = ""
    fcm_enabled: bool = False

    # Phase 3: Vintern VLM (Transformers pipeline local, HTTP API fallback)
    vintern_model_id: str = "5CD-AI/Vintern-1B-v3_5"
    vintern_use_local_pipeline: bool = True
    vintern_api_url: str = ""
    vintern_api_key: str = ""
    vintern_model_name: str = "vintern-1b"
    vintern_confidence_threshold: float = 0.75
    vintern_timeout_seconds: int = 90

    # Phase 3: Gemini
    gemini_model: str = "gemini-2.0-flash"

    # Phase 3: Gmail OAuth (iOS email parsing)
    gmail_client_id: str = ""
    gmail_client_secret: str = ""
    gmail_redirect_uri: str = "http://localhost:8000/api/v1/email/oauth/callback"

    # Phase 4: GPU cost optimization
    smart_track_target_pct: float = 25.0  # target max % hitting expensive tracks
    community_min_distinct_users: int = 3

    cors_origins: list[str] = ["*"]


settings = Settings()
