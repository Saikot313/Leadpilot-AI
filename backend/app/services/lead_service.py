"""Lead management and the end-to-end inquiry pipeline."""
from __future__ import annotations

from typing import Any

from app.core.config import Settings
from app.core.errors import AppError, ConflictError, NotFoundError, ValidationFailedError
from app.schemas.common import (
    ActorType,
    LeadSource,
    LeadStatus,
    NextAction,
    Priority,
    WorkflowType,
    can_transition,
    utcnow,
)
from app.schemas.lead import InquiryIn, InquiryResponse, LeadCreate, LeadOut, LeadUpdate, StatusHistoryOut
from app.schemas.qualification import QualifyResponse
from app.services import approval_service
from app.services.audit_service import log_activity, log_error
from app.services.firestore_client import DocumentStore, deterministic_id, new_id
from app.services.n8n_client import trigger_workflow
from app.services.qualification_service import qualify_message, scan_draft_flags

QUALIFIED_MIN_SCORE = 40
DEFAULT_FOLLOWUP_SUBJECT = "Thanks for your inquiry"


def _lead_path(workspace_id: str, lead_id: str) -> str:
    return f"workspaces/{workspace_id}/leads/{lead_id}"


def _to_out(doc: dict[str, Any], workspace_id: str) -> LeadOut:
    return LeadOut.model_validate({**doc, "workspaceId": workspace_id})


def _unique_tags(tags: list[str] | None) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for tag in tags or []:
        if tag.lower() not in seen:
            seen.add(tag.lower())
            out.append(tag)
    return out


def _check_assignee(store: DocumentStore, workspace_id: str, user_id: str | None) -> None:
    if not user_id:
        return
    member = store.get(f"workspaces/{workspace_id}/members/{user_id}")
    if not member or member.get("status", "active") != "active":
        raise ValidationFailedError("The assignee is not an active member of this workspace.", code="invalid_assignee")


# ---------- Reads ----------
def get_lead(store: DocumentStore, workspace_id: str, lead_id: str) -> LeadOut:
    doc = store.get(_lead_path(workspace_id, lead_id))
    if not doc:
        raise NotFoundError("Lead not found.")
    return _to_out(doc, workspace_id)


def list_leads(
    store: DocumentStore,
    workspace_id: str,
    *,
    status: LeadStatus | None = None,
    priority: Priority | None = None,
    assigned_to: str | None = None,
    source: LeadSource | None = None,
    tag: str | None = None,
    search: str | None = None,
    limit: int = 100,
) -> list[LeadOut]:
    limit = max(1, min(limit, 500))
    equality = [
        (field, "==", value.value if hasattr(value, "value") else value)
        for field, value in (("status", status), ("priority", priority), ("assignedTo", assigned_to))
        if value is not None
    ]
    query_filters, python_filters = equality[:1], equality[1:]  # indexes cover one equality filter + createdAt
    needs_python = bool(python_filters or source or tag or search)
    rows = store.list(
        f"workspaces/{workspace_id}/leads",
        filters=query_filters,
        order_by="createdAt",
        descending=True,
        limit=500 if needs_python else limit,
    )
    for field, _, value in python_filters:
        rows = [r for r in rows if r.get(field) == value]
    if source:
        rows = [r for r in rows if r.get("source") == source.value]
    if tag:
        rows = [r for r in rows if tag.lower() in [str(t).lower() for t in r.get("tags", [])]]
    if search:
        needle = search.lower()
        rows = [
            r for r in rows
            if needle in " ".join(str(r.get(k) or "") for k in ("customerName", "customerEmail", "company", "message")).lower()
        ]
    return [_to_out(r, workspace_id) for r in rows[:limit]]


def list_status_history(store: DocumentStore, workspace_id: str, lead_id: str) -> list[StatusHistoryOut]:
    get_lead(store, workspace_id, lead_id)
    rows = store.list(
        f"{_lead_path(workspace_id, lead_id)}/statusHistory", order_by="createdAt", descending=True, limit=100
    )
    return [StatusHistoryOut.model_validate(r) for r in rows]


