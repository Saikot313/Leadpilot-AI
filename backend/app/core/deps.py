"""FastAPI dependencies: auth, workspace membership, roles, callback secret."""
from dataclasses import dataclass
from typing import Annotated

from fastapi import Depends, Header, Path

from app.core.config import DEMO_USER_ID, Settings, get_settings
from app.core.errors import ForbiddenError, ServiceUnavailableError, UnauthorizedError
from app.core.security import secrets_match, verify_id_token
from app.schemas.common import ID_PATTERN, Role
from app.services.firestore_client import DocumentStore, get_store


@dataclass(frozen=True)
class AuthUser:
    uid: str
    email: str | None = None
    name: str | None = None


@dataclass(frozen=True)
class WorkspaceContext:
    user: AuthUser
    workspace_id: str
    role: Role

    @property
    def actor_id(self) -> str:
        return self.user.uid


def get_current_user(
    authorization: Annotated[str | None, Header()] = None,
    settings: Settings = Depends(get_settings),
) -> AuthUser:
    if settings.demo_mode:
        return AuthUser(uid=DEMO_USER_ID, email="demo@leadpilot.local", name="Demo User")
    if not authorization or not authorization.lower().startswith("bearer "):
        raise UnauthorizedError("Missing bearer token.")
    token = authorization[7:].strip()
    if not token:
        raise UnauthorizedError("Missing bearer token.")
    claims = verify_id_token(token)
    uid = claims.get("uid") or claims.get("sub")
    if not uid:
        raise UnauthorizedError("Invalid token claims.")
    return AuthUser(uid=uid, email=claims.get("email"), name=claims.get("name"))


def get_workspace_ctx(
    workspace_id: Annotated[str, Path(pattern=ID_PATTERN)],
    user: AuthUser = Depends(get_current_user),
    store: DocumentStore = Depends(get_store),
) -> WorkspaceContext:
    member = store.get(f"workspaces/{workspace_id}/members/{user.uid}")
    if not member or member.get("status", "active") != "active":
        raise ForbiddenError("You do not have access to this workspace.")
    try:
        role = Role(member.get("role"))
    except ValueError as exc:
        raise ForbiddenError("Invalid workspace role.") from exc
    return WorkspaceContext(user=user, workspace_id=workspace_id, role=role)


def require_roles(*roles: Role):
    def checker(ctx: WorkspaceContext = Depends(get_workspace_ctx)) -> WorkspaceContext:
        if ctx.role not in roles:
            raise ForbiddenError("Your role does not allow this action.")
        return ctx

    return checker


def verify_callback_secret(
    x_leadpilot_callback_secret: Annotated[str | None, Header()] = None,
    settings: Settings = Depends(get_settings),
) -> None:
    if not settings.callbacks_configured:
        raise ServiceUnavailableError("Callbacks are disabled: BACKEND_CALLBACK_SECRET is not set.")
    if not secrets_match(x_leadpilot_callback_secret, settings.backend_callback_secret.get_secret_value()):
        raise UnauthorizedError("Invalid callback credentials.")


# ---- Annotated shortcuts for route signatures ----
AppSettings = Annotated[Settings, Depends(get_settings)]
Store = Annotated[DocumentStore, Depends(get_store)]
CurrentUser = Annotated[AuthUser, Depends(get_current_user)]
MemberCtx = Annotated[WorkspaceContext, Depends(get_workspace_ctx)]
WriterCtx = Annotated[WorkspaceContext, Depends(require_roles(Role.OWNER, Role.ADMIN, Role.AGENT))]
ManagerCtx = Annotated[WorkspaceContext, Depends(require_roles(Role.OWNER, Role.ADMIN))]
CallbackAuth = Annotated[None, Depends(verify_callback_secret)]