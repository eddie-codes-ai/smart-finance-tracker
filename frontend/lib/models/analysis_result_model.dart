// lib/models/analysis_result_model.dart
// Represents the full response from POST /api/analyze.
// Fields verified against routes.py analyze() return statement
// and analysis_service.py compute_analysis_payload() return dict.

class CategoryVariance {
  final double spent;
  final double budget;
  final double variance;      // positive = overspent, negative = underspent
  final double usagePercent;  // spent / budget * 100
  final String status;        // 'over' | 'under'

  CategoryVariance({
    required this.spent,
    required this.budget,
    required this.variance,
    required this.usagePercent,
    required this.status,
  });

  factory CategoryVariance.fromJson(Map<String, dynamic> json) {
    return CategoryVariance(
      spent:        (json['spent'] as num).toDouble(),
      budget:       (json['budget'] as num).toDouble(),
      variance:     (json['variance'] as num).toDouble(),
      usagePercent: (json['usage_percent'] as num).toDouble(),
      status:       json['status'] ?? 'under',
    );
  }
}

class AnalysisResultModel {
  // ─── Period ─────────────────────────────────────────────────────────────────
  final String period;          // e.g. "2025-07"

  // ─── Score & Classification ─────────────────────────────────────────────────
  final double score;           // 0-100 clamped
  final String category;        // Critical | At Risk | Average | Good | Very Good | Excellent | Elite
  final String persona;         // e.g. "Financial Free-Faller" to "Strict Saver"
  final String projection;      // 4-level projection string from expense_rate

  // ─── Financials ─────────────────────────────────────────────────────────────
  final double income;
  final double expenses;
  final double savings;             // income - expenses (gross)
  final double balance;             // income - expenses - total_contributions (truly free money)
  final double totalContributions;  // total committed across all goals
  final double savingsRate;         // % of income saved
  final double expenseRate;         // % of income spent
  final double dailyBudget;         // monthly_income / 30

  // ─── Spending Behavior ──────────────────────────────────────────────────────
  final bool hasIncome;         // false when no income is recorded for the period
  final int dayOfMonth;
  final String spendingTrend;   // improving | stable | worsening_slow | worsening_fast

  /// Month-end spend projected from the pace so far, as a % of income. Over 100
  /// means this month ends in deficit if nothing changes. Replaces
  /// salaryBurnRate, whose old server-side formula reduced to 3000/day and so
  /// carried no information about actual spending.
  final double projectedSpendRate;

  /// Months of typical spending covered by savings accumulated across all
  /// history. Replaces emergencyBufferPresent, which was just
  /// (income - expenses) / income >= 0.1 — the savings rate again.
  final double emergencyFundMonths;

  final int overspentDays;        // days the daily budget was exceeded
  final int overspendingStreak;   // longest consecutive run of those days

  // ─── Goal ───────────────────────────────────────────────────────────────────
  final double goalProgress;    // % toward savings goal
  final double goalPaceRatio;   // contributed / expected-by-now; 1.0 is on pace
  final String goalHealth;      // human-readable goal status string

  // ─── Advice & Alerts ────────────────────────────────────────────────────────
  final List<String> advice;    // list of advice strings fired by Experta rules
  final bool isUrgent;          // true if guardian auto-notify was triggered

  // ─── Budget Variance Per Category ───────────────────────────────────────────
  final Map<String, CategoryVariance> categoryVariance;

  AnalysisResultModel({
    required this.period,
    required this.score,
    required this.category,
    required this.persona,
    required this.projection,
    required this.income,
    required this.expenses,
    required this.savings,
    required this.balance,
    required this.totalContributions,
    required this.savingsRate,
    required this.expenseRate,
    required this.dailyBudget,
    required this.hasIncome,
    required this.dayOfMonth,
    required this.spendingTrend,
    required this.projectedSpendRate,
    required this.emergencyFundMonths,
    required this.overspentDays,
    required this.overspendingStreak,
    required this.goalProgress,
    required this.goalPaceRatio,
    required this.goalHealth,
    required this.advice,
    required this.isUrgent,
    required this.categoryVariance,
  });

  factory AnalysisResultModel.fromJson(Map<String, dynamic> json) {
    final Map<String, CategoryVariance> variance = {};
    if (json['category_variance'] != null) {
      (json['category_variance'] as Map<String, dynamic>).forEach((key, value) {
        variance[key] = CategoryVariance.fromJson(value);
      });
    }

    return AnalysisResultModel(
      period:                 json['period']              ?? '',
      score:                  (json['score'] as num? ?? 0).toDouble(),
      category:               json['category']            ?? '',
      persona:                json['persona']             ?? '',
      projection:             json['projection']          ?? '',
      income:                 (json['income'] as num? ?? 0).toDouble(),
      expenses:               (json['expenses'] as num? ?? 0).toDouble(),
      savings:                (json['savings'] as num? ?? 0).toDouble(),
      balance:                (json['balance'] as num? ?? 0).toDouble(),
      totalContributions:     (json['total_contributions'] as num? ?? 0).toDouble(),
      savingsRate:            (json['savings_rate'] as num? ?? 0).toDouble(),
      expenseRate:            (json['expense_rate'] as num? ?? 0).toDouble(),
      dailyBudget:            (json['daily_budget'] as num? ?? 0).toDouble(),
      hasIncome:              json['has_income'] ?? true,
      dayOfMonth:             json['day_of_month']        ?? DateTime.now().day,
      spendingTrend:          json['spending_trend']      ?? 'stable',
      projectedSpendRate:     (json['projected_spend_rate'] as num? ?? 0).toDouble(),
      emergencyFundMonths:    (json['emergency_fund_months'] as num? ?? 0).toDouble(),
      overspentDays:          (json['overspent_days'] as num? ?? 0).toInt(),
      overspendingStreak:     (json['overspending_streak'] as num? ?? 0).toInt(),
      goalProgress:           (json['goal_progress'] as num? ?? 0).toDouble(),
      goalPaceRatio:          (json['goal_pace_ratio'] as num? ?? 1).toDouble(),
      goalHealth:             json['goal_health']         ?? '',
      advice:                 List<String>.from(json['advice'] ?? []),
      isUrgent:               json['is_urgent']           ?? false,
      categoryVariance:       variance,
    );
  }
}