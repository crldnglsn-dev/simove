/// Booking lifecycle states tracked by the detection engine.
enum BookingState {
  idle,
  bookingDetected,
  waitingForEarnings,
  earningsDetected,
  recorded,
  bookingEnded,
  errorRequiresReview;

  static BookingState fromDb(String? value) {
    if (value == null) return BookingState.idle;
    final normalized = value
        .replaceAll('_', '')
        .replaceAll(' ', '')
        .toLowerCase();
    for (final state in BookingState.values) {
      if (state.name.toLowerCase() == normalized) return state;
    }
    return BookingState.idle;
  }

  String get dbValue => name;

  bool get isPending =>
      this == BookingState.bookingDetected ||
      this == BookingState.waitingForEarnings ||
      this == BookingState.earningsDetected ||
      this == BookingState.errorRequiresReview;

  bool get hasEarnings =>
      this == BookingState.earningsDetected ||
      this == BookingState.recorded ||
      this == BookingState.bookingEnded;

  String get label => switch (this) {
    BookingState.idle => 'Idle',
    BookingState.bookingDetected => 'Booking detected',
    BookingState.waitingForEarnings => 'Waiting for earnings',
    BookingState.earningsDetected => 'Earnings detected',
    BookingState.recorded => 'Recorded',
    BookingState.bookingEnded => 'Booking ended',
    BookingState.errorRequiresReview => 'Needs review',
  };
}

enum DetectionSource {
  ocr,
  manual,
  notification,
  imported;

  static DetectionSource fromDb(String? value) {
    for (final source in DetectionSource.values) {
      if (source.name == value) return source;
    }
    return DetectionSource.manual;
  }

  String get label => switch (this) {
    DetectionSource.ocr => 'Auto-detected',
    DetectionSource.manual => 'Manual entry',
    DetectionSource.notification => 'Notification',
    DetectionSource.imported => 'Imported',
  };
}

enum TipType {
  cash,
  digital,
  other;

  static TipType fromDb(String? value) {
    for (final type in TipType.values) {
      if (type.name == value) return type;
    }
    return TipType.cash;
  }

  String get label => switch (this) {
    TipType.cash => 'Cash',
    TipType.digital => 'Digital',
    TipType.other => 'Other',
  };
}

/// A single booking / earning record.
class BookingTransaction {
  const BookingTransaction({
    this.id,
    required this.bookingReference,
    required this.bookingStatus,
    required this.createdAt,
    required this.updatedAt,
    this.platformEarningsCents,
    this.fareToCollectCents,
    this.paymentMethod,
    this.tipCents = 0,
    this.tipType = TipType.cash,
    this.tipIncludedInPlatformEarnings = false,
    this.detectionSource = DetectionSource.manual,
    this.detectionConfidence,
    this.notes,
    this.screenSignature,
    this.bookingFingerprint,
    this.earningsDetectedAt,
    this.endedAt,
    this.isManuallyEdited = false,
  });

  final int? id;
  final String bookingReference;
  final BookingState bookingStatus;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int? platformEarningsCents;
  final int? fareToCollectCents;
  final String? paymentMethod;
  final int tipCents;
  final TipType tipType;
  final bool tipIncludedInPlatformEarnings;
  final DetectionSource detectionSource;
  final double? detectionConfidence;
  final String? notes;

  /// A salted hash of normalized on-screen text used for duplicate
  /// prevention. No passenger text or address is ever stored.
  final String? screenSignature;

  /// Salted hash of stable booking-panel text (pickup/drop-off area). Used to
  /// tell a genuinely new ride from the same ride being viewed again. The
  /// readable text is never stored.
  final String? bookingFingerprint;

  final DateTime? earningsDetectedAt;
  final DateTime? endedAt;

  /// Once the rider corrects a record, automatic OCR must never overwrite it.
  final bool isManuallyEdited;

  int get effectiveTipCents => tipIncludedInPlatformEarnings ? 0 : tipCents;

  /// Platform earnings plus additional tips that were not already included.
  int get recordedEarningsCents =>
      (platformEarningsCents ?? 0) + effectiveTipCents;

  bool get isComplete => bookingStatus == BookingState.recorded;

  bool get hasPlatformEarnings => platformEarningsCents != null;

