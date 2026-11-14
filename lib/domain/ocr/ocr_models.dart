import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

/// A single line of text recognised by ML Kit, with its on-screen bounds in
/// pixels. Bounds are important so fields can be matched to their labels
/// instead of blindly scanning the whole screen.
class OcrLine {
  const OcrLine({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    this.confidence,
  });

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final double? confidence;

  double get centerY => (top + bottom) / 2;
  double get height => bottom - top;
  double get width => right - left;

  factory OcrLine.fromMap(Map<Object?, Object?> map) {
    double read(String key) => (map[key] as num?)?.toDouble() ?? 0;
    return OcrLine(
      text: (map['text'] as String?) ?? '',
      left: read('left'),
      top: read('top'),
      right: read('right'),
      bottom: read('bottom'),
      confidence: (map['confidence'] as num?)?.toDouble(),
    );
  }

  @override
  String toString() => 'OcrLine("$text", y=$top..$bottom)';
}

/// One OCR frame produced by the native screen-capture service.
class ScreenObservation {
  const ScreenObservation({
    required this.lines,
    required this.screenWidth,
    required this.screenHeight,
    required this.capturedAt,
    this.foregroundPackage,
    this.frameId,
  });

  final List<OcrLine> lines;
  final int screenWidth;
  final int screenHeight;
  final DateTime capturedAt;
  final String? foregroundPackage;
  final int? frameId;

  double get averageConfidence {
    final values = lines
        .map((l) => l.confidence)
        .whereType<double>()
        .where((v) => v > 0)
        .toList();
    if (values.isEmpty) return 0.85;
    return values.reduce((a, b) => a + b) / values.length;
  }

  factory ScreenObservation.fromMap(Map<Object?, Object?> map) {
    final rawLines = (map['lines'] as List<Object?>?) ?? const [];
    return ScreenObservation(
      lines: rawLines
          .whereType<Map<Object?, Object?>>()
          .map(OcrLine.fromMap)
          .where((line) => line.text.trim().isNotEmpty)
          .toList(),
      screenWidth: (map['screenWidth'] as num?)?.toInt() ?? 1080,
      screenHeight: (map['screenHeight'] as num?)?.toInt() ?? 2400,
      capturedAt: DateTime.fromMillisecondsSinceEpoch(
        ((map['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch),
      ),
      foregroundPackage: map['packageName'] as String?,
      frameId: (map['frameId'] as num?)?.toInt(),
    );
  }
}

/// Result of interpreting one Angkas screen.
class ParsedBookingScreen {
  const ParsedBookingScreen({
    required this.hasAcceptedSignal,
    required this.hasEndedSignal,
    required this.hasCancelledSignal,
    required this.hasEarningsPanel,
    this.totalEarningsCents,
    this.fareToCollectCents,
    this.paymentMethod,
    this.statusLabel,
    required this.confidence,
    required this.signature,
    required this.signals,
    this.bookingFingerprint,
  });

  final bool hasAcceptedSignal;
  final bool hasEndedSignal;
  final bool hasCancelledSignal;
  final bool hasEarningsPanel;
  final int? totalEarningsCents;
  final int? fareToCollectCents;
  final String? paymentMethod;
  final String? statusLabel;
  final double confidence;
  final String signature;
  final List<String> signals;

  /// Salted hash of the stable booking-panel text, used to distinguish a new
  /// ride from the same ride reopened. Null when no stable text was found.
  final String? bookingFingerprint;

  bool get hasEarnings =>
      totalEarningsCents != null || fareToCollectCents != null;

  bool get isLikelyBookingScreen =>
      hasAcceptedSignal ||
      hasEndedSignal ||
      hasCancelledSignal ||
      hasEarningsPanel;

  bool get isCompleteEarnings =>
      totalEarningsCents != null && fareToCollectCents != null;
}

class OcrSignature {
  OcrSignature._();

  /// A per-install salt is loaded at startup, making stored hashes useless on
  /// another device even if the database were copied.
  static String salt = 'simove-local-v1';

  static String compute(ScreenObservation observation) {
    final height = math.max(observation.screenHeight, 1);
    final relevant = observation.lines.where((line) {
      final relativeTop = line.top / height;
      if (relativeTop < 0.05 || relativeTop > 0.95) return false;
      final text = line.text.trim();
      if (text.isEmpty) return false;
      if (RegExp(r'^\d{1,2}:\d{2}$').hasMatch(text)) return false;
      if (RegExp(r'^[\d\s%+\-:APM]+$', caseSensitive: false).hasMatch(text)) {
        return false;
      }
      return true;
    }).map((line) => line.text).join('|');
    return hashText('$salt::$relevant');
  }

  static String hashText(String text) {
    // A one-way fingerprint: readable screen content (including addresses) is
    // never written to the database.
    return sha256.convert(utf8.encode(text)).toString().substring(0, 24);
  }

  /// Builds a fingerprint from stable booking-panel lines only. Earnings,
  /// buttons, labels, clocks and map pins are discarded, leaving text such as
  /// the pickup/drop-off area. Only the salted hash leaves this function.
  static String? bookingFingerprint(
    List<OcrLine> lines,
    int screenHeight,
  ) {
    const uiWords = [
      'PICKUP', 'DROPOFF', 'DROP', 'OFF', 'PROCEED', 'OTW', 'ONTHEWAY',
      'WAY', 'TOTAL', 'EARNINGS', 'EARNING', 'FARE', 'COLLECT', 'PAYMENT',
      'CASH', 'GCASH', 'MAYA', 'PAYMAYA', 'WALLET', 'CARD', 'ACCEPT',
      'ACCEPTED', 'AUTO', 'BOOKING', 'CANCEL', 'CANCELLED', 'STATUS',
      'ONLINE', 'RATE', 'COMPLETED', 'COMPLETE', 'ARRIVED', 'NAME',
      'PASSENGER', 'CALL', 'CHAT', 'NAVIGATE', 'CONFIRM', 'BACK', 'HOME',
      'ESTIMATED', 'DISTANCE', 'KM', 'MIN', 'MINS', 'PAY', 'COLLECT', 'METHOD',
    ];
    final basis = <String>[];
    for (final line in lines) {
      final relativeTop = line.top / math.max(screenHeight, 1);
      if (relativeTop < 0.5 || relativeTop > 0.95) continue;
      var text = line.text.toUpperCase().trim();
      if (text.isEmpty) continue;
      // Remove UI vocabulary, leaving the booking-specific remainder.
      for (final word in uiWords) {
        text = text.replaceAll(RegExp('\\b$word\\b'), ' ');
      }
      text = text.replaceAll(RegExp(r'[₱]|PHP\s*\d[\d,.]*'), ' ');
      if (RegExp(r'^[\d\s.,:+\-–—/()%]+$').hasMatch(text)) continue;
      final letters = RegExp(r'[A-Z]').allMatches(text).length;
      if (letters < 3) continue;
      final normalized = text.replaceAll(RegExp(r'[^A-Z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      if (normalized.length < 4) continue;
      basis.add(normalized);
    }
    if (basis.length < 2) return null;
    return hashText('$salt::booking::${basis.join('|')}');
  }
}
