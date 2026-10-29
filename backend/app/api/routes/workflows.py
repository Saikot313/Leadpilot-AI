"""Workflow endpoints: catalog, executions, manual trigger, retry, and n8n internal callbacks."""
from datetime import datetime
from typing import Annotated
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Header, Path, Query

from app.core.config import Settings
from app.core.deps import AppSettings, CallbackAuth, MemberCtx, Store, WriterCtx
from app.core.errors import ConflictError, NotFoundError, ValidationFailedError
from app.schemas.common import ID_PATTERN, ActorType, CamelModel, ExecutionStatus, ListResponse, WorkflowType
from app.schemas.qualification import QualifyResponse
from app.schemas.workflow import ErrorReport, ExecutionCallback, ExecutionOut, WorkflowTriggerRequest
from app.services.audit_service import log_activity, log_error
from app.services.firestore_client import DocumentStore, new_id
from app.services.lead_service import draft_followup_approval, get_lead, qualify_lead
from app.services.n8n_client import WEBHOOK_PATHS, apply_execution_callback, trigger_workflow

IdPath = Annotated[str, Path(pattern=ID_PATTERN)]
router = APIRouter(tags=["workflows"])

# Workflows a person may start by hand. Outbound, booking, ingestion and error workflows are only
# started by the backend itself (after approval, booking confirmation, or an inbound event).
MANUAL_WORKFLOWS = {
    WorkflowType.AI_QUALIFICATION,
    WorkflowType.LEAD_ROUTING,
    WorkflowType.FOLLOWUP_DRAFT,
    WorkflowType.DAILY_SUMMARY,
}
LEAD_REQUIRED = {WorkflowType.AI_QUALIFICATION, WorkflowType.LEAD_ROUTING, WorkflowType.FOLLOWUP_DRAFT}

_CATALOG = {
    WorkflowType.INQUIRY_INGESTION: ("New inquiry ingestion", "Receives inquiries from forms and forwards them to the backend."),
    WorkflowType.AI_QUALIFICATION: ("AI lead qualification", "Asks the backend to qualify a lead with the LLM."),
    WorkflowType.LEAD_ROUTING: ("Lead routing and logging", "Routes a lead by score and priority and notifies the team."),
    WorkflowType.FOLLOWUP_DRAFT: ("Follow-up draft generation", "Generates a follow-up draft and queues it for approval."),
    WorkflowType.OUTBOUND_ACTION: ("Approved outbound actions", "Sends a message only after a human approves it."),
    WorkflowType.BOOKING_PROCESSING: ("Booking processing", "Sends confirmations and reminders for confirmed bookings."),
    WorkflowType.ERROR_NOTIFICATION: ("Error notification and retry", "Reports workflow failures back to the backend."),
    WorkflowType.DAILY_SUMMARY: ("Daily summary report", "Delivers the daily activity summary."),
}


class WorkflowInfo(CamelModel):
    workflow: WorkflowType
    label: str
    description: str
    webhook_path: str
    manual_trigger: bool
    requires_lead: bool


# ---------- Helpers ----------
def _exec_out(row: dict, workspace_id: str) -> ExecutionOut:
    return ExecutionOut.model_validate({**row, "workspaceId": workspace_id})


def _build_payload(
    store: DocumentStore, settings: Settings, workspace_id: str,
    workflow: WorkflowType, lead_id: str | None, note: str | None,
) -> dict:
    if workflow == WorkflowType.DAILY_SUMMARY:
        return {"date": datetime.now(ZoneInfo(settings.booking_timezone)).date().isoformat()}
    lead = get_lead(store, workspace_id, str(lead_id))
    if workflow == WorkflowType.LEAD_ROUTING:
        q = lead.qualification
        return {
            "leadId": lead.id, "customerName": lead.customer_name, "source": lead.source.value,
            "status": lead.status.value, "qualified": q is not None, "score": lead.score,
            "priority": lead.priority.value if lead.priority else None,
            "recommendedNextAction": q.recommended_next_action.value if q else None,
            "needsHumanHandoff": q.needs_human_handoff if q else True,
            "summary": q.summary if q else None, "approvalId": None,
        }
    if workflow == WorkflowType.FOLLOWUP_DRAFT:
        return {"leadId": lead.id, "instruction": note}
    return {"leadId": lead.id}


# ---------- Catalog and history ----------
@router.get("/workspaces/{workspace_id}/workflows", response_model=ListResponse[WorkflowInfo])
def workflow_catalog(ctx: MemberCtx):
    items = [
        WorkflowInfo(
            workflow=wf, label=label, description=desc, webhook_path=WEBHOOK_PATHS[wf],
            manual_trigger=wf in MANUAL_WORKFLOWS, requires_lead=wf in LEAD_REQUIRED,
        )
        for wf, (label, desc) in _CATALOG.items()
    ]
    return ListResponse[WorkflowInfo](items=items, count=len(items))


@router.get("/workspaces/{workspace_id}/executions", response_model=ListResponse[ExecutionOut])
def list_executions(
    ctx: MemberCtx, store: Store,
    status: ExecutionStatus | None = None,
    limit: int = Query(default=50, ge=1, le=200),
):
    rows = store.list(
        f"workspaces/{ctx.workspace_id}/executions",
        filters=[("status", "==", status.value)] if status else None,
        order_by="startedAt", descending=True, limit=limit,
    )
    items = [_exec_out(r, ctx.workspace_id) for r in rows]
    return ListResponse[ExecutionOut](items=items, count=len(items))


