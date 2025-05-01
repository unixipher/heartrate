import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class SocketService {
  late io.Socket socket;
  bool isLoading = false;
  String? error;
  double? heartRate;
  String? token;
  final Function(bool) onLoadingChanged;
  final Function(String?) onErrorChanged;
  late final Function(double?) onHeartRateChanged;

  SocketService({
    required this.onLoadingChanged,
    required this.onErrorChanged,
    required this.onHeartRateChanged,
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
        ..onConnect((_) => _setLoading(false))
        ..onDisconnect((_) => _setLoading(false))
        ..onError((err) => _setError('Connection error: $err'))
        ..on('watchdataSaved', (data) => _handleWatchData(data))
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
    }
  }

  void dispose() {
    socket.dispose();
  }
}