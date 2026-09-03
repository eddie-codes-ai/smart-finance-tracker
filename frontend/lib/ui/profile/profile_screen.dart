// lib/ui/profile/profile_screen.dart
// UPDATED: Full dark mode support.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/device_timezone.dart';
import '../../core/theme.dart';
import '../../data/remote/api_client.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _usernameExpanded = false;
  bool _emailExpanded    = false;
  bool _passwordExpanded = false;
  bool _timezoneExpanded = false;

  // Time zone picker. The full list comes from the server so it can never
  // offer a name the backend would reject.
  final _zoneSearchCtrl  = TextEditingController();
  List<String> _allZones = const [];
  String? _deviceZone;
  bool _loadingZones     = false;
  bool _savingTimezone   = false;

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
  void initState() {
    super.initState();
    // Cheap and offline — read it up front so the section can immediately say
    // whether the saved zone still matches the device.
    DeviceTimezone.current().then((zone) {
      if (mounted) setState(() => _deviceZone = zone);
    });
  }

  @override
  void dispose() {
    _usernameCtrl.dispose(); _emailCtrl.dispose();
    _currentPasswordCtrl.dispose(); _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose(); _deletePasswordCtrl.dispose();
    _zoneSearchCtrl.dispose();
    super.dispose();
  }

  /// Fetch the accepted zone list the first time the section is opened.
  Future<void> _loadZones() async {
    if (_allZones.isNotEmpty || _loadingZones) return;
    setState(() => _loadingZones = true);
    try {
      final data = await ApiClient.getTimezones();
      final zones = (data['timezones'] as List).cast<String>();
      if (mounted) setState(() { _allZones = zones; _loadingZones = false; });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loadingZones = false);
      _showSnackBar(e.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingZones = false);
      _showSnackBar('Could not load the time zone list.', isError: true);
    }
  }

  Future<void> _saveTimezone(String zone) async {
    setState(() => _savingTimezone = true);
    final auth = context.read<AuthProvider>();
    final success = await auth.updateProfile(timezone: zone);
    if (!mounted) return;
    setState(() => _savingTimezone = false);
    if (success) {
      _zoneSearchCtrl.clear();
      setState(() => _timezoneExpanded = false);
      _showSnackBar('Time zone set to $zone.');
    } else {
      _showSnackBar(auth.error ?? 'Failed to update the time zone.', isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.error : AppTheme.success,
        behavior: SnackBarBehavior.floating));
  }

  Future<void> _saveUsername() async {
    final newUsername = _usernameCtrl.text.trim();
    if (newUsername.isEmpty) { _showSnackBar('Please enter a new username.', isError: true); return; }
    setState(() => _savingUsername = true);
    final auth = context.read<AuthProvider>();
    final success = await auth.updateProfile(username: newUsername);
    if (!mounted) return;
    setState(() => _savingUsername = false);
    if (success) { _usernameCtrl.clear(); setState(() => _usernameExpanded = false); _showSnackBar('Username updated successfully.'); }
    else { _showSnackBar(auth.error ?? 'Failed to update username.', isError: true); }
  }

  Future<void> _saveEmail() async {
    final newEmail = _emailCtrl.text.trim();
    if (newEmail.isEmpty) { _showSnackBar('Please enter an email address.', isError: true); return; }
    if (!newEmail.contains('@') || !newEmail.contains('.')) { _showSnackBar('Please enter a valid email address.', isError: true); return; }
    setState(() => _savingEmail = true);
    final auth = context.read<AuthProvider>();
    final success = await auth.updateProfile(email: newEmail);
    if (!mounted) return;
    setState(() => _savingEmail = false);
    if (success) { _emailCtrl.clear(); setState(() => _emailExpanded = false); _showSnackBar('Email updated successfully.'); }
    else { _showSnackBar(auth.error ?? 'Failed to update email.', isError: true); }
  }

  Future<void> _savePassword() async {
    final currentPassword = _currentPasswordCtrl.text;
    final newPassword     = _newPasswordCtrl.text;
    final confirmPassword = _confirmPasswordCtrl.text;
    if (currentPassword.isEmpty) { _showSnackBar('Please enter your current password.', isError: true); return; }
    if (newPassword.isEmpty) { _showSnackBar('Please enter a new password.', isError: true); return; }
    if (newPassword.length < 6) { _showSnackBar('New password must be at least 6 characters.', isError: true); return; }
    if (newPassword != confirmPassword) { _showSnackBar('New passwords do not match.', isError: true); return; }
    setState(() => _savingPassword = true);
    final auth = context.read<AuthProvider>();
    final success = await auth.updateProfile(newPassword: newPassword, currentPassword: currentPassword);
    if (!mounted) return;
    setState(() => _savingPassword = false);
    if (success) {
      _currentPasswordCtrl.clear(); _newPasswordCtrl.clear(); _confirmPasswordCtrl.clear();
      setState(() => _passwordExpanded = false); _showSnackBar('Password changed successfully.');
    } else { _showSnackBar(auth.error ?? 'Failed to change password.', isError: true); }
  }

  Future<void> _requestDeletion() async {
    final password = _deletePasswordCtrl.text.trim();
    if (password.isEmpty) { _showSnackBar('Please enter your password to confirm.', isError: true); return; }
    setState(() => _requestingDelete = true);
    final auth = context.read<AuthProvider>();
    final success = await auth.requestDeletion(password: password);
    if (!mounted) return;
    setState(() => _requestingDelete = false);
    _deletePasswordCtrl.clear();
    if (success) { _showSnackBar('Account scheduled for deletion. You have 96 hours to cancel.'); }
    else { _showSnackBar(auth.error ?? 'Failed to schedule deletion.', isError: true); }
  }

  Future<void> _cancelDeletion() async {
    setState(() => _cancellingDelete = true);
    final auth = context.read<AuthProvider>();
    final success = await auth.cancelDeletion();
    if (!mounted) return;
    setState(() => _cancellingDelete = false);
    if (success) { _showSnackBar('Account deletion cancelled. Your account is safe!'); }
    else { _showSnackBar(auth.error ?? 'Failed to cancel deletion.', isError: true); }
  }

  void _showDeleteConfirmDialog() {
    _deletePasswordCtrl.clear();
    showDialog(context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Text('Delete Account', style: TextStyle(color: Colors.red)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('This will permanently delete your account and ALL your data.\n\nYou have 96 hours to cancel after requesting deletion.',
                style: TextStyle(fontSize: 14)),
            const SizedBox(height: 16),
            const Text('Enter your password to confirm:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            StatefulBuilder(builder: (context, setDialogState) => TextField(
              controller: _deletePasswordCtrl,
              obscureText: !_showDeletePass,
              decoration: InputDecoration(
                hintText: 'Your password', prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_showDeletePass ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setDialogState(() => _showDeletePass = !_showDeletePass),
                ),
              ),
            )),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(onPressed: () { Navigator.pop(ctx); _requestDeletion(); },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Schedule Deletion')),
          ],
        ));
  }

  @override
  Widget build(BuildContext context) {
    final auth          = context.watch<AuthProvider>();
    final user          = auth.user;
    final themeProvider = context.watch<ThemeProvider>();
    final cs            = Theme.of(context).colorScheme;
    final divider       = Theme.of(context).dividerColor;

    return Scaffold(
      appBar: AppBar(title: const Text('Account Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (auth.pendingDeletion) ...[_buildDeletionBanner(auth), const SizedBox(height: 16)],

          _buildInfoCard(user),
          const SizedBox(height: 24),

          // ── Section label ─────────────────────────────────────────────────
          Text('UPDATE YOUR DETAILS', style: TextStyle(fontSize: 12,
              fontWeight: FontWeight.w700, color: cs.onSurface.withOpacity(0.5), letterSpacing: 1.2)),
          const SizedBox(height: 12),

          _buildSection(icon: Icons.person_outline, title: 'Change Username',
              subtitle: user?.username ?? '', expanded: _usernameExpanded,
              onToggle: () => setState(() {
                _usernameExpanded = !_usernameExpanded;
                _emailExpanded = false; _passwordExpanded = false;
              }),
              child: _buildUsernameForm()),
          const SizedBox(height: 12),

          _buildSection(icon: Icons.email_outlined, title: 'Change Email',
              subtitle: user?.email ?? 'Not set — add one for password recovery',
              expanded: _emailExpanded,
              onToggle: () => setState(() {
                _emailExpanded = !_emailExpanded;
                _usernameExpanded = false; _passwordExpanded = false;
              }),
              child: _buildEmailForm(user?.email)),
          const SizedBox(height: 12),

          _buildSection(icon: Icons.lock_outline, title: 'Change Password',
              subtitle: 'Update your login password', expanded: _passwordExpanded,
              onToggle: () => setState(() {
                _passwordExpanded = !_passwordExpanded;
                _usernameExpanded = false; _emailExpanded = false;
                _timezoneExpanded = false;
              }),
              child: _buildPasswordForm()),
          const SizedBox(height: 12),

          _buildSection(icon: Icons.public, title: 'Time Zone',
              subtitle: user?.timezone ?? 'Africa/Nairobi',
              expanded: _timezoneExpanded,
              onToggle: () {
                setState(() {
                  _timezoneExpanded = !_timezoneExpanded;
                  _usernameExpanded = false; _emailExpanded = false;
                  _passwordExpanded = false;
                });
                if (_timezoneExpanded) _loadZones();
              },
              child: _buildTimezoneForm(user?.timezone ?? 'Africa/Nairobi')),

          const SizedBox(height: 32),

          // ── Appearance ────────────────────────────────────────────────────
          Text('APPEARANCE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
              color: cs.onSurface.withOpacity(0.5), letterSpacing: 1.2)),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surface, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: divider),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.palette_outlined, color: AppTheme.primary, size: 22),
                  const SizedBox(width: 12),
                  Text('Theme', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: cs.onSurface)),
                ]),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: _themeOption(label: 'Light', icon: Icons.light_mode_outlined,
                      selected: themeProvider.isLight, onTap: () => themeProvider.setTheme(ThemeMode.light))),
                  const SizedBox(width: 8),
                  Expanded(child: _themeOption(label: 'Dark', icon: Icons.dark_mode_outlined,
                      selected: themeProvider.isDark, onTap: () => themeProvider.setTheme(ThemeMode.dark))),
                  const SizedBox(width: 8),
                  Expanded(child: _themeOption(label: 'System', icon: Icons.phone_android_outlined,
                      selected: themeProvider.isSystem, onTap: () => themeProvider.setTheme(ThemeMode.system))),
                ]),
              ],
            ),
          ),

          const SizedBox(height: 32),

          if (user != null)
            Center(child: Text('Member since ${_formatDate(user.createdAt)}',
                style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.5)))),

          const SizedBox(height: 32),

          // ── Danger Zone ───────────────────────────────────────────────────
          if (!auth.pendingDeletion) ...[
            const Divider(),
            const SizedBox(height: 16),
            const Text('DANGER ZONE', style: TextStyle(fontSize: 12,
                fontWeight: FontWeight.w700, color: Colors.red, letterSpacing: 1.2)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.04), borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withOpacity(0.2)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.delete_forever_outlined, color: Colors.red, size: 20),
                  SizedBox(width: 8),
                  Text('Delete Account', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Colors.red)),
                ]),
                const SizedBox(height: 8),
                Text('Permanently delete your account and all data. You will have 96 hours to cancel after requesting deletion.',
                    style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.6))),
                const SizedBox(height: 16),
                SizedBox(width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _requestingDelete ? null : _showDeleteConfirmDialog,
                      icon: _requestingDelete
                          ? const SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red))
                          : const Icon(Icons.delete_outline, color: Colors.red),
                      label: Text(_requestingDelete ? 'Processing...' : 'Delete My Account',
                          style: const TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 12)),
                    )),
              ]),
            ),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }

  Widget _themeOption({
    required String label, required IconData icon,
    required bool selected, required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    final divider = Theme.of(context).dividerColor;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? AppTheme.primary : divider, width: selected ? 1.5 : 1),
        ),
        child: Column(children: [
          Icon(icon, size: 22, color: selected ? AppTheme.primary : cs.onSurface.withOpacity(0.5)),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
              color: selected ? AppTheme.primary : cs.onSurface.withOpacity(0.5))),
        ]),
      ),
    );
  }

  Widget _buildDeletionBanner(AuthProvider auth) {
    final cs = Theme.of(context).colorScheme;
    String dueDateStr = '';
    if (auth.deletionDueAt != null) {
      try {
        final dt = DateTime.parse(auth.deletionDueAt!).toLocal();
        dueDateStr = '${dt.day} ${_monthName(dt.month)} ${dt.year} at ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) { dueDateStr = auth.deletionDueAt!; }
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.red.withOpacity(0.08), borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.withOpacity(0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
          SizedBox(width: 8),
          Text('Account Deletion Scheduled',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Colors.red)),
        ]),
        const SizedBox(height: 8),
        Text(dueDateStr.isNotEmpty
            ? 'Your account will be permanently deleted on $dueDateStr. Cancel below to keep it.'
            : 'Your account is scheduled for deletion. Cancel below to keep it.',
            style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.6))),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _cancellingDelete ? null : _cancelDeletion,
              icon: _cancellingDelete
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.undo),
              label: Text(_cancellingDelete ? 'Cancelling...' : 'Cancel Deletion — Keep My Account'),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success,
                  padding: const EdgeInsets.symmetric(vertical: 12)),
            )),
      ]),
    );
  }

  Widget _buildInfoCard(user) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [AppTheme.primary, AppTheme.primary.withOpacity(0.75)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        CircleAvatar(radius: 30, backgroundColor: Colors.white.withOpacity(0.2),
            child: Text((user?.username ?? '?')[0].toUpperCase(),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white))),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(user?.username ?? 'Unknown',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 4),
          Text(user?.email ?? 'No email set',
              style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.85))),
        ])),
      ]),
    );
  }

  Widget _buildSection({
    required IconData icon, required String title, required String subtitle,
    required bool expanded, required VoidCallback onToggle, required Widget child,
  }) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: cs.surface, borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: expanded ? AppTheme.primary.withOpacity(0.4) : Colors.transparent, width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(children: [
        InkWell(
          onTap: onToggle, borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Icon(icon, color: AppTheme.primary, size: 22),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: cs.onSurface)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6)),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              Icon(expanded ? Icons.expand_less : Icons.expand_more,
                  color: cs.onSurface.withOpacity(0.5)),
            ]),
          ),
        ),
        if (expanded) ...[
          const Divider(height: 1),
          Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 20), child: child),
        ],
      ]),
    );
  }

  Widget _buildTimezoneForm(String currentZone) {
    final cs      = Theme.of(context).colorScheme;
    final divider = Theme.of(context).dividerColor;
    final query   = _zoneSearchCtrl.text.trim().toLowerCase();

    final matches = query.isEmpty
        ? _allZones
        : _allZones.where((z) => z.toLowerCase().contains(query)).toList();
    // The full list is ~600 entries; showing every match while someone types
    // would rebuild a very long list on each keystroke for no benefit.
    final shown = matches.take(60).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
        'Your months and daily spending are grouped using this zone. It stays '
        'fixed when you travel, so past months never change.',
        style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6)),
      ),
      const SizedBox(height: 14),

      // ── Device shortcut ─────────────────────────────────────────────────
      if (_deviceZone != null && _deviceZone != currentZone) ...[
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.info.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.info.withOpacity(0.35)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Icon(Icons.phone_android, size: 17, color: AppTheme.info),
              const SizedBox(width: 8),
              Expanded(child: Text('Your device says ${_deviceZone!}',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurface))),
            ]),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _savingTimezone ? null : () => _saveTimezone(_deviceZone!),
              child: const Text("Use my device's time zone"),
            ),
          ]),
        ),
        const SizedBox(height: 16),
      ] else if (_deviceZone != null) ...[
        Row(children: [
          const Icon(Icons.check_circle_outline, size: 16, color: AppTheme.success),
          const SizedBox(width: 8),
          Expanded(child: Text('Matches your device.',
              style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6)))),
        ]),
        const SizedBox(height: 16),
      ],

      // ── Search ──────────────────────────────────────────────────────────
      TextField(
        controller: _zoneSearchCtrl,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: 'Search time zones',
          hintText: 'e.g. Nairobi, Toronto, London',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _zoneSearchCtrl.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() => _zoneSearchCtrl.clear()),
                ),
        ),
      ),
      const SizedBox(height: 12),

      if (_loadingZones)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        )
      else if (_allZones.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text('Time zone list unavailable. Check your connection.',
              style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
        )
      else if (shown.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text('No time zone matches "${_zoneSearchCtrl.text.trim()}".',
              style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
        )
      else
        Container(
          constraints: const BoxConstraints(maxHeight: 260),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: divider),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: shown.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: divider),
            itemBuilder: (_, i) {
              final zone     = shown[i];
              final selected = zone == currentZone;
              return ListTile(
                dense: true,
                title: Text(zone, style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    color: selected ? AppTheme.primary : cs.onSurface)),
                trailing: selected
                    ? const Icon(Icons.check, size: 18, color: AppTheme.primary)
                    : null,
                onTap: (_savingTimezone || selected) ? null : () => _saveTimezone(zone),
              );
            },
          ),
        ),

      if (matches.length > shown.length) ...[
        const SizedBox(height: 8),
        Text('${matches.length - shown.length} more — keep typing to narrow it down.',
            style: TextStyle(fontSize: 11.5, color: cs.onSurface.withOpacity(0.5))),
      ],

      if (_savingTimezone) ...[
        const SizedBox(height: 14),
        const Center(child: SizedBox(
            height: 20, width: 20,
            child: CircularProgressIndicator(strokeWidth: 2))),
      ],
    ]);
  }

  Widget _buildUsernameForm() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(controller: _usernameCtrl, textInputAction: TextInputAction.done,
          decoration: const InputDecoration(labelText: 'New Username',
              hintText: 'Enter a new username', prefixIcon: Icon(Icons.person_outline)),
          onSubmitted: (_) => _saveUsername()),
      const SizedBox(height: 16),
      ElevatedButton(onPressed: _savingUsername ? null : _saveUsername,
          child: _savingUsername
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Save Username')),
    ]);
  }

  Widget _buildEmailForm(String? currentEmail) {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (currentEmail == null || currentEmail.isEmpty)
        Container(
          padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: AppTheme.warning.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.warning.withOpacity(0.4))),
          child: Row(children: [
            Icon(Icons.warning_amber_outlined, color: AppTheme.warning, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('No email set. Add one to enable password recovery.',
                style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6)))),
          ]),
        ),
      TextField(controller: _emailCtrl, keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(labelText: 'Email Address',
              hintText: 'Enter your email address', prefixIcon: Icon(Icons.email_outlined)),
          onSubmitted: (_) => _saveEmail()),
      const SizedBox(height: 16),
      ElevatedButton(onPressed: _savingEmail ? null : _saveEmail,
          child: _savingEmail
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Save Email')),
    ]);
  }

  Widget _buildPasswordForm() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(controller: _currentPasswordCtrl, obscureText: !_showCurrent,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(labelText: 'Current Password', prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(icon: Icon(_showCurrent ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _showCurrent = !_showCurrent)))),
      const SizedBox(height: 12),
      TextField(controller: _newPasswordCtrl, obscureText: !_showNew,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(labelText: 'New Password', hintText: 'Minimum 6 characters',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(icon: Icon(_showNew ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _showNew = !_showNew)))),
      const SizedBox(height: 12),
      TextField(controller: _confirmPasswordCtrl, obscureText: !_showConfirm,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(labelText: 'Confirm New Password', prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(icon: Icon(_showConfirm ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _showConfirm = !_showConfirm))),
          onSubmitted: (_) => _savePassword()),
      const SizedBox(height: 16),
      ElevatedButton(onPressed: _savingPassword ? null : _savePassword,
          child: _savingPassword
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Change Password')),
    ]);
  }

  String _formatDate(String isoDate) {
    try { final dt = DateTime.parse(isoDate).toLocal(); return '${_monthName(dt.month)} ${dt.year}'; }
    catch (_) { return isoDate; }
  }

  String _monthName(int month) {
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month];
  }
}