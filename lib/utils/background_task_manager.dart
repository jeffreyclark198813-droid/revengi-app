import 'dart:async';
import 'package:flutter/services.dart';
import 'package:revengi/utils/platform.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Status of a background task managed by WorkManager.
class BackgroundTaskStatus {
  final String workId;
  final String state;
  final String? progressStage;
  final int progressPercent;
  final int progressBytes;
  final int progressTotal;
  final String? resultPath;
  final int downloadedBytes;
  final String? errorMessage;

  BackgroundTaskStatus({
    required this.workId,
    required this.state,
    this.progressStage,
    this.progressPercent = -1,
    this.progressBytes = -1,
    this.progressTotal = -1,
    this.resultPath,
    this.downloadedBytes = -1,
    this.errorMessage,
  });

  factory BackgroundTaskStatus.fromMap(Map<dynamic, dynamic> map) {
    return BackgroundTaskStatus(
      workId: map['workId'] as String? ?? '',
      state: map['state'] as String? ?? 'UNKNOWN',
      progressStage: map['progressStage'] as String?,
      progressPercent: map['progressPercent'] as int? ?? -1,
      progressBytes: (map['progressBytes'] as num?)?.toInt() ?? -1,
      progressTotal: (map['progressTotal'] as num?)?.toInt() ?? -1,
      resultPath: map['resultPath'] as String?,
      downloadedBytes: (map['downloadedBytes'] as num?)?.toInt() ?? -1,
      errorMessage: map['errorMessage'] as String?,
    );
  }

  bool get isRunning => state == 'RUNNING';
  bool get isSucceeded => state == 'SUCCEEDED';
  bool get isFailed => state == 'FAILED';
  bool get isCancelled => state == 'CANCELLED';
  bool get isEnqueued => state == 'ENQUEUED';
  bool get isComplete => isSucceeded || isFailed || isCancelled;
}

/// Preferences keys for background task configuration.
class BackgroundTaskPrefs {
  static const String enabledKey = 'backgroundProcessingEnabled';
  static const String wifiOnlyKey = 'backgroundWifiOnly';
  static const String requireChargingKey = 'backgroundRequireCharging';

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(enabledKey) ?? false;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(enabledKey, value);
  }

  static Future<bool> isWifiOnly() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(wifiOnlyKey) ?? false;
  }

  static Future<void> setWifiOnly(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(wifiOnlyKey, value);
  }

  static Future<bool> requiresCharging() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(requireChargingKey) ?? false;
  }

  static Future<void> setRequiresCharging(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(requireChargingKey, value);
  }
}

/// Flutter-side bridge to the native Android WorkManager via MethodChannel.
/// All methods are platform-guarded and return no-ops on non-Android platforms.
class BackgroundTaskManager {
  static const MethodChannel _channel = MethodChannel('flutter.native/helper');

  /// Schedule a background APK merge task via WorkManager.
  /// Returns the unique work ID for tracking, or null if not available.
  static Future<String?> scheduleApkMerge({
    required Map<String, dynamic> options,
  }) async {
    if (isWeb() || !isAndroid()) return null;
    if (!await BackgroundTaskPrefs.isEnabled()) return null;

    try {
      final requireCharging = await BackgroundTaskPrefs.requiresCharging();
      final mergeOptions = Map<String, dynamic>.from(options);
      mergeOptions['requireCharging'] = requireCharging;

      final workId = await _channel.invokeMethod<String>(
        'scheduleBackgroundMerge',
        mergeOptions,
      );
      return workId;
    } on PlatformException {
      return null;
    }
  }

  /// Schedule a background URL fetch task via WorkManager.
  /// Returns the unique work ID for tracking, or null if not available.
  static Future<String?> scheduleUrlFetch({
    required String url,
    required String outputPath,
    String? fileName,
    String? headers,
  }) async {
    if (isWeb() || !isAndroid()) return null;

    try {
      final wifiOnly = await BackgroundTaskPrefs.isWifiOnly();

      final workId = await _channel.invokeMethod<String>(
        'scheduleUrlFetch',
        {
          'url': url,
          'outputPath': outputPath,
          'fileName': fileName,
          'headers': headers,
          'wifiOnly': wifiOnly,
        },
      );
      return workId;
    } on PlatformException {
      return null;
    }
  }

  /// Cancel a specific background task by its work ID.
  static Future<bool> cancelTask(String workId) async {
    if (isWeb() || !isAndroid()) return false;

    try {
      final result = await _channel.invokeMethod<bool>(
        'cancelBackgroundWork',
        {'workId': workId},
      );
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Get the current status of a background task.
  static Future<BackgroundTaskStatus?> getTaskStatus(String workId) async {
    if (isWeb() || !isAndroid()) return null;

    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getBackgroundWorkStatus',
        {'workId': workId},
      );
      if (result != null) {
        return BackgroundTaskStatus.fromMap(result);
      }
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Poll the status of a background task at regular intervals.
  /// Returns a stream that emits status updates until the task is complete.
  static Stream<BackgroundTaskStatus> watchTaskStatus(
    String workId, {
    Duration interval = const Duration(seconds: 2),
  }) {
    late StreamController<BackgroundTaskStatus> controller;
    Timer? timer;

    controller = StreamController<BackgroundTaskStatus>(
      onListen: () {
        timer = Timer.periodic(interval, (_) async {
          final status = await getTaskStatus(workId);
          if (status != null) {
            controller.add(status);
            if (status.isComplete) {
              timer?.cancel();
              await controller.close();
            }
          }
        });
      },
      onCancel: () {
        timer?.cancel();
      },
    );

    return controller.stream;
  }

  /// Cancel all RevEngi background work.
  static Future<bool> cancelAllTasks() async {
    if (isWeb() || !isAndroid()) return false;

    try {
      final result = await _channel.invokeMethod<bool>('cancelAllBackgroundWork');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }
}
