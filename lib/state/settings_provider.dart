import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/utils/money.dart';
import '../data/repositories/settings_repository.dart';
import '../domain/ocr/ocr_models.dart';

class SettingKeys {
  SettingKeys._();

  static const autoMonitoring = 'monitoring.auto_start';
  static const overlayEnabled = 'overlay.enabled';
  static const minConfidence = 'ocr.min_confidence';
  static const currency = 'display.currency';
  static const targetPackage = 'monitor.target_package';
  static const defaultTipType = 'tips.default_type';
  static const onboardingCompleted = 'onboarding.completed';
  static const installSalt = 'privacy.install_salt';
  static const lastReferenceDate = 'transactions.last_reference_date';
}

class SettingsProvider extends ChangeNotifier {
  SettingsProvider(this._repository);

  final SettingsRepository _repository;
  final Map<String, String> _values = {};
  bool _loaded = false;

  bool get loaded => _loaded;

  Future<void> load() async {
    _values.addAll(await _repository.loadAll());
    if ((_values[SettingKeys.installSalt] ?? '').isEmpty) {
      final salt = _generateSalt();
      _values[SettingKeys.installSalt] = salt;
      await _repository.put(SettingKeys.installSalt, salt);
    }
    OcrSignature.salt = _values[SettingKeys.installSalt]!;
    Money.setCurrency(currency);
    _loaded = true;
    notifyListeners();
  }

  String _generateSalt() {
    final random = Random.secure();
    return List.generate(24, (_) => random.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  String? _get(String key) => _values[key];

  Future<void> _set(String key, String value) async {
    _values[key] = value;
    await _repository.put(key, value);
    notifyListeners();
  }

  Future<void> _setBool(String key, bool value) => _set(key, value ? '1' : '0');

  bool _getBool(String key, {bool fallback = false}) {
    final value = _values[key];
    if (value == null) return fallback;
    return value == '1' || value.toLowerCase() == 'true';
  }

  bool get autoMonitoring => _getBool(SettingKeys.autoMonitoring);
  Future<void> setAutoMonitoring(bool value) =>
      _setBool(SettingKeys.autoMonitoring, value);

  bool get overlayEnabled => _getBool(SettingKeys.overlayEnabled);
  Future<void> setOverlayEnabled(bool value) =>
      _setBool(SettingKeys.overlayEnabled, value);

  double get minConfidence =>
      double.tryParse(_get(SettingKeys.minConfidence) ?? '') ?? 0.6;
  Future<void> setMinConfidence(double value) =>
      _set(SettingKeys.minConfidence, value.toStringAsFixed(2));

  String get currency => _get(SettingKeys.currency) ?? 'PHP';
  Future<void> setCurrency(String value) async {
    Money.setCurrency(value);
    await _set(SettingKeys.currency, value);
  }

  String get targetPackage =>
      _get(SettingKeys.targetPackage) ?? 'com.angkas.rider';
  Future<void> setTargetPackage(String value) =>
      _set(SettingKeys.targetPackage, value.trim());

  String get defaultTipType => _get(SettingKeys.defaultTipType) ?? 'cash';
  Future<void> setDefaultTipType(String value) =>
      _set(SettingKeys.defaultTipType, value);

  bool get onboardingCompleted => _getBool(SettingKeys.onboardingCompleted);
  Future<void> setOnboardingCompleted(bool value) =>
      _setBool(SettingKeys.onboardingCompleted, value);

  String get installSalt => _values[SettingKeys.installSalt] ?? 'simove-local-v1';

  Future<void> reset() async {
    await _repository.clear();
    _values.clear();
    _loaded = false;
    await load();
  }
}
