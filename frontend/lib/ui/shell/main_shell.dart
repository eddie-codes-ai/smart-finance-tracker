// lib/ui/shell/main_shell.dart
// UPDATED: Added person icon to AppBar for navigating to the Profile screen.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../dashboard/dashboard_screen.dart';
import '../transactions/transactions_screen.dart';
import '../budget/budget_screen.dart';
import '../reports/reports_screen.dart';
import '../insights/insights_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    DashboardScreen(),
    TransactionsScreen(),
    BudgetScreen(),
    ReportsScreen(),
    InsightsScreen(),
  ];

  void _onTabTapped(int index) {
    setState(() => _currentIndex = index);
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await context.read<AuthProvider>().logout();
      Navigator.pushReplacementNamed(context, AppRoutes.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_appBarTitle()),
        actions: [
          // Profile / Account Settings
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Account Settings',
            onPressed: () => Navigator.pushNamed(context, AppRoutes.profile),
          ),
          // Guardian shortcut
          IconButton(
            icon: const Icon(Icons.shield_outlined),
            tooltip: 'Guardian',
            onPressed: () => Navigator.pushNamed(context, AppRoutes.guardian),
          ),
          // Logout
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: _confirmLogout,
          ),
        ],
      ),

      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),

      floatingActionButton: _currentIndex <= 1
          ? FloatingActionButton(
              onPressed: _onFabPressed,
              tooltip: _currentIndex == 0 ? 'Add Transaction' : 'Add',
              child: const Icon(Icons.add),
            )
          : null,

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_outlined),
            activeIcon: Icon(Icons.receipt_long),
            label: 'Transactions',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.pie_chart_outline),
            activeIcon: Icon(Icons.pie_chart),
            label: 'Budget',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart_outlined),
            activeIcon: Icon(Icons.bar_chart),
            label: 'Reports',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.lightbulb_outline),
            activeIcon: Icon(Icons.lightbulb),
            label: 'Insights',
          ),
        ],
      ),
    );
  }

  String _appBarTitle() {
    switch (_currentIndex) {
      case 0:  return 'Dashboard';
      case 1:  return 'Transactions';
      case 2:  return 'Budget';
      case 3:  return 'Reports';
      case 4:  return 'Insights';
      default: return 'Smart Finance';
    }
  }

  void _onFabPressed() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Add Transaction',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 20),

            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.arrow_downward, color: AppTheme.success),
              ),
              title: const Text('Add Income', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Log a new income record'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, AppRoutes.addIncome);
              },
            ),
            const SizedBox(height: 8),

            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.arrow_upward, color: AppTheme.error),
              ),
              title: const Text('Add Expense', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Log a new expense record'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, AppRoutes.addExpense);
              },
            ),
            const SizedBox(height: 8),

            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.flag_outlined, color: AppTheme.primary),
              ),
              title: const Text('Add Savings Goal', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Set a new savings target'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, AppRoutes.addGoal);
              },
            ),
            const SizedBox(height: 8),

            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.sms_outlined, color: AppTheme.primary),
              ),
              title: const Text('Import from M-Pesa', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Paste or read SMS automatically'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, AppRoutes.mpesaImport);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}