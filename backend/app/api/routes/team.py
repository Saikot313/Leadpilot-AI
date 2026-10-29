"""Workspaces, membership and roles. Workspace and membership documents are written only here."""
from datetime import datetime
from typing import Annotated
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Path, Response
from firebase_admin import auth as fb_auth
from pydantic import AfterValidator, Field, field_validator

from app.core.config import Settings
from app.core.deps import AppSettings, CurrentUser, ManagerCtx, MemberCtx, Store
from app.core.errors import (
    ConflictError,
    ForbiddenError,
    NotFoundError,
    UpstreamError,
    ValidationFailedError,
)
from app.core.security import init_firebase_app
from app.schemas.common import (
    ID_PATTERN,
    ActorType,
    CamelModel,
    EmailAddress,
    ListResponse,
    RequestModel,
    Role,
    utcnow,
)
from app.schemas.qualification import AgentConfig
from app.services.audit_service import log_activity
from app.services.firestore_client import DocumentStore, new_id

MAX_OWNED_WORKSPACES = 5
IdPath = Annotated[str, Path(pattern=ID_PATTERN)]
router = APIRouter(tags=["workspaces"])


# ---------- Models ----------
def _check_tz(value: str | None) -> str | None:
    if value is None:
        return value
    try:
        ZoneInfo(value)
    except Exception as exc:  # noqa: BLE001
        raise ValueError("Unknown timezone") from exc
    return value


def _not_owner(role: Role) -> Role:
    if role == Role.OWNER:
        raise ValueError("The owner role cannot be assigned.")
    return role


AssignableRole = Annotated[Role, AfterValidator(_not_owner)]


class WorkspaceCreate(RequestModel):
    name: str = Field(min_length=2, max_length=80)
    industry: str | None = Field(default=None, max_length=80)
    timezone: str = Field(default="UTC", max_length=64)

    _tz = field_validator("timezone")(_check_tz)


class WorkspaceUpdate(RequestModel):
    name: str | None = Field(default=None, min_length=2, max_length=80)
    industry: str | None = Field(default=None, max_length=80)
    timezone: str | None = Field(default=None, max_length=64)

    _tz = field_validator("timezone")(_check_tz)


class WorkspaceOut(CamelModel):
    id: str
    name: str
    industry: str | None = None
    timezone: str = "UTC"
    role: Role | None = None
    is_demo: bool = False
    owner_id: str | None = None
    created_at: datetime | None = None


class MemberOut(CamelModel):
    uid: str
    email: str | None = None
    display_name: str | None = None
    role: Role
    status: str = "active"
    joined_at: datetime | None = None


class MemberAdd(RequestModel):
    email: EmailAddress
    role: AssignableRole = Role.AGENT


class MemberRoleUpdate(RequestModel):
    role: AssignableRole


# ---------- Helpers ----------
def _workspace_out(workspace_id: str, doc: dict, role: Role | str | None) -> WorkspaceOut:
    return WorkspaceOut(
        id=workspace_id,
        name=doc.get("name", ""),
        industry=doc.get("industry"),
        timezone=doc.get("timezone", "UTC"),
        role=Role(role) if role else None,
        is_demo=bool(doc.get("isDemo")),
        owner_id=doc.get("ownerId"),
        created_at=doc.get("createdAt"),
    )


def _member_path(workspace_id: str, uid: str) -> str:
    return f"workspaces/{workspace_id}/members/{uid}"


def _get_member(store: DocumentStore, workspace_id: str, uid: str) -> dict:
    doc = store.get(_member_path(workspace_id, uid))
    if not doc or doc.get("status", "active") == "removed":
        raise NotFoundError("Member not found.")
    return doc


def _resolve_user(store: DocumentStore, settings: Settings, email: str) -> tuple[str, str]:
    """Map an email to a Firebase UID. Live mode uses the authoritative Firebase Admin lookup."""
    if settings.demo_mode:
        rows = store.list("users", filters=[("email", "==", email)], limit=1)
        if not rows:
            raise NotFoundError("No user with that email exists in demo mode.", code="user_not_found")
        return rows[0]["id"], rows[0].get("displayName") or email
    init_firebase_app()
    try:
        record = fb_auth.get_user_by_email(email)
    except fb_auth.UserNotFoundError:
        raise NotFoundError(
            "No account with that email exists. Ask them to sign up first.", code="user_not_found"
        ) from None
    except Exception as exc:  # noqa: BLE001
        raise UpstreamError("Could not look up that user right now.", code="user_lookup_failed") from exc
    return record.uid, record.display_name or email


