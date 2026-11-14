import 'package:flutter_test/flutter_test.dart';
import 'package:simove/data/models/booking_transaction.dart';
import 'package:simove/domain/detection/booking_state_machine.dart';

import 'helpers/observation_builder.dart';

class FakeStore {
  BookingTransaction? active;
  int _id = 0;

  void apply(DetectionDecision decision) {
    final updated = decision.updatedActive;
    if (updated != null && active != null) {
      active = updated.copyWith(
        id: active!.id,
        bookingReference: active!.bookingReference,
      );
    }
    final draft = decision.newTransaction;
    if (draft != null) {
      _id++;
      active = draft.copyWith(
        id: _id,
        bookingReference: 'SMV-TEST-${_id.toString().padLeft(3, '0')}',
      );
    }
  }
}

void main() {
  late BookingStateMachine machine;
  late FakeStore store;
  final start = DateTime(2026, 11, 14, 9, 0);

  setUp(() {
    machine = BookingStateMachine();
    store = FakeStore();
  });

  DetectionDecision process(DateTime at, {bool expanded = false, String? pickup, String? dropoff, String? total, String? fare, String? payment}) {
    final observation = expanded
        ? earningsScreen(
            at: at,
            pickup: pickup ?? 'Pickup: 123 Mabini Street, Makati',
            dropoff: dropoff ?? 'Drop-off: Ayala Avenue Tower 2',
            totalValue: total ?? '₱75.00',
            fareValue: fare ?? '₱95.00',
            payment: payment ?? 'Cash',
          ).build()
        : acceptedBooking(
            at: at,
            pickup: pickup ?? 'Pickup: 123 Mabini Street, Makati',
            dropoff: dropoff ?? 'Drop-off: Ayala Avenue Tower 2',
          ).build();
    final decision = machine.process(observation, store.active);
    store.apply(decision);
    return decision;
  }

  test('Test 1: a new accepted booking creates exactly one pending record', () {
    final decision = process(start);

    expect(decision.action, DetectionAction.create);
    expect(store.active, isNotNull);
    expect(store.active!.bookingStatus, BookingState.bookingDetected);
    expect(store.active!.platformEarningsCents, isNull);
  });

  test('Test 2: earnings are not invented before the panel is expanded', () {
    process(start);
    process(start.add(const Duration(seconds: 8)));
    process(start.add(const Duration(seconds: 16)));

    expect(store.active!.platformEarningsCents, isNull);
    expect(store.active!.bookingStatus, BookingState.bookingDetected);
  });

  test('Test 3: expanded panel records the exact displayed values', () {
    process(start);
    final decision = process(start.add(const Duration(seconds: 20)), expanded: true);

    expect(decision.action, DetectionAction.update);
    expect(store.active!.platformEarningsCents, 7500);
    expect(store.active!.fareToCollectCents, 9500);
    expect(store.active!.paymentMethod, 'Cash');
    expect(store.active!.bookingStatus, BookingState.recorded);
  });

  test('Test 4: switching away and back keeps the same transaction', () {
    process(start);
    process(start.add(const Duration(seconds: 25)), expanded: true);
    final id = store.active!.id;

    // No observations while Google Maps is open: nothing is changed.
    expect(store.active!.id, id);

    // Angkas becomes visible again with the same booking.
    process(start.add(const Duration(minutes: 2)), expanded: true);
    expect(store.active!.id, id);
    expect(store.active!.bookingStatus, BookingState.recorded);
  });

  test('Test 5: repeated identical screens do not create a duplicate', () {
    process(start);
    process(start.add(const Duration(seconds: 20)), expanded: true);
    for (var i = 1; i <= 5; i++) {
      final decision = process(
        start.add(Duration(seconds: 20 + i * 4)),
        expanded: true,
      );
      expect(decision.action, isNot(DetectionAction.create));
    }
    expect(store.active!.id, 1);
  });

  test('a partial frame does not un-record an already verified booking', () {
    process(start);
    process(start.add(const Duration(seconds: 20)), expanded: true);
    expect(store.active!.bookingStatus, BookingState.recorded);
    expect(store.active!.platformEarningsCents, 7500);

    // The same booking panel, but the amount rows were missed by OCR (for
    // example a scroll or a transient blur).
    final partial = ObservationBuilder(at: start.add(const Duration(seconds: 40)))
      ..line('Proceed to Pickup', top: 560)
      ..line('Pickup: 123 Mabini Street, Makati', top: 1350)
      ..line('Drop-off: Ayala Avenue Tower 2', top: 1430)
      ..line('Total Earnings', top: 1550);
    final decision = machine.process(partial.build(), store.active);
    store.apply(decision);

    expect(decision.action, DetectionAction.none);
    expect(decision.reason, contains('already recorded'));
    expect(store.active!.bookingStatus, BookingState.recorded);
    expect(store.active!.platformEarningsCents, 7500);
    expect(store.active!.fareToCollectCents, 9500);
  });

  test('a low-confidence frame with different values still needs review', () {
    machine.minConfidence = 0.99;
    process(start);
    process(start.add(const Duration(seconds: 20)), expanded: true);

    final blurry = earningsScreen(
      at: start.add(const Duration(seconds: 40)),
      totalValue: '₱88.00',
    ).allConfidence(0.2);
    final decision = machine.process(blurry.build(), store.active);
    store.apply(decision);

    expect(decision.action, DetectionAction.update);
    expect(decision.reason, contains('review'));
    expect(store.active!.bookingStatus, BookingState.errorRequiresReview);
    expect(store.active!.platformEarningsCents, 8800);
  });

  test('Test 6: a genuinely new booking creates a separate pending record', () {
    process(start);
    process(start.add(const Duration(seconds: 20)), expanded: true);

    final first = process(
      start.add(const Duration(minutes: 2)),
      pickup: 'Pickup: 88 Katipunan Avenue, Quezon City',
      dropoff: 'Drop-off: SM North EDSA',
    );
    expect(first.action, DetectionAction.none);
    expect(first.reason, contains('Checking'));

    final second = process(
      start.add(const Duration(minutes: 2, seconds: 4)),
      pickup: 'Pickup: 88 Katipunan Avenue, Quezon City',
      dropoff: 'Drop-off: SM North EDSA',
    );
    expect(second.action, DetectionAction.create);
    expect(store.active!.id, 2);
    expect(store.active!.bookingStatus, BookingState.bookingDetected);
    expect(store.active!.platformEarningsCents, isNull);
  });

  test('a new booking that already shows earnings is created immediately', () {
    process(start);
    process(start.add(const Duration(seconds: 20)), expanded: true);

    final decision = process(
      start.add(const Duration(minutes: 3)),
      expanded: true,
      pickup: 'Pickup: 88 Katipunan Avenue, Quezon City',
      dropoff: 'Drop-off: SM North EDSA',
      total: '₱110.00',
      fare: '₱140.00',
    );

    expect(decision.action, DetectionAction.create);
    expect(store.active!.id, 2);
    expect(store.active!.platformEarningsCents, 11000);
    expect(store.active!.bookingStatus, BookingState.recorded);
  });

  test('Test 7: a tip is added to platform earnings without double counting', () {
    process(start);
    process(start.add(const Duration(seconds: 20)), expanded: true);

    final withTip = store.active!.copyWith(tipCents: 2000, tipType: TipType.cash);
    expect(withTip.recordedEarningsCents, 9500);
    expect(withTip.fareToCollectCents, 9500);

    final included = store.active!.copyWith(
      tipCents: 2000,
      tipIncludedInPlatformEarnings: true,
    );
    expect(included.recordedEarningsCents, 7500);
  });

  test('Test 8: incomplete OCR keeps the booking pending for review', () {
    process(start);
    final builder = acceptedBooking(at: start.add(const Duration(seconds: 30)))
      ..line('Total Earnings', top: 1550)
      ..line('₱75.00', top: 1600);
    final decision = machine.process(builder.build(), store.active);
    store.apply(decision);

    expect(store.active!.platformEarningsCents, 7500);
    expect(store.active!.fareToCollectCents, isNull);
    expect(store.active!.bookingStatus, BookingState.errorRequiresReview);
    expect(store.active!.bookingStatus.isPending, isTrue);
  });

  test('an ended booking closes without losing detected earnings', () {
    process(start);
    process(start.add(const Duration(seconds: 20)), expanded: true);

    final ended = ObservationBuilder(at: start.add(const Duration(minutes: 5)))
      ..line('Trip Completed', top: 700)
      ..line('Rate your passenger', top: 800);
    final decision = machine.process(ended.build(), store.active);
    store.apply(decision);

    expect(store.active!.bookingStatus, BookingState.bookingEnded);
    expect(store.active!.endedAt, isNotNull);
    expect(store.active!.platformEarningsCents, 7500);
  });

  test('an ended booking without earnings is flagged for manual review', () {
    process(start);
    final ended = ObservationBuilder(at: start.add(const Duration(minutes: 5)))
      ..line('Booking Cancelled', top: 700);
    final decision = machine.process(ended.build(), store.active);
    store.apply(decision);

    expect(store.active!.bookingStatus, BookingState.errorRequiresReview);
    expect(store.active!.endedAt, isNotNull);
  });

  test('manual corrections are never overwritten by OCR', () {
    process(start);
    process(start.add(const Duration(seconds: 20)), expanded: true);
    final corrected = store.active!.copyWith(
      platformEarningsCents: 8000,
      fareToCollectCents: 9500,
      isManuallyEdited: true,
    );

    final decision = machine.process(
      earningsScreen(at: start.add(const Duration(minutes: 1))).build(),
      corrected,
    );

    final result = decision.updatedActive ?? corrected;
    expect(result.platformEarningsCents, 8000);
  });

  test('random non-booking screens do not create or alter records', () {
    process(start);
    final map = ObservationBuilder(at: start.add(const Duration(seconds: 10)))
      ..line('Google Maps', top: 100)
      ..line('Ayala Avenue', top: 1200)
      ..line('12 min • 3.4 km', top: 1300);

    final decision = machine.process(map.build(), store.active);
    expect(decision.action, DetectionAction.none);
    expect(store.active!.bookingStatus, BookingState.bookingDetected);
  });
}
