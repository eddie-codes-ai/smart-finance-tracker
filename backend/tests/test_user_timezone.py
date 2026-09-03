"""
Tests for per-user home time zones.

Pinning the backend to Africa/Nairobi fixed things for Kenyan users but simply
relocated the bug: a user in Toronto logging at 20:00 on 31 August local is
01:00 UTC on 1 September, which is 04:00 in Nairobi, so their expense was filed
to September when they expect August.

Each user now carries a home IANA zone, and every month boundary is computed in
it. The headline test here is that the *same stored instant* belongs to
different months for two users in different countries - and both answers are
correct.

The zone is deliberately the user's HOME zone rather than their device's current
one: if boundaries followed the phone, flying abroad would silently re-bucket a
user's existing history.

Run it directly, no pytest needed:

    cd backend
    venv/Scripts/python tests/test_user_timezone.py     # Windows
    venv/bin/python tests/test_user_timezone.py         # Linux/macOS
"""
import os
import sys
import tempfile
import uuid
from datetime import datetime

BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, BACKEND_DIR)

_DB_PATH = os.path.join(tempfile.mkdtemp(prefix="sft-usertz-"), "test.db")
os.environ["DATABASE_URL"] = "sqlite:///" + _DB_PATH.replace(os.sep, "/")
os.environ.setdefault("JWT_SECRET_KEY", "test-secret-not-used-in-production")

from flask_migrate import upgrade                                     # noqa: E402

from app import create_app                                            # noqa: E402
from app_time import (DEFAULT_TIMEZONE_NAME, is_valid_timezone,       # noqa: E402
                      month_range_utc, resolve_timezone)

_app = create_app()
_app.config["PROPAGATE_EXCEPTIONS"] = False
_app.config["TESTING"] = True
with _app.app_context():
    upgrade()
CLIENT = _app.test_client()


def _user(timezone=None):
    """Register a user, optionally with a home zone, and return its headers."""
    payload = {"username": "u-" + uuid.uuid4().hex[:8], "password": "correct-horse"}
    if timezone is not None:
        payload["timezone"] = timezone
    r = CLIENT.post("/api/auth/register", json=payload)
    assert r.status_code == 201, r.get_data(as_text=True)
    body = r.get_json()
    return {"Authorization": "Bearer " + body["token"]}, body["user"]


def _expense_at(utc_iso, headers, amount=100.0):
    r = CLIENT.post("/api/expenses", json={"amount": amount, "category": "Food"},
                    headers=headers)
    assert r.status_code == 201, r.get_data(as_text=True)
    eid = r.get_json()["expense"]["id"]
    r = CLIENT.put("/api/expenses/%s" % eid, json={"date_added": utc_iso},
                   headers=headers)
    assert r.status_code == 200, r.get_data(as_text=True)
    return r.get_json()["expense"]


def _ids_for(month, year, headers):
    r = CLIENT.get("/api/expenses?month=%d&year=%d" % (month, year), headers=headers)
    assert r.status_code == 200, r.get_data(as_text=True)
    return [e["id"] for e in r.get_json()["expenses"]]


# ── The headline case ─────────────────────────────────────────────────────────

def test_same_instant_lands_in_different_months_for_different_users():
    """
    2026-09-01T01:00Z is 20:00 on 31 August in Toronto and 04:00 on
    1 September in Nairobi. Both users should see their own answer.
    """
    stored = "2026-09-01T01:00:00"

    toronto, _ = _user("America/Toronto")
    nairobi, _ = _user("Africa/Nairobi")

    t_expense = _expense_at(stored, toronto)
    n_expense = _expense_at(stored, nairobi)

    assert t_expense["id"] in _ids_for(8, 2026, toronto), \
        "Toronto user's 31 August evening expense is missing from August"
    assert t_expense["id"] not in _ids_for(9, 2026, toronto), \
        "Toronto user's expense leaked into September"

    assert n_expense["id"] in _ids_for(9, 2026, nairobi), \
        "Nairobi user's 1 September expense is missing from September"
    assert n_expense["id"] not in _ids_for(8, 2026, nairobi), \
        "Nairobi user's expense leaked into August"


def test_month_totals_follow_the_users_own_zone():
    stored = "2026-09-01T01:00:00"
    toronto, _ = _user("America/Toronto")
    _expense_at(stored, toronto, amount=400.0)

    august = CLIENT.post("/api/analyze", json={"month": 8, "year": 2026},
                         headers=toronto).get_json()
    september = CLIENT.post("/api/analyze", json={"month": 9, "year": 2026},
                            headers=toronto).get_json()

    assert august["expenses"] == 400.0, "August total missed the expense"
    assert september["expenses"] == 0, "September total wrongly included it"


