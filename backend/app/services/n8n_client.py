"""n8n integration: webhook contract, retrying client, execution tracking, callbacks."""
from __future__ import annotations

import time
from dataclasses import dataclass
from typing import Any

import httpx

from app.core.config import Settings
from app.core.errors import ConflictError, NotFoundError
from app.core.logging import get_logger
from app.schemas.common import ActorType, ExecutionStatus, WorkflowType, utcnow
from app.schemas.workflow import ExecutionCallback, ExecutionOut
from app.services.audit_service import log_activity, log_error
from app.services.firestore_client import DocumentStore, deterministic_id

logger = get_logger("leadpilot.n8n")

# Contract with the n8n workflow JSON files: POST {N8N_BASE_URL}/webhook/<path>
WEBHOOK_PATHS: dict[WorkflowType, str] = {
    WorkflowType.INQUIRY_INGESTION: "leadpilot-inquiry-ingestion",
    WorkflowType.AI_QUALIFICATION: "leadpilot-ai-qualification",
    WorkflowType.LEAD_ROUTING: "leadpilot-lead-routing",
    WorkflowType.FOLLOWUP_DRAFT: "leadpilot-followup-draft",
    WorkflowType.OUTBOUND_ACTION: "leadpilot-outbound-action",
    WorkflowType.BOOKING_PROCESSING: "leadpilot-booking-processing",
    WorkflowType.ERROR_NOTIFICATION: "leadpilot-error-notification",
    WorkflowType.DAILY_SUMMARY: "leadpilot-daily-summary",
}


@dataclass
class N8nResult:
    ok: bool
    attempts: int = 0
    status_code: int | None = None
    latency_ms: int | None = None
    error: str | None = None
    retryable: bool = False
    summary: str | None = None


class N8nClient:
    def __init__(self, settings: Settings):
        self._base = settings.n8n_base_url.rstrip("/")
        self._secret = settings.n8n_shared_secret.get_secret_value()
        self._timeout = settings.n8n_timeout_seconds
        self._max_retries = settings.n8n_max_retries

    def call(self, workflow: WorkflowType, body: dict[str, Any], idempotency_key: str) -> N8nResult:
        url = f"{self._base}/webhook/{WEBHOOK_PATHS[workflow]}"
        headers = {
            "Content-Type": "application/json",
            "X-LeadPilot-Secret": self._secret,
            "Idempotency-Key": idempotency_key,
        }
        started = time.perf_counter()
        total = self._max_retries + 1
        result = N8nResult(ok=False)
        for attempt in range(total):
            result.attempts = attempt + 1
            retryable = False
            try:
                resp = httpx.post(url, headers=headers, json=body, timeout=self._timeout)
                result.status_code = resp.status_code
                if resp.status_code < 300:
                    result.ok = True
                    result.error = None
                    result.summary = _summarize(resp)
                    break
                retryable = resp.status_code in (408, 429) or resp.status_code >= 500
                result.error = f"n8n responded with HTTP {resp.status_code}."
            except httpx.TimeoutException:
                retryable, result.error = True, "n8n request timed out."
            except httpx.HTTPError:
                retryable, result.error = True, "n8n could not be reached."
            result.retryable = retryable
            if not retryable:
                break
            if attempt < total - 1:
                time.sleep(min(0.5 * 2**attempt, 4))
        result.latency_ms = int((time.perf_counter() - started) * 1000)
        return result


def _summarize(resp: httpx.Response) -> str:
    try:
        data = resp.json()
        if isinstance(data, dict) and isinstance(data.get("message"), str):
            return f"HTTP {resp.status_code}: {data['message'][:150]}"
    except ValueError:
        pass
    return f"HTTP {resp.status_code}"


def _to_out(doc: dict[str, Any], workspace_id: str) -> ExecutionOut:
    return ExecutionOut.model_validate({**doc, "workspaceId": workspace_id})


