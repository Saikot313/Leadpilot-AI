"""Environment-based application settings."""
from functools import lru_cache
from typing import Literal
from zoneinfo import ZoneInfo

from pydantic import SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

API_PREFIX = "/api/v1"
DEMO_USER_ID = "demo-user"
DEMO_WORKSPACE_ID = "demo-workspace"
MAX_BODY_BYTES = 32_768
INQUIRY_SIGNATURE_TOLERANCE_SECONDS = 300


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # App
    app_env: Literal["development", "staging", "production"] = "development"
    log_level: str = "INFO"
    cors_origins: str = ""
    demo_mode: bool = True

    # Firebase
    firebase_project_id: str = ""
    google_application_credentials: str = ""

    # LLM
    llm_provider: Literal["gemini", "openai"] = "gemini"
    gemini_api_key: SecretStr = SecretStr("")
    gemini_model: str = "gemini-2.0-flash"
    openai_api_key: SecretStr = SecretStr("")
    openai_model: str = "gpt-4o-mini"
    llm_timeout_seconds: float = 30.0
    llm_max_retries: int = 2
    llm_input_price_per_1m: float | None = None
    llm_output_price_per_1m: float | None = None

    # n8n
    n8n_base_url: str = "http://localhost:5678"
    n8n_timeout_seconds: float = 15.0
    n8n_max_retries: int = 2
    n8n_shared_secret: SecretStr = SecretStr("")
    backend_callback_secret: SecretStr = SecretStr("")

    # Public inquiry webhook
    inquiry_webhook_secret: SecretStr = SecretStr("")

    # Booking rules
    booking_slot_minutes: int = 30
    booking_day_start_hour: int = 9
    booking_day_end_hour: int = 17
    booking_timezone: str = "Asia/Dhaka"

    @field_validator("llm_input_price_per_1m", "llm_output_price_per_1m", mode="before")
    @classmethod
    def _empty_price_to_none(cls, v):
        return None if v in ("", None) else v

    @field_validator("log_level")
    @classmethod
    def _upper_level(cls, v: str) -> str:
        return v.upper()

    @model_validator(mode="after")
    def _validate_settings(self) -> "Settings":
        if self.app_env == "production" and self.demo_mode:
            raise ValueError("DEMO_MODE must be false when APP_ENV=production.")
        if not self.demo_mode and not self.firebase_project_id:
            raise ValueError("FIREBASE_PROJECT_ID is required when DEMO_MODE=false.")
        if not (0 <= self.booking_day_start_hour < self.booking_day_end_hour <= 24):
            raise ValueError("Booking hours must satisfy 0 <= start < end <= 24.")
        if self.booking_slot_minutes <= 0 or 60 % self.booking_slot_minutes != 0:
            raise ValueError("BOOKING_SLOT_MINUTES must divide 60 evenly (e.g. 15, 30, 60).")
        try:
            ZoneInfo(self.booking_timezone)
        except Exception as exc:  # noqa: BLE001
            raise ValueError(f"Unknown BOOKING_TIMEZONE: {self.booking_timezone}") from exc
        return self

    # ---- Derived helpers ----
    @property
    def mode(self) -> str:
        return "demo" if self.demo_mode else "live"

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]

    @property
    def llm_api_key(self) -> str:
        key = self.gemini_api_key if self.llm_provider == "gemini" else self.openai_api_key
        return key.get_secret_value()

    @property
    def llm_model(self) -> str:
        return self.gemini_model if self.llm_provider == "gemini" else self.openai_model

    @property
    def llm_configured(self) -> bool:
        return bool(self.llm_api_key)

    @property
    def n8n_configured(self) -> bool:
        return bool(self.n8n_shared_secret.get_secret_value()) and bool(self.n8n_base_url)

    @property
    def callbacks_configured(self) -> bool:
        return bool(self.backend_callback_secret.get_secret_value())

    @property
    def inquiry_hmac_configured(self) -> bool:
        return bool(self.inquiry_webhook_secret.get_secret_value())

    @property
    def pricing_configured(self) -> bool:
        return self.llm_input_price_per_1m is not None and self.llm_output_price_per_1m is not None


@lru_cache
def get_settings() -> Settings:
    return Settings()