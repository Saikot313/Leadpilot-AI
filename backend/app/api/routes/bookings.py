"""Booking endpoints. Validation, conflict protection and confirmation happen in the backend."""
from datetime import date, datetime, timedelta, timezone
from typing import Annotated

from fastapi import APIRouter, Path, Query

from app.core.deps import AppSettings, CallbackAuth, MemberCtx, Store, WriterCtx
from app.core.errors import ValidationFailedError
from app.schemas.booking import AvailabilityOut, BookingCancel, BookingOut, BookingRequestIn
from app.schemas.common import ID_PATTERN, BookingStatus, ListResponse, utcnow
from app.services import booking_service

BookingId = Annotated[str, Path(pattern=ID_PATTERN)]
WorkspaceId = Annotated[str, Path(pattern=ID_PATTERN)]
MAX_RANGE_DAYS = 93
router = APIRouter(prefix="/workspaces/{workspace_id}/bookings", tags=["bookings"])
internal_router = APIRouter(prefix="/internal/workspaces/{workspace_id}/bookings", tags=["bookings"])


def _to_utc(value: datetime) -> datetime:
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)


# NOTE: "/availability" is declared before "/{booking_id}" so it is not captured as an ID.
@router.get("/availability", response_model=AvailabilityOut)
def availability(
    ctx: MemberCtx, store: Store, settings: AppSettings, day: Annotated[date, Query(alias="date")]
):
    return booking_service.get_availability(store, settings, ctx.workspace_id, day)


@router.get("", response_model=ListResponse[BookingOut])
def list_bookings(
    ctx: MemberCtx,
    store: Store,
    start: datetime | None = None,
    end: datetime | None = None,
    status: BookingStatus | None = None,
):
    """Defaults to today (UTC) through the next 30 days. Send timezone offsets URL-encoded (+ as %2B)."""
    start_utc = _to_utc(start) if start else utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
    end_utc = _to_utc(end) if end else start_utc + timedelta(days=30)
    if end_utc <= start_utc:
        raise ValidationFailedError("end must be after start.")
    if end_utc - start_utc > timedelta(days=MAX_RANGE_DAYS):
        raise ValidationFailedError(f"The range cannot exceed {MAX_RANGE_DAYS} days.")
    items = booking_service.list_bookings(store, ctx.workspace_id, start=start_utc, end=end_utc, status=status)
    return ListResponse[BookingOut](items=items, count=len(items))


@router.post("", response_model=BookingOut, status_code=201)
def create_booking(body: BookingRequestIn, ctx: WriterCtx, store: Store, settings: AppSettings):
    return booking_service.create_booking(
        store, settings, workspace_id=ctx.workspace_id, user_id=ctx.actor_id, data=body
    )


@router.get("/{booking_id}", response_model=BookingOut)
def get_booking(booking_id: BookingId, ctx: MemberCtx, store: Store):
    return booking_service.get_booking(store, ctx.workspace_id, booking_id)


@router.post("/{booking_id}/confirm", response_model=BookingOut)
def confirm_booking(booking_id: BookingId, ctx: WriterCtx, store: Store, settings: AppSettings):
    return booking_service.confirm_booking(
        store, settings, workspace_id=ctx.workspace_id, user_id=ctx.actor_id, booking_id=booking_id
    )


@router.post("/{booking_id}/cancel", response_model=BookingOut)
def cancel_booking(
    booking_id: BookingId, ctx: WriterCtx, store: Store, body: BookingCancel | None = None
):
    return booking_service.cancel_booking(
        store, workspace_id=ctx.workspace_id, user_id=ctx.actor_id, booking_id=booking_id,
        reason=body.reason if body else None,
    )


@internal_router.get("/{booking_id}", response_model=BookingOut)
def internal_get_booking(workspace_id: WorkspaceId, booking_id: BookingId, _auth: CallbackAuth, store: Store):
    """Read-only. Called by the n8n booking workflow (X-LeadPilot-Callback-Secret) before sending a reminder."""
    return booking_service.get_booking(store, workspace_id, booking_id)