from datetime import datetime
from engine.facts import FinancialProfile
from engine.rules import FinancialAdvisor


def run_analysis(payload: dict) -> dict:
    """
    Entry point for the expert system.

    Accepts a processed payload (already computed by analysis_service),
    declares the FinancialProfile fact, runs all rules, finalizes,
    and returns a clean results dict for the API layer to return to Flutter.
    """

    # ── No-data guard ────────────────────────────────────────────────────────
    # If the student has not logged any income or expenses yet, skip the engine
    # entirely and return a neutral placeholder result. Without this check,
    # the engine runs on near-zero fallback values and produces a misleading
    # score (e.g. 60) for a brand new account with no transactions.
    income   = payload.get("income",   0)
    expenses = payload.get("expenses", 0)

    if income <= 0.01 and expenses <= 0.01:
        return {
            "score":      0,
            "category":   "No Data",
            "persona":    "No transactions recorded yet",
            "projection": "Add income and expenses to get your financial projection",
            "advice":     [],
            "is_urgent":  False,
        }
    # ─────────────────────────────────────────────────────────────────────────

    advisor = FinancialAdvisor()
    advisor.reset()

    advisor.declare(FinancialProfile(
        income                   = _safe_float(payload.get("income")),
        expenses                 = _safe_float(payload.get("expenses")),
        savings_rate             = _safe_float(payload.get("savings_rate")),
        expense_rate             = _safe_float(payload.get("expense_rate")),
        overspent_days           = _safe_int(payload.get("overspent_days")),
        luxury_spending_ratio    = _safe_float(payload.get("luxury_spending_ratio")),
        emergency_buffer_present = bool(payload.get("emergency_buffer_present", False)),
        emergency_buffer_amount  = _safe_float(payload.get("emergency_buffer_amount")),
        goal_progress            = _safe_float(payload.get("goal_progress")),
        goal_set                 = bool(payload.get("goal_set", False)),
        day_of_month             = _safe_int(payload.get("day_of_month", datetime.now().day)),
        spending_trend           = payload.get("spending_trend", "stable"),
        salary_burn_rate         = _safe_float(payload.get("salary_burn_rate")),
        luxury_expense_growth    = payload.get("luxury_expense_growth", "stable"),
        overspending_streak      = _safe_int(payload.get("overspending_streak")),
        goal_achievement_streak  = _safe_int(payload.get("goal_achievement_streak")),
    ))

    advisor.run()
    advisor.finalize(expense_rate=_safe_float(payload.get("expense_rate")))

    return {
        "score":      advisor.score,
        "category":   advisor.category,
        "persona":    advisor.persona,
        "projection": advisor.projection,
        "advice":     advisor.advice,
        "is_urgent":  _is_urgent(advisor.score, payload),
    }


def _is_urgent(score: int, payload: dict) -> bool:
    """
    Determines if the guardian should be auto-notified.
    Triggers if any of the three urgency conditions are met.
    """
    worsening_fast  = payload.get("spending_trend") == "worsening_fast"
    mid_month_blown = (
        payload.get("day_of_month", 0) >= 15 and
        payload.get("expense_rate", 0) > 80
    )
    return score < 40 or worsening_fast or mid_month_blown


# ─── Safe type helpers ────────────────────────────────────────────────────────

def _safe_float(value, fallback: float = 0.01) -> float:
    """Convert to float safely. Uses a small fallback to avoid Experta zero issues."""
    try:
        v = float(value)
        return v if v != 0 else fallback
    except (TypeError, ValueError):
        return fallback


def _safe_int(value, fallback: int = 0) -> int:
    """Convert to int safely."""
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return fallback