"""
Tests for session lifetime, refresh, and revocation.

JWT_ACCESS_TOKEN_EXPIRES was False, so tokens never expired. There was no
refresh, no revocation, and logout only cleared the phone's storage. A token
that leaked - a shared laptop, a backup, an intercepted request - was permanent
access to someone's finances, and it survived the victim changing their
password. That last part mattered most: it made the password reset flow useless
against the attack it exists to stop.

Run it directly, no pytest needed:

    cd backend
    venv/Scripts/python tests/test_session_lifecycle.py     # Windows
    venv/bin/python tests/test_session_lifecycle.py         # Linux/macOS
"""
import os
import sys
import tempfile
import uuid
from datetime import timedelta

BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, BACKEND_DIR)

_DB_PATH = os.path.join(tempfile.mkdtemp(prefix="sft-session-"), "test.db")
os.environ["DATABASE_URL"] = "sqlite:///" + _DB_PATH.replace(os.sep, "/")
os.environ.setdefault("JWT_SECRET_KEY", "test-secret-not-used-in-production")

from flask_jwt_extended import create_access_token                   # noqa: E402
from flask_migrate import upgrade                                    # noqa: E402

from app import create_app                                           # noqa: E402
from models import User, db                                          # noqa: E402

_app = create_app()
_app.config["PROPAGATE_EXCEPTIONS"] = False
_app.config["TESTING"] = True
with _app.app_context():
    upgrade()
CLIENT = _app.test_client()

PASSWORD = "correct-horse"


def register():
    """Create a user; return (username, access token, refresh token)."""
    username = "s-" + uuid.uuid4().hex[:8]
    r = CLIENT.post("/api/auth/register",
                    json={"username": username, "password": PASSWORD,
                          "email": username + "@example.com"})
    assert r.status_code == 201, r.get_data(as_text=True)
    body = r.get_json()
    return username, body["token"], body["refresh_token"]


def auth(token):
    return {"Authorization": "Bearer " + token}


def protected(token):
    """Any authenticated endpoint, for checking whether a token still works."""
    return CLIENT.get("/api/expenses", headers=auth(token))


def expired_token_for(username):
    """An access token for this user that expired an hour ago."""
    with _app.app_context():
        user = User.query.filter_by(username=username).first()
        return create_access_token(
            identity=str(user.id),
            additional_claims={"tv": user.token_version or 0},
            expires_delta=timedelta(seconds=-3600),
        )


# ── Tokens expire ─────────────────────────────────────────────────────────────

def test_a_fresh_token_works():
    _, token, _ = register()
    assert protected(token).status_code == 200


def test_an_expired_token_is_refused():
    username, _, _ = register()
    r = protected(expired_token_for(username))
    assert r.status_code == 401, r.get_data(as_text=True)


def test_expiry_is_distinguishable_from_invalidity():
    """
    The client refreshes on expiry and signs out on anything else, so the two
    must not look the same.
    """
    username, _, _ = register()

    expired = protected(expired_token_for(username)).get_json()
    assert expired.get("token_expired") is True, expired

    garbage = CLIENT.get("/api/expenses", headers=auth("not.a.token")).get_json()
    assert garbage.get("token_expired") is not True, garbage


def test_tokens_are_issued_at_every_entry_point():
    _, access, refresh = register()
    assert access and refresh and access != refresh

    username = None
    with _app.app_context():
        username = User.query.order_by(User.id.desc()).first().username

    body = CLIENT.post("/api/auth/login",
                       json={"username": username, "password": PASSWORD}).get_json()
    assert body.get("token") and body.get("refresh_token")


# ── Refresh ───────────────────────────────────────────────────────────────────

def test_a_refresh_token_buys_a_working_access_token():
    _, _, refresh = register()
    r = CLIENT.post("/api/auth/refresh", headers=auth(refresh))
    assert r.status_code == 200, r.get_data(as_text=True)

    fresh = r.get_json()["token"]
    assert protected(fresh).status_code == 200


def test_the_two_token_types_are_not_interchangeable():
    _, access, refresh = register()
    # A refresh token must not open a normal endpoint...
    assert protected(refresh).status_code == 401
    # ...and an access token must not buy a new one.
    assert CLIENT.post("/api/auth/refresh", headers=auth(access)).status_code == 401


def test_refresh_survives_access_token_expiry():
    """The whole point: the hourly expiry must be invisible to the user."""
    username, _, refresh = register()
    assert protected(expired_token_for(username)).status_code == 401

    fresh = CLIENT.post("/api/auth/refresh", headers=auth(refresh)).get_json()["token"]
    assert protected(fresh).status_code == 200


# ── Revocation ────────────────────────────────────────────────────────────────

def test_logout_ends_the_session_server_side():
    """Logging out used to clear the phone and nothing else."""
    _, access, refresh = register()
    assert CLIENT.post("/api/auth/logout", headers=auth(access)).status_code == 200

    assert protected(access).status_code == 401, "the access token still worked"
    assert CLIENT.post("/api/auth/refresh", headers=auth(refresh)).status_code == 401, \
        "the refresh token still worked after logout"


def test_resetting_the_password_ends_existing_sessions():
    """
    The case that matters. Someone resetting their password because they think
    they have been compromised expects it to lock the intruder out.
    """
    username, stolen, _ = register()
    with _app.app_context():
        user = User.query.filter_by(username=username).first()
        email = user.email
        code = user.issue_reset_code(15)
        db.session.commit()

    assert protected(stolen).status_code == 200, "precondition: the token works"

    r = CLIENT.post("/api/auth/reset-password",
                    json={"email": email, "code": code, "new_password": "a-new-password"})
    assert r.status_code == 200, r.get_data(as_text=True)

    assert protected(stolen).status_code == 401, \
        "a token stolen before the reset still worked after it"


def test_changing_the_password_ends_other_sessions_but_not_this_one():
    username, phone, _ = register()

    # A second device signed in with the same account.
    other = CLIENT.post("/api/auth/login",
                        json={"username": username, "password": PASSWORD}
                        ).get_json()["token"]
    assert protected(other).status_code == 200

    r = CLIENT.put("/api/auth/profile",
                   json={"new_password": "a-new-password", "current_password": PASSWORD},
                   headers=auth(phone))
    assert r.status_code == 200, r.get_data(as_text=True)

    assert protected(other).status_code == 401, "the other device stayed signed in"

    # The device that made the change is handed a fresh pair rather than being
    # signed out of the account it just updated.
    replacement = r.get_json()
    assert replacement.get("token") and replacement.get("refresh_token")
    assert protected(replacement["token"]).status_code == 200


def test_one_users_logout_leaves_another_alone():
    _, first, _ = register()
    _, second, _ = register()

    CLIENT.post("/api/auth/logout", headers=auth(first))

    assert protected(first).status_code == 401
    assert protected(second).status_code == 200, "logging out one user ended another's session"


# ── Session restore ───────────────────────────────────────────────────────────

def test_me_returns_the_user_for_a_valid_token():
    username, access, _ = register()
    r = CLIENT.get("/api/auth/me", headers=auth(access))
    assert r.status_code == 200, r.get_data(as_text=True)

    body = r.get_json()
    assert body["user"]["username"] == username
    assert "pending_deletion" in body


def test_me_refuses_an_expired_token():
    """
    The splash screen decided it was signed in purely because a token string
    existed in storage. With expiry that would route into a dashboard where
    every request fails.
    """
    username, _, _ = register()
    r = CLIENT.get("/api/auth/me", headers=auth(expired_token_for(username)))
    assert r.status_code == 401


def test_me_refuses_a_revoked_token():
    _, access, _ = register()
    CLIENT.post("/api/auth/logout", headers=auth(access))
    assert CLIENT.get("/api/auth/me", headers=auth(access)).status_code == 401


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
