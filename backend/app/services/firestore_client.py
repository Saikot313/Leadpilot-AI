"""Document store abstraction: Firestore in live mode, in-memory store in demo mode and tests."""
from __future__ import annotations

import hashlib
import operator
import threading
import uuid
from abc import ABC, abstractmethod
from copy import deepcopy
from enum import Enum
from functools import lru_cache
from typing import Any

from pydantic import BaseModel

from app.core.config import get_settings
from app.core.errors import ConflictError, NotFoundError

Filter = tuple[str, str, Any]  # (field, op, value); ops: == != < <= > >= in array_contains
WriteOp = tuple[str, str, dict[str, Any] | None]  # ("create"|"set"|"update"|"delete", path, data)
MAX_BATCH_OPS = 400


def new_id() -> str:
    return uuid.uuid4().hex[:20]


def deterministic_id(prefix: str, key: str) -> str:
    """Stable document ID for idempotency (same key -> same ID)."""
    return f"{prefix}_{hashlib.sha256(key.encode()).hexdigest()[:24]}"


def clean(value: Any) -> Any:
    """Convert models and enums into Firestore-safe values. Datetimes are kept as-is."""
    if isinstance(value, BaseModel):
        return clean(value.model_dump(by_alias=True))
    if isinstance(value, Enum):
        return value.value
    if isinstance(value, dict):
        return {k: clean(v) for k, v in value.items()}
    if isinstance(value, (list, tuple, set)):
        return [clean(v) for v in value]
    return value


class DocumentStore(ABC):
    """Paths use Firestore style: documents have an even number of segments, collections an odd number.
    Returned dicts always include an `id` key."""

    @abstractmethod
    def get(self, path: str) -> dict[str, Any] | None: ...

    @abstractmethod
    def set(self, path: str, data: dict[str, Any], merge: bool = False) -> None: ...

    @abstractmethod
    def create(self, path: str, data: dict[str, Any]) -> None:
        """Create a document. Raises ConflictError if it already exists."""

    @abstractmethod
    def update(self, path: str, data: dict[str, Any]) -> None:
        """Shallow-merge top-level fields. Raises NotFoundError if missing."""

    @abstractmethod
    def delete(self, path: str) -> None: ...

    @abstractmethod
    def list(
        self,
        collection: str,
        filters: list[Filter] | None = None,
        order_by: str | None = None,
        descending: bool = False,
        limit: int | None = None,
    ) -> list[dict[str, Any]]: ...

    @abstractmethod
    def list_group(
        self, collection_id: str, filters: list[Filter] | None = None, limit: int | None = None
    ) -> list[dict[str, Any]]:
        """Query every collection with this ID. Rows include `_path`."""

    @abstractmethod
    def batch(self, ops: list[WriteOp]) -> None:
        """Apply writes atomically. A `create` on an existing document aborts everything (ConflictError)."""

    @abstractmethod
    def compare_and_update(self, path: str, expected: dict[str, Any], data: dict[str, Any]) -> bool:
        """Atomically update only if all `expected` fields currently match. Returns False otherwise."""


# ---------------------------------------------------------------------------
# In-memory implementation (demo mode and tests)
# ---------------------------------------------------------------------------
_OPS = {
    "==": operator.eq,
    "!=": operator.ne,
    "<": operator.lt,
    "<=": operator.le,
    ">": operator.gt,
    ">=": operator.ge,
    "in": lambda a, b: a in b,
    "array_contains": lambda a, b: isinstance(a, list) and b in a,
}


def _matches(data: dict[str, Any], filters: list[Filter]) -> bool:
    for field, op, value in filters:
        actual = data.get(field)
        if actual is None and op not in ("==", "!="):
            return False
        try:
            if not _OPS[op](actual, value):
                return False
        except TypeError:
            return False
    return True


