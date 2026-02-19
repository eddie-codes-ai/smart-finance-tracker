from experta import Fact, Field


class FinancialProfile(Fact):
    """
    Represents a snapshot of a student's financial state.
    Declared into the Experta engine before running analysis.
    """
    income                  = Field(float, mandatory=True)
    expenses                = Field(float, mandatory=True)
    savings_rate            = Field(float, mandatory=True)   # % of income saved
    expense_rate            = Field(float, mandatory=True)   # % of income spent
    overspent_days          = Field(int,   mandatory=True)   # days daily budget exceeded
    luxury_spending_ratio   = Field(float, mandatory=True)   # % of expenses on luxuries
    emergency_buffer_present= Field(bool,  mandatory=True)   # >= 10% income remaining
    emergency_buffer_amount = Field(float, mandatory=True)   # buffer as % of income
    goal_progress           = Field(float, mandatory=True)   # % toward savings goal
    day_of_month            = Field(int,   mandatory=True)   # current day (1-31)
    spending_trend          = Field(str,   mandatory=True)   # 'improving' | 'stable' | 'worsening_slow' | 'worsening_fast'
    salary_burn_rate        = Field(float, mandatory=True)   # % of salary burned by mid-month
    luxury_expense_growth   = Field(str,   mandatory=True)   # 'increasing' | 'stable' | 'decreasing'
    overspending_streak     = Field(int,   mandatory=True)   # longest consecutive overspending days
    goal_achievement_streak = Field(int,   mandatory=True)   # consecutive months meeting goal