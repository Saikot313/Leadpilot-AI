"""Booking management. The backend validates and confirms every booking."""
from __future__ import annotations

import math
from datetime import date, datetime, time, timedelta, timezone
from typing import Any
from zoneinfo import ZoneInfo

from app.core.config import Settings
from app.core.errors import AppError, ConflictError, NotFoundError, ValidationFailedError
from app.schemas.booking import AvailabilityOut, BookingOut, BookingRequestIn, SlotOut
from app.schemas.common import ActorType, BookingStatus, LeadStatus, WorkflowType, utcnow
from app.services.audit_service import log_activity
from app.services.firestore_client import DocumentStore, new_id
from app.services.lead_service import change_status
from app.services.n8n_client import trigger_workflow


def _tz(settings: Settings) -> ZoneInfo:
    return ZoneInfo(settings.booking_timezone)


def slot_key(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y%m%dT%H%M")


def slot_starts(start_utc: datetime, duration_minutes: int, slot_minutes: int) -> list[datetime]:
    count = math.ceil(duration_minutes / slot_minutes)
    return [start_utc + timedelta(minutes=slot_minutes * i) for i in range(count)]


def _day_bounds(settings: Settings, day: date) -> tuple[datetime, datetime]:
    midnight = datetime.combine(day, time(0), tzinfo=_tz(settings))
    return (
        midnight + timedelta(hours=settings.booking_day_start_hour),
        midnight + timedelta(hours=settings.booking_day_end_hour),
    )


def validate_window(
    settings: Settings, start_utc: datetime, duration_minutes: int, now: datetime | None = None
) -> tuple[datetime, int]:
    """Validate a requested window. Returns (end_utc, reserved_minutes). Duration is rounded up to whole slots."""
    now = now or utcnow()
    if start_utc <= now:
        raise ValidationFailedError("Bookings must start in the future.", code="booking_in_past")
    slot = settings.booking_slot_minutes
    local_start = start_utc.astimezone(_tz(settings))
    if local_start.minute % slot or local_start.second or local_start.microsecond:
        raise ValidationFailedError(f"Start time must align to {slot}-minute slots.", code="booking_misaligned")
    reserved = math.ceil(duration_minutes / slot) * slot
    end_utc = start_utc + timedelta(minutes=reserved)
    day_open, day_close = _day_bounds(settings, local_start.date())
    if local_start < day_open or end_utc.astimezone(_tz(settings)) > day_close:
        raise ValidationFailedError(
            f"Bookings are available {settings.booking_day_start_hour:02d}:00 to "
            f"{settings.booking_day_end_hour:02d}:00 ({settings.booking_timezone}).",
            code="booking_outside_hours",
        )
    return end_utc, reserved


def _path(workspace_id: str, booking_id: str) -> str:
    return f"workspaces/{workspace_id}/bookings/{booking_id}"


def _to_out(doc: dict[str, Any], workspace_id: str) -> BookingOut:
    return BookingOut.model_validate({**doc, "workspaceId": workspace_id})


def get_booking(store: DocumentStore, workspace_id: str, booking_id: str) -> BookingOut:
    doc = store.get(_path(workspace_id, booking_id))
    if not doc:
        raise NotFoundError("Booking not found.")
    return _to_out(doc, workspace_id)


def list_bookings(
    store: DocumentStore,
    workspace_id: str,
    *,
    start: datetime,
    end: datetime,
    status: BookingStatus | None = None,
) -> list[BookingOut]:
    rows = store.list(
        f"workspaces/{workspace_id}/bookings",
        filters=[("startAt", ">=", start), ("startAt", "<", end)],
        order_by="startAt",
    )
    if status:
        rows = [r for r in rows if r.get("status") == status.value]
    return [_to_out(r, workspace_id) for r in rows]


def get_availability(store: DocumentStore, settings: Settings, workspace_id: str, day: date) -> AvailabilityOut:
    day_open, day_close = _day_bounds(settings, day)
    open_utc, close_utc = day_open.astimezone(timezone.utc), day_close.astimezone(timezone.utc)
    taken = {
        r["id"]
        for r in store.list(
            f"workspaces/{workspace_id}/bookingSlots",
            filters=[("startAt", ">=", open_utc), ("startAt", "<", close_utc)],
        )
    }
    now = utcnow()
    step = timedelta(minutes=settings.booking_slot_minutes)
    slots: list[SlotOut] = []
    cursor = open_utc
    while cursor + step <= close_utc:
        slots.append(
            SlotOut(start_at=cursor, end_at=cursor + step, available=slot_key(cursor) not in taken and cursor > now)
        )
        cursor += step
    return AvailabilityOut(
        date=day, timezone=settings.booking_timezone, slot_minutes=settings.booking_slot_minutes, slots=slots
    )


def create_booking(
    store: DocumentStore, settings: Settings, *, workspace_id: str, user_id: str, data: BookingRequestIn
) -> BookingOut:
    end_utc, reserved = validate_window(settings, data.start_at, data.duration_minutes)
    if data.lead_id and not store.get(f"workspaces/{workspace_id}/leads/{data.lead_id}"):
        raise NotFoundError("Lead not found.")

    starts = slot_starts(data.start_at, reserved, settings.booking_slot_minutes)
    keys = [slot_key(s) for s in starts]
    booking_id = new_id()
    ops: list[tuple[str, str, dict[str, Any] | None]] = [
        ("create", f"workspaces/{workspace_id}/bookingSlots/{k}",
         {"workspaceId": workspace_id, "bookingId": booking_id, "startAt": s})
        for k, s in zip(keys, starts)
    ]
    ops.append((
        "create", _path(workspace_id, booking_id),
        {
            "workspaceId": workspace_id, "leadId": data.lead_id, "customerName": data.customer_name,
            "customerEmail": data.customer_email, "startAt": data.start_at, "endAt": end_utc,
            "durationMinutes": reserved, "status": BookingStatus.PENDING, "notes": data.notes,
            "slotKeys": keys, "createdBy": user_id, "createdAt": utcnow(),
            "confirmedBy": None, "confirmedAt": None, "cancelledReason": None,
        },
    ))
    try:
        store.batch(ops)  # atomic: if any slot document already exists, nothing is written
    except ConflictError:
        raise ConflictError("That time is no longer available.", code="slot_unavailable") from None

    log_activity(
        store, workspace_id, actor_type=ActorType.USER, actor_id=user_id, action="booking.requested",
        entity_type="booking", entity_id=booking_id, summary="Booking requested",
        metadata={"leadId": data.lead_id, "durationMinutes": reserved},
    )
    return get_booking(store, workspace_id, booking_id)


def confirm_booking(
    store: DocumentStore, settings: Settings, *, workspace_id: str, user_id: str, booking_id: str
) -> BookingOut:
    doc = store.get(_path(workspace_id, booking_id))
    if not doc:
        raise NotFoundError("Booking not found.")
    if doc.get("status") != BookingStatus.PENDING:
        raise ConflictError("Only pending bookings can be confirmed.", code="invalid_booking_state")
    if doc["startAt"] <= utcnow():
        raise ConflictError("The booking start time has already passed.", code="booking_in_past")

    claimed = store.compare_and_update(
        _path(workspace_id, booking_id), {"status": "pending"},
        {"status": BookingStatus.CONFIRMED, "confirmedBy": user_id, "confirmedAt": utcnow()},
    )
    if not claimed:
        raise ConflictError("The booking was changed at the same time. Refresh and try again.", code="concurrent_update")

    lead_id = doc.get("leadId")
    if lead_id:
        try:
            change_status(
                store, workspace_id=workspace_id, lead_id=lead_id, target=LeadStatus.MEETING_BOOKED,
                actor_type=ActorType.USER, actor_id=user_id, note="Booking confirmed",
            )
        except AppError:
            pass  # lead already past this stage; the booking itself is still valid

    log_activity(
        store, workspace_id, actor_type=ActorType.USER, actor_id=user_id, action="booking.confirmed",
        entity_type="booking", entity_id=booking_id, summary="Booking confirmed",
    )
    trigger_workflow(
        store, settings, workspace_id=workspace_id, workflow=WorkflowType.BOOKING_PROCESSING,
        payload={
            "bookingId": booking_id, "leadId": lead_id, "customerName": doc.get("customerName"),
            "customerEmail": doc.get("customerEmail"), "startAt": doc["startAt"].isoformat(),
            "endAt": doc["endAt"].isoformat(), "timezone": settings.booking_timezone,
        },
        triggered_by=user_id, idempotency_key=f"booking-confirm:{booking_id}", lead_id=lead_id, related_id=booking_id,
    )
    return get_booking(store, workspace_id, booking_id)


def cancel_booking(
    store: DocumentStore, *, workspace_id: str, user_id: str, booking_id: str, reason: str | None = None
) -> BookingOut:
    doc = store.get(_path(workspace_id, booking_id))
    if not doc:
        raise NotFoundError("Booking not found.")
    current = doc.get("status")
    if current == BookingStatus.CANCELLED:
        raise ConflictError("The booking is already cancelled.", code="invalid_booking_state")
    claimed = store.compare_and_update(
        _path(workspace_id, booking_id), {"status": str(current)},
        {"status": BookingStatus.CANCELLED, "cancelledReason": reason},
    )
    if not claimed:
        raise ConflictError("The booking was changed at the same time. Refresh and try again.", code="concurrent_update")
    store.batch([("delete", f"workspaces/{workspace_id}/bookingSlots/{k}", None) for k in doc.get("slotKeys", [])])
    log_activity(
        store, workspace_id, actor_type=ActorType.USER, actor_id=user_id, action="booking.cancelled",
        entity_type="booking", entity_id=booking_id, summary="Booking cancelled",
    )
    return get_booking(store, workspace_id, booking_id)