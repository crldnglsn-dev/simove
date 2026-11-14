import '../../data/models/booking_transaction.dart';
import '../ocr/angkas_ocr_parser.dart';
import '../ocr/ocr_models.dart';

enum DetectionAction { none, update, create }

/// The outcome of evaluating one OCR frame against the active booking.
class DetectionDecision {
  const DetectionDecision({
    required this.action,
    required this.reason,
    this.updatedActive,
    this.newTransaction,
    this.screen,
    this.confidence = 0,
    this.signals = const [],
  });

  final DetectionAction action;
  final String reason;

  /// Updated version of the currently open booking, if it changed.
  final BookingTransaction? updatedActive;

  /// Draft to insert. Its `bookingReference` is assigned by the repository.
  final BookingTransaction? newTransaction;
  final ParsedBookingScreen? screen;
  final double confidence;
  final List<String> signals;

  bool get createsTransaction => action == DetectionAction.create;
  bool get updatesTransaction => action == DetectionAction.update;

  static const idle = DetectionDecision(
    action: DetectionAction.none,
    reason: 'Waiting for Angkas booking screen',
  );
}

/// Stateful booking detector.
///
/// One instance lives for the whole monitoring session. It never invents
/// earnings, never stores passenger data, and never creates a second record
/// while the same booking is still visible.
class BookingStateMachine {
  BookingStateMachine({
    this.parser = const AngkasOcrParser(),
    this.minConfidence = 0.6,
  });

  final AngkasOcrParser parser;
  double minConfidence;

  static const Duration _strongNewBookingDelay = Duration(seconds: 12);
  static const Duration _weakNewBookingDelay = Duration(seconds: 45);
  static const Duration _stalePendingAge = Duration(minutes: 45);
  static const Duration _signatureRefresh = Duration(minutes: 2);

  String? _candidateSignature;
  int _candidateCount = 0;

