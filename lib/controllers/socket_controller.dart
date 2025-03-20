import 'package:socket_io_client/socket_io_client.dart' as io;
import '../models/heart_rate.dart';
import '../utils/constants.dart';
import 'audio_controller.dart';

class SocketController {
  late io.Socket socket;
  bool isConnected = false;
  bool isLoading = false;
  Function(HeartRate)? onHeartRateReceived;
  Function(String)? onError;
  
  final AudioController audioController = AudioController();
  bool isMainTrackStarted = false;

  SocketController({
    required String token,
    this.onHeartRateReceived,
    this.onError,
  }) {
    _initSocket(token);
  }

  void _initSocket(String token) {
    try {
      isLoading = true;
      
      socket = io.io(
        kServerUrl,
        io.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .enableForceNew()
          .setExtraHeaders({'Authorization': 'Bearer $token'})
          .build(),
      );

      socket
        ..onConnect((_) {
          isConnected = true;
          isLoading = false;
        })
        ..onDisconnect((_) {
          isConnected = false;
          isLoading = false;
        })
        ..onError((err) {
          if (onError != null) onError!('Connection error: $err');
        })
        ..on('watchdataSaved', (data) {
          if (data?['heartRate'] != null) {
            final heartRateValue = (data['heartRate'] as num).toDouble();
            final heartRate = HeartRate(value: heartRateValue);
            
            // Pass the heart rate to any external listeners.
            if (onHeartRateReceived != null) onHeartRateReceived!(heartRate);
            
            // Update the AudioController.
            audioController.currentHeartRate = heartRateValue;
            if (!isMainTrackStarted) {
              audioController.startMainTrack();
              isMainTrackStarted = true;
            }
          }
        })
        ..connect();
    } catch (e) {
      if (onError != null) onError!('Connection failed: $e');
    }
  }

  void disconnect() {
    if (socket.connected) {
      socket.disconnect();
      socket.dispose();
    }
    audioController.dispose();
  }
}