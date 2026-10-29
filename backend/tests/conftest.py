"""Test environment. Must set variables BEFORE any `app` import so settings are deterministic."""
import os

os.environ.update(
    {
        "DEMO_MODE": "true",
        "APP_ENV": "development",
        "LOG_LEVEL": "WARNING",
        "FIREBASE_PROJECT_ID": "",
        "GOOGLE_APPLICATION_CREDENTIALS": "",
        "LLM_PROVIDER": "gemini",
        "GEMINI_API_KEY": "",
        "OPENAI_API_KEY": "",
        "LLM_INPUT_PRICE_PER_1M": "",
        "LLM_OUTPUT_PRICE_PER_1M": "",
        "N8N_SHARED_SECRET": "",
        "BACKEND_CALLBACK_SECRET": "test-callback-secret",
        "INQUIRY_WEBHOOK_SECRET": "test-inquiry-secret",
        "BOOKING_SLOT_MINUTES": "30",
        "BOOKING_DAY_START_HOUR": "9",
        "BOOKING_DAY_END_HOUR": "17",
        "BOOKING_TIMEZONE": "Asia/Dhaka",
        "CORS_ORIGINS": "",
    }
)

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app.services.firestore_client import get_store  # noqa: E402

WS = "demo-workspace"
BASE = f"/api/v1/workspaces/{WS}"


@pytest.fixture(autouse=True)
def fresh_store():
    """Every test gets a newly seeded in-memory store."""
    get_store.cache_clear()
    yield
    get_store.cache_clear()


@pytest.fixture
def client():
    from app.main import app

    return TestClient(app)