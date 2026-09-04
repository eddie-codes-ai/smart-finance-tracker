// lib/core/mpesa_parser.dart
//
// Parses M-Pesa SMS messages into structured MpesaParseResult objects.
//
// Supported message types:
//   1. Send money      — "Ksh500.00 sent to JOHN KAMAU"
//   2. Receive money   — "You have received Ksh3,500.00 from MARY WANJIRU"
//   3. Pay bill        — "Ksh2,000.00 paid to KENYA POWER Account Number..."
//   4. Buy goods/till  — "Ksh250.00 paid to NAIVAS SUPERMARKET."
//   5. Airtime         — "Ksh50.00 airtime bought successfully"
//
// The parser extracts:
//   - Transaction code (e.g. SB27LJ9O3R)
//   - Type: 'expense' or 'income'
//   - Amount (double)
//   - Recipient or sender name (used for memory lookup)
//   - Description (human-readable, pre-fills the form)
//   - Suggested category (from CategorySuggester, overridden by memory)
//   - Income type (only for income messages: monthly/helb/parental/gig/other)

class MpesaParseResult {
  final String transactionCode;
  final String type;              // 'expense' | 'income'
  final double amount;
  final String recipientOrSender; // normalised name, used as memory key
  final String description;       // pre-fills the description field
  final String suggestedCategory; // pre-selects the category chip
  final String incomeType;        // pre-selects income type (income only)
  final String rawMessage;        // original SMS for reference

  /// When the transaction happened, read out of the message body. Null when the
  /// message carries no readable date; the caller then falls back to the SMS
  /// envelope's own timestamp, and only then to "now".
  final DateTime? transactionDate;

  const MpesaParseResult({
    required this.transactionCode,
    required this.type,
    required this.amount,
    required this.recipientOrSender,
    required this.description,
    required this.suggestedCategory,
    required this.incomeType,
    required this.rawMessage,
    this.transactionDate,
  });
}

class MpesaParser {
  // ── Public entry point ───────────────────────────────────────────────────

  /// Attempts to parse [message] as an M-Pesa SMS.
  /// Returns null if the message is not a recognised M-Pesa format.
  static MpesaParseResult? parse(String message) {
    final msg = message.trim();

    // Must look like an M-Pesa message — contains "Confirmed" and "Ksh"
    if (!msg.contains('Confirmed') || !RegExp(r'[Kk]sh').hasMatch(msg)) {
      return null;
    }

    if (_isReceive(msg))  return _parseReceive(msg);
    if (_isSend(msg))     return _parseSend(msg);
    if (_isAirtime(msg))  return _parseAirtime(msg);
    if (_isPayment(msg))  return _parsePayment(msg);

    return null; // unrecognised format
  }

  // ── Type detectors ───────────────────────────────────────────────────────

  static bool _isReceive(String msg) =>
      msg.toLowerCase().contains('you have received');

  static bool _isSend(String msg) =>
      msg.toLowerCase().contains('sent to');

  static bool _isAirtime(String msg) =>
      msg.toLowerCase().contains('airtime bought');

  static bool _isPayment(String msg) =>
      msg.toLowerCase().contains('paid to');

  // ── Parsers ──────────────────────────────────────────────────────────────

  static MpesaParseResult _parseReceive(String msg) {
    final code   = _extractCode(msg);
    final amount = _extractAmount(msg);

    // "received Ksh3,500.00 from MARY WANJIRU 0723456789 on"
    final nameMatch = RegExp(
      r'received\s+Ksh[\d,.]+\s+from\s+([A-Z][A-Z\s]+?)(?:\s+\d{10}|\s+on\b)',
      caseSensitive: false,
    ).firstMatch(msg);

    final name = _cleanName(nameMatch?.group(1) ?? '');
    final isHelb = name.toUpperCase().contains('HELB');

    return MpesaParseResult(
      transactionCode:    code,
      type:               'income',
      amount:             amount,
      recipientOrSender:  name.isEmpty ? 'Unknown' : name,
      description:        isHelb
                            ? 'HELB disbursement'
                            : name.isEmpty
                              ? 'M-Pesa received'
                              : 'Received from $name',
      suggestedCategory:  'Other',   // income — category not applicable
      incomeType:         isHelb
                            ? 'helb'
                            : _guessIncomeType(name),
      rawMessage:         msg,
      transactionDate:    extractDate(msg),
    );
  }

  static MpesaParseResult _parseSend(String msg) {
    final code   = _extractCode(msg);
    final amount = _extractAmount(msg);

    // "Ksh500.00 sent to JOHN KAMAU 0712345678 on"
    final nameMatch = RegExp(
      r'sent\s+to\s+([A-Z][A-Z\s]+?)(?:\s+\d{10}|\s+on\b)',
      caseSensitive: false,
    ).firstMatch(msg);

    final name = _cleanName(nameMatch?.group(1) ?? '');
    final desc = name.isEmpty ? 'M-Pesa sent' : 'Sent to $name';

    return MpesaParseResult(
      transactionCode:    code,
      type:               'expense',
      amount:             amount,
      recipientOrSender:  name.isEmpty ? 'Unknown' : name,
      description:        desc,
      suggestedCategory:  'Other', // memory/keyword will override this
      incomeType:         'other',
      rawMessage:         msg,
      transactionDate:    extractDate(msg),
    );
  }

  static MpesaParseResult _parseAirtime(String msg) {
    final code   = _extractCode(msg);
    final amount = _extractAmount(msg);

    return MpesaParseResult(
      transactionCode:    code,
      type:               'expense',
      amount:             amount,
      recipientOrSender:  'AIRTIME',
      description:        'Airtime purchase',
      suggestedCategory:  'Utilities',
      incomeType:         'other',
      rawMessage:         msg,
      transactionDate:    extractDate(msg),
    );
  }