# ---------- Workspaces ----------
@router.get("/me/workspaces", response_model=ListResponse[WorkspaceOut])
def my_workspaces(user: CurrentUser, store: Store):
    rows = store.list_group("members", filters=[("uid", "==", user.uid)], limit=100)
    items: list[WorkspaceOut] = []
    for row in rows:
        path = row.get("_path", "")
        parts = path.split("/")
        if len(parts) != 4 or parts[0] != "workspaces" or row.get("status", "active") != "active":
            continue
        doc = store.get(f"workspaces/{parts[1]}")
        if doc:
            items.append(_workspace_out(parts[1], doc, row.get("role")))
    items.sort(key=lambda w: w.name.lower())
    return ListResponse[WorkspaceOut](items=items, count=len(items))


@router.post("/workspaces", response_model=WorkspaceOut, status_code=201)
def create_workspace(body: WorkspaceCreate, user: CurrentUser, store: Store):
    owned = [
        r
        for r in store.list_group("members", filters=[("uid", "==", user.uid)], limit=200)
        if r.get("role") == Role.OWNER and r.get("status", "active") == "active"
    ]
    if len(owned) >= MAX_OWNED_WORKSPACES:
        raise ConflictError(
            f"You can own at most {MAX_OWNED_WORKSPACES} workspaces.", code="workspace_limit_reached"
        )

    workspace_id, now = new_id(), utcnow()
    base = f"workspaces/{workspace_id}"
    config = AgentConfig(business_name=body.name).model_dump(by_alias=True)
    store.batch([
        ("create", base, {
            "name": body.name, "industry": body.industry, "timezone": body.timezone,
            "ownerId": user.uid, "isDemo": False, "createdAt": now, "updatedAt": now,
        }),
        ("create", _member_path(workspace_id, user.uid), {
            "uid": user.uid, "workspaceId": workspace_id, "email": user.email,
            "displayName": user.name or user.email, "role": Role.OWNER, "status": "active", "joinedAt": now,
        }),
        ("create", f"{base}/settings/agent_config", {**config, "updatedAt": now, "updatedBy": user.uid}),
    ])

    if store.get(f"users/{user.uid}"):
        store.update(f"users/{user.uid}", {"activeWorkspaceId": workspace_id, "updatedAt": now})
    else:
        store.set(f"users/{user.uid}", {
            "uid": user.uid, "email": user.email, "displayName": user.name or user.email, "photoUrl": None,
            "activeWorkspaceId": workspace_id, "createdAt": now, "updatedAt": now,
        })
    log_activity(
        store, workspace_id, actor_type=ActorType.USER, actor_id=user.uid, action="workspace.created",
        entity_type="workspace", entity_id=workspace_id, summary="Workspace created",
    )
    return _workspace_out(workspace_id, store.get(base) or {}, Role.OWNER)


@router.get("/workspaces/{workspace_id}", response_model=WorkspaceOut)
def get_workspace(ctx: MemberCtx, store: Store):
    doc = store.get(f"workspaces/{ctx.workspace_id}")
    if not doc:
        raise NotFoundError("Workspace not found.")
    return _workspace_out(ctx.workspace_id, doc, ctx.role)


@router.patch("/workspaces/{workspace_id}", response_model=WorkspaceOut)
def update_workspace(body: WorkspaceUpdate, ctx: ManagerCtx, store: Store):
    changes = body.model_dump(exclude_unset=True)
    if not changes:
        raise ValidationFailedError("No fields to update.")
    if "name" in changes and changes["name"] is None:
        raise ValidationFailedError("name cannot be empty.")
    if "timezone" in changes and changes["timezone"] is None:
        raise ValidationFailedError("timezone cannot be empty.")
    changes["updatedAt"] = utcnow()
    path = f"workspaces/{ctx.workspace_id}"
    store.update(path, changes)
    log_activity(
        store, ctx.workspace_id, actor_type=ActorType.USER, actor_id=ctx.actor_id,
        action="workspace.updated", entity_type="workspace", entity_id=ctx.workspace_id,
        summary="Workspace settings updated",
    )
    return _workspace_out(ctx.workspace_id, store.get(path) or {}, ctx.role)


