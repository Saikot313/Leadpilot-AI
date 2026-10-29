"""Approval schemas."""
from datetime import datetime
from typing import Any, Literal

from pydantic import Field

from app.schemas.common import ApprovalAction, ApprovalStatus, CamelModel, RequestModel


class ApprovalOut(CamelModel):
    id: str
    workspace_id: str
    action_type: ApprovalAction
    status: ApprovalStatus
    title: str
    description: str | None = None
    lead_id: str | None = None
    payload: dict[str, Any] = Field(default_factory=dict)
    safety_flags: list[str] = Field(default_factory=list)
    requested_by: str = "ai"
    created_at: datetime | None = None
    decided_by: str | None = None
    decided_at: datetime | None = None
    decision_note: str | None = None
    execution_id: str | None = None
    result_message: str | None = None


class ApprovalDecision(RequestModel):
    decision: Literal["approve", "reject"]
    note: str | None = Field(default=None, max_length=500)
    edited_subject: str | None = Field(default=None, min_length=1, max_length=200)
    edited_body: str | None = Field(default=None, min_length=1, max_length=5000)