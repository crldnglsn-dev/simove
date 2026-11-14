import 'package:simove/domain/ocr/angkas_ocr_parser.dart';
import 'package:simove/domain/ocr/ocr_models.dart';

class ObservationBuilder {
  ObservationBuilder({this.width = 1080, this.height = 2400, DateTime? at})
    : at = at ?? DateTime(2026, 11, 14, 9, 0);

  final int width;
  final int height;
  final DateTime at;
  final List<OcrLine> _lines = [];

  ObservationBuilder line(
    String text, {
    double? top,
    double left = 80,
    double right = 1000,
    double lineHeight = 42,
    double? confidence = 0.95,
  }) {
    final y = top ?? (height * 0.5 + _lines.length * 50);
    _lines.add(
      OcrLine(
        text: text,
        left: left,
        top: y,
        right: right,
        bottom: y + lineHeight,
        confidence: confidence,
      ),
    );
    return this;
  }

  /// Marks every line as a low-confidence read, emulating a blurry frame.
  ObservationBuilder allConfidence(double value) {
    for (var i = 0; i < _lines.length; i++) {
      final line = _lines[i];
      _lines[i] = OcrLine(
        text: line.text,
        left: line.left,
        top: line.top,
        right: line.right,
        bottom: line.bottom,
        confidence: value,
      );
    }
    return this;
  }

  ScreenObservation build({String? packageName}) => ScreenObservation(
    lines: List.of(_lines),
    screenWidth: width,
    screenHeight: height,
    capturedAt: at,
    foregroundPackage: packageName ?? 'com.angkas.rider',
  );
}

ObservationBuilder acceptedBooking({
  DateTime? at,
  String pickup = 'Pickup: 123 Mabini Street, Makati',
  String dropoff = 'Drop-off: Ayala Avenue Tower 2',
}) {
  return ObservationBuilder(at: at)
    ..line('Booking Auto-accepted', top: 520)
    ..line('Proceed to Pickup', top: 620)
    ..line('1.2 km • 4 min', top: 700, confidence: 0.8)
    ..line(pickup, top: 1400)
    ..line(dropoff, top: 1480)
    ..line('OTW To Pickup', top: 1560);
}

ObservationBuilder earningsScreen({
  DateTime? at,
  String pickup = 'Pickup: 123 Mabini Street, Makati',
  String dropoff = 'Drop-off: Ayala Avenue Tower 2',
  String total = 'Total Earnings',
  String totalValue = '₱75.00',
  String fareValue = '₱95.00',
  String payment = 'Cash',
}) {
  return ObservationBuilder(at: at)
    ..line('Proceed to Pickup', top: 560)
    ..line(pickup, top: 1350)
    ..line(dropoff, top: 1430)
    ..line(total, top: 1550)
    ..line(totalValue, top: 1600)
    ..line('Fare To Collect', top: 1680)
    ..line(fareValue, top: 1730)
    ..line('Payment Method', top: 1800)
    ..line(payment, top: 1850);
}

/// The Angkas "Earnings" tab as observed on a real driver phone: weekly
/// summary cards plus a list of finished trips. It has no live booking panel
/// and must never produce a transaction.
ObservationBuilder earningsHistoryScreen({DateTime? at}) {
  return ObservationBuilder(at: at)
    ..line('Earnings', top: 176)
    ..line('Today', top: 276, left: 120)
    ..line('Yesterday', top: 276, left: 620)
    ..line('₱0.00', top: 384, left: 160)
    ..line('₱909.70', top: 384, left: 640)
    ..line('0 Trips', top: 459, left: 200)
    ..line('16 Trips', top: 459, left: 660)
    ..line('This Week', top: 600, left: 120)
    ..line('Last Week', top: 600, left: 620)
    ..line('₱5,367.90', top: 706, left: 140)
    ..line('₱4,657.66', top: 706, left: 640)
    ..line('99 Trips', top: 780, left: 190)
    ..line('87 Trips', top: 780, left: 660)
    ..line('Biker Cancelled', top: 1626)
    ..line('Passenger', top: 1688)
    ..line('₱53.40', top: 1649, left: 800)
    ..line('Net Earnings', top: 1745, left: 800)
    ..line('To Medical Arts Building | C...', top: 1723)
    ..line('14 Nov 2026, 10:05 AM', top: 1764)
    ..line('Biker Cancelled', top: 1940)
    ..line('₱75.00', top: 1963, left: 800)
    ..line('Net Earnings', top: 2059, left: 800)
    ..line('14 Nov 2026, 07:20 AM', top: 2078);
}

/// The real Angkas trip-details sheet captured on a driver phone. It uses
/// "Total Payment" for the amount the passenger pays and shows the trip status
/// as a chip ("Biker Cancelled" / "Biker Completed").
ObservationBuilder tripDetailsScreen({
  DateTime? at,
  String? status = 'Biker Cancelled',
  String totalValue = '₱55.90',
  String paymentValue = '₱76.00',
}) {
  final builder = ObservationBuilder(at: at)
    ..line('Passenger', top: 349)
    ..line('BOOKING ID 3M4vhgJRg91Q589exDz594sKULx', top: 422)
    ..line('Total Earnings', top: 574)
    ..line(totalValue, top: 694)
    ..line('Fare Earnings 20%', top: 917, left: 80)
    ..line('₱55.80', top: 917, left: 900)
    ..line('Cash Handling Earnings', top: 1031, left: 80)
    ..line('₱0.10', top: 1031, left: 900)
    ..line('CS Insurance Plus', top: 1112, left: 160)
    ..line('₱0.10', top: 1112, left: 900)
    ..line('Total Earnings  ₱55.90', top: 1238)
    ..line('Total Payment  $paymentValue', top: 1413)
    ..line('Collected Payment  $paymentValue', top: 1497, left: 160)
    ..line('Payment Method', top: 1619, left: 80)
    ..line('Cash', top: 1619, left: 900)
    ..line('56 Roxas St', top: 1794)
    ..line('Barangay 105, Tondo, Manila, Metro Manila, Philippines', top: 1843)
    ..line('Hi-Precision Diagnostics - A.H. Lacson Branch', top: 1933)
    ..line(
      'Mezzanine and 2nd floor, Pacific Skyloft Bldg., 1160 Governor Forbes, '
      '1008 Lacson Ave, Sampaloc, Manila',
      top: 2034,
    )
    ..line('Have concerns or issues about this trip?', top: 2276)
    ..line('Report an issue', top: 2390);
  if (status != null) {
    builder.line(status, top: 349, left: 600);
  }
  return builder;
}

AngkasOcrParser get parser => const AngkasOcrParser();
