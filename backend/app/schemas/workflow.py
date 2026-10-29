"""Workflow execution schemas."""
from datetime import datetime
from typing import Any, Literal

from pydantic import Field

from app.schemas.common import (
    ID_PATTERN,
    CamelModel,
    ExecutionStatus,
    RequestModel,
    WorkflowType,
)


class WorkflowTriggerRequest(RequestModel):
    workflow: WorkflowType
    lead_id: str | None = Field(default=None, pattern=ID_PATTERN)
    note: str | None = Field(default=None, max_length=500)


class ExecutionOut(CamelModel):
    id: str
    workspace_id: str
    workflow: WorkflowType
    status: ExecutionStatus
    lead_id: str | None = None
    related_id: str | None = None
    attempts: int = 0
    retry_count: int = 0
    triggered_by: str | None = None
    idempotency_key: str | None = None
    started_at: datetime | None = None
    finished_at: datetime | None = None
    latency_ms: int | None = None
    error_message: str | None = None
    response_summary: str | None = None


class ExecutionCallback(RequestModel):
    """Sent by n8n to report the final outcome of a workflow run."""

    status: Literal["success", "failed"]
    message: str | None = Field(default=None, max_length=1000)
    data: dict[str, Any] | None = None


class ErrorReport(RequestModel):
    """Sent by the n8n error-handling workflow."""

    workflow: str = Field(max_length=80)
    message: str = Field(max_length=1000)
    node: str | None = Field(default=None, max_length=120)
    execution_id: str | None = Field(default=None, pattern=ID_PATTERN)
    lead_id: str | None = Field(default=None, pattern=ID_PATTERN)
    retry_status: Literal["will_retry", "exhausted", "not_retryable"] = "not_retryable"


class ExecutionStats(CamelModel):
    total: int = 0
    success: int = 0
    failed: int = 0
    retrying: int = 0
    skipped: int = 0
    in_progress: int = 0


class DailySummary(CamelModel):
    workspace_id: str
    date: str
    new_leads: int = 0
    qualified_leads: int = 0
    high_priority_leads: int = 0
    converted_leads: int = 0
    lost_leads: int = 0
    pending_approvals: int = 0
    bookings_today: int = 0
    failed_executions: int = 0
    ai_requests: int = 0
    estimated_cost_usd: float | None = None
    cost_is_estimate: bool = True
    generated_at: datetime