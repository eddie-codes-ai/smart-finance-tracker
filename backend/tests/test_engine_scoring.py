"""
Golden-scenario tests for the expert system.

The engine had 43 rules and no tests. Several families measured the same number
under different names - emergency_buffer_amount was literally
(income - expenses) / income, which is savings_rate / 100, and expense_rate is
its complement - so one fact was penalised up to three times. A student saving
8% of income with nothing else wrong scored 20/100, "Critical".

Scoring changes cannot be verified by reading the diff; they need scenarios with
stated expectations. That is what this file is. It runs the engine directly,
with no database or app, so it is fast and each case is explicit about the
student it describes.

Run it directly, no pytest needed:

    cd backend
    venv/Scripts/python tests/test_engine_scoring.py     # Windows
    venv/bin/python tests/test_engine_scoring.py         # Linux/macOS
"""
import os
import sys

BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, BACKEND_DIR)

from engine.knowledge_engine import run_analysis                      # noqa: E402


def profile(**overrides):
    """A student doing nothing wrong and nothing especially well."""
    base = dict(
        has_income=True,
        income=20000.0,
        expenses=15000.0,
        savings_rate=25.0,
        projected_spend_rate=75.0,
        emergency_fund_months=1.5,
        overspent_days=0,
        overspending_streak=0,
        luxury_spending_ratio=20.0,
        luxury_expense_growth='stable',
        goal_set=True,
        goal_progress=50.0,
        goal_pace_ratio=1.0,
        goal_achievement_streak=0,
        goal_required_share=0.1,
        goal_is_realistic=True,
        budgets_set=3,
        budget_overspend_ratio=0.8,
        budgets_breached=0,
        day_of_month=20,
        spending_trend='stable',
    )
    base.update(overrides)
    return base


def score_of(**overrides):
    return run_analysis(profile(**overrides))["score"]


def advice_of(**overrides):
    return run_analysis(profile(**overrides))["advice"]


def joined(**overrides):
    return " || ".join(advice_of(**overrides)).lower()


# ── The bug that started this ─────────────────────────────────────────────────

def test_one_weakness_is_penalised_once():
    """
    Saving 8% used to cost -20 (savings), -20 (no buffer) and -40 (mid-month
    expense rate) for the single fact that 8% was saved: 20/100, "Critical".

    It is a real weakness and should still hurt - but as one weakness.
    """
    result = run_analysis(profile(
        savings_rate=8.0,
        projected_spend_rate=92.0,   # the arithmetic consequence of saving 8%
        emergency_fund_months=0.0,   # a new saver genuinely has no fund yet
    ))
    assert 40 <= result["score"] <= 75, \
        "8%% saver scored %s (%s)" % (result["score"], result["category"])


def test_the_savings_rate_ladder_is_monotonic():
    previous = -1
    for rate in [0, 4, 8, 12, 18, 25, 35, 45, 60]:
        current = score_of(savings_rate=rate,
                           projected_spend_rate=max(0.0, 100.0 - rate))
        assert current >= previous, \
            "saving %s%% scored %s, less than the tier below (%s)" % (rate, current, previous)
        previous = current


def test_no_contradictory_pair_about_the_same_number():
    """A 30% saver was told their savings were excellent AND that they were at
    risk of running out before month-end. Both described one number."""
    text = joined(savings_rate=30.0, projected_spend_rate=70.0)
    assert "excellent savings rate" in text
    assert "spend more than you earn" not in text
    assert "slightly more than your income" not in text


# ── No income ─────────────────────────────────────────────────────────────────

def test_no_income_says_so_and_claims_nothing_else():
    result = run_analysis(profile(
        has_income=False, income=0.0, expenses=5000.0,
        savings_rate=0.0, projected_spend_rate=0.0,
    ))
    text = " || ".join(result["advice"]).lower()

    assert "no income recorded" in text
    # None of the income-derived claims may appear.
    assert "saving less than" not in text
    assert "% of your income" not in text
    assert "pace" not in text


def test_no_income_does_not_alert_the_guardian():
    """Someone who has not yet entered a payslip is not in crisis."""
    result = run_analysis(profile(
        has_income=False, income=0.0, expenses=5000.0,
        savings_rate=0.0, projected_spend_rate=0.0, spending_trend='worsening_fast',
    ))
    assert result["is_urgent"] is False


