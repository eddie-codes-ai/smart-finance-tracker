// lib/ui/lock/app_lock_gate.dart
//
// Wraps the whole app and covers it when the device has been away, until the
// owner proves who they are.
//
// Two separate jobs, and the second is the one people forget: it blocks the UI
// on resume, AND it hides the content while the app sits in the recent-apps
// switcher, where Android renders a live thumbnail of the last frame. Locking
// only on resume would still leave someone's balance legible in the task list.

import 'package:flutter/material.dart';

import '../../core/app_lock.dart';
import '../../core/theme.dart';

class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _locked = false;
  bool _prompting = false;
  bool _obscured = false;      // covering the recent-apps thumbnail
  DateTime? _leftAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lockOnColdStart();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _lockOnColdStart() async {
    if (await AppLock.isEnabled()) {
      if (!mounted) return;
      setState(() => _locked = true);
      _promptForUnlock();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // Cover the content before the OS screenshots it for the app switcher.
        _leftAt ??= DateTime.now();
        if (!_obscured) setState(() => _obscured = true);
        break;

      case AppLifecycleState.resumed:
        setState(() => _obscured = false);
        _maybeLockOnResume();
        break;

      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _maybeLockOnResume() async {
    final leftAt = _leftAt;
    _leftAt = null;
    if (_locked || leftAt == null) return;

    // A glance at an SMS should not demand a fingerprint on the way back.
    if (DateTime.now().difference(leftAt) < AppLock.graceWindow) return;
    if (!await AppLock.isEnabled()) return;

    if (!mounted) return;
    setState(() => _locked = true);
    _promptForUnlock();
  }

  Future<void> _promptForUnlock() async {
    if (_prompting) return;
    _prompting = true;
    final unlocked = await AppLock.authenticate();
    _prompting = false;
    if (!mounted) return;
    if (unlocked) setState(() => _locked = false);
    // On failure the lock screen stays up with a retry button rather than
    // looping the system prompt, which Android rate-limits after a few tries.
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_locked || _obscured)
          _LockCurtain(
            // While merely obscured there is nothing to do but wait for the
            // app to come back, so the button only appears once truly locked.
            onUnlock: _locked ? _promptForUnlock : null,
          ),
      ],
    );
  }
}

class _LockCurtain extends StatelessWidget {
  const _LockCurtain({this.onUnlock});

  final VoidCallback? onUnlock;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.primary,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(Icons.lock_outline, size: 44, color: Colors.white),
              ),
              const SizedBox(height: 24),
              const Text('Smart Finance Tracker',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
                      color: Colors.white)),
              const SizedBox(height: 8),
              Text('Locked',
                  style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.7))),
              if (onUnlock != null) ...[
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: onUnlock,
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Unlock'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
