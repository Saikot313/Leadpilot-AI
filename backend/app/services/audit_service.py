"""Activity audit trail and error log. Logging failures never break the calling request."""
from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Any

from app.core.logging import get_logger
from app.schemas.common import ActorType, utcnow
from app.schemas.monitoring import ActivityLogOut, ErrorLogOut
from app.services.firestore_client import DocumentStore, new_id

logger = get_logger("leadpilot.audit")

_SENSITIVE_KEY_PARTS = ("message", "body", "email", "phone", "secret", "token", "password", "key")


def _safe_metadata(meta: dict[str, Any] | None) -> dict[str, Any]:
    """Keep small scalar values only; drop anything that could hold customer content or secrets."""
    out: dict[str, Any] = {}
    for key, value in (meta or {}).items():
        if any(part in key.lower() for part in _SENSITIVE_KEY_PARTS):
            continue
        if isinstance(value, Enum):
            out[key] = value.value
        elif isinstance(value, (bool, int, float)) or value is None:
            out[key] = value
        elif isinstance(value, str):
            out[key] = value[:200]
    return out


def log_activity(
    store: DocumentStore,
    workspace_id: str,
    *,
    actor_type: ActorType,
    actor_id: str | None,
    action: str,
    entity_type: str | None = None,
    entity_id: str | None = None,
    summary: str = "",
    metadata: dict[str, Any] | None = None,
) -> None:
    try:
        store.set(
            f"workspaces/{workspace_id}/activity/{new_id()}",
            {
                "workspaceId": workspace_id,
                "actorType": actor_type,
                "actorId": actor_id,
                "action": action,
                "entityType": entity_type,
                "entityId": entity_id,
                "summary": summary[:300],
                "metadata": _safe_metadata(metadata),
                "createdAt": utcnow(),
            },
        )
    except Exception:  # noqa: BLE001
        logger.exception("activity_log_failed", extra={"action": action})


def log_error(
    store: DocumentStore,
    workspace_id: str,
    *,
    source: str,
    message: str,
    code: str | None = None,
    workflow: str | None = None,
    execution_id: str | None = None,
    lead_id: str | None = None,
    retry_status: str | None = None,
) -> None:
    try:
        store.set(
            f"workspaces/{workspace_id}/errors/{new_id()}",
            {
                "workspaceId": workspace_id,
                "source": source,
                "code": code,
                "message": message[:500],
                "workflow": workflow,
                "executionId": execution_id,
                "leadId": lead_id,
                "retryStatus": retry_status,
                "createdAt": utcnow(),
            },
        )
    except Exception:  # noqa: BLE001
        logger.exception("error_log_failed", extra={"source": source})


def list_activity(store: DocumentStore, workspace_id: str, limit: int = 100) -> list[ActivityLogOut]:
    rows = store.list(
        f"workspaces/{workspace_id}/activity", order_by="createdAt", descending=True, limit=min(limit, 500)
    )
    return [ActivityLogOut.model_validate(r) for r in rows]


def list_errors(
    store: DocumentStore, workspace_id: str, limit: int = 100, since: datetime | None = None
) -> list[ErrorLogOut]:
    filters = [("createdAt", ">=", since)] if since else None
    rows = store.list(
        f"workspaces/{workspace_id}/errors",
        filters=filters,
        order_by="createdAt",
        descending=True,
        limit=min(limit, 500),
    )
    return [ErrorLogOut.model_validate(r) for r in rows]