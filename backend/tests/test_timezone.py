"""
Regression tests for the UTC / East Africa Time boundary.

The server stores naive UTC and users are in Kenya (UTC+3, no DST). Before this
was fixed, months were filtered with extract("month", date_added) in UTC while
the app asked for the month it saw locally, so anything logged between 00:00 and
03:00 EAT fell into the previous UTC day - and on the 1st of a month it dropped
out of that month's list, totals, budget variance and health score entirely.

The first test in this file is that exact case.

Run it directly, no pytest needed:

    cd backend
    venv/Scripts/python tests/test_timezone.py     # Windows
    venv/bin/python tests/test_timezone.py         # Linux/macOS
"""
import os
import re
import sys
import tempfile
import uuid
from datetime import datetime, date

BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, BACKEND_DIR)

_DB_PATH = os.path.join(tempfile.mkdtemp(prefix="sft-tz-"), "test.db")
os.environ["DATABASE_URL"] = "sqlite:///" + _DB_PATH.replace(os.sep, "/")
os.environ.setdefault("JWT_SECRET_KEY", "test-secret-not-used-in-production")

from flask_migrate import upgrade                                     # noqa: E402

from app import create_app                                            # noqa: E402
from app_time import (default_timezone, iso_utc, local_date_of,       # noqa: E402
                      month_range_utc, to_tz)
from services.analysis_service import (_calculate_overspent_days,     # noqa: E402
                                       _calculate_overspending_streak)

# This suite covers the Kenyan default zone; per-user zones live in
# test_user_timezone.py.
NBO = default_timezone()

_app = create_app()
_app.config["PROPAGATE_EXCEPTIONS"] = False
_app.config["TESTING"] = True
# The schema comes from the migrations now, not db.create_all().
with _app.app_context():
    upgrade()
CLIENT = _app.test_client()


def _new_user():
    username = "tz-" + uuid.uuid4().hex[:8]
    r = CLIENT.post("/api/auth/register",
                    json={"username": username, "password": "correct-horse"})
    assert r.status_code == 201, r.get_data(as_text=True)
    return {"Authorization": "Bearer " + r.get_json()["token"]}


HEADERS = _new_user()


def _expense_at(utc_iso, headers=None, amount=100.0, category="Food"):
    """Create an expense and force its stored (naive UTC) timestamp."""
    h = headers or HEADERS
    r = CLIENT.post("/api/expenses", json={"amount": amount, "category": category},
                    headers=h)
    assert r.status_code == 201, r.get_data(as_text=True)
    eid = r.get_json()["expense"]["id"]
    r = CLIENT.put("/api/expenses/%s" % eid, json={"date_added": utc_iso}, headers=h)
    assert r.status_code == 200, r.get_data(as_text=True)
    return r.get_json()["expense"]


def _expense_ids_for(month, year, headers=None):
    r = CLIENT.get("/api/expenses?month=%d&year=%d" % (month, year),
                   headers=headers or HEADERS)
    assert r.status_code == 200, r.get_data(as_text=True)
    return [e["id"] for e in r.get_json()["expenses"]]


# ── The bug ───────────────────────────────────────────────────────────────────

def test_after_midnight_local_belongs_to_the_new_month():
    """
    01:00 EAT on 1 February is 22:00 UTC on 31 January.

    Filtering in UTC put this in January, so it vanished from February's
    figures. It must come back for February and not for January.
    """
    user = _new_user()
    expense = _expense_at("2026-01-31T22:00:00", headers=user)

    assert expense["id"] in _expense_ids_for(2, 2026, user), \
        "01:00 EAT on 1 Feb is missing from February"
    assert expense["id"] not in _expense_ids_for(1, 2026, user), \
        "01:00 EAT on 1 Feb is wrongly counted in January"


def test_late_evening_local_stays_in_the_old_month():
    """23:30 EAT on 31 January is 20:30 UTC the same day - still January."""
    user = _new_user()
    expense = _expense_at("2026-01-31T20:30:00", headers=user)

    assert expense["id"] in _expense_ids_for(1, 2026, user)
    assert expense["id"] not in _expense_ids_for(2, 2026, user)


def test_the_missing_money_shows_up_in_the_month_total():
    """The same case, but through the totals rather than the list."""
    user = _new_user()
    _expense_at("2026-01-31T22:00:00", headers=user, amount=250.0)   # 1 Feb, 01:00 EAT

    r = CLIENT.post("/api/analyze", json={"month": 2, "year": 2026}, headers=user)
    assert r.status_code == 200, r.get_data(as_text=True)
    assert r.get_json()["expenses"] == 250.0, \
        "February's expense total lost the after-midnight transaction"


# ── Month boundaries ──────────────────────────────────────────────────────────

def test_month_range_is_half_open():
    start, end = month_range_utc(2026, 2, NBO)
    assert start == datetime(2026, 1, 31, 21, 0), start
    assert end == datetime(2026, 2, 28, 21, 0), end


