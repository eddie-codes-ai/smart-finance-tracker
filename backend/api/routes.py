import json as _json
import os
import secrets
from datetime import datetime, timedelta, timezone
from typing import Optional

from flask import Blueprint, request, jsonify, g, current_app
from flask_jwt_extended import (create_access_token, create_refresh_token,
                                jwt_required, get_jwt_identity)

from app_time import (DEFAULT_TIMEZONE_NAME, is_valid_timezone, known_timezones,
                      month_range_utc, now_in, resolve_timezone, utc_now)

from models import (db, User, Income, Expense, Budget, SavingsGoal,
                    GoalContribution, HelbPlan, UserCategory, UserIncomeType,
                    DEFAULT_EXPENSE_CATEGORIES, DEFAULT_INCOME_TYPES,
                    DELETION_GRACE_HOURS, EXPENSE_TYPES, RECURRENCE_CHOICES)
from engine.knowledge_engine import run_analysis
from services.analysis_service import compute_analysis_payload
from services.email_service import send_reset_email
from services.guardian_service import (
    get_guardian, link_guardian, unlink_guardian,
    build_guardian_report, save_report, get_latest_report, can_auto_notify
)
from services.notification_service import dispatch

api = Blueprint("api", __name__, url_prefix="/api")


# ─── Helpers ──────────────────────────────────────────────────────────────────

def success(data: dict, status: int = 200):
    return jsonify({"status": "success", **data}), status

def error(message: str, status: int = 400):
    return jsonify({"status": "error", "message": message}), status

def body() -> dict:
    """
    Request JSON as a dict, never None.

    A plain request.get_json() raises on a missing or malformed body, which
    used to surface as an HTML 500. Returning {} lets each route report the
    specific field it needs instead.
    """
    data = request.get_json(silent=True)
    return data if isinstance(data, dict) else {}

def positive_amount(value) -> Optional[float]:
    """
    Coerce a client-supplied amount to a positive float, or None if it isn't one.

    Guards the bare float(value) calls that returned a 500 for any non-numeric
    input. Also rejects NaN and infinity, which float() accepts happily and
    which poison every downstream total.
    """
    if value is None or isinstance(value, bool):
        return None
    try:
        amount = float(value)
    except (TypeError, ValueError):
        return None
    if amount != amount or amount in (float("inf"), float("-inf")):
        return None
    if amount <= 0:
        return None
    return amount

def current_user_tz():
    """
    The signed-in user's home timezone, resolved once per request.

    Month boundaries and daily spending buckets are computed in this zone, so
    every handler that answers a calendar question needs it. Cached on flask.g
    because a single handler can ask three times and this should not mean three
    queries.
    """
    if not hasattr(g, "_user_tz"):
        user = User.query.get(int(get_jwt_identity()))
        g._user_tz = resolve_timezone(user.timezone if user else None)
    return g._user_tz


def issue_session(user) -> dict:
    """
    Mint an access/refresh pair for a user.

    Both carry the user's current token_version, so bumping that column ends
    every session they hold. The access token is short-lived and refreshed
    silently by the app; the refresh token is what decides how often a password
    is actually typed again.
    """
    claims = {"tv": user.token_version or 0}
    identity = str(user.id)
    return {
        "token":         create_access_token(identity=identity, additional_claims=claims),
        "refresh_token": create_refresh_token(identity=identity, additional_claims=claims),
    }


def parse_timestamp(value) -> Optional[datetime]:
    """
    Parse an ISO 8601 string into a naive datetime, or None if it isn't one.

    Every timestamp in this database is stored naive, so an offset-aware value
    is converted to UTC and stripped rather than stored in a second, silently
    incompatible representation.
    """
    if not isinstance(value, str) or not value.strip():
        return None
    text = value.strip()
    # datetime.fromisoformat() cannot read a trailing "Z" before Python 3.11,
    # and the Dockerfile pins 3.9.
    if text.endswith(("Z", "z")):
        text = text[:-1]
    try:
        moment = datetime.fromisoformat(text)
    except ValueError:
        return None
    if moment.tzinfo is not None:
        moment = moment.astimezone(timezone.utc).replace(tzinfo=None)
    return moment


# How far ahead of "now" a client-supplied timestamp may sit before we reject
# it. The slack absorbs device clock skew and the UTC/EAT offset that the app
# does not yet account for.
FUTURE_TIMESTAMP_SLACK = timedelta(hours=24)


def is_future_timestamp(moment: datetime) -> bool:
    return moment > utc_now() + FUTURE_TIMESTAMP_SLACK


def mpesa_code(value) -> Optional[str]:
    """
    Normalise a submitted M-Pesa confirmation code, or None if there isn't one.

    The parser yields the literal string "N/A" when it cannot find a code in the
    message. Storing that would make the second unparseable import collide with
    the first under the unique constraint, so it is treated as absent - which is
    what it means.
    """
    if not isinstance(value, str):
        return None
    code = value.strip().upper()
    if not code or code == "N/A":
        return None
    return code[:20]


def created_at_from(data: dict):
    """
    Resolve an optional client-supplied date_added for a new record.

    Returns (value, None) or (None, error_response). Imported transactions carry
    the date of the original SMS; without this every imported message landed on
    the day it was imported.
    """
    if "date_added" not in data:
        return None, None
    moment = parse_timestamp(data.get("date_added"))
    if moment is None:
        return None, error("Invalid date_added. Use an ISO 8601 timestamp.")
    if is_future_timestamp(moment):
        return None, error("date_added cannot be in the future.")
    return moment, None


MIN_PASSWORD_LENGTH = 6

