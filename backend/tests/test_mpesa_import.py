"""
Tests for M-Pesa import: no duplicates, and the SMS keeps its own date.

The import screen lists the last 60 M-Pesa messages every time it opens and used
to send neither the transaction code nor the message date. Tapping the same
message twice produced two identical expenses, and every imported message was
stamped with the moment of import - so importing a month of history piled it all
onto one day, distorting the daily-budget and overspending figures.

Silent double-counting is the nastier of the two: the totals stay plausible.

Run it directly, no pytest needed:

    cd backend
    venv/Scripts/python tests/test_mpesa_import.py     # Windows
    venv/bin/python tests/test_mpesa_import.py         # Linux/macOS
"""
import os
import sys
import tempfile
import uuid
from datetime import timedelta

BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, BACKEND_DIR)

_DB_PATH = os.path.join(tempfile.mkdtemp(prefix="sft-mpesa-"), "test.db")
os.environ["DATABASE_URL"] = "sqlite:///" + _DB_PATH.replace(os.sep, "/")
os.environ.setdefault("JWT_SECRET_KEY", "test-secret-not-used-in-production")

from flask_migrate import upgrade                                     # noqa: E402

from app import create_app                                            # noqa: E402
from app_time import utc_now                                          # noqa: E402

_app = create_app()
_app.config["PROPAGATE_EXCEPTIONS"] = False
_app.config["TESTING"] = True
with _app.app_context():
    upgrade()
CLIENT = _app.test_client()


def _user():
    username = "m-" + uuid.uuid4().hex[:8]
    r = CLIENT.post("/api/auth/register",
                    json={"username": username, "password": "correct-horse"})
    assert r.status_code == 201, r.get_data(as_text=True)
    return {"Authorization": "Bearer " + r.get_json()["token"]}


HEADERS = _user()


def _import_expense(headers=None, code=None, amount=250.0, date_added=None,
                    category="Food"):
    payload = {"amount": amount, "category": category, "description": "M-Pesa"}
    if code is not None:
        payload["mpesa_code"] = code
    if date_added is not None:
        payload["date_added"] = date_added
    return CLIENT.post("/api/expenses", json=payload, headers=headers or HEADERS)


def _import_income(headers=None, code=None, amount=8000.0):
    payload = {"amount": amount, "income_type": "helb", "description": "M-Pesa"}
    if code is not None:
        payload["mpesa_code"] = code
    return CLIENT.post("/api/income", json=payload, headers=headers or HEADERS)


def _expenses_for(month, year, headers=None):
    r = CLIENT.get("/api/expenses?month=%d&year=%d" % (month, year),
                   headers=headers or HEADERS)
    assert r.status_code == 200, r.get_data(as_text=True)
    return r.get_json()["expenses"]


def _code():
    return "SB" + uuid.uuid4().hex[:8].upper()


# ── No duplicates ─────────────────────────────────────────────────────────────

def test_the_same_message_cannot_be_imported_twice():
    user = _user()
    code = _code()

    first = _import_expense(user, code=code)
    assert first.status_code == 201, first.get_data(as_text=True)

    second = _import_expense(user, code=code)
    assert second.status_code == 409, second.get_data(as_text=True)
    assert "already been imported" in second.get_json()["message"].lower()

    # And exactly one row exists, not two.
    matching = [e for e in _expenses_for(utc_now().month, utc_now().year, user)
                if e.get("mpesa_code") == code]
    assert len(matching) == 1, "duplicate rows: %d" % len(matching)


def test_the_conflict_names_the_transaction_it_matched():
    """So the app can say which expense this already is."""
    user = _user()
    code = _code()
    original = _import_expense(user, code=code, amount=777.0).get_json()["expense"]

    clash = _import_expense(user, code=code, amount=777.0)
    returned = clash.get_json()["expense"]
    assert returned["id"] == original["id"]
    assert returned["amount"] == 777.0


def test_income_imports_are_deduplicated_too():
    user = _user()
    code = _code()
    assert _import_income(user, code=code).status_code == 201
    assert _import_income(user, code=code).status_code == 409


def test_an_expense_and_an_income_do_not_block_each_other():
    """The two tables are constrained separately, as they should be."""
    user = _user()
    code = _code()
    assert _import_expense(user, code=code).status_code == 201
    assert _import_income(user, code=code).status_code == 201


