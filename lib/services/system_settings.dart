import 'package:flutter/services.dart';

/// Opens the phone's "App info" page for Broker Diary — where battery,
/// autostart and permission settings live.
abstract final class SystemSettings {
  static const _channel = MethodChannel('broker_diary/system');

  static Future<bool> openAppSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openAppSettings') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
