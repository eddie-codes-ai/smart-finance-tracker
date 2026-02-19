from collections import defaultdict
from datetime import datetime, date
from sqlalchemy import extract
from models import db, Income, Expense, Budget, SavingsGoal


# Categories treated as luxury / non-essential
LUXURY_CATEGORIES = {"Entertainment", "Shopping", "Other"}


def compute_analysis_payload(user_id: int, month: int = None, year: int = None) -> dict:
    """
    Master function called by the /api/analyze route.

    Pulls all data for the given user and period directly from the DB,
    computes every financial metric, and returns a payload dict ready
    to be passed into knowledge_engine.run_analysis().

    Args:
        user_id: authenticated student's ID
        month:   month to analyze (defaults to current month)
        year:    year to analyze  (defaults to current year)

    Returns:
        dict of all computed fields expected by run_analysis() plus
        extra fields returned to Flutter (savings, daily_budget, etc.)
    """
    now   = datetime.utcnow()
    month = month or now.month
    year  = year  or now.year

    # ── Fetch records for the requested period ────────────────────────────────
    income_records = Income.query.filter(
        Income.user_id == user_id,
        extract("month", Income.date_added) == month,
        extract("year",  Income.date_added) == year,
    ).all()

    expense_records = Expense.query.filter(
        Expense.user_id == user_id,
        extract("month", Expense.date_added) == month,
        extract("year",  Expense.date_added) == year,
    ).all()

    budget_records = Budget.query.filter(
        Budget.user_id    == user_id,
        Budget.month_year == f"{year}-{month:02d}",
    ).all()

    # Active savings goals only
    goals = SavingsGoal.query.filter_by(user_id=user_id, is_active=True).all()
    primary_goal = goals[0] if goals else None

    # ── Totals ────────────────────────────────────────────────────────────────
    total_income = sum(r.amount for r in income_records)

    # Exclude one-time expenses from regular spending calculations
    regular_expenses = [e for e in expense_records if e.expense_type != "one-time"]
    total_expenses   = sum(e.amount for e in regular_expenses)

    savings = total_income - total_expenses

    # ── Core rates ────────────────────────────────────────────────────────────
    savings_rate = (savings / total_income * 100)        if total_income else 0.01
    expense_rate = (total_expenses / total_income * 100) if total_income else 0.01

    # ── Daily budget ──────────────────────────────────────────────────────────
    monthly_income = next((r.amount for r in income_records if r.income_type == "monthly"), None)
    daily_budget   = (monthly_income / 30) if monthly_income else (total_income / 30) if total_income else 0

    # ── Overspending ──────────────────────────────────────────────────────────
    overspent_days      = _calculate_overspent_days(regular_expenses, daily_budget)
    overspending_streak = _calculate_overspending_streak(regular_expenses, daily_budget)

    # ── Luxury spending ───────────────────────────────────────────────────────
    luxury_spending_ratio = _calculate_luxury_spending_ratio(regular_expenses)

    # ── Emergency buffer ──────────────────────────────────────────────────────
    emergency_buffer_present = _check_emergency_buffer(total_income, total_expenses)
    emergency_buffer_amount  = _calculate_emergency_buffer_amount(total_income, total_expenses)

    # ── Goal progress ─────────────────────────────────────────────────────────
    goal_progress = _calculate_goal_progress(primary_goal, savings)
    goal_health   = _evaluate_goal_health(primary_goal, savings)

    # ── Salary burn rate ──────────────────────────────────────────────────────
    day_of_month     = now.day if (month == now.month and year == now.year) else 30
    salary_burn_rate = _calculate_salary_burn_rate(total_expenses, day_of_month)

    # ── Trend detection — compare with previous month ─────────────────────────
    prev_month, prev_year = (month - 1, year) if month > 1 else (12, year - 1)

    prev_income_records = Income.query.filter(
        Income.user_id == user_id,
        extract("month", Income.date_added) == prev_month,
        extract("year",  Income.date_added) == prev_year,
    ).all()

    prev_expense_records = Expense.query.filter(
        Expense.user_id == user_id,
        extract("month", Expense.date_added) == prev_month,
        extract("year",  Expense.date_added) == prev_year,
        Expense.expense_type != "one-time",
    ).all()

    prev_income   = sum(r.amount for r in prev_income_records)
    prev_expenses = sum(e.amount for e in prev_expense_records)
    prev_savings  = prev_income - prev_expenses if prev_income_records else None
    prev_luxury   = _calculate_luxury_spending_ratio(prev_expense_records) if prev_expense_records else None

    spending_trend        = _detect_spending_trend(prev_savings, savings)
    luxury_expense_growth = _detect_luxury_expense_growth(prev_luxury, luxury_spending_ratio)

    # ── Goal achievement streak ───────────────────────────────────────────────
    goal_achievement_streak = _calculate_goal_achievement_streak(user_id, primary_goal)

    # ── Budget variance per category ──────────────────────────────────────────
    budgets_dict    = {b.category: b.limit for b in budget_records}
    category_totals = defaultdict(float)
    for e in regular_expenses:
        category_totals[e.category] += e.amount
    category_variance = _calculate_category_variance(category_totals, budgets_dict)

    return {
        # ── Engine fields (go into knowledge_engine.run_analysis) ─────────────
        "income":                    total_income,
        "expenses":                  total_expenses,
        "savings_rate":              round(savings_rate, 2),
        "expense_rate":              round(expense_rate, 2),
        "overspent_days":            overspent_days,
        "luxury_spending_ratio":     round(luxury_spending_ratio, 2),
        "emergency_buffer_present":  emergency_buffer_present,
        "emergency_buffer_amount":   round(emergency_buffer_amount, 4),
        "goal_progress":             round(goal_progress, 2),
        "day_of_month":              day_of_month,
        "spending_trend":            spending_trend,
        "salary_burn_rate":          round(salary_burn_rate, 2),
        "luxury_expense_growth":     luxury_expense_growth,
        "overspending_streak":       overspending_streak,
        "goal_achievement_streak":   goal_achievement_streak,

        # ── Extra fields returned to Flutter alongside engine results ──────────
        "savings":                   round(savings, 2),
        "daily_budget":              round(daily_budget, 2),
        "goal_health":               goal_health,
        "category_variance":         category_variance,
        "period":                    f"{year}-{month:02d}",
    }