# ---------- Writes ----------
def _insert_lead(
    store: DocumentStore,
    *,
    workspace_id: str,
    lead_id: str,
    actor_type: ActorType,
    actor_id: str,
    customer_name: str,
    customer_email: str | None,
    customer_phone: str | None,
    company: str | None,
    source: LeadSource,
    message: str,
    tags: list[str],
    notes: str | None,
    assigned_to: str | None,
    event_id: str | None,
) -> None:
    now = utcnow()
    store.create(_lead_path(workspace_id, lead_id), {
        "workspaceId": workspace_id, "customerName": customer_name, "customerEmail": customer_email,
        "customerPhone": customer_phone, "company": company, "source": source, "message": message,
        "tags": _unique_tags(tags), "notes": notes, "status": LeadStatus.NEW, "score": None,
        "priority": None, "qualification": None, "assignedTo": assigned_to, "createdBy": actor_id,
        "eventId": event_id, "createdAt": now, "updatedAt": now, "lastContactedAt": None,
    })
    store.set(f"{_lead_path(workspace_id, lead_id)}/statusHistory/{new_id()}", {
        "fromStatus": None, "toStatus": LeadStatus.NEW, "changedBy": actor_id,
        "note": "Lead created", "createdAt": now,
    })
    log_activity(
        store, workspace_id, actor_type=actor_type, actor_id=actor_id, action="lead.created",
        entity_type="lead", entity_id=lead_id, summary=f"Lead created from {source.value}",
        metadata={"source": source},
    )


def _try_qualify(
    store: DocumentStore, settings: Settings, workspace_id: str, lead_id: str, actor_id: str, actor_type: ActorType
) -> QualifyResponse | None:
    """Qualification failure must never lose the lead: log it and continue."""
    try:
        return qualify_lead(
            store, settings, workspace_id=workspace_id, lead_id=lead_id, actor_id=actor_id, actor_type=actor_type
        )
    except AppError as exc:
        log_error(store, workspace_id, source="llm", code=exc.code, message=exc.message, lead_id=lead_id)
        return None


def create_lead(
    store: DocumentStore,
    settings: Settings,
    *,
    workspace_id: str,
    actor_id: str,
    data: LeadCreate,
    actor_type: ActorType = ActorType.USER,
) -> tuple[LeadOut, bool]:
    """Returns (lead, duplicate). A repeated event_id returns the existing lead."""
    _check_assignee(store, workspace_id, data.assigned_to)
    lead_id = deterministic_id("lead", data.event_id) if data.event_id else new_id()
    try:
        _insert_lead(
            store, workspace_id=workspace_id, lead_id=lead_id, actor_type=actor_type, actor_id=actor_id,
            customer_name=data.customer_name, customer_email=data.customer_email,
            customer_phone=data.customer_phone, company=data.company, source=data.source,
            message=data.message, tags=data.tags, notes=data.notes, assigned_to=data.assigned_to,
            event_id=data.event_id,
        )
    except ConflictError:
        if not data.event_id:
            raise
        return get_lead(store, workspace_id, lead_id), True
    if data.qualify:
        _try_qualify(store, settings, workspace_id, lead_id, actor_id, actor_type)
    return get_lead(store, workspace_id, lead_id), False


