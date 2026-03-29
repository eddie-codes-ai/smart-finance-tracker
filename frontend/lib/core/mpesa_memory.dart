// lib/core/mpesa_memory.dart
//
// Stores and retrieves a recipient→category mapping so the app can
// automatically suggest the correct category the next time the student
// transacts with the same M-Pesa recipient or till number.
//
// Storage backend: SharedPreferences (local, on-device, private).
// No backend change needed. No network call.
//
// Key format stored:  "mpesa_mem_JOHN KAMAU"  →  "Food"
//                     "mpesa_mem_KENYA POWER"  →  "Utilities"
//                     "mpesa_mem_AIRTIME"       →  "Utilities"
//
// Usage flow:
//   1. MpesaImportScreen calls MpesaMemory.lookup(recipientName)
//      before showing the category suggestion.
//   2. If a match is found, it pre-selects the category and shows
//      a small "from memory" badge so the student knows why.
//   3. After the student confirms and saves, MpesaMemory.save() is called
//      to record (or update) the mapping with whatever category was used.
//
// This means if a student changes the suggested category, the NEW category
// becomes the remembered one going forward — the memory self-corrects.

import 'package:shared_preferences/shared_preferences.dart';

class MpesaMemory {
  static const String _prefix = 'mpesa_mem_';

  // ── Save ─────────────────────────────────────────────────────────────────

  /// Stores [category] for [recipient].
  /// If the recipient was already stored, the value is updated (self-corrects).
  static Future<void> save(String recipient, String category) async {
    if (recipient.isEmpty || recipient == 'Unknown') return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(recipient), category);
  }

  // ── Lookup ───────────────────────────────────────────────────────────────

  /// Returns the remembered category for [recipient], or null if not seen before.
  static Future<String?> lookup(String recipient) async {
    if (recipient.isEmpty || recipient == 'Unknown') return null;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key(recipient));
  }

  // ── List all memories (for debugging / future "manage memory" screen) ────

  /// Returns a map of all stored recipient→category pairs.
  static Future<Map<String, String>> all() async {
    final prefs = await SharedPreferences.getInstance();
    final result = <String, String>{};
    for (final key in prefs.getKeys()) {
      if (key.startsWith(_prefix)) {
        final recipient = key.substring(_prefix.length);
        result[recipient] = prefs.getString(key)!;
      }
    }
    return result;
  }

  // ── Clear a single entry (for future use) ────────────────────────────────

  /// Removes the stored category for [recipient].
  static Future<void> forget(String recipient) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(recipient));
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  /// Builds the SharedPreferences key from a recipient name.
  /// Names are normalised to uppercase to avoid case mismatches.
  static String _key(String recipient) =>
      '$_prefix${recipient.trim().toUpperCase()}';
}