# ─── Private helpers ──────────────────────────────────────────────────────────

def _calculate_overspent_days(expenses: list, daily_budget: float) -> int:
    """Count days where total spending exceeded the daily budget."""
    if daily_budget <= 0:
        return 0
    daily_totals = defaultdict(float)
    for e in expenses:
        day = e.date_added.date()
        daily_totals[day] += e.amount
    return sum(1 for total in daily_totals.values() if total > daily_budget)


def _calculate_overspending_streak(expenses: list, daily_budget: float) -> int:
    """Longest run of consecutive days where spending exceeded daily budget."""
    if daily_budget <= 0:
        return 0
    daily_totals = defaultdict(float)
    for e in expenses:
        daily_totals[e.date_added.date()] += e.amount

    streak = max_streak = 0
    for day in sorted(daily_totals.keys()):
        if daily_totals[day] > daily_budget:
            streak += 1
            max_streak = max(max_streak, streak)
        else:
            streak = 0
    return max_streak


def _calculate_luxury_spending_ratio(expenses: list) -> float:
    """Percentage of expenses that fall in luxury categories."""
    luxury_total = total = 0.0
    for e in expenses:
        total += e.amount
        if e.category in LUXURY_CATEGORIES:
            luxury_total += e.amount
    return (luxury_total / total * 100) if total else 0.0


def _check_emergency_buffer(income: float, expenses: float) -> bool:
    """True if at least 10% of income remains after expenses."""
    return (income - expenses) >= (0.10 * income)


def _calculate_emergency_buffer_amount(income: float, expenses: float) -> float:
    """Buffer remaining as a fraction of income (e.g. 0.15 = 15%)."""
    return ((income - expenses) / income) if income else 0.0


def _calculate_goal_progress(goal: SavingsGoal, savings: float) -> float:
    """Percentage of savings goal achieved."""
    if not goal:
        return 0.0
    return min((savings / goal.goal_amount) * 100, 150.0)


