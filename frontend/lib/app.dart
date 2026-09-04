// lib/app.dart
// The root widget of the application.
// Sets up Provider (state management), the theme, and the route system.
// UPDATED: ThemeProvider added so the user can switch light/dark/system.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'core/routes.dart';
import 'data/remote/api_client.dart';
import 'ui/lock/app_lock_gate.dart';
import 'providers/auth_provider.dart';
import 'providers/income_provider.dart';
import 'providers/expense_provider.dart';
import 'providers/budget_provider.dart';
import 'providers/goals_provider.dart';
import 'providers/guardian_provider.dart';
import 'providers/analysis_provider.dart';
import 'providers/theme_provider.dart';

/// Lets code outside the widget tree navigate — specifically the API layer,
/// when a session ends and the user has to be returned to sign-in.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  final AuthProvider _auth = AuthProvider();

  @override
  void initState() {
    super.initState();

    // When the refresh token is gone too, the session is genuinely over. Clear
    // it and return to sign-in with an explanation — being dropped on a login
    // screen with no reason given is its own kind of bug.
    ApiClient.onSessionExpired = () async {
      _auth.clearSession();
      final navigator = appNavigatorKey.currentState;
      if (navigator == null) return;
      await navigator.pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
      final messenger = ScaffoldMessenger.maybeOf(appNavigatorKey.currentContext!);
      messenger?.showSnackBar(const SnackBar(
        content: Text('Your session expired. Please sign in again.'),
      ));
    };
  }

  @override
  void dispose() {
    ApiClient.onSessionExpired = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _auth),
        ChangeNotifierProvider(create: (_) => IncomeProvider()),
        ChangeNotifierProvider(create: (_) => ExpenseProvider()),
        ChangeNotifierProvider(create: (_) => BudgetProvider()),
        ChangeNotifierProvider(create: (_) => GoalsProvider()),
        ChangeNotifierProvider(create: (_) => GuardianProvider()),
        ChangeNotifierProvider(create: (_) => AnalysisProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()..loadTheme()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'Smart Finance Tracker',
            navigatorKey: appNavigatorKey,
            debugShowCheckedModeBanner: false,
            theme:      AppTheme.theme,
            darkTheme:  AppTheme.darkTheme,
            themeMode:  themeProvider.themeMode,
            initialRoute: AppRoutes.splash,
            routes: AppRoutes.routes,
            // Wraps every route, so the lock covers the app wherever the user
            // happens to be — including the recent-apps thumbnail.
            builder: (context, child) =>
                AppLockGate(child: child ?? const SizedBox.shrink()),
          );
        },
      ),
    );
  }
}