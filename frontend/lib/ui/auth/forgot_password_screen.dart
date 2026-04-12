// lib/ui/auth/forgot_password_screen.dart
// Step 1 of the password reset flow.
// The student enters their registered email address.
// The backend emails them a 6-digit code (15-minute expiry).
// After submitting, a success view appears with a button to proceed
// to the reset code entry screen (ResetPasswordScreen).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/routes.dart';
import 'package:frontend/core/theme.dart';
import 'package:frontend/providers/auth_provider.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  bool  _submitted       = false;   // true after code is sent

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      _snack('Please enter your email address.');
      return;
    }
    if (!email.contains('@')) {
      _snack('Please enter a valid email address.');
      return;
    }

    final auth = context.read<AuthProvider>();
    final ok   = await auth.forgotPassword(email);

    if (!mounted) return;

    if (ok) {
      setState(() => _submitted = true);
    } else if (auth.error != null) {
      _snack(auth.error!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Forgot Password'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(28),
        child: _submitted ? _buildSuccess() : _buildForm(auth),
      ),
    );
  }

  // ── Form view — enter email ───────────────────────────────────────────────

  Widget _buildForm(AuthProvider auth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        const Icon(
          Icons.lock_reset,
          size: 72,
          color: AppTheme.primary,
        ),
        const SizedBox(height: 16),
        const Text(
          'Forgot your password?',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Enter the email address linked to your account.\n'
          'We will send you a 6-digit reset code.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black54, fontSize: 14),
        ),
        const SizedBox(height: 36),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Email Address',
            hintText: 'e.g. yourname@gmail.com',
            prefixIcon: Icon(Icons.email_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: auth.isLoading ? null : _sendCode,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: auth.isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : const Text(
                  'Send Reset Code',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
        ),
        const SizedBox(height: 12),

        // Already have a code (e.g. they came back to this screen)
        TextButton(
          onPressed: () =>
              Navigator.pushReplacementNamed(context, AppRoutes.resetPassword),
          child: const Text('Already have a code? Enter it here'),
        ),
      ],
    );
  }

  // ── Success view — code has been sent ────────────────────────────────────

  Widget _buildSuccess() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.mark_email_read,
          size: 88,
          color: Colors.green,
        ),
        const SizedBox(height: 24),
        const Text(
          'Check Your Email',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text(
          'A 6-digit reset code has been sent to\n${_emailController.text.trim()}\n\n'
          'Check your inbox and spam folder.\nThe code expires in 15 minutes.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.black54, fontSize: 14),
        ),
        const SizedBox(height: 36),
        ElevatedButton(
          onPressed: () =>
              Navigator.pushReplacementNamed(context, AppRoutes.resetPassword),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text(
            'Enter Reset Code',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => setState(() => _submitted = false),
          child: const Text('Use a different email'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back to Login'),
        ),
      ],
    );
  }
}