def test_no_income_is_not_scored_at_all():
    """
    Suppressing the income rules leaves little deducting, so an unscoreable
    period drifted up to 82 and displayed as "Excellent" - a different false
    claim from the old "CRITICAL: saving less than 2% of your income", but a
    false claim all the same.
    """
    result = run_analysis(profile(
        has_income=False, income=0.0, expenses=5000.0,
        savings_rate=0.0, projected_spend_rate=0.0,
    ))
    assert result["category"] == "Not Scored", result["category"]
    assert result["score"] == 0
    assert "excellent" not in result["persona"].lower()
    assert "add your income" in result["projection"].lower()


def test_an_empty_period_is_not_a_failing_grade():
    result = run_analysis(profile(
        has_income=False, income=0.0, expenses=0.0,
        savings_rate=0.0, projected_spend_rate=0.0,
        goal_set=False, emergency_fund_months=0.0,
    ))
    assert "no income or spending recorded" in " || ".join(result["advice"]).lower()
    assert result["is_urgent"] is False
    assert result["category"] == "Not Scored"


def test_pace_is_not_extrapolated_from_the_first_few_days():
    """
    One ordinary shop on day 2 extrapolates to several times the month's income.
    The projection is withheld until there is enough of the month to read.
    """
    from services.analysis_service import _calculate_projected_spend_rate

    # 5,000 spent by day 3 of a 30-day month, against 20,000 income: the naive
    # extrapolation is 250%.
    assert _calculate_projected_spend_rate(5000.0, 20000.0, 3, 30) == 0.0

    # By day 10 the same pace is a real signal and is reported.
    assert _calculate_projected_spend_rate(5000.0, 20000.0, 10, 30) == 75.0


# ── Goals judged against the deadline ─────────────────────────────────────────

def test_a_brand_new_goal_is_not_a_failure():
    """
    A goal created yesterday sits near 0% progress. Judged absolutely that cost
    30 points, which is how someone saving 70% of income was labelled an
    Overspender.
    """
    result = run_analysis(profile(
        savings_rate=70.0, projected_spend_rate=30.0,
        goal_set=True, goal_progress=2.0, goal_pace_ratio=1.0,
        emergency_fund_months=2.0,
    ))
    assert result["score"] >= 80, "%s (%s)" % (result["score"], result["category"])
    assert "overspender" not in result["persona"].lower()


def test_genuinely_behind_on_a_goal_still_counts_against_you():
    on_pace = score_of(goal_pace_ratio=1.0)
    behind  = score_of(goal_pace_ratio=0.1)
    assert behind < on_pace


def test_goal_pace_ladder_is_monotonic():
    previous = -1
    for ratio in [0.1, 0.4, 0.75, 1.0, 2.0]:
        current = score_of(goal_pace_ratio=ratio)
        assert current >= previous, "pace %s scored %s vs %s" % (ratio, current, previous)
        previous = current


# ── Budgets the student set for themselves ────────────────────────────────────

def test_breaching_your_budgets_costs_you():
    """
    The whole budget feature previously had no effect on the score: a student
    could set limits on every category, breach them all, and nothing moved.
    """
    kept    = score_of(budgets_set=4, budget_overspend_ratio=0.8, budgets_breached=0)
    breached = score_of(budgets_set=4, budget_overspend_ratio=1.4, budgets_breached=4)
    assert breached < kept, "breaching every budget scored the same as keeping them"


def test_budget_adherence_ladder_is_monotonic():
    previous = -1
    for ratio in [1.5, 1.15, 1.0, 0.7]:
        current = score_of(budgets_set=4, budget_overspend_ratio=ratio)
        assert current >= previous, "ratio %s scored %s vs %s" % (ratio, current, previous)
        previous = current


def test_setting_no_budgets_is_a_nudge_not_a_punishment():
    none_set = score_of(budgets_set=0, budget_overspend_ratio=0.0, budgets_breached=0)
    breached = score_of(budgets_set=4, budget_overspend_ratio=1.4, budgets_breached=4)
    kept     = score_of(budgets_set=4, budget_overspend_ratio=0.8, budgets_breached=0)

    assert none_set < kept, "not budgeting should cost a little"
    assert none_set > breached, \
        "not setting a budget scored worse than setting one and blowing through it"


def test_budgets_do_not_disturb_the_savings_verdict():
    for ratio in (0.5, 1.6):
        text = joined(budgets_set=4, budget_overspend_ratio=ratio)
        assert "good savings discipline" in text, \
            "the savings verdict changed with budget adherence alone"


def test_breach_count_alone_does_not_change_the_score():
    """
    Count and magnitude move together, so only magnitude is scored. Scoring
    both would repeat the double-counting this engine was fixed for.
    """
    one_big  = score_of(budgets_set=4, budget_overspend_ratio=1.4, budgets_breached=1)
    all_four = score_of(budgets_set=4, budget_overspend_ratio=1.4, budgets_breached=4)
    assert one_big == all_four


