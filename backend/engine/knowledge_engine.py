from engine.facts import FinancialProfile
from engine.rules import FinancialAdvisor


def run_analysis(payload: dict) -> dict:
    """
    Entry point for the expert system.

    Takes the payload computed by analysis_service, declares it as a
    FinancialProfile, runs the rules and returns a result for the API layer.

    Note there is no longer a "no data" short-circuit here. The rules handle an
    empty period themselves, which keeps one set of statements about a user's
    finances in one place instead of two.
    """
    has_income = bool(payload.get("has_income", False))

    advisor = FinancialAdvisor()
    advisor.reset()

    projected = _safe_float(payload.get("projected_spend_rate"))

    advisor.declare(FinancialProfile(
        has_income              = has_income,
        income                  = _safe_float(payload.get("income")),
        expenses                = _safe_float(payload.get("expenses")),
        savings_rate            = _safe_float(payload.get("savings_rate")),
        projected_spend_rate    = projected,
        day_of_month            = _safe_int(payload.get("day_of_month")),
        emergency_fund_months   = _safe_float(payload.get("emergency_fund_months")),
        overspent_days          = _safe_int(payload.get("overspent_days")),
        overspending_streak     = _safe_int(payload.get("overspending_streak")),
        luxury_spending_ratio   = _safe_float(payload.get("luxury_spending_ratio")),
        luxury_expense_growth   = payload.get("luxury_expense_growth", "stable"),
        budgets_set             = _safe_int(payload.get("budgets_set")),
        budget_overspend_ratio  = _safe_float(payload.get("budget_overspend_ratio")),
        budgets_breached        = _safe_int(payload.get("budgets_breached")),
        goal_set                = bool(payload.get("goal_set", False)),
        goal_progress           = _safe_float(payload.get("goal_progress")),
        goal_pace_ratio         = _safe_float(payload.get("goal_pace_ratio")),
        goal_achievement_streak = _safe_int(payload.get("goal_achievement_streak")),
        goal_required_share     = _safe_float(payload.get("goal_required_share")),
        # Default True: an absent or unmeasurable goal is not "unrealistic",
        # and treating it as such would suppress the pace rules for everyone.
        goal_is_realistic       = bool(payload.get("goal_is_realistic", True)),
        spending_trend          = payload.get("spending_trend", "stable"),
    ))

    advisor.run()
    advisor.finalize(projected_spend_rate=projected, has_income=has_income)

    return {
        "score":      advisor.score,
        "category":   advisor.category,
        "persona":    advisor.persona,
        "projection": advisor.projection,
        "advice":     advisor.advice,
        "is_urgent":  _is_urgent(advisor.score, payload, has_income),
    }


def _is_urgent(score: int, payload: dict, has_income: bool) -> bool:
    """
    Whether the guardian should be alerted automatically.

    Requires real income data. Without it the rates are unknown rather than
    alarming, and alerting someone's guardian because they have not yet entered
    a payslip is worse than not alerting at all.
    """
    if not has_income:
        return False

    spending_far_over = _safe_float(payload.get("projected_spend_rate")) > 130
    collapsing        = payload.get("spending_trend") == "worsening_fast"
    return score < 35 or (spending_far_over and collapsing)


# ─── Safe type helpers ────────────────────────────────────────────────────────

def _safe_float(value, fallback: float = 0.0) -> float:
    """
    Convert to float, defaulting to 0.0.

    This used to substitute 0.01 for any zero "to avoid Experta zero issues",
    which meant a user with no income was scored as though they saved 0.01% of
    it - producing "CRITICAL: saving less than 2% of your income" for someone
    with no income at all. Zero is now allowed to mean zero, and the has_income
    flag carries the distinction.
    """
    try:
        result = float(value)
    except (TypeError, ValueError):
        return fallback
    if result != result:          # NaN
        return fallback
    return result


def _safe_int(value, fallback: int = 0) -> int:
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return fallback
