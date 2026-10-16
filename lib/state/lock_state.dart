import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import 'settings_state.dart';

/// Whether the PIN screen is showing.
///
/// The diary locks when the app starts, and again when it comes back after
/// spending [SettingsState.lockAfterSeconds] in the background. A short
/// trip out — picking a photo, answering a call — doesn't re-lock.
class AppLock extends ChangeNotifier {
  AppLock(this.settings, {LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication() {
    _locked = settings.lockEnabled;
  }

  final SettingsState settings;
  final LocalAuthentication _auth;

  bool _locked = false;
  DateTime? _backgroundedAt;
  int _failedAttempts = 0;
  DateTime? _coolDownUntil;

  bool get locked => _locked && settings.lockEnabled;

  /// After 5 wrong PINs, wait 30 seconds before the next try.
  Duration get coolDownLeft {
    final until = _coolDownUntil;
    if (until == null) return Duration.zero;
    final left = until.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  void onBackgrounded() => _backgroundedAt = DateTime.now();

  void onForegrounded() {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (!settings.lockEnabled || since == null) return;
    if (DateTime.now().difference(since).inSeconds >= settings.lockAfterSeconds) {
      _locked = true;
      notifyListeners();
    }
  }

  void lockNow() {
    if (!settings.lockEnabled) return;
    _locked = true;
    notifyListeners();
  }

  /// Returns null on success, otherwise the message to show.
  String? unlockWithPin(String pin) {
    if (coolDownLeft > Duration.zero) {
      return 'Too many tries. Wait ${coolDownLeft.inSeconds} s.';
    }
    if (settings.checkPin(pin)) {
      _unlock();
      return null;
    }
    _failedAttempts++;
    if (_failedAttempts % 5 == 0) {
      _coolDownUntil = DateTime.now().add(const Duration(seconds: 30));
      return 'Wrong PIN. Try again in 30 seconds.';
    }
    return 'Wrong PIN';
  }

  Future<bool> canUseBiometrics() async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } catch (_) {
      // No sensor, no plugin (tests), or the OS refused: PIN only.
      return false;
    }
  }

  Future<bool> unlockWithBiometrics() async {
    if (!settings.biometricEnabled) return false;
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Unlock your Broker Diary',
        biometricOnly: true,
      );
      if (ok) _unlock();
      return ok;
    } on PlatformException {
      return false;
    } on LocalAuthException {
      return false;
    }
  }

  /// Confirms a fingerprint works before turning it on in Settings.
  Future<bool> confirmBiometrics() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Confirm to use your fingerprint for Broker Diary',
        biometricOnly: true,
      );
    } on PlatformException {
      return false;
    } on LocalAuthException {
      return false;
    }
  }

  void _unlock() {
    _locked = false;
    _failedAttempts = 0;
    _coolDownUntil = null;
    notifyListeners();
  }

  /// After "Forgot PIN → erase", or when the lock is switched off.
  void reset() => _unlock();
}
