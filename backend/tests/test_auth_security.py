"""
Tests for the brute-force controls on the authentication endpoints.

The password reset code is six digits - a million possibilities. It used to be
minted with random.randint (a Mersenne Twister, whose output is derivable from
enough prior output), stored in the database in plaintext, given an hour to
live, and compared with no limit on attempts. Any one of those alone would be
bad; together they were a straightforward account takeover, on accounts that may
carry a guardian's phone number.

Login had no throttling at all.

Run it directly, no pytest needed:

    cd backend
    venv/Scripts/python tests/test_auth_security.py     # Windows
    venv/bin/python tests/test_auth_security.py         # Linux/macOS
"""
import os
import sys
import tempfile
import uuid
from datetime import timedelta

BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, BACKEND_DIR)

_DB_PATH = os.path.join(tempfile.mkdtemp(prefix="sft-authsec-"), "test.db")
os.environ["DATABASE_URL"] = "sqlite:///" + _DB_PATH.replace(os.sep, "/")
os.environ.setdefault("JWT_SECRET_KEY", "test-secret-not-used-in-production")

from flask_migrate import upgrade                                     # noqa: E402

from app import create_app                                            # noqa: E402
from app_time import utc_now                                          # noqa: E402
from api.routes import (LOGIN_LOCKOUT_MINUTES, MAX_LOGIN_ATTEMPTS,    # noqa: E402
                        MAX_RESET_ATTEMPTS, RESET_CODE_TTL_MINUTES)
from models import User, db                                           # noqa: E402

_app = create_app()
_app.config["PROPAGATE_EXCEPTIONS"] = False
_app.config["TESTING"] = True
with _app.app_context():
    upgrade()
CLIENT = _app.test_client()

PASSWORD = "correct-horse"


def _register(email=None):
    """Create a user and return (username, email)."""
    username = "u-" + uuid.uuid4().hex[:8]
    email = email or (username + "@example.com")
    r = CLIENT.post("/api/auth/register",
                    json={"username": username, "password": PASSWORD, "email": email})
    assert r.status_code == 201, r.get_data(as_text=True)
    return username, email


def _issue_code(email):
    """
    Trigger a reset and read the real code out of the database.

    The email send fails in tests (no SMTP configured), which is itself part of
    what is being checked: the endpoint must still behave normally.
    """
    r = CLIENT.post("/api/auth/forgot-password", json={"email": email})
    assert r.status_code == 200, r.get_data(as_text=True)
    with _app.app_context():
        user = User.query.filter_by(email=email).first()
        # The stored value is a hash, so the plaintext is not recoverable -
        # which is the point. Re-issue one we know instead.
        code = user.issue_reset_code(RESET_CODE_TTL_MINUTES)
        db.session.commit()
    return code


def _reset(email, code, new_password="brand-new-password"):
    return CLIENT.post("/api/auth/reset-password",
                       json={"email": email, "code": code, "new_password": new_password})


def _login(username, password):
    return CLIENT.post("/api/auth/login", json={"username": username, "password": password})


# ── The reset code is no longer guessable ─────────────────────────────────────

def test_reset_code_is_not_stored_in_plaintext():
    _, email = _register()
    code = _issue_code(email)
    with _app.app_context():
        stored = User.query.filter_by(email=email).first().reset_token
    assert stored != code, "the code is still stored in plaintext"
    assert code not in stored, "the plaintext code appears inside the stored value"
    assert len(stored) > 20, "stored value is too short to be a hash: %r" % stored


def test_five_wrong_attempts_destroy_the_code():
    _, email = _register()
    code = _issue_code(email)
    wrong = "000000" if code != "000000" else "111111"

    for i in range(MAX_RESET_ATTEMPTS - 1):
        r = _reset(email, wrong)
        assert r.status_code == 400, r.get_data(as_text=True)
        assert "remaining" in r.get_json()["message"].lower(), r.get_json()

    # The last one burns it.
    r = _reset(email, wrong)
    assert "request a new" in r.get_json()["message"].lower(), r.get_json()

    # And now even the CORRECT code is refused.
    r = _reset(email, code)
    assert r.status_code == 400, r.get_data(as_text=True)
    with _app.app_context():
        assert User.query.filter_by(email=email).first().reset_token is None


def test_attempts_are_counted_down_visibly():
    _, email = _register()
    code = _issue_code(email)
    wrong = "000000" if code != "000000" else "111111"
    message = _reset(email, wrong).get_json()["message"]
    assert str(MAX_RESET_ATTEMPTS - 1) in message, message


def test_the_correct_code_still_works():
    username, email = _register()
    code = _issue_code(email)
    r = _reset(email, code, new_password="a-fresh-password")
    assert r.status_code == 200, r.get_data(as_text=True)

    assert _login(username, "a-fresh-password").status_code == 200
    assert _login(username, PASSWORD).status_code == 401, "old password still works"


