import 'dart:io';

import 'package:flutter/services.dart';

/// Controls the Android foreground priority used while Relay is connected.
///
/// The Relay WebSocket remains owned by [BridgeController]. The native service
/// keeps the application process at foreground priority while the activity is
/// backgrounded, so the existing socket and local notification callbacks can
/// continue to receive events without opening a second connection.
class AndroidRelayForegroundService {
  AndroidRelayForegroundService._();

  static const _channel = MethodChannel('recodex/background_service');

  static Future<void> start() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('start');
    } on MissingPluginException {
      // Desktop, tests, and an old Android build may not expose the channel.
    } on PlatformException {
      // Background priority is best effort; Relay reconnect logic remains the
      // source of truth if the service cannot be started.
    }
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // See start().
    } on PlatformException {
      // Stopping is best effort during activity teardown.
    }
  }
}
