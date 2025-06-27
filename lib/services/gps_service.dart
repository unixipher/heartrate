import 'dart:async';
import 'package:geolocator/geolocator.dart';

class GeolocationSpeedService {
  static final GeolocationSpeedService _instance = GeolocationSpeedService._internal();
  factory GeolocationSpeedService() => _instance;
  GeolocationSpeedService._internal();

  // Location tracking
  StreamSubscription<Position>? _positionSubscription;
  Position? _currentPosition;
  Position? _previousPosition;
  
  // Speed calculations
  double _currentSpeed = 0.0; // m/s from GPS
  double _calculatedSpeed = 0.0; // m/s calculated from distance/time
  double _averageSpeed = 0.0; // Running average
  double _maxSpeed = 0.0;
  
  // Distance tracking
  double _totalDistance = 0.0; // meters
  double _sessionDistance = 0.0; // meters for current session
  
  // Time tracking
  DateTime? _trackingStartTime;
  DateTime? _sessionStartTime;
  DateTime? _lastPositionTime;
  
  // Speed history for averaging
  final List<double> _speedHistory = [];
  final int _maxSpeedHistorySize = 10;
  
  // Accuracy filtering
  double _minAccuracy = 20.0; // meters
  double _minDistanceFilter = 1.0; // meters
  
  // Stream controllers
  final StreamController<double> _speedController = StreamController<double>.broadcast();
  final StreamController<Position> _positionController = StreamController<Position>.broadcast();
  final StreamController<double> _distanceController = StreamController<double>.broadcast();
  
  // Service state
  bool _isInitialized = false;
  bool _isTracking = false;
  bool _hasPermission = false;
  
  // Getters for streams
  Stream<double> get speedStream => _speedController.stream;
  Stream<Position> get positionStream => _positionController.stream;
  Stream<double> get distanceStream => _distanceController.stream;
  
  // Location settings
  final LocationSettings _locationSettings = const LocationSettings(
    accuracy: LocationAccuracy.bestForNavigation,
    distanceFilter: 1, // Update every 1 meter
    timeLimit: Duration(seconds: 10),
  );

  /// Initialize the geolocation service
  Future<bool> initialize() async {
    if (_isInitialized) return _hasPermission;

    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('GeolocationSpeedService: Location services are disabled');
        return false;
      }

