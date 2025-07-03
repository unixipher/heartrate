import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class SocketService {
  late io.Socket socket;
  bool isLoading = false;
  String? error;
  double? heartRate;
  double? speed;
  String? token;
  final Function(bool) onLoadingChanged;
  final Function(String?) onErrorChanged;
  final Function(double?) onHeartRateChanged;
  final Function(double?) onSpeedChanged;

  SocketService({
    required this.onLoadingChanged,
    required this.onErrorChanged,
    required this.onHeartRateChanged,
    required this.onSpeedChanged,
  });

  Future<void> fetechtoken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      token = prefs.getString('token');

      if (token != null) {
        _initSocket(token!);
      } else {
        _setError('No token found');
      }
    } catch (e) {
      _setError('Initialization failed: $e');
    }
  }

  void _initSocket(String token) {
    try {
      _setLoading(true);

      socket = io.io(
        'https://authcheck.co',
        io.OptionBuilder()
            .setTransports(['websocket'])
            .enableAutoConnect()
            .enableForceNew()
            .setExtraHeaders({'Authorization': 'Bearer $token'})
            .build(),
      );

      socket
        ..onConnect((_) {
          _setLoading(false);
          print('Connected to Socket.IO server');
        })
        ..onDisconnect((_) {
          _setLoading(false);
          print('Disconnected from Socket.IO server');
        })
        ..onError((err) => _setError('Connection error: $err'))
        ..on('watchdataSaved', (data) => _handleWatchData(data))
        ..on('speeddataSaved', (data) => _handleSpeedData(data))
        ..on('error', (err) => _setError('Server error: $err'))
        ..connect();
    } catch (e) {
      _setError('Connection failed: $e');
    }
  }

  void _setLoading(bool value) {
    isLoading = value;
    onLoadingChanged(value);
  }

  void _setError(String? message) {
    error = message;
    onErrorChanged(message);
  }

  void _handleWatchData(dynamic data) {
    if (data != null && data['heartRate'] != null) {
      final hr = (data['heartRate'] as num).toDouble();
      heartRate = hr;
      onHeartRateChanged(hr);
      print('Heart rate data saved: $hr BPM');
    }
  }

  void _handleSpeedData(dynamic data) {
    if (data != null && data['speed'] != null) {
      final spd = (data['speed'] as num).toDouble();
      speed = spd;
      onSpeedChanged(spd);
      print('Speed data saved: $spd km/h');
    }
  }

  // Send heart rate data to server
  void sendHeartRate(double heartRate) {
    if (socket.connected) {
      socket.emit('watchdata', {'heartRate': heartRate});
      print('Sending heart rate: $heartRate BPM');
    } else {
      _setError('Socket not connected');
    }
  }

  // Send speed data to server
  void sendSpeed(double speed) {
    if (socket.connected) {
      socket.emit('speeddata', {'speed': speed});
      print('Sending speed: $speed km/h');
    } else {
      _setError('Socket not connected');
    }
  }

  void dispose() {
    socket.dispose();
  }
}