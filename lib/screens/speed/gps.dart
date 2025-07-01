import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:testingheartrate/services/kalman_filter.dart';
import 'package:testingheartrate/services/motion_detection_service.dart';

class GeolocationScreen extends StatefulWidget {
  const GeolocationScreen({Key? key}) : super(key: key);

  @override
  State<GeolocationScreen> createState() => _GeolocationScreenState();
}

class _GeolocationScreenState extends State<GeolocationScreen> {
  final KalmanFilter _speedKalman = KalmanFilter();
  final MotionDetectionService _motionService = MotionDetectionService();

  Position? _previousPosition;
  double? _latitude;
  double? _longitude;
  double? _accuracy;
  double? _speed;
  bool _isMoving = false;
  String _status = 'Initializing...';

  StreamSubscription<Position>? _positionSub;
  StreamSubscription<bool>? _motionSub;

  @override
  void initState() {
    super.initState();
    _initTracking();
  }

  Future<void> _initTracking() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled || permission == LocationPermission.deniedForever) {
      setState(() => _status = 'GPS not available or permission denied');
      return;
    }

    setState(() => _status = 'Tracking...');
    _motionService.start();
    _motionSub = _motionService.motionStream.listen((moving) {
      setState(() {
        _isMoving = moving;
      });
    });

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
      ),
    ).listen((Position pos) {
      final current = pos;
      double rawSpeed = 0.0;

      if (_previousPosition != null) {
        final prev = _previousPosition!;
        final timeDelta = current.timestamp!.difference(prev.timestamp!).inMilliseconds / 1000.0;

        final distance = Geolocator.distanceBetween(
          prev.latitude,
          prev.longitude,
          current.latitude,
          current.longitude,
        );

        // If coordinates haven't changed and motion is still, reset speed to zero
        if (distance == 0.0 && !_isMoving) {
          rawSpeed = 0.0;
        } else {
          rawSpeed = timeDelta > 0 ? distance / timeDelta : 0.0;
          if (!_isMoving || rawSpeed < 0.5) rawSpeed = 0.0;
        }

        final smoothedSpeed = _speedKalman.filter(rawSpeed);

        setState(() {
          _speed = smoothedSpeed;
        });
      }

      setState(() {
        _latitude = current.latitude;
        _longitude = current.longitude;
        _accuracy = current.accuracy;
      });

      _previousPosition = current;
    });
  }

  @override
  void dispose() {
    _motionSub?.cancel();
    _positionSub?.cancel();
    _motionService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String lat = _latitude?.toStringAsFixed(6) ?? '...';
    String lon = _longitude?.toStringAsFixed(6) ?? '...';
    String acc = _accuracy?.toStringAsFixed(2) ?? '...';
    String spd = _speed != null
        ? '${_speed!.toStringAsFixed(2)} m/s (${(_speed! * 3.6).toStringAsFixed(1)} km/h)'
        : '...';

    return Scaffold(
      appBar: AppBar(title: const Text('Enhanced GPS Tracker')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_status, style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 24),
              Text('Latitude: $lat', style: const TextStyle(fontSize: 20)),
              Text('Longitude: $lon', style: const TextStyle(fontSize: 20)),
              Text('Accuracy: ±$acc m', style: const TextStyle(fontSize: 20)),
              const SizedBox(height: 16),
              Text('Speed: $spd', style: const TextStyle(fontSize: 22)),
              const SizedBox(height: 16),
              Text('Motion: ${_isMoving ? "MOVING" : "STILL"}',
                  style: TextStyle(
                    fontSize: 22,
                    color: _isMoving ? Colors.green : Colors.grey,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
