import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/ocr/ocr_models.dart';

class PermissionSnapshot {
  const PermissionSnapshot({
    this.notifications = false,
    this.overlay = false,
    this.usageAccess = false,
    this.notificationListener = false,
    this.batteryOptimizationIgnored = false,
    this.captureRunning = false,
    this.sdkInt = 0,
  });

  final bool notifications;
  final bool overlay;
  final bool usageAccess;
  final bool notificationListener;
  final bool batteryOptimizationIgnored;
  final bool captureRunning;
  final int sdkInt;

  bool get canMonitor => usageAccess;

  PermissionSnapshot copyWith({
    bool? notifications,
    bool? overlay,
    bool? usageAccess,
    bool? notificationListener,
    bool? batteryOptimizationIgnored,
    bool? captureRunning,
    int? sdkInt,
  }) {
    return PermissionSnapshot(
      notifications: notifications ?? this.notifications,
      overlay: overlay ?? this.overlay,
      usageAccess: usageAccess ?? this.usageAccess,
      notificationListener: notificationListener ?? this.notificationListener,
      batteryOptimizationIgnored:
          batteryOptimizationIgnored ?? this.batteryOptimizationIgnored,
      captureRunning: captureRunning ?? this.captureRunning,
      sdkInt: sdkInt ?? this.sdkInt,
    );
  }

  static const unknown = PermissionSnapshot();

  factory PermissionSnapshot.fromMap(Map<Object?, Object?>? map) {
    if (map == null) return unknown;
    bool read(String key) => map[key] == true;
    return PermissionSnapshot(
      notifications: read('notifications'),
      overlay: read('overlay'),
      usageAccess: read('usageAccess'),
      notificationListener: read('notificationListener'),
      batteryOptimizationIgnored: read('batteryOptimizationIgnored'),
      captureRunning: read('captureRunning'),
      sdkInt: (map['sdkInt'] as num?)?.toInt() ?? 0,
    );
  }
}

enum MonitoringEventType { ocr, status, notification, error }

class MonitoringEvent {
  const MonitoringEvent({
    required this.type,
    this.status,
    this.message,
    this.observation,
    this.foregroundPackage,
    this.notificationEvent,
  });

  final MonitoringEventType type;
  final String? status;
  final String? message;
  final ScreenObservation? observation;
  final String? foregroundPackage;
  final String? notificationEvent;

  factory MonitoringEvent.fromMap(Map<Object?, Object?> map) {
    final type = switch ((map['type'] as String?) ?? '') {
      'ocr' => MonitoringEventType.ocr,
      'notification' => MonitoringEventType.notification,
      'error' => MonitoringEventType.error,
      _ => MonitoringEventType.status,
    };
    final rawObservation = map['observation'] ?? (type == MonitoringEventType.ocr ? map : null);
    return MonitoringEvent(
      type: type,
      status: map['status'] as String?,
      message: map['message'] as String?,
      foregroundPackage: map['foregroundPackage'] as String?,
      notificationEvent: map['event'] as String?,
      observation: rawObservation is Map<Object?, Object?>
          ? ScreenObservation.fromMap(rawObservation)
          : null,
    );
  }
}

class MonitoringException implements Exception {
  MonitoringException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thin bridge to the native Android screen-capture / OCR / overlay service.
class MonitoringPlatform {
  MonitoringPlatform({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _methods = methodChannel ??
            const MethodChannel('simove/control'),
        _events = eventChannel ?? const EventChannel('simove/events');

  final MethodChannel _methods;
  final EventChannel _events;

  Stream<MonitoringEvent> get events => _events
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map((event) => MonitoringEvent.fromMap(event as Map<Object?, Object?>));

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _methods.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      throw MonitoringException(
        'Screen monitoring is only available in the Android app.',
      );
    } on PlatformException catch (error) {
      throw MonitoringException(error.message ?? 'Android service error.');
    }
  }

  Future<PermissionSnapshot> getPermissionStatus() async {
    final map = await _invoke<Map<Object?, Object?>>('getPermissionStatus');
    return PermissionSnapshot.fromMap(map);
  }

  Future<bool> startCapture() async =>
      await _invoke<bool>('startCapture') ?? false;

  Future<bool> stopCapture() async =>
      await _invoke<bool>('stopCapture') ?? false;

  Future<bool> isCaptureRunning() async =>
      await _invoke<bool>('isCaptureRunning') ?? false;

  Future<void> setTargetPackage(String packageName) =>
      _invoke<void>('setTargetPackage', {'package': packageName});

  Future<Map<Object?, Object?>?> getLastOcr() =>
      _invoke<Map<Object?, Object?>>('getLastOcr');

  Future<void> showOverlay(Map<String, Object?> data) =>
      _invoke<void>('showOverlay', data);

  Future<void> updateOverlay(Map<String, Object?> data) =>
      _invoke<void>('updateOverlay', data);

  Future<void> hideOverlay() => _invoke<void>('hideOverlay');

  Future<void> openSettings(String target) =>
      _invoke<void>('openSettings', {'target': target});

  Future<void> requestNotificationPermission() =>
      _invoke<void>('requestNotificationPermission');

  Future<void> openTargetApp() => _invoke<void>('openTargetApp');

  bool get isAndroid => defaultTargetPlatform == TargetPlatform.android;
}
