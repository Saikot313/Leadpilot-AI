"""Monitoring endpoints. Measured values and estimates are labeled separately in every response."""
from datetime import datetime, time, timedelta, timezone
from typing import Annotated
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Path, Query

from app.core.config import Settings
from app.core.deps import AppSettings, CallbackAuth, ManagerCtx, MemberCtx, Store
from app.core.errors import NotFoundError
from app.schemas.common import ID_PATTERN, ActorType, ExecutionStatus, ListResponse, utcnow
from app.schemas.monitoring import (
    ActivityLogOut,
    ErrorLogOut,
    IntegrationStatusOut,
    MonitoringOverview,
    ServiceStatus,
    UsageRecordOut,
    UsageSummary,
)
from app.schemas.workflow import DailySummary, ExecutionStats
from app.services.audit_service import list_activity, list_errors
from app.services.cost_estimator import summarize_usage
from app.services.firestore_client import DocumentStore
from app.services.lead_service import QUALIFIED_MIN_SCORE
from app.services.qualification_service import get_agent_config

IdPath = Annotated[str, Path(pattern=ID_PATTERN)]
router = APIRouter(tags=["monitoring"])


# ---------- Helpers ----------
def _usage_rows(store: DocumentStore, workspace_id: str, since: datetime, limit: int = 5000) -> list[dict]:
    return store.list(
        f"workspaces/{workspace_id}/usage",
        filters=[("createdAt", ">=", since)], order_by="createdAt", descending=True, limit=limit,
    )


def _usage_summary(store: DocumentStore, workspace_id: str, days: int) -> UsageSummary:
    rows = _usage_rows(store, workspace_id, utcnow() - timedelta(days=days))
    # A budget percentage is only meaningful for a 30-day window.
    budget = get_agent_config(store, workspace_id).monthly_budget_usd if days == 30 else None
    return summarize_usage(rows, period_days=days, monthly_budget_usd=budget)


def _execution_stats(rows: list[dict]) -> ExecutionStats:
    stats = ExecutionStats(total=len(rows))
    for row in rows:
        status = row.get("status")
        if status == ExecutionStatus.SUCCESS:
            stats.success += 1
        elif status == ExecutionStatus.FAILED:
            stats.failed += 1
        elif status == ExecutionStatus.RETRYING:
            stats.retrying += 1
        elif status == ExecutionStatus.SKIPPED:
            stats.skipped += 1
        else:
            stats.in_progress += 1
    return stats


def integration_status(settings: Settings) -> IntegrationStatusOut:
    services = [
        ServiceStatus(
            name="Database", configured=not settings.demo_mode,
            detail="Cloud Firestore" if not settings.demo_mode else "Demo mode: in-memory data, reset on restart.",
        ),
        ServiceStatus(
            name="LLM provider", configured=settings.llm_configured,
            detail=f"{settings.llm_provider} / {settings.llm_model}" if settings.llm_configured
            else ("No API key: demo rule-based fallback is active." if settings.demo_mode
                  else "No API key: AI endpoints return 503."),
        ),
        ServiceStatus(
            name="Cost estimation", configured=settings.pricing_configured,
            detail="Estimates use the prices you configured." if settings.pricing_configured
            else "Set LLM_INPUT_PRICE_PER_1M and LLM_OUTPUT_PRICE_PER_1M to enable cost estimates.",
        ),
        ServiceStatus(
            name="n8n automation", configured=settings.n8n_configured,
            detail="Workflow webhooks enabled." if settings.n8n_configured
            else "N8N_SHARED_SECRET is empty: workflow runs are recorded as skipped.",
        ),
        ServiceStatus(
            name="n8n callbacks", configured=settings.callbacks_configured,
            detail="Internal endpoints enabled." if settings.callbacks_configured
            else "BACKEND_CALLBACK_SECRET is empty: /internal endpoints return 503.",
        ),
        ServiceStatus(
            name="Public inquiry webhook", configured=settings.inquiry_hmac_configured,
            detail="Signed submissions accepted." if settings.inquiry_hmac_configured
            else "INQUIRY_WEBHOOK_SECRET is empty: the public endpoint returns 503.",
        ),
    ]
    return IntegrationStatusOut(
        mode=settings.mode, llm_provider=settings.llm_provider, llm_model=settings.llm_model, services=services
    )


