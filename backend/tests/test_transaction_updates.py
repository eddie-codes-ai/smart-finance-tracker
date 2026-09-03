"""
Regression tests for PUT /api/expenses/<id> and PUT /api/income/<id>.

These endpoints exist because editing a transaction used to be implemented in
the app as delete-then-recreate. That was not atomic (a failed recreate lost
the record outright) and it reset date_added to now, silently moving an edited
transaction to today and possibly into a different month.

The most important assertion in this file is that an update which does not
mention date_added leaves it exactly as it was.

Run it directly, no pytest needed:

    cd backend
    venv/Scripts/python tests/test_transaction_updates.py     # Windows
    venv/bin/python tests/test_transaction_updates.py         # Linux/macOS
"""
import os
import sys
import tempfile
import uuid
from datetime import datetime, timedelta

BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, BACKEND_DIR)

_DB_PATH = os.path.join(tempfile.mkdtemp(prefix="sft-tests-"), "test.db")
os.environ["DATABASE_URL"] = "sqlite:///" + _DB_PATH.replace(os.sep, "/")
os.environ.setdefault("JWT_SECRET_KEY", "test-secret-not-used-in-production")

from flask_migrate import upgrade  # noqa: E402

from app import create_app  # noqa: E402

_app = create_app()
_app.config["PROPAGATE_EXCEPTIONS"] = False
_app.config["TESTING"] = True
# The schema comes from the migrations now, not db.create_all().
with _app.app_context():
    upgrade()
CLIENT = _app.test_client()


def _new_user():
    """Register a throwaway user and return its Authorization header."""
    username = "user-" + uuid.uuid4().hex[:8]
    r = CLIENT.post("/api/auth/register",
                    json={"username": username, "password": "correct-horse"})
    assert r.status_code == 201, r.get_data(as_text=True)
    return {"Authorization": "Bearer " + r.get_json()["token"]}


HEADERS = _new_user()
OTHER_USER = _new_user()

OLD_DATE = "2026-03-14T09:30:00"


def _make_expense(headers=None, **overrides):
    payload = {"amount": 500.0, "category": "Food", "description": "Lunch",
               "expense_type": "daily"}
    payload.update(overrides)
    r = CLIENT.post("/api/expenses", json=payload, headers=headers or HEADERS)
    assert r.status_code == 201, r.get_data(as_text=True)
    record = r.get_json()["expense"]
    # Back-date it so "did the update preserve the date?" is a meaningful
    # question — a record created just now would pass by coincidence.
    r = CLIENT.put("/api/expenses/%s" % record["id"],
                   json={"date_added": OLD_DATE}, headers=headers or HEADERS)
    assert r.status_code == 200, r.get_data(as_text=True)
    return r.get_json()["expense"]


def _make_income(headers=None, **overrides):
    payload = {"amount": 8000.0, "income_type": "helb", "description": "Disbursement"}
    payload.update(overrides)
    r = CLIENT.post("/api/income", json=payload, headers=headers or HEADERS)
    assert r.status_code == 201, r.get_data(as_text=True)
    record = r.get_json()["income"]
    r = CLIENT.put("/api/income/%s" % record["id"],
                   json={"date_added": OLD_DATE}, headers=headers or HEADERS)
    assert r.status_code == 200, r.get_data(as_text=True)
    return r.get_json()["income"]


def _put_expense(expense_id, payload, headers=None):
    return CLIENT.put("/api/expenses/%s" % expense_id, json=payload,
                      headers=headers or HEADERS)


def _assert_json_error(response, status, contains=None):
    assert "application/json" in response.headers.get("Content-Type", ""), \
        response.get_data(as_text=True)[:200]
    assert response.status_code == status, \
        "expected %s, got %s: %s" % (status, response.status_code,
                                     response.get_data(as_text=True)[:200])
    payload = response.get_json()
    assert payload.get("status") == "error", payload
    if contains:
        assert contains.lower() in (payload.get("message") or "").lower(), payload


