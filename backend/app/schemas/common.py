"""Shared enums, base models, and helpers."""
import re
from datetime import datetime, timezone
from enum import StrEnum
from typing import Annotated, Generic, Literal, TypeVar

from pydantic import AfterValidator, BaseModel, ConfigDict, StringConstraints
from pydantic.alias_generators import to_camel

ID_PATTERN = r"^[A-Za-z0-9_-]{1,128}$"
Mode = Literal["live", "demo"]


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


# ---------- Base models ----------
class CamelModel(BaseModel):
    """camelCase JSON; accepts snake_case too. Unknown fields ignored."""

    model_config = ConfigDict(
        alias_generator=to_camel,
        populate_by_name=True,
        str_strip_whitespace=True,
    )


class RequestModel(CamelModel):
    """Request bodies reject unknown fields."""

    model_config = ConfigDict(extra="forbid")


T = TypeVar("T")


class ListResponse(CamelModel, Generic[T]):
    items: list[T]
    count: int


# ---------- Validators ----------
_EMAIL_RE = re.compile(r"[^@\s]+@[^@\s]+\.[^@\s]{2,}")


def _check_email(value: str) -> str:
    value = value.strip().lower()
    if len(value) > 254 or not _EMAIL_RE.fullmatch(value):
        raise ValueError("Invalid email address")
    return value


EmailAddress = Annotated[str, AfterValidator(_check_email)]
Tag = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=30)]


# ---------- Enums ----------
class Role(StrEnum):
    OWNER = "owner"
    ADMIN = "admin"
    AGENT = "agent"
    VIEWER = "viewer"


class LeadStatus(StrEnum):
    NEW = "new"
    QUALIFIED = "qualified"
    CONTACTED = "contacted"
    MEETING_BOOKED = "meeting_booked"
    CONVERTED = "converted"
    LOST = "lost"


class Priority(StrEnum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"


class Urgency(StrEnum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    UNSPECIFIED = "unspecified"


class LeadSource(StrEnum):
    WEBSITE = "website"
    EMAIL = "email"
    WHATSAPP = "whatsapp"
    REFERRAL = "referral"
    SOCIAL = "social"
    PHONE = "phone"
    MANUAL = "manual"
    WEBHOOK = "webhook"
    PLAYGROUND = "playground"
    OTHER = "other"


class NextAction(StrEnum):
    SEND_FOLLOWUP = "send_followup"
    REQUEST_INFORMATION = "request_information"
    BOOK_MEETING = "book_meeting"
    HUMAN_HANDOFF = "human_handoff"
    NURTURE = "nurture"
    DISQUALIFY = "disqualify"


class ApprovalStatus(StrEnum):
    PENDING = "pending"
    APPROVED = "approved"  # approved by a human, external action not executed
    REJECTED = "rejected"
    EXECUTED = "executed"
    FAILED = "failed"


class ApprovalAction(StrEnum):
    SEND_FOLLOWUP = "send_followup"
    UPDATE_STATUS = "update_status"


class ExecutionStatus(StrEnum):
    QUEUED = "queued"
    RUNNING = "running"
    SUCCESS = "success"
    FAILED = "failed"
    RETRYING = "retrying"
    SKIPPED = "skipped"  # e.g. n8n not configured


class WorkflowType(StrEnum):
    INQUIRY_INGESTION = "inquiry_ingestion"
    AI_QUALIFICATION = "ai_qualification"
    LEAD_ROUTING = "lead_routing"
    FOLLOWUP_DRAFT = "followup_draft"
    OUTBOUND_ACTION = "outbound_action"
    BOOKING_PROCESSING = "booking_processing"
    ERROR_NOTIFICATION = "error_notification"
    DAILY_SUMMARY = "daily_summary"


class BookingStatus(StrEnum):
    PENDING = "pending"
    CONFIRMED = "confirmed"
    CANCELLED = "cancelled"


class FollowupStatus(StrEnum):
    OPEN = "open"
    DONE = "done"
    CANCELLED = "cancelled"


class ActorType(StrEnum):
    USER = "user"
    AI = "ai"
    SYSTEM = "system"
    N8N = "n8n"


class UsageKind(StrEnum):
    QUALIFICATION = "qualification"
    PLAYGROUND = "playground"
    FOLLOWUP_DRAFT = "followup_draft"


# ---------- Pipeline rules ----------
ALLOWED_TRANSITIONS: dict[LeadStatus, set[LeadStatus]] = {
    LeadStatus.NEW: {LeadStatus.QUALIFIED, LeadStatus.CONTACTED, LeadStatus.MEETING_BOOKED, LeadStatus.LOST},
    LeadStatus.QUALIFIED: {
        LeadStatus.NEW, LeadStatus.CONTACTED, LeadStatus.MEETING_BOOKED, LeadStatus.CONVERTED, LeadStatus.LOST,
    },
    LeadStatus.CONTACTED: {
        LeadStatus.QUALIFIED, LeadStatus.MEETING_BOOKED, LeadStatus.CONVERTED, LeadStatus.LOST,
    },
    LeadStatus.MEETING_BOOKED: {LeadStatus.CONTACTED, LeadStatus.CONVERTED, LeadStatus.LOST},
    LeadStatus.CONVERTED: set(),
    LeadStatus.LOST: {LeadStatus.NEW},
}


def can_transition(current: LeadStatus, target: LeadStatus) -> bool:
    return target in ALLOWED_TRANSITIONS.get(current, set())


def score_to_priority(score: int) -> Priority:
    """Deterministic backend mapping. Never trust the model's own priority label."""
    if score >= 70:
        return Priority.HIGH
    if score >= 40:
        return Priority.MEDIUM
    return Priority.LOW