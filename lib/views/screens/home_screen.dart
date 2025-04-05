import 'package:flutter/material.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/otp_controller.dart';
import '../../controllers/socket_controller.dart';
import '../../controllers/audio_controller.dart';
import '../../models/heart_rate.dart';
import '../../views/widgets/heart_rate_display.dart';

class HomeScreen extends StatefulWidget {
  final AuthController authController;
  final OTPController otpController;
  final SocketController socketController;
  final Function() onLogout;

  const HomeScreen({
    super.key,
    required this.authController,
    required this.otpController,
    required this.socketController,
    required this.onLogout,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  HeartRate? heartRate;
  String error = '';
  late AudioController audioController;

  @override
  void initState() {
    super.initState();
    audioController = AudioController();
    widget.socketController.onHeartRateReceived = _updateHeartRate;
    widget.socketController.onError = _handleError;
  }

  void _updateHeartRate(HeartRate rate) {
    setState(() => heartRate = rate);
  }

  void _handleError(String errorMessage) {
    setState(() => error = errorMessage);
  }

  void _refreshOTP() {
    widget.otpController.fetchOTP(widget.authController.token);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.favorite, color: Colors.red, size: 80),
          const SizedBox(height: 16),
          Text(
            'Heart Rate Monitor',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.red.shade800,
            ),
          ),
          const SizedBox(height: 50),
          HeartRateDisplay(
            heartRate: heartRate,
            isLoading: widget.socketController.isLoading,
          ),
          const SizedBox(height: 20),
          _buildAudioButton(),
          const SizedBox(height: 20),
          _buildLogoutButton(),
          if (error.isNotEmpty) _buildErrorDisplay(),
        ],
      ),
    );
  }

  Widget _buildAudioButton() {
    return ElevatedButton.icon(
      icon: const Icon(Icons.music_note),
      label: const Text('Start Main Track'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue[50],
        foregroundColor: Colors.blue[800],
      ),
      onPressed: () {
        audioController.startMainTrack();
      },
    );
  }

  Widget _buildLogoutButton() {
    return ElevatedButton.icon(
      icon: const Icon(Icons.logout),
      label: const Text('Logout'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.red[50],
        foregroundColor: Colors.red[800],
      ),
      onPressed: widget.onLogout,
    );
  }

  Widget _buildErrorDisplay() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        error,
        style: TextStyle(color: Colors.red.shade800),
      ),
    );
  }
}