# A six-digit code is only a million possibilities, so what actually protects it
# is the attempt budget, not its own entropy. Five wrong guesses destroys it.
RESET_CODE_TTL_MINUTES = 15          # what the email has always claimed
MAX_RESET_ATTEMPTS     = 5

# Login throttling. Generous on purpose: a low threshold would let anyone who
# knows a username lock that person out at will.
MAX_LOGIN_ATTEMPTS   = 10
LOGIN_LOCKOUT_MINUTES = 15

def password_problem(password: str) -> Optional[str]:
    """Return an error message if the password is unacceptable, else None."""
    if not password:
        return "Password is required."
    if len(password) < MIN_PASSWORD_LENGTH:
        return f"Password must be at least {MIN_PASSWORD_LENGTH} characters long."
    return None

# Why _verify_google_token returned None, so the caller can tell a broken server
# apart from a bad token. Collapsing these into a bare `return None` is what let
# a missing google-auth dependency report itself as "Invalid or expired Google
# token" — blaming the user's credentials for a server-side fault.
GOOGLE_NOT_CONFIGURED = "not_configured"
GOOGLE_BAD_TOKEN      = "bad_token"


def _verify_google_token(id_token_str: str):
    """
    Verify a Google ID token.

    Returns (profile, None) on success, or (None, reason) on failure, where
    reason is GOOGLE_NOT_CONFIGURED for a server problem the user cannot act on
    and GOOGLE_BAD_TOKEN for a token that is genuinely invalid or expired.
    """
    google_client_id = os.environ.get("GOOGLE_CLIENT_ID")
    if not google_client_id:
        current_app.logger.error(
            "Google sign-in attempted but GOOGLE_CLIENT_ID is not set.")
        return None, GOOGLE_NOT_CONFIGURED

    try:
        from google.oauth2 import id_token as g_id_token
        from google.auth.transport import requests as g_requests
    except ImportError:
        current_app.logger.exception(
            "google-auth is not installed; add it to requirements.txt.")
        return None, GOOGLE_NOT_CONFIGURED

    try:
        idinfo = g_id_token.verify_oauth2_token(
            id_token_str, g_requests.Request(), google_client_id)
    except ValueError as e:
        # Wrong audience, bad signature, expired — all genuinely the token.
        current_app.logger.warning("Google token rejected: %s", e)
        return None, GOOGLE_BAD_TOKEN
    except Exception:
        # Network failure reaching Google's certs, and anything else unforeseen.
        current_app.logger.exception("Google token verification failed.")
        return None, GOOGLE_NOT_CONFIGURED

    return {
        "google_id": idinfo["sub"],
        "email":     idinfo.get("email", ""),
        "name":      idinfo.get("name", ""),
    }, None


def _purge_expired_deletions():
    cutoff = utc_now() - timedelta(hours=DELETION_GRACE_HOURS)
    expired = User.query.filter(
        User.deletion_requested_at != None,
        User.deletion_requested_at <= cutoff,
    ).all()
    for user in expired:
        db.session.delete(user)
    if expired:
        db.session.commit()


# ═══════════════════════════════════════════════════════════════════════════════
# AUTH
# ═══════════════════════════════════════════════════════════════════════════════

@api.route("/auth/register", methods=["POST"])
def register():
    data     = body()
    username = data.get("username", "").strip()
    password = data.get("password", "")
    email    = data.get("email", "").strip().lower() or None
    if not username:
        return error("Username is required.")
    problem = password_problem(password)
    if problem:
        return error(problem)
    if User.query.filter_by(username=username).first():
        return error("Username already exists.", 409)
    if email and User.query.filter_by(email=email).first():
        return error("Email already registered.", 409)
    user = User(username=username, email=email)
    requested_tz = (data.get("timezone") or "").strip()
    if requested_tz and is_valid_timezone(requested_tz):
        user.timezone = requested_tz
    else:
        user.timezone = DEFAULT_TIMEZONE_NAME
    user.set_password(password)
    db.session.add(user)
    db.session.commit()
    return success({"message": "Account created.", "user": user.to_dict(),
                    **issue_session(user)}, 201)


@api.route("/auth/login", methods=["POST"])
def login():
    _purge_expired_deletions()
    data     = body()
    username = data.get("username", "").strip()
    password = data.get("password", "")
    user = User.query.filter_by(username=username).first()

    if user and user.is_locked_out:
        # Say so plainly. Hiding it behind "invalid password" would leave
        # someone who simply mistyped retrying a password that is actually
        # correct, with no idea why it keeps failing.
        return error(
            f"Too many failed attempts. Try again in {LOGIN_LOCKOUT_MINUTES} minutes, "
            "or reset your password.", 429)

    if not user or not user.check_password(password):
        if user:
            user.register_failed_login(MAX_LOGIN_ATTEMPTS, LOGIN_LOCKOUT_MINUTES)
            db.session.commit()
        return error("Invalid username or password.", 401)

    user.clear_login_failures()
    db.session.commit()
    return success({
        **issue_session(user),
        "user":             user.to_dict(),
        "pending_deletion": user.is_pending_deletion,
        "deletion_due_at":  user.deletion_due_at.isoformat() if user.deletion_due_at else None,
    })