# ── Was the goal ever achievable? ─────────────────────────────────────────────

def test_an_impossible_goal_is_charged_once_not_twice():
    """
    A target needing 90% of income is permanently "behind pace". Charging for
    the target AND the pace would penalise one fact twice - and telling the
    student to contribute more is useless advice.
    """
    result = run_analysis(profile(
        goal_required_share=0.9, goal_is_realistic=False, goal_pace_ratio=0.05,
    ))
    text = " || ".join(result["advice"]).lower()

    assert "move the deadline or lower the target" in text
    assert "far behind the pace" not in text, \
        "an unreachable goal was charged for its pace as well as its target"


def test_an_impossible_goal_makes_no_pace_claim_at_all():
    """
    A goal created today has nothing expected of it yet, so the pace ratio is
    1.0 and the positive pace rule fired - producing "move the deadline or
    lower the target" immediately followed by "you are on track to hit your
    savings goal". One goal, two contradictory statements.
    """
    for pace in (0.05, 1.0, 2.0):
        text = " || ".join(run_analysis(profile(
            goal_required_share=0.9, goal_is_realistic=False, goal_pace_ratio=pace,
        ))["advice"]).lower()
        assert "on track to hit your savings goal" not in text, \
            "unreachable goal claimed to be on track (pace %s)" % pace
        assert "well ahead of your savings goal" not in text, pace


def test_a_realistic_goal_that_is_behind_still_counts():
    on_pace = score_of(goal_required_share=0.1, goal_is_realistic=True,
                       goal_pace_ratio=1.0)
    behind  = score_of(goal_required_share=0.1, goal_is_realistic=True,
                       goal_pace_ratio=0.1)
    assert behind < on_pace, "a genuinely behind goal stopped counting"
    assert "far behind the pace" in joined(goal_required_share=0.1,
                                           goal_is_realistic=True,
                                           goal_pace_ratio=0.1)


def test_goal_demand_ladder_is_monotonic():
    previous = -1
    for share in [0.9, 0.6, 0.35, 0.1]:
        current = score_of(goal_required_share=share, goal_is_realistic=share <= 0.75)
        assert current >= previous, "share %s scored %s vs %s" % (share, current, previous)
        previous = current


def test_goal_realism_is_skipped_without_income():
    """Nothing to measure the demand against."""
    text = " || ".join(run_analysis(profile(
        has_income=False, income=0.0, expenses=1000.0,
        savings_rate=0.0, projected_spend_rate=0.0,
        goal_required_share=0.0,
    ))["advice"]).lower()
    assert "three quarters of your income" not in text
    assert "half your income each month" not in text


# ── Each family is independent ────────────────────────────────────────────────

def test_each_family_moves_the_score_on_its_own():
    """
    The whole point of the rework: changing one dimension must not be double
    counted through another. Each of these worsens exactly one thing.
    """
    baseline = score_of()
    for label, worse in [
        ("savings rate",     dict(savings_rate=2.0)),
        ("spending pace",    dict(projected_spend_rate=140.0)),
        ("emergency fund",   dict(emergency_fund_months=0.0)),
        ("overspent days",   dict(overspent_days=20)),
        ("overspend streak", dict(overspending_streak=12)),
        ("luxury ratio",     dict(luxury_spending_ratio=70.0)),
        ("goal pace",        dict(goal_pace_ratio=0.1)),
        ("goal realism",     dict(goal_required_share=0.9, goal_is_realistic=False)),
        ("budget adherence", dict(budget_overspend_ratio=1.5, budgets_breached=4)),
        ("trend",            dict(spending_trend='worsening_fast')),
    ]:
        assert score_of(**worse) < baseline, "%s did not affect the score" % label


def test_luxury_spending_does_not_disturb_the_savings_verdict():
    frugal_text = joined(luxury_spending_ratio=5.0)
    lavish_text = joined(luxury_spending_ratio=70.0)
    for text in (frugal_text, lavish_text):
        assert "good savings discipline" in text, \
            "the savings verdict changed with luxury spending alone"


def test_pace_is_about_rate_not_total():
    """
    Spending fast early is a real warning even when the month's total is still
    small - which is exactly what the old expense_rate rules could not express.
    """
    early_and_fast = run_analysis(profile(
        day_of_month=6, expenses=4000.0, savings_rate=80.0,
        projected_spend_rate=150.0,
    ))
    assert "pace" in " || ".join(early_and_fast["advice"]).lower()


# ── Persistence versus frequency ──────────────────────────────────────────────

