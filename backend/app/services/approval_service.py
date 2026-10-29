"""Human-in-the-loop approvals. Sensitive actions only run after an explicit human decision."""
from __future__ import annotations

from typing import Any

from app.core.config import Settings
from app.core.errors import AppError, ConflictError, NotFoundError, ValidationFailedError
from app.schemas.approval import ApprovalDecision, ApprovalOut
from app.schemas.common import (
    ActorType,
    ApprovalAction,
    ApprovalStatus,
    ExecutionStatus,
    LeadStatus,
    WorkflowType,
    utcnow,
)
from app.schemas.lead import LeadOut
from app.services.audit_service import log_activity
from app.services.firestore_client import DocumentStore, new_id
from app.services.n8n_client import trigger_workflow


def _path(workspace_id: str, approval_id: str) -> str:
    return f"workspaces/{workspace_id}/approvals/{approval_id}"


def _to_out(doc: dict[str, Any], workspace_id: str) -> ApprovalOut:
    return ApprovalOut.model_validate({**doc, "workspaceId": workspace_id})


def create_approval(
    store: DocumentStore,
    *,
    workspace_id: str,
    action: ApprovalAction,
    title: str,
    description: str | None,
    lead_id: str | None,
    payload: dict[str, Any],
    safety_flags: list[str] | None = None,
) -> str:
    """Create a pending approval. A lead never gets two pending approvals of the same action type."""
    coll = f"workspaces/{workspace_id}/approvals"
    if lead_id:
        existing = store.list(
            coll,
            filters=[("leadId", "==", lead_id), ("status", "==", "pending"), ("actionType", "==", action.value)],
            limit=1,
        )
        if existing:
            return existing[0]["id"]
    approval_id = new_id()
    store.set(f"{coll}/{approval_id}", {
        "workspaceId": workspace_id, "actionType": action, "status": ApprovalStatus.PENDING,
        "title": title, "description": description, "leadId": lead_id, "payload": payload,
        "safetyFlags": safety_flags or [], "requestedBy": "ai", "createdAt": utcnow(),
        "decidedBy": None, "decidedAt": None, "decisionNote": None, "executionId": None, "resultMessage": None,
    })
    log_activity(
        store, workspace_id, actor_type=ActorType.AI, actor_id="ai", action="approval.requested",
        entity_type="approval", entity_id=approval_id, summary=title,
        metadata={"actionType": action, "leadId": lead_id},
    )
    return approval_id


def create_followup_approval(
    store: DocumentStore,
    *,
    workspace_id: str,
    lead: LeadOut,
    subject: str,
    body: str,
    safety_flags: list[str] | None = None,
) -> str | None:
    if not lead.customer_email or not body.strip():
        return None
    return create_approval(
        store,
        workspace_id=workspace_id,
        action=ApprovalAction.SEND_FOLLOWUP,
        title=f"Send follow-up to {lead.customer_name}",
        description="AI-drafted follow-up email. Review and edit before approving. Nothing is sent without approval.",
        lead_id=lead.id,
        payload={"channel": "email", "to": lead.customer_email, "subject": subject, "body": body},
        safety_flags=safety_flags,
    )


def create_disqualify_approval(
    store: DocumentStore, *, workspace_id: str, lead: LeadOut, reason: str
) -> str:
    return create_approval(
        store,
        workspace_id=workspace_id,
        action=ApprovalAction.UPDATE_STATUS,
        title=f"Mark {lead.customer_name} as lost",
        description=reason[:500],
        lead_id=lead.id,
        payload={"leadId": lead.id, "status": LeadStatus.LOST.value, "reason": reason[:500]},
    )


def get_approval(store: DocumentStore, workspace_id: str, approval_id: str) -> ApprovalOut:
    doc = store.get(_path(workspace_id, approval_id))
    if not doc:
        raise NotFoundError("Approval not found.")
    return _to_out(doc, workspace_id)


def list_approvals(
    store: DocumentStore, workspace_id: str, status: ApprovalStatus | None = None, limit: int = 100
) -> list[ApprovalOut]:
    filters = [("status", "==", status.value)] if status else None
    rows = store.list(
        f"workspaces/{workspace_id}/approvals", filters=filters, order_by="createdAt",
        descending=True, limit=min(limit, 500),
    )
    return [_to_out(r, workspace_id) for r in rows]


def _finish(store: DocumentStore, path: str, status: ApprovalStatus, message: str, execution_id: str | None = None) -> None:
    store.update(path, {"status": status, "resultMessage": message[:300], "executionId": execution_id})


