"""Authentication and request-signing primitives."""
import hashlib
import hmac
import time

import firebase_admin
from firebase_admin import auth as fb_auth
from firebase_admin import credentials

from app.core.config import get_settings
from app.core.errors import UnauthorizedError
from app.core.logging import get_logger

logger = get_logger("leadpilot.security")


def init_firebase_app() -> None:
    """Initialise the Firebase Admin SDK once. Uses the service account file if configured, else ADC."""
    try:
        firebase_admin.get_app()
        return
    except ValueError:
        pass
    settings = get_settings()
    if settings.google_application_credentials:
        cred = credentials.Certificate(settings.google_application_credentials)
    else:
        cred = credentials.ApplicationDefault()
    firebase_admin.initialize_app(cred, {"projectId": settings.firebase_project_id})


def verify_id_token(token: str) -> dict:
    init_firebase_app()
    try:
        return fb_auth.verify_id_token(token)
    except Exception as exc:  # noqa: BLE001
        logger.info("token_verification_failed", extra={"reason": type(exc).__name__})
        raise UnauthorizedError("Invalid or expired credentials.") from exc


def secrets_match(provided: str | None, expected: str) -> bool:
    if not provided or not expected:
        return False
    return hmac.compare_digest(provided.encode(), expected.encode())


def sign_payload(secret: str, timestamp: str, body: bytes) -> str:
    message = timestamp.encode() + b"." + body
    return hmac.new(secret.encode(), message, hashlib.sha256).hexdigest()


def verify_signature(
    secret: str,
    timestamp: str | None,
    body: bytes,
    signature: str | None,
    tolerance_seconds: int = 300,
    now: float | None = None,
) -> bool:
    """Verify `hex(HMAC_SHA256(secret, f"{timestamp}.{body}"))` with replay-window protection."""
    if not secret or not timestamp or not signature:
        return False
    try:
        ts = int(timestamp)
    except ValueError:
        return False
    current = now if now is not None else time.time()
    if abs(current - ts) > tolerance_seconds:
        return False
    expected = sign_payload(secret, timestamp, body)
    provided = signature.strip().lower().removeprefix("sha256=")
    return hmac.compare_digest(expected.encode(), provided.encode())