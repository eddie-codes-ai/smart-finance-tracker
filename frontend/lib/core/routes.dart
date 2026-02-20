// lib/core/routes.dart
// All named routes in one place.
// To navigate anywhere in the app: Navigator.pushNamed(context, AppRoutes.login)

import 'package:flutter/material.dart';
import '../ui/splash/splash_screen.dart';
import '../ui/auth/login_screen.dart';
import '../ui/auth/register_screen.dart';
import '../ui/dashboard/dashboard_screen.dart';
import '../ui/transactions/transactions_screen.dart';
import '../ui/transactions/add_income_screen.dart';
import '../ui/transactions/add_expense_screen.dart';
import '../ui/budget/budget_screen.dart';
import '../ui/budget/add_budget_screen.dart';
import '../ui/reports/reports_screen.dart';
import '../ui/insights/insights_screen.dart';
import '../ui/goals/goals_screen.dart';
import '../ui/goals/add_goal_screen.dart';
import '../ui/guardian/guardian_screen.dart';

class AppRoutes {
  // ─── Route Name Constants ───────────────────────────────────────────────────
  static const String splash = '/';
  static const String login = '/login';
  static const String register = '/register';
  static const String dashboard = '/dashboard';
  static const String transactions = '/transactions';
  static const String addIncome = '/transactions/add-income';
  static const String addExpense = '/transactions/add-expense';
  static const String budget = '/budget';
  static const String addBudget = '/budget/add';
  static const String reports = '/reports';
  static const String insights = '/insights';
  static const String goals = '/goals';
  static const String addGoal = '/goals/add';
  static const String guardian = '/guardian';

  // ─── Route Map ──────────────────────────────────────────────────────────────
  // Passed to MaterialApp's routes parameter in app.dart.
  static Map<String, WidgetBuilder> get routes {
    return {
      splash: (_) => const SplashScreen(),
      login: (_) => const LoginScreen(),
      register: (_) => const RegisterScreen(),
      dashboard: (_) => const DashboardScreen(),
      transactions: (_) => const TransactionsScreen(),
      addIncome: (_) => const AddIncomeScreen(),
      addExpense: (_) => const AddExpenseScreen(),
      budget: (_) => const BudgetScreen(),
      addBudget: (_) => const AddBudgetScreen(),
      reports: (_) => const ReportsScreen(),
      insights: (_) => const InsightsScreen(),
      goals: (_) => const GoalsScreen(),
      addGoal: (_) => const AddGoalScreen(),
      guardian: (_) => const GuardianScreen(),
    };
  }
}