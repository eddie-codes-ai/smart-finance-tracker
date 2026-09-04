import calendar
from collections import defaultdict
from datetime import datetime, date

from sqlalchemy import func

from app_time import (local_date_of, month_range_utc, now_in, resolve_timezone,
                      today_in)
from models import db, User, Income, Expense, Budget, SavingsGoal, GoalContribution


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
        extra fields returned to Flutter (savings, balance, daily_budget, etc.)
    """
    # Every calendar question below - which month, which day - is asked in the
    # user's own home zone, so two users in different countries get different
    # (and individually correct) answers from the same rows.
    owner = User.query.get(user_id)
    tz    = resolve_timezone(owner.timezone if owner else None)

    now   = now_in(tz)
    month = month or now.month
    year  = year  or now.year

    # ── Fetch records for the requested period ────────────────────────────────
    period_start, period_end = month_range_utc(year, month, tz)

    income_records = Income.query.filter(
        Income.user_id == user_id,
        Income.date_added >= period_start,
        Income.date_added <  period_end,
    ).all()

    expense_records = Expense.query.filter(
        Expense.user_id == user_id,
        Expense.date_added >= period_start,
        Expense.date_added <  period_end,
    ).all()

    budget_records = Budget.query.filter(
        Budget.user_id    == user_id,
        Budget.month_year == f"{year}-{month:02d}",
    ).all()

    # Active savings goals only
    goals        = SavingsGoal.query.filter_by(user_id=user_id, is_active=True).all()
    primary_goal = goals[0] if goals else None

    # ── Totals ────────────────────────────────────────────────────────────────
    total_income = sum(r.amount for r in income_records)

    # Exclude one-time expenses from regular spending calculations
    regular_expenses = [e for e in expense_records if e.expense_type != "one-time"]
    total_expenses   = sum(e.amount for e in regular_expenses)

    savings = total_income - total_expenses

    # ── Goal contributions ────────────────────────────────────────────────────
    # Total contributed toward the primary goal (used for goal progress)
    primary_goal_contributed = 0.0
    if primary_goal:
        primary_goal_contributed = sum(
            c.amount for c in GoalContribution.query.filter_by(goal_id=primary_goal.id).all()
        )

    # Total contributions across ALL active goals (reduces available balance)
    total_contributions = 0.0
    for goal in goals:
        total_contributions += sum(
            c.amount for c in GoalContribution.query.filter_by(goal_id=goal.id).all()
        )

    # Balance = what the student actually has free after expenses AND goal commitments
    balance = savings - total_contributions

    # ── Core rates ────────────────────────────────────────────────────────────
    # Zero means zero. These used to fall back to 0.01 so Experta always had a
    # non-zero number, which meant a user with no income was scored as saving
    # 0.01% of it - hence "CRITICAL: saving less than 2% of your income" for
    # someone with no income at all. has_income now carries that distinction.
    has_income   = total_income > 0
    savings_rate = (savings / total_income * 100)        if has_income else 0.0
    expense_rate = (total_expenses / total_income * 100) if has_income else 0.0

    # ── Daily budget ──────────────────────────────────────────────────────────
    monthly_income = next((r.amount for r in income_records if r.income_type == "monthly"), None)
    daily_budget   = (monthly_income / 30) if monthly_income else (total_income / 30) if total_income else 0

    # ── Overspending ──────────────────────────────────────────────────────────
    overspent_days      = _calculate_overspent_days(regular_expenses, daily_budget, tz)
    overspending_streak = _calculate_overspending_streak(regular_expenses, daily_budget, tz)

    # ── Luxury spending ───────────────────────────────────────────────────────
    luxury_spending_ratio = _calculate_luxury_spending_ratio(regular_expenses)

    # ── Emergency fund ────────────────────────────────────────────────────────
    # Months of typical spending covered by everything saved to date. The old
    # "emergency buffer" was (income - expenses) / income, i.e. the savings rate
    # under another name, so the buffer rules were re-punishing a number the
    # savings rules had already punished.
    emergency_fund_months = _calculate_emergency_fund_months(user_id, total_expenses)

    # ── Goal progress — uses contributions, not net savings ───────────────────
    goal_progress   = _calculate_goal_progress(primary_goal, primary_goal_contributed)
    goal_pace_ratio = _calculate_goal_pace_ratio(primary_goal, primary_goal_contributed, tz)
    goal_health     = _evaluate_goal_health(primary_goal, primary_goal_contributed, tz)

    # ── Spending pace ─────────────────────────────────────────────────────────
    days_in_month    = _days_in_month(year, month)
    day_of_month     = now.day if (month == now.month and year == now.year) else days_in_month
    projected_spend_rate = _calculate_projected_spend_rate(
        total_expenses, total_income, day_of_month, days_in_month)

    # ── Trend detection — compare with previous month ─────────────────────────
    prev_month, prev_year = (month - 1, year) if month > 1 else (12, year - 1)

    prev_start, prev_end = month_range_utc(prev_year, prev_month, tz)

    prev_income_records = Income.query.filter(
        Income.user_id == user_id,
        Income.date_added >= prev_start,
        Income.date_added <  prev_end,
    ).all()

    prev_expense_records = Expense.query.filter(
        Expense.user_id == user_id,
        Expense.date_added >= prev_start,
        Expense.date_added <  prev_end,
        Expense.expense_type != "one-time",
    ).all()

    prev_income   = sum(r.amount for r in prev_income_records)
    prev_expenses = sum(e.amount for e in prev_expense_records)
    prev_savings  = prev_income - prev_expenses if prev_income_records else None
    prev_luxury   = _calculate_luxury_spending_ratio(prev_expense_records) if prev_expense_records else None

    spending_trend        = _detect_spending_trend(prev_savings, savings)
    luxury_expense_growth = _detect_luxury_expense_growth(prev_luxury, luxury_spending_ratio)

    # ── Goal achievement streak ───────────────────────────────────────────────
    goal_achievement_streak = _calculate_goal_achievement_streak(user_id, primary_goal, tz)

    # ── Budget variance per category ──────────────────────────────────────────
    budgets_dict    = {b.category: b.limit for b in budget_records}
    category_totals = defaultdict(float)
    for e in regular_expenses:
        category_totals[e.category] += e.amount
    category_variance = _calculate_category_variance(category_totals, budgets_dict)

    # Budget adherence, straight off the variance already computed - no extra
    # queries. Until now the entire budget feature had no effect on the score.
    budgets_set, budget_overspend_ratio, budgets_breached = \
        _summarise_budget_adherence(category_variance)

    # Is the goal even reachable? Distinct from pace: an impossible target is
    # permanently "behind", and telling the student to contribute more is
    # useless advice.
    goal_required_share = _calculate_goal_required_share(
        primary_goal, primary_goal_contributed, total_income, tz)
    goal_is_realistic = goal_required_share <= 0.75

    return {
        # ── Engine fields (go into knowledge_engine.run_analysis) ─────────────
        "has_income":                has_income,
        "income":                    total_income,
        "expenses":                  total_expenses,
        "savings_rate":              round(savings_rate, 2),
        "expense_rate":              round(expense_rate, 2),
        "projected_spend_rate":      round(projected_spend_rate, 2),
        "emergency_fund_months":     round(emergency_fund_months, 2),
        "overspent_days":            overspent_days,
        "overspending_streak":       overspending_streak,
        "luxury_spending_ratio":     round(luxury_spending_ratio, 2),
        "luxury_expense_growth":     luxury_expense_growth,
        "budgets_set":               budgets_set,
        "budget_overspend_ratio":    round(budget_overspend_ratio, 3),
        "budgets_breached":          budgets_breached,
        "goal_set":                  primary_goal is not None,
        "goal_progress":             round(goal_progress, 2),
        "goal_pace_ratio":           round(goal_pace_ratio, 3),
        "goal_required_share":       round(goal_required_share, 3),
        "goal_is_realistic":         goal_is_realistic,
        "goal_achievement_streak":   goal_achievement_streak,
        "day_of_month":              day_of_month,
        "spending_trend":            spending_trend,

        # ── Extra fields returned to Flutter alongside engine results ──────────
        "savings":                   round(savings, 2),
        "balance":                   round(balance, 2),
        "total_contributions":       round(total_contributions, 2),
        "daily_budget":              round(daily_budget, 2),
        "goal_health":               goal_health,
        "category_variance":         category_variance,
        "period":                    f"{year}-{month:02d}",
    }


# ─── Private helpers ──────────────────────────────────────────────────────────

def _calculate_overspent_days(expenses: list, daily_budget: float, tz) -> int:
    """Count days where total spending exceeded the daily budget."""
    if daily_budget <= 0:
        return 0
    # Bucket by LOCAL day: an expense at 01:00 EAT is stored as 22:00 UTC the
    # previous day, and grouping on the raw UTC date files it against the wrong
    # day, skewing the overspending penalties.
    daily_totals = defaultdict(float)
    for e in expenses:
        daily_totals[local_date_of(e.date_added, tz)] += e.amount
    return sum(1 for total in daily_totals.values() if total > daily_budget)


def _calculate_overspending_streak(expenses: list, daily_budget: float, tz) -> int:
    """Longest run of consecutive days where spending exceeded daily budget."""
    if daily_budget <= 0:
        return 0
    daily_totals = defaultdict(float)
    for e in expenses:
        daily_totals[local_date_of(e.date_added, tz)] += e.amount

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


def _days_in_month(year: int, month: int) -> int:
    return calendar.monthrange(year, month)[1]


def _calculate_emergency_fund_months(user_id: int, current_expenses: float) -> float:
    """
    How many months of typical spending everything saved to date would cover.

    This replaces the old "emergency buffer", which was
    (income - expenses) / income - the savings rate wearing a different name,
    so the buffer rules simply re-punished the savings rules' finding.

    A real emergency fund is cumulative: a student can save nothing this month
    and still be three months deep from earlier ones. Two aggregate queries
    rather than a loop over history.
    """
    lifetime_income = db.session.query(
        func.coalesce(func.sum(Income.amount), 0.0)
    ).filter(Income.user_id == user_id).scalar() or 0.0

    lifetime_spend = db.session.query(
        func.coalesce(func.sum(Expense.amount), 0.0)
    ).filter(
        Expense.user_id == user_id,
        Expense.expense_type != "one-time",
    ).scalar() or 0.0

    surplus = lifetime_income - lifetime_spend
    if surplus <= 0:
        return 0.0

    # Compare against a typical month rather than this one, so a quiet month
    # does not make the fund look enormous.
    months_active = db.session.query(
        func.count(func.distinct(func.strftime("%Y-%m", Expense.date_added)))
    ).filter(Expense.user_id == user_id).scalar() or 0

    if months_active > 0:
        typical_monthly_spend = lifetime_spend / months_active
    else:
        typical_monthly_spend = current_expenses

    if typical_monthly_spend <= 0:
        return 0.0
    return surplus / typical_monthly_spend


def _calculate_projected_spend_rate(total_expenses: float, total_income: float,
                                    day_of_month: int, days_in_month: int) -> float:
    """
    Month-end spending projected from the pace so far, as a % of income.

    The old salary_burn_rate reduced to 3000 / days_so_far - entirely
    independent of how much had actually been spent, so no rule could usefully
    read it (and none did). This measures rate rather than total, which is what
    makes it independent of the savings rate: spending 40% of income in three
    days projects well past 100% by month-end and is worth flagging on day 3.
    """
    if total_income <= 0 or day_of_month <= 0:
        return 0.0
    # Extrapolating a month from two or three days produces wild numbers - one
    # ordinary shop on day 2 projects to several times the month's income. The
    # rules ignore the projection before day 5 for that reason, and returning
    # 0.0 here keeps the same noise out of anything else that reads the field.
    if day_of_month < 5:
        return 0.0
    daily_rate = total_expenses / day_of_month
    projected  = daily_rate * days_in_month
    return (projected / total_income) * 100


def _calculate_goal_pace_ratio(goal, contributed: float, tz) -> float:
    """
    Contributed divided by what the deadline implies by now. 1.0 is on pace.

    The rules previously judged absolute progress, so a goal created yesterday
    sat at "less than 10% achieved" and cost 30 points - which is how a student
    saving 70% of their income came to be labelled an Overspender. The pacing
    maths already existed in _evaluate_goal_health; this exposes it as a fact.
    """
    if not goal or goal.goal_amount <= 0:
        return 1.0

    total_days  = (goal.due_date - goal.date_set.date()).days
    days_passed = (today_in(tz) - goal.date_set.date()).days
    if total_days <= 0:
        return 1.0
    if days_passed <= 0:
        # Nothing is expected yet, so nobody is behind.
        return 1.0

    expected = goal.goal_amount * (min(days_passed, total_days) / total_days)
    if expected <= 0:
        return 1.0
    return contributed / expected


def _calculate_goal_progress(goal: SavingsGoal, contributed: float) -> float:
    """Percentage of savings goal achieved based on contributions."""
    if not goal:
        return 0.0
    return min((contributed / goal.goal_amount) * 100, 150.0)


def _evaluate_goal_health(goal: SavingsGoal, contributed: float, tz) -> str:
    """Human-readable goal tracking status based on contributions."""
    if not goal:
        return "No savings goal set."

    today       = today_in(tz)
    total_days  = (goal.due_date - goal.date_set.date()).days
    days_passed = (today - goal.date_set.date()).days

    if total_days <= 0:
        return "Invalid goal dates."

    expected_by_now = (goal.goal_amount / total_days) * days_passed

    if contributed >= goal.goal_amount:
        return "Goal already achieved! Congratulations!"

    if expected_by_now <= 0:
        if contributed > 0:
            pct = (contributed / goal.goal_amount) * 100
            return f"Great start! You've already saved {pct:.1f}% of your goal."
        return "Goal period has just started. Start saving to meet your target!"

    if contributed >= expected_by_now:
        return "On track to meet your goal. Keep it up!"

    gap = expected_by_now - contributed
    if gap <= 0.10 * goal.goal_amount:
        return "Slightly behind your goal. Minor adjustment needed."
    elif gap <= 0.30 * goal.goal_amount:
        return "Warning: You are behind on your savings goal. Consider saving more aggressively."
    else:
        return "Critical: You are far behind on your goal. Immediate action required to catch up!"


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


def _calculate_goal_achievement_streak(user_id: int, goal: SavingsGoal, tz) -> int:
    """
    Count consecutive months where contributions met or exceeded
    the expected goal progress for that point in time.
    Looks back up to 12 months.
    """
    if not goal:
        return 0

    streak = 0
    now    = now_in(tz)

    for i in range(1, 13):
        m = now.month - i
        y = now.year
        while m <= 0:
            m += 12
            y -= 1

        streak_start, streak_end = month_range_utc(y, m, tz)
        inc = Income.query.filter(
            Income.user_id == user_id,
            Income.date_added >= streak_start,
            Income.date_added <  streak_end,
        ).all()

        if not inc:
            break

        # Contributions up to end of that month
        period_end = datetime(y, m, 28, 23, 59, 59)
        contributed_so_far = sum(
            c.amount for c in GoalContribution.query.filter(
                GoalContribution.goal_id == goal.id,
                GoalContribution.date_added <= period_end,
            ).all()
        )

        period_date = date(y, m, 28)
        total_days  = (goal.due_date - goal.date_set.date()).days
        days_passed = (period_date - goal.date_set.date()).days

        if total_days <= 0 or days_passed <= 0:
            break

        expected = (goal.goal_amount / total_days) * days_passed
        if contributed_so_far >= expected:
            streak += 1
        else:
            break

    return streak


def _summarise_budget_adherence(category_variance: dict):
    """
    (how many budgets, spent / budgeted, how many breached).

    Measures the limits the student chose, which is a different promise from
    the daily-discipline family: that one checks income/30, a figure the app
    derives. Someone can stay under that average every day and still break
    every category budget.

    Only the ratio is scored. The breach count shapes the advice wording, and
    is deliberately not penalised - count and magnitude move together, so
    charging for both would repeat the double-counting this engine was fixed
    for.
    """
    if not category_variance:
        return 0, 0.0, 0

    total_budgeted = sum(v["budget"] for v in category_variance.values())
    total_spent    = sum(v["spent"] for v in category_variance.values())
    breached       = sum(1 for v in category_variance.values() if v["status"] == "over")

    if total_budgeted <= 0:
        return len(category_variance), 0.0, breached
    return len(category_variance), total_spent / total_budgeted, breached


def _calculate_goal_required_share(goal, contributed: float, monthly_income: float,
                                   tz) -> float:
    """
    The monthly contribution the deadline demands, as a share of income.

    0.0 when there is no goal, nothing left to save, or no income to measure
    against - in each case there is nothing to judge as unrealistic.
    """
    if not goal or monthly_income <= 0:
        return 0.0

    remaining = goal.goal_amount - contributed
    if remaining <= 0:
        return 0.0            # already funded

    days_left = (goal.due_date - today_in(tz)).days
    # An overdue or same-day deadline demands the whole remainder at once.
    months_left = max(days_left, 1) / 30.0
    required_per_month = remaining / months_left
    return required_per_month / monthly_income


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