def test_month_range_wraps_the_year():
    assert month_range_utc(2026, 1, NBO)[0] == datetime(2025, 12, 31, 21, 0)
    assert month_range_utc(2026, 12, NBO)[1] == datetime(2026, 12, 31, 21, 0)


def test_first_and_last_instants_land_in_exactly_one_month():
    user = _new_user()
    start, end = month_range_utc(2026, 2, NBO)

    first = _expense_at(start.isoformat(), headers=user)
    last = _expense_at((end.replace(microsecond=0)).isoformat(), headers=user)

    feb = _expense_ids_for(2, 2026, user)
    mar = _expense_ids_for(3, 2026, user)

    assert first["id"] in feb, "first instant of February excluded from February"
    assert last["id"] not in feb, "first instant of March counted in February"
    assert last["id"] in mar, "first instant of March missing from March"


# ── Serialization ─────────────────────────────────────────────────────────────

def test_timestamps_are_marked_utc():
    """Without the marker the client parses the string as local and shows it 3h early."""
    expense = _expense_at("2026-01-31T22:00:00")
    assert expense["date_added"].endswith("Z"), expense["date_added"]


def test_calendar_dates_carry_no_timezone():
    """A goal due date is a calendar day - marking it UTC would shift it."""
    r = CLIENT.post("/api/goals",
                    json={"name": "Laptop", "goal_amount": 50000, "due_date": "2026-12-01"},
                    headers=HEADERS)
    assert r.status_code == 201, r.get_data(as_text=True)
    goal = r.get_json()["goal"]

    assert re.match(r"^\d{4}-\d{2}-\d{2}$", goal["due_date"]), goal["due_date"]
    assert goal["due_date"] == "2026-12-01"
    assert goal["date_set"].endswith("Z"), "date_set is a timestamp and should be marked"


def test_helb_plan_dates_carry_no_timezone():
    r = CLIENT.post("/api/helb/plan",
                    json={"semester_name": "Sem 1", "helb_amount": 40000,
                          "start_date": "2026-01-05", "end_date": "2026-05-30",
                          "allocations": {}},
                    headers=HEADERS)
    assert r.status_code == 201, r.get_data(as_text=True)
    plan = r.get_json()["plan"]
    assert plan["start_date"] == "2026-01-05"
    assert plan["end_date"] == "2026-05-30"
    assert plan["created_at"].endswith("Z")


# ── Daily buckets ─────────────────────────────────────────────────────────────

class _FakeExpense:
    def __init__(self, stored_utc, amount):
        self.date_added = stored_utc
        self.amount = amount


def test_daily_buckets_use_the_local_day():
    """
    Two expenses 01:00 and 23:00 EAT on 1 February are one local day apart from
    31 January, but in UTC they straddle two different dates. Bucketing on the
    UTC date splits a single day's spending in two and understates the overage.
    """
    same_local_day = [
        _FakeExpense(datetime(2026, 1, 31, 22, 0), 600.0),   # 01:00 EAT, 1 Feb
        _FakeExpense(datetime(2026, 2, 1, 20, 0), 600.0),    # 23:00 EAT, 1 Feb
    ]
    assert local_date_of(same_local_day[0].date_added, NBO) == date(2026, 2, 1)
    assert local_date_of(same_local_day[1].date_added, NBO) == date(2026, 2, 1)

    # Both fall on one local day totalling 1200 against a 1000 budget: one
    # overspent day. Bucketed by UTC date it would be two days of 600, i.e. none.
    assert _calculate_overspent_days(same_local_day, 1000.0, NBO) == 1
    assert _calculate_overspending_streak(same_local_day, 1000.0, NBO) == 1


# ── Helpers ───────────────────────────────────────────────────────────────────

def test_to_tz_adds_three_hours():
    assert to_tz(datetime(2026, 1, 31, 22, 0), NBO).hour == 1
    assert to_tz(datetime(2026, 1, 31, 22, 0), NBO).day == 1


def test_app_timezone_has_no_dst():
    """Kenya has never observed DST; the offset is constant across the year."""
    offsets = {NBO.utcoffset(datetime(2026, m, 15)) for m in range(1, 13)}
    assert len(offsets) == 1, offsets


def test_iso_utc_handles_none_and_aware_values():
    from datetime import timezone as _tz, timedelta as _td
    assert iso_utc(None) is None
    aware = datetime(2026, 2, 1, 1, 0, tzinfo=_tz(_td(hours=3)))
    assert iso_utc(aware) == "2026-01-31T22:00:00Z"


# ── Runner ────────────────────────────────────────────────────────────────────

def main():
    tests = [(name, fn) for name, fn in sorted(globals().items())
             if name.startswith("test_") and callable(fn)]
    failures = []
    for name, fn in tests:
        try:
            fn()
            print("PASS  %s" % name)
        except AssertionError as e:
            failures.append(name)
            print("FAIL  %s\n      %s" % (name, e))
    print("\n%d/%d passed" % (len(tests) - len(failures), len(tests)))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
