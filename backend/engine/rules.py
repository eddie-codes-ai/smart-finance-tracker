from experta import KnowledgeEngine, Rule, P
from engine.facts import FinancialProfile


# ─── Advice severity ──────────────────────────────────────────────────────────
# Rules fire in whatever order Experta resolves them, so without this the advice
# list came out in an arbitrary order: a CRITICAL item could sit fifth while
# "spending habits are stable" sat first. The insights screen renders the list
# in order, and the guardian report sends only the first two - so a guardian
# could be told "spending habits are stable" while the critical finding went
# unmentioned. finalize() sorts on this.
CRITICAL = 0
WARNING  = 1
CAUTION  = 2
NEUTRAL  = 3
GOOD     = 4


class FinancialAdvisor(KnowledgeEngine):
    """
    Rule-based financial health assessment.

    The score starts at 100 and rules deduct from it, with one exception: a
    sustained goal streak adds back, so consistent good behaviour is visible
    rather than merely un-penalised.

    The organising principle is that **each family measures something no other
    family measures**. Previously savings_rate, emergency_buffer and
    expense_rate were three names for one number, and a student saving 8% of
    income was penalised -20, -20 and -40 for that single fact, landing on
    20/100 "Critical" with nothing else wrong.
    """

    def __init__(self):
        super().__init__()
        self.findings   = []      # (severity, text) - sorted into self.advice
        self.score      = 100
        self.category   = ""
        self.persona    = ""
        self.projection = ""

    @property
    def advice(self):
        """Advice text, most severe first."""
        return [text for _, text in sorted(self.findings, key=lambda f: f[0])]

    def note(self, severity: int, text: str, penalty: int = 0):
        self.findings.append((severity, text))
        self.score -= penalty

    # =========================================================
    # NO INCOME
    # Nothing derived from income means anything without it.
    # =========================================================

    @Rule(FinancialProfile(has_income=False, expenses=P(lambda x: x > 0)))
    def no_income_but_spending(self):
        self.note(WARNING,
                  "No income recorded for this period, so your savings rate cannot be "
                  "assessed. Add your income to get a meaningful score.")

    @Rule(FinancialProfile(has_income=False, expenses=P(lambda x: x <= 0)))
    def no_activity(self):
        self.note(NEUTRAL,
                  "No income or spending recorded yet for this period.")

    # =========================================================
    # SAVINGS RATE — how much of income is kept
    # =========================================================

    @Rule(FinancialProfile(has_income=True, savings_rate=P(lambda x: x < 0)))
    def savings_negative(self):
        self.note(CRITICAL,
                  "You are spending more than you earn this period. This is the single "
                  "most urgent thing to correct.", 28)

    @Rule(FinancialProfile(has_income=True, savings_rate=P(lambda x: 0 <= x < 5)))
    def savings_extremely_critical(self):
        self.note(CRITICAL,
                  "CRITICAL: You are saving less than 5% of your income. Almost nothing "
                  "is being kept back.", 24)

    @Rule(FinancialProfile(has_income=True, savings_rate=P(lambda x: 5 <= x < 10)))
    def savings_very_low(self):
        self.note(WARNING,
                  "Saving only 5%-10% of your income leaves very little margin for a "
                  "bad month.", 16)

    @Rule(FinancialProfile(has_income=True, savings_rate=P(lambda x: 10 <= x < 15)))
    def savings_low(self):
        self.note(WARNING,
                  "Saving 10%-15%. A workable start, but thin if anything unexpected "
                  "comes up.", 10)

    @Rule(FinancialProfile(has_income=True, savings_rate=P(lambda x: 15 <= x < 20)))
    def savings_moderate(self):
        self.note(CAUTION,
                  "Saving 15%-20%. Reasonable, and worth pushing a little higher.", 6)

    @Rule(FinancialProfile(has_income=True, savings_rate=P(lambda x: 20 <= x < 30)))
    def savings_good(self):
        self.note(GOOD,
                  "Good savings discipline (20%-30% of income). Keep this up.", 4)

    @Rule(FinancialProfile(has_income=True, savings_rate=P(lambda x: 30 <= x < 40)))
    def savings_excellent(self):
        self.note(GOOD,
                  "Excellent savings rate (30%-40%). Well ahead of where most students are.", 2)

    @Rule(FinancialProfile(has_income=True, savings_rate=P(lambda x: 40 <= x < 50)))
    def savings_outstanding(self):
        self.note(GOOD,
                  "Outstanding: saving 40%-50% of your income.", 1)

    @Rule(FinancialProfile(has_income=True, savings_rate=P(lambda x: x >= 50)))
    def savings_exceptional(self):
        self.note(GOOD,
                  "Exceptional: you are keeping more than half of everything you earn.")

    # =========================================================
    # SPENDING PACE — projected month-end spend vs income
    #
    # Distinct from savings rate: this is about RATE, not total. Spending 40% of
    # income in the first three days projects to well over 100% by month-end,
    # and that is worth flagging on day 3 even though little has gone out yet.
    # The old rules compared raw expense_rate - the arithmetic complement of the
    # savings rate - and so punished the same fact a second time.
    # =========================================================

    @Rule(FinancialProfile(has_income=True, day_of_month=P(lambda d: d >= 5),
                           projected_spend_rate=P(lambda x: x > 130)))
    def pace_far_over(self):
        self.note(CRITICAL,
                  "At your current pace you will spend far more than you earn this "
                  "month. Slow down now or the month ends in deficit.", 18)

    @Rule(FinancialProfile(has_income=True, day_of_month=P(lambda d: d >= 5),
                           projected_spend_rate=P(lambda x: 105 < x <= 130)))
    def pace_over_income(self):
        self.note(WARNING,
                  "Your spending pace projects to slightly more than your income by "
                  "month-end. A small correction now avoids a shortfall.", 11)

    @Rule(FinancialProfile(has_income=True, day_of_month=P(lambda d: d >= 5),
                           projected_spend_rate=P(lambda x: 90 < x <= 105)))
    def pace_tight(self):
        self.note(CAUTION,
                  "You are on pace to spend almost exactly what you earn, leaving "
                  "nothing over.", 5)

    @Rule(FinancialProfile(has_income=True, day_of_month=P(lambda d: d >= 5),
                           projected_spend_rate=P(lambda x: x <= 90)))
    def pace_sustainable(self):
        self.note(GOOD,
                  "Your spending pace is sustainable for the rest of the month.")

    # =========================================================
    # EMERGENCY FUND — months of expenses the accumulated surplus covers
    #
    # A real cushion built over time, not this month's leftover. A student can
    # save nothing this month and still be three months deep.
    # =========================================================

    @Rule(FinancialProfile(emergency_fund_months=P(lambda x: x <= 0)))
    def fund_none(self):
        self.note(WARNING,
                  "You have no emergency fund. One unexpected cost would have to go on "
                  "credit or go unpaid.", 12)

    @Rule(FinancialProfile(emergency_fund_months=P(lambda x: 0 < x < 0.5)))
    def fund_negligible(self):
        self.note(WARNING,
                  "Your savings would cover less than two weeks of spending.", 8)

    @Rule(FinancialProfile(emergency_fund_months=P(lambda x: 0.5 <= x < 1)))
    def fund_thin(self):
        self.note(CAUTION,
                  "Your savings would cover under a month of spending. Aim for one "
                  "month first.", 4)

    @Rule(FinancialProfile(emergency_fund_months=P(lambda x: 1 <= x < 3)))
    def fund_building(self):
        self.note(GOOD,
                  "You have between one and three months of spending saved. A solid "
                  "cushion is forming.", 3)

    @Rule(FinancialProfile(emergency_fund_months=P(lambda x: x >= 3)))
    def fund_strong(self):
        self.note(GOOD,
                  "You have over three months of expenses saved. That is a genuine "
                  "safety net.")

    # =========================================================
    # DAILY DISCIPLINE — how often the daily budget breaks
    # =========================================================

    @Rule(FinancialProfile(overspent_days=P(lambda x: 1 <= x < 5)))
    def overspent_occasional(self):
        self.note(CAUTION,
                  "You went over your daily budget on a few days. Worth watching.", 3)

    @Rule(FinancialProfile(overspent_days=P(lambda x: 5 <= x < 10)))
    def overspent_frequent(self):
        self.note(WARNING,
                  "Your daily budget was exceeded on 5-10 days this period.", 7)

    @Rule(FinancialProfile(overspent_days=P(lambda x: 10 <= x < 18)))
    def overspent_habitual(self):
        self.note(WARNING,
                  "Your daily budget was broken on most days. The budget may be set "
                  "too low, or spending needs reining in.", 11)

    @Rule(FinancialProfile(overspent_days=P(lambda x: x >= 18)))
    def overspent_constant(self):
        self.note(CRITICAL,
                  "Your daily budget was exceeded on almost every day. It is not "
                  "currently guiding your spending at all.", 16)

    # =========================================================
    # PERSISTENCE — consecutive days over budget
    #
    # Independent of the count above: five scattered overspends is a bad month,
    # five consecutive is a spiral, and only a streak separates them.
    # =========================================================

    @Rule(FinancialProfile(overspending_streak=P(lambda x: 3 <= x < 6)))
    def streak_forming(self):
        self.note(CAUTION,
                  "You have been over budget several days running. Breaking the run "
                  "matters more than the amounts.", 3)

    @Rule(FinancialProfile(overspending_streak=P(lambda x: 6 <= x < 10)))
    def streak_entrenched(self):
        self.note(WARNING,
                  "Nearly a week of consecutive overspending. This has become a "
                  "pattern rather than a slip.", 7)

    @Rule(FinancialProfile(overspending_streak=P(lambda x: x >= 10)))
    def streak_spiral(self):
        self.note(CRITICAL,
                  "Over ten days of unbroken overspending. Reset your daily limit and "
                  "start again from today.", 12)

    # =========================================================
    # WHAT THE MONEY GOES ON
    # =========================================================

    @Rule(FinancialProfile(luxury_spending_ratio=P(lambda x: x > 60)))
    def luxury_dominant(self):
        self.note(WARNING,
                  "Over 60% of your spending is non-essential. Redirecting even a "
                  "quarter of it would change your month.", 12)

    @Rule(FinancialProfile(luxury_spending_ratio=P(lambda x: 45 < x <= 60)))
    def luxury_high(self):
        self.note(WARNING,
                  "45%-60% of your spending goes on non-essentials.", 8)

    @Rule(FinancialProfile(luxury_spending_ratio=P(lambda x: 30 < x <= 45)))
    def luxury_moderate(self):
        self.note(CAUTION,
                  "Around a third of your spending is non-essential. Worth keeping an "
                  "eye on.", 4)

    @Rule(FinancialProfile(luxury_spending_ratio=P(lambda x: x <= 30)))
    def luxury_controlled(self):
        self.note(GOOD,
                  "Most of your spending goes on essentials. Good control.", 1)

    @Rule(FinancialProfile(luxury_expense_growth='increasing'))
    def luxury_rising(self):
        self.note(CAUTION,
                  "Non-essential spending is a larger share than last period.", 6)

    @Rule(FinancialProfile(luxury_expense_growth='decreasing'))
    def luxury_falling(self):
        self.note(GOOD,
                  "Non-essential spending is a smaller share than last period.")

    # =========================================================
    # GOALS — pace against the deadline, not the absolute total
    #
    # goal_pace_ratio is contributed / expected-by-now. 1.0 is exactly on pace.
    # Judging on absolute progress punished every newly created goal: a student
    # saving 70% of income was labelled "Overspender" for setting one.
    # =========================================================

    @Rule(FinancialProfile(goal_set=True, goal_pace_ratio=P(lambda x: x < 0.25)))
    def goal_far_behind(self):
        self.note(WARNING,
                  "You are far behind the pace your savings goal needs. Either "
                  "contribute more or move the deadline.", 12)

    @Rule(FinancialProfile(goal_set=True, goal_pace_ratio=P(lambda x: 0.25 <= x < 0.6)))
    def goal_behind(self):
        self.note(WARNING,
                  "Your goal is behind schedule. Catching up now is easier than later.", 7)

    @Rule(FinancialProfile(goal_set=True, goal_pace_ratio=P(lambda x: 0.6 <= x < 0.9)))
    def goal_slightly_behind(self):
        self.note(CAUTION,
                  "You are a little behind on your savings goal. A small increase "
                  "would put you back on track.", 3)

    @Rule(FinancialProfile(goal_set=True, goal_pace_ratio=P(lambda x: 0.9 <= x < 1.5)))
    def goal_on_track(self):
        self.note(GOOD,
                  "You are on track to hit your savings goal by its deadline.", 1)

    @Rule(FinancialProfile(goal_set=True, goal_pace_ratio=P(lambda x: x >= 1.5)))
    def goal_ahead(self):
        self.note(GOOD,
                  "You are well ahead of your savings goal. Consider raising the "
                  "target or bringing the date forward.")

    @Rule(FinancialProfile(goal_set=False))
    def goal_absent(self):
        self.note(CAUTION,
                  "No savings goal set. Even a small target makes saving markedly "
                  "easier to sustain.", 3)

    # =========================================================
    # CONSISTENCY — the one place the score goes UP
    #
    # Nothing else adds points, so sustained good behaviour was invisible: a
    # student on pace for six months straight looked identical to one who
    # started yesterday.
    # =========================================================

    @Rule(FinancialProfile(goal_achievement_streak=P(lambda x: 2 <= x < 4)))
    def streak_goal_building(self):
        self.note(GOOD,
                  "You have hit your goal pace two months running.", -2)

    @Rule(FinancialProfile(goal_achievement_streak=P(lambda x: 4 <= x < 7)))
    def streak_goal_established(self):
        self.note(GOOD,
                  "Four or more consecutive months on target. This is a real habit now.", -5)

    @Rule(FinancialProfile(goal_achievement_streak=P(lambda x: x >= 7)))
    def streak_goal_sustained(self):
        self.note(GOOD,
                  "Over half a year of consistently meeting your savings pace. "
                  "Outstanding consistency.", -8)

    # =========================================================
    # DIRECTION OF TRAVEL — this period against the last
    # =========================================================

    @Rule(FinancialProfile(spending_trend='worsening_fast'))
    def trend_worsening_fast(self):
        self.note(WARNING,
                  "Your position has deteriorated sharply since last period.", 12)

    @Rule(FinancialProfile(spending_trend='worsening_slow'))
    def trend_worsening_slow(self):
        self.note(CAUTION,
                  "Your position is slipping gradually compared with last period.", 6)

    @Rule(FinancialProfile(spending_trend='stable'))
    def trend_stable(self):
        self.note(NEUTRAL,
                  "Your position is roughly unchanged since last period.", 2)

    @Rule(FinancialProfile(spending_trend='improving'))
    def trend_improving(self):
        self.note(GOOD,
                  "Your position has improved since last period. Whatever changed, "
                  "keep doing it.")

    # =========================================================
    # FINALIZATION
    # =========================================================

    def finalize(self, projected_spend_rate: float = 0.0, has_income: bool = True):
        """
        Assign category, persona and projection once every rule has fired.

        Args:
            projected_spend_rate: month-end spend as % of income, for the
                                  projection text.
            has_income:           when False there is nothing to project from.
        """
        self.score = max(0, min(100, self.score))

        # Without income there is nothing to score against. Suppressing the
        # income-derived rules leaves almost nothing deducting, so the score
        # drifts upward and an unscoreable period reads as "Excellent" - a
        # different lie from the old "CRITICAL: saving less than 2% of your
        # income", but a lie all the same. Say plainly that it is not scored.
        if not has_income:
            self.score      = 0
            self.category   = "Not Scored"
            self.persona    = "Add your income to see your financial profile"
            self.projection = ("Add your income for this period to see a month-end "
                               "projection.")
            return

        if self.score >= 90:
            self.category = "Elite"
            self.persona  = "Strict Saver (Ultra Disciplined)"
        elif self.score >= 80:
            self.category = "Excellent"
            self.persona  = "Strategic Planner (Goal-Oriented)"
        elif self.score >= 70:
            self.category = "Very Good"
            self.persona  = "Balanced Planner (Well-Managed)"
        elif self.score >= 60:
            self.category = "Good"
            self.persona  = "Conscious Spender (Stable but Watchful)"
        elif self.score >= 50:
            self.category = "Average"
            self.persona  = "Casual Planner (Occasionally Careless)"
        elif self.score >= 40:
            self.category = "At Risk"
            self.persona  = "Overspender (At Financial Risk)"
        elif self.score >= 25:
            self.category = "Critical"
            self.persona  = "Paycheck-to-Paycheck Survivor (Financially Fragile)"
        else:
            self.category = "Critical"
            self.persona  = "Financial Free-Faller (Critical Emergency)"

        if not has_income:
            self.projection = ("Add your income for this period to see a month-end "
                               "projection.")
        elif projected_spend_rate >= 115:
            self.projection = ("At this pace you will end the month having spent "
                               "considerably more than you earned.")
        elif projected_spend_rate >= 100:
            self.projection = ("At this pace you will spend everything you earn this "
                               "month, and possibly a little more.")
        elif projected_spend_rate >= 85:
            self.projection = ("At this pace you will finish the month with only a "
                               "small amount left over.")
        else:
            self.projection = ("At this pace you will finish the month with a healthy "
                               "surplus.")
