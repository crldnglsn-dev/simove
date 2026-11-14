import 'package:intl/intl.dart';

/// Central money formatting/parsing helpers.
///
/// All amounts are stored as integer centavos to avoid floating point drift.
class Money {
  Money._();

  static String symbol = '₱';
  static String code = 'PHP';

  static const Map<String, String> supportedCurrencies = {
    'PHP': '₱',
    'USD': r'$',
    'EUR': '€',
    'GBP': '£',
    'SGD': r'S$',
  };

  static void setCurrency(String currencyCode) {
    code = currencyCode;
    symbol = supportedCurrencies[currencyCode] ?? '₱';
  }

  static String format(int cents, {bool withSymbol = true}) {
    final value = cents / 100;
    final text = value.toStringAsFixed(2);
    final parts = text.split('.');
    final whole = _groupThousands(parts.first);
    final formatted = '$whole.${parts.last}';
    return withSymbol ? '$symbol$formatted' : formatted;
  }

  static String formatCompact(int cents, {bool withSymbol = true}) {
    final value = cents / 100;
    if (value.abs() >= 1000000) {
      final m = value / 1000000;
      return '${withSymbol ? symbol : ''}${m.toStringAsFixed(1)}M';
    }
    if (value.abs() >= 10000) {
      final k = value / 1000;
      return '${withSymbol ? symbol : ''}${k.toStringAsFixed(1)}k';
    }
    return format(cents, withSymbol: withSymbol);
  }

  static String _groupThousands(String digits) {
    final negative = digits.startsWith('-');
    final clean = negative ? digits.substring(1) : digits;
    final buffer = StringBuffer();
    for (var i = 0; i < clean.length; i++) {
      if (i > 0 && (clean.length - i) % 3 == 0) buffer.write(',');
      buffer.write(clean[i]);
    }
    return negative ? '-$buffer' : buffer.toString();
  }

  /// Parses a user-typed amount such as `75`, `₱75.00`, `1,250.50`.
  static int? parseToCents(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;
    text = text
        .replaceAll(RegExp(r'[₱$€£]'), '')
        .replaceAll(RegExp(r'PHP|php|USD|usd', caseSensitive: false), '')
        .replaceAll(RegExp(r'[,\s]'), '');
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    if (value == null || value.isNaN || value.isInfinite) return null;
    if (value < 0 || value > 10000000) return null;
    return (value * 100).round();
  }

  static String forCsv(int? cents) =>
      cents == null ? '' : (cents / 100).toStringAsFixed(2);

  static NumberFormat get percentFormat =>
      NumberFormat.decimalPercentPattern(decimalDigits: 0);
}