def update_lead(
    store: DocumentStore, *, workspace_id: str, lead_id: str, actor_id: str, data: LeadUpdate
) -> LeadOut:
    get_lead(store, workspace_id, lead_id)
    changes = data.model_dump(exclude_unset=True, by_alias=True)
    if not changes:
        raise ValidationFailedError("No fields to update.")
    if "customerName" in changes and changes["customerName"] is None:
        raise ValidationFailedError("customerName cannot be empty.")
    if "tags" in changes:
        changes["tags"] = _unique_tags(changes["tags"])
    if "assignedTo" in changes:
        _check_assignee(store, workspace_id, changes["assignedTo"])
    changes["updatedAt"] = utcnow()
    store.update(_lead_path(workspace_id, lead_id), changes)
    log_activity(
        store, workspace_id, actor_type=ActorType.USER, actor_id=actor_id, action="lead.updated",
        entity_type="lead", entity_id=lead_id, summary="Lead details updated",
        metadata={"fields": ",".join(sorted(k for k in changes if k != "updatedAt"))},
    )
    return get_lead(store, workspace_id, lead_id)


def change_status(
    store: DocumentStore,
    *,
    workspace_id: str,
    lead_id: str,
    target: LeadStatus,
    actor_type: ActorType,
    actor_id: str,
    note: str | None = None,
) -> LeadOut:
    lead = get_lead(store, workspace_id, lead_id)
    if lead.status == target:
        raise ConflictError("The lead is already in this status.", code="same_status")
    if not can_transition(lead.status, target):
        raise ConflictError(
            f"A lead cannot move from {lead.status.value} to {target.value}.", code="invalid_transition"
        )
    now = utcnow()
    updates: dict[str, Any] = {"status": target, "updatedAt": now}
    if target == LeadStatus.CONTACTED:
        updates["lastContactedAt"] = now
    if not store.compare_and_update(_lead_path(workspace_id, lead_id), {"status": lead.status.value}, updates):
        raise ConflictError("The lead was modified at the same time. Refresh and try again.", code="concurrent_update")
    store.set(f"{_lead_path(workspace_id, lead_id)}/statusHistory/{new_id()}", {
        "fromStatus": lead.status, "toStatus": target, "changedBy": actor_id, "note": note, "createdAt": now,
    })
    log_activity(
        store, workspace_id, actor_type=actor_type, actor_id=actor_id, action="lead.status_changed",
        entity_type="lead", entity_id=lead_id, summary=f"{lead.status.value} -> {target.value}",
        metadata={"from": lead.status, "to": target},
    )
    return get_lead(store, workspace_id, lead_id)


def qualify_lead(
    store: DocumentStore,
    settings: Settings,
    *,
    workspace_id: str,
    lead_id: str,
    actor_id: str,
    actor_type: ActorType = ActorType.USER,
) -> QualifyResponse:
    lead = get_lead(store, workspace_id, lead_id)
    result, usage = qualify_message(
        store, settings, workspace_id=workspace_id, message=lead.message,
        customer_name=lead.customer_name, source=lead.source, requested_by=actor_id, lead_id=lead_id,
    )
    store.update(_lead_path(workspace_id, lead_id), {
        "qualification": result, "score": result.score, "priority": result.priority, "updatedAt": utcnow(),
    })
    log_activity(
        store, workspace_id, actor_type=ActorType.AI, actor_id=result.provider, action="lead.qualified",
        entity_type="lead", entity_id=lead_id, summary=f"Score {result.score} ({result.priority.value})",
        metadata={"score": result.score, "priority": result.priority, "model": result.model, "mode": result.mode},
    )

    # Deterministic pipeline rule: NEW + score >= 40 becomes QUALIFIED. Anything else stays with a human.
    if lead.status == LeadStatus.NEW and result.score >= QUALIFIED_MIN_SCORE:
        try:
            change_status(
                store, workspace_id=workspace_id, lead_id=lead_id, target=LeadStatus.QUALIFIED,
                actor_type=ActorType.AI, actor_id="ai", note=f"Auto-qualified (score {result.score})",
            )
        except AppError:
            pass

    refreshed = get_lead(store, workspace_id, lead_id)
    approval_id: str | None = None
    if result.needs_human_handoff:
        log_activity(
            store, workspace_id, actor_type=ActorType.AI, actor_id="ai", action="lead.handoff_requested",
            entity_type="lead", entity_id=lead_id, summary="Human handoff requested",
            metadata={"reason": result.handoff_reason},
        )
    elif result.recommended_next_action == NextAction.DISQUALIFY:
        approval_id = approval_service.create_disqualify_approval(
            store, workspace_id=workspace_id, lead=refreshed, reason=result.explanation
        )
    elif result.suggested_followup_message:
        approval_id = approval_service.create_followup_approval(
            store, workspace_id=workspace_id, lead=refreshed, subject=DEFAULT_FOLLOWUP_SUBJECT,
            body=result.suggested_followup_message, safety_flags=result.safety_flags,
        )
    return QualifyResponse(
        result=result, usage=usage, mode=settings.mode, lead_id=lead_id, persisted=True, approval_id=approval_id
    )