def test_the_constraint_is_per_user():
    """Two people can receive genuinely different messages; codes are only
    unique within one account."""
    a, b = _user(), _user()
    code = _code()
    assert _import_expense(a, code=code).status_code == 201
    assert _import_expense(b, code=code).status_code == 201, \
        "one user's import blocked another user's"


def test_manual_entries_without_a_code_never_collide():
    """NULL does not conflict with NULL - hand-entered rows stay unconstrained."""
    user = _user()
    for _ in range(4):
        assert _import_expense(user, code=None).status_code == 201


def test_an_unparseable_code_is_stored_as_null():
    """
    The parser emits "N/A" when it finds no code. Stored literally, the second
    such import would collide with the first.
    """
    user = _user()
    first = _import_expense(user, code="N/A")
    assert first.status_code == 201, first.get_data(as_text=True)
    assert first.get_json()["expense"]["mpesa_code"] is None

    second = _import_expense(user, code="N/A")
    assert second.status_code == 201, "a second unparseable import was refused"

    assert _import_expense(user, code="   ").status_code == 201


def test_codes_are_normalised_to_uppercase():
    user = _user()
    code = _code()
    assert _import_expense(user, code=code.lower()).status_code == 201
    assert _import_expense(user, code=code).status_code == 409, \
        "case difference let the same message in twice"


# ── The date survives ─────────────────────────────────────────────────────────

def test_an_imported_message_keeps_its_own_date():
    user = _user()
    r = _import_expense(user, code=_code(), date_added="2026-01-20T14:30:00")
    assert r.status_code == 201, r.get_data(as_text=True)
    assert r.get_json()["expense"]["date_added"].startswith("2026-01-20T14:30:00")


def test_an_imported_message_lands_in_its_own_month():
    """The point of keeping the date: it must not pile onto the import day."""
    user = _user()
    created = _import_expense(user, code=_code(),
                              date_added="2026-01-20T14:30:00").get_json()["expense"]
    january = [e["id"] for e in _expenses_for(1, 2026, user)]
    assert created["id"] in january, "imported transaction missing from its own month"


def test_no_date_still_defaults_to_now():
    user = _user()
    r = _import_expense(user, code=_code())
    assert r.status_code == 201
    assert r.get_json()["expense"]["date_added"] is not None


def test_a_future_date_is_rejected():
    user = _user()
    future = (utc_now() + timedelta(days=30)).isoformat()
    r = _import_expense(user, code=_code(), date_added=future)
    assert r.status_code == 400, r.get_data(as_text=True)
    assert "future" in r.get_json()["message"].lower()


def test_a_malformed_date_is_rejected():
    user = _user()
    r = _import_expense(user, code=_code(), date_added="20th January")
    assert r.status_code == 400
    assert "iso 8601" in r.get_json()["message"].lower()


# ── Telling the app what is already there ─────────────────────────────────────

def test_imported_endpoint_returns_only_what_exists():
    user = _user()
    present, absent = _code(), _code()
    _import_expense(user, code=present)

    r = CLIENT.post("/api/mpesa/imported",
                    json={"codes": [present, absent]}, headers=user)
    assert r.status_code == 200, r.get_data(as_text=True)
    assert r.get_json()["imported"] == [present]


def test_imported_endpoint_covers_income_as_well():
    user = _user()
    code = _code()
    _import_income(user, code=code)
    r = CLIENT.post("/api/mpesa/imported", json={"codes": [code]}, headers=user)
    assert r.get_json()["imported"] == [code]


def test_imported_endpoint_does_not_leak_across_users():
    a, b = _user(), _user()
    code = _code()
    _import_expense(a, code=code)

    r = CLIENT.post("/api/mpesa/imported", json={"codes": [code]}, headers=b)
    assert r.get_json()["imported"] == [], "one user was told about another's imports"


def test_imported_endpoint_handles_junk_input():
    user = _user()
    r = CLIENT.post("/api/mpesa/imported",
                    json={"codes": ["N/A", "", "   ", None, 42]}, headers=user)
    assert r.status_code == 200, r.get_data(as_text=True)
    assert r.get_json()["imported"] == []

    r = CLIENT.post("/api/mpesa/imported", json={"codes": "not-a-list"}, headers=user)
    assert r.status_code == 400

    r = CLIENT.post("/api/mpesa/imported", json={}, headers=user)
    assert r.status_code == 400


def test_imported_endpoint_requires_authentication():
    assert CLIENT.post("/api/mpesa/imported", json={"codes": []}).status_code == 401


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
