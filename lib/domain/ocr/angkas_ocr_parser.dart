import 'dart:math' as math;

import 'ocr_models.dart';

/// Interprets ML Kit text lines from the Angkas rider interface.
///
/// The parser is intentionally conservative: an amount is only returned when
/// it is found next to its own label, so unrelated map labels and distance
/// markers cannot accidentally become earnings.
class AngkasOcrParser {
  const AngkasOcrParser();

  static const _acceptedSignals = <String, String>{
    'PROCEEDTOPICKUP': 'Proceed to Pickup',
    'OTWTOPICKUP': 'On the way to pickup',
    'ONTHEWAYTOPICKUP': 'On the way to pickup',
    'IMHEREATPICKUP': "I'm here at pickup",
    'IMHEREPICKUP': "I'm here at pickup",
    'AUTOACCEPTED': 'Auto-accepted',
    'BOOKINGAUTOACCEPTED': 'Auto-accepted',
    'BOOKINGACCEPTED': 'Booking accepted',
    'NEWBOOKING': 'New booking',
    'WAITINGFORPASSENGER': 'Waiting for passenger',
    'PASSENGERONBOARD': 'Passenger onboard',
    'TRIPSTARTED': 'Trip in progress',
    'ONGOINGTRIP': 'Trip in progress',
    'PROCEEDTODROP': 'Proceed to drop-off',
    'ARRIVEDATDROP': 'Arrived at drop-off',
  };

  static const _endedSignals = <String, String>{
    'TRIPCOMPLETED': 'Trip completed',
    'RIDECOMPLETED': 'Trip completed',
    'BOOKINGCOMPLETED': 'Trip completed',
    'SERVICECOMPLETED': 'Trip completed',
    'BIKERCOMPLETED': 'Trip completed',
    'BIKERCOMPLETE': 'Trip completed',
    'RATEYOURPASSENGER': 'Rate your passenger',
    'RATEPASSENGER': 'Rate your passenger',
    'HOWWASYOURTRIP': 'Rate your passenger',
    'PAYMENTRECEIVED': 'Payment received',
    'YOUREONLINE': 'You are online',
  };

  static const _cancelledSignals = <String, String>{
    'BOOKINGCANCELLED': 'Booking cancelled',
    'RIDECANCELLED': 'Booking cancelled',
    'RIDERCANCELLED': 'Booking cancelled',
    'PASSENGERCANCELLED': 'Passenger cancelled',
    'TRIPCANCELLED': 'Booking cancelled',
    'BIKERCANCELLED': 'Booking cancelled',
    'BIKERCANCELED': 'Booking cancelled',
  };

  // Angkas settles rides with exactly one of these three methods. Wallet
  // brands (GCash, Maya, Angkas Credit) all count as E-wallet.
  static const _paymentMethods = <String, String>{
    'CASH': 'Cash',
    'PAYMENTCASH': 'Cash',
    'GCASH': 'E-wallet',
    'MAYA': 'E-wallet',
    'PAYMAYA': 'E-wallet',
    'EWALLET': 'E-wallet',
    'EWALLETPAYMENT': 'E-wallet',
    'WALLET': 'E-wallet',
    'ANGKASCREDIT': 'E-wallet',
    'CREDITCARD': 'Card',
    'DEBITCARD': 'Card',
    'CARD': 'Card',
  };

  static final RegExp _rawAmount = RegExp(
    r'(?:₱|PHP|Php|php)?\s*(\d[\d,]*(?:\.\d{1,2})?)',
  );

