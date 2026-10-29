"""Booking schemas."""
from datetime import date, datetime, timezone

from pydantic import Field, field_validator

from app.schemas.common import (
    ID_PATTERN,
    BookingStatus,
    CamelModel,
    EmailAddress,
    RequestModel,
)


class BookingRequestIn(RequestModel):
    lead_id: str | None = Field(default=None, pattern=ID_PATTERN)
    customer_name: str = Field(min_length=1, max_length=120)
    customer_email: EmailAddress | None = None
    start_at: datetime
    duration_minutes: int = Field(default=30, ge=10, le=240)
    notes: str | None = Field(default=None, max_length=1000)

    @field_validator("start_at")
    @classmethod
    def _require_timezone(cls, v: datetime) -> datetime:
        if v.tzinfo is None:
            raise ValueError("startAt must include a timezone offset, e.g. 2026-11-05T10:00:00+06:00")
        return v.astimezone(timezone.utc)


class BookingCancel(RequestModel):
    reason: str | None = Field(default=None, max_length=300)


class BookingOut(CamelModel):
    id: str
    workspace_id: str
    lead_id: str | None = None
    customer_name: str = ""
    customer_email: str | None = None
    start_at: datetime
    end_at: datetime
    duration_minutes: int
    status: BookingStatus
    notes: str | None = None
    created_by: str | None = None
    created_at: datetime | None = None
    confirmed_by: str | None = None
    confirmed_at: datetime | None = None
    cancelled_reason: str | None = None


class SlotOut(CamelModel):
    start_at: datetime
    end_at: datetime
    available: bool


class AvailabilityOut(CamelModel):
    date: date
    timezone: str
    slot_minutes: int
    slots: list[SlotOut]