// lib/ui/auth/reset_password_screen.dart
// Step 2 of the password reset flow.
// The student enters:
//   - The email they requested the code for
//   - The 6-digit code from their email
//   - A new password (with confirmation)
// On success, shows a confirmation view and routes back to Login.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/routes.dart';
import 'package:frontend/core/theme.dart';
import 'package:frontend/providers/auth_provider.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _emailController   = TextEditingController();
  final _codeController    = TextEditingController();
  final _newPassController = TextEditingController();
  final _confirmController = TextEditingController();
  bool  _obscureNew        = true;
  bool  _obscureConfirm    = true;
  bool  _success           = false;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _newPassController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _submit() async {
    final email   = _emailController.text.trim();
    final code    = _codeController.text.trim();
    final newPass = _newPassController.text;
    final confirm = _confirmController.text;

    // Client-side validation before hitting the backend
    if (email.isEmpty || !email.contains('@')) {
      _snack('Please enter the email address you used to request the code.');
      return;
    }
    if (code.length != 6) {
      _snack('Please enter the full 6-digit code from your email.');
      return;
    }
    if (newPass.length < 6) {
      _snack('New password must be at least 6 characters.');
      return;
    }
    if (newPass != confirm) {
      _snack('Passwords do not match. Please check and try again.');
      return;
    }

    final auth = context.read<AuthProvider>();
    final ok   = await auth.resetPassword(email, code, newPass);

    if (!mounted) return;
    if (ok) {
      setState(() => _success = true);
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
        title: const Text('Reset Password'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: _success ? _buildSuccess() : _buildForm(auth),
      ),
    );
  }

  // ── Form view ─────────────────────────────────────────────────────────────

  Widget _buildForm(AuthProvider auth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        const Icon(Icons.lock_open, size: 56, color: AppTheme.primary),
        const SizedBox(height: 10),
        const Text(
          'Enter your reset code and choose a new password.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black54, fontSize: 14),
        ),
        const SizedBox(height: 28),

        // ── Email ───────────────────────────────────────────────────────────
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email Address',
            hintText: 'Same email used to request the code',
            prefixIcon: Icon(Icons.email_outlined),
            border: OutlineInputBorder(),
          ),
        ),

        const SizedBox(height: 16),

        // ── 6-digit code ────────────────────────────────────────────────────
        TextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: '6-Digit Reset Code',
            hintText: 'From your email',
            prefixIcon: Icon(Icons.pin_outlined),
            border: OutlineInputBorder(),
            counterText: '',   // hide the character counter Flutter adds
          ),
        ),

        const SizedBox(height: 16),

        // ── New password ────────────────────────────────────────────────────
        TextField(
          controller: _newPassController,
          obscureText: _obscureNew,
          decoration: InputDecoration(
            labelText: 'New Password',
            helperText: 'At least 6 characters',
            prefixIcon: const Icon(Icons.lock_outline),
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon:
                  Icon(_obscureNew ? Icons.visibility_off : Icons.visibility),
              onPressed: () =>
                  setState(() => _obscureNew = !_obscureNew),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // ── Confirm new password ────────────────────────────────────────────
        TextField(
          controller: _confirmController,
          obscureText: _obscureConfirm,
          decoration: InputDecoration(
            labelText: 'Confirm New Password',
            prefixIcon: const Icon(Icons.lock_outline),
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(
                  _obscureConfirm ? Icons.visibility_off : Icons.visibility),
              onPressed: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
            ),
          ),
        ),

        const SizedBox(height: 28),

        // ── Submit button ───────────────────────────────────────────────────
        ElevatedButton(
          onPressed: auth.isLoading ? null : _submit,
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
                  'Reset Password',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
        ),

        const SizedBox(height: 12),

        // ── Back / request new code ─────────────────────────────────────────
        TextButton(
          onPressed: () =>
              Navigator.pushReplacementNamed(context, AppRoutes.forgotPassword),
          child: const Text("Didn't receive a code? Request again"),
        ),
      ],
    );
  }

  // ── Success view ──────────────────────────────────────────────────────────

  Widget _buildSuccess() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 60),
        const Icon(Icons.check_circle, size: 88, color: Colors.green),
        const SizedBox(height: 24),
        const Text(
          'Password Reset Successful!',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Text(
          'Your password has been updated.\n'
          'You can now log in with your new password.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black54, fontSize: 14),
        ),
        const SizedBox(height: 40),
        ElevatedButton(
          onPressed: () => Navigator.pushNamedAndRemoveUntil(
            context,
            AppRoutes.login,
            (route) => false,   // clear the entire back stack
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text(
            'Go to Login',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      ],
    );
  }
}