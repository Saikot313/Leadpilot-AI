"""Approval endpoints. Sensitive actions only run after a human decision made here."""
from typing import Annotated

from fastapi import APIRouter, Path, Query

from app.core.deps import AppSettings, MemberCtx, Store, WriterCtx
from app.schemas.approval import ApprovalDecision, ApprovalOut
from app.schemas.common import ID_PATTERN, ApprovalStatus, ListResponse
from app.services import approval_service

ApprovalId = Annotated[str, Path(pattern=ID_PATTERN)]
router = APIRouter(prefix="/workspaces/{workspace_id}/approvals", tags=["approvals"])


@router.get("", response_model=ListResponse[ApprovalOut])
def list_approvals(
    ctx: MemberCtx,
    store: Store,
    status: ApprovalStatus | None = None,
    limit: int = Query(default=100, ge=1, le=500),
):
    items = approval_service.list_approvals(store, ctx.workspace_id, status=status, limit=limit)
    return ListResponse[ApprovalOut](items=items, count=len(items))


@router.get("/{approval_id}", response_model=ApprovalOut)
def get_approval(approval_id: ApprovalId, ctx: MemberCtx, store: Store):
    return approval_service.get_approval(store, ctx.workspace_id, approval_id)


@router.post("/{approval_id}/decision", response_model=ApprovalOut)
def decide_approval(
    approval_id: ApprovalId, body: ApprovalDecision, ctx: WriterCtx, store: Store, settings: AppSettings
):
    return approval_service.decide(
        store, settings, workspace_id=ctx.workspace_id, approval_id=approval_id,
        user_id=ctx.actor_id, decision=body,
    )