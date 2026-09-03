import json as _json
import os
import random
import secrets
from datetime import datetime, timedelta
from typing import Optional

from flask import Blueprint, request, jsonify
from flask_jwt_extended import create_access_token, jwt_required, get_jwt_identity
from sqlalchemy import extract

from models import (db, User, Income, Expense, Budget, SavingsGoal,
                    GoalContribution, HelbPlan, UserCategory, UserIncomeType,
                    DEFAULT_EXPENSE_CATEGORIES, DEFAULT_INCOME_TYPES,
                    DELETION_GRACE_HOURS)
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

MIN_PASSWORD_LENGTH = 6

def password_problem(password: str) -> Optional[str]:
    """Return an error message if the password is unacceptable, else None."""
    if not password:
        return "Password is required."
    if len(password) < MIN_PASSWORD_LENGTH:
        return f"Password must be at least {MIN_PASSWORD_LENGTH} characters long."
    return None

def _verify_google_token(id_token_str: str) -> Optional[dict]:
    google_client_id = os.environ.get("GOOGLE_CLIENT_ID")
    if not google_client_id:
        return None
    try:
        from google.oauth2 import id_token as g_id_token
        from google.auth.transport import requests as g_requests
        idinfo = g_id_token.verify_oauth2_token(id_token_str, g_requests.Request(), google_client_id)
        return {"google_id": idinfo["sub"], "email": idinfo.get("email", ""), "name": idinfo.get("name", "")}
    except Exception:
        return None


def _purge_expired_deletions():
    cutoff = datetime.utcnow() - timedelta(hours=DELETION_GRACE_HOURS)
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
    data     = request.get_json()
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
    user.set_password(password)
    db.session.add(user)
    db.session.commit()
    token = create_access_token(identity=str(user.id))
    return success({"message": "Account created.", "token": token, "user": user.to_dict()}, 201)


@api.route("/auth/login", methods=["POST"])
def login():
    _purge_expired_deletions()
    data     = request.get_json()
    username = data.get("username", "").strip()
    password = data.get("password", "")
    user = User.query.filter_by(username=username).first()
    if not user or not user.check_password(password):
        return error("Invalid username or password.", 401)
    token = create_access_token(identity=str(user.id))
    return success({
        "token":            token,
        "user":             user.to_dict(),
        "pending_deletion": user.is_pending_deletion,
        "deletion_due_at":  user.deletion_due_at.isoformat() if user.deletion_due_at else None,
    })


@api.route("/auth/google", methods=["POST"])
def google_signin():
    data         = request.get_json()
    id_token_str = data.get("id_token", "").strip()
    if not id_token_str:
        return error("Google ID token is required.")
    google_info = _verify_google_token(id_token_str)
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
    token = create_access_token(identity=str(user.id))
    return success({"token": token, "user": user.to_dict()})


@api.route("/auth/forgot-password", methods=["POST"])
def forgot_password():
    data  = request.get_json()
    email = data.get("email", "").strip().lower()
    if not email:
        return error("Email address is required.")
    user = User.query.filter_by(email=email).first()
    if user:
        code                    = f"{random.randint(0, 999999):06d}"
        user.reset_token        = code
        user.reset_token_expiry = datetime.utcnow() + timedelta(minutes=60)
        db.session.commit()
        send_reset_email(email, user.username, code)
    return success({"message": "If that email is registered, a reset code has been sent. Check your inbox and spam folder."})


@api.route("/auth/reset-password", methods=["POST"])
def reset_password_endpoint():
    data         = request.get_json()
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
    if user.reset_token != code:
        return error("Incorrect reset code.", 400)
    if user.reset_token_expiry < datetime.utcnow():
        return error("Reset code has expired. Please request a new one.", 400)
    user.set_password(new_password)
    user.reset_token        = None
    user.reset_token_expiry = None
    db.session.commit()
    return success({"message": "Password reset successfully. You can now log in with your new password."})


@api.route("/auth/profile", methods=["PUT"])
@jwt_required()
def update_profile():
    user_id          = int(get_jwt_identity())
    user             = User.query.get(user_id)
    data             = request.get_json() or {}
    new_username     = data.get("username", "").strip() or None
    new_email        = data.get("email", "").strip().lower() or None
    new_password     = data.get("new_password", "") or None
    current_password = data.get("current_password", "") or None
    if not any([new_username, new_email, new_password]):
        return error("No changes provided.")
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
    db.session.commit()
    return success({"message": "Profile updated successfully.", "user": user.to_dict()})


@api.route("/auth/account", methods=["DELETE"])
@jwt_required()
def request_account_deletion():
    user_id  = int(get_jwt_identity())
    user     = User.query.get(user_id)
    data     = request.get_json() or {}
    password = data.get("password", "")
    if not password:
        return error("Password is required to delete your account.")
    if not user.check_password(password):
        return error("Incorrect password.", 401)
    if user.is_pending_deletion:
        return error("Account deletion is already scheduled.", 400)
    user.deletion_requested_at = datetime.utcnow()
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
    data    = request.get_json()
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
    data    = request.get_json()
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
    data    = request.get_json()
    amount      = data.get("amount")
    income_type = data.get("income_type", "monthly")
    description = data.get("description", "")
    if not amount or float(amount) <= 0:
        return error("A valid amount is required.")
    income = Income(user_id=user_id, amount=float(amount), income_type=income_type, description=description)
    db.session.add(income)
    db.session.commit()
    return success({"message": "Income added.", "income": income.to_dict()}, 201)


