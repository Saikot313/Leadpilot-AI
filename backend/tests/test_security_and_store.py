import time

import pytest

from app.core.config import Settings
from app.core.errors import ConflictError, NotFoundError
from app.core.security import secrets_match, sign_payload, verify_signature
from app.services.firestore_client import MemoryStore, clean, deterministic_id
from app.schemas.common import LeadStatus

SECRET = "s3cret"
BODY = b'{"message":"hello"}'


def test_valid_signature_is_accepted():
    ts = str(int(time.time()))
    assert verify_signature(SECRET, ts, BODY, sign_payload(SECRET, ts, BODY))


def test_sha256_prefix_and_uppercase_are_tolerated():
    ts = str(int(time.time()))
    sig = sign_payload(SECRET, ts, BODY)
    assert verify_signature(SECRET, ts, BODY, "sha256=" + sig.upper())


def test_tampered_body_wrong_secret_and_missing_parts_are_rejected():
    ts = str(int(time.time()))
    sig = sign_payload(SECRET, ts, BODY)
    assert not verify_signature(SECRET, ts, BODY + b" ", sig)
    assert not verify_signature("other", ts, BODY, sig)
    assert not verify_signature(SECRET, None, BODY, sig)
    assert not verify_signature(SECRET, ts, BODY, None)
    assert not verify_signature("", ts, BODY, sig)
    assert not verify_signature(SECRET, "not-a-number", BODY, sig)


def test_stale_and_future_timestamps_are_rejected_to_prevent_replay():
    now = 1_800_000_000.0
    old = str(int(now) - 301)
    future = str(int(now) + 301)
    ok = str(int(now) - 100)
    assert not verify_signature(SECRET, old, BODY, sign_payload(SECRET, old, BODY), now=now)
    assert not verify_signature(SECRET, future, BODY, sign_payload(SECRET, future, BODY), now=now)
    assert verify_signature(SECRET, ok, BODY, sign_payload(SECRET, ok, BODY), now=now)


def test_secrets_match_is_strict():
    assert secrets_match("abc", "abc")
    assert not secrets_match("abc", "abd")
    assert not secrets_match(None, "abc")
    assert not secrets_match("", "")


def test_create_conflicts_on_existing_documents():
    s = MemoryStore()
    s.create("c/1", {"x": 1})
    with pytest.raises(ConflictError):
        s.create("c/1", {"x": 2})
    assert s.get("c/1")["x"] == 1


def test_update_requires_an_existing_document():
    s = MemoryStore()
    with pytest.raises(NotFoundError):
        s.update("c/missing", {"x": 1})


def test_batch_is_atomic():
    s = MemoryStore()
    s.create("c/exists", {"v": 1})
    with pytest.raises(ConflictError):
        s.batch([("create", "c/new", {"v": 2}), ("create", "c/exists", {"v": 3})])
    assert s.get("c/new") is None
    assert s.get("c/exists")["v"] == 1


def test_compare_and_update_only_applies_when_expectation_holds():
    s = MemoryStore()
    s.set("c/1", {"status": "pending"})
    assert s.compare_and_update("c/1", {"status": "pending"}, {"status": "done"}) is True
    assert s.compare_and_update("c/1", {"status": "pending"}, {"status": "again"}) is False
    assert s.get("c/1")["status"] == "done"
    assert s.compare_and_update("c/none", {"status": "x"}, {"status": "y"}) is False


def test_list_filters_orders_and_limits_direct_children_only():
    s = MemoryStore()
    for i, v in enumerate([3, 1, 2]):
        s.set(f"c/{i}", {"v": v})
    s.set("c/0/sub/1", {"v": 99})  # nested documents must not appear in the parent listing
    rows = s.list("c", filters=[("v", ">", 1)], order_by="v", descending=True)
    assert [r["v"] for r in rows] == [3, 2]
    assert len(s.list("c", limit=1)) == 1


def test_clean_converts_enums_and_models():
    assert clean({"status": LeadStatus.QUALIFIED, "tags": [LeadStatus.NEW]}) == {
        "status": "qualified",
        "tags": ["new"],
    }


def test_deterministic_ids_are_stable_and_distinct():
    assert deterministic_id("lead", "evt-1") == deterministic_id("lead", "evt-1")
    assert deterministic_id("lead", "evt-1") != deterministic_id("lead", "evt-2")


def test_production_refuses_demo_mode():
    with pytest.raises(ValueError):
        Settings(app_env="production", demo_mode=True)


def test_live_mode_requires_a_firebase_project():
    with pytest.raises(ValueError):
        Settings(demo_mode=False, firebase_project_id="")


def test_booking_slot_must_divide_an_hour():
    with pytest.raises(ValueError):
        Settings(booking_slot_minutes=45)