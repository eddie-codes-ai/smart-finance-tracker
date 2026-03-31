// lib/core/routes.dart
// All named routes for the app.

import 'package:flutter/material.dart';

import '../ui/auth/login_screen.dart';
import '../ui/auth/register_screen.dart';
import '../ui/splash/splash_screen.dart';
import '../ui/shell/main_shell.dart';
import '../ui/dashboard/dashboard_screen.dart';
import '../ui/transactions/transactions_screen.dart';
import '../ui/transactions/add_income_screen.dart';
import '../ui/transactions/add_expense_screen.dart';
import '../ui/transactions/mpesa_import_screen.dart';
import '../ui/budget/budget_screen.dart';
import '../ui/budget/add_budget_screen.dart';
import '../ui/goals/goals_screen.dart';
import '../ui/goals/add_goal_screen.dart';
import '../ui/reports/reports_screen.dart';
import '../ui/insights/insights_screen.dart';
import '../ui/guardian/guardian_screen.dart';
import '../ui/helb/helb_planner_screen.dart'; // ← NEW

class AppRoutes {
  // ── Existing routes ──────────────────────────────────────────────────────
  static const String splash        = '/';
  static const String login         = '/login';
  static const String register      = '/register';
  static const String shell         = '/shell';
  static const String dashboard     = '/dashboard';
  static const String transactions  = '/transactions';
  static const String addIncome     = '/add-income';
  static const String addExpense    = '/add-expense';
  static const String budget        = '/budget';
  static const String addBudget     = '/add-budget';
  static const String goals         = '/goals';
  static const String addGoal       = '/add-goal';
  static const String reports       = '/reports';
  static const String insights      = '/insights';
  static const String guardian      = '/guardian';
  static const String mpesaImport   = '/mpesa-import';
  static const String helbPlanner   = '/helb-planner'; // ← NEW

  // ── Static routes map ────────────────────────────────────────────────────
  static Map<String, WidgetBuilder> get routes => {
    splash:        (_) => const SplashScreen(),
    login:         (_) => const LoginScreen(),
    register:      (_) => const RegisterScreen(),
    shell:         (_) => const MainShell(),
    dashboard:     (_) => const DashboardScreen(),
    transactions:  (_) => const TransactionsScreen(),
    addIncome:     (_) => const AddIncomeScreen(),
    addExpense:    (_) => const AddExpenseScreen(),
    budget:        (_) => const BudgetScreen(),
    addBudget:     (_) => const AddBudgetScreen(),
    goals:         (_) => const GoalsScreen(),
    addGoal:       (_) => const AddGoalScreen(),
    reports:       (_) => const ReportsScreen(),
    insights:      (_) => const InsightsScreen(),
    guardian:      (_) => const GuardianScreen(),
    mpesaImport:   (_) => const MpesaImportScreen(),
    helbPlanner:   (_) => const HelbPlannerScreen(), // ← NEW
  };

  // ── Route generator ──────────────────────────────────────────────────────
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case splash:
        return MaterialPageRoute(builder: (_) => const SplashScreen());
      case login:
        return MaterialPageRoute(builder: (_) => const LoginScreen());
      case register:
        return MaterialPageRoute(builder: (_) => const RegisterScreen());
      case shell:
        return MaterialPageRoute(builder: (_) => const MainShell());
      case dashboard:
        return MaterialPageRoute(builder: (_) => const DashboardScreen());
      case transactions:
        return MaterialPageRoute(builder: (_) => const TransactionsScreen());
      case addIncome:
        return MaterialPageRoute(builder: (_) => const AddIncomeScreen());
      case addExpense:
        return MaterialPageRoute(builder: (_) => const AddExpenseScreen());
      case budget:
        return MaterialPageRoute(builder: (_) => const BudgetScreen());
      case addBudget:
        return MaterialPageRoute(builder: (_) => const AddBudgetScreen());
      case goals:
        return MaterialPageRoute(builder: (_) => const GoalsScreen());
      case addGoal:
        return MaterialPageRoute(builder: (_) => const AddGoalScreen());
      case reports:
        return MaterialPageRoute(builder: (_) => const ReportsScreen());
      case insights:
        return MaterialPageRoute(builder: (_) => const InsightsScreen());
      case guardian:
        return MaterialPageRoute(builder: (_) => const GuardianScreen());
      case mpesaImport:
        return MaterialPageRoute(builder: (_) => const MpesaImportScreen());
      case helbPlanner: // ← NEW
        return MaterialPageRoute(builder: (_) => const HelbPlannerScreen());

      default:
        return MaterialPageRoute(
          builder: (_) => const Scaffold(
            body: Center(child: Text('Route not found')),
          ),
        );
    }
  }
}