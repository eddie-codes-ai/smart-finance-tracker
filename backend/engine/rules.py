from experta import KnowledgeEngine, Rule, P
from engine.facts import FinancialProfile


class FinancialAdvisor(KnowledgeEngine):
    """
    Expert system engine.
    Fires rules against a declared FinancialProfile fact,
    then finalize() assigns persona, category, and projection.
    """

    def __init__(self):
        super().__init__()
        self.advice   = []
        self.score    = 100
        self.category = ""
        self.persona  = ""
        self.projection = ""

    # =========================================================
    # SAVINGS RATE RULES
    # =========================================================

    @Rule(FinancialProfile(savings_rate=P(lambda x: x < 2)))
    def savings_extremely_critical(self):
        self.advice.append("CRITICAL: Saving less than 2% of your income is financially dangerous!")
        self.score -= 40

    @Rule(FinancialProfile(savings_rate=P(lambda x: 2 <= x < 5)))
    def savings_critical(self):
        self.advice.append("Very bad: Saving only 2%-5%. Major financial instability risk.")
        self.score -= 30

    @Rule(FinancialProfile(savings_rate=P(lambda x: 5 <= x < 8)))
    def savings_very_low(self):
        self.advice.append("Very low savings (5%-8%). Immediate correction needed.")
        self.score -= 25

    @Rule(FinancialProfile(savings_rate=P(lambda x: 8 <= x < 10)))
    def savings_low_borderline(self):
        self.advice.append("Borderline low savings (8%-10%). Still dangerous.")
        self.score -= 20

    @Rule(FinancialProfile(savings_rate=P(lambda x: 10 <= x < 12)))
    def savings_better_but_risky(self):
        self.advice.append("Savings slightly better (10%-12%) but still risky. Improve more.")
        self.score -= 15

    @Rule(FinancialProfile(savings_rate=P(lambda x: 12 <= x < 15)))
    def savings_moderate_risk(self):
        self.advice.append("Moderate risk: Saving between 12%-15%. You need stronger habits.")
        self.score -= 10

    @Rule(FinancialProfile(savings_rate=P(lambda x: 15 <= x < 18)))
    def savings_decent(self):
        self.advice.append("Decent savings (15%-18%). Could still be improved slightly.")
        self.score -= 5

    @Rule(FinancialProfile(savings_rate=P(lambda x: 18 <= x < 20)))
    def savings_okay(self):
        self.advice.append("Okay savings (18%-20%). Acceptable but strengthen for safety.")

    @Rule(FinancialProfile(savings_rate=P(lambda x: 20 <= x < 25)))
    def savings_good(self):
        self.advice.append("Good savings discipline (20%-25%). Keep maintaining this momentum.")

    @Rule(FinancialProfile(savings_rate=P(lambda x: 25 <= x < 30)))
    def savings_very_good(self):
        self.advice.append("Very good savings habit (25%-30%). Strong financial control!")

    @Rule(FinancialProfile(savings_rate=P(lambda x: 30 <= x < 40)))
    def savings_excellent(self):
        self.advice.append("Excellent savings (30%-40%). Your financial future looks very secure!")

    @Rule(FinancialProfile(savings_rate=P(lambda x: 40 <= x < 50)))
    def savings_outstanding(self):
        self.advice.append("Outstanding: Saving 40%-50% of your income! True financial independence ahead!")

    @Rule(FinancialProfile(savings_rate=P(lambda x: x >= 50)))
    def savings_legendary(self):
        self.advice.append("LEGENDARY: Saving more than half your income! Future millionaire behavior.")

    # =========================================================
    # BUDGET DISCIPLINE — OVERSPENT DAYS
    # =========================================================

    @Rule(FinancialProfile(overspent_days=P(lambda x: 1 <= x < 5)))
    def slight_overspending(self):
        self.advice.append("Slight overspending pattern detected. Monitor spending closely.")
        self.score -= 10

    @Rule(FinancialProfile(overspent_days=P(lambda x: 5 <= x < 10)))
    def moderate_overspending(self):
        self.advice.append("Moderate overspending across several days. Financial discipline slipping.")
        self.score -= 20

    @Rule(FinancialProfile(overspent_days=P(lambda x: 10 <= x < 15)))
    def severe_overspending(self):
        self.advice.append("Severe overspending streak detected. Major risk building.")
        self.score -= 35

    @Rule(FinancialProfile(overspent_days=P(lambda x: 15 <= x < 20)))
    def critical_overspending(self):
        self.advice.append("CRITICAL: Overspending almost every day. Financial stability at serious risk.")
        self.score -= 45

    @Rule(FinancialProfile(overspent_days=P(lambda x: x >= 20)))
    def extreme_overspending(self):
        self.advice.append("EXTREME: Daily budget violated almost every single day. Emergency action required.")
        self.score -= 55

    # =========================================================
    # EMERGENCY BUFFER RULES
    # =========================================================

    @Rule(FinancialProfile(emergency_buffer_present=False))
    def no_emergency_buffer(self):
        self.advice.append("No emergency buffer! You have no financial safety net. Build one immediately.")
        self.score -= 20

    @Rule(FinancialProfile(emergency_buffer_present=True))
    def has_emergency_buffer(self):
        self.advice.append("Good: Emergency buffer present. You have a financial safety net.")

    # =========================================================
    # LUXURY SPENDING RULES
    # =========================================================

    @Rule(FinancialProfile(luxury_spending_ratio=P(lambda x: x > 60)))
    def luxury_extreme_addiction(self):
        self.advice.append("EXTREME luxury addiction detected (>60% of expenses on luxuries). Critical risk of financial instability.")
        self.score -= 40

    @Rule(FinancialProfile(luxury_spending_ratio=P(lambda x: 50 < x <= 60)))
    def luxury_heavy_addiction(self):
        self.advice.append("Heavy luxury spending habit (50%-60% of expenses). Major risk of lifestyle inflation.")
        self.score -= 30

    @Rule(FinancialProfile(luxury_spending_ratio=P(lambda x: 40 < x <= 50)))
    def luxury_high(self):
        self.advice.append("High luxury expenses (40%-50%). Caution: lifestyle may be inflating beyond control.")
        self.score -= 20

    @Rule(FinancialProfile(luxury_spending_ratio=P(lambda x: 30 < x <= 40)))
    def luxury_moderate_high(self):
        self.advice.append("Moderate-High luxury spending (30%-40%). Monitor non-essential purchases closely.")
        self.score -= 10

    @Rule(FinancialProfile(luxury_spending_ratio=P(lambda x: 20 < x <= 30)))
    def luxury_acceptable_range(self):
        self.advice.append("Luxury spending (20%-30%) within tolerable range. Stay disciplined.")

    @Rule(FinancialProfile(luxury_expense_growth='increasing'))
    def luxury_addiction_increasing(self):
        self.advice.append("ALERT: Luxury spending pattern is increasing over time. Risk of financial habits worsening.")
        self.score -= 20

    @Rule(FinancialProfile(luxury_expense_growth='stable'))
    def luxury_stable(self):
        self.advice.append("Luxury spending pattern is stable. Good discipline maintained.")

    @Rule(FinancialProfile(luxury_expense_growth='decreasing'))
    def luxury_improving(self):
        self.advice.append("Luxury spending is decreasing over time. Excellent financial behavior improvement.")

    # =========================================================
    # GOAL ACHIEVEMENT RULES
    # =========================================================

    @Rule(FinancialProfile(goal_progress=P(lambda x: x < 10)))
    def goal_no_progress(self):
        self.advice.append("Critical: Less than 10% of your savings goal achieved. Immediate action required.")
        self.score -= 30

    @Rule(FinancialProfile(goal_progress=P(lambda x: 10 <= x < 30)))
    def goal_low_progress(self):
        self.advice.append("Low progress towards savings goal (10%-30%). Increase your savings efforts.")
        self.score -= 20

    @Rule(FinancialProfile(goal_progress=P(lambda x: 30 <= x < 50)))
    def goal_moderate_progress(self):
        self.advice.append("Moderate savings goal progress (30%-50%). Keep pushing forward.")
        self.score -= 10

    @Rule(FinancialProfile(goal_progress=P(lambda x: 50 <= x < 70)))
    def goal_good_progress(self):
        self.advice.append("Good progress toward savings goal (50%-70%). Stay focused!")

    @Rule(FinancialProfile(goal_progress=P(lambda x: 70 <= x < 90)))
    def goal_very_good_progress(self):
        self.advice.append("Very good savings goal achievement (70%-90%). Almost there!")

    @Rule(FinancialProfile(goal_progress=P(lambda x: 90 <= x <= 100)))
    def goal_almost_achieved(self):
        self.advice.append("Excellent: Near or complete achievement of savings goal. Outstanding!")

    @Rule(FinancialProfile(goal_progress=P(lambda x: x > 100)))
    def goal_exceeded(self):
        self.advice.append("WOW: You have exceeded your savings goal! True financial discipline.")

    # =========================================================
    # MID-MONTH FINANCIAL HEALTH RULES
    # =========================================================

    @Rule(FinancialProfile(
        day_of_month=P(lambda d: d >= 15),
        expense_rate=P(lambda x: x > 80)
    ))
    def mid_month_expenses_critical(self):
        self.advice.append("CRITICAL: By mid-month, over 80% of income spent. Immediate financial intervention required!")
        self.score -= 40

    @Rule(FinancialProfile(
        day_of_month=P(lambda d: d >= 15),
        expense_rate=P(lambda x: 60 < x <= 80)
    ))
    def mid_month_expenses_high(self):
        self.advice.append("Warning: By mid-month, 60%-80% of income already spent. Risk of salary depletion before month-end.")
        self.score -= 25

    @Rule(FinancialProfile(
        day_of_month=P(lambda d: d >= 15),
        expense_rate=P(lambda x: 40 < x <= 60)
    ))
    def mid_month_expenses_caution(self):
        self.advice.append("Caution: Mid-month expenses are 40%-60% of income. Monitor spending to stay on track.")

    @Rule(FinancialProfile(
        day_of_month=P(lambda d: d >= 15),
        expense_rate=P(lambda x: x <= 40)
    ))
    def mid_month_expenses_healthy(self):
        self.advice.append("Good management: Less than 40% of income spent by mid-month. Financial discipline strong!")

    # =========================================================
    # SPENDING TREND RULES
    # =========================================================

    @Rule(FinancialProfile(spending_trend='worsening_fast'))
    def spending_trend_worsening_fast(self):
        self.advice.append("CRITICAL: Spending habits are worsening rapidly. Financial collapse imminent if not corrected.")
        self.score -= 40

    @Rule(FinancialProfile(spending_trend='worsening_slow'))
    def spending_trend_worsening_slow(self):
        self.advice.append("Warning: Spending habits are slowly deteriorating. Early intervention needed.")
        self.score -= 20

    @Rule(FinancialProfile(spending_trend='stable'))
    def spending_trend_stable(self):
        self.advice.append("Spending habits are stable. Continue monitoring and maintaining discipline.")

    @Rule(FinancialProfile(spending_trend='improving'))
    def spending_trend_improving(self):
        self.advice.append("Excellent: Spending habits are improving over time. Keep reinforcing good behaviors!")

    # =========================================================
    # FINALIZATION
    # =========================================================

    def finalize(self):
        """Assign financial persona, category, and projection after all rules fire."""

        # Clamp score between 0 and 100
        self.score = max(0, min(100, self.score))

        # Score → Category
        if self.score >= 90:
            self.category = "Elite"
        elif self.score >= 80:
            self.category = "Excellent"
        elif self.score >= 70:
            self.category = "Very Good"
        elif self.score >= 60:
            self.category = "Good"
        elif self.score >= 50:
            self.category = "Average"
        elif self.score >= 40:
            self.category = "At Risk"
        else:
            self.category = "Critical"

        # Score → Persona
        if self.score >= 90:
            self.persona = "Strict Saver (Ultra Disciplined)"
        elif self.score >= 80:
            self.persona = "Strategic Investor (Goal-Oriented)"
        elif self.score >= 70:
            self.persona = "Balanced Planner (Well-Managed)"
        elif self.score >= 60:
            self.persona = "Conscious Spender (Stable but Watchful)"
        elif self.score >= 50:
            self.persona = "Casual Planner (Occasionally Careless)"
        elif self.score >= 40:
            self.persona = "Overspender (At Financial Risk)"
        elif self.score >= 30:
            self.persona = "Lifestyle Inflator (Dangerously Addicted to Luxury)"
        elif self.score >= 20:
            self.persona = "Paycheck-to-Paycheck Survivor (Financially Fragile)"
        elif self.score >= 10:
            self.persona = "Risk Taker (Negligent Financial Habits)"
        else:
            self.persona = "Financial Free-Faller (Critical Emergency)"