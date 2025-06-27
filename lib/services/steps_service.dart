import 'dart:async';
import 'package:cm_pedometer/cm_pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

class PedometerService {
  static final PedometerService _instance = PedometerService._internal();
  factory PedometerService() => _instance;
  PedometerService._internal();

  // Streams for pedometer data
  StreamSubscription<CMPedometerData>? _stepCountSubscription;
  StreamSubscription<CMPedometerData>? _stepCountFromSubscription;
  StreamSubscription<CMPedestrianStatus>? _pedestrianStatusSubscription;

  // Current data holders
  CMPedometerData? _currentPedometerData;
  CMPedometerData? _currentPedometerDataFrom;
  String _currentPedestrianStatus = 'unknown';
  DateTime? _trackingStartTime;

  // Stream controllers for broadcasting updates
  final StreamController<CMPedometerData> _pedometerDataController = 
      StreamController<CMPedometerData>.broadcast();
  final StreamController<CMPedometerData> _pedometerDataFromController = 
      StreamController<CMPedometerData>.broadcast();
  final StreamController<String> _pedestrianStatusController = 
      StreamController<String>.broadcast();

  // Getters for streams
  Stream<CMPedometerData> get pedometerDataStream => _pedometerDataController.stream;
  Stream<CMPedometerData> get pedometerDataFromStream => _pedometerDataFromController.stream;
  Stream<String> get pedestrianStatusStream => _pedestrianStatusController.stream;

  bool _isInitialized = false;
  bool _hasPermission = false;

  /// Initialize the pedometer service
  Future<bool> initialize() async {
    if (_isInitialized) return _hasPermission;

    _hasPermission = await _checkActivityRecognitionPermission();
    if (!_hasPermission) {
      print('PedometerService: Activity recognition permission not granted');
      return false;
    }

    try {
      // Initialize pedestrian status stream
      _pedestrianStatusSubscription = CMPedometer.pedestrianStatusStream
          .listen(_onPedestrianStatusChanged, onError: _onPedestrianStatusError);

      // Initialize step count stream (since last system boot)
      _stepCountSubscription = CMPedometer.stepCounterFirstStream()
          .listen(_onStepCount, onError: _onStepCountError);

      // Initialize step count from stream (from app start)
      _trackingStartTime = DateTime.now();
      _stepCountFromSubscription = CMPedometer.stepCounterSecondStream(from: _trackingStartTime!)
          .listen(_onStepCountFrom, onError: _onStepCountFromError);

      _isInitialized = true;
      print('PedometerService: Successfully initialized');
      return true;
    } catch (e) {
      print('PedometerService: Initialization failed: $e');
      return false;
    }
  }

  /// Check if activity recognition permission is granted
  Future<bool> _checkActivityRecognitionPermission() async {
    bool granted = await Permission.activityRecognition.isGranted;

    if (!granted) {
      granted = await Permission.activityRecognition.request() == PermissionStatus.granted;
    }

    return granted;
  }

  /// Get current pedometer data (since last system boot)
  CMPedometerData? getCurrentPedometerData() {
    return _currentPedometerData;
  }

  /// Get current pedometer data from tracking start time
  CMPedometerData? getCurrentPedometerDataFrom() {
    return _currentPedometerDataFrom;
  }

  /// Get current pedestrian status
  String getCurrentPedestrianStatus() {
    return _currentPedestrianStatus;
  }

  /// Get current steps count
  int getCurrentSteps() {
    return _currentPedometerData?.numberOfSteps ?? 0;
  }

  /// Get current steps count from tracking start
  int getCurrentStepsFrom() {
    return _currentPedometerDataFrom?.numberOfSteps ?? 0;
  }

  /// Get current distance in meters
  double getCurrentDistance() {
    return _currentPedometerData?.distance ?? 0.0;
  }