  ParsedBookingScreen parse(ScreenObservation observation) {
    final lines = [...observation.lines]
      ..sort((a, b) => a.top.compareTo(b.top));
    final compacts = lines.map((l) => _compact(l.text)).toList();
    final joined = compacts.join(' ');
    final height = math.max(observation.screenHeight, 1).toDouble();

    final signals = <String>[];

    // The earnings tab lists past trips ("Today", "Yesterday", "Net Earnings").
    // Status chips inside those rows ("Biker Cancelled") describe history, not
    // the booking that is currently open, so they must not end a live booking.
    final historyScreen = _isEarningsHistory(compacts);
    if (historyScreen) signals.add('earnings_history');

    String? statusLabel;
    var accepted = false;
    var ended = false;
    var cancelled = false;
    if (!historyScreen) {
      for (final entry in _acceptedSignals.entries) {
        if (joined.contains(entry.key)) {
          accepted = true;
          statusLabel ??= entry.value;
          signals.add('accepted:${entry.value}');
        }
      }

      for (final entry in _endedSignals.entries) {
        if (joined.contains(entry.key)) {
          ended = true;
          statusLabel ??= entry.value;
          signals.add('ended:${entry.value}');
        }
      }

      for (final entry in _cancelledSignals.entries) {
        if (joined.contains(entry.key)) {
          cancelled = true;
          statusLabel ??= entry.value;
          signals.add('cancelled:${entry.value}');
        }
      }
    }

    final earningsIndex = _findLabel(compacts, const [
      'TOTAL EARNING',
      'TOTALEARNING',
      'TOTALNETEARNING',
    ]);
    final fareIndex = _findLabel(compacts, const [
      'FARETOCOLLECT',
      'FARECOLLECT',
      'FARETOCOLLECTFROMPASSENGER',
      // Angkas trip details label the passenger's payment this way.
      'TOTALPAYMENT',
      'COLLECTEDPAYMENT',
    ]);

    // A bare "Earnings" heading on the history tab must never be read as a
    // live booking panel. Only an explicit "Total Earnings" label overrides
    // this guard.
    final hasEarningsPanel =
        earningsIndex != null || (fareIndex != null && !historyScreen);
    if (hasEarningsPanel) signals.add('earnings_panel');

    int? earnings;
    int? fare;
    if (earningsIndex != null) {
      final match = _extractAmount(
        lines: lines,
        compacts: compacts,
        labelIndex: earningsIndex,
        labelRegex: RegExp(r'total\s*earning[s]?', caseSensitive: false),
        screenHeight: height,
        excludedIndexes: {?fareIndex},
      );
      earnings = match?.cents;
      if (match != null) signals.add('total_earnings');
    }
    if (fareIndex != null) {
      final match = _extractAmount(
        lines: lines,
        compacts: compacts,
        labelIndex: fareIndex,
        labelRegex: RegExp(
          r'(?:fare\s*(?:to\s*)?collect|total\s*payment|collected\s*payment)',
          caseSensitive: false,
        ),
        screenHeight: height,
        excludedIndexes: {?earningsIndex},
      );
      fare = match?.cents;
      if (match != null) signals.add('fare_to_collect');
    }

    // A trip-detail sheet ("BOOKING ID", "Report an issue") describes a
    // finished trip. It is safe to update the open booking from it, but it
    // must never create a new record when no booking is open (for example
    // while browsing the earnings history).
    final isHistoricalDetail =
        joined.contains('BOOKINGID') ||
        joined.contains('HAVECONCERNS') ||
        joined.contains('REPORTANISSUE');

    String? payment;
    if (hasEarningsPanel) {
      payment = _extractPayment(
        lines,
        compacts,
        fareIndex,
        earningsIndex,
        height,
      );
      if (payment != null) signals.add('payment:$payment');
    }

    if (earnings != null && earnings > 500000) {
      // More than ₱5,000 for a single motorcycle ride is far more likely to be
      // an OCR misread than a real fare.
      signals.add('earnings_out_of_range');
      earnings = null;
    }
    if (fare != null && fare > 500000) {
      signals.add('fare_out_of_range');
      fare = null;
    }
    if (earnings != null && fare != null && earnings > fare) {
      // Tips usually appear as a separate field; a total above the collected
      // fare deserves review rather than blind trust.
      signals.add('earnings_exceed_fare');
    }

    var confidence = 0.0;
    if (earnings != null) confidence += 0.55;
    if (fare != null) confidence += 0.25;
    if (payment != null) confidence += 0.1;
    if (accepted || ended || cancelled) confidence += 0.1;
    if (earnings != null && fare != null) confidence += 0.05;
    if (signals.contains('earnings_exceed_fare')) confidence -= 0.25;
    confidence *= (0.7 + 0.3 * observation.averageConfidence);
    confidence = confidence.clamp(0.0, 0.99);

    return ParsedBookingScreen(
      hasAcceptedSignal: accepted,
      hasEndedSignal: ended,
      hasCancelledSignal: cancelled,
      hasEarningsPanel: hasEarningsPanel,
      totalEarningsCents: earnings,
      fareToCollectCents: fare,
      paymentMethod: payment,
      statusLabel: statusLabel,
      confidence: confidence,
      signature: OcrSignature.compute(observation),
      bookingFingerprint: OcrSignature.bookingFingerprint(
        lines,
        observation.screenHeight,
      ),
      isHistoricalDetail: isHistoricalDetail,
      signals: signals,
    );
  }

  int? _findLabel(List<String> compacts, List<String> patterns) {
    for (var i = 0; i < compacts.length; i++) {
      for (final pattern in patterns) {
        if (compacts[i].contains(pattern)) return i;
      }
    }
    return null;
  }

  /// True when the screen is the earnings tab (a list of finished trips)
  /// rather than the earnings breakdown for one active booking.
  bool _isEarningsHistory(List<String> compacts) {
    if (compacts.any((c) => c.contains('NETEARNINGS'))) return true;
    var today = false;
    var yesterday = false;
    var trips = false;
    for (final compact in compacts) {
      if (compact == 'TODAY') today = true;
      if (compact == 'YESTERDAY') yesterday = true;
      if (compact.contains('TRIPS')) trips = true;
    }
    return today && yesterday && trips;
  }