def build_daily_summary(store: DocumentStore, settings: Settings, workspace_id: str) -> DailySummary:
    tz = ZoneInfo(settings.booking_timezone)
    day_start = datetime.combine(datetime.now(tz).date(), time(0), tzinfo=tz)
    start_utc = day_start.astimezone(timezone.utc)
    end_utc = (day_start + timedelta(days=1)).astimezone(timezone.utc)
    base = f"workspaces/{workspace_id}"

    created = store.list(f"{base}/leads", filters=[("createdAt", ">=", start_utc)], limit=2000)
    touched = store.list(f"{base}/leads", filters=[("updatedAt", ">=", start_utc)], limit=2000)
    pending = store.list(f"{base}/approvals", filters=[("status", "==", "pending")], limit=1000)
    bookings = store.list(
        f"{base}/bookings", filters=[("startAt", ">=", start_utc), ("startAt", "<", end_utc)]
    )
    executions = store.list(f"{base}/executions", filters=[("startedAt", ">=", start_utc)], limit=2000)
    usage = _usage_rows(store, workspace_id, start_utc)
    costs = [r["estimatedCostUsd"] for r in usage if r.get("estimatedCostUsd") is not None]

    return DailySummary(
        workspace_id=workspace_id,
        date=day_start.date().isoformat(),
        new_leads=len(created),
        qualified_leads=sum(1 for r in created if (r.get("score") or -1) >= QUALIFIED_MIN_SCORE),
        high_priority_leads=sum(1 for r in created if r.get("priority") == "high"),
        converted_leads=sum(1 for r in touched if r.get("status") == "converted"),
        lost_leads=sum(1 for r in touched if r.get("status") == "lost"),
        pending_approvals=len(pending),
        bookings_today=sum(1 for r in bookings if r.get("status") != "cancelled"),
        failed_executions=sum(1 for r in executions if r.get("status") == "failed"),
        ai_requests=len(usage),
        estimated_cost_usd=round(sum(costs), 6) if costs else None,
        cost_is_estimate=True,
        generated_at=utcnow(),
    )


# ---------- Manager endpoints ----------
@router.get("/workspaces/{workspace_id}/monitoring/overview", response_model=MonitoringOverview)
def overview(
    ctx: ManagerCtx, store: Store, settings: AppSettings, days: int = Query(default=7, ge=1, le=90)
):
    since = utcnow() - timedelta(days=days)
    executions = store.list(
        f"workspaces/{ctx.workspace_id}/executions", filters=[("startedAt", ">=", since)], limit=2000
    )
    errors_24h = list_errors(store, ctx.workspace_id, limit=500, since=utcnow() - timedelta(hours=24))
    return MonitoringOverview(
        executions=_execution_stats(executions),
        usage=_usage_summary(store, ctx.workspace_id, days),
        errors_last_24h=len(errors_24h),
        integrations=integration_status(settings),
    )


@router.get("/workspaces/{workspace_id}/monitoring/usage", response_model=UsageSummary)
def usage_summary(ctx: ManagerCtx, store: Store, days: int = Query(default=30, ge=1, le=90)):
    return _usage_summary(store, ctx.workspace_id, days)


@router.get(
    "/workspaces/{workspace_id}/monitoring/usage/records", response_model=ListResponse[UsageRecordOut]
)
def usage_records(ctx: ManagerCtx, store: Store, limit: int = Query(default=100, ge=1, le=500)):
    rows = store.list(
        f"workspaces/{ctx.workspace_id}/usage", order_by="createdAt", descending=True, limit=limit
    )
    items = [UsageRecordOut.model_validate(r) for r in rows]
    return ListResponse[UsageRecordOut](items=items, count=len(items))


@router.get("/workspaces/{workspace_id}/monitoring/errors", response_model=ListResponse[ErrorLogOut])
def error_logs(
    ctx: ManagerCtx,
    store: Store,
    limit: int = Query(default=100, ge=1, le=500),
    hours: int | None = Query(default=None, ge=1, le=24 * 90),
):
    since = utcnow() - timedelta(hours=hours) if hours else None
    items = list_errors(store, ctx.workspace_id, limit=limit, since=since)
    return ListResponse[ErrorLogOut](items=items, count=len(items))


@router.get("/workspaces/{workspace_id}/monitoring/activity", response_model=ListResponse[ActivityLogOut])
def activity_logs(
    ctx: ManagerCtx,
    store: Store,
    limit: int = Query(default=100, ge=1, le=500),
    actor_type: ActorType | None = Query(default=None, alias="actorType"),
):
    """Pass actorType=ai for the AI action audit trail."""
    rows = list_activity(store, ctx.workspace_id, limit=500 if actor_type else limit)
    if actor_type:
        rows = [r for r in rows if r.actor_type == actor_type]
    items = rows[:limit]
    return ListResponse[ActivityLogOut](items=items, count=len(items))


@router.get("/workspaces/{workspace_id}/monitoring/integrations", response_model=IntegrationStatusOut)
def integrations(ctx: ManagerCtx, settings: AppSettings):
    return integration_status(settings)


# ---------- Daily summary ----------
@router.get("/workspaces/{workspace_id}/daily-summary", response_model=DailySummary)
def daily_summary(ctx: MemberCtx, store: Store, settings: AppSettings):
    return build_daily_summary(store, settings, ctx.workspace_id)


@router.get("/internal/workspaces/{workspace_id}/daily-summary", response_model=DailySummary)
def internal_daily_summary(
    workspace_id: IdPath, _auth: CallbackAuth, store: Store, settings: AppSettings
):
    """Called by the n8n daily-summary workflow (X-LeadPilot-Callback-Secret)."""
    if not store.get(f"workspaces/{workspace_id}"):
        raise NotFoundError("Workspace not found.")
    return build_daily_summary(store, settings, workspace_id)