import 'package:simove/domain/ocr/angkas_ocr_parser.dart';
import 'package:simove/domain/ocr/ocr_models.dart';

class ObservationBuilder {
  ObservationBuilder({
    this.width = 1080,
    this.height = 2400,
    DateTime? at,
  }) : at = at ?? DateTime(2026, 11, 14, 9, 0);

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

AngkasOcrParser get parser => const AngkasOcrParser();