  _AmountMatch? _extractAmount({
    required List<OcrLine> lines,
    required List<String> compacts,
    required int labelIndex,
    required RegExp labelRegex,
    required double screenHeight,
    required Set<int> excludedIndexes,
  }) {
    final labelLine = lines[labelIndex];
    final rawMatch = labelRegex.firstMatch(labelLine.text);
    final searchFrom = rawMatch?.end ?? 0;

    final sameLine = _tokensIn(labelLine.text, minStart: searchFrom);
    if (sameLine.isNotEmpty) return sameLine.first;

    // Amounts are commonly rendered directly underneath their label.
    for (var offset = 1; offset <= 4; offset++) {
      final index = labelIndex + offset;
      if (index >= lines.length || excludedIndexes.contains(index)) break;
      final line = lines[index];
      if (line.top - labelLine.top > screenHeight * 0.12) break;
      if (_looksLikeOtherLabel(compacts[index])) continue;
      final tokens = _tokensIn(line.text);
      if (tokens.isNotEmpty && _isAmountOnlyLine(line.text)) {
        return tokens.first;
      }
    }

    // Some layouts place the value above the label.
    final previousIndex = labelIndex - 1;
    if (previousIndex >= 0 &&
        !excludedIndexes.contains(previousIndex) &&
        labelLine.top - lines[previousIndex].bottom < screenHeight * 0.05) {
      final tokens = _tokensIn(lines[previousIndex].text);
      if (tokens.isNotEmpty && _isAmountOnlyLine(lines[previousIndex].text)) {
        return tokens.first;
      }
    }
    return null;
  }

  bool _isAmountOnlyLine(String text) {
    final stripped = text
        .replaceAll(RegExp(r'(?:₱|PHP|Php|php|[\d,.\s])'), '')
        .trim();
    if (stripped.isEmpty) return true;
    return stripped.length <= 4 && RegExp(r'^[a-zA-Z%]+$').hasMatch(stripped);
  }

  bool _looksLikeOtherLabel(String compact) {
    return compact.contains('TOTALEARNING') ||
        compact.contains('FARETOCOLLECT') ||
        compact.contains('PAYMENT') ||
        compact.contains('EARNING');
  }

  String? _extractPayment(
    List<OcrLine> lines,
    List<String> compacts,
    int? fareIndex,
    int? earningsIndex,
    double screenHeight,
  ) {
    final paymentIndex = _findLabel(compacts, const [
      'PAYMENTMETHOD',
      'PAYMENT',
    ]);
    if (paymentIndex != null) {
      final labelLine = lines[paymentIndex];
      final rawMatch = RegExp(
        r'payment(\s*method)?',
        caseSensitive: false,
      ).firstMatch(labelLine.text);
      final searchFrom = rawMatch?.end ?? 0;
      final sameLine = _methodInText(
        labelLine.text.substring(math.min(searchFrom, labelLine.text.length)),
      );
      if (sameLine != null) return sameLine;
      for (var offset = 1; offset <= 2; offset++) {
        final index = paymentIndex + offset;
        if (index >= lines.length) break;
        if (lines[index].top - labelLine.top > screenHeight * 0.06) break;
        final method = _methodInText(lines[index].text);
        if (method != null) return method;
      }
    }

    // Fallback: a payment method displayed inside the earnings panel area.
    final referenceIndex = fareIndex ?? earningsIndex;
    if (referenceIndex == null) return null;
    final referenceTop = lines[referenceIndex].top;
    for (var i = 0; i < lines.length; i++) {
      if (compacts[i] == 'PAYMENT') continue;
      if ((lines[i].top - referenceTop).abs() > screenHeight * 0.18) continue;
      final method = _methodInText(lines[i].text);
      if (method != null) return method;
    }
    return null;
  }

  String? _methodInText(String text) {
    final compact = _compact(text);
    if (compact.isEmpty) return null;
    // "Cash Handling Earnings" is a fee row, not a payment method.
    if (compact.contains('HANDLING') || compact.contains('EARNING')) {
      return null;
    }
    for (final entry in _paymentMethods.entries) {
      if (compact == entry.key) return entry.value;
    }
    for (final entry in _paymentMethods.entries) {
      if (compact.contains(entry.key)) return entry.value;
    }
    return null;
  }

  List<_AmountMatch> _tokensIn(String text, {int minStart = 0}) {
    final matches = <_AmountMatch>[];
    for (final match in _rawAmount.allMatches(text)) {
      if (match.start < minStart) continue;
      final full = match.group(0) ?? '';
      final digits = match.group(1) ?? '';
      final hasSymbol =
          full.contains('₱') || full.toUpperCase().contains('PHP');
      final decimals = digits.contains('.') ? digits.split('.').last.length : 0;
      final trailing = text.substring(match.end);
      if (RegExp(
        r'^\s*(km|kms|min|mins|m\b|%|x\b)',
        caseSensitive: false,
      ).hasMatch(trailing)) {
        continue;
      }
      // Bare integers are ambiguous (clock times, booking numbers, map
      // labels). Only accept them when a currency symbol is present, or when
      // the value has exactly two decimal places.
      if (!hasSymbol && decimals != 2) continue;
      if (decimals == 1) continue;
      final normalized = digits.replaceAll(',', '');
      final value = double.tryParse(normalized);
      if (value == null) continue;
      final cents = (value * 100).round();
      if (cents <= 0 || cents > 5000000) continue;
      matches.add(_AmountMatch(cents, match.start));
    }
    return matches;
  }

  String _compact(String text) =>
      text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
}

class _AmountMatch {
  const _AmountMatch(this.cents, this.position);

  final int cents;
  final int position;
}
