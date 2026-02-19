from flask import Blueprint, request, jsonify
from flask_jwt_extended import (
    create_access_token, jwt_required, get_jwt_identity
)
from datetime import datetime
from sqlalchemy import extract

from models import db, User, Income, Expense, Budget, SavingsGoal
from engine.knowledge_engine import run_analysis
from services.analysis_service import compute_analysis_payload
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


# ═══════════════════════════════════════════════════════════════════════════════
# AUTH
# ═══════════════════════════════════════════════════════════════════════════════

@api.route("/auth/register", methods=["POST"])
def register():
    """
    POST /api/auth/register
    Body: { "username": "edwin", "password": "secret" }
    """
    data     = request.get_json()
    username = data.get("username", "").strip()
    password = data.get("password", "")

    if not username or not password:
        return error("Username and password are required.")

    if User.query.filter_by(username=username).first():
        return error("Username already exists.", 409)

    user = User(username=username)
    user.set_password(password)
    db.session.add(user)
    db.session.commit()

    token = create_access_token(identity=str(user.id))
    return success({"message": "Account created.", "token": token, "user": user.to_dict()}, 201)


@api.route("/auth/login", methods=["POST"])
def login():
    """
    POST /api/auth/login
    Body: { "username": "edwin", "password": "secret" }
    """
    data     = request.get_json()
    username = data.get("username", "").strip()
    password = data.get("password", "")

    user = User.query.filter_by(username=username).first()
    if not user or not user.check_password(password):
        return error("Invalid username or password.", 401)

    token = create_access_token(identity=str(user.id))
    return success({"token": token, "user": user.to_dict()})


# ═══════════════════════════════════════════════════════════════════════════════
# INCOME
# ═══════════════════════════════════════════════════════════════════════════════

@api.route("/income", methods=["POST"])
@jwt_required()
def add_income():
    """
    POST /api/income
    Body: { "amount": 15000, "income_type": "monthly", "description": "HELB" }
    """
    user_id = int(get_jwt_identity())
    data    = request.get_json()

    amount      = data.get("amount")
    income_type = data.get("income_type", "monthly")
    description = data.get("description", "")

    if not amount or float(amount) <= 0:
        return error("A valid amount is required.")

    income = Income(
        user_id     = user_id,
        amount      = float(amount),
        income_type = income_type,
        description = description,
    )
    db.session.add(income)
    db.session.commit()
    return success({"message": "Income added.", "income": income.to_dict()}, 201)


@api.route("/income", methods=["GET"])
@jwt_required()
def get_income():
    """
    GET /api/income?month=7&year=2025
    Returns all income records for the given period.
    """
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
    """DELETE /api/income/<id>"""
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
    """
    POST /api/expenses
    Body: {
        "amount": 500, "category": "Food", "description": "Lunch",
        "expense_type": "daily", "recurrence_interval": null
    }
    """
    user_id = int(get_jwt_identity())
    data    = request.get_json()

    amount              = data.get("amount")
    category            = data.get("category", "Other")
    description         = data.get("description", "")
    expense_type        = data.get("expense_type", "daily")
    recurrence_interval = data.get("recurrence_interval", None)

    if not amount or float(amount) <= 0:
        return error("A valid amount is required.")

    expense = Expense(
        user_id             = user_id,
        amount              = float(amount),
        category            = category,
        description         = description,
        expense_type        = expense_type,
        recurrence_interval = recurrence_interval,
    )
    db.session.add(expense)
    db.session.commit()
    return success({"message": "Expense added.", "expense": expense.to_dict()}, 201)


@api.route("/expenses", methods=["GET"])
@jwt_required()
def get_expenses():
    """
    GET /api/expenses?month=7&year=2025
    Returns all expense records for the given period.
    """
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
    """DELETE /api/expenses/<id>"""
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
    """
    POST /api/budgets
    Body: { "category": "Food", "limit": 3000, "month_year": "2025-07" }
    Upserts — updates limit if budget for that category/month already exists.
    """
    user_id    = int(get_jwt_identity())
    data       = request.get_json()
    category   = data.get("category")
    limit      = data.get("limit")
    month_year = data.get("month_year", datetime.utcnow().strftime("%Y-%m"))

    if not category or not limit or float(limit) <= 0:
        return error("Category and a valid limit are required.")

    existing = Budget.query.filter_by(
        user_id=user_id, category=category, month_year=month_year
    ).first()

    if existing:
        existing.limit = float(limit)
    else:
        db.session.add(Budget(
            user_id    = user_id,
            category   = category,
            limit      = float(limit),
            month_year = month_year,
        ))

    db.session.commit()
    return success({"message": "Budget saved."}, 201)


