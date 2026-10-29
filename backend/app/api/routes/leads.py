"""Lead CRUD and pipeline status endpoints."""
from typing import Annotated

from fastapi import APIRouter, Path, Query, Response

from app.core.deps import AppSettings, MemberCtx, Store, WriterCtx
from app.schemas.common import (
    ID_PATTERN,
    ActorType,
    LeadSource,
    LeadStatus,
    ListResponse,
    Priority,
)
from app.schemas.lead import (
    LeadCreate,
    LeadOut,
    LeadStatusChange,
    LeadUpdate,
    StatusHistoryOut,
)
from app.services import lead_service

LeadId = Annotated[str, Path(pattern=ID_PATTERN)]
router = APIRouter(prefix="/workspaces/{workspace_id}/leads", tags=["leads"])


@router.get("", response_model=ListResponse[LeadOut])
def list_leads(
    ctx: MemberCtx,
    store: Store,
    status: LeadStatus | None = None,
    priority: Priority | None = None,
    source: LeadSource | None = None,
    tag: str | None = Query(default=None, max_length=30),
    search: str | None = Query(default=None, max_length=100),
    assigned_to: str | None = Query(default=None, alias="assignedTo", pattern=ID_PATTERN),
    limit: int = Query(default=100, ge=1, le=500),
):
    leads = lead_service.list_leads(
        store, ctx.workspace_id, status=status, priority=priority, assigned_to=assigned_to,
        source=source, tag=tag, search=search, limit=limit,
    )
    return ListResponse[LeadOut](items=leads, count=len(leads))


@router.post("", response_model=LeadOut, status_code=201)
def create_lead(body: LeadCreate, ctx: WriterCtx, store: Store, settings: AppSettings, response: Response):
    lead, duplicate = lead_service.create_lead(
        store, settings, workspace_id=ctx.workspace_id, actor_id=ctx.actor_id, data=body
    )
    if duplicate:
        response.status_code = 200
    return lead


@router.get("/{lead_id}", response_model=LeadOut)
def get_lead(lead_id: LeadId, ctx: MemberCtx, store: Store):
    return lead_service.get_lead(store, ctx.workspace_id, lead_id)


@router.patch("/{lead_id}", response_model=LeadOut)
def update_lead(lead_id: LeadId, body: LeadUpdate, ctx: WriterCtx, store: Store):
    return lead_service.update_lead(
        store, workspace_id=ctx.workspace_id, lead_id=lead_id, actor_id=ctx.actor_id, data=body
    )


@router.post("/{lead_id}/status", response_model=LeadOut)
def change_lead_status(lead_id: LeadId, body: LeadStatusChange, ctx: WriterCtx, store: Store):
    return lead_service.change_status(
        store, workspace_id=ctx.workspace_id, lead_id=lead_id, target=body.status,
        actor_type=ActorType.USER, actor_id=ctx.actor_id, note=body.note,
    )


@router.get("/{lead_id}/history", response_model=ListResponse[StatusHistoryOut])
def lead_status_history(lead_id: LeadId, ctx: MemberCtx, store: Store):
    items = lead_service.list_status_history(store, ctx.workspace_id, lead_id)
    return ListResponse[StatusHistoryOut](items=items, count=len(items))