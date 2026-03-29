// lib/core/category_suggester.dart
//
// Suggests an expense category from a plain-text description.
// Uses a keyword map built specifically for Kenyan student spending patterns.
//
// Called from two places:
//   1. add_expense_screen.dart  — live suggestion as user types description
//   2. mpesa_import_screen.dart — suggestion after M-Pesa message is parsed
//
// Priority order (handled in mpesa_import_screen, not here):
//   1. MpesaMemory lookup  — if recipient was seen before, use stored category
//   2. CategorySuggester   — keyword scan on the description
//   3. Fallback            — 'Other'

class CategorySuggester {
  // ── Keyword map ──────────────────────────────────────────────────────────
  // Each entry maps a category name to a list of trigger words/phrases.
  // Words are matched case-insensitively against individual tokens in the
  // description — partial matches are allowed (e.g. "lunch" matches "lunching").

  static const Map<String, List<String>> _keywords = {
    'Food': [
      'food', 'lunch', 'dinner', 'breakfast', 'snack', 'meal',
      'restaurant', 'cafe', 'canteen', 'kiosk', 'hotel',
      // Kenyan foods
      'mandazi', 'chapati', 'ugali', 'nyama', 'chicken', 'fry',
      'githeri', 'chips', 'rice', 'matumbo', 'mutura', 'smokie',
      'bhajia', 'mahindi', 'mkate',
      // Drinks & groceries
      'juice', 'tea', 'coffee', 'soda', 'water', 'milk',
      'groceries', 'sukuma', 'cabbage', 'tomato', 'onions',
      'bread', 'eggs', 'butter', 'sugar', 'flour', 'beans',
      'lentils', 'omena', 'tilapia', 'beef', 'pork',
      // Fast food chains common in Kenya
      'kfc', 'java', 'chicken inn', 'debonairs', 'pizza',
      'subway', 'galitos', 'eating', 'bought food',
    ],
    'Transport': [
      'transport', 'matatu', 'fare', 'bus', 'commute', 'travel',
      // Ride-hailing & bikes
      'bodaboda', 'boda', 'taxi', 'uber', 'bolt', 'little',
      'tuk', 'tuk-tuk',
      // Fuel & parking
      'fuel', 'petrol', 'diesel', 'parking', 'toll',
      // Routes & places used as transport context
      'stage', 'terminus', 'cbd', 'nairobi', 'juja', 'thika',
      'mombasa road', 'ngong', 'rongai', 'shuttle',
      // Rail
      'sgr', 'train', 'railway', 'flight', 'bus ticket',
    ],
    'Entertainment': [
      'entertainment', 'movie', 'cinema', 'netflix', 'youtube',
      'gaming', 'game', 'ps4', 'ps5', 'xbox',
      // Night life
      'club', 'bar', 'drinks', 'alcohol', 'beer', 'wine',
      'spirits', 'whisky',
      // Events
      'party', 'concert', 'event', 'ticket', 'show', 'series',
      // Streaming
      'streaming', 'spotify', 'deezer', 'apple music',
      // Social
      'fun', 'outing', 'hangout', 'date', 'trip',
    ],
    'Shopping': [
      'shopping', 'clothes', 'shoes', 'shirt', 'trouser', 'dress',
      'sandals', 'sneakers', 'boots', 'bag', 'belt', 'watch',
      'accessories', 'mall', 'market', 'online',
      // Kenyan e-commerce
      'jumia', 'kilimall', 'copia',
      // Clothing brands/stores common in Kenya
      'fashion', 'jeans', 'hoodie', 'jacket', 'socks', 'cap',
      'hat', 'vest', 'shorts',
      // Personal care
      'cosmetics', 'beauty', 'lotion', 'perfume', 'deodorant',
      'shampoo', 'soap', 'hair', 'nails', 'salon', 'barber',
    ],
    'Health': [
      'health', 'doctor', 'hospital', 'clinic', 'pharmacy',
      'medicine', 'drugs', 'panadol', 'prescription', 'lab',
      'test', 'xray', 'dental', 'dentist', 'eye', 'glasses',
      'therapy', 'counseling',
      // Kenyan health systems
      'nhif', 'nairobi hospital', 'aga khan', 'knh',
      'first aid', 'insurance', 'medical',
    ],
    'Education': [
      'education', 'school', 'tuition', 'fee', 'fees',
      'books', 'textbook', 'notes', 'printing', 'photocopy',
      'stationery', 'pen', 'pencil', 'ruler', 'folder',
      'library', 'exam', 'course', 'certificate',
      // Tech for school
      'laptop', 'computer', 'internet', 'research', 'journal',
      // Kenyan unis
      'jkuat', 'uon', 'kenyatta', 'strathmore', 'ku',
      'attachment', 'internship', 'project',
    ],
    'Utilities': [
      'utilities', 'electricity', 'power', 'kplc',
      'water', 'wifi', 'internet', 'zuku', 'faiba',
      // Mobile data & airtime
      'bundles', 'airtime', 'safaricom', 'airtel', 'telkom',
      'data', 'minutes', 'sms bundle',
      // Gas & energy
      'token', 'prepaid', 'bill', 'gas', 'cylinder',
      'cooking gas', 'total gas', 'k-gas',
      'generator', 'charcoal', 'firewood',
    ],
    'Rent': [
      'rent', 'bedsitter', 'room', 'house', 'hostel',
      'landlord', 'caretaker', 'deposit', 'lease',
      'accommodation', 'dwelling', 'flat', 'apartment',
      'studio', 'single room', 'double room', 'house rent',
    ],
    'Other': [
      'other', 'miscellaneous', 'misc', 'random',
      'unknown', 'various', 'general',
    ],
  };

  // ── Category order (priority matters — more specific first) ──────────────
  static const List<String> _orderedCategories = [
    'Utilities',   // before 'Food' so "Safaricom" doesn't match Food
    'Rent',
    'Health',
    'Education',
    'Transport',
    'Food',
    'Entertainment',
    'Shopping',
    'Other',
  ];

  // ── Public API ───────────────────────────────────────────────────────────

  /// Returns the best-matching category for [description], or null if no
  /// keyword matches. The caller should fall back to 'Other' on null.
  static String? suggest(String description) {
    if (description.trim().isEmpty) return null;

    final tokens = description
        .toLowerCase()
        .split(RegExp(r'[\s\-_/,]+'));

    for (final category in _orderedCategories) {
      final keywords = _keywords[category]!;
      for (final token in tokens) {
        if (token.length < 3) continue; // skip very short tokens
        for (final kw in keywords) {
          if (token.contains(kw) || kw.contains(token)) {
            return category;
          }
        }
      }
    }

    return null; // no match — caller shows 'Other'
  }

  /// Returns all 9 expense categories in display order.
  static List<String> get allCategories => const [
    'Food', 'Transport', 'Entertainment', 'Shopping',
    'Health', 'Education', 'Utilities', 'Rent', 'Other',
  ];
}