@api.route("/income", methods=["GET"])
@jwt_required()
def get_income():
    user_id = int(get_jwt_identity())
    month   = request.args.get("month", datetime.utcnow().month, type=int)
    year    = request.args.get("year",  datetime.utcnow().year,  type=int)
    records = Income.query.filter(
        Income.user_id == user_id,
        extract("month", Income.date_added) == month,
        extract("year",  Income.date_added) == year,
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


# ═══════════════════════════════════════════════════════════════════════════════
# EXPENSES
# ═══════════════════════════════════════════════════════════════════════════════

@api.route("/expenses", methods=["POST"])
@jwt_required()
def add_expense():
    user_id = int(get_jwt_identity())
    data    = request.get_json()
    amount              = data.get("amount")
    category            = data.get("category", "Other")
    description         = data.get("description", "")
    expense_type        = data.get("expense_type", "daily")
    recurrence_interval = data.get("recurrence_interval", None)
    if not amount or float(amount) <= 0:
        return error("A valid amount is required.")
    expense = Expense(user_id=user_id, amount=float(amount), category=category,
                      description=description, expense_type=expense_type,
                      recurrence_interval=recurrence_interval)
    db.session.add(expense)
    db.session.commit()
    return success({"message": "Expense added.", "expense": expense.to_dict()}, 201)


@api.route("/expenses", methods=["GET"])
@jwt_required()
def get_expenses():
    user_id = int(get_jwt_identity())
    month   = request.args.get("month", datetime.utcnow().month, type=int)
    year    = request.args.get("year",  datetime.utcnow().year,  type=int)
    records = Expense.query.filter(
        Expense.user_id == user_id,
        extract("month", Expense.date_added) == month,
        extract("year",  Expense.date_added) == year,
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


# ═══════════════════════════════════════════════════════════════════════════════
# BUDGETS
# ═══════════════════════════════════════════════════════════════════════════════

@api.route("/budgets", methods=["POST"])
@jwt_required()
def set_budget():
    user_id    = int(get_jwt_identity())
    data       = request.get_json()
    category   = data.get("category")
    limit      = data.get("limit")
    month_year = data.get("month_year", datetime.utcnow().strftime("%Y-%m"))
    if not category or not limit or float(limit) <= 0:
        return error("Category and a valid limit are required.")
    existing = Budget.query.filter_by(user_id=user_id, category=category, month_year=month_year).first()
    if existing:
        existing.limit = float(limit)
    else:
        db.session.add(Budget(user_id=user_id, category=category, limit=float(limit), month_year=month_year))
    db.session.commit()
    return success({"message": "Budget saved."}, 201)


@api.route("/budgets", methods=["GET"])
@jwt_required()
def get_budgets():
    user_id    = int(get_jwt_identity())
    month_year = request.args.get("month_year", datetime.utcnow().strftime("%Y-%m"))
    records    = Budget.query.filter_by(user_id=user_id, month_year=month_year).all()
    return success({"budgets": [r.to_dict() for r in records]})


# ═══════════════════════════════════════════════════════════════════════════════
# SAVINGS GOALS
# ═══════════════════════════════════════════════════════════════════════════════

@api.route("/goals", methods=["POST"])
@jwt_required()
def add_goal():
    user_id      = int(get_jwt_identity())
    data         = request.get_json()
    name         = data.get("name", "My Goal")
    goal_amount  = data.get("goal_amount")
    due_date_str = data.get("due_date")
    if not goal_amount or float(goal_amount) <= 0:
        return error("A valid goal amount is required.")
    if not due_date_str:
        return error("A due date is required.")
    try:
        due_date = datetime.strptime(due_date_str, "%Y-%m-%d").date()
    except ValueError:
        return error("Invalid due_date format. Use YYYY-MM-DD.")
    goal = SavingsGoal(user_id=user_id, name=name, goal_amount=float(goal_amount), due_date=due_date)
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
    data   = request.get_json()
    amount = data.get("amount")
    note   = data.get("note", "").strip() or None
    if not amount or float(amount) <= 0:
        return error("A valid amount is required.")
    contribution = GoalContribution(goal_id=goal_id, user_id=user_id, amount=float(amount), note=note)
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
    month   = request.args.get("month", datetime.utcnow().month, type=int)
    year    = request.args.get("year",  datetime.utcnow().year,  type=int)
    contributions = GoalContribution.query.filter(
        GoalContribution.user_id == user_id,
        extract("month", GoalContribution.date_added) == month,
        extract("year",  GoalContribution.date_added) == year,
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
    data    = request.get_json() or {}
    month   = data.get("month", datetime.utcnow().month)
    year    = data.get("year",  datetime.utcnow().year)
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
    })


# ═══════════════════════════════════════════════════════════════════════════════
# GUARDIAN
# ═══════════════════════════════════════════════════════════════════════════════

@api.route("/guardian/link", methods=["POST"])
@jwt_required()
def guardian_link():
    user_id      = int(get_jwt_identity())
    data         = request.get_json()
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
    data  = request.get_json() or {}
    month = data.get("month", datetime.utcnow().month)
    year  = data.get("year",  datetime.utcnow().year)
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
    data          = request.get_json()
    semester_name = data.get("semester_name", "").strip()
    helb_amount   = data.get("helb_amount")
    start_date_s  = data.get("start_date")
    end_date_s    = data.get("end_date")
    allocations   = data.get("allocations", {})
    if not semester_name:
        return error("Semester name is required.")
    if not helb_amount or float(helb_amount) <= 0:
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
        plan.helb_amount   = float(helb_amount)
        plan.start_date    = start_date
        plan.end_date      = end_date
        plan.allocations   = _json.dumps(allocations)
        plan.updated_at    = datetime.utcnow()
    else:
        plan = HelbPlan(user_id=user_id, semester_name=semester_name,
                        helb_amount=float(helb_amount), start_date=start_date,
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