@router.get("/workspaces/{workspace_id}/executions/{execution_id}", response_model=ExecutionOut)
def get_execution(execution_id: IdPath, ctx: MemberCtx, store: Store):
    row = store.get(f"workspaces/{ctx.workspace_id}/executions/{execution_id}")
    if not row:
        raise NotFoundError("Execution not found.")
    return _exec_out(row, ctx.workspace_id)


# ---------- Manual trigger and retry ----------
@router.post("/workspaces/{workspace_id}/workflows/trigger", response_model=ExecutionOut)
def trigger_manually(
    body: WorkflowTriggerRequest,
    ctx: WriterCtx,
    store: Store,
    settings: AppSettings,
    idempotency_key: Annotated[str | None, Header(max_length=100, pattern=r"^[A-Za-z0-9_.:-]+$")] = None,
):
    if body.workflow not in MANUAL_WORKFLOWS:
        raise ValidationFailedError(
            "This workflow cannot be started manually.", code="workflow_not_manual"
        )
    if body.workflow in LEAD_REQUIRED and not body.lead_id:
        raise ValidationFailedError("leadId is required for this workflow.", code="lead_required")
    payload = _build_payload(store, settings, ctx.workspace_id, body.workflow, body.lead_id, body.note)
    key = f"manual:{body.workflow.value}:{idempotency_key or new_id()}"
    return trigger_workflow(
        store, settings, workspace_id=ctx.workspace_id, workflow=body.workflow, payload=payload,
        triggered_by=ctx.actor_id, idempotency_key=key, lead_id=body.lead_id,
    )


@router.post("/workspaces/{workspace_id}/executions/{execution_id}/retry", response_model=ExecutionOut)
def retry_execution(execution_id: IdPath, ctx: WriterCtx, store: Store, settings: AppSettings):
    path = f"workspaces/{ctx.workspace_id}/executions/{execution_id}"
    doc = store.get(path)
    if not doc:
        raise NotFoundError("Execution not found.")
    workflow = WorkflowType(doc["workflow"])
    if doc.get("status") != ExecutionStatus.FAILED:
        raise ConflictError("Only failed executions can be retried.", code="invalid_execution_state")
    if workflow not in MANUAL_WORKFLOWS:
        raise ConflictError(
            "This workflow is retried by re-approving or re-confirming the original item.",
            code="not_retryable",
        )
    # Atomic claim so two people cannot retry the same failure at once.
    if not store.compare_and_update(
        path, {"status": "failed", "retriedBy": None}, {"retriedBy": "pending"}
    ):
        raise ConflictError("This execution is already being retried.", code="already_retried")
    try:
        payload = _build_payload(store, settings, ctx.workspace_id, workflow, doc.get("leadId"), None)
        new = trigger_workflow(
            store, settings, workspace_id=ctx.workspace_id, workflow=workflow, payload=payload,
            triggered_by=ctx.actor_id, idempotency_key=f"retry:{execution_id}:{new_id()}",
            lead_id=doc.get("leadId"), related_id=execution_id,
        )
    except Exception:
        store.update(path, {"retriedBy": None})
        raise
    store.update(path, {"retriedBy": new.id, "retryCount": int(doc.get("retryCount") or 0) + 1})
    log_activity(
        store, ctx.workspace_id, actor_type=ActorType.USER, actor_id=ctx.actor_id,
        action="workflow.retry_requested", entity_type="execution", entity_id=execution_id,
        summary=f"Retry of {workflow.value} requested", metadata={"newExecutionId": new.id},
    )
    return new


# ---------- n8n internal endpoints (X-LeadPilot-Callback-Secret) ----------
@router.post(
    "/internal/workspaces/{workspace_id}/executions/{execution_id}/callback", response_model=ExecutionOut
)
def execution_callback(
    workspace_id: IdPath, execution_id: IdPath, body: ExecutionCallback, _auth: CallbackAuth, store: Store
):
    return apply_execution_callback(store, workspace_id, execution_id, body)


@router.post("/internal/workspaces/{workspace_id}/errors", status_code=202)
def report_workflow_error(workspace_id: IdPath, body: ErrorReport, _auth: CallbackAuth, store: Store):
    if not store.get(f"workspaces/{workspace_id}"):
        raise NotFoundError("Workspace not found.")
    message = f"[{body.node}] {body.message}" if body.node else body.message
    log_error(
        store, workspace_id, source="n8n", code="workflow_error", message=message,
        workflow=body.workflow, execution_id=body.execution_id, lead_id=body.lead_id,
        retry_status=body.retry_status,
    )
    return {"accepted": True}


@router.post("/internal/workspaces/{workspace_id}/leads/{lead_id}/qualify", response_model=QualifyResponse)
def internal_qualify(
    workspace_id: IdPath, lead_id: IdPath, _auth: CallbackAuth, store: Store, settings: AppSettings
):
    return qualify_lead(
        store, settings, workspace_id=workspace_id, lead_id=lead_id, actor_id="n8n",
        actor_type=ActorType.N8N,
    )


@router.post("/internal/workspaces/{workspace_id}/leads/{lead_id}/followup-draft")
def internal_followup_draft(
    workspace_id: IdPath, lead_id: IdPath, _auth: CallbackAuth, store: Store, settings: AppSettings
):
    approval_id, subject, _body = draft_followup_approval(
        store, settings, workspace_id=workspace_id, lead_id=lead_id, actor_id="n8n"
    )
    return {"approvalId": approval_id, "subject": subject}