def test_consecutive_overspending_is_worse_than_scattered():
    scattered  = score_of(overspent_days=6, overspending_streak=1)
    consecutive = score_of(overspent_days=6, overspending_streak=6)
    assert consecutive < scattered, \
        "a six-day run scored the same as six scattered days"


# ── Consistency is the one thing that adds points ─────────────────────────────

def test_a_long_goal_streak_improves_the_score():
    fresh     = score_of(goal_achievement_streak=0)
    sustained = score_of(goal_achievement_streak=8)
    assert sustained > fresh, "sustained consistency was invisible to the score"


# ── Advice ordering ───────────────────────────────────────────────────────────

def test_the_worst_news_comes_first():
    """
    The insights screen renders this list in order and the guardian report sends
    only the first two, so a guardian could be told "spending habits are stable"
    while the critical finding went unmentioned.
    """
    advice = advice_of(
        savings_rate=-10.0, projected_spend_rate=160.0,
        overspent_days=25, overspending_streak=14,
        spending_trend='worsening_fast', emergency_fund_months=0.0,
    )
    assert len(advice) >= 3
    head = " ".join(advice[:2]).lower()
    assert "spending more than you earn" in head or "unbroken overspending" in head, \
        "the most severe finding was not near the top: %s" % advice[:2]
    assert "roughly unchanged" not in head


# ── The bands still separate people ───────────────────────────────────────────

def test_personas_land_in_distinct_bands():
    """
    A fix that made everyone Elite would be no better than one that made
    everyone Critical. These four should stay clearly apart and in order.
    """
    disciplined = run_analysis(profile(
        savings_rate=45.0, projected_spend_rate=55.0, emergency_fund_months=4.0,
        luxury_spending_ratio=10.0, goal_pace_ratio=1.2, goal_achievement_streak=5,
        spending_trend='improving',
    ))
    typical = run_analysis(profile())
    stretched = run_analysis(profile(
        savings_rate=6.0, projected_spend_rate=97.0, emergency_fund_months=0.3,
        overspent_days=7, overspending_streak=3, luxury_spending_ratio=40.0,
        goal_pace_ratio=0.5, spending_trend='worsening_slow',
    ))
    in_trouble = run_analysis(profile(
        savings_rate=-15.0, projected_spend_rate=145.0, emergency_fund_months=0.0,
        overspent_days=22, overspending_streak=12, luxury_spending_ratio=65.0,
        luxury_expense_growth='increasing', goal_pace_ratio=0.05,
        spending_trend='worsening_fast',
    ))

    order = [disciplined, typical, stretched, in_trouble]
    scores = [r["score"] for r in order]
    assert scores == sorted(scores, reverse=True), scores

    assert disciplined["score"] >= 85, scores
    assert 60 <= typical["score"] <= 90, scores
    assert 30 <= stretched["score"] <= 65, scores
    assert in_trouble["score"] <= 25, scores

    # And they must not all read as the same person.
    assert len({r["category"] for r in order}) >= 3, [r["category"] for r in order]


def test_the_disciplined_student_is_not_urgent_and_the_failing_one_is():
    disciplined = run_analysis(profile(
        savings_rate=45.0, projected_spend_rate=55.0, emergency_fund_months=4.0,
        luxury_spending_ratio=10.0, goal_pace_ratio=1.2,
    ))
    assert disciplined["is_urgent"] is False

    failing = run_analysis(profile(
        savings_rate=-20.0, projected_spend_rate=170.0, emergency_fund_months=0.0,
        overspent_days=25, overspending_streak=15, luxury_spending_ratio=70.0,
        goal_pace_ratio=0.0, spending_trend='worsening_fast',
    ))
    assert failing["is_urgent"] is True


def test_score_is_always_in_range():
    for extreme in [
        dict(savings_rate=-500.0, projected_spend_rate=900.0, overspent_days=31,
             overspending_streak=31, luxury_spending_ratio=100.0,
             emergency_fund_months=0.0, goal_pace_ratio=0.0,
             spending_trend='worsening_fast', luxury_expense_growth='increasing'),
        dict(savings_rate=99.0, projected_spend_rate=1.0, emergency_fund_months=99.0,
             luxury_spending_ratio=0.0, goal_pace_ratio=9.0,
             goal_achievement_streak=99, spending_trend='improving',
             luxury_expense_growth='decreasing'),
    ]:
        s = score_of(**extreme)
        assert 0 <= s <= 100, s


def test_every_result_carries_the_expected_shape():
    result = run_analysis(profile())
    for key in ("score", "category", "persona", "projection", "advice", "is_urgent"):
        assert key in result, key
    assert isinstance(result["advice"], list) and result["advice"]
    assert result["projection"]


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
