import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';

class MotionDetectionService {
  static final MotionDetectionService _instance = MotionDetectionService._internal();
  factory MotionDetectionService() => _instance;
  MotionDetectionService._internal();

  final StreamController<bool> _motionStreamController = StreamController<bool>.broadcast();
  Stream<bool> get motionStream => _motionStreamController.stream;

  static const double _threshold = 0.1; // lower = more sensitive
  bool _isMoving = false;
  StreamSubscription? _accelSub;

  void start() {
    _accelSub = accelerometerEvents.listen((event) {
      final magnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      final delta = (magnitude - 9.8).abs(); // gravity = 9.8 m/s²

      bool moving = delta > _threshold;
      if (moving != _isMoving) {
        _isMoving = moving;
        _motionStreamController.add(_isMoving);
      }
    });
  }

  void stop() {
    _accelSub?.cancel();
  }

  bool get isMoving => _isMoving;
}