@api.route("/auth/google", methods=["POST"])
def google_signin():
    data         = body()
    id_token_str = data.get("id_token", "").strip()
    if not id_token_str:
        return error("Google ID token is required.")
    google_info, failure = _verify_google_token(id_token_str)
    if failure == GOOGLE_NOT_CONFIGURED:
        # The user can do nothing about this; say so rather than blaming their
        # credentials, and use a status that reads as "our fault".
        return error("Google sign-in is not available right now. "
                     "Please sign in with your username and password.", 503)
    if not google_info:
        return error("Invalid or expired Google token.", 401)
    google_id = google_info["google_id"]
    email     = google_info["email"]
    name      = google_info["name"]
    user = User.query.filter_by(google_id=google_id).first()
    if not user and email:
        user = User.query.filter_by(email=email).first()
        if user:
            user.google_id = google_id
    if not user:
        base = (email.split("@")[0] if email else name.replace(" ", "").lower()) or "user"
        base = base[:30]
        username, counter = base, 1
        while User.query.filter_by(username=username).first():
            username = f"{base}{counter}"; counter += 1
        user = User(username=username, email=email, google_id=google_id)
        user.password_hash = secrets.token_hex(32)
        db.session.add(user)
    db.session.commit()
    return success({"user": user.to_dict(), **issue_session(user)})


@api.route("/auth/refresh", methods=["POST"])
@jwt_required(refresh=True)
def refresh_session():
    """
    Exchange a refresh token for a new access token.

    Only accepts refresh tokens - an access token presented here is rejected by
    the decorator, and vice versa at every other endpoint, so the two cannot be
    used interchangeably.
    """
    user = User.query.get(int(get_jwt_identity()))
    if not user:
        return error("Your session is no longer valid. Please sign in again.", 401)
    claims = {"tv": user.token_version or 0}
    return success({
        "token": create_access_token(identity=str(user.id), additional_claims=claims),
    })


@api.route("/auth/logout", methods=["POST"])
@jwt_required()
def logout():
    """
    End every session this user holds.

    Logging out used to clear the phone's storage and nothing else, so a token
    already copied elsewhere kept working indefinitely.
    """
    user = User.query.get(int(get_jwt_identity()))
    if user:
        user.revoke_all_sessions()
        db.session.commit()
    return success({"message": "Signed out."})


@api.route("/auth/me", methods=["GET"])
@jwt_required()
def current_user():
    """
    The signed-in user, for restoring a session on app start.

    The app previously decided it was logged in purely because a token string
    existed in storage - never checking whether it was still valid, and never
    reloading the user, which is why the profile screen showed "Unknown" until
    the next manual sign-in.
    """
    user = User.query.get(int(get_jwt_identity()))
    if not user:
        return error("Your session is no longer valid. Please sign in again.", 401)
    return success({
        "user":             user.to_dict(),
        "pending_deletion": user.is_pending_deletion,
        "deletion_due_at":  user.deletion_due_at.isoformat() if user.deletion_due_at else None,
    })


@api.route("/auth/forgot-password", methods=["POST"])
def forgot_password():
    data  = body()
    email = data.get("email", "").strip().lower()
    if not email:
        return error("Email address is required.")
    user = User.query.filter_by(email=email).first()
    if user:
        code = user.issue_reset_code(RESET_CODE_TTL_MINUTES)
        db.session.commit()
        result = send_reset_email(email, user.username, code)
        if not result.get("success"):
            # Logged, not returned: answering differently when the send fails
            # would tell an attacker which addresses are registered, which is
            # exactly what the deliberately vague reply below prevents.
            current_app.logger.error("Reset email to %s failed: %s",
                                     email, result.get("error"))
    return success({"message": "If that email is registered, a reset code has been sent. Check your inbox and spam folder."})


@api.route("/auth/reset-password", methods=["POST"])
def reset_password_endpoint():
    data         = body()
    email        = data.get("email", "").strip().lower()
    code         = data.get("code", "").strip()
    new_password = data.get("new_password", "")
    if not all([email, code, new_password]):
        return error("Email, reset code, and new password are all required.")
    problem = password_problem(new_password)
    if problem:
        return error(problem)
    user = User.query.filter_by(email=email).first()
    if not user or not user.reset_token:
        return error("Invalid or expired reset code.", 400)

    if user.reset_token_expiry is None or user.reset_token_expiry < utc_now():
        user.clear_reset_code()
        db.session.commit()
        return error("Reset code has expired. Please request a new one.", 400)

    if not user.check_reset_code(code):
        user.reset_attempts = (user.reset_attempts or 0) + 1
        remaining = MAX_RESET_ATTEMPTS - user.reset_attempts
        if remaining <= 0:
            # Burn the code rather than counting forever. Without this the six
            # digits could simply be enumerated.
            user.clear_reset_code()
            db.session.commit()
            return error("Too many incorrect attempts. Please request a new reset code.", 400)
        db.session.commit()
        return error(f"Incorrect reset code. {remaining} attempt(s) remaining.", 400)

    user.set_password(new_password)
    user.clear_reset_code()
    user.clear_login_failures()   # a successful reset should not leave them locked out
    # End every existing session. Someone resetting their password because they
    # suspect a compromise expects that to lock the intruder out; without this
    # a stolen token kept working regardless.
    user.revoke_all_sessions()
    db.session.commit()
    return success({"message": "Password reset successfully. You can now log in with your new password."})


