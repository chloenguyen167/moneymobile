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

    # Local Ollama — Qwen3 text LLM for classify (OCR uses VietOCR, not Qwen-VL)
    ollama_enabled: bool = True
    ollama_base_url: str = "http://127.0.0.1:11434"
    ollama_vl_model: str = "qwen3-vl:4b"  # unused for OCR; kept for optional experiments
    ollama_llm_model: str = "qwen3:8b"
    ollama_llm_timeout_seconds: int = 120
    ollama_vl_timeout_seconds: int = 600
    ollama_vl_max_edge_px: int = 1280
    ollama_timeout_seconds: int = 180

    # Local VietOCR (https://github.com/pbcquoc/vietocr)
    vietocr_enabled: bool = True
    vietocr_model: str = "vgg_seq2seq"  # or vgg_transformer
    vietocr_device: str = ""  # auto: mps / cuda / cpu
    vietocr_max_image_width: int = 1600

    # After VietOCR: Ollama text LLM (qwen3) structures merchant/items/total — no Qwen-VL
    ocr_llm_struct_enabled: bool = True
    ocr_llm_vision_fallback: bool = False  # Qwen-VL disabled; VietOCR + text LLM only


    upload_dir: str = "uploads"
    ocr_fast_confidence_threshold: float = 0.85
    ocr_smart_confidence_threshold: float = 0.6
    classify_knn_threshold: float = 0.85
    classify_knn_top_k: int = 5
    classify_knn_min_similarity: float = 0.6
    classify_item_llm_confidence_threshold: float = 0.7
    classify_item_llm_max_items: int = 50

    use_sentence_embeddings: bool = False
    embedding_model_name: str = "paraphrase-multilingual-mpnet-base-v2"

    firebase_credentials_path: str = ""
    fcm_enabled: bool = False

    # Phase 3: Vintern VLM
    vintern_api_url: str = ""
    vintern_api_key: str = ""
    vintern_model_name: str = "vintern-1b"
    vintern_confidence_threshold: float = 0.75
    vintern_timeout_seconds: int = 90

    # Phase 3: Gemini
    gemini_model: str = "gemini-2.5-flash"

    # Phase 3: Gmail OAuth (iOS email parsing)
    gmail_client_id: str = ""
    gmail_client_secret: str = ""
    gmail_redirect_uri: str = "http://localhost:8000/api/v1/email/oauth/callback"

    # Phase 4: GPU cost optimization
    smart_track_target_pct: float = 25.0  # target max % hitting expensive tracks
    community_min_distinct_users: int = 3

    cors_origins: list[str] = ["*"]


settings = Settings()