  /// Get current distance from tracking start in meters
  double getCurrentDistanceFrom() {
    return _currentPedometerDataFrom?.distance ?? 0.0;
  }

  /// Get current pace in seconds per meter (convert to m/s by taking 1/pace)
  double getCurrentPace() {
    return _currentPedometerData?.currentPace ?? 0.0;
  }

  /// Get current pace in m/s
  double getCurrentPaceInMeterPerSecond() {
    final pace = getCurrentPace();
    return pace > 0 ? 1 / pace : 0.0;
  }

  /// Get current cadence in steps per second
  double getCurrentCadence() {
    return _currentPedometerData?.currentCadence ?? 0.0;
  }

  /// Get current cadence in steps per minute
  double getCurrentCadencePerMinute() {
    return getCurrentCadence() * 60;
  }

  /// Get floors ascended
  int getFloorsAscended() {
    return _currentPedometerData?.floorsAscended ?? 0;
  }

  /// Get floors descended
  int getFloorsDescended() {
    return _currentPedometerData?.floorsDescended ?? 0;
  }

  /// Get tracking start time
  DateTime? getTrackingStartTime() {
    return _trackingStartTime;
  }

  /// Reset tracking from current time
  void resetTrackingFrom() {
    _stepCountFromSubscription?.cancel();
    _trackingStartTime = DateTime.now();
    _stepCountFromSubscription = CMPedometer.stepCounterSecondStream(from: _trackingStartTime!)
        .listen(_onStepCountFrom, onError: _onStepCountFromError);
  }

  /// Get comprehensive pedometer info
  Map<String, dynamic> getPedometerInfo() {
    return {
      'isInitialized': _isInitialized,
      'hasPermission': _hasPermission,
      'pedestrianStatus': _currentPedestrianStatus,
      'trackingStartTime': _trackingStartTime?.toIso8601String(),
      'stepsSinceSystemBoot': getCurrentSteps(),
      'stepsFromTracking': getCurrentStepsFrom(),
      'distanceInMeters': getCurrentDistance(),
      'distanceFromTrackingInMeters': getCurrentDistanceFrom(),
      'distanceInKm': getCurrentDistance() / 1000,
      'distanceFromTrackingInKm': getCurrentDistanceFrom() / 1000,
      'paceInSecondsPerMeter': getCurrentPace(),
      'paceInMeterPerSecond': getCurrentPaceInMeterPerSecond(),
      'cadenceInStepsPerSecond': getCurrentCadence(),
      'cadenceInStepsPerMinute': getCurrentCadencePerMinute(),
      'floorsAscended': getFloorsAscended(),
      'floorsDescended': getFloorsDescended(),
    };
  }

  // Private callback methods
  void _onStepCount(CMPedometerData data) {
    _currentPedometerData = data;
    _pedometerDataController.add(data);
  }

  void _onStepCountFrom(CMPedometerData data) {
    _currentPedometerDataFrom = data;
    _pedometerDataFromController.add(data);
  }

  void _onPedestrianStatusChanged(CMPedestrianStatus event) {
    _currentPedestrianStatus = event.status;
    _pedestrianStatusController.add(event.status);
  }

  void _onPedestrianStatusError(error) {
    print('PedometerService: Pedestrian status error: $error');
    _currentPedestrianStatus = 'error';
    _pedestrianStatusController.add('error');
  }

  void _onStepCountError(error) {
    print('PedometerService: Step count error: $error');
    _currentPedometerData = null;
  }

  void _onStepCountFromError(error) {
    print('PedometerService: Step count from error: $error');
    _currentPedometerDataFrom = null;
  }

  /// Dispose of the service and cleanup resources
  void dispose() {
    _stepCountSubscription?.cancel();
    _stepCountFromSubscription?.cancel();
    _pedestrianStatusSubscription?.cancel();
    _pedometerDataController.close();
    _pedometerDataFromController.close();
    _pedestrianStatusController.close();
    _isInitialized = false;
  }
}