@api.route("/auth/profile", methods=["PUT"])
@jwt_required()
def update_profile():
    user_id          = int(get_jwt_identity())
    user             = User.query.get(user_id)
    data             = body()
    new_username     = data.get("username", "").strip() or None
    new_email        = data.get("email", "").strip().lower() or None
    new_password     = data.get("new_password", "") or None
    current_password = data.get("current_password", "") or None
    new_timezone     = (data.get("timezone") or "").strip() or None
    password_changed = False
    if not any([new_username, new_email, new_password, new_timezone]):
        return error("No changes provided.")
    if new_timezone:
        if not is_valid_timezone(new_timezone):
            return error(f"'{new_timezone}' is not a recognised time zone.")
        user.timezone = new_timezone
    if new_username:
        if new_username == user.username:
            return error("New username is the same as your current username.")
        if User.query.filter(User.username == new_username, User.id != user_id).first():
            return error("That username is already taken.", 409)
        user.username = new_username
    if new_email:
        if new_email == user.email:
            return error("New email is the same as your current email.")
        if User.query.filter(User.email == new_email, User.id != user_id).first():
            return error("That email is already registered.", 409)
        user.email = new_email
    if new_password:
        if not current_password:
            return error("Current password is required to set a new password.")
        if not user.check_password(current_password):
            return error("Current password is incorrect.", 401)
        problem = password_problem(new_password)
        if problem:
            return error(problem)
        user.set_password(new_password)
        # End sessions on every other device. The caller gets a fresh pair
        # below, so changing your own password does not sign you out of the
        # device you just changed it on.
        user.revoke_all_sessions()
        password_changed = True
    db.session.commit()

    response = {"message": "Profile updated successfully.", "user": user.to_dict()}
    if password_changed:
        response.update(issue_session(user))
        response["message"] = ("Password changed. You have been signed out on any "
                               "other devices.")
    return success(response)


@api.route("/auth/account", methods=["DELETE"])
@jwt_required()
def request_account_deletion():
    user_id  = int(get_jwt_identity())
    user     = User.query.get(user_id)
    data     = body()
    password = data.get("password", "")
    if not password:
        return error("Password is required to delete your account.")
    if not user.check_password(password):
        return error("Incorrect password.", 401)
    if user.is_pending_deletion:
        return error("Account deletion is already scheduled.", 400)
    user.deletion_requested_at = utc_now()
    db.session.commit()
    return success({
        "message":         f"Account scheduled for deletion in {DELETION_GRACE_HOURS} hours.",
        "deletion_due_at": user.deletion_due_at.isoformat(),
    })


@api.route("/auth/cancel-deletion", methods=["POST"])
@jwt_required()
def cancel_account_deletion():
    user_id = int(get_jwt_identity())
    user    = User.query.get(user_id)
    if not user.is_pending_deletion:
        return error("No pending deletion request found.", 400)
    user.deletion_requested_at = None
    db.session.commit()
    return success({"message": "Account deletion cancelled. Your account is safe.", "user": user.to_dict()})


@api.route("/mpesa/imported", methods=["POST"])
@jwt_required()
def mpesa_imported():
    """
    POST /api/mpesa/imported   { "codes": ["SB27LJ9O3R", ...] }

    Returns the subset this user has already imported, so the import screen can
    mark those messages instead of letting the user tap one and be refused.
    One round trip for the whole visible list.
    """
    user_id = int(get_jwt_identity())
    raw     = body().get("codes")
    if not isinstance(raw, list):
        return error("codes must be a list of M-Pesa transaction codes.")

    codes = {c for c in (mpesa_code(v) for v in raw) if c}
    if not codes:
        return success({"imported": []})

    found = set()
    for model in (Expense, Income):
        rows = model.query.filter(
            model.user_id == user_id,
            model.mpesa_code.in_(codes),
        ).all()
        found.update(r.mpesa_code for r in rows)

    return success({"imported": sorted(found)})


@api.route("/timezones", methods=["GET"])
@jwt_required()
def get_timezones():
    """
    Every IANA zone this server accepts.

    Served from the backend so the app's picker can never offer a name the
    server would reject, and so the app does not have to ship its own copy of
    the tz database.
    """
    return success({"timezones": known_timezones(), "default": DEFAULT_TIMEZONE_NAME})


# ═══════════════════════════════════════════════════════════════════════════════
# CATEGORIES
# ═══════════════════════════════════════════════════════════════════════════════

@api.route("/categories", methods=["GET"])
@jwt_required()
def get_categories():
    user_id = int(get_jwt_identity())
    custom  = UserCategory.query.filter_by(user_id=user_id).order_by(UserCategory.created_at).all()
    defaults = [{"name": c, "is_custom": False} for c in DEFAULT_EXPENSE_CATEGORIES]
    customs  = [c.to_dict() for c in custom]
    return success({"categories": defaults + customs})


@api.route("/categories", methods=["POST"])
@jwt_required()
def add_category():
    user_id = int(get_jwt_identity())
    data    = body()
    name    = data.get("name", "").strip()
    if not name:
        return error("Category name is required.")
    if len(name) > 50:
        return error("Category name must be 50 characters or less.")
    if name in DEFAULT_EXPENSE_CATEGORIES:
        return error(f"'{name}' is already a default category.", 409)
    existing = UserCategory.query.filter(
        UserCategory.user_id == user_id,
        UserCategory.name.ilike(name),
    ).first()
    if existing:
        return error(f"You already have a category named '{existing.name}'.", 409)
    category = UserCategory(user_id=user_id, name=name)
    db.session.add(category)
    db.session.commit()
    return success({"message": "Category added.", "category": category.to_dict()}, 201)


@api.route("/categories/<string:name>", methods=["DELETE"])
@jwt_required()
def delete_category(name: str):
    user_id = int(get_jwt_identity())
    if name in DEFAULT_EXPENSE_CATEGORIES:
        return error(f"'{name}' is a default category and cannot be deleted.", 403)
    category = UserCategory.query.filter_by(user_id=user_id, name=name).first()
    if not category:
        return error("Custom category not found.", 404)
    db.session.delete(category)
    db.session.commit()
    return success({"message": f"Category '{name}' deleted."})


# ═══════════════════════════════════════════════════════════════════════════════
# INCOME TYPES
# ═══════════════════════════════════════════════════════════════════════════════

