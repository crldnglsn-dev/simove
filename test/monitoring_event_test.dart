import 'package:flutter_test/flutter_test.dart';
import 'package:simove/services/monitoring_platform.dart';

void main() {
  group('MonitoringEvent.fromMap', () {
    test('reads the flat OCR payload emitted by the native service', () {
      final event = MonitoringEvent.fromMap(<Object?, Object?>{
        'type': 'ocr',
        'timestamp': 1700000000000,
        'packageName': 'com.angkas.rider',
        'screenWidth': 1080,
        'screenHeight': 2400,
        'frameId': 7,
        'lines': <Object?>[
          <Object?, Object?>{
            'text': 'Total Earnings',
            'left': 42.0,
            'top': 900.0,
            'right': 500.0,
            'bottom': 950.0,
            'confidence': 0.93,
          },
          <Object?, Object?>{
            'text': '₱75.00',
            'left': 700.0,
            'top': 900.0,
            'right': 1000.0,
            'bottom': 950.0,
            'confidence': null,
          },
        ],
      });

      expect(event.type, MonitoringEventType.ocr);
      final observation = event.observation;
      expect(observation, isNotNull);
      expect(observation!.frameId, 7);
      expect(observation.foregroundPackage, 'com.angkas.rider');
      expect(observation.screenHeight, 2400);
      expect(observation.capturedAt.millisecondsSinceEpoch, 1700000000000);
      expect(observation.lines, hasLength(2));
      expect(observation.lines.first.text, 'Total Earnings');
      expect(observation.lines.first.confidence, closeTo(0.93, 0.001));
      expect(observation.lines.last.text, '₱75.00');
      expect(observation.lines.last.top, 900.0);
    });

    test('still accepts a nested observation payload', () {
      final event = MonitoringEvent.fromMap(<Object?, Object?>{
        'type': 'ocr',
        'observation': <Object?, Object?>{
          'timestamp': 1700000000000,
          'screenWidth': 1080,
          'screenHeight': 2400,
          'frameId': 3,
          'lines': <Object?>[],
        },
      });

      expect(event.observation, isNotNull);
      expect(event.observation!.frameId, 3);
    });

    test('ignores status events that carry no observation', () {
      final event = MonitoringEvent.fromMap(<Object?, Object?>{
        'type': 'status',
        'status': 'monitoring',
        'message': 'Waiting for Angkas',
      });

      expect(event.type, MonitoringEventType.status);
      expect(event.observation, isNull);
      expect(event.status, 'monitoring');
    });
  });
}
