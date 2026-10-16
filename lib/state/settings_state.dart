import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;

import '../data/diary_storage.dart';

/// Preferences, saved to `settings.json` next to the diary.
///
/// Settings are deliberately *not* part of a backup: restoring on a new
/// phone shouldn't carry over the old phone's PIN.
class SettingsState extends ChangeNotifier {
  SettingsState(this._storage);

  final DiaryStorage _storage;

  static const fileName = 'settings';

  bool _loaded = false;
  bool _darkMode = false;

  // Reminders
  bool _remindersEnabled = true;
  bool _digestEnabled = true;
  TimeOfDay _digestTime = const TimeOfDay(hour: 8, minute: 30);
  int _visitLeadMinutes = 60;

  // App lock
  String? _pinHash;
  String? _pinSalt;
  int _pinLength = 4;
  bool _biometricEnabled = false;
  int _lockAfterSeconds = 60;

  // Backup
  DateTime? _lastBackupAt;
  DateTime? _backupNudgeSnoozedUntil;

  bool get loaded => _loaded;

  Future<void> load() async {
    final j = await _storage.read(fileName) ?? const <String, dynamic>{};
    _darkMode = j['darkMode'] == true;
    _remindersEnabled = j['remindersEnabled'] != false;
    _digestEnabled = j['digestEnabled'] != false;
    final dh = j['digestHour'], dm = j['digestMinute'];
    if (dh is int && dm is int) {
      _digestTime = TimeOfDay(hour: dh.clamp(0, 23), minute: dm.clamp(0, 59));
    }
    final vl = j['visitLeadMinutes'];
    if (vl is int) _visitLeadMinutes = vl;
    _pinHash = j['pinHash'] as String?;
    _pinSalt = j['pinSalt'] as String?;
    final pl = j['pinLength'];
    if (pl is int) _pinLength = pl;
    _biometricEnabled = j['biometricEnabled'] == true;
    final la = j['lockAfterSeconds'];
    if (la is int) _lockAfterSeconds = la;
    _lastBackupAt = DateTime.tryParse(j['lastBackupAt']?.toString() ?? '');
    _backupNudgeSnoozedUntil =
        DateTime.tryParse(j['backupNudgeSnoozedUntil']?.toString() ?? '');
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    notifyListeners();
    await _storage.write(fileName, {
      'version': 1,
      'darkMode': _darkMode,
      'remindersEnabled': _remindersEnabled,
      'digestEnabled': _digestEnabled,
      'digestHour': _digestTime.hour,
      'digestMinute': _digestTime.minute,
      'visitLeadMinutes': _visitLeadMinutes,
      'pinHash': _pinHash,
      'pinSalt': _pinSalt,
      'pinLength': _pinLength,
      'biometricEnabled': _biometricEnabled,
      'lockAfterSeconds': _lockAfterSeconds,
      'lastBackupAt': _lastBackupAt?.toUtc().toIso8601String(),
      'backupNudgeSnoozedUntil':
          _backupNudgeSnoozedUntil?.toUtc().toIso8601String(),
    });
  }

  // --- appearance ----------------------------------------------------------

  bool get darkMode => _darkMode;
  Future<void> setDarkMode(bool value) {
    _darkMode = value;
    return _save();
  }

  // --- reminders -----------------------------------------------------------

  bool get remindersEnabled => _remindersEnabled;
  Future<void> setRemindersEnabled(bool value) {
    _remindersEnabled = value;
    return _save();
  }

  /// The "today's follow-ups" summary each morning.
  bool get digestEnabled => _digestEnabled;
  Future<void> setDigestEnabled(bool value) {
    _digestEnabled = value;
    return _save();
  }

  TimeOfDay get digestTime => _digestTime;
  Future<void> setDigestTime(TimeOfDay value) {
    _digestTime = value;
    return _save();
  }

  /// How long before a site visit its reminder fires.
  int get visitLeadMinutes => _visitLeadMinutes;
  Future<void> setVisitLeadMinutes(int value) {
    _visitLeadMinutes = value;
    return _save();
  }

  // --- app lock ------------------------------------------------------------

  bool get lockEnabled => _pinHash != null;
  bool get biometricEnabled => lockEnabled && _biometricEnabled;

  /// So the lock screen can check the PIN as soon as the last digit is in.
  int get pinLength => _pinLength;

  /// Seconds in the background before the app asks for the PIN again.
  int get lockAfterSeconds => _lockAfterSeconds;

  Future<void> setPin(String pin) {
    final salt = base64Url.encode(
        List<int>.generate(16, (_) => Random.secure().nextInt(256)));
    _pinSalt = salt;
    _pinHash = _hash(pin, salt);
    _pinLength = pin.length;
    return _save();
  }

  bool checkPin(String pin) {
    final salt = _pinSalt, hash = _pinHash;
    if (salt == null || hash == null) return true;
    return _hash(pin, salt) == hash;
  }

  Future<void> clearPin() {
    _pinHash = null;
    _pinSalt = null;
    _biometricEnabled = false;
    return _save();
  }

  Future<void> setBiometricEnabled(bool value) {
    _biometricEnabled = value;
    return _save();
  }

  Future<void> setLockAfterSeconds(int value) {
    _lockAfterSeconds = value;
    return _save();
  }

  /// Salted and stretched, so the PIN can't be read back out of
  /// settings.json. (The lock keeps the diary private from someone holding
  /// the phone; it is not encryption of the files themselves.)
  static String _hash(String pin, String salt) {
    var bytes = utf8.encode('$salt:$pin');
    for (var i = 0; i < 20000; i++) {
      bytes = Uint8List.fromList(sha256.convert(bytes).bytes);
    }
    return base64Url.encode(bytes);
  }

  // --- backup --------------------------------------------------------------

  DateTime? get lastBackupAt => _lastBackupAt;

  static const backupInterval = Duration(days: 7);

  /// True when the diary has data and hasn't been backed up for a week.
  bool backupDue({required bool hasData, DateTime? now}) {
    if (!hasData) return false;
    final t = now ?? DateTime.now();
    final snooze = _backupNudgeSnoozedUntil;
    if (snooze != null && snooze.isAfter(t)) return false;
    final last = _lastBackupAt;
    return last == null || t.difference(last) > backupInterval;
  }

  Future<void> markBackedUp() {
    _lastBackupAt = DateTime.now();
    _backupNudgeSnoozedUntil = null;
    return _save();
  }

  Future<void> snoozeBackupNudge() {
    _backupNudgeSnoozedUntil = DateTime.now().add(const Duration(days: 3));
    return _save();
  }

  /// After "erase all data", start from defaults.
  Future<void> reset() async {
    _darkMode = false;
    _remindersEnabled = true;
    _digestEnabled = true;
    _digestTime = const TimeOfDay(hour: 8, minute: 30);
    _visitLeadMinutes = 60;
    _pinHash = null;
    _pinSalt = null;
    _biometricEnabled = false;
    _lockAfterSeconds = 60;
    _lastBackupAt = null;
    _backupNudgeSnoozedUntil = null;
    await _save();
  }
}