@api.route("/income-types", methods=["GET"])
@jwt_required()
def get_income_types():
    """
    GET /api/income-types
    Returns all income types available to the user:
    - Default income types (always present, is_custom: False)
    - User's custom income types (is_custom: True)
    """
    user_id = int(get_jwt_identity())
    custom  = UserIncomeType.query.filter_by(user_id=user_id).order_by(UserIncomeType.created_at).all()
    defaults = [{"name": t, "is_custom": False} for t in DEFAULT_INCOME_TYPES]
    customs  = [t.to_dict() for t in custom]
    return success({"income_types": defaults + customs})


@api.route("/income-types", methods=["POST"])
@jwt_required()
def add_income_type():
    """
    POST /api/income-types
    Body: { "name": "freelance" }
    Adds a custom income type for this user.
    """
    user_id = int(get_jwt_identity())
    data    = body()
    name    = data.get("name", "").strip().lower()
    if not name:
        return error("Income type name is required.")
    if len(name) > 50:
        return error("Income type name must be 50 characters or less.")
    if name in DEFAULT_INCOME_TYPES:
        return error(f"'{name}' is already a default income type.", 409)
    existing = UserIncomeType.query.filter(
        UserIncomeType.user_id == user_id,
        UserIncomeType.name.ilike(name),
    ).first()
    if existing:
        return error(f"You already have an income type named '{existing.name}'.", 409)
    income_type = UserIncomeType(user_id=user_id, name=name)
    db.session.add(income_type)
    db.session.commit()
    return success({"message": "Income type added.", "income_type": income_type.to_dict()}, 201)


@api.route("/income-types/<string:name>", methods=["DELETE"])
@jwt_required()
def delete_income_type(name: str):
    """
    DELETE /api/income-types/<name>
    Deletes a custom income type by name.
    Returns 403 if trying to delete a default income type.
    """
    user_id = int(get_jwt_identity())
    if name in DEFAULT_INCOME_TYPES:
        return error(f"'{name}' is a default income type and cannot be deleted.", 403)
    income_type = UserIncomeType.query.filter_by(user_id=user_id, name=name).first()
    if not income_type:
        return error("Custom income type not found.", 404)
    db.session.delete(income_type)
    db.session.commit()
    return success({"message": f"Income type '{name}' deleted."})


# ═══════════════════════════════════════════════════════════════════════════════
# INCOME
# ═══════════════════════════════════════════════════════════════════════════════

@api.route("/income", methods=["POST"])
@jwt_required()
def add_income():
    user_id = int(get_jwt_identity())
    data    = body()
    amount      = positive_amount(data.get("amount"))
    income_type = data.get("income_type", "monthly")
    description = data.get("description", "")
    if amount is None:
        return error("A valid amount is required.")

    code = mpesa_code(data.get("mpesa_code"))
    if code:
        existing = Income.query.filter_by(user_id=user_id, mpesa_code=code).first()
        if existing:
            return jsonify({
                "status":  "error",
                "message": "This M-Pesa message has already been imported.",
                "income":  existing.to_dict(),
            }), 409

    created_at, failure = created_at_from(data)
    if failure:
        return failure

    income = Income(user_id=user_id, amount=amount, income_type=income_type,
                    description=description, mpesa_code=code)
    if created_at:
        income.date_added = created_at
    db.session.add(income)
    db.session.commit()
    return success({"message": "Income added.", "income": income.to_dict()}, 201)


@api.route("/income", methods=["GET"])
@jwt_required()
def get_income():
    user_id = int(get_jwt_identity())
    tz      = current_user_tz()
    today   = now_in(tz)
    month   = request.args.get("month", today.month, type=int)
    year    = request.args.get("year",  today.year,  type=int)
    period_start, period_end = month_range_utc(year, month, tz)
    records = Income.query.filter(
        Income.user_id == user_id,
        Income.date_added >= period_start,
        Income.date_added <  period_end,
    ).order_by(Income.date_added.desc()).all()
    return success({"income": [r.to_dict() for r in records]})


@api.route("/income/<int:income_id>", methods=["DELETE"])
@jwt_required()
def delete_income(income_id):
    user_id = int(get_jwt_identity())
    record  = Income.query.filter_by(id=income_id, user_id=user_id).first()
    if not record:
        return error("Income record not found.", 404)
    db.session.delete(record)
    db.session.commit()
    return success({"message": "Income deleted."})


@api.route("/income/<int:income_id>", methods=["PUT"])
@jwt_required()
def update_income(income_id):
    """
    PUT /api/income/<id>

    Partial update, same semantics as PUT /api/expenses/<id>.
    """
    user_id = int(get_jwt_identity())
    record  = Income.query.filter_by(id=income_id, user_id=user_id).first()
    if not record:
        return error("Income record not found.", 404)

    data = body()

    if "amount" in data:
        amount = positive_amount(data.get("amount"))
        if amount is None:
            return error("A valid amount is required.")
        record.amount = amount

    if "income_type" in data:
        # Left unchecked for the same reason as expense category above — a user
        # may delete a custom income type that existing records still name.
        income_type = (data.get("income_type") or "").strip()
        if not income_type:
            return error("Income type cannot be empty.")
        record.income_type = income_type

    if "description" in data:
        record.description = (data.get("description") or "").strip()

    if "date_added" in data:
        moment = parse_timestamp(data.get("date_added"))
        if moment is None:
            return error("Invalid date_added. Use an ISO 8601 timestamp.")
        if is_future_timestamp(moment):
            return error("date_added cannot be in the future.")
        record.date_added = moment

    db.session.commit()
    return success({"message": "Income updated.", "income": record.to_dict()})


# ═══════════════════════════════════════════════════════════════════════════════
# EXPENSES
# ═══════════════════════════════════════════════════════════════════════════════

