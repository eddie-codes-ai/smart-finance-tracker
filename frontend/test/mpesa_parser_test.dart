// test/mpesa_parser_test.dart
//
// Covers MpesaParser.extractDate, which reads the transaction date out of the
// message body. Imported transactions used to be stamped with the moment of
// import, so a month of history all landed on one day.
//
// The date format is a judgement call: M-Pesa writes "on 5/2/26" and never says
// whether that is day/month or month/day. Kenya uses day/month, so that is what
// this assumes — and why anything implausible is rejected rather than guessed.
//
// Run with:  flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/mpesa_parser.dart';

/// A realistic send message, dated [dateFragment].
String sendSms(String dateFragment) =>
    'SB27LJ9O3R Confirmed. Ksh500.00 sent to JOHN KAMAU 0712345678 '
    '$dateFragment. New M-PESA balance is Ksh1,200.00. Transaction cost, Ksh13.00.';

void main() {
  group('extractDate', () {
    test('reads day/month/year and a 12-hour time', () {
      final d = MpesaParser.extractDate(sendSms('on 5/2/26 at 3:45 PM'));
      expect(d, isNotNull);
      expect(d!.year, 2026);
      expect(d.month, 2);
      expect(d.day, 5);
      expect(d.hour, 15);
      expect(d.minute, 45);
    });

    test('treats the date as day/month, not month/day', () {
      // 13 cannot be a month, so this also proves the ordering is not reversed.
      final d = MpesaParser.extractDate(sendSms('on 13/1/26 at 9:00 AM'));
      expect(d!.day, 13);
      expect(d.month, 1);
    });

    test('handles midnight and noon correctly', () {
      expect(MpesaParser.extractDate(sendSms('on 5/2/26 at 12:30 AM'))!.hour, 0);
      expect(MpesaParser.extractDate(sendSms('on 5/2/26 at 12:30 PM'))!.hour, 12);
    });

    test('accepts a date with no time', () {
      final d = MpesaParser.extractDate(sendSms('on 5/2/26'));
      expect(d, isNotNull);
      expect(d!.day, 5);
      expect(d.hour, 0);
    });

    test('accepts a four-digit year', () {
      expect(MpesaParser.extractDate(sendSms('on 5/2/2026'))!.year, 2026);
    });

    test('returns null when there is no date at all', () {
      expect(MpesaParser.extractDate('SB27LJ9O3R Confirmed. Ksh500.00 sent.'), isNull);
      expect(MpesaParser.extractDate(''), isNull);
    });

    test('rejects a date that does not exist', () {
      // 31 April would silently roll into 1 May, which would be a wrong answer
      // rather than no answer.
      expect(MpesaParser.extractDate(sendSms('on 31/4/26')), isNull);
      expect(MpesaParser.extractDate(sendSms('on 30/2/26')), isNull);
    });

    test('rejects an impossible month or day', () {
      expect(MpesaParser.extractDate(sendSms('on 5/13/26')), isNull);
      expect(MpesaParser.extractDate(sendSms('on 0/5/26')), isNull);
    });

    test('rejects a future date', () {
      final nextYear = DateTime.now().year + 1;
      expect(MpesaParser.extractDate(sendSms('on 5/2/$nextYear')), isNull);
    });

    test('rejects a date implausibly far in the past', () {
      expect(MpesaParser.extractDate(sendSms('on 5/2/1999')), isNull);
    });

    test('rejects a nonsensical time', () {
      expect(MpesaParser.extractDate(sendSms('on 5/2/26 at 25:00 PM')), isNull);
      expect(MpesaParser.extractDate(sendSms('on 5/2/26 at 3:99 PM')), isNull);
    });
  });

  group('parse() surfaces the date', () {
    test('a send message carries its transaction date', () {
      final result = MpesaParser.parse(sendSms('on 5/2/26 at 3:45 PM'));
      expect(result, isNotNull);
      expect(result!.type, 'expense');
      expect(result.amount, 500.0);
      expect(result.transactionCode, 'SB27LJ9O3R');
      expect(result.transactionDate, isNotNull);
      expect(result.transactionDate!.day, 5);
    });

    test('a received message carries its transaction date', () {
      final result = MpesaParser.parse(
        'SB27LJ9O3R Confirmed. You have received Ksh3,500.00 from '
        'MARY WANJIRU 0723456789 on 5/2/26 at 3:45 PM. New M-PESA balance is Ksh4,000.00.',
      );
      expect(result, isNotNull);
      expect(result!.type, 'income');
      expect(result.amount, 3500.0);
      expect(result.transactionDate!.month, 2);
    });

    test('a message with no date still parses, with a null date', () {
      final result = MpesaParser.parse(
        'SB27LJ9O3R Confirmed. Ksh500.00 sent to JOHN KAMAU 0712345678.',
      );
      expect(result, isNotNull);
      expect(result!.transactionDate, isNull);
    });

    test('a non-M-Pesa message is still rejected outright', () {
      expect(MpesaParser.parse('Hello, are we still meeting at 3?'), isNull);
    });
  });
}