# ── The core C-1 regression ───────────────────────────────────────────────────

def test_update_preserves_date_added():
    """An edit that doesn't mention the date must not move the transaction."""
    expense = _make_expense()
    assert expense["date_added"].startswith("2026-03-14")

    r = _put_expense(expense["id"], {"amount": 750.0})
    assert r.status_code == 200, r.get_data(as_text=True)
    updated = r.get_json()["expense"]

    assert updated["amount"] == 750.0
    assert updated["date_added"] == expense["date_added"], (
        "date_added changed on update: %s -> %s"
        % (expense["date_added"], updated["date_added"]))


def test_update_income_preserves_date_added():
    income = _make_income()
    r = CLIENT.put("/api/income/%s" % income["id"], json={"amount": 9000.0},
                   headers=HEADERS)
    assert r.status_code == 200, r.get_data(as_text=True)
    updated = r.get_json()["income"]
    assert updated["amount"] == 9000.0
    assert updated["date_added"] == income["date_added"]


def test_update_keeps_the_same_record_id():
    """Delete-then-recreate produced a new id; a real update must not."""
    expense = _make_expense()
    r = _put_expense(expense["id"], {"amount": 123.0})
    assert r.get_json()["expense"]["id"] == expense["id"]


# ── Partial update semantics ──────────────────────────────────────────────────

def test_partial_update_leaves_other_fields_alone():
    expense = _make_expense(category="Transport", description="Matatu",
                            expense_type="daily")
    r = _put_expense(expense["id"], {"amount": 60.0})
    updated = r.get_json()["expense"]
    assert updated["category"] == "Transport"
    assert updated["description"] == "Matatu"
    assert updated["expense_type"] == "daily"


def test_each_field_updates():
    expense = _make_expense()
    r = _put_expense(expense["id"], {
        "amount": 99.5,
        "category": "Health",
        "description": "Pharmacy",
        "expense_type": "one-time",
    })
    assert r.status_code == 200, r.get_data(as_text=True)
    updated = r.get_json()["expense"]
    assert updated["amount"] == 99.5
    assert updated["category"] == "Health"
    assert updated["description"] == "Pharmacy"
    assert updated["expense_type"] == "one-time"


def test_income_type_and_description_update():
    income = _make_income()
    r = CLIENT.put("/api/income/%s" % income["id"],
                   json={"income_type": "gig", "description": "Freelance"},
                   headers=HEADERS)
    updated = r.get_json()["income"]
    assert updated["income_type"] == "gig"
    assert updated["description"] == "Freelance"


def test_empty_body_is_a_no_op_not_an_error():
    expense = _make_expense()
    r = _put_expense(expense["id"], {})
    assert r.status_code == 200, r.get_data(as_text=True)
    assert r.get_json()["expense"]["amount"] == expense["amount"]


# ── Explicit date changes ─────────────────────────────────────────────────────

def test_explicit_date_added_is_accepted():
    expense = _make_expense()
    r = _put_expense(expense["id"], {"date_added": "2026-01-05T18:45:00"})
    assert r.status_code == 200, r.get_data(as_text=True)
    assert r.get_json()["expense"]["date_added"].startswith("2026-01-05T18:45:00")


def test_date_added_accepts_a_trailing_z():
    """fromisoformat() can't read a Z before Python 3.11; the helper strips it."""
    expense = _make_expense()
    r = _put_expense(expense["id"], {"date_added": "2026-01-05T18:45:00Z"})
    assert r.status_code == 200, r.get_data(as_text=True)


def test_future_date_added_is_rejected():
    expense = _make_expense()
    future = (datetime.utcnow() + timedelta(days=30)).isoformat()
    _assert_json_error(_put_expense(expense["id"], {"date_added": future}),
                       400, "future")


def test_unparseable_date_added_is_rejected():
    expense = _make_expense()
    for bad in ["not-a-date", "14/03/2026", "", 12345, None]:
        _assert_json_error(_put_expense(expense["id"], {"date_added": bad}),
                           400, "iso 8601")


