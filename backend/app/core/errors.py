"""Application errors and exception handlers."""
from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.core.logging import get_logger, request_id_ctx

logger = get_logger("leadpilot.errors")


class AppError(Exception):
    status_code = 500
    code = "internal_error"
    default_message = "An unexpected error occurred."

    def __init__(self, message: str | None = None, *, code: str | None = None, details: Any = None):
        self.message = message or self.default_message
        super().__init__(self.message)
        if code:
            self.code = code
        self.details = details


class UnauthorizedError(AppError):
    status_code = 401
    code = "unauthorized"
    default_message = "Authentication required."


class ForbiddenError(AppError):
    status_code = 403
    code = "forbidden"
    default_message = "You do not have permission to perform this action."


class NotFoundError(AppError):
    status_code = 404
    code = "not_found"
    default_message = "Resource not found."


class ConflictError(AppError):
    status_code = 409
    code = "conflict"
    default_message = "The request conflicts with the current state."


class ValidationFailedError(AppError):
    status_code = 422
    code = "validation_error"
    default_message = "The request could not be validated."


class RateLimitedError(AppError):
    status_code = 429
    code = "rate_limited"
    default_message = "Too many requests. Please retry later."


class UpstreamError(AppError):
    status_code = 502
    code = "upstream_error"
    default_message = "An upstream service failed."


class ServiceUnavailableError(AppError):
    status_code = 503
    code = "service_unavailable"
    default_message = "The service is not available or not configured."


def _body(code: str, message: str, details: Any = None) -> dict:
    error: dict[str, Any] = {"code": code, "message": message, "requestId": request_id_ctx.get()}
    if details is not None:
        error["details"] = details
    return {"error": error}


def register_exception_handlers(app: FastAPI) -> None:
    @app.exception_handler(AppError)
    async def handle_app_error(request: Request, exc: AppError) -> JSONResponse:
        level = logger.error if exc.status_code >= 500 else logger.info
        level("app_error", extra={"code": exc.code, "status": exc.status_code, "path": request.url.path})
        return JSONResponse(status_code=exc.status_code, content=_body(exc.code, exc.message, exc.details))

    @app.exception_handler(RequestValidationError)
    async def handle_validation(request: Request, exc: RequestValidationError) -> JSONResponse:
        details = [
            {"loc": [str(p) for p in e.get("loc", [])], "msg": e.get("msg", ""), "type": e.get("type", "")}
            for e in exc.errors()
        ]
        return JSONResponse(status_code=422, content=_body("validation_error", "Invalid request.", details))

    @app.exception_handler(StarletteHTTPException)
    async def handle_http(request: Request, exc: StarletteHTTPException) -> JSONResponse:
        return JSONResponse(
            status_code=exc.status_code,
            content=_body(f"http_{exc.status_code}", str(exc.detail)),
            headers=getattr(exc, "headers", None),
        )

    @app.exception_handler(Exception)
    async def handle_unexpected(request: Request, exc: Exception) -> JSONResponse:
        logger.exception("unhandled_exception", extra={"path": request.url.path})
        return JSONResponse(
            status_code=500,
            content=_body("internal_error", "An unexpected error occurred."),
        )