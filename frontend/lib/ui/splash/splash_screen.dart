// lib/ui/splash/splash_screen.dart
// First screen the app shows on launch.
// Checks for an existing JWT token and routes accordingly:
//   - Token found → Dashboard (user is already logged in)
//   - No token    → Login screen

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    // Fade-in animation for the logo
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );
    _controller.forward();

    // Check session after the first frame is drawn
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkSession());
  }

  Future<void> _checkSession() async {
    // Wait for animation to finish before navigating
    await Future.delayed(const Duration(milliseconds: 1500));

    if (!mounted) return;

    final auth = context.read<AuthProvider>();
    final hasSession = await auth.restoreSession();

    if (!mounted) return;

    Navigator.pushReplacementNamed(
      context,
      hasSession ? AppRoutes.dashboard : AppRoutes.login,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primary,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // App icon / logo
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  size: 56,
                  color: AppTheme.primary,
                ),
              ),

              const SizedBox(height: 28),

              // App name
              const Text(
                'Smart Finance',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
              const Text(
                'Tracker',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w300,
                  color: Colors.white70,
                  letterSpacing: 0.5,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'Built for JKUAT Students',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white54,
                  letterSpacing: 0.3,
                ),
              ),

              const SizedBox(height: 60),

              // Loading indicator
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white54,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}