# ── Field validation ──────────────────────────────────────────────────────────

def test_bad_amount_is_rejected():
    expense = _make_expense()
    for bad in ["abc", -5, 0, "NaN", "Infinity", True, None]:
        _assert_json_error(_put_expense(expense["id"], {"amount": bad}),
                           400, "valid amount")


def test_bad_expense_type_is_rejected():
    expense = _make_expense()
    _assert_json_error(_put_expense(expense["id"], {"expense_type": "weekly"}),
                       400, "expense_type must be one of")


def test_bad_recurrence_interval_is_rejected():
    expense = _make_expense()
    _assert_json_error(
        _put_expense(expense["id"], {"recurrence_interval": "fortnightly"}),
        400, "recurrence_interval must be one of")


def test_recurrence_interval_can_be_cleared():
    expense = _make_expense(expense_type="recurring", recurrence_interval="weekly")
    r = _put_expense(expense["id"], {"recurrence_interval": None})
    assert r.status_code == 200, r.get_data(as_text=True)
    assert r.get_json()["expense"]["recurrence_interval"] is None


def test_changing_type_away_from_recurring_clears_the_interval():
    expense = _make_expense(expense_type="recurring", recurrence_interval="weekly")
    assert expense["recurrence_interval"] == "weekly"
    r = _put_expense(expense["id"], {"expense_type": "daily"})
    assert r.status_code == 200, r.get_data(as_text=True)
    assert r.get_json()["expense"]["recurrence_interval"] is None


def test_recurring_expense_keeps_its_interval_on_an_unrelated_edit():
    expense = _make_expense(expense_type="recurring", recurrence_interval="weekly")
    r = _put_expense(expense["id"], {"amount": 42.0})
    assert r.get_json()["expense"]["recurrence_interval"] == "weekly"


def test_empty_category_is_rejected():
    expense = _make_expense()
    _assert_json_error(_put_expense(expense["id"], {"category": "   "}),
                       400, "category cannot be empty")


def test_custom_category_is_accepted():
    """A category outside the defaults must still be editable (see the comment
    in update_expense: deleted custom categories leave records behind)."""
    expense = _make_expense()
    r = _put_expense(expense["id"], {"category": "Chama contribution"})
    assert r.status_code == 200, r.get_data(as_text=True)
    assert r.get_json()["expense"]["category"] == "Chama contribution"


# ── The POST side now agrees with PUT ─────────────────────────────────────────

def test_post_expense_rejects_bad_expense_type():
    _assert_json_error(
        CLIENT.post("/api/expenses",
                    json={"amount": 10, "category": "Food", "expense_type": "weekly"},
                    headers=HEADERS),
        400, "expense_type must be one of")


# ── Ownership and existence ───────────────────────────────────────────────────

def test_cannot_update_another_users_expense():
    """IDOR guard — must be indistinguishable from a missing record."""
    victim = _make_expense()
    _assert_json_error(
        _put_expense(victim["id"], {"amount": 1.0}, headers=OTHER_USER),
        404, "not found")
    # And the record is genuinely untouched.
    r = _put_expense(victim["id"], {})
    assert r.get_json()["expense"]["amount"] == victim["amount"]


def test_cannot_update_another_users_income():
    victim = _make_income()
    _assert_json_error(
        CLIENT.put("/api/income/%s" % victim["id"], json={"amount": 1.0},
                   headers=OTHER_USER),
        404, "not found")


def test_unknown_expense_id_is_404():
    _assert_json_error(_put_expense(999999, {"amount": 1.0}), 404, "not found")


def test_unknown_income_id_is_404():
    _assert_json_error(
        CLIENT.put("/api/income/999999", json={"amount": 1.0}, headers=HEADERS),
        404, "not found")


def test_update_requires_authentication():
    expense = _make_expense()
    _assert_json_error(
        CLIENT.put("/api/expenses/%s" % expense["id"], json={"amount": 1.0}),
        401)


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
