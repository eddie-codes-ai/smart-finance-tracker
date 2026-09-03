"""
Regression tests for the API error contract.

The Flutter client decodes every response body as JSON and reads `message`
from it. Before these checks existed, bad input produced a Werkzeug HTML 500,
which the client reported to the user as "Check your connection" — hiding the
real cause and making genuine validation errors indistinguishable from
network failures.

Run it directly, no pytest needed:

    cd backend
    venv/Scripts/python tests/test_error_contract.py     # Windows
    venv/bin/python tests/test_error_contract.py         # Linux/macOS

Exits non-zero if anything regresses. Also collectable by pytest if you add it
later — each check is a plain assert inside a test_* function.
"""
import os
import sys
import tempfile

# Import the app package regardless of where this is run from.
BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, BACKEND_DIR)

_DB_PATH = os.path.join(tempfile.mkdtemp(prefix="sft-tests-"), "test.db")
os.environ["DATABASE_URL"] = "sqlite:///" + _DB_PATH.replace(os.sep, "/")
os.environ.setdefault("JWT_SECRET_KEY", "test-secret-not-used-in-production")

from flask_migrate import upgrade  # noqa: E402

from app import create_app  # noqa: E402


def _client():
    app = create_app()
    # Exercise the error handlers rather than letting Flask re-raise.
    app.config["PROPAGATE_EXCEPTIONS"] = False
    app.config["TESTING"] = True
    # The schema comes from the migrations now, not db.create_all().
    with app.app_context():
        upgrade()
    return app.test_client()


CLIENT = _client()


def _auth_header():
    """Register a throwaway user and return its Authorization header."""
    import uuid
    username = "user-" + uuid.uuid4().hex[:8]
    r = CLIENT.post("/api/auth/register",
                    json={"username": username, "password": "correct-horse"})
    assert r.status_code == 201, r.get_data(as_text=True)
    return {"Authorization": "Bearer " + r.get_json()["token"]}


HEADERS = _auth_header()


def _assert_json_error(response, status, contains=None):
    """Every failure must be JSON carrying status/message — never HTML."""
    content_type = response.headers.get("Content-Type", "")
    assert "application/json" in content_type, (
        "expected JSON, got %s:\n%s" % (content_type, response.get_data(as_text=True)[:200])
    )
    assert response.status_code == status, (
        "expected %s, got %s" % (status, response.status_code)
    )
    payload = response.get_json()
    assert payload.get("status") == "error", payload
    message = payload.get("message") or ""
    assert message, "error response carried no message: %s" % payload
    if contains:
        assert contains.lower() in message.lower(), (
            "expected %r in %r" % (contains, message)
        )


# ── Password rules ────────────────────────────────────────────────────────────

def test_register_rejects_short_password():
    _assert_json_error(
        CLIENT.post("/api/auth/register", json={"username": "shorty", "password": "x"}),
        400, "at least 6")


def test_register_rejects_missing_password():
    _assert_json_error(
        CLIENT.post("/api/auth/register", json={"username": "nopass"}),
        400, "password is required")


def test_register_accepts_a_valid_password():
    import uuid
    r = CLIENT.post("/api/auth/register",
                    json={"username": "ok-" + uuid.uuid4().hex[:8], "password": "correct-horse"})
    assert r.status_code == 201, r.get_data(as_text=True)
    assert r.get_json()["status"] == "success"


# ── Amount validation ─────────────────────────────────────────────────────────

BAD_AMOUNTS = ["abc", "", None, -5, 0, "NaN", "Infinity", "-Infinity", True, [], {}]


def test_expense_rejects_every_bad_amount():
    for bad in BAD_AMOUNTS:
        _assert_json_error(
            CLIENT.post("/api/expenses", json={"amount": bad, "category": "Food"},
                        headers=HEADERS),
            400, "valid amount")


def test_income_rejects_every_bad_amount():
    for bad in BAD_AMOUNTS:
        _assert_json_error(
            CLIENT.post("/api/income", json={"amount": bad}, headers=HEADERS),
            400, "valid amount")


def test_budget_rejects_bad_limit():
    _assert_json_error(
        CLIENT.post("/api/budgets", json={"category": "Food", "limit": "abc"},
                    headers=HEADERS),
        400, "valid limit")


def test_goal_rejects_bad_amount():
    _assert_json_error(
        CLIENT.post("/api/goals", json={"goal_amount": "abc", "due_date": "2026-12-01"},
                    headers=HEADERS),
        400, "valid goal amount")


def test_helb_rejects_bad_amount():
    _assert_json_error(
        CLIENT.post("/api/helb/plan",
                    json={"semester_name": "Sem 1", "helb_amount": "abc",
                          "start_date": "2026-01-01", "end_date": "2026-06-01"},
                    headers=HEADERS),
        400, "valid helb amount")


def test_valid_amounts_are_accepted():
    for good in [250.5, "250.50", 1, "0.01"]:
        r = CLIENT.post("/api/expenses", json={"amount": good, "category": "Food"},
                        headers=HEADERS)
        assert r.status_code == 201, "%r rejected: %s" % (good, r.get_data(as_text=True))


# ── Malformed requests ────────────────────────────────────────────────────────

def test_missing_body_is_a_json_400():
    _assert_json_error(CLIENT.post("/api/expenses", headers=HEADERS), 400)


def test_malformed_json_body_is_a_json_400():
    _assert_json_error(
        CLIENT.post("/api/expenses", data="{not json",
                    headers=dict(HEADERS, **{"Content-Type": "application/json"})),
        400)


# ── Framework errors use the same envelope ────────────────────────────────────

def test_unknown_route_is_json():
    _assert_json_error(CLIENT.get("/api/does-not-exist", headers=HEADERS), 404)


def test_wrong_method_is_json():
    _assert_json_error(CLIENT.put("/api/expenses", json={}, headers=HEADERS), 405)


def test_missing_token_is_json():
    _assert_json_error(CLIENT.get("/api/expenses"), 401, "signed in")


def test_garbage_token_is_json():
    _assert_json_error(
        CLIENT.get("/api/expenses", headers={"Authorization": "Bearer not.a.token"}),
        401, "no longer valid")


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
            failures.append((name, e))
            print("FAIL  %s\n      %s" % (name, e))
    print("\n%d/%d passed" % (len(tests) - len(failures), len(tests)))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