@api.route("/budgets", methods=["GET"])
@jwt_required()
def get_budgets():
    """GET /api/budgets?month_year=2025-07"""
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
    """
    POST /api/goals
    Body: { "name": "Laptop", "goal_amount": 50000, "due_date": "2025-12-01" }
    """
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

    goal = SavingsGoal(
        user_id     = user_id,
        name        = name,
        goal_amount = float(goal_amount),
        due_date    = due_date,
    )
    db.session.add(goal)
    db.session.commit()
    return success({"message": "Goal created.", "goal": goal.to_dict()}, 201)


@api.route("/goals", methods=["GET"])
@jwt_required()
def get_goals():
    """GET /api/goals — returns all active savings goals."""
    user_id = int(get_jwt_identity())
    goals   = SavingsGoal.query.filter_by(user_id=user_id, is_active=True).all()
    return success({"goals": [g.to_dict() for g in goals]})


@api.route("/goals/<int:goal_id>", methods=["DELETE"])
@jwt_required()
def close_goal(goal_id):
    """DELETE /api/goals/<id> — soft-closes a goal."""
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
    """
    POST /api/analyze
    Optional body: { "month": 7, "year": 2025 }
    Defaults to current month/year if not provided.

    Flow:
    1. Pull all records from DB for the period via analysis_service
    2. Run Experta engine via knowledge_engine
    3. If urgent + guardian linked + cooldown passed → auto-notify guardian
    4. Return full results to Flutter
    """
    user_id = int(get_jwt_identity())
    data    = request.get_json() or {}
    month   = data.get("month", datetime.utcnow().month)
    year    = data.get("year",  datetime.utcnow().year)

    # Steps 1 & 2
    payload = compute_analysis_payload(user_id, month, year)
    result  = run_analysis(payload)

    # Step 3 — auto-notify guardian if urgent
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

    # Step 4 — return full results
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
    """
    POST /api/guardian/link
    Body: { "phone_number": "0712345678" }
    """
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
    """GET /api/guardian/status — is a guardian linked?"""
    user_id  = int(get_jwt_identity())
    guardian = get_guardian(user_id)
    if not guardian:
        return success({"linked": False, "guardian": None})
    return success({"linked": True, "guardian": guardian.to_dict()})


@api.route("/guardian/unlink", methods=["DELETE"])
@jwt_required()
def guardian_unlink():
    """DELETE /api/guardian/unlink — soft-deactivate guardian link."""
    user_id = int(get_jwt_identity())
    removed = unlink_guardian(user_id)
    if not removed:
        return error("No active guardian found.", 404)
    return success({"message": "Guardian unlinked."})


@api.route("/guardian/notify", methods=["POST"])
@jwt_required()
def guardian_notify():
    """
    POST /api/guardian/notify
    Manual trigger — student explicitly sends a report to their guardian.
    Optional body: { "month": 7, "year": 2025 }
    No cooldown applies to manual triggers.
    """
    user_id  = int(get_jwt_identity())
    guardian = get_guardian(user_id)

    if not guardian:
        return error("No active guardian linked. Please link a guardian first.", 404)

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
        return success({
            "message": "Guardian notified.",
            "channel": dispatch_result.get("channel"),
            "report":  report_text,
        })

    return error(f"Notification failed: {dispatch_result.get('error')}", 502)


@api.route("/guardian/report", methods=["GET"])
@jwt_required()
def guardian_report():
    """GET /api/guardian/report — fetch the latest guardian report."""
    user_id = int(get_jwt_identity())
    report  = get_latest_report(user_id)
    if not report:
        return success({"report": None, "message": "No reports sent yet."})
    return success({"report": report.to_dict()})