def test_using_the_code_clears_it():
    _, email = _register()
    code = _issue_code(email)
    assert _reset(email, code).status_code == 200
    # A replay must fail.
    assert _reset(email, code).status_code == 400
    with _app.app_context():
        user = User.query.filter_by(email=email).first()
        assert user.reset_token is None
        assert user.reset_attempts == 0


def test_expired_code_is_refused_and_cleared():
    _, email = _register()
    code = _issue_code(email)
    with _app.app_context():
        user = User.query.filter_by(email=email).first()
        user.reset_token_expiry = utc_now() - timedelta(minutes=1)
        db.session.commit()

    r = _reset(email, code)
    assert r.status_code == 400
    assert "expired" in r.get_json()["message"].lower(), r.get_json()


def test_code_lifetime_matches_what_the_email_promises():
    """The email said 15 minutes while the code lived for 60."""
    assert RESET_CODE_TTL_MINUTES == 15
    _, email = _register()
    _issue_code(email)
    with _app.app_context():
        user = User.query.filter_by(email=email).first()
        remaining = user.reset_token_expiry - utc_now()
    assert timedelta(minutes=14) < remaining <= timedelta(minutes=15), remaining


def test_reset_codes_differ_between_issues():
    _, email = _register()
    codes = {_issue_code(email) for _ in range(8)}
    assert len(codes) > 1, "reset codes are not varying"


# ── No account enumeration ────────────────────────────────────────────────────

def test_forgot_password_answers_the_same_for_unknown_addresses():
    _, known = _register()
    a = CLIENT.post("/api/auth/forgot-password", json={"email": known})
    b = CLIENT.post("/api/auth/forgot-password",
                    json={"email": "definitely-not-registered@example.com"})
    assert a.status_code == b.status_code == 200
    assert a.get_json()["message"] == b.get_json()["message"], \
        "the reply differs, which reveals whether an address is registered"


def test_a_failed_email_send_does_not_change_the_reply():
    """SMTP is unconfigured in tests, so the send genuinely fails here."""
    _, email = _register()
    r = CLIENT.post("/api/auth/forgot-password", json={"email": email})
    assert r.status_code == 200
    assert "if that email is registered" in r.get_json()["message"].lower()


# ── Login throttling ──────────────────────────────────────────────────────────

def test_repeated_failures_lock_the_account():
    username, _ = _register()
    for _ in range(MAX_LOGIN_ATTEMPTS):
        assert _login(username, "wrong-password").status_code == 401

    r = _login(username, "wrong-password")
    assert r.status_code == 429, r.get_data(as_text=True)
    assert "too many failed attempts" in r.get_json()["message"].lower()


def test_the_right_password_is_refused_while_locked():
    username, _ = _register()
    for _ in range(MAX_LOGIN_ATTEMPTS):
        _login(username, "wrong-password")

    r = _login(username, PASSWORD)
    assert r.status_code == 429, "a locked account accepted the correct password"


def test_login_works_again_once_the_lock_expires():
    username, _ = _register()
    for _ in range(MAX_LOGIN_ATTEMPTS):
        _login(username, "wrong-password")
    assert _login(username, PASSWORD).status_code == 429

    with _app.app_context():
        user = User.query.filter_by(username=username).first()
        user.locked_until = utc_now() - timedelta(seconds=1)
        db.session.commit()

    assert _login(username, PASSWORD).status_code == 200


def test_a_success_resets_the_failure_count():
    username, _ = _register()
    for _ in range(MAX_LOGIN_ATTEMPTS - 1):
        _login(username, "wrong-password")

    assert _login(username, PASSWORD).status_code == 200
    with _app.app_context():
        user = User.query.filter_by(username=username).first()
        assert user.failed_login_attempts == 0
        assert user.locked_until is None

    # The budget is full again rather than one away from a lockout.
    for _ in range(MAX_LOGIN_ATTEMPTS - 1):
        assert _login(username, "wrong-password").status_code == 401


def test_lockout_does_not_leak_whether_a_username_exists():
    r = _login("no-such-user-" + uuid.uuid4().hex[:6], "whatever")
    assert r.status_code == 401
    assert "invalid username or password" in r.get_json()["message"].lower()


def test_a_successful_reset_unlocks_the_account():
    username, email = _register()
    for _ in range(MAX_LOGIN_ATTEMPTS):
        _login(username, "wrong-password")
    assert _login(username, PASSWORD).status_code == 429

    code = _issue_code(email)
    assert _reset(email, code, new_password="another-password").status_code == 200
    assert _login(username, "another-password").status_code == 200, \
        "resetting the password should not leave the account locked out"


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
