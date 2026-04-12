import json as _json
import os
import random
import secrets
from typing import Optional
from flask import Blueprint, request, jsonify
from flask_jwt_extended import create_access_token, jwt_required, get_jwt_identity
from datetime import datetime, timedelta
from sqlalchemy import extract

from models import db, User, Income, Expense, Budget, SavingsGoal, HelbPlan
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

def _verify_google_token(id_token_str: str) -> Optional[dict]:
    google_client_id = os.environ.get("GOOGLE_CLIENT_ID")
    if not google_client_id:
        return None
    try:
        from google.oauth2 import id_token as g_id_token
        from google.auth.transport import requests as g_requests
        idinfo = g_id_token.verify_oauth2_token(id_token_str, g_requests.Request(), google_client_id)
        return {"google_id": idinfo["sub"], "email": idinfo.get("email",""), "name": idinfo.get("name","")}
    except Exception:
        return None


# ═══════════════════════════════════════════════════════════════════════════════
# AUTH
# ═══════════════════════════════════════════════════════════════════════════════

@api.route("/auth/register", methods=["POST"])
def register():
    data     = request.get_json()
    username = data.get("username", "").strip()
    password = data.get("password", "")
    email    = data.get("email", "").strip().lower() or None
    if not username or not password:
        return error("Username and password are required.")
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
    data     = request.get_json()
    username = data.get("username", "").strip()
    password = data.get("password", "")
    user = User.query.filter_by(username=username).first()
    if not user or not user.check_password(password):
        return error("Invalid username or password.", 401)
    token = create_access_token(identity=str(user.id))
    return success({"token": token, "user": user.to_dict()})


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
        base = (email.split("@")[0] if email else name.replace(" ","").lower()) or "user"
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
        user.reset_token_expiry = datetime.utcnow() + timedelta(minutes=15)
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
    if len(new_password) < 6:
        return error("Password must be at least 6 characters long.")
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
        "period":            payload["period"],
        "score":             result["score"],
        "category":          result["category"],
        "persona":           result["persona"],
        "projection":        result["projection"],
        "advice":            result["advice"],
        "is_urgent":         result["is_urgent"],
        "savings":           payload["savings"],
        "income":            payload["income"],
        "expenses":          payload["expenses"],
        "savings_rate":      payload["savings_rate"],
        "expense_rate":      payload["expense_rate"],
        "daily_budget":      payload["daily_budget"],
        "goal_health":       payload["goal_health"],
        "category_variance": payload["category_variance"],
        "auto_notify":       auto_notify_status,
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
    """GET /api/helb/plan — fetch the student's current semester plan."""
    user_id = int(get_jwt_identity())
    plan    = HelbPlan.query.filter_by(user_id=user_id).first()
    return success({"plan": plan.to_dict() if plan else None})


@api.route("/helb/plan", methods=["POST"])
@jwt_required()
def save_helb_plan():
    """POST /api/helb/plan — create or update semester plan (upsert)."""
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
    """DELETE /api/helb/plan — permanently delete the student's semester plan."""
    user_id = int(get_jwt_identity())
    plan    = HelbPlan.query.filter_by(user_id=user_id).first()
    if not plan:
        return error("No HELB plan found.", 404)
    db.session.delete(plan)
    db.session.commit()
    return success({"message": "Plan deleted."})