def decide(
    store: DocumentStore,
    settings: Settings,
    *,
    workspace_id: str,
    approval_id: str,
    user_id: str,
    decision: ApprovalDecision,
) -> ApprovalOut:
    path = _path(workspace_id, approval_id)
    doc = store.get(path)
    if not doc:
        raise NotFoundError("Approval not found.")
    if doc.get("status") != ApprovalStatus.PENDING:
        raise ConflictError("This approval has already been decided.", code="already_decided")

    action = ApprovalAction(doc["actionType"])
    now = utcnow()
    base = {"decidedBy": user_id, "decidedAt": now, "decisionNote": decision.note}

    if decision.decision == "reject":
        if not store.compare_and_update(path, {"status": "pending"}, {**base, "status": ApprovalStatus.REJECTED}):
            raise ConflictError("This approval has already been decided.", code="already_decided")
        log_activity(
            store, workspace_id, actor_type=ActorType.USER, actor_id=user_id, action="approval.rejected",
            entity_type="approval", entity_id=approval_id, summary=str(doc.get("title", "")),
        )
        return get_approval(store, workspace_id, approval_id)

    payload = dict(doc.get("payload") or {})
    if decision.edited_subject or decision.edited_body:
        if action != ApprovalAction.SEND_FOLLOWUP:
            raise ValidationFailedError("Only follow-up approvals can be edited.")
        payload["subject"] = decision.edited_subject or payload.get("subject")
        payload["body"] = decision.edited_body or payload.get("body")

    # Atomic claim: exactly one concurrent approver wins, so an external action can never run twice.
    claimed = store.compare_and_update(
        path, {"status": "pending"}, {**base, "status": ApprovalStatus.APPROVED, "payload": payload}
    )
    if not claimed:
        raise ConflictError("This approval has already been decided.", code="already_decided")
    log_activity(
        store, workspace_id, actor_type=ActorType.USER, actor_id=user_id, action="approval.approved",
        entity_type="approval", entity_id=approval_id, summary=str(doc.get("title", "")),
        metadata={"edited": bool(decision.edited_subject or decision.edited_body)},
    )
    _execute(store, settings, workspace_id, approval_id, action, payload, doc.get("leadId"), user_id)
    return get_approval(store, workspace_id, approval_id)


def _execute(
    store: DocumentStore,
    settings: Settings,
    workspace_id: str,
    approval_id: str,
    action: ApprovalAction,
    payload: dict[str, Any],
    lead_id: str | None,
    user_id: str,
) -> None:
    from app.services.lead_service import change_status, get_lead  # lazy import avoids a circular dependency

    path = _path(workspace_id, approval_id)

    if action == ApprovalAction.SEND_FOLLOWUP:
        execution = trigger_workflow(
            store, settings, workspace_id=workspace_id, workflow=WorkflowType.OUTBOUND_ACTION,
            payload={
                "approvalId": approval_id, "leadId": lead_id, "channel": payload.get("channel", "email"),
                "to": payload.get("to"), "subject": payload.get("subject"), "body": payload.get("body"),
            },
            triggered_by=user_id, idempotency_key=f"approval:{approval_id}",
            lead_id=lead_id, related_id=approval_id,
        )
        if execution.status == ExecutionStatus.SUCCESS:
            _finish(store, path, ApprovalStatus.EXECUTED, "Accepted by the n8n outbound workflow.", execution.id)
            if lead_id:
                store.update(f"workspaces/{workspace_id}/leads/{lead_id}", {"lastContactedAt": utcnow()})
                try:
                    lead = get_lead(store, workspace_id, lead_id)
                    if lead.status in (LeadStatus.NEW, LeadStatus.QUALIFIED):
                        change_status(
                            store, workspace_id=workspace_id, lead_id=lead_id, target=LeadStatus.CONTACTED,
                            actor_type=ActorType.USER, actor_id=user_id, note="Follow-up approved and sent",
                        )
                except AppError:
                    pass
        elif execution.status == ExecutionStatus.SKIPPED:
            _finish(
                store, path, ApprovalStatus.APPROVED,
                "Approved, but nothing was sent because n8n is not configured.", execution.id,
            )
        else:
            _finish(
                store, path, ApprovalStatus.FAILED,
                f"Outbound workflow failed: {execution.error_message or 'unknown error'}", execution.id,
            )
        return

    if action == ApprovalAction.UPDATE_STATUS:
        try:
            target = LeadStatus(payload["status"])
            change_status(
                store, workspace_id=workspace_id, lead_id=str(payload["leadId"]), target=target,
                actor_type=ActorType.USER, actor_id=user_id, note="Approved AI recommendation",
            )
            _finish(store, path, ApprovalStatus.EXECUTED, f"Lead moved to {target.value}.")
        except (AppError, KeyError, ValueError) as exc:
            _finish(store, path, ApprovalStatus.FAILED, getattr(exc, "message", "Could not update the lead."))