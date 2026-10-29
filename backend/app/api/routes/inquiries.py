"""Inquiry ingestion: signed public webhook, n8n internal endpoint, authenticated in-app submission."""
from typing import Annotated

from fastapi import APIRouter, Header, Path, Request, Response
from pydantic import ValidationError
from starlette.concurrency import run_in_threadpool

from app.core.config import INQUIRY_SIGNATURE_TOLERANCE_SECONDS, MAX_BODY_BYTES, Settings
from app.core.deps import AppSettings, CallbackAuth, Store, WriterCtx
from app.core.errors import (
    AppError,
    NotFoundError,
    ServiceUnavailableError,
    UnauthorizedError,
    ValidationFailedError,
)
from app.core.security import verify_signature
from app.schemas.common import ID_PATTERN, ActorType
from app.schemas.lead import InquiryIn, InquiryResponse
from app.services.firestore_client import DocumentStore
from app.services.lead_service import process_inquiry

IdPath = Annotated[str, Path(pattern=ID_PATTERN)]
router = APIRouter(tags=["inquiries"])


class PayloadTooLargeError(AppError):
    status_code = 413
    code = "payload_too_large"
    default_message = "The request body is too large."


def _ingest(
    store: DocumentStore, settings: Settings, workspace_id: str, inquiry: InquiryIn,
    actor_type: ActorType, actor_id: str,
) -> InquiryResponse:
    if not store.get(f"workspaces/{workspace_id}"):
        raise NotFoundError("Workspace not found.")
    return process_inquiry(
        store, settings, workspace_id=workspace_id, inquiry=inquiry, actor_type=actor_type, actor_id=actor_id
    )


@router.post("/public/inquiries/{workspace_id}", response_model=InquiryResponse)
async def public_inquiry(
    workspace_id: IdPath,
    request: Request,
    settings: AppSettings,
    store: Store,
    x_leadpilot_timestamp: Annotated[str | None, Header()] = None,
    x_leadpilot_signature: Annotated[str | None, Header()] = None,
):
    """Signed webhook. Signature = hex(HMAC_SHA256(secret, f"{timestamp}.{raw_body}")), timestamp in unix seconds."""
    if not settings.inquiry_hmac_configured:
        raise ServiceUnavailableError(
            "The public inquiry webhook is disabled: INQUIRY_WEBHOOK_SECRET is not set.",
            code="webhook_not_configured",
        )
    raw = await request.body()
    if len(raw) > MAX_BODY_BYTES:
        raise PayloadTooLargeError()
    if not verify_signature(
        settings.inquiry_webhook_secret.get_secret_value(),
        x_leadpilot_timestamp,
        raw,
        x_leadpilot_signature,
        tolerance_seconds=INQUIRY_SIGNATURE_TOLERANCE_SECONDS,
    ):
        raise UnauthorizedError("Invalid or expired signature.", code="invalid_signature")
    try:
        inquiry = InquiryIn.model_validate_json(raw)
    except ValidationError as exc:
        details = [{"loc": [str(p) for p in e["loc"]], "msg": e["msg"]} for e in exc.errors()]
        raise ValidationFailedError("Invalid inquiry payload.", details=details) from None

    response = await run_in_threadpool(
        _ingest, store, settings, workspace_id, inquiry, ActorType.SYSTEM, "inquiry-webhook"
    )
    # Public callers get a minimal acknowledgement, never the AI analysis.
    return response.model_copy(update={"qualification": None, "execution": None})


@router.post("/internal/workspaces/{workspace_id}/inquiries", response_model=InquiryResponse)
def internal_inquiry(
    workspace_id: IdPath, body: InquiryIn, _auth: CallbackAuth, store: Store, settings: AppSettings
):
    """Called by the n8n ingestion workflow (X-LeadPilot-Callback-Secret)."""
    return _ingest(store, settings, workspace_id, body, ActorType.N8N, "n8n")


@router.post("/workspaces/{workspace_id}/inquiries", response_model=InquiryResponse, status_code=201)
def submit_inquiry(
    body: InquiryIn, ctx: WriterCtx, store: Store, settings: AppSettings, response: Response
):
    """In-app submission: validate, qualify with the LLM, queue approval, trigger n8n routing."""
    result = _ingest(store, settings, ctx.workspace_id, body, ActorType.USER, ctx.actor_id)
    if result.duplicate:
        response.status_code = 200
    return result