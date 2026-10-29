from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

import pytest

from app.core.config import get_settings
from app.core.errors import ValidationFailedError
from app.services.booking_service import get_availability, slot_key, slot_starts, validate_window
from app.services.firestore_client import MemoryStore

DHAKA = ZoneInfo("Asia/Dhaka")
NOW = datetime(2026, 11, 1, 0, 0, tzinfo=timezone.utc)


def dhaka(y, m, d, h, mi=0):
    return datetime(y, m, d, h, mi, tzinfo=DHAKA).astimezone(timezone.utc)


def code_of(start, minutes=30):
    with pytest.raises(ValidationFailedError) as exc:
        validate_window(get_settings(), start, minutes, now=NOW)
    return exc.value.code


def test_valid_window_returns_end_and_reserved_minutes():
    end, reserved = validate_window(get_settings(), dhaka(2026, 11, 2, 10), 30, now=NOW)
    assert reserved == 30
    assert end == dhaka(2026, 11, 2, 10, 30)


def test_duration_rounds_up_to_whole_slots():
    end, reserved = validate_window(get_settings(), dhaka(2026, 11, 2, 10), 40, now=NOW)
    assert reserved == 60
    assert end == dhaka(2026, 11, 2, 11)


def test_last_slot_of_the_day_is_allowed():
    end, _ = validate_window(get_settings(), dhaka(2026, 11, 2, 16, 30), 30, now=NOW)
    assert end == dhaka(2026, 11, 2, 17)


def test_past_misaligned_and_out_of_hours_are_rejected():
    assert code_of(dhaka(2026, 10, 30, 10)) == "booking_in_past"
    assert code_of(dhaka(2026, 11, 2, 10, 15)) == "booking_misaligned"
    assert code_of(dhaka(2026, 11, 2, 8, 30)) == "booking_outside_hours"
    assert code_of(dhaka(2026, 11, 2, 17)) == "booking_outside_hours"
    assert code_of(dhaka(2026, 11, 2, 16, 30), minutes=60) == "booking_outside_hours"


def test_slot_key_is_utc_and_stable():
    assert slot_key(dhaka(2026, 11, 2, 10)) == "20261102T0400"
    assert slot_key(datetime(2026, 11, 2, 4, 0, tzinfo=timezone.utc)) == "20261102T0400"


def test_slot_starts_cover_the_reserved_window():
    start = dhaka(2026, 11, 2, 10)
    assert slot_starts(start, 60, 30) == [start, start + timedelta(minutes=30)]
    assert len(slot_starts(start, 90, 30)) == 3


def test_availability_marks_taken_slots_unavailable():
    settings = get_settings()
    store = MemoryStore()
    day = date.today() + timedelta(days=5)

    before = get_availability(store, settings, "w", day)
    assert len(before.slots) == 16  # 09:00-17:00 in 30-minute slots
    assert all(s.available for s in before.slots)
    assert before.timezone == "Asia/Dhaka"

    first = before.slots[0]
    store.set(f"workspaces/w/bookingSlots/{slot_key(first.start_at)}", {"startAt": first.start_at})
    after = get_availability(store, settings, "w", day)
    assert after.slots[0].available is False
    assert sum(s.available for s in after.slots) == 15