class MemoryStore(DocumentStore):
    def __init__(self) -> None:
        self._docs: dict[str, dict[str, Any]] = {}
        self._lock = threading.RLock()

    @staticmethod
    def _row(path: str, data: dict[str, Any]) -> dict[str, Any]:
        return {**deepcopy(data), "id": path.rsplit("/", 1)[-1]}

    def get(self, path):
        with self._lock:
            data = self._docs.get(path)
            return self._row(path, data) if data is not None else None

    def set(self, path, data, merge=False):
        with self._lock:
            payload = deepcopy(clean(data))
            if merge and path in self._docs:
                self._docs[path] = {**self._docs[path], **payload}
            else:
                self._docs[path] = payload

    def create(self, path, data):
        with self._lock:
            if path in self._docs:
                raise ConflictError("Document already exists.")
            self._docs[path] = deepcopy(clean(data))

    def update(self, path, data):
        with self._lock:
            if path not in self._docs:
                raise NotFoundError("Document not found.")
            self._docs[path] = {**self._docs[path], **deepcopy(clean(data))}

    def delete(self, path):
        with self._lock:
            self._docs.pop(path, None)

    def _children(self, collection: str):
        prefix = collection.rstrip("/") + "/"
        for path, data in list(self._docs.items()):
            if path.startswith(prefix) and "/" not in path[len(prefix):]:
                yield path, data

    def list(self, collection, filters=None, order_by=None, descending=False, limit=None):
        with self._lock:
            rows = [self._row(p, d) for p, d in self._children(collection) if _matches(d, filters or [])]
        if order_by:
            rows = [r for r in rows if r.get(order_by) is not None]
            rows.sort(key=lambda r: r[order_by], reverse=descending)
        return rows[:limit] if limit else rows

    def list_group(self, collection_id, filters=None, limit=None):
        with self._lock:
            rows = []
            for path, data in self._docs.items():
                parts = path.split("/")
                if len(parts) >= 2 and parts[-2] == collection_id and _matches(data, filters or []):
                    rows.append({**self._row(path, data), "_path": path})
        return rows[:limit] if limit else rows

    def batch(self, ops):
        if len(ops) > MAX_BATCH_OPS:
            raise ValueError("Too many operations in one batch.")
        with self._lock:
            seen_creates: set[str] = set()
            for op, path, _ in ops:
                if op == "create":
                    if path in self._docs or path in seen_creates:
                        raise ConflictError("Document already exists.")
                    seen_creates.add(path)
                elif op == "update" and path not in self._docs and path not in seen_creates:
                    raise NotFoundError("Document not found.")
            for op, path, data in ops:
                if op in ("create", "set"):
                    self._docs[path] = deepcopy(clean(data))
                elif op == "update":
                    self._docs[path] = {**self._docs[path], **deepcopy(clean(data))}
                elif op == "delete":
                    self._docs.pop(path, None)

    def compare_and_update(self, path, expected, data):
        with self._lock:
            current = self._docs.get(path)
            if current is None or any(current.get(k) != v for k, v in expected.items()):
                return False
            self._docs[path] = {**current, **deepcopy(clean(data))}
            return True


# ---------------------------------------------------------------------------
# Firestore implementation (live mode)
# ---------------------------------------------------------------------------
class FirestoreStore(DocumentStore):
    def __init__(self) -> None:
        from firebase_admin import firestore

        from app.core.security import init_firebase_app

        init_firebase_app()
        self._client = firestore.client()

    @staticmethod
    def _row(snap) -> dict[str, Any]:
        return {**(snap.to_dict() or {}), "id": snap.id}

    def get(self, path):
        snap = self._client.document(path).get()
        return self._row(snap) if snap.exists else None

    def set(self, path, data, merge=False):
        self._client.document(path).set(clean(data), merge=merge)

    def create(self, path, data):
        from google.api_core import exceptions as gexc

        try:
            self._client.document(path).create(clean(data))
        except gexc.AlreadyExists as exc:
            raise ConflictError("Document already exists.") from exc

    def update(self, path, data):
        from google.api_core import exceptions as gexc

        try:
            self._client.document(path).update(clean(data))
        except gexc.NotFound as exc:
            raise NotFoundError("Document not found.") from exc

    def delete(self, path):
        self._client.document(path).delete()

    def _apply(self, query, filters, order_by, descending, limit):
        from google.cloud import firestore as gcf
        from google.cloud.firestore_v1.base_query import FieldFilter

        for field, op, value in filters or []:
            query = query.where(filter=FieldFilter(field, op, clean(value)))
        if order_by:
            direction = gcf.Query.DESCENDING if descending else gcf.Query.ASCENDING
            query = query.order_by(order_by, direction=direction)
        if limit:
            query = query.limit(limit)
        return query

    def list(self, collection, filters=None, order_by=None, descending=False, limit=None):
        query = self._apply(self._client.collection(collection), filters, order_by, descending, limit)
        return [self._row(s) for s in query.stream()]

    def list_group(self, collection_id, filters=None, limit=None):
        query = self._apply(self._client.collection_group(collection_id), filters, None, False, limit)
        return [{**self._row(s), "_path": s.reference.path} for s in query.stream()]

    def batch(self, ops):
        from google.api_core import exceptions as gexc

        if len(ops) > MAX_BATCH_OPS:
            raise ValueError("Too many operations in one batch.")
        batch = self._client.batch()
        for op, path, data in ops:
            ref = self._client.document(path)
            if op == "create":
                batch.create(ref, clean(data))
            elif op == "set":
                batch.set(ref, clean(data))
            elif op == "update":
                batch.update(ref, clean(data))
            elif op == "delete":
                batch.delete(ref)
        try:
            batch.commit()
        except gexc.AlreadyExists as exc:
            raise ConflictError("Document already exists.") from exc
        except gexc.NotFound as exc:
            raise NotFoundError("Document not found.") from exc

    def compare_and_update(self, path, expected, data):
        from google.cloud import firestore as gcf

        ref = self._client.document(path)
        payload = clean(data)

        @gcf.transactional
        def run(txn) -> bool:
            snap = ref.get(transaction=txn)
            if not snap.exists:
                return False
            current = snap.to_dict() or {}
            if any(current.get(k) != v for k, v in expected.items()):
                return False
            txn.update(ref, payload)
            return True

        return run(self._client.transaction())


@lru_cache
def get_store() -> DocumentStore:
    settings = get_settings()
    if settings.demo_mode:
        from app.services.demo_data import seed_demo_store

        store = MemoryStore()
        seed_demo_store(store)
        return store
    return FirestoreStore()