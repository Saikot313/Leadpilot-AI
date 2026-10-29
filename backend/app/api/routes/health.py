"""Health endpoints (root level, outside /api/v1)."""
from fastapi import APIRouter, Response

from app.core.deps import AppSettings
from app.core.logging import get_logger
from app.schemas.common import utcnow
from app.services.firestore_client import get_store

APP_VERSION = "1.0.0"

logger = get_logger("leadpilot.health")
router = APIRouter(tags=["health"])


@router.get("/health")
def health(settings: AppSettings) -> dict:
    """Liveness: the process is up. Does not touch external services."""
    return {
        "status": "ok",
        "service": "leadpilot-api",
        "version": APP_VERSION,
        "mode": settings.mode,
        "environment": settings.app_env,
        "time": utcnow().isoformat(),
    }


@router.get("/health/ready")
def ready(settings: AppSettings, response: Response) -> dict:
    """Readiness: the document store can be reached."""
    try:
        get_store().get("healthcheck/ping")
    except Exception:  # noqa: BLE001
        logger.exception("readiness_check_failed")
        response.status_code = 503
        return {"status": "unavailable", "database": "unreachable", "mode": settings.mode}
    return {
        "status": "ready",
        "database": "in-memory (demo)" if settings.demo_mode else "firestore",
        "mode": settings.mode,
    }