"""FastAPI application entry point: `uvicorn app.main:app`."""
import re
import time
import uuid
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api.router import api_router
from app.api.routes import health
from app.core.config import MAX_BODY_BYTES, get_settings
from app.core.errors import register_exception_handlers
from app.core.logging import configure_logging, get_logger, request_id_ctx
from app.services.firestore_client import get_store

logger = get_logger("leadpilot.app")
_REQUEST_ID_RE = re.compile(r"^[A-Za-z0-9._-]{8,64}$")
_QUIET_PATHS = ("/health",)


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    logger.info(
        "startup",
        extra={
            "mode": settings.mode,
            "environment": settings.app_env,
            "llmConfigured": settings.llm_configured,
            "n8nConfigured": settings.n8n_configured,
            "callbacksConfigured": settings.callbacks_configured,
            "inquiryWebhookConfigured": settings.inquiry_hmac_configured,
        },
    )
    if settings.demo_mode:
        logger.warning("demo_mode_enabled: authentication is bypassed and data is in memory")
    get_store()  # fail fast on bad Firebase credentials (live) or seed demo data (demo)
    yield
    logger.info("shutdown")


def create_app() -> FastAPI:
    settings = get_settings()  # raises a clear error if the environment is invalid
    configure_logging(settings.log_level)
    is_prod = settings.app_env == "production"

    app = FastAPI(
        title="LeadPilot AI API",
        version=health.APP_VERSION,
        description="AI-powered lead qualification and sales automation backend.",
        lifespan=lifespan,
        docs_url=None if is_prod else "/docs",
        redoc_url=None,
        openapi_url=None if is_prod else "/openapi.json",
    )

    @app.middleware("http")
    async def request_context(request: Request, call_next):
        supplied = request.headers.get("x-request-id", "")
        request_id = supplied if _REQUEST_ID_RE.fullmatch(supplied) else uuid.uuid4().hex
        token = request_id_ctx.set(request_id)
        started = time.perf_counter()
        try:
            length = request.headers.get("content-length", "")
            if length.isdigit() and int(length) > MAX_BODY_BYTES:
                response = JSONResponse(
                    status_code=413,
                    content={"error": {
                        "code": "payload_too_large",
                        "message": "The request body is too large.",
                        "requestId": request_id,
                    }},
                )
            else:
                response = await call_next(request)
            response.headers["X-Request-ID"] = request_id
            response.headers["X-Content-Type-Options"] = "nosniff"
            response.headers["Referrer-Policy"] = "no-referrer"
            response.headers["Cache-Control"] = "no-store"
            if not request.url.path.startswith(_QUIET_PATHS):
                logger.info(
                    "request",
                    extra={
                        "method": request.method,
                        "path": request.url.path,  # no query string: it may contain personal data
                        "status": response.status_code,
                        "durationMs": int((time.perf_counter() - started) * 1000),
                    },
                )
            return response
        finally:
            request_id_ctx.reset(token)

    if settings.cors_origin_list:  # native mobile apps do not need CORS; web builds do
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.cors_origin_list,
            allow_credentials=False,
            allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
            allow_headers=["Authorization", "Content-Type", "Idempotency-Key", "X-Request-ID"],
            max_age=600,
        )

    register_exception_handlers(app)
    app.include_router(health.router)
    app.include_router(api_router)
    return app


app = create_app()