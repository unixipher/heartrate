import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';

class TimeTrackingService with WidgetsBindingObserver {
  static final TimeTrackingService _instance = TimeTrackingService._internal();
  factory TimeTrackingService() => _instance;
  TimeTrackingService._internal();

  DateTime? _sessionStartTime;
  String? _currentSessionId;
  Timer? _updateTimer;
  bool _isInitialized = false;

  /// Initialize the time tracking service
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Add this as an observer to monitor app lifecycle
    WidgetsBinding.instance.addObserver(this);

    // Start tracking current session
    await _startNewSession();

    // Set up periodic updates (every 5 seconds)
    _updateTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _updateSession();
    });

    _isInitialized = true;
  }

  /// Clean up resources
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _updateTimer?.cancel();
    _endCurrentSession(); // End session before disposal
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // App came to foreground - start new session
        _startNewSession();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // App went to background or was closed
        _endCurrentSession();
        break;
    }
  }

  /// Start a new session
  Future<void> _startNewSession() async {
    // End current session if exists
    if (_currentSessionId != null) {
      await _endCurrentSession();
    }

    final now = DateTime.now();
    _sessionStartTime = now;

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';

      if (token.isEmpty) {
        debugPrint('TimeTracking: No auth token available');
        return;
      }

      // Get package info for app version
      final packageInfo = await PackageInfo.fromPlatform();
      final appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';

      // Get comprehensive device information
      final deviceInfo = await _getDeviceInfo();

      // Create new session
      final createPayload = {
        'sessionStart': now.toUtc().toIso8601String(),
        'appVersion': appVersion,
        'deviceInfo': json.encode(deviceInfo), // Store as JSON string
        'timezone': now.timeZoneName,
      };

      debugPrint(
          'TimeTracking: Creating session with payload: ${json.encode(createPayload)}');

      final response = await http.post(
        Uri.parse('https://authcheck.co/createappusagesession'),
        headers: {
          'Accept': '*/*',
          'User-Agent': 'Thunder Client (https://www.thunderclient.com)',
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode(createPayload),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = json.decode(response.body);
        debugPrint('TimeTracking: Create session response: ${response.body}');

        // Extract session ID from nested response structure
        _currentSessionId = responseData['session']?['id'] ??
            responseData['sessionId'] ??
            responseData['id'];

        debugPrint(
            'TimeTracking: New session started with ID: $_currentSessionId');
      } else {
        debugPrint(
            'TimeTracking: Failed to create session: ${response.statusCode}');
        debugPrint('TimeTracking: Response body: ${response.body}');
      }
    } catch (e) {
      debugPrint('TimeTracking: Error creating session: $e');
    }
  }

  /// Update current session (called every 5 seconds)
  Future<void> _updateSession() async {
    if (_currentSessionId == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';

      if (token.isEmpty) {
        debugPrint('TimeTracking: No auth token available for update');
        return;
      }

      final updatePayload = {
        'sessionId': _currentSessionId,
        'sessionEnd': DateTime.now().toUtc().toIso8601String(),
      };

      // debugPrint(
      //     'TimeTracking: Updating session with payload: ${json.encode(updatePayload)}');

      final response = await http.post(
        Uri.parse('https://authcheck.co/updateappusagesession'),
        headers: {
          'Accept': '*/*',
          'User-Agent': 'Thunder Client (https://www.thunderclient.com)',
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode(updatePayload),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        // debugPrint('App Alive');
      } else {
        debugPrint(
            'TimeTracking: Failed to update session: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('TimeTracking: Error updating session: $e');
    }
  }

  /// End current session
  Future<void> _endCurrentSession() async {
    if (_currentSessionId == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';

      if (token.isEmpty) {
        debugPrint('TimeTracking: No auth token available for ending session');
        return;
      }

      final endPayload = {
        'sessionId': _currentSessionId,
        'sessionEnd': DateTime.now().toUtc().toIso8601String(),
      };

      debugPrint(
          'TimeTracking: Ending session with payload: ${json.encode(endPayload)}');

      final response = await http.post(
        Uri.parse('https://authcheck.co/updateappusagesession'),
        headers: {
          'Accept': '*/*',
          'User-Agent': 'Thunder Client (https://www.thunderclient.com)',
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode(endPayload),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('TimeTracking: Session ended successfully');
      } else {
        debugPrint(
            'TimeTracking: Failed to end session: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('TimeTracking: Error ending session: $e');
    } finally {
      _currentSessionId = null;
      _sessionStartTime = null;
    }
  }

  /// Get current session info (for debugging)
  Map<String, dynamic> getCurrentSessionInfo() {
    if (_sessionStartTime != null && _currentSessionId != null) {
      final currentDuration = DateTime.now().difference(_sessionStartTime!);
      return {
        'sessionId': _currentSessionId,
        'sessionStart': _sessionStartTime!.toIso8601String(),
        'currentDuration': currentDuration.inMilliseconds,
        'isActive': true,
      };
    }
    return {'isActive': false};
  }

  /// Force start new session (for testing)
  Future<void> forceStartNewSession() async {
    await _startNewSession();
  }

  /// Check if service is initialized
  bool get isInitialized => _isInitialized;

  /// Collect comprehensive device information including crash data and logs
  Future<Map<String, dynamic>> _getDeviceInfo() async {
    try {
      final deviceInfoPlugin = DeviceInfoPlugin();
      final deviceInfo = await deviceInfoPlugin.deviceInfo;
      final allInfo = deviceInfo.data;

      Map<String, dynamic> deviceData = {
        'platform': '',
        'model': '',
        'manufacturer': '',
        'osVersion': '',
        'deviceId': '',
        'screenResolution': '',
        'memoryInfo': {},
        'networkInfo': {},
        'crashLogs': [],
        'systemLogs': [],
        'rawDeviceInfo': allInfo,
      };

      // Platform-specific device information
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfoPlugin.androidInfo;
        deviceData.addAll({
          'platform': 'Android',
          'model': androidInfo.model,
          'manufacturer': androidInfo.manufacturer,
          'osVersion':
              'Android ${androidInfo.version.release} (API ${androidInfo.version.sdkInt})',
          'deviceId': androidInfo.id,
          'brand': androidInfo.brand,
          'device': androidInfo.device,
          'hardware': androidInfo.hardware,
          'bootloader': androidInfo.bootloader,
          'fingerprint': androidInfo.fingerprint,
          'host': androidInfo.host,
          'product': androidInfo.product,
          'supported32BitAbis': androidInfo.supported32BitAbis,
          'supported64BitAbis': androidInfo.supported64BitAbis,
          'supportedAbis': androidInfo.supportedAbis,
          'tags': androidInfo.tags,
          'type': androidInfo.type,
          'isPhysicalDevice': androidInfo.isPhysicalDevice,
          'systemFeatures': androidInfo.systemFeatures,
          // Remove displayMetrics as it's not available in current version
        });

        // Android crash logs simulation (in real app, you'd integrate with Firebase Crashlytics)
        deviceData['crashLogs'] = await _getAndroidCrashLogs();
        deviceData['systemLogs'] = await _getAndroidSystemLogs();
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfoPlugin.iosInfo;
        deviceData.addAll({
          'platform': 'iOS',
          'model': iosInfo.model,
          'manufacturer': 'Apple',
          'osVersion': '${iosInfo.systemName} ${iosInfo.systemVersion}',
          'deviceId': iosInfo.identifierForVendor ?? 'unknown',
          'name': iosInfo.name,
          'localizedModel': iosInfo.localizedModel,
          'systemName': iosInfo.systemName,
          'systemVersion': iosInfo.systemVersion,
          'isPhysicalDevice': iosInfo.isPhysicalDevice,
          'utsname': {
            'machine': iosInfo.utsname.machine,
            'nodename': iosInfo.utsname.nodename,
            'release': iosInfo.utsname.release,
            'sysname': iosInfo.utsname.sysname,
            'version': iosInfo.utsname.version,
          },
        });

        // iOS crash logs simulation
        deviceData['crashLogs'] = await _getIOSCrashLogs();
        deviceData['systemLogs'] = await _getIOSSystemLogs();
      } else if (Platform.isMacOS) {
        final macInfo = await deviceInfoPlugin.macOsInfo;
        deviceData.addAll({
          'platform': 'macOS',
          'model': macInfo.model,
          'manufacturer': 'Apple',
          'osVersion': macInfo.osRelease,
          'deviceId': macInfo.systemGUID ?? 'unknown',
          'computerName': macInfo.computerName,
          'hostName': macInfo.hostName,
          'arch': macInfo.arch,
          'kernelVersion': macInfo.kernelVersion,
          'majorVersion': macInfo.majorVersion,
          'minorVersion': macInfo.minorVersion,
          'patchVersion': macInfo.patchVersion,
          'activeCPUs': macInfo.activeCPUs,
          'memorySize': macInfo.memorySize,
          'cpuFrequency': macInfo.cpuFrequency,
        });
      } else if (Platform.isWindows) {
        final windowsInfo = await deviceInfoPlugin.windowsInfo;
        deviceData.addAll({
          'platform': 'Windows',
          'model': windowsInfo.productName,
          'manufacturer': 'Microsoft',
          'osVersion':
              '${windowsInfo.majorVersion}.${windowsInfo.minorVersion}.${windowsInfo.buildNumber}',
          'deviceId':
              windowsInfo.computerName, // Use computerName as device identifier
          'computerName': windowsInfo.computerName,
          'userName': windowsInfo.userName,
          'buildLab': windowsInfo.buildLab,
          'buildLabEx': windowsInfo.buildLabEx,
          'digitalProductId': windowsInfo.digitalProductId,
          'displayVersion': windowsInfo.displayVersion,
          'editionId': windowsInfo.editionId,
          'installDate': windowsInfo.installDate.toIso8601String(),
          'productId': windowsInfo.productId,
          'productName': windowsInfo.productName,
          'registeredOwner': windowsInfo.registeredOwner,
          'releaseId': windowsInfo.releaseId,
          // Remove deviceFamily as it's not available in current version
        });
      } else if (Platform.isLinux) {
        final linuxInfo = await deviceInfoPlugin.linuxInfo;
        deviceData.addAll({
          'platform': 'Linux',
          'model': linuxInfo.prettyName,
          'manufacturer': 'Linux',
          'osVersion': linuxInfo.version ?? 'unknown',
          'deviceId': linuxInfo.machineId ?? 'unknown',
          'name': linuxInfo.name,
          'version': linuxInfo.version,
          'id': linuxInfo.id,
          'idLike': linuxInfo.idLike,
          'versionCodename': linuxInfo.versionCodename,
          'versionId': linuxInfo.versionId,
          'prettyName': linuxInfo.prettyName,
          'buildId': linuxInfo.buildId,
          'variant': linuxInfo.variant,
          'variantId': linuxInfo.variantId,
        });
      }

      // Get screen resolution
      final mediaQuery = WidgetsBinding.instance.platformDispatcher.views.first;
      deviceData['screenResolution'] =
          '${mediaQuery.physicalSize.width.toInt()}x${mediaQuery.physicalSize.height.toInt()}';
      deviceData['devicePixelRatio'] = mediaQuery.devicePixelRatio;

      // Memory information
      deviceData['memoryInfo'] = await _getMemoryInfo();

      // Network information
      deviceData['networkInfo'] = await _getNetworkInfo();

      return deviceData;
    } on MissingPluginException catch (e) {
      debugPrint(
          'TimeTracking: Device info plugin not available (simulator/emulator): $e');
      // Return blank/minimal payload for simulators/emulators
      return {
        'platform': Platform.operatingSystem,
        'model': 'Simulator/Emulator',
        'manufacturer': 'Unknown',
        'osVersion': 'Unknown',
        'deviceId': 'simulator',
        'screenResolution': 'Unknown',
        'memoryInfo': {},
        'networkInfo': {},
        'crashLogs': [],
        'systemLogs': [],
        'rawDeviceInfo': {},
        'isSimulator': true,
      };
    } catch (e) {
      debugPrint('Error collecting device info: $e');
      return {
        'platform': Platform.operatingSystem,
        'model': 'Unknown',
        'manufacturer': 'Unknown',
        'osVersion': 'Unknown',
        'deviceId': 'unknown',
        'screenResolution': 'Unknown',
        'memoryInfo': {},
        'networkInfo': {},
        'crashLogs': [],
        'systemLogs': [],
        'rawDeviceInfo': {},
        'error': e.toString(),
      };
    }
  }

  /// Get Android crash logs (simulation - integrate with actual crash reporting)
  Future<List<Map<String, dynamic>>> _getAndroidCrashLogs() async {
    // In a real app, integrate with Firebase Crashlytics or similar
    return [
      {
        'timestamp':
            DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
        'type': 'ANR',
        'message': 'Application Not Responding detected',
        'stackTrace': 'Simulated ANR stack trace...',
      },
      {
        'timestamp':
            DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
        'type': 'Exception',
        'message': 'NetworkException: Connection timeout',
        'stackTrace': 'Simulated network exception...',
      },
    ];
  }

  /// Get iOS crash logs (simulation)
  Future<List<Map<String, dynamic>>> _getIOSCrashLogs() async {
    return [
      {
        'timestamp':
            DateTime.now().subtract(const Duration(hours: 3)).toIso8601String(),
        'type': 'Signal',
        'message': 'SIGABRT received',
        'stackTrace': 'Simulated iOS crash stack trace...',
      },
    ];
  }

  /// Get Android system logs
  Future<List<Map<String, dynamic>>> _getAndroidSystemLogs() async {
    return [
      {
        'timestamp': DateTime.now()
            .subtract(const Duration(minutes: 30))
            .toIso8601String(),
        'level': 'WARNING',
        'tag': 'ActivityManager',
        'message': 'Background app optimization applied',
      },
      {
        'timestamp': DateTime.now()
            .subtract(const Duration(minutes: 15))
            .toIso8601String(),
        'level': 'INFO',
        'tag': 'NetworkStats',
        'message': 'Data usage updated',
      },
    ];
  }

  /// Get iOS system logs
  Future<List<Map<String, dynamic>>> _getIOSSystemLogs() async {
    return [
      {
        'timestamp': DateTime.now()
            .subtract(const Duration(minutes: 20))
            .toIso8601String(),
        'level': 'INFO',
        'subsystem': 'com.apple.UIKit',
        'message': 'View controller transition completed',
      },
    ];
  }

  /// Get memory information
  Future<Map<String, dynamic>> _getMemoryInfo() async {
    try {
      // This is a simulation - in reality you'd use platform channels for actual memory stats
      return {
        'totalRAM': '8GB',
        'availableRAM': '3.2GB',
        'usedRAM': '4.8GB',
        'appMemoryUsage': '156MB',
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Get network information
  Future<Map<String, dynamic>> _getNetworkInfo() async {
    try {
      // This is a simulation - in reality you'd use connectivity_plus package
      return {
        'connectionType': 'WiFi',
        'isConnected': true,
        'signalStrength': '-45 dBm',
        'networkName': 'MyNetwork',
        'ipAddress': '192.168.1.100',
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Get device info summary for debugging
  Future<Map<String, dynamic>> getDeviceInfoSummary() async {
    final deviceInfo = await _getDeviceInfo();
    return {
      'platform': deviceInfo['platform'],
      'model': deviceInfo['model'],
      'osVersion': deviceInfo['osVersion'],
      'appVersion': (await PackageInfo.fromPlatform()).version,
      'crashLogCount': (deviceInfo['crashLogs'] as List).length,
      'systemLogCount': (deviceInfo['systemLogs'] as List).length,
      'lastUpdated': DateTime.now().toIso8601String(),
    };
  }
}
