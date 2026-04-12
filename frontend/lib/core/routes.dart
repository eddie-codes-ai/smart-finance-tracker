// lib/core/routes.dart
// UPDATED: Added profile route constant and ProfileScreen registration.

import 'package:flutter/material.dart';
import 'package:frontend/ui/splash/splash_screen.dart';
import 'package:frontend/ui/auth/login_screen.dart';
import 'package:frontend/ui/auth/register_screen.dart';
import 'package:frontend/ui/auth/forgot_password_screen.dart';
import 'package:frontend/ui/auth/reset_password_screen.dart';
import 'package:frontend/ui/shell/main_shell.dart';
import 'package:frontend/ui/transactions/transactions_screen.dart';
import 'package:frontend/ui/transactions/add_income_screen.dart';
import 'package:frontend/ui/transactions/add_expense_screen.dart';
import 'package:frontend/ui/budget/budget_screen.dart';
import 'package:frontend/ui/budget/add_budget_screen.dart';
import 'package:frontend/ui/reports/reports_screen.dart';
import 'package:frontend/ui/insights/insights_screen.dart';
import 'package:frontend/ui/goals/goals_screen.dart';
import 'package:frontend/ui/goals/add_goal_screen.dart';
import 'package:frontend/ui/guardian/guardian_screen.dart';
import 'package:frontend/ui/helb/helb_planner_screen.dart';
import 'package:frontend/ui/transactions/mpesa_import_screen.dart';
import 'package:frontend/ui/profile/profile_screen.dart';

class AppRoutes {
  AppRoutes._();

  static const String splash         = '/';
  static const String login          = '/login';
  static const String register       = '/register';
  static const String forgotPassword = '/forgot-password';
  static const String resetPassword  = '/reset-password';
  static const String shell          = '/dashboard';
  static const String dashboard      = '/dashboard';
  static const String transactions   = '/transactions';
  static const String addIncome      = '/add-income';
  static const String addExpense     = '/add-expense';
  static const String budget         = '/budget';
  static const String addBudget      = '/add-budget';
  static const String reports        = '/reports';
  static const String insights       = '/insights';
  static const String goals          = '/goals';
  static const String addGoal        = '/add-goal';
  static const String guardian       = '/guardian';
  static const String helbPlanner    = '/helb-planner';
  static const String mpesaImport    = '/mpesa-import';
  static const String profile        = '/profile';

  static final Map<String, WidgetBuilder> routes = {
    splash:         (_) => const SplashScreen(),
    login:          (_) => const LoginScreen(),
    register:       (_) => const RegisterScreen(),
    forgotPassword: (_) => const ForgotPasswordScreen(),
    resetPassword:  (_) => const ResetPasswordScreen(),
    dashboard:      (_) => const MainShell(),
    transactions:   (_) => const TransactionsScreen(),
    addIncome:      (_) => const AddIncomeScreen(),
    addExpense:     (_) => const AddExpenseScreen(),
    budget:         (_) => const BudgetScreen(),
    addBudget:      (_) => const AddBudgetScreen(),
    reports:        (_) => const ReportsScreen(),
    insights:       (_) => const InsightsScreen(),
    goals:          (_) => const GoalsScreen(),
    addGoal:        (_) => const AddGoalScreen(),
    guardian:       (_) => const GuardianScreen(),
    helbPlanner:    (_) => const HelbPlannerScreen(),
    mpesaImport:    (_) => const MpesaImportScreen(),
    profile:        (_) => const ProfileScreen(),
  };
}