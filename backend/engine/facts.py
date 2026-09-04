from experta import Fact, Field


class FinancialProfile(Fact):
    """
    A snapshot of a student's financial state, declared into the engine before
    analysis runs.

    Each field is meant to carry information no other field carries. That was
    not previously true: emergency_buffer_amount was literally
    (income - expenses) / income, which is savings_rate / 100, and expense_rate
    is 100 - savings_rate. Three families of rules were therefore penalising one
    number three times, and a student saving 8% of their income scored 20/100
    with nothing else wrong.

    Where two fields could overlap, the comment says what keeps them distinct.
    """

    # ── Is there anything to measure? ────────────────────────────────────────
    # Everything derived from income is meaningless without it. Rather than
    # substituting a fake 0.01 rate - which produced "saving less than 2% is
    # dangerous" alongside "less than 40% of income spent, discipline strong!"
    # for the same user - the income-derived rules are gated on this.
    has_income              = Field(bool,  mandatory=True)

    income                  = Field(float, mandatory=True)
    expenses                = Field(float, mandatory=True)

    # ── How much is kept ─────────────────────────────────────────────────────
    savings_rate            = Field(float, mandatory=True)   # % of income saved

    # ── How fast it is going out ─────────────────────────────────────────────
    # Projected month-end spend as a % of income, extrapolated from the pace so
    # far. Distinct from savings_rate: "you are spending faster than the month
    # is passing" is a claim about *rate*, and is the only thing that justifies
    # warning about running out before month-end. Early in the month a high
    # projection is a real warning even when little has been spent yet.
    projected_spend_rate    = Field(float, mandatory=True)
    day_of_month            = Field(int,   mandatory=True)

    # ── Depth of the safety net ──────────────────────────────────────────────
    # Months of typical expenses covered by surplus accumulated across ALL
    # history. A real emergency fund, and independent of this month's rate: a
    # student can save 0% this month and still be three months deep.
    emergency_fund_months   = Field(float, mandatory=True)

    # ── Daily discipline ─────────────────────────────────────────────────────
    overspent_days          = Field(int,   mandatory=True)   # how OFTEN
    overspending_streak     = Field(int,   mandatory=True)   # how PERSISTENTLY
    # Five scattered overspends is a bad month; five consecutive is a spiral.
    # Only the streak distinguishes them.

    # ── What the money goes on ───────────────────────────────────────────────
    luxury_spending_ratio   = Field(float, mandatory=True)   # % of spend on luxuries
    luxury_expense_growth   = Field(str,   mandatory=True)   # increasing|stable|decreasing

    # ── Budgets the student set for themselves ───────────────────────────────
    # Distinct from overspent_days, which measures breaches of a daily average
    # the app derives (income / 30). This measures the limits the student chose.
    # Someone can stay under that average every day and still wreck every
    # category budget.
    budgets_set             = Field(int,   mandatory=True)   # how many exist
    budget_overspend_ratio  = Field(float, mandatory=True)   # spent / budgeted; 1.0 is on budget
    # How many individual limits were breached. Used ONLY to make the advice
    # specific - never scored. Breach count and breach magnitude move together,
    # so scoring both would re-introduce the double-counting this design exists
    # to avoid.
    budgets_breached        = Field(int,   mandatory=True)

    # ── Goals ────────────────────────────────────────────────────────────────
    goal_set                = Field(bool,  mandatory=True)
    goal_progress           = Field(float, mandatory=True)   # % of target, for display
    # Contributed vs what the deadline implies by now. 1.0 is exactly on pace.
    # Absolute progress alone punished every newly created goal: a student
    # saving 70% of income was labelled "Overspender" for having set one.
    goal_pace_ratio         = Field(float, mandatory=True)
    goal_achievement_streak = Field(int,   mandatory=True)   # consecutive months on pace

    # What the deadline demands each month, as a share of income. Pace asks
    # "are you keeping up"; this asks "was this ever achievable". A 50,000
    # target due next month on 15,000 a month reads as "far behind pace" every
    # month forever, and the advice tells the student to contribute more when
    # no amount of contributing would work.
    goal_required_share     = Field(float, mandatory=True)
    goal_is_realistic       = Field(bool,  mandatory=True)

    # ── Direction of travel ──────────────────────────────────────────────────
    spending_trend          = Field(str,   mandatory=True)
    # improving | stable | worsening_slow | worsening_fast