@api.route("/expenses", methods=["POST"])
@jwt_required()
def add_expense():
    user_id = int(get_jwt_identity())
    data    = body()
    amount              = positive_amount(data.get("amount"))
    category            = data.get("category", "Other")
    description         = data.get("description", "")
    expense_type        = data.get("expense_type", "daily")
    recurrence_interval = data.get("recurrence_interval", None)
    if amount is None:
        return error("A valid amount is required.")
    if expense_type not in EXPENSE_TYPES:
        return error(f"expense_type must be one of: {', '.join(EXPENSE_TYPES)}.")
    if recurrence_interval not in (None, "") and recurrence_interval not in RECURRENCE_CHOICES:
        return error(f"recurrence_interval must be one of: {', '.join(RECURRENCE_CHOICES)}.")

    code = mpesa_code(data.get("mpesa_code"))
    if code:
        existing = Expense.query.filter_by(user_id=user_id, mpesa_code=code).first()
        if existing:
            # 409 with the row it matched, so the app can say which transaction
            # this already is rather than showing a bare failure.
            return jsonify({
                "status":  "error",
                "message": "This M-Pesa message has already been imported.",
                "expense": existing.to_dict(),
            }), 409

    created_at, failure = created_at_from(data)
    if failure:
        return failure

    expense = Expense(user_id=user_id, amount=amount, category=category,
                      description=description, expense_type=expense_type,
                      recurrence_interval=recurrence_interval or None,
                      mpesa_code=code)
    if created_at:
        expense.date_added = created_at
    db.session.add(expense)
    db.session.commit()
    return success({"message": "Expense added.", "expense": expense.to_dict()}, 201)


@api.route("/expenses", methods=["GET"])
@jwt_required()
def get_expenses():
    user_id = int(get_jwt_identity())
    tz      = current_user_tz()
    today   = now_in(tz)
    month   = request.args.get("month", today.month, type=int)
    year    = request.args.get("year",  today.year,  type=int)
    period_start, period_end = month_range_utc(year, month, tz)
    records = Expense.query.filter(
        Expense.user_id == user_id,
        Expense.date_added >= period_start,
        Expense.date_added <  period_end,
    ).order_by(Expense.date_added.desc()).all()
    return success({"expenses": [r.to_dict() for r in records]})


@api.route("/expenses/<int:expense_id>", methods=["DELETE"])
@jwt_required()
def delete_expense(expense_id):
    user_id = int(get_jwt_identity())
    record  = Expense.query.filter_by(id=expense_id, user_id=user_id).first()
    if not record:
        return error("Expense record not found.", 404)
    db.session.delete(record)
    db.session.commit()
    return success({"message": "Expense deleted."})


@api.route("/expenses/<int:expense_id>", methods=["PUT"])
@jwt_required()
def update_expense(expense_id):
    """
    PUT /api/expenses/<id>

    Partial update — only the fields present in the body are changed, matching
    the convention already used by PUT /auth/profile. date_added is preserved
    unless explicitly supplied, so correcting an amount never moves a
    transaction to today.
    """
    user_id = int(get_jwt_identity())
    record  = Expense.query.filter_by(id=expense_id, user_id=user_id).first()
    if not record:
        return error("Expense record not found.", 404)

    data = body()

    if "amount" in data:
        amount = positive_amount(data.get("amount"))
        if amount is None:
            return error("A valid amount is required.")
        record.amount = amount

    if "category" in data:
        # Not checked against the category list: deleting a custom category
        # leaves existing records pointing at it, and rejecting those would
        # make them permanently uneditable.
        category = (data.get("category") or "").strip()
        if not category:
            return error("Category cannot be empty.")
        record.category = category

    if "description" in data:
        record.description = (data.get("description") or "").strip()

    if "expense_type" in data:
        expense_type = (data.get("expense_type") or "").strip()
        if expense_type not in EXPENSE_TYPES:
            return error(f"expense_type must be one of: {', '.join(EXPENSE_TYPES)}.")
        record.expense_type = expense_type

    if "recurrence_interval" in data:
        interval = data.get("recurrence_interval")
        if interval not in (None, "") and interval not in RECURRENCE_CHOICES:
            return error(f"recurrence_interval must be one of: {', '.join(RECURRENCE_CHOICES)}.")
        record.recurrence_interval = interval or None
    elif record.expense_type != "recurring":
        # Switching a recurring expense to any other type would otherwise leave
        # a stale interval behind. Enforced here so no client has to remember.
        record.recurrence_interval = None

    if "date_added" in data:
        moment = parse_timestamp(data.get("date_added"))
        if moment is None:
            return error("Invalid date_added. Use an ISO 8601 timestamp.")
        if is_future_timestamp(moment):
            return error("date_added cannot be in the future.")
        record.date_added = moment

    db.session.commit()
    return success({"message": "Expense updated.", "expense": record.to_dict()})


# ═══════════════════════════════════════════════════════════════════════════════
# BUDGETS
# ═══════════════════════════════════════════════════════════════════════════════

@api.route("/budgets", methods=["POST"])
@jwt_required()
def set_budget():
    user_id    = int(get_jwt_identity())
    data       = body()
    category   = data.get("category")
    limit      = positive_amount(data.get("limit"))
    month_year = data.get("month_year", now_in(current_user_tz()).strftime("%Y-%m"))
    if not category or limit is None:
        return error("Category and a valid limit are required.")
    existing = Budget.query.filter_by(user_id=user_id, category=category, month_year=month_year).first()
    if existing:
        existing.limit = limit
    else:
        db.session.add(Budget(user_id=user_id, category=category, limit=limit, month_year=month_year))
    db.session.commit()
    return success({"message": "Budget saved."}, 201)