  BookingTransaction copyWith({
    int? id,
    String? bookingReference,
    BookingState? bookingStatus,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? platformEarningsCents,
    bool clearPlatformEarnings = false,
    int? fareToCollectCents,
    bool clearFareToCollect = false,
    String? paymentMethod,
    bool clearPaymentMethod = false,
    int? tipCents,
    TipType? tipType,
    bool? tipIncludedInPlatformEarnings,
    DetectionSource? detectionSource,
    double? detectionConfidence,
    bool clearDetectionConfidence = false,
    String? notes,
    bool clearNotes = false,
    String? screenSignature,
    bool clearScreenSignature = false,
    String? bookingFingerprint,
    bool clearBookingFingerprint = false,
    DateTime? earningsDetectedAt,
    bool clearEarningsDetectedAt = false,
    DateTime? endedAt,
    bool clearEndedAt = false,
    bool? isManuallyEdited,
  }) {
    return BookingTransaction(
      id: id ?? this.id,
      bookingReference: bookingReference ?? this.bookingReference,
      bookingStatus: bookingStatus ?? this.bookingStatus,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      platformEarningsCents: clearPlatformEarnings
          ? null
          : platformEarningsCents ?? this.platformEarningsCents,
      fareToCollectCents: clearFareToCollect
          ? null
          : fareToCollectCents ?? this.fareToCollectCents,
      paymentMethod: clearPaymentMethod
          ? null
          : paymentMethod ?? this.paymentMethod,
      tipCents: tipCents ?? this.tipCents,
      tipType: tipType ?? this.tipType,
      tipIncludedInPlatformEarnings:
          tipIncludedInPlatformEarnings ?? this.tipIncludedInPlatformEarnings,
      detectionSource: detectionSource ?? this.detectionSource,
      detectionConfidence: clearDetectionConfidence
          ? null
          : detectionConfidence ?? this.detectionConfidence,
      notes: clearNotes ? null : notes ?? this.notes,
      screenSignature: clearScreenSignature
          ? null
          : screenSignature ?? this.screenSignature,
      bookingFingerprint: clearBookingFingerprint
          ? null
          : bookingFingerprint ?? this.bookingFingerprint,
      earningsDetectedAt: clearEarningsDetectedAt
          ? null
          : earningsDetectedAt ?? this.earningsDetectedAt,
      endedAt: clearEndedAt ? null : endedAt ?? this.endedAt,
      isManuallyEdited: isManuallyEdited ?? this.isManuallyEdited,
    );
  }

  Map<String, Object?> toDbMap() {
    return {
      if (id != null) 'id': id,
      'booking_reference': bookingReference,
      'booking_status': bookingStatus.dbValue,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'platform_earnings_cents': platformEarningsCents,
      'fare_to_collect_cents': fareToCollectCents,
      'payment_method': paymentMethod,
      'tip_cents': tipCents,
      'tip_type': tipType.name,
      'tip_included_in_platform_earnings': tipIncludedInPlatformEarnings
          ? 1
          : 0,
      'detection_source': detectionSource.name,
      'detection_confidence': detectionConfidence,
      'notes': notes,
      'screen_signature': screenSignature,
      'booking_fingerprint': bookingFingerprint,
      'earnings_detected_at': earningsDetectedAt?.millisecondsSinceEpoch,
      'ended_at': endedAt?.millisecondsSinceEpoch,
      'manually_edited': isManuallyEdited ? 1 : 0,
    };
  }

  static BookingTransaction fromDbMap(Map<String, Object?> map) {
    return BookingTransaction(
      id: map['id'] as int?,
      bookingReference: map['booking_reference'] as String? ?? '',
      bookingStatus: BookingState.fromDb(map['booking_status'] as String?),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['created_at'] as int?) ?? 0,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['updated_at'] as int?) ?? 0,
      ),
      platformEarningsCents: map['platform_earnings_cents'] as int?,
      fareToCollectCents: map['fare_to_collect_cents'] as int?,
      paymentMethod: map['payment_method'] as String?,
      tipCents: (map['tip_cents'] as int?) ?? 0,
      tipType: TipType.fromDb(map['tip_type'] as String?),
      tipIncludedInPlatformEarnings:
          ((map['tip_included_in_platform_earnings'] as int?) ?? 0) == 1,
      detectionSource: DetectionSource.fromDb(
        map['detection_source'] as String?,
      ),
      detectionConfidence: (map['detection_confidence'] as num?)?.toDouble(),
      notes: map['notes'] as String?,
      screenSignature: map['screen_signature'] as String?,
      bookingFingerprint: map['booking_fingerprint'] as String?,
      earningsDetectedAt: map['earnings_detected_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              map['earnings_detected_at'] as int,
            ),
      endedAt: map['ended_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(map['ended_at'] as int),
      isManuallyEdited: ((map['manually_edited'] as int?) ?? 0) == 1,
    );
  }
}