def _evaluate_goal_health(goal: SavingsGoal, savings: float) -> str:
    """Human-readable goal tracking status."""
    if not goal:
        return "No savings goal set."

    today       = datetime.utcnow().date()
    total_days  = (goal.due_date - goal.date_set.date()).days
    days_passed = (today - goal.date_set.date()).days

    if total_days <= 0:
        return "Invalid goal dates."

    expected_by_now = (goal.goal_amount / total_days) * days_passed

    if savings >= goal.goal_amount:
        return "Goal already achieved! Congratulations!"
    if expected_by_now <= 0:
        return "Goal period has not started yet."
    if savings >= expected_by_now:
        return "On track to meet your goal. Keep it up!"

    gap = expected_by_now - savings
    if gap <= 0.10 * goal.goal_amount:
        return "Slightly behind your goal. Minor adjustment needed."
    elif gap <= 0.30 * goal.goal_amount:
        return "Warning: You are behind on your savings goal. Consider saving more aggressively."
    else:
        return "Critical: You are far behind on your goal. Immediate action required to catch up!"


def _calculate_salary_burn_rate(total_expenses: float, day_of_month: int) -> float:
    """Projected monthly spend based on pace so far, as % of current total."""
    if total_expenses == 0 or day_of_month < 1:
        return 0.0
    days_so_far       = min(day_of_month, 15)
    daily_rate        = total_expenses / days_so_far
    projected_monthly = daily_rate * 30
    return round((projected_monthly / total_expenses) * 100, 2)


def _detect_spending_trend(prev_savings: float, current_savings: float) -> str:
    """Compare savings this period vs last to detect trend direction."""
    if prev_savings is None:
        return "stable"
    diff = current_savings - prev_savings
    if diff > 0:
        return "improving"
    elif prev_savings != 0 and diff < -(0.20 * abs(prev_savings)):
        return "worsening_fast"
    elif diff < 0:
        return "worsening_slow"
    return "stable"


def _detect_luxury_expense_growth(prev_luxury: float, current_luxury: float) -> str:
    """Compare luxury ratio this period vs last."""
    if prev_luxury is None:
        return "stable"
    if current_luxury > prev_luxury:
        return "increasing"
    elif current_luxury < prev_luxury:
        return "decreasing"
    return "stable"


def _calculate_goal_achievement_streak(user_id: int, goal: SavingsGoal) -> int:
    """
    Count consecutive months where the student's savings met or
    exceeded the expected goal progress for that point in time.
    Looks back up to 12 months.
    """
    if not goal:
        return 0

    streak = 0
    now    = datetime.utcnow()

    for i in range(1, 13):  # check up to 12 previous months
        m = now.month - i
        y = now.year
        while m <= 0:
            m += 12
            y -= 1

        inc = Income.query.filter(
            Income.user_id == user_id,
            extract("month", Income.date_added) == m,
            extract("year",  Income.date_added) == y,
        ).all()

        exp = Expense.query.filter(
            Expense.user_id == user_id,
            extract("month", Expense.date_added) == m,
            extract("year",  Expense.date_added) == y,
            Expense.expense_type != "one-time",
        ).all()

        if not inc:
            break  # no data for this month, stop counting

        period_income   = sum(r.amount for r in inc)
        period_expenses = sum(e.amount for e in exp)
        period_savings  = period_income - period_expenses

        # Check if savings met the expected pace toward goal
        period_date    = date(y, m, 1)
        total_days     = (goal.due_date - goal.date_set.date()).days
        days_passed    = (period_date - goal.date_set.date()).days

        if total_days <= 0 or days_passed <= 0:
            break

        expected = (goal.goal_amount / total_days) * days_passed
        if period_savings >= expected:
            streak += 1
        else:
            break  # streak broken

    return streak


def _calculate_category_variance(category_totals: dict, budgets: dict) -> dict:
    """For each budgeted category return spent, limit, variance, and status."""
    variance = {}
    for category, limit in budgets.items():
        spent = category_totals.get(category, 0.0)
        limit = float(limit)
        diff  = spent - limit
        pct   = round((spent / limit * 100), 2) if limit else 0.0
        variance[category] = {
            "spent":         round(spent, 2),
            "budget":        round(limit, 2),
            "variance":      round(diff, 2),
            "usage_percent": pct,
            "status":        "over" if diff > 0 else "under",
        }
    return variance