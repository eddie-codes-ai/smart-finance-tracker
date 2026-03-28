// lib/core/notification_service.dart
// Singleton service for local budget alert notifications.
//
// Fires a notification only when spending CROSSES a threshold for the
// first time — not on every expense — to avoid notification spam.
//
// Thresholds:
//   50%  → gentle nudge   (halfway warning)
//   80%  → warning        (high priority)
//   100% → critical alert (max priority, budget exceeded)
//
// Only fires for non-one-time expenses, matching analysis_service.py logic.
//
// Android 13+ (API 33+) requires both:
//   1. <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
//      in AndroidManifest.xml  ← already done
//   2. A runtime permission request the first time the app runs ← done here

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String _channelId   = 'budget_alerts';
  static const String _channelName = 'Budget Alerts';
  static const String _channelDesc =
      'Alerts when spending approaches or exceeds your category budget limits';

  // ─── Init ────────────────────────────────────────────────────────────────────

  Future<void> init() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initSettings =
        InitializationSettings(android: androidSettings);

    await _plugin.initialize(initSettings);

    // Create the notification channel (Android 8.0+ / API 26+ requirement).
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.high,
    );

    final AndroidFlutterLocalNotificationsPlugin? androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(channel);

    // Android 13+ (API 33+) requires an explicit runtime permission request.
    // Without this the OS silently blocks all notifications even if the
    // manifest permission is declared.
    await androidPlugin?.requestNotificationsPermission();
  }

  // ─── Budget Check ────────────────────────────────────────────────────────────

  /// Called after an expense is successfully saved.
  /// Compares previousTotal and newTotal against the budget limit and fires
  /// a notification only when a threshold boundary is newly crossed.
  ///
  /// [category]      — expense category name e.g. "Food"
  /// [previousTotal] — category total BEFORE this expense was added
  /// [newTotal]      — category total AFTER this expense was added
  /// [limit]         — budget limit set by the student for this category
  Future<void> checkAndNotify({
    required String category,
    required double previousTotal,
    required double newTotal,
    required double limit,
  }) async {
    if (limit <= 0) return;

    final double prevPct = (previousTotal / limit) * 100;
    final double newPct  = (newTotal      / limit) * 100;

    // 100% threshold — budget exceeded
    if (newPct >= 100 && prevPct < 100) {
      await _show(
        id:         _idFor(category),
        title:      '🚨 Budget Exceeded: $category',
        body:       'You\'ve gone over your $category budget. '
                    'Spent KES ${newTotal.toStringAsFixed(0)} of '
                    'KES ${limit.toStringAsFixed(0)}.',
        importance: Importance.max,
        priority:   Priority.max,
      );
      return;
    }

    // 80% threshold — high warning
    if (newPct >= 80 && prevPct < 80) {
      await _show(
        id:         _idFor(category),
        title:      '⚠️ Budget Warning: $category',
        body:       '${newPct.toStringAsFixed(0)}% of your $category budget used. '
                    'Only KES ${(limit - newTotal).toStringAsFixed(0)} remaining.',
        importance: Importance.high,
        priority:   Priority.high,
      );
      return;
    }

    // 50% threshold — gentle nudge
    if (newPct >= 50 && prevPct < 50) {
      await _show(
        id:         _idFor(category),
        title:      '📊 Halfway There: $category',
        body:       'Half your $category budget is used. '
                    'KES ${(limit - newTotal).toStringAsFixed(0)} left for the month.',
        importance: Importance.defaultImportance,
        priority:   Priority.defaultPriority,
      );
    }
  }

  // ─── Private helpers ──────────────────────────────────────────────────────────

  Future<void> _show({
    required int id,
    required String title,
    required String body,
    required Importance importance,
    required Priority priority,
  }) async {
    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: importance,
      priority:   priority,
      showWhen:   true,
    );

    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(android: androidDetails),
    );
  }

  /// Generates a stable notification ID per category.
  /// Using category hashCode keeps Food, Transport, etc. each in their own slot.
  int _idFor(String category) => category.hashCode.abs() % 10000;
}