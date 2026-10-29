"""Lead and inquiry schemas."""
from datetime import datetime

from pydantic import Field

from app.schemas.common import (
    ID_PATTERN,
    CamelModel,
    EmailAddress,
    LeadSource,
    LeadStatus,
    Mode,
    Priority,
    RequestModel,
    Tag,
)
from app.schemas.qualification import QualificationResult
from app.schemas.workflow import ExecutionOut

EVENT_ID_PATTERN = r"^[A-Za-z0-9_.:-]+$"


class LeadCreate(RequestModel):
    customer_name: str = Field(min_length=1, max_length=120)
    customer_email: EmailAddress | None = None
    customer_phone: str | None = Field(default=None, max_length=32)
    company: str | None = Field(default=None, max_length=120)
    source: LeadSource = LeadSource.MANUAL
    message: str = Field(min_length=1, max_length=5000)
    tags: list[Tag] = Field(default_factory=list, max_length=10)
    notes: str | None = Field(default=None, max_length=2000)
    assigned_to: str | None = Field(default=None, pattern=ID_PATTERN)
    qualify: bool = True
    event_id: str | None = Field(default=None, max_length=128, pattern=EVENT_ID_PATTERN)


class LeadUpdate(RequestModel):
    customer_name: str | None = Field(default=None, min_length=1, max_length=120)
    customer_email: EmailAddress | None = None
    customer_phone: str | None = Field(default=None, max_length=32)
    company: str | None = Field(default=None, max_length=120)
    source: LeadSource | None = None
    tags: list[Tag] | None = Field(default=None, max_length=10)
    notes: str | None = Field(default=None, max_length=2000)
    assigned_to: str | None = Field(default=None, pattern=ID_PATTERN)


class LeadStatusChange(RequestModel):
    status: LeadStatus
    note: str | None = Field(default=None, max_length=500)


class LeadOut(CamelModel):
    id: str
    workspace_id: str
    customer_name: str = ""
    customer_email: str | None = None
    customer_phone: str | None = None
    company: str | None = None
    source: LeadSource = LeadSource.OTHER
    message: str = ""
    tags: list[str] = Field(default_factory=list)
    notes: str | None = None
    status: LeadStatus = LeadStatus.NEW
    score: int | None = None
    priority: Priority | None = None
    qualification: QualificationResult | None = None
    assigned_to: str | None = None
    created_by: str | None = None
    event_id: str | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None
    last_contacted_at: datetime | None = None


class StatusHistoryOut(CamelModel):
    id: str
    from_status: LeadStatus | None = None
    to_status: LeadStatus
    changed_by: str
    note: str | None = None
    created_at: datetime | None = None


class InquiryIn(RequestModel):
    """Public inquiry payload (signed webhook or trusted n8n)."""

    customer_name: str | None = Field(default=None, max_length=120)
    customer_email: EmailAddress | None = None
    customer_phone: str | None = Field(default=None, max_length=32)
    company: str | None = Field(default=None, max_length=120)
    source: LeadSource = LeadSource.WEBSITE
    message: str = Field(min_length=1, max_length=5000)
    event_id: str | None = Field(default=None, max_length=128, pattern=EVENT_ID_PATTERN)


class InquiryResponse(CamelModel):
    lead_id: str
    duplicate: bool = False
    status: LeadStatus
    qualification: QualificationResult | None = None
    approval_id: str | None = None
    execution: ExecutionOut | None = None
    mode: Mode