      // Check permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('GeolocationSpeedService: Location permissions denied');
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('GeolocationSpeedService: Location permissions permanently denied');
        return false;
      }

      _hasPermission = true;
      _isInitialized = true;
      print('GeolocationSpeedService: Successfully initialized');
      return true;
    } catch (e) {
      print('GeolocationSpeedService: Initialization failed: $e');
      return false;
    }
  }

  /// Start tracking location and speed
  Future<bool> startTracking() async {
    if (!_isInitialized) {
      bool initialized = await initialize();
      if (!initialized) return false;
    }

    if (_isTracking) return true;

    try {
      // Get initial position
      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
        timeLimit: const Duration(seconds: 10),
      );

      // Reset tracking data
      _resetTrackingData();
      
      // Start position stream
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: _locationSettings,
      ).listen(_onPositionUpdate, onError: _onPositionError);

      _isTracking = true;
      print('GeolocationSpeedService: Started tracking');
      return true;
    } catch (e) {
      print('GeolocationSpeedService: Failed to start tracking: $e');
      return false;
    }
  }

  /// Stop tracking
  void stopTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _isTracking = false;
    print('GeolocationSpeedService: Stopped tracking');
  }

  /// Reset session data
  void resetSession() {
    _sessionDistance = 0.0;
    _sessionStartTime = DateTime.now();
    _speedHistory.clear();
    _averageSpeed = 0.0;
    _maxSpeed = 0.0;
    print('GeolocationSpeedService: Session reset');
  }

  /// Reset all tracking data
  void _resetTrackingData() {
    _trackingStartTime = DateTime.now();
    _sessionStartTime = DateTime.now();
    _lastPositionTime = DateTime.now();
    _totalDistance = 0.0;
    _sessionDistance = 0.0;
    _currentSpeed = 0.0;
    _calculatedSpeed = 0.0;
    _averageSpeed = 0.0;
    _maxSpeed = 0.0;
    _speedHistory.clear();
    _previousPosition = _currentPosition;
  }

  /// Handle position updates
  void _onPositionUpdate(Position position) {
    // Filter out inaccurate readings
    if (position.accuracy > _minAccuracy) {
      print('GeolocationSpeedService: Position too inaccurate: ${position.accuracy}m');
      return;
    }

    _previousPosition = _currentPosition;
    _currentPosition = position;
    _lastPositionTime = DateTime.now();

    // Calculate speed from GPS
    _currentSpeed = position.speed; // m/s from GPS

    // Calculate speed from distance and time if we have previous position
    if (_previousPosition != null) {
      _calculatedSpeed = _calculateSpeedFromDistance(_previousPosition!, position);
      
      // Calculate distance
      double distance = Geolocator.distanceBetween(
        _previousPosition!.latitude,
        _previousPosition!.longitude,
        position.latitude,
        position.longitude,
      );

      // Only update if moved minimum distance
      if (distance >= _minDistanceFilter) {
        _totalDistance += distance;
        _sessionDistance += distance;
        
        // Update speed history for averaging
        _updateSpeedHistory(_currentSpeed);
        
        // Update max speed
        if (_currentSpeed > _maxSpeed) {
          _maxSpeed = _currentSpeed;
        }

        // Broadcast updates
        _speedController.add(_currentSpeed);
        _distanceController.add(_sessionDistance);
      }
    }

    _positionController.add(position);
  }

  /// Handle position errors
  void _onPositionError(dynamic error) {
    print('GeolocationSpeedService: Position error: $error');
  }

  /// Calculate speed from distance between two positions
  double _calculateSpeedFromDistance(Position previous, Position current) {
    double distance = Geolocator.distanceBetween(
      previous.latitude,
      previous.longitude,
      current.latitude,
      current.longitude,
    );

    int timeDifference = current.timestamp.millisecondsSinceEpoch - 
                        previous.timestamp.millisecondsSinceEpoch;
    
    if (timeDifference <= 0) return 0.0;
    
    double timeInSeconds = timeDifference / 1000.0;
    return distance / timeInSeconds; // m/s
  }

  /// Update speed history for calculating average
  void _updateSpeedHistory(double speed) {
    _speedHistory.add(speed);
    
    if (_speedHistory.length > _maxSpeedHistorySize) {
      _speedHistory.removeAt(0);
    }
    
    // Calculate average
    if (_speedHistory.isNotEmpty) {
      _averageSpeed = _speedHistory.reduce((a, b) => a + b) / _speedHistory.length;
    }
  }

  // Getters for current data
  bool get isInitialized => _isInitialized;
  bool get isTracking => _isTracking;
  bool get hasPermission => _hasPermission;
  
  Position? get currentPosition => _currentPosition;
  
  /// Get current speed in m/s (from GPS)
  double getCurrentSpeed() => _currentSpeed;
  
  /// Get current speed in km/h
  double getCurrentSpeedKmh() => _currentSpeed * 3.6;
  
  /// Get current speed in mph
  double getCurrentSpeedMph() => _currentSpeed * 2.237;
  
  /// Get calculated speed from distance/time in m/s
  double getCalculatedSpeed() => _calculatedSpeed;
  
  /// Get calculated speed in km/h
  double getCalculatedSpeedKmh() => _calculatedSpeed * 3.6;
  
  /// Get average speed in m/s
  double getAverageSpeed() => _averageSpeed;
  
  /// Get average speed in km/h
  double getAverageSpeedKmh() => _averageSpeed * 3.6;
  
  /// Get maximum speed reached in m/s
  double getMaxSpeed() => _maxSpeed;
  
  /// Get maximum speed in km/h
  double getMaxSpeedKmh() => _maxSpeed * 3.6;
  
  /// Get total distance traveled in meters
  double getTotalDistance() => _totalDistance;
  
  /// Get total distance in kilometers
  double getTotalDistanceKm() => _totalDistance / 1000.0;
  
  /// Get session distance in meters
  double getSessionDistance() => _sessionDistance;
  
  /// Get session distance in kilometers
  double getSessionDistanceKm() => _sessionDistance / 1000.0;
  
  /// Get current altitude
  double? getCurrentAltitude() => _currentPosition?.altitude;
  
  /// Get current accuracy
  double? getCurrentAccuracy() => _currentPosition?.accuracy;
  
  /// Get current heading/bearing
  double? getCurrentHeading() => _currentPosition?.heading;
  
  /// Get session duration
  Duration? getSessionDuration() {
    if (_sessionStartTime == null) return null;
    return DateTime.now().difference(_sessionStartTime!);
  }
  
  /// Get total tracking duration
  Duration? getTotalTrackingDuration() {
    if (_trackingStartTime == null) return null;
    return DateTime.now().difference(_trackingStartTime!);
  }

  /// Calculate distance between two coordinates
  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }

  /// Calculate bearing between two coordinates
  double calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.bearingBetween(lat1, lon1, lat2, lon2);
  }

  /// Set minimum accuracy filter (default: 20 meters)
  void setMinAccuracy(double accuracy) {
    _minAccuracy = accuracy;
  }

  /// Set minimum distance filter (default: 1 meter)
  void setMinDistanceFilter(double distance) {
    _minDistanceFilter = distance;
  }

  /// Get comprehensive speed and location info
  Map<String, dynamic> getLocationSpeedInfo() {
    final sessionDuration = getSessionDuration();
    final totalDuration = getTotalTrackingDuration();
    
    return {
      'isInitialized': _isInitialized,
      'isTracking': _isTracking,
      'hasPermission': _hasPermission,
      'currentSpeedMs': getCurrentSpeed(),
      'currentSpeedKmh': getCurrentSpeedKmh(),
      'currentSpeedMph': getCurrentSpeedMph(),
      'calculatedSpeedMs': getCalculatedSpeed(),
      'calculatedSpeedKmh': getCalculatedSpeedKmh(),
      'averageSpeedMs': getAverageSpeed(),
      'averageSpeedKmh': getAverageSpeedKmh(),
      'maxSpeedMs': getMaxSpeed(),
      'maxSpeedKmh': getMaxSpeedKmh(),
      'totalDistanceM': getTotalDistance(),
      'totalDistanceKm': getTotalDistanceKm(),
      'sessionDistanceM': getSessionDistance(),
      'sessionDistanceKm': getSessionDistanceKm(),
      'altitude': getCurrentAltitude(),
      'accuracy': getCurrentAccuracy(),
      'heading': getCurrentHeading(),
      'latitude': _currentPosition?.latitude,
      'longitude': _currentPosition?.longitude,
      'sessionDurationSeconds': sessionDuration?.inSeconds,
      'totalDurationSeconds': totalDuration?.inSeconds,
      'trackingStartTime': _trackingStartTime?.toIso8601String(),
      'sessionStartTime': _sessionStartTime?.toIso8601String(),
      'lastPositionTime': _lastPositionTime?.toIso8601String(),
      'speedHistorySize': _speedHistory.length,
      'minAccuracy': _minAccuracy,
      'minDistanceFilter': _minDistanceFilter,
    };
  }

  /// Dispose and cleanup
  void dispose() {
    stopTracking();
    _speedController.close();
    _positionController.close();
    _distanceController.close();
    _isInitialized = false;
    print('GeolocationSpeedService: Disposed');
  }
}