@api.route("/budgets", methods=["GET"])
@jwt_required()
def get_budgets():
    user_id    = int(get_jwt_identity())
    month_year = request.args.get("month_year", now_in(current_user_tz()).strftime("%Y-%m"))
    records    = Budget.query.filter_by(user_id=user_id, month_year=month_year).all()
    return success({"budgets": [r.to_dict() for r in records]})


# ═══════════════════════════════════════════════════════════════════════════════
# SAVINGS GOALS
# ═══════════════════════════════════════════════════════════════════════════════

@api.route("/goals", methods=["POST"])
@jwt_required()
def add_goal():
    user_id      = int(get_jwt_identity())
    data         = body()
    name         = data.get("name", "My Goal")
    goal_amount  = positive_amount(data.get("goal_amount"))
    due_date_str = data.get("due_date")
    if goal_amount is None:
        return error("A valid goal amount is required.")
    if not due_date_str:
        return error("A due date is required.")
    try:
        due_date = datetime.strptime(due_date_str, "%Y-%m-%d").date()
    except ValueError:
        return error("Invalid due_date format. Use YYYY-MM-DD.")
    goal = SavingsGoal(user_id=user_id, name=name, goal_amount=goal_amount, due_date=due_date)
    db.session.add(goal)
    db.session.commit()
    return success({"message": "Goal created.", "goal": goal.to_dict()}, 201)


@api.route("/goals", methods=["GET"])
@jwt_required()
def get_goals():
    user_id = int(get_jwt_identity())
    goals   = SavingsGoal.query.filter_by(user_id=user_id, is_active=True).all()
    return success({"goals": [g.to_dict() for g in goals]})


@api.route("/goals/<int:goal_id>", methods=["DELETE"])
@jwt_required()
def close_goal(goal_id):
    user_id = int(get_jwt_identity())
    goal    = SavingsGoal.query.filter_by(id=goal_id, user_id=user_id).first()
    if not goal:
        return error("Goal not found.", 404)
    goal.is_active = False
    db.session.commit()
    return success({"message": "Goal closed."})


@api.route("/goals/<int:goal_id>/contribute", methods=["POST"])
@jwt_required()
def add_contribution(goal_id):
    user_id = int(get_jwt_identity())
    goal    = SavingsGoal.query.filter_by(id=goal_id, user_id=user_id, is_active=True).first()
    if not goal:
        return error("Goal not found.", 404)
    data   = body()
    amount = positive_amount(data.get("amount"))
    note   = (data.get("note") or "").strip() or None
    if amount is None:
        return error("A valid amount is required.")
    contribution = GoalContribution(goal_id=goal_id, user_id=user_id, amount=amount, note=note)
    db.session.add(contribution)
    db.session.commit()
    return success({"message": "Contribution added.", "contribution": contribution.to_dict(), "goal": goal.to_dict()}, 201)


@api.route("/goals/<int:goal_id>/contributions", methods=["GET"])
@jwt_required()
def get_contributions(goal_id):
    user_id = int(get_jwt_identity())
    goal    = SavingsGoal.query.filter_by(id=goal_id, user_id=user_id).first()
    if not goal:
        return error("Goal not found.", 404)
    contributions = (GoalContribution.query.filter_by(goal_id=goal_id)
                     .order_by(GoalContribution.date_added.desc()).all())
    return success({"contributions": [c.to_dict() for c in contributions], "total_contributed": goal.total_contributed})


@api.route("/contributions", methods=["GET"])
@jwt_required()
def get_all_contributions():
    user_id = int(get_jwt_identity())
    tz      = current_user_tz()
    today   = now_in(tz)
    month   = request.args.get("month", today.month, type=int)
    year    = request.args.get("year",  today.year,  type=int)
    period_start, period_end = month_range_utc(year, month, tz)
    contributions = GoalContribution.query.filter(
        GoalContribution.user_id == user_id,
        GoalContribution.date_added >= period_start,
        GoalContribution.date_added <  period_end,
    ).order_by(GoalContribution.date_added.desc()).all()
    result = []
    for c in contributions:
        d = c.to_dict()
        d["goal_name"] = c.goal.name if c.goal else "Unknown Goal"
        result.append(d)
    return success({"contributions": result})


# ═══════════════════════════════════════════════════════════════════════════════
# ANALYSIS
# ═══════════════════════════════════════════════════════════════════════════════

@api.route("/analyze", methods=["POST"])
@jwt_required()
def analyze():
    user_id = int(get_jwt_identity())
    data    = body()
    today   = now_in(current_user_tz())
    month   = data.get("month", today.month)
    year    = data.get("year",  today.year)
    payload = compute_analysis_payload(user_id, month, year)
    result  = run_analysis(payload)
    auto_notify_status = None
    if result.get("is_urgent"):
        guardian = get_guardian(user_id)
        if guardian and can_auto_notify(guardian):
            user        = User.query.get(user_id)
            report_text = build_guardian_report(user.username, result, payload)
            dispatch_result = dispatch(guardian.phone_number, report_text)
            if dispatch_result["success"]:
                save_report(user_id, report_text, result["score"], trigger="auto")
            auto_notify_status = dispatch_result
    return success({
        "period":              payload["period"],
        "score":               result["score"],
        "category":            result["category"],
        "persona":             result["persona"],
        "projection":          result["projection"],
        "advice":              result["advice"],
        "is_urgent":           result["is_urgent"],
        "savings":             payload["savings"],
        "balance":             payload["balance"],
        "total_contributions": payload["total_contributions"],
        "income":              payload["income"],
        "expenses":            payload["expenses"],
        "savings_rate":        payload["savings_rate"],
        "expense_rate":        payload["expense_rate"],
        "daily_budget":        payload["daily_budget"],
        "goal_health":         payload["goal_health"],
        "category_variance":   payload["category_variance"],
        "auto_notify":         auto_notify_status,

        # The dashboard has always rendered a trend icon and label from
        # spending_trend, but the response never carried it, so it silently
        # showed "stable" for everyone. These are the engine's own facts, now
        # exposed so the app can show what the score was actually based on.
        "has_income":            payload["has_income"],
        "spending_trend":        payload["spending_trend"],
        "projected_spend_rate":  payload["projected_spend_rate"],
        "emergency_fund_months": payload["emergency_fund_months"],
        "overspent_days":        payload["overspent_days"],
        "overspending_streak":   payload["overspending_streak"],
        "goal_progress":         payload["goal_progress"],
        "goal_pace_ratio":       payload["goal_pace_ratio"],
        "day_of_month":          payload["day_of_month"],
    })