# ── Why an offset would not have been enough ──────────────────────────────────

def test_boundaries_respect_dst_at_the_date_in_question():
    """
    New York is UTC-5 in winter and UTC-4 in summer. A stored offset could not
    express both, so November and July boundaries would be wrong half the year.
    """
    ny = resolve_timezone("America/New_York")

    nov_start, _ = month_range_utc(2026, 11, ny)
    jul_start, _ = month_range_utc(2026, 7, ny)

    # 1 Nov 00:00 EST (-5) is 05:00 UTC; 1 Jul 00:00 EDT (-4) is 04:00 UTC.
    assert nov_start == datetime(2026, 11, 1, 4, 0), nov_start   # DST still on 1 Nov
    assert jul_start == datetime(2026, 7, 1, 4, 0), jul_start

    dec_start, _ = month_range_utc(2026, 12, ny)
    assert dec_start == datetime(2026, 12, 1, 5, 0), dec_start   # EST by December


def test_nairobi_has_a_constant_offset():
    """Kenya has never used DST, which is why a fixed offset was survivable there."""
    nbo = resolve_timezone("Africa/Nairobi")
    offsets = {nbo.utcoffset(datetime(2026, m, 15)) for m in range(1, 13)}
    assert len(offsets) == 1, offsets


# ── Defaults and validation ───────────────────────────────────────────────────

def test_registering_without_a_zone_defaults_to_nairobi():
    _, user = _user()
    assert user["timezone"] == DEFAULT_TIMEZONE_NAME


def test_registering_with_a_bogus_zone_falls_back_rather_than_failing():
    _, user = _user("Mars/Olympus_Mons")
    assert user["timezone"] == DEFAULT_TIMEZONE_NAME


def test_resolve_timezone_never_raises():
    for bad in [None, "", "   ", "Not/AZone", "UTC+3", "../../etc/passwd"]:
        assert resolve_timezone(bad).key == DEFAULT_TIMEZONE_NAME, bad


def test_is_valid_timezone():
    assert is_valid_timezone("America/Toronto")
    assert is_valid_timezone("Africa/Nairobi")
    assert not is_valid_timezone("Mars/Olympus_Mons")
    assert not is_valid_timezone("")
    assert not is_valid_timezone(None)


# ── Changing it ───────────────────────────────────────────────────────────────

def test_profile_update_changes_the_zone():
    headers, user = _user()
    assert user["timezone"] == "Africa/Nairobi"

    r = CLIENT.put("/api/auth/profile", json={"timezone": "America/Toronto"},
                   headers=headers)
    assert r.status_code == 200, r.get_data(as_text=True)
    assert r.get_json()["user"]["timezone"] == "America/Toronto"


def test_profile_update_rejects_a_bogus_zone():
    headers, _ = _user()
    r = CLIENT.put("/api/auth/profile", json={"timezone": "Mars/Olympus_Mons"},
                   headers=headers)
    assert r.status_code == 400, r.get_data(as_text=True)
    assert "not a recognised time zone" in r.get_json()["message"].lower()


def test_changing_the_zone_re_buckets_future_queries():
    """Moving home zone changes which month a borderline expense reports in."""
    headers, _ = _user("Africa/Nairobi")
    expense = _expense_at("2026-09-01T01:00:00", headers)

    assert expense["id"] in _ids_for(9, 2026, headers)      # 04:00 1 Sep in Nairobi

    r = CLIENT.put("/api/auth/profile", json={"timezone": "America/Toronto"},
                   headers=headers)
    assert r.status_code == 200, r.get_data(as_text=True)

    assert expense["id"] in _ids_for(8, 2026, headers), \
        "after moving to Toronto the expense should report in August"


# ── The picker's source list ──────────────────────────────────────────────────

def test_timezone_list_endpoint():
    headers, _ = _user()
    r = CLIENT.get("/api/timezones", headers=headers)
    assert r.status_code == 200, r.get_data(as_text=True)
    body = r.get_json()

    zones = body["timezones"]
    assert len(zones) > 100, len(zones)
    assert "Africa/Nairobi" in zones
    assert "America/Toronto" in zones
    assert body["default"] == DEFAULT_TIMEZONE_NAME
    assert zones == sorted(zones), "list should be sorted for the picker"


def test_every_offered_zone_is_actually_accepted():
    """The picker must never offer a name PUT /auth/profile would reject."""
    headers, _ = _user()
    zones = CLIENT.get("/api/timezones", headers=headers).get_json()["timezones"]
    for name in zones[::40]:          # sample across the list, not all 598
        assert is_valid_timezone(name), name


def test_timezone_list_requires_authentication():
    r = CLIENT.get("/api/timezones")
    assert r.status_code == 401, r.status_code


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
