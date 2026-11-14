import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/utils/money.dart';
import '../data/models/booking_transaction.dart';
import '../data/repositories/transaction_repository.dart';
import '../domain/detection/booking_state_machine.dart';
import '../domain/ocr/ocr_models.dart';
import '../services/monitoring_platform.dart';
import 'earnings_provider.dart';
import 'settings_provider.dart';

enum MonitoringStatus { off, starting, monitoring, needsPermission, error }

class MonitoringProvider extends ChangeNotifier {
  MonitoringProvider({
    required TransactionRepository transactionRepository,
    required SettingsProvider settings,
    required EarningsProvider earnings,
    MonitoringPlatform? platform,
    BookingStateMachine? machine,
  })  : _transactions = transactionRepository,
        // ignore: prefer_initializing_formals
        _settings = settings,
        // ignore: prefer_initializing_formals
        _earnings = earnings,
        _platform = platform ?? MonitoringPlatform(),
        _machine = machine ?? BookingStateMachine();

  final TransactionRepository _transactions;
  final SettingsProvider _settings;
  final EarningsProvider _earnings;
  final MonitoringPlatform _platform;
  final BookingStateMachine _machine;

  StreamSubscription<MonitoringEvent>? _subscription;
  MonitoringStatus _status = MonitoringStatus.off;
  PermissionSnapshot _permissions = PermissionSnapshot.unknown;
  BookingTransaction? _active;
  ParsedBookingScreen? _lastScreen;
  DateTime? _lastOcrAt;
  String _lastReason = 'Monitoring is off';
  String? _lastError;
  String? _notificationHint;
  bool _overlayShown = false;
  bool _initialized = false;
  bool _busy = false;

  MonitoringStatus get status => _status;
  PermissionSnapshot get permissions => _permissions;
  BookingTransaction? get activeTransaction => _active;
  ParsedBookingScreen? get lastScreen => _lastScreen;
  DateTime? get lastOcrAt => _lastOcrAt;
  String get lastReason => _lastReason;
  String? get lastError => _lastError;
  String? get notificationHint => _notificationHint;
  bool get initialized => _initialized;
  bool get isMonitoring => _status == MonitoringStatus.monitoring;
  bool get isBusy => _busy;

  String get statusLabel => switch (_status) {
        MonitoringStatus.off => 'Monitoring off',
        MonitoringStatus.starting => 'Starting…',
        MonitoringStatus.monitoring => 'Monitoring Angkas',
        MonitoringStatus.needsPermission => 'Permission needed',
        MonitoringStatus.error => 'Monitoring stopped',
      };

  Future<void> init() async {
    if (_initialized) return;
    _subscription = _platform.events.listen(
      _onEvent,
      onError: (Object error) {
        _lastError = 'Monitoring event error: $error';
        notifyListeners();
      },
    );
    debugPrint('[SIMOVE] native event stream subscribed');
    _active = await _transactions.latestActive();
    await refreshPermissions();
    await _pushTargetPackage();

    if (_permissions.captureRunning) {
      _status = MonitoringStatus.monitoring;
      _lastReason = 'Screen capture is running';
    }

    final cached = await _platform.getLastOcr().catchError((_) => null);
    if (cached != null) {
      try {
        final observation = ScreenObservation.fromMap(cached);
        if (DateTime.now().difference(observation.capturedAt) <
            const Duration(minutes: 5)) {
          await _handleObservation(observation);
        }
      } catch (error) {
        debugPrint('Could not restore last OCR frame: $error');
      }
    }

    _initialized = true;
    notifyListeners();
  }

  Future<void> refreshPermissions() async {
    try {
      _permissions = await _platform.getPermissionStatus();
      if (_permissions.canMonitor == false && isMonitoring) {
        _status = MonitoringStatus.needsPermission;
        _lastReason = 'Usage access is required to detect when Angkas is open';
      }
      notifyListeners();
    } catch (error) {
      debugPrint('Permission status unavailable: $error');
    }
  }