def trigger_workflow(
    store: DocumentStore,
    settings: Settings,
    *,
    workspace_id: str,
    workflow: WorkflowType,
    payload: dict[str, Any],
    triggered_by: str,
    idempotency_key: str,
    lead_id: str | None = None,
    related_id: str | None = None,
    client: N8nClient | None = None,
) -> ExecutionOut:
    """Record an execution and call n8n. Never raises for n8n failures: the outcome is stored on the execution.
    The same idempotency key never triggers a second run; the existing execution is returned."""
    execution_id = deterministic_id("exec", f"{workspace_id}:{idempotency_key}")
    path = f"workspaces/{workspace_id}/executions/{execution_id}"
    started_at = utcnow()
    try:
        store.create(
            path,
            {
                "workspaceId": workspace_id, "workflow": workflow, "status": ExecutionStatus.RUNNING,
                "leadId": lead_id, "relatedId": related_id, "attempts": 0, "retryCount": 0,
                "triggeredBy": triggered_by, "idempotencyKey": idempotency_key, "startedAt": started_at,
                "finishedAt": None, "latencyMs": None, "errorMessage": None, "responseSummary": None,
            },
        )
    except ConflictError:
        existing = store.get(path)
        return _to_out(existing, workspace_id)  # type: ignore[arg-type]

    if not settings.n8n_configured:
        store.update(path, {
            "status": ExecutionStatus.SKIPPED, "finishedAt": utcnow(),
            "responseSummary": "n8n is not configured (N8N_SHARED_SECRET is empty). Nothing was sent.",
        })
    else:
        body = {
            "executionId": execution_id,
            "workspaceId": workspace_id,
            "workflow": workflow.value,
            "idempotencyKey": idempotency_key,
            "mode": settings.mode,
            "data": payload,
        }
        result = (client or N8nClient(settings)).call(workflow, body, idempotency_key)
        update: dict[str, Any] = {
            "status": ExecutionStatus.SUCCESS if result.ok else ExecutionStatus.FAILED,
            "attempts": result.attempts,
            "retryCount": max(result.attempts - 1, 0),
            "finishedAt": utcnow(),
            "latencyMs": result.latency_ms,
            "responseSummary": result.summary,
            "errorMessage": result.error,
        }
        store.update(path, update)
        if not result.ok:
            log_error(
                store, workspace_id, source="n8n", code="n8n_call_failed",
                message=result.error or "n8n call failed.", workflow=workflow.value,
                execution_id=execution_id, lead_id=lead_id,
                retry_status="exhausted" if result.retryable else "not_retryable",
            )

    final = store.get(path)
    log_activity(
        store, workspace_id, actor_type=ActorType.SYSTEM, actor_id=triggered_by,
        action=f"workflow.{final['status']}", entity_type="execution", entity_id=execution_id,
        summary=f"Workflow {workflow.value} finished with status {final['status']}",
        metadata={"workflow": workflow.value, "leadId": lead_id},
    )
    return _to_out(final, workspace_id)  # type: ignore[arg-type]


def apply_execution_callback(
    store: DocumentStore, workspace_id: str, execution_id: str, callback: ExecutionCallback
) -> ExecutionOut:
    """n8n reports a final outcome (for example when later steps failed after the webhook was accepted)."""
    path = f"workspaces/{workspace_id}/executions/{execution_id}"
    doc = store.get(path)
    if not doc:
        raise NotFoundError("Execution not found.")
    failed = callback.status == "failed"
    store.update(path, {
        "status": ExecutionStatus.FAILED if failed else ExecutionStatus.SUCCESS,
        "finishedAt": utcnow(),
        "errorMessage": (callback.message or "Workflow reported a failure.") if failed else None,
        "responseSummary": None if failed else (callback.message or doc.get("responseSummary")),
    })
    if failed:
        log_error(
            store, workspace_id, source="n8n", code="workflow_failed",
            message=callback.message or "Workflow reported a failure.",
            workflow=str(doc.get("workflow")), execution_id=execution_id, lead_id=doc.get("leadId"),
            retry_status="not_retryable",
        )
    log_activity(
        store, workspace_id, actor_type=ActorType.N8N, actor_id="n8n",
        action=f"workflow.callback_{callback.status}", entity_type="execution", entity_id=execution_id,
        summary=f"n8n reported {callback.status}",
    )
    return _to_out(store.get(path), workspace_id)  # type: ignore[arg-type]