  static MpesaParseResult _parsePayment(String msg) {
    final code   = _extractCode(msg);
    final amount = _extractAmount(msg);

    // "Ksh250.00 paid to NAIVAS SUPERMARKET. on"
    // "Ksh2,000.00 paid to KENYA POWER Account Number 12345678 on"
    final nameMatch = RegExp(
      r'paid\s+to\s+([A-Z][A-Z\s]+?)(?:\.|Account|\bon\b)',
      caseSensitive: false,
    ).firstMatch(msg);

    final name = _cleanName(nameMatch?.group(1) ?? '');
    final desc = name.isEmpty ? 'M-Pesa payment' : 'Paid to $name';

    // Use description to seed category suggestion
    final seededCategory = _seedCategoryFromMerchant(name);

    return MpesaParseResult(
      transactionCode:    code,
      type:               'expense',
      amount:             amount,
      recipientOrSender:  name.isEmpty ? 'Unknown' : name,
      description:        desc,
      suggestedCategory:  seededCategory,
      incomeType:         'other',
      rawMessage:         msg,
      transactionDate:    extractDate(msg),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Reads the transaction date out of the message body.
  ///
  /// M-Pesa writes it as "on 5/2/26 at 3:45 PM" — day/month/two-digit-year, the
  /// Kenyan convention. That ordering is a judgement call rather than something
  /// the message states, so anything implausible is rejected and the caller
  /// falls back rather than recording a confidently wrong date.
  static DateTime? extractDate(String msg) {
    final match = RegExp(
      r'on\s+(\d{1,2})/(\d{1,2})/(\d{2,4})'
      r'(?:\s+at\s+(\d{1,2}):(\d{2})\s*([AaPp])\.?[Mm])?',
    ).firstMatch(msg);
    if (match == null) return null;

    final day   = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    var   year  = int.tryParse(match.group(3)!);
    if (day == null || month == null || year == null) return null;
    if (year < 100) year += 2000;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;

    var hour   = 0;
    var minute = 0;
    if (match.group(4) != null) {
      hour   = int.tryParse(match.group(4)!) ?? 0;
      minute = int.tryParse(match.group(5)!) ?? 0;
      final isPm = match.group(6)!.toUpperCase() == 'P';
      if (hour == 12) hour = 0;        // 12 AM is 00; 12 PM becomes 12 below
      if (isPm) hour += 12;
      if (hour > 23 || minute > 59) return null;
    }

    final parsed = DateTime(year, month, day, hour, minute);

    // A day that rolled over (31 April silently becoming 1 May) means the input
    // was not a real date.
    if (parsed.day != day || parsed.month != month) return null;

    // Guard against a misread: a transaction cannot be in the future, and one
    // over five years old is far likelier to be a parsing error than a message
    // still sitting in the inbox.
    final now = DateTime.now();
    if (parsed.isAfter(now.add(const Duration(days: 1)))) return null;
    if (parsed.isBefore(now.subtract(const Duration(days: 365 * 5)))) return null;

    return parsed;
  }

  /// Extracts the leading transaction code e.g. "SB27LJ9O3R"
  static String _extractCode(String msg) {
    final m = RegExp(r'^([A-Z0-9]{8,12})\b').firstMatch(msg);
    return m?.group(1) ?? 'N/A';
  }

  /// Extracts the primary Ksh amount (the payment amount, not the balance)
  static double _extractAmount(String msg) {
    // M-Pesa puts the transaction amount FIRST — take the first Ksh match
    final matches = RegExp(r'[Kk]sh([\d,]+\.?\d*)').allMatches(msg).toList();
    if (matches.isEmpty) return 0.0;
    final raw = matches.first.group(1)!.replaceAll(',', '');
    return double.tryParse(raw) ?? 0.0;
  }

  /// Removes trailing/leading whitespace and strips double spaces
  static String _cleanName(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// For received money, guess the income type from the sender name
  static String _guessIncomeType(String name) {
    final n = name.toUpperCase();
    if (n.contains('HELB'))     return 'helb';
    if (n.contains('MUM') ||
        n.contains('DAD') ||
        n.contains('MAMA') ||
        n.contains('BABA') ||
        n.contains('PARENT'))   return 'parental';
    return 'other';
  }

  /// Merchant-name based category seeding (for bill payments and buy goods)
  static String _seedCategoryFromMerchant(String name) {
    final n = name.toUpperCase();
    if (n.contains('POWER') ||
        n.contains('WATER') ||
        n.contains('WIFI') ||
        n.contains('ZUKU') ||
        n.contains('FAIBA') ||
        n.contains('KPLC'))        return 'Utilities';
    if (n.contains('NAIVAS') ||
        n.contains('QUICKMART') ||
        n.contains('CARREFOUR') ||
        n.contains('SUPERMARKET')) return 'Shopping';
    if (n.contains('HOSPITAL') ||
        n.contains('CLINIC') ||
        n.contains('PHARMACY') ||
        n.contains('NHIF'))        return 'Health';
    if (n.contains('SCHOOL') ||
        n.contains('UNIVERSITY') ||
        n.contains('COLLEGE') ||
        n.contains('JKUAT'))       return 'Education';
    if (n.contains('BUS') ||
        n.contains('MATATU') ||
        n.contains('STAGE') ||
        n.contains('PETROL'))      return 'Transport';
    if (n.contains('HOTEL') ||
        n.contains('RESTAURANT') ||
        n.contains('CAFE') ||
        n.contains('FOOD') ||
        n.contains('KFC') ||
        n.contains('JAVA'))        return 'Food';
    return 'Other';
  }
}