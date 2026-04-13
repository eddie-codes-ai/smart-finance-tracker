// lib/ui/profile/profile_screen.dart
// Account settings screen — edit username, email, password.
// UPDATED: Added Danger Zone section with 96-hour account deletion,
// and a pending deletion banner when deletion has been requested.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {

  bool _usernameExpanded = false;
  bool _emailExpanded    = false;
  bool _passwordExpanded = false;

  final _usernameCtrl        = TextEditingController();
  final _emailCtrl           = TextEditingController();
  final _currentPasswordCtrl = TextEditingController();
  final _newPasswordCtrl     = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _deletePasswordCtrl  = TextEditingController();

  bool _showCurrent      = false;
  bool _showNew          = false;
  bool _showConfirm      = false;
  bool _showDeletePass   = false;

  bool _savingUsername   = false;
  bool _savingEmail      = false;
  bool _savingPassword   = false;
  bool _requestingDelete = false;
  bool _cancellingDelete = false;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _currentPasswordCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _deletePasswordCtrl.dispose();
    super.dispose();
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.error : AppTheme.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Save handlers ─────────────────────────────────────────────────────────

  Future<void> _saveUsername() async {
    final newUsername = _usernameCtrl.text.trim();
    if (newUsername.isEmpty) {
      _showSnackBar('Please enter a new username.', isError: true);
      return;
    }
    setState(() => _savingUsername = true);
    final auth    = context.read<AuthProvider>();
    final success = await auth.updateProfile(username: newUsername);
    if (!mounted) return;
    setState(() => _savingUsername = false);
    if (success) {
      _usernameCtrl.clear();
      setState(() => _usernameExpanded = false);
      _showSnackBar('Username updated successfully.');
    } else {
      _showSnackBar(auth.error ?? 'Failed to update username.', isError: true);
    }
  }

  Future<void> _saveEmail() async {
    final newEmail = _emailCtrl.text.trim();
    if (newEmail.isEmpty) {
      _showSnackBar('Please enter an email address.', isError: true);
      return;
    }
    if (!newEmail.contains('@') || !newEmail.contains('.')) {
      _showSnackBar('Please enter a valid email address.', isError: true);
      return;
    }
    setState(() => _savingEmail = true);
    final auth    = context.read<AuthProvider>();
    final success = await auth.updateProfile(email: newEmail);
    if (!mounted) return;
    setState(() => _savingEmail = false);
    if (success) {
      _emailCtrl.clear();
      setState(() => _emailExpanded = false);
      _showSnackBar('Email updated successfully.');
    } else {
      _showSnackBar(auth.error ?? 'Failed to update email.', isError: true);
    }
  }

  Future<void> _savePassword() async {
    final currentPassword = _currentPasswordCtrl.text;
    final newPassword     = _newPasswordCtrl.text;
    final confirmPassword = _confirmPasswordCtrl.text;
    if (currentPassword.isEmpty) {
      _showSnackBar('Please enter your current password.', isError: true); return;
    }
    if (newPassword.isEmpty) {
      _showSnackBar('Please enter a new password.', isError: true); return;
    }
    if (newPassword.length < 6) {
      _showSnackBar('New password must be at least 6 characters.', isError: true); return;
    }
    if (newPassword != confirmPassword) {
      _showSnackBar('New passwords do not match.', isError: true); return;
    }
    setState(() => _savingPassword = true);
    final auth    = context.read<AuthProvider>();
    final success = await auth.updateProfile(
      newPassword: newPassword, currentPassword: currentPassword);
    if (!mounted) return;
    setState(() => _savingPassword = false);
    if (success) {
      _currentPasswordCtrl.clear();
      _newPasswordCtrl.clear();
      _confirmPasswordCtrl.clear();
      setState(() => _passwordExpanded = false);
      _showSnackBar('Password changed successfully.');
    } else {
      _showSnackBar(auth.error ?? 'Failed to change password.', isError: true);
    }
  }

  // ── Deletion handlers ─────────────────────────────────────────────────────

  Future<void> _requestDeletion() async {
    final password = _deletePasswordCtrl.text.trim();
    if (password.isEmpty) {
      _showSnackBar('Please enter your password to confirm.', isError: true);
      return;
    }
    setState(() => _requestingDelete = true);
    final auth    = context.read<AuthProvider>();
    final success = await auth.requestDeletion(password: password);
    if (!mounted) return;
    setState(() => _requestingDelete = false);
    _deletePasswordCtrl.clear();
    if (success) {
      _showSnackBar('Account scheduled for deletion. You have 96 hours to cancel.');
    } else {
      _showSnackBar(auth.error ?? 'Failed to schedule deletion.', isError: true);
    }
  }

  Future<void> _cancelDeletion() async {
    setState(() => _cancellingDelete = true);
    final auth    = context.read<AuthProvider>();
    final success = await auth.cancelDeletion();
    if (!mounted) return;
    setState(() => _cancellingDelete = false);
    if (success) {
      _showSnackBar('Account deletion cancelled. Your account is safe!');
    } else {
      _showSnackBar(auth.error ?? 'Failed to cancel deletion.', isError: true);
    }
  }

  void _showDeleteConfirmDialog() {
    _deletePasswordCtrl.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Text('Delete Account', style: TextStyle(color: Colors.red)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This will permanently delete your account and ALL your data including transactions, goals, budgets, and contributions.\n\nYou have 96 hours to cancel after requesting deletion.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            const Text(
              'Enter your password to confirm:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 8),
            StatefulBuilder(
              builder: (context, setDialogState) => TextField(
                controller: _deletePasswordCtrl,
                obscureText: !_showDeletePass,
                decoration: InputDecoration(
                  hintText: 'Your password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_showDeletePass
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () => setDialogState(
                        () => _showDeletePass = !_showDeletePass),
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _requestDeletion();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Schedule Deletion'),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    return Scaffold(
      appBar: AppBar(title: const Text('Account Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // ── Pending deletion banner ───────────────────────────────────────
          if (auth.pendingDeletion) ...[
            _buildDeletionBanner(auth),
            const SizedBox(height: 16),
          ],

          // ── Account info card ─────────────────────────────────────────────
          _buildInfoCard(user),
          const SizedBox(height: 24),

          // ── Section label ─────────────────────────────────────────────────
          const Text(
            'UPDATE YOUR DETAILS',
            style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700,
              color: AppTheme.textSecondary, letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),

          // ── Edit Username ─────────────────────────────────────────────────
          _buildSection(
            icon: Icons.person_outline, title: 'Change Username',
            subtitle: user?.username ?? '', expanded: _usernameExpanded,
            onToggle: () => setState(() {
              _usernameExpanded = !_usernameExpanded;
              _emailExpanded = false; _passwordExpanded = false;
            }),
            child: _buildUsernameForm(),
          ),
          const SizedBox(height: 12),

          // ── Edit Email ────────────────────────────────────────────────────
          _buildSection(
            icon: Icons.email_outlined, title: 'Change Email',
            subtitle: user?.email ?? 'Not set — add one for password recovery',
            expanded: _emailExpanded,
            onToggle: () => setState(() {
              _emailExpanded = !_emailExpanded;
              _usernameExpanded = false; _passwordExpanded = false;
            }),
            child: _buildEmailForm(user?.email),
          ),
          const SizedBox(height: 12),

          // ── Change Password ───────────────────────────────────────────────
          _buildSection(
            icon: Icons.lock_outline, title: 'Change Password',
            subtitle: 'Update your login password', expanded: _passwordExpanded,
            onToggle: () => setState(() {
              _passwordExpanded = !_passwordExpanded;
              _usernameExpanded = false; _emailExpanded = false;
            }),
            child: _buildPasswordForm(),
          ),

          const SizedBox(height: 32),

          // ── Member since footer ───────────────────────────────────────────
          if (user != null)
            Center(
              child: Text(
                'Member since ${_formatDate(user.createdAt)}',
                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ),

          const SizedBox(height: 32),

          // ── Danger Zone ───────────────────────────────────────────────────
          if (!auth.pendingDeletion) ...[
            const Divider(),
            const SizedBox(height: 16),
            const Text(
              'DANGER ZONE',
              style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700,
                color: Colors.red, letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.delete_forever_outlined,
                          color: Colors.red, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Delete Account',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: Colors.red),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Permanently delete your account and all associated data. '
                    'You will have 96 hours to cancel after requesting deletion.',
                    style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _requestingDelete ? null : _showDeleteConfirmDialog,
                      icon: _requestingDelete
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.red))
                          : const Icon(Icons.delete_outline, color: Colors.red),
                      label: Text(
                        _requestingDelete ? 'Processing...' : 'Delete My Account',
                        style: const TextStyle(color: Colors.red),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }

  // ── Pending deletion banner ───────────────────────────────────────────────
  Widget _buildDeletionBanner(AuthProvider auth) {
    String dueDateStr = '';
    if (auth.deletionDueAt != null) {
      try {
        final dt = DateTime.parse(auth.deletionDueAt!).toLocal();
        dueDateStr = '${dt.day} ${_monthName(dt.month)} ${dt.year} at ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {
        dueDateStr = auth.deletionDueAt!;
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
              SizedBox(width: 8),
              Text(
                'Account Deletion Scheduled',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Colors.red),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            dueDateStr.isNotEmpty
                ? 'Your account and all data will be permanently deleted on $dueDateStr. Cancel below to keep your account.'
                : 'Your account is scheduled for deletion. Cancel below to keep your account.',
            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _cancellingDelete ? null : _cancelDeletion,
              icon: _cancellingDelete
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.undo),
              label: Text(_cancellingDelete
                  ? 'Cancelling...'
                  : 'Cancel Deletion — Keep My Account'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.success,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Reusable widgets ──────────────────────────────────────────────────────

  Widget _buildInfoCard(user) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primary, AppTheme.primary.withOpacity(0.75)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: Colors.white.withOpacity(0.2),
            child: Text(
              (user?.username ?? '?')[0].toUpperCase(),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user?.username ?? 'Unknown',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                const SizedBox(height: 4),
                Text(user?.email ?? 'No email set',
                    style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.85))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required IconData icon, required String title,
    required String subtitle, required bool expanded,
    required VoidCallback onToggle, required Widget child,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: expanded ? AppTheme.primary.withOpacity(0.4) : Colors.transparent,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(icon, color: AppTheme.primary, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                        const SizedBox(height: 2),
                        Text(subtitle, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  Icon(expanded ? Icons.expand_less : Icons.expand_more, color: AppTheme.textSecondary),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const Divider(height: 1),
            Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 20), child: child),
          ],
        ],
      ),
    );
  }

  Widget _buildUsernameForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _usernameCtrl,
          decoration: const InputDecoration(
              labelText: 'New Username', hintText: 'Enter a new username',
              prefixIcon: Icon(Icons.person_outline)),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _saveUsername(),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _savingUsername ? null : _saveUsername,
          child: _savingUsername
              ? const SizedBox(height: 20, width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Save Username'),
        ),
      ],
    );
  }

  Widget _buildEmailForm(String? currentEmail) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (currentEmail == null || currentEmail.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppTheme.warning.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.warning.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_outlined, color: AppTheme.warning, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('No email set. Add one to enable password recovery.',
                      style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                ),
              ],
            ),
          ),
        TextField(
          controller: _emailCtrl,
          decoration: const InputDecoration(
              labelText: 'Email Address', hintText: 'Enter your email address',
              prefixIcon: Icon(Icons.email_outlined)),
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _saveEmail(),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _savingEmail ? null : _saveEmail,
          child: _savingEmail
              ? const SizedBox(height: 20, width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Save Email'),
        ),
      ],
    );
  }

  Widget _buildPasswordForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _currentPasswordCtrl,
          obscureText: !_showCurrent,
          decoration: InputDecoration(
            labelText: 'Current Password', prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_showCurrent ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _showCurrent = !_showCurrent),
            ),
          ),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _newPasswordCtrl,
          obscureText: !_showNew,
          decoration: InputDecoration(
            labelText: 'New Password', hintText: 'Minimum 6 characters',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_showNew ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _showNew = !_showNew),
            ),
          ),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmPasswordCtrl,
          obscureText: !_showConfirm,
          decoration: InputDecoration(
            labelText: 'Confirm New Password',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_showConfirm ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _showConfirm = !_showConfirm),
            ),
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _savePassword(),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _savingPassword ? null : _savePassword,
          child: _savingPassword
              ? const SizedBox(height: 20, width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Change Password'),
        ),
      ],
    );
  }

  String _formatDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      return '${_monthName(dt.month)} ${dt.year}';
    } catch (_) {
      return isoDate;
    }
  }

  String _monthName(int month) {
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month];
  }
}