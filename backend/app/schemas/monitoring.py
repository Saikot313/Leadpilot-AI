"""Monitoring schemas. Measured values and estimates are labeled separately."""
from datetime import datetime
from typing import Any

from pydantic import Field

from app.schemas.common import ActorType, CamelModel, Mode, UsageKind
from app.schemas.workflow import ExecutionStats


class UsageRecordOut(CamelModel):
    id: str
    kind: UsageKind
    provider: str
    model: str
    success: bool = True
    error_code: str | None = None
    lead_id: str | None = None
    requested_by: str | None = None
    input_tokens: int | None = None
    output_tokens: int | None = None
    total_tokens: int | None = None
    tokens_measured: bool = False
    latency_ms: int | None = None
    estimated_cost_usd: float | None = None
    cost_is_estimate: bool = True
    created_at: datetime | None = None


class ModelUsage(CamelModel):
    provider: str
    model: str
    requests: int = 0
    measured_input_tokens: int = 0
    measured_output_tokens: int = 0
    estimated_cost_usd: float | None = None


class UsageSummary(CamelModel):
    period_days: int
    total_requests: int = 0
    successful_requests: int = 0
    failed_requests: int = 0
    requests_without_token_data: int = 0
    measured_input_tokens: int = 0
    measured_output_tokens: int = 0
    estimated_cost_usd: float | None = None
    cost_note: str = ""
    avg_latency_ms: float | None = None
    by_model: list[ModelUsage] = Field(default_factory=list)
    monthly_budget_usd: float | None = None
    budget_used_pct: float | None = None


class ErrorLogOut(CamelModel):
    id: str
    source: str
    code: str | None = None
    message: str
    workflow: str | None = None
    execution_id: str | None = None
    lead_id: str | None = None
    retry_status: str | None = None
    created_at: datetime | None = None


class ActivityLogOut(CamelModel):
    id: str
    actor_type: ActorType
    actor_id: str | None = None
    action: str
    entity_type: str | None = None
    entity_id: str | None = None
    summary: str = ""
    metadata: dict[str, Any] = Field(default_factory=dict)
    created_at: datetime | None = None


class ServiceStatus(CamelModel):
    name: str
    configured: bool
    detail: str = ""


class IntegrationStatusOut(CamelModel):
    mode: Mode
    llm_provider: str
    llm_model: str
    services: list[ServiceStatus]


class MonitoringOverview(CamelModel):
    executions: ExecutionStats
    usage: UsageSummary
    errors_last_24h: int = 0
    integrations: IntegrationStatusOut