  Future<void> startMonitoring() async {
    if (_busy || _status == MonitoringStatus.monitoring) return;
    _busy = true;
    _status = MonitoringStatus.starting;
    _lastError = null;
    _lastReason = 'Requesting screen capture permission…';
    notifyListeners();
    try {
      await _pushTargetPackage();
      await _platform.setTargetPackage(_settings.targetPackage);
      await refreshPermissions();
      if (!_permissions.notifications &&
          _permissions.sdkInt >= 33) {
        await _platform.requestNotificationPermission().catchError((_) {});
      }
      final granted = await _platform.startCapture();
      if (!granted) {
        _status = MonitoringStatus.off;
        _lastReason = 'Screen capture permission was not granted';
        _lastError = _lastReason;
      } else {
        _status = MonitoringStatus.monitoring;
        _lastReason = 'Screen capture started';
        await _settings.setAutoMonitoring(true);
        await refreshPermissions();
        // The service reports foreground app state shortly after starting.
        await _handleCachedFrame();
      }
    } on MonitoringException catch (error) {
      _status = MonitoringStatus.error;
      _lastError = error.message;
      _lastReason = error.message;
    } catch (error) {
      _status = MonitoringStatus.error;
      _lastError = 'Could not start monitoring: $error';
      _lastReason = _lastError!;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> stopMonitoring() async {
    if (_busy) return;
    _busy = true;
    notifyListeners();
    try {
      await _platform.stopCapture();
      await _settings.setAutoMonitoring(false);
      _status = MonitoringStatus.off;
      _lastReason = 'Monitoring stopped';
      _active = await _transactions.latestActive();
    } catch (error) {
      _lastError = 'Could not stop monitoring: $error';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> toggleMonitoring() async {
    if (isMonitoring) {
      await stopMonitoring();
    } else {
      await startMonitoring();
    }
  }

  Future<void> _handleCachedFrame() async {
    final cached = await _platform.getLastOcr().catchError((_) => null);
    if (cached == null) return;
    try {
      await _handleObservation(ScreenObservation.fromMap(cached));
    } catch (error) {
      debugPrint('Could not process cached OCR frame: $error');
    }
  }

  void _onEvent(MonitoringEvent event) {
    switch (event.type) {
      case MonitoringEventType.ocr:
        final observation = event.observation;
        if (observation != null) {
          unawaited(_handleObservation(observation));
        }
        break;
      case MonitoringEventType.status:
        _handleStatus(event.status, event.message);
        break;
      case MonitoringEventType.notification:
        _notificationHint = event.notificationEvent == null
            ? null
            : 'Angkas notification: ${event.notificationEvent}';
        notifyListeners();
        break;
      case MonitoringEventType.error:
        _status = MonitoringStatus.error;
        _lastError = event.message ?? 'Screen capture error';
        _lastReason = _lastError!;
        notifyListeners();
        break;
    }
  }

  void _handleStatus(String? status, String? message) {
    switch (status) {
      case 'monitoring':
        _status = MonitoringStatus.monitoring;
        _lastReason = message ?? 'Monitoring Angkas';
        break;
      case 'paused':
      case 'permission_required':
        _status = MonitoringStatus.needsPermission;
        _lastReason = message ?? 'Permission required';
        break;
      case 'stopped':
      case 'capture_stopped':
        _status = MonitoringStatus.off;
        _lastReason = message ?? 'Monitoring stopped';
        break;
      case 'capture_started':
        _status = MonitoringStatus.monitoring;
        _lastReason = message ?? 'Screen capture started';
        break;
      case 'error':
        _status = MonitoringStatus.error;
        _lastError = message;
        _lastReason = message ?? 'Monitoring error';
        break;
      default:
        if (message != null) _lastReason = message;
    }
    notifyListeners();
  }

  Future<void> _handleObservation(ScreenObservation observation) async {
    final active = await _transactions.latestActive();
    _active = active;
    final decision = _machine.process(
      observation,
      active,
      confidenceThreshold: _settings.minConfidence,
    );

    var changed = false;
    var updated = active;
    try {
      if (decision.updatedActive != null && active != null) {
        updated = await _transactions.update(decision.updatedActive!);
        changed = true;
      }
      if (decision.newTransaction != null) {
        updated = await _transactions.insertDetected(decision.newTransaction!);
        changed = true;
      }
    } catch (error) {
      _lastError = 'Could not save detected booking: $error';
      _lastReason = _lastError!;
      notifyListeners();
      return;
    }

    _active = (updated != null && updated.endedAt == null) ? updated : null;
    _lastScreen = decision.screen;
    _lastOcrAt = observation.capturedAt;
    _lastReason = decision.reason;
    _lastError = null;
    debugPrint(
      '[SIMOVE] frame=${observation.frameId} lines=${observation.lines.length} '
      'reason=${decision.reason} confidence=${decision.confidence.toStringAsFixed(2)} '
      'signals=${decision.signals.join(",")} action=${decision.action.name}',
    );

    if (changed) {
      await _earnings.refresh();
      await syncOverlay();
    }
    notifyListeners();
  }

  Future<void> _pushTargetPackage() async {
    try {
      await _platform.setTargetPackage(_settings.targetPackage);
    } catch (error) {
      debugPrint('Could not sync target package: $error');
    }
  }

  Future<void> openSettings(String target) async {
    try {
      await _platform.openSettings(target);
      await refreshPermissions();
    } catch (error) {
      _lastError = 'Could not open Android settings: $error';
      notifyListeners();
    }
  }

  Future<void> openAngkas() async {
    try {
      await _platform.openTargetApp();
    } catch (error) {
      _lastError = 'Could not open ${_settings.targetPackage}: $error';
      notifyListeners();
    }
  }

  Future<void> setOverlayEnabled(bool enabled) async {
    await _settings.setOverlayEnabled(enabled);
    if (enabled) {
      await syncOverlay(force: true);
    } else {
      await _platform.hideOverlay().catchError((_) {});
      _overlayShown = false;
    }
    notifyListeners();
  }

  Future<void> syncOverlay({bool force = false}) async {
    if (!_settings.overlayEnabled) return;
    try {
      final today = _earnings.today;
      final latest =
          _earnings.recent.isNotEmpty ? _earnings.recent.first : null;
      final data = <String, Object?>{
        'today': Money.format(today.recordedEarningsCents),
        'tips': Money.format(today.tipsCents),
        'bookings': today.bookingCount.toString(),
        'latest': latest?.hasPlatformEarnings == true
            ? Money.format(latest!.recordedEarningsCents)
            : '—',
        'status': statusLabel,
        'reference': _active?.bookingReference ??
            latest?.bookingReference ??
            '',
      };
      if (_overlayShown && !force) {
        await _platform.updateOverlay(data);
      } else {
        await _platform.showOverlay(data);
        _overlayShown = true;
      }
    } catch (error) {
      debugPrint('Overlay update failed: $error');
    }
  }

  Future<void> applyTargetPackage(String packageName) async {
    await _settings.setTargetPackage(packageName);
    await _pushTargetPackage();
    notifyListeners();
  }

  Future<void> applyConfidence(double value) async {
    await _settings.setMinConfidence(value);
    _machine.minConfidence = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
