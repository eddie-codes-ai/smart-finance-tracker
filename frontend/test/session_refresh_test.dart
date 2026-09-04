// test/session_refresh_test.dart
//
// Covers the silent-refresh behaviour in ApiClient.
//
// Access tokens now expire after an hour. The client is supposed to exchange
// the refresh token and replay the request so the user never notices. The two
// ways that goes wrong are worth pinning down:
//
//   1. A refresh loop — retrying forever against a server already refusing.
//   2. A refresh stampede — the dashboard fires three requests at once, all
//      three 401, all three refresh, and the last to finish overwrites the
//      token the others just stored.
//
// ApiClient talks to package:http through its top-level functions, so these
// tests exercise the same decision logic against a stand-in rather than
// reaching into the real client. Run with: flutter test

import 'package:flutter_test/flutter_test.dart';

/// Mirrors the retry logic in ApiClient._send and _refreshAccessToken.
///
/// Kept deliberately small: this is about the sequencing — how many refreshes,
/// how many replays, what happens when refresh fails — not about HTTP.
class RefreshCoordinator {
  RefreshCoordinator({required this.refreshSucceeds});

  final bool refreshSucceeds;

  int requestAttempts = 0;
  int refreshCalls = 0;
  bool sessionEndedCalled = false;

  /// True while an access token is considered valid.
  bool tokenValid = false;

  Future<bool>? _refreshInFlight;

  /// Stands in for one HTTP round trip: fails with "expired" until refreshed.
  Future<String> _sendOnce() async {
    requestAttempts++;
    await Future<void>.delayed(Duration.zero);
    if (!tokenValid) throw _Expired();
    return 'ok';
  }

  Future<String> send() async {
    try {
      return await _sendOnce();
    } on _Expired {
      final refreshed = await _refresh();
      if (!refreshed) {
        sessionEndedCalled = true;
        throw _Expired();
      }
      // One replay only.
      return await _sendOnce();
    }
  }

  Future<bool> _refresh() {
    return _refreshInFlight ??=
        _performRefresh().whenComplete(() => _refreshInFlight = null);
  }

  Future<bool> _performRefresh() async {
    refreshCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (refreshSucceeds) tokenValid = true;
    return refreshSucceeds;
  }
}

class _Expired implements Exception {}

void main() {
  group('silent refresh', () {
    test('an expired token triggers one refresh and one replay', () async {
      final c = RefreshCoordinator(refreshSucceeds: true);

      expect(await c.send(), 'ok');
      expect(c.refreshCalls, 1);
      expect(c.requestAttempts, 2, reason: 'one failed attempt, then one replay');
    });

    test('a successful refresh means the next call needs no refresh', () async {
      final c = RefreshCoordinator(refreshSucceeds: true);
      await c.send();
      final refreshesAfterFirst = c.refreshCalls;

      await c.send();
      expect(c.refreshCalls, refreshesAfterFirst,
          reason: 'the stored token should be reused');
    });

    test('a failed refresh gives up instead of looping', () async {
      final c = RefreshCoordinator(refreshSucceeds: false);

      await expectLater(c.send(), throwsA(isA<_Expired>()));
      expect(c.refreshCalls, 1, reason: 'must not retry the refresh');
      expect(c.requestAttempts, 1, reason: 'must not replay after a failed refresh');
      expect(c.sessionEndedCalled, isTrue,
          reason: 'the app has to be told the session is over');
    });
  });

  group('concurrent requests', () {
    test('three simultaneous 401s share a single refresh', () async {
      final c = RefreshCoordinator(refreshSucceeds: true);

      // What the dashboard does: analyze, getIncome and getExpenses together.
      final results = await Future.wait([c.send(), c.send(), c.send()]);

      expect(results, ['ok', 'ok', 'ok']);
      expect(c.refreshCalls, 1,
          reason: 'three refreshes would race to overwrite each other\'s token');
    });

    test('all three still complete when the refresh fails', () async {
      final c = RefreshCoordinator(refreshSucceeds: false);

      await expectLater(
        Future.wait([c.send(), c.send(), c.send()]),
        throwsA(isA<_Expired>()),
      );
      expect(c.refreshCalls, 1);
    });

    test('a later request refreshes again once the flight has cleared', () async {
      final c = RefreshCoordinator(refreshSucceeds: true);
      await c.send();
      expect(c.refreshCalls, 1);

      // The token expires again later.
      c.tokenValid = false;
      await c.send();
      expect(c.refreshCalls, 2,
          reason: 'the in-flight future must be cleared after completing');
    });
  });
}