def draft_followup_approval(
    store: DocumentStore,
    settings: Settings,
    *,
    workspace_id: str,
    lead_id: str,
    actor_id: str,
    instruction: str | None = None,
) -> tuple[str | None, str, str]:
    """Generate a fresh follow-up draft and queue it for approval. Returns (approval_id, subject, body)."""
    from app.services.qualification_service import draft_followup

    lead = get_lead(store, workspace_id, lead_id)
    draft, _ = draft_followup(
        store, settings, workspace_id=workspace_id, lead=lead, requested_by=actor_id, instruction=instruction
    )
    approval_id = approval_service.create_followup_approval(
        store, workspace_id=workspace_id, lead=lead, subject=draft.subject, body=draft.body,
        safety_flags=scan_draft_flags(draft.body),
    )
    return approval_id, draft.subject, draft.body


def process_inquiry(
    store: DocumentStore,
    settings: Settings,
    *,
    workspace_id: str,
    inquiry: InquiryIn,
    actor_type: ActorType = ActorType.SYSTEM,
    actor_id: str = "inquiry-webhook",
) -> InquiryResponse:
    """Inquiry -> validated lead -> LLM qualification -> approval -> n8n routing -> response."""
    lead_id = deterministic_id("lead", inquiry.event_id) if inquiry.event_id else new_id()
    try:
        _insert_lead(
            store, workspace_id=workspace_id, lead_id=lead_id, actor_type=actor_type, actor_id=actor_id,
            customer_name=inquiry.customer_name or "Unknown customer", customer_email=inquiry.customer_email,
            customer_phone=inquiry.customer_phone, company=inquiry.company, source=inquiry.source,
            message=inquiry.message, tags=[], notes=None, assigned_to=None, event_id=inquiry.event_id,
        )
    except ConflictError:
        if not inquiry.event_id:
            raise
        existing = get_lead(store, workspace_id, lead_id)
        return InquiryResponse(
            lead_id=lead_id, duplicate=True, status=existing.status,
            qualification=existing.qualification, mode=settings.mode,
        )

    outcome = _try_qualify(store, settings, workspace_id, lead_id, actor_id, actor_type)
    lead = get_lead(store, workspace_id, lead_id)
    q = lead.qualification
    execution = trigger_workflow(
        store, settings, workspace_id=workspace_id, workflow=WorkflowType.LEAD_ROUTING,
        payload={
            "leadId": lead.id, "customerName": lead.customer_name, "source": lead.source.value,
            "status": lead.status.value, "qualified": q is not None,
            "score": lead.score, "priority": lead.priority.value if lead.priority else None,
            "recommendedNextAction": q.recommended_next_action.value if q else None,
            "needsHumanHandoff": q.needs_human_handoff if q else True,
            "summary": q.summary if q else None,
            "approvalId": outcome.approval_id if outcome else None,
        },
        triggered_by=actor_id, idempotency_key=f"lead-routing:{lead.id}", lead_id=lead.id,
    )
    return InquiryResponse(
        lead_id=lead.id, duplicate=False, status=lead.status, qualification=q,
        approval_id=outcome.approval_id if outcome else None, execution=execution, mode=settings.mode,
    )