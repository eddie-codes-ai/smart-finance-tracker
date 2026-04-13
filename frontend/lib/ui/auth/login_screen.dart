// lib/ui/auth/login_screen.dart
// UPDATED: Full dark mode support.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/routes.dart';
import 'package:frontend/core/theme.dart';
import 'package:frontend/providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      _snack('Please enter your username and password.');
      return;
    }
    final auth = context.read<AuthProvider>();
    final ok   = await auth.login(username, password);
    if (!mounted) return;
    if (ok) {
      Navigator.pushReplacementNamed(context, AppRoutes.dashboard);
    } else if (auth.error != null) {
      _snack(auth.error!);
    }
  }

  Future<void> _signInWithGoogle() async {
    final auth = context.read<AuthProvider>();
    final ok   = await auth.signInWithGoogle();
    if (!mounted) return;
    if (ok) {
      Navigator.pushReplacementNamed(context, AppRoutes.dashboard);
    } else if (auth.error != null) {
      _snack(auth.error!);
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final cs   = Theme.of(context).colorScheme;

    return Scaffold(
      // No backgroundColor — Scaffold uses theme's scaffoldBackgroundColor automatically
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Logo / header ────────────────────────────────────────────
              const SizedBox(height: 24),
              const Icon(Icons.account_balance_wallet, size: 72, color: AppTheme.primary),
              const SizedBox(height: 12),
              const Text(
                'Smart Finance Tracker',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.primary),
              ),
              const SizedBox(height: 6),
              Text(
                'Manage your money. Build your future.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurface.withOpacity(0.45), fontSize: 14),
              ),

              const SizedBox(height: 40),

              // ── Username ─────────────────────────────────────────────────
              TextField(
                controller: _usernameController,
                keyboardType: TextInputType.text,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 16),

              // ── Password ──────────────────────────────────────────────────
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),

              // ── Forgot Password ───────────────────────────────────────────
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pushNamed(context, AppRoutes.forgotPassword),
                  child: const Text('Forgot Password?'),
                ),
              ),

              const SizedBox(height: 4),

              // ── Login button ──────────────────────────────────────────────
              ElevatedButton(
                onPressed: auth.isLoading ? null : _login,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary, padding: const EdgeInsets.symmetric(vertical: 16)),
                child: auth.isLoading
                    ? const SizedBox(height: 20, width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Log In', style: TextStyle(color: Colors.white, fontSize: 16)),
              ),

              const SizedBox(height: 20),

              // ── OR divider ────────────────────────────────────────────────
              Row(children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('OR', style: TextStyle(color: cs.onSurface.withOpacity(0.45), fontSize: 13)),
                ),
                const Expanded(child: Divider()),
              ]),

              const SizedBox(height: 16),

              // ── Google Sign-In ─────────────────────────────────────────────
              OutlinedButton.icon(
                onPressed: auth.isLoading ? null : _signInWithGoogle,
                icon: const Text('G', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF4285F4))),
                label: Text('Sign in with Google',
                    style: TextStyle(color: cs.onSurface.withOpacity(0.87), fontSize: 15)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: cs.onSurface.withOpacity(0.2)),
                  minimumSize: const Size(double.infinity, 0),
                ),
              ),

              const SizedBox(height: 28),

              // ── Register link ─────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text("Don't have an account? ",
                      style: TextStyle(color: cs.onSurface.withOpacity(0.7))),
                  GestureDetector(
                    onTap: () => Navigator.pushNamed(context, AppRoutes.register),
                    child: const Text('Register',
                        style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}