# ═══════════════════════════════════════════════════════════════════════════════
# GUARDIAN
# ═══════════════════════════════════════════════════════════════════════════════

@api.route("/guardian/link", methods=["POST"])
@jwt_required()
def guardian_link():
    user_id      = int(get_jwt_identity())
    data         = body()
    phone_number = data.get("phone_number", "").strip()
    if not phone_number:
        return error("Phone number is required.")
    guardian = link_guardian(user_id, phone_number)
    return success({"message": "Guardian linked.", "guardian": guardian.to_dict()}, 201)


@api.route("/guardian/status", methods=["GET"])
@jwt_required()
def guardian_status():
    user_id  = int(get_jwt_identity())
    guardian = get_guardian(user_id)
    if not guardian:
        return success({"linked": False, "guardian": None})
    return success({"linked": True, "guardian": guardian.to_dict()})


@api.route("/guardian/unlink", methods=["DELETE"])
@jwt_required()
def guardian_unlink():
    user_id = int(get_jwt_identity())
    removed = unlink_guardian(user_id)
    if not removed:
        return error("No active guardian found.", 404)
    return success({"message": "Guardian unlinked."})


@api.route("/guardian/notify", methods=["POST"])
@jwt_required()
def guardian_notify():
    user_id  = int(get_jwt_identity())
    guardian = get_guardian(user_id)
    if not guardian:
        return error("No active guardian linked.", 404)
    data  = body()
    today = now_in(current_user_tz())
    month = data.get("month", today.month)
    year  = data.get("year",  today.year)
    payload     = compute_analysis_payload(user_id, month, year)
    result      = run_analysis(payload)
    user        = User.query.get(user_id)
    report_text = build_guardian_report(user.username, result, payload)
    dispatch_result = dispatch(guardian.phone_number, report_text)
    if dispatch_result["success"]:
        save_report(user_id, report_text, result["score"], trigger="manual")
        return success({"message": "Guardian notified.", "channel": dispatch_result.get("channel"), "report": report_text})
    return error(f"Notification failed: {dispatch_result.get('error')}", 502)


@api.route("/guardian/report", methods=["GET"])
@jwt_required()
def guardian_report():
    user_id = int(get_jwt_identity())
    report  = get_latest_report(user_id)
    if not report:
        return success({"report": None, "message": "No reports sent yet."})
    return success({"report": report.to_dict()})


# ═══════════════════════════════════════════════════════════════════════════════
# HELB SEMESTER PLANNER
# ═══════════════════════════════════════════════════════════════════════════════

@api.route("/helb/plan", methods=["GET"])
@jwt_required()
def get_helb_plan():
    user_id = int(get_jwt_identity())
    plan    = HelbPlan.query.filter_by(user_id=user_id).first()
    return success({"plan": plan.to_dict() if plan else None})


@api.route("/helb/plan", methods=["POST"])
@jwt_required()
def save_helb_plan():
    user_id       = int(get_jwt_identity())
    data          = body()
    semester_name = data.get("semester_name", "").strip()
    helb_amount   = positive_amount(data.get("helb_amount"))
    start_date_s  = data.get("start_date")
    end_date_s    = data.get("end_date")
    allocations   = data.get("allocations", {})
    if not semester_name:
        return error("Semester name is required.")
    if helb_amount is None:
        return error("A valid HELB amount is required.")
    if not start_date_s or not end_date_s:
        return error("Start date and end date are required.")
    try:
        start_date = datetime.strptime(start_date_s, "%Y-%m-%d").date()
        end_date   = datetime.strptime(end_date_s,   "%Y-%m-%d").date()
    except ValueError:
        return error("Invalid date format. Use YYYY-MM-DD.")
    if end_date <= start_date:
        return error("End date must be after start date.")
    plan = HelbPlan.query.filter_by(user_id=user_id).first()
    if plan:
        plan.semester_name = semester_name
        plan.helb_amount   = helb_amount
        plan.start_date    = start_date
        plan.end_date      = end_date
        plan.allocations   = _json.dumps(allocations)
        plan.updated_at    = utc_now()
    else:
        plan = HelbPlan(user_id=user_id, semester_name=semester_name,
                        helb_amount=helb_amount, start_date=start_date,
                        end_date=end_date, allocations=_json.dumps(allocations))
        db.session.add(plan)
    db.session.commit()
    return success({"message": "Plan saved.", "plan": plan.to_dict()}, 201)


@api.route("/helb/plan", methods=["DELETE"])
@jwt_required()
def delete_helb_plan():
    user_id = int(get_jwt_identity())
    plan    = HelbPlan.query.filter_by(user_id=user_id).first()
    if not plan:
        return error("No HELB plan found.", 404)
    db.session.delete(plan)
    db.session.commit()
    return success({"message": "Plan deleted."})