  DetectionDecision process(
    ScreenObservation observation,
    BookingTransaction? active, {
    double? confidenceThreshold,
  }) {
    final parsed = parser.parse(observation);
    final threshold = confidenceThreshold ?? minConfidence;
    final now = observation.capturedAt;

    if (!parsed.isLikelyBookingScreen) {
      _resetCandidate();
      return DetectionDecision(
        action: DetectionAction.none,
        reason: 'No Angkas booking information on screen',
        screen: parsed,
        confidence: parsed.confidence,
      );
    }

    if (active == null) {
      if (parsed.hasEndedSignal || parsed.hasCancelledSignal) {
        return DetectionDecision(
          action: DetectionAction.none,
          reason: 'Idle Angkas screen',
          screen: parsed,
          confidence: parsed.confidence,
        );
      }
      final hasEarningsValue = parsed.totalEarningsCents != null;
      // A past-trip detail sheet can show earnings without any live booking
      // signal. It must never create a second record for a finished trip.
      final canCreateFromEarnings =
          parsed.hasEarningsPanel &&
          hasEarningsValue &&
          !parsed.isHistoricalDetail;
      if (parsed.hasAcceptedSignal || canCreateFromEarnings) {
        return DetectionDecision(
          action: DetectionAction.create,
          reason: parsed.hasAcceptedSignal
              ? 'New booking detected'
              : 'Earnings visible without an open booking',
          newTransaction: _draft(parsed, now, threshold),
          screen: parsed,
          confidence: parsed.confidence,
          signals: parsed.signals,
        );
      }
      return DetectionDecision(
        action: DetectionAction.none,
        reason: 'No booking detected',
        screen: parsed,
        confidence: parsed.confidence,
      );
    }

    if (parsed.hasEndedSignal || parsed.hasCancelledSignal) {
      _resetCandidate();
      final hasEarnings = active.platformEarningsCents != null;
      final state = hasEarnings
          ? (active.bookingStatus == BookingState.recorded
                ? BookingState.bookingEnded
                : BookingState.errorRequiresReview)
          : BookingState.errorRequiresReview;
      return DetectionDecision(
        action: DetectionAction.update,
        reason: parsed.hasCancelledSignal
            ? 'Booking cancelled'
            : (hasEarnings
                  ? 'Booking ended'
                  : 'Booking ended without detected earnings — review needed'),
        updatedActive: active.copyWith(
          bookingStatus: state,
          updatedAt: now,
          endedAt: now,
          screenSignature: parsed.signature,
          bookingFingerprint:
              active.bookingFingerprint ?? parsed.bookingFingerprint,
        ),
        screen: parsed,
        confidence: parsed.confidence,
        signals: parsed.signals,
      );
    }

    final signatureChanged = parsed.signature != active.screenSignature;
    final earningsChanged =
        parsed.totalEarningsCents != null &&
        parsed.totalEarningsCents != active.platformEarningsCents;
    final sinceEarnings = active.earningsDetectedAt == null
        ? null
        : now.difference(active.earningsDetectedAt!);

    final activeHasRecordedValues =
        active.bookingStatus == BookingState.recorded ||
        active.bookingStatus == BookingState.earningsDetected;
    final isPendingWithoutEarnings =
        active.bookingStatus == BookingState.bookingDetected ||
        active.bookingStatus == BookingState.waitingForEarnings;
    final fingerprintAvailable =
        parsed.bookingFingerprint != null && active.bookingFingerprint != null;
    final fingerprintChanged =
        fingerprintAvailable &&
        parsed.bookingFingerprint != active.bookingFingerprint;
    final fingerprintSame =
        fingerprintAvailable &&
        parsed.bookingFingerprint == active.bookingFingerprint;

    if (activeHasRecordedValues && parsed.hasAcceptedSignal) {
      if (fingerprintChanged) {
        if (earningsChanged) {
          _resetCandidate();
          return _createAfter(
            active,
            parsed,
            now,
            threshold,
            'New booking confirmed',
          );
        }
        // The booking-panel text changed, but no new earnings are visible yet.
        // Confirm with a second consecutive frame before creating a record.
        if (_candidateSignature == parsed.signature) {
          _candidateCount++;
        } else {
          _candidateSignature = parsed.signature;
          _candidateCount = 1;
        }
        if (_candidateCount >= 2) {
          _resetCandidate();
          return _createAfter(
            active,
            parsed,
            now,
            threshold,
            'New booking pickup screen confirmed',
          );
        }
        return DetectionDecision(
          action: DetectionAction.none,
          reason: 'Checking whether this is a new booking',
          screen: parsed,
          confidence: parsed.confidence,
          signals: parsed.signals,
        );
      }

      if (!fingerprintSame &&
          (active.bookingFingerprint == null ||
              parsed.bookingFingerprint == null)) {
        // Fall back to timing when a stable fingerprint is unavailable.
        if (earningsChanged &&
            signatureChanged &&
            (sinceEarnings == null || sinceEarnings > _strongNewBookingDelay)) {
          _resetCandidate();
          return _createAfter(
            active,
            parsed,
            now,
            threshold,
            'New booking confirmed',
          );
        }
        if (!parsed.hasEarningsPanel &&
            signatureChanged &&
            (sinceEarnings == null || sinceEarnings > _weakNewBookingDelay)) {
          if (_candidateSignature == parsed.signature) {
            _candidateCount++;
          } else {
            _candidateSignature = parsed.signature;
            _candidateCount = 1;
          }
          if (_candidateCount >= 2) {
            _resetCandidate();
            return _createAfter(
              active,
              parsed,
              now,
              threshold,
              'New booking pickup screen confirmed',
            );
          }
          return DetectionDecision(
            action: DetectionAction.none,
            reason: 'Checking whether this is a new booking',
            screen: parsed,
            confidence: parsed.confidence,
            signals: parsed.signals,
          );
        }
      }
    }
    _resetCandidate();

    // A pending record that has been open for too long is stale (the rider
    // likely finished the ride while detection was unavailable).
    if (isPendingWithoutEarnings &&
        now.difference(active.createdAt) > _stalePendingAge &&
        parsed.hasAcceptedSignal &&
        signatureChanged) {
      return DetectionDecision(
        action: DetectionAction.create,
        reason: 'Stale pending booking closed — new booking detected',
        updatedActive: active.copyWith(
          bookingStatus: BookingState.errorRequiresReview,
          updatedAt: now,
          endedAt: now,
          screenSignature: parsed.signature,
        ),
        newTransaction: _draft(parsed, now, threshold),
        screen: parsed,
        confidence: parsed.confidence,
        signals: parsed.signals,
      );
    }

    if (active.isManuallyEdited && active.platformEarningsCents != null) {
      if (signatureChanged &&
          now.difference(active.updatedAt) > _signatureRefresh) {
        return DetectionDecision(
          action: DetectionAction.update,
          reason: 'Manual values preserved',
          updatedActive: active.copyWith(
            updatedAt: now,
            screenSignature: parsed.signature,
            bookingFingerprint:
                active.bookingFingerprint ?? parsed.bookingFingerprint,
          ),
          screen: parsed,
          confidence: parsed.confidence,
          signals: parsed.signals,
        );
      }
      return DetectionDecision(
        action: DetectionAction.none,
        reason: 'Manual values preserved',
        screen: parsed,
        confidence: parsed.confidence,
        signals: parsed.signals,
      );
    }

    if (parsed.hasEarningsPanel || parsed.totalEarningsCents != null) {
      return _updateWithEarnings(active, parsed, now, threshold);
    }

    if (parsed.hasAcceptedSignal) {
      final state = active.bookingStatus.isPending
          ? active.bookingStatus
          : BookingState.bookingDetected;
      if (signatureChanged &&
          now.difference(active.updatedAt) > _signatureRefresh) {
        return DetectionDecision(
          action: DetectionAction.update,
          reason: 'Booking still active',
          updatedActive: active.copyWith(
            bookingStatus: state == BookingState.recorded
                ? BookingState.bookingDetected
                : state,
            updatedAt: now,
            screenSignature: parsed.signature,
            bookingFingerprint:
                active.bookingFingerprint ?? parsed.bookingFingerprint,
          ),
          screen: parsed,
          confidence: parsed.confidence,
          signals: parsed.signals,
        );
      }
      return DetectionDecision(
        action: DetectionAction.none,
        reason: 'Booking still active — waiting for earnings',
        screen: parsed,
        confidence: parsed.confidence,
        signals: parsed.signals,
      );
    }

    return DetectionDecision(
      action: DetectionAction.none,
      reason: 'Screen not understood — booking kept',
      screen: parsed,
      confidence: parsed.confidence,
      signals: parsed.signals,
    );
  }

  DetectionDecision _updateWithEarnings(
    BookingTransaction active,
    ParsedBookingScreen parsed,
    DateTime now,
    double threshold,
  ) {
    var earnings = parsed.totalEarningsCents ?? active.platformEarningsCents;
    var fare = parsed.fareToCollectCents ?? active.fareToCollectCents;
    var payment = parsed.paymentMethod ?? active.paymentMethod;

    if (active.isManuallyEdited) {
      earnings = active.platformEarningsCents ?? earnings;
      fare = active.fareToCollectCents ?? fare;
      payment = active.paymentMethod ?? payment;
    }

    final hasBoth = earnings != null && fare != null;
    final trustworthy = hasBoth && parsed.confidence >= threshold;
    final nextState = trustworthy
        ? BookingState.recorded
        : (earnings != null
              ? BookingState.errorRequiresReview
              : (active.bookingStatus.isPending
                    ? active.bookingStatus
                    : BookingState.waitingForEarnings));

    final onlySignatureChanged =
        earnings == active.platformEarningsCents &&
        fare == active.fareToCollectCents &&
        payment == active.paymentMethod &&
        nextState == active.bookingStatus;

    // A partially readable or blurry frame (for example during a scroll) must
    // not un-record an already verified booking. Only downgrade to review when
    // this frame actually proposes different values.
    final valuesUnchanged =
        (parsed.totalEarningsCents == null ||
            parsed.totalEarningsCents == active.platformEarningsCents) &&
        (parsed.fareToCollectCents == null ||
            parsed.fareToCollectCents == active.fareToCollectCents) &&
        (parsed.paymentMethod == null ||
            parsed.paymentMethod == active.paymentMethod);
    if (nextState == BookingState.errorRequiresReview &&
        active.bookingStatus == BookingState.recorded &&
        valuesUnchanged) {
      return DetectionDecision(
        action: DetectionAction.none,
        reason: 'Earnings already recorded',
        screen: parsed,
        confidence: parsed.confidence,
        signals: parsed.signals,
      );
    }

    if (onlySignatureChanged &&
        now.difference(active.updatedAt) < _signatureRefresh) {
      return DetectionDecision(
        action: DetectionAction.none,
        reason: active.bookingStatus == BookingState.recorded
            ? 'Earnings already recorded'
            : 'Waiting for a clearer view of earnings',
        screen: parsed,
        confidence: parsed.confidence,
        signals: parsed.signals,
      );
    }

    final reason = switch (nextState) {
      BookingState.recorded => 'Earnings recorded',
      BookingState.errorRequiresReview =>
        'Earnings detected with low confidence — review needed',
      _ => 'Earnings detected — waiting for complete values',
    };

    return DetectionDecision(
      action: DetectionAction.update,
      reason: reason,
      updatedActive: active.copyWith(
        bookingStatus: nextState,
        updatedAt: now,
        platformEarningsCents: earnings,
        fareToCollectCents: fare,
        paymentMethod: payment,
        detectionConfidence: parsed.confidence,
        detectionSource: active.detectionSource == DetectionSource.manual
            ? DetectionSource.manual
            : DetectionSource.ocr,
        screenSignature: parsed.signature,
        bookingFingerprint:
            active.bookingFingerprint ?? parsed.bookingFingerprint,
        earningsDetectedAt: earnings != null
            ? active.earningsDetectedAt ?? now
            : active.earningsDetectedAt,
      ),
      screen: parsed,
      confidence: parsed.confidence,
      signals: parsed.signals,
    );
  }

  DetectionDecision _createAfter(
    BookingTransaction active,
    ParsedBookingScreen parsed,
    DateTime now,
    double threshold,
    String reason,
  ) {
    final remaining = active.copyWith(
      bookingStatus: active.hasPlatformEarnings
          ? BookingState.bookingEnded
          : BookingState.errorRequiresReview,
      updatedAt: now,
      endedAt: now,
    );
    return DetectionDecision(
      action: DetectionAction.create,
      reason: reason,
      updatedActive: remaining,
      newTransaction: _draft(parsed, now, threshold),
      screen: parsed,
      confidence: parsed.confidence,
      signals: parsed.signals,
    );
  }

  BookingTransaction _draft(
    ParsedBookingScreen parsed,
    DateTime now,
    double threshold,
  ) {
    final hasEarnings = parsed.totalEarningsCents != null;
    final complete =
        hasEarnings &&
        parsed.fareToCollectCents != null &&
        parsed.confidence >= threshold;
    final state = complete
        ? BookingState.recorded
        : (hasEarnings
              ? BookingState.errorRequiresReview
              : (parsed.hasEarningsPanel
                    ? BookingState.waitingForEarnings
                    : BookingState.bookingDetected));

    return BookingTransaction(
      bookingReference: '',
      bookingStatus: state,
      createdAt: now,
      updatedAt: now,
      platformEarningsCents: parsed.totalEarningsCents,
      fareToCollectCents: parsed.fareToCollectCents,
      paymentMethod: parsed.paymentMethod,
      detectionSource: DetectionSource.ocr,
      detectionConfidence: parsed.confidence,
      screenSignature: parsed.signature,
      bookingFingerprint: parsed.bookingFingerprint,
      earningsDetectedAt: hasEarnings ? now : null,
    );
  }

  void _resetCandidate() {
    _candidateSignature = null;
    _candidateCount = 0;
  }
}