# ---------- Members ----------
@router.get("/workspaces/{workspace_id}/members", response_model=ListResponse[MemberOut])
def list_members(ctx: MemberCtx, store: Store):
    rows = store.list(f"workspaces/{ctx.workspace_id}/members")
    members = [MemberOut.model_validate(r) for r in rows if r.get("status", "active") != "removed"]
    members.sort(key=lambda m: (m.display_name or m.email or m.uid).lower())
    return ListResponse[MemberOut](items=members, count=len(members))


@router.post("/workspaces/{workspace_id}/members", response_model=MemberOut, status_code=201)
def add_member(body: MemberAdd, ctx: ManagerCtx, store: Store, settings: AppSettings):
    if body.role == Role.ADMIN and ctx.role != Role.OWNER:
        raise ForbiddenError("Only the owner can add admins.")
    uid, display_name = _resolve_user(store, settings, body.email)
    path = _member_path(ctx.workspace_id, uid)
    existing = store.get(path)
    if existing and existing.get("status", "active") == "active":
        raise ConflictError("This user is already a member.", code="already_member")
    store.set(path, {
        "uid": uid, "workspaceId": ctx.workspace_id, "email": body.email, "displayName": display_name,
        "role": body.role, "status": "active", "joinedAt": utcnow(), "addedBy": ctx.actor_id,
    })
    log_activity(
        store, ctx.workspace_id, actor_type=ActorType.USER, actor_id=ctx.actor_id, action="member.added",
        entity_type="member", entity_id=uid, summary=f"Member added as {body.role.value}",
        metadata={"role": body.role},
    )
    return MemberOut.model_validate(store.get(path))


@router.patch("/workspaces/{workspace_id}/members/{uid}", response_model=MemberOut)
def update_member_role(uid: IdPath, body: MemberRoleUpdate, ctx: ManagerCtx, store: Store):
    member = _get_member(store, ctx.workspace_id, uid)
    current = Role(member["role"])
    if current == Role.OWNER:
        raise ForbiddenError("The owner's role cannot be changed.")
    if uid == ctx.user.uid:
        raise ForbiddenError("You cannot change your own role.")
    if ctx.role != Role.OWNER and Role.ADMIN in (current, body.role):
        raise ForbiddenError("Only the owner can grant or revoke the admin role.")
    path = _member_path(ctx.workspace_id, uid)
    store.update(path, {"role": body.role})
    log_activity(
        store, ctx.workspace_id, actor_type=ActorType.USER, actor_id=ctx.actor_id,
        action="member.role_changed", entity_type="member", entity_id=uid,
        summary=f"Role changed from {current.value} to {body.role.value}",
        metadata={"from": current, "to": body.role},
    )
    return MemberOut.model_validate(store.get(path))


@router.delete("/workspaces/{workspace_id}/members/{uid}", status_code=204)
def remove_member(uid: IdPath, ctx: ManagerCtx, store: Store) -> Response:
    member = _get_member(store, ctx.workspace_id, uid)
    current = Role(member["role"])
    if current == Role.OWNER:
        raise ForbiddenError("The owner cannot be removed.")
    if uid == ctx.user.uid:
        raise ForbiddenError("You cannot remove yourself.")
    if ctx.role != Role.OWNER and current == Role.ADMIN:
        raise ForbiddenError("Only the owner can remove an admin.")
    store.update(_member_path(ctx.workspace_id, uid), {"status": "removed", "removedAt": utcnow()})
    log_activity(
        store, ctx.workspace_id, actor_type=ActorType.USER, actor_id=ctx.actor_id,
        action="member.removed", entity_type="member", entity_id=uid, summary="Member removed",
    )
    return Response(status_code=204)