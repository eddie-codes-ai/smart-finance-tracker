"""
Tests for the guardian alert path — the parts that only run when something
has already gone wrong.

Two problems lived here. Twilio failures were caught only as
TwilioRestException, so a DNS failure or a timeout escaped as an unhandled 500
mid-alert, even though every caller is written against a {"success": False}
dict. And phone numbers were never validated, so "hello" was stored happily and
became "+hello" at dial time — discovered only when an alert silently failed.

Run it directly, no pytest needed:

    cd backend
    venv/Scripts/python tests/test_guardian_notifications.py     # Windows
    venv/bin/python tests/test_guardian_notifications.py         # Linux/macOS
"""
import os
import sys
import tempfile
import uuid

BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, BACKEND_DIR)

_DB_PATH = os.path.join(tempfile.mkdtemp(prefix="sft-guardian-"), "test.db")
os.environ["DATABASE_URL"] = "sqlite:///" + _DB_PATH.replace(os.sep, "/")
os.environ.setdefault("JWT_SECRET_KEY", "test-secret-not-used-in-production")

from flask_migrate import upgrade                                     # noqa: E402

import services.notification_service as notifications                 # noqa: E402
from app import create_app                                            # noqa: E402
from services.guardian_service import (build_guardian_report,         # noqa: E402
                                       normalise_phone)

_app = create_app()
_app.config["PROPAGATE_EXCEPTIONS"] = False
_app.config["TESTING"] = True
with _app.app_context():
    upgrade()
CLIENT = _app.test_client()


def user():
    username = "g-" + uuid.uuid4().hex[:8]
    r = CLIENT.post("/api/auth/register",
                    json={"username": username, "password": "correct-horse"})
    assert r.status_code == 201, r.get_data(as_text=True)
    return {"Authorization": "Bearer " + r.get_json()["token"]}


def link(headers, phone):
    return CLIENT.post("/api/guardian/link", json={"phone_number": phone},
                       headers=headers)


# ── Phone numbers are checked before they are stored ──────────────────────────

def test_kenyan_local_numbers_are_normalised():
    assert normalise_phone("0712345678") == "+254712345678"
    assert normalise_phone("0112345678") == "+254112345678"


def test_international_format_is_kept():
    assert normalise_phone("+254712345678") == "+254712345678"
    assert normalise_phone("+44 7700 900123") == "+447700900123"


def test_spacing_and_punctuation_are_tolerated():
    assert normalise_phone(" 0712 345 678 ") == "+254712345678"
    assert normalise_phone("0712-345-678") == "+254712345678"
    assert normalise_phone("(0712) 345678") == "+254712345678"


def test_nonsense_is_rejected():
    for bad in ["hello", "", "   ", "+", "abc123", "0712abc678", None, "071234"]:
        assert normalise_phone(bad) is None, bad


def test_absurdly_long_numbers_are_rejected():
    assert normalise_phone("+1234567890123456789") is None


def test_the_endpoint_refuses_a_bad_number():
    h = user()
    r = link(h, "hello")
    assert r.status_code == 400, r.get_data(as_text=True)
    assert "valid phone number" in r.get_json()["message"].lower()

    # And nothing was linked.
    status = CLIENT.get("/api/guardian/status", headers=h).get_json()
    assert status["linked"] is False


def test_the_endpoint_stores_the_normalised_number():
    h = user()
    r = link(h, "0712 345 678")
    assert r.status_code == 201, r.get_data(as_text=True)
    assert r.get_json()["guardian"]["phone_number"] == "+254712345678"


# ── Twilio failures stay failures, not 500s ───────────────────────────────────

class _Exploding:
    """Stands in for twilio.rest.Client when the network is unreachable."""

    def __init__(self, *_args, **_kwargs):
        raise ConnectionError("getaddrinfo failed")


class _RefusingClient:
    """Reachable, but Twilio rejects the request."""

    def __init__(self, *_args, **_kwargs):
        self.messages = self

    def create(self, **_kwargs):
        from twilio.base.exceptions import TwilioRestException
        raise TwilioRestException(status=400, uri="/Messages", msg="Unverified number")


def _with_twilio(fake_client, fn):
    original = notifications.Client
    env = {k: os.environ.get(k) for k in
           ("TWILIO_ACCOUNT_SID", "TWILIO_AUTH_TOKEN",
            "TWILIO_WHATSAPP_FROM", "TWILIO_SMS_FROM")}
    os.environ.update({
        "TWILIO_ACCOUNT_SID": "AC" + "0" * 32,
        "TWILIO_AUTH_TOKEN": "x" * 32,
        "TWILIO_WHATSAPP_FROM": "whatsapp:+14155238886",
        "TWILIO_SMS_FROM": "+14155238886",
    })
    notifications.Client = fake_client
    try:
        return fn()
    finally:
        notifications.Client = original
        for k, v in env.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v


def test_a_network_failure_returns_a_result_instead_of_raising():
    """
    Only TwilioRestException was caught, so a DNS failure or timeout escaped as
    an unhandled 500 at the exact moment an alert mattered.
    """
    result = _with_twilio(_Exploding,
                          lambda: notifications.send_whatsapp("+254712345678", "hi"))
    assert result["success"] is False
    assert result["error"]


def test_sms_survives_a_network_failure_too():
    result = _with_twilio(_Exploding,
                          lambda: notifications.send_sms("+254712345678", "hi"))
    assert result["success"] is False


def test_dispatch_reports_both_channels_failing():
    result = _with_twilio(_Exploding,
                          lambda: notifications.dispatch("+254712345678", "hi"))
    assert result["success"] is False
    assert result["channel"] is None


def test_a_twilio_rejection_is_still_reported_cleanly():
    result = _with_twilio(_RefusingClient,
                          lambda: notifications.send_whatsapp("+254712345678", "hi"))
    assert result["success"] is False
    assert "unverified" in result["error"].lower()


def test_missing_credentials_are_reported_not_raised():
    for key in ("TWILIO_ACCOUNT_SID", "TWILIO_AUTH_TOKEN", "TWILIO_WHATSAPP_FROM"):
        os.environ.pop(key, None)
    result = notifications.send_whatsapp("+254712345678", "hi")
    assert result["success"] is False
    assert "not configured" in result["error"].lower()


# ── The report itself ─────────────────────────────────────────────────────────

def test_the_report_builds_without_a_day_in_the_payload():
    """
    This line called datetime.now() against an import that had been removed
    during the timezone work, so the fallback path raised NameError instead of
    defaulting. Only reachable with an incomplete payload, which is why nothing
    caught it.
    """
    text = build_guardian_report("alice", {"score": 42, "category": "At Risk",
                                           "persona": "Test", "advice": []}, {})
    assert "alice" in text
    assert "42/100" in text


def test_the_report_uses_the_day_from_the_payload():
    text = build_guardian_report(
        "alice",
        {"score": 42, "category": "At Risk", "persona": "Test", "advice": []},
        {"day_of_month": 17, "period": "2026-04"})
    assert "Day 17" in text


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
