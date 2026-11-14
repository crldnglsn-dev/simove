import 'package:flutter_test/flutter_test.dart';
import 'package:simove/domain/ocr/angkas_ocr_parser.dart';
import 'package:simove/domain/ocr/ocr_models.dart';

import 'helpers/observation_builder.dart';

void main() {
  const parser = AngkasOcrParser();

  group('AngkasOcrParser', () {
    test('reads total earnings, fare and payment method', () {
      final parsed = parser.parse(earningsScreen().build());

      expect(parsed.totalEarningsCents, 7500);
      expect(parsed.fareToCollectCents, 9500);
      expect(parsed.paymentMethod, 'Cash');
      expect(parsed.hasEarningsPanel, isTrue);
      expect(parsed.confidence, greaterThan(0.6));
    });

    test('reads values when label and amount are on the same line', () {
      final observation = ObservationBuilder()
        ..line('Proceed to Pickup', top: 600)
        ..line('Pickup: 123 Mabini Street', top: 1300)
        ..line('Drop-off: Ayala Avenue', top: 1370)
        ..line('Total Earnings  ₱125.50', top: 1500)
        ..line('Fare To Collect  ₱150.00', top: 1570);
      final parsed = parser.parse(observation.build());

      expect(parsed.totalEarningsCents, 12550);
      expect(parsed.fareToCollectCents, 15000);
    });

    test('does not invent earnings from map distances or promos', () {
      final observation = ObservationBuilder()
        ..line('Proceed to Pickup', top: 600)
        ..line('2.4 km • 8 min', top: 900)
        ..line('₱50 promo available', top: 1900)
        ..line('Pickup: 123 Mabini Street', top: 1400);
      final parsed = parser.parse(observation.build());

      expect(parsed.totalEarningsCents, isNull);
      expect(parsed.fareToCollectCents, isNull);
      expect(parsed.hasAcceptedSignal, isTrue);
    });

    test('ignores the fare value when the total earnings value is missing', () {
      final observation = ObservationBuilder()
        ..line('Proceed to Pickup', top: 600)
        ..line('Total Earnings', top: 1500)
        ..line('Fare To Collect', top: 1600)
        ..line('₱95.00', top: 1650);
      final parsed = parser.parse(observation.build());

      expect(parsed.totalEarningsCents, isNull);
      expect(parsed.fareToCollectCents, 9500);
      expect(parsed.confidence, lessThan(0.6));
    });

    test('marks an earnings value above the fare as a review signal', () {
      final parsed = parser.parse(
        earningsScreen(totalValue: '₱120.00', fareValue: '₱95.00').build(),
      );

      expect(parsed.signals, contains('earnings_exceed_fare'));
      expect(parsed.confidence, lessThan(0.9));
    });

    test('detects an ended booking screen', () {
      final observation = ObservationBuilder()
        ..line('Trip Completed', top: 700)
        ..line('Rate your passenger', top: 800);
      final parsed = parser.parse(observation.build());

      expect(parsed.hasEndedSignal, isTrue);
    });

    test('fingerprint is stable when earnings appear in the panel', () {
      final collapsed = acceptedBooking().build();
      final expanded = earningsScreen().build();
      final collapsedParsed = parser.parse(collapsed);
      final expandedParsed = parser.parse(expanded);

      expect(collapsedParsed.bookingFingerprint, isNotNull);
      expect(
        expandedParsed.bookingFingerprint,
        collapsedParsed.bookingFingerprint,
      );
    });

    test('fingerprint changes for a different pickup and drop-off', () {
      final first = parser.parse(acceptedBooking().build());
      final second = parser.parse(
        acceptedBooking(
          pickup: 'Pickup: 88 Katipunan Avenue, Quezon City',
          dropoff: 'Drop-off: SM North EDSA',
        ).build(),
      );

      expect(second.bookingFingerprint, isNotNull);
      expect(second.bookingFingerprint, isNot(first.bookingFingerprint));
    });

    test('signature is a one-way hash and does not contain readable text', () {
      final parsed = parser.parse(earningsScreen().build());

      expect(parsed.signature, hasLength(24));
      expect(parsed.signature.contains('MAKATI'), isFalse);
      expect(parsed.signature.contains('123'), isFalse);
    });

    test('OCR line parsing tolerates missing confidence', () {
      final observation = earningsScreen().build();
      final withoutConfidence = ScreenObservation(
        lines: observation.lines
            .map((l) => OcrLine(
                  text: l.text,
                  left: l.left,
                  top: l.top,
                  right: l.right,
                  bottom: l.bottom,
                ))
            .toList(),
        screenWidth: observation.screenWidth,
        screenHeight: observation.screenHeight,
        capturedAt: observation.capturedAt,
      );

      expect(parser.parse(withoutConfidence).totalEarningsCents, 7500);
    });
  });
}
