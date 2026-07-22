import 'package:fl_lib/fl_lib.dart';
import 'package:flutter/services.dart';
import 'package:server_box/data/res/misc.dart';
import 'package:server_box/data/res/store.dart';

abstract final class MethodChans {
  static const _channel = MethodChannel('${Miscs.pkgName}/main_chan');

  /// Issue #662
  static Future<void> startService() async {
    if (!isAndroid) return;
    try {
      await _channel.invokeMethod('startService');
    } catch (e, s) {
      Loggers.app.warning('Failed to start Android SSH service', e, s);
    }
  }

  /// Issue #662
  static Future<void> stopService() async {
    if (!isAndroid) return;
    try {
      await _channel.invokeMethod('stopService');
    } catch (e, s) {
      Loggers.app.warning('Failed to stop Android SSH service', e, s);
    }
  }

  /// Show a short Android system toast even when the Flutter route displaying
  /// the transfer list is not visible.
  static Future<void> showToast(String message) async {
    if (!isAndroid || message.isEmpty) return;
    try {
      await _channel.invokeMethod('showToast', message);
    } catch (e, s) {
      Loggers.app.warning('Failed to show Android toast', e, s);
    }
  }

  static Future<bool> hasStorageAccess() async {
    if (!isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('hasStorageAccess') ?? false;
    } catch (e, s) {
      Loggers.app.warning('Failed to query Android storage access', e, s);
      return false;
    }
  }

  static Future<void> requestStorageAccess() async {
    if (!isAndroid) return;
    try {
      await _channel.invokeMethod('requestStorageAccess');
    } catch (e, s) {
      Loggers.app.warning('Failed to request Android storage access', e, s);
    }
  }

  /// Open a local file through Android's ACTION_VIEW chooser. The native side
  /// exposes a scoped FileProvider URI so internal SFTP edit copies are safe to
  /// hand to another editor without using file:// URIs.
  static Future<bool> openFileExternally(String path) async {
    if (!isAndroid || path.isEmpty) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'openFileExternally',
            {'path': path},
          ) ??
          false;
    } catch (e, s) {
      Loggers.app.warning('Failed to open file externally', e, s);
      return false;
    }
  }

  /// Stop the Android foreground service, remove the task from Recents, and
  /// terminate the app process after Flutter has closed its connections.
  static Future<void> exitApp() async {
    if (!isAndroid) return;
    try {
      await _channel.invokeMethod('exitApp');
    } catch (e, s) {
      Loggers.app.warning('Failed to fully exit Android app', e, s);
    }
  }

  static Future<void> updateHomeWidget() async {
    if (!isIOS && !isAndroid) return;
    if (!Stores.setting.autoUpdateHomeWidget.fetch()) return;
    try {
      await _channel.invokeMethod('updateHomeWidget');
    } catch (e, s) {
      Loggers.app.warning('Failed to update home widget', e, s);
    }
  }

  /// Update Android foreground service notifications for SSH sessions
  /// The [payload] is a JSON string describing sessions list.
  static Future<void> updateSessions(String payload) async {
    if (!isAndroid) return;
    try {
      Loggers.app.info('Updating Android sessions: $payload');
      await _channel.invokeMethod('updateSessions', payload);
    } catch (e, s) {
      Loggers.app.warning('Failed to update Android sessions', e, s);
    }
  }

  /// Query whether the Android foreground service is currently running.
  static Future<bool> isServiceRunning() async {
    if (!isAndroid) return false;
    try {
      final res = await _channel.invokeMethod('isServiceRunning');
      return res == true;
    } catch (e, s) {
      Loggers.app.warning(
        'Failed to check if Android service is running',
        e,
        s,
      );
      return false;
    }
  }

  // iOS Live Activities controls
  static Future<void> updateLiveActivity(String payload) async {
    if (!isIOS) return;
    try {
      Loggers.app.info('Updating iOS Live Activity: $payload');
      await _channel.invokeMethod('updateLiveActivity', payload);
    } catch (e, s) {
      Loggers.app.warning('Failed to update iOS Live Activity', e, s);
    }
  }

  static Future<void> stopLiveActivity() async {
    if (!isIOS) return;
    try {
      Loggers.app.info('Stopping iOS Live Activity');
      await _channel.invokeMethod('stopLiveActivity');
    } catch (e, s) {
      Loggers.app.warning('Failed to stop iOS Live Activity', e, s);
    }
  }

  /// Register a handler for native -> Flutter callbacks.
  /// Currently handles:
  /// - `disconnectSession` with argument map {id: string}
  /// - `stopAllConnections` with no arguments
  static void registerHandler(
    Future<void> Function(String id) onDisconnect, [
    VoidCallback? onStopAll,
  ]) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'disconnectSession':
          final args = call.arguments;
          final id = args is Map ? args['id'] as String? : args as String?;
          if (id != null && id.isNotEmpty) {
            await onDisconnect(id);
          }
          return;
        case 'stopAllConnections':
          onStopAll?.call();
          return;
        default:
          return;
      }
    });
  }
}
