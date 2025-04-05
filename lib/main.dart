import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:audioplayers/audioplayers.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _token = '';
  double? heartRate;
  String error = '';
  late io.Socket socket;
  bool isAuthenticated = false;
  bool isLoading = false;
  bool _isAuthLoading = false;
  final AudioController audioController = AudioController();

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token != null) {
      setState(() {
        _token = token;
        isAuthenticated = true;
      });
      _initSocket(token);
    }
  }

  Future<void> _handleAppleSignIn() async {
    setState(() {
      _isAuthLoading = true;
      error = '';
    });

    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
      );

      final userIdentifier = credential.userIdentifier;
      final identityToken = credential.identityToken;

      if (userIdentifier == null || identityToken == null) {
        throw Exception('Missing required authentication data');
      }

      final response = await http.post(
        Uri.parse('https://authcheck.co/auth'),
        headers: {'Accept': '*/*', 'Content-Type': 'application/json'},
        body: json.encode({'token': userIdentifier}),
      );

      if (response.statusCode == 201) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', userIdentifier);

        setState(() {
          _token = userIdentifier;
          isAuthenticated = true;
        });

        _initSocket(userIdentifier);
      } else {
        throw Exception('Failed to authenticate: ${response.body}');
      }
    } catch (error) {
      setState(() => this.error = "Authentication failed: ${error.toString()}");
    } finally {
      setState(() => _isAuthLoading = false);
    }
  }

  void _initSocket(String token) {
    try {
      setState(() => isLoading = true);

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
        ..onConnect((_) => setState(() => isLoading = false))
        ..onDisconnect((_) => setState(() => isLoading = false))
        ..onError((err) => setState(() => error = 'Connection error: $err'))
        ..on('watchdataSaved', (data) {
          if (data?['heartRate'] != null) {
            final hr = data['heartRate'].toDouble();
            setState(() => heartRate = hr);
            
            // Start main track on first heart rate received
            if (!audioController.isMainTrackPlaying) {
              audioController.startMainTrack();
            }
            
            // Update heart rate for overlay decisions
            audioController.currentHeartRate = hr;
          }
        })
        ..connect();
    } catch (e) {
      setState(() => error = 'Connection failed: $e');
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');

    if (socket.connected) {
      socket.disconnect();
      socket.dispose();
    }

    setState(() {
      _token = '';
      isAuthenticated = false;
      heartRate = null;
      error = '';
    });
    audioController.dispose();
  }

  @override
  void dispose() {
    if (isAuthenticated) socket.disconnect();
    audioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        primarySwatch: Colors.red,
        brightness: Brightness.light,
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.red.shade100, Colors.red.shade50],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.favorite, color: Colors.red, size: 80),
                    const SizedBox(height: 16),
                    Text('Heart Rate Monitor',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade800,
                      ),
                    ),
                    const SizedBox(height: 50),
                    if (!isAuthenticated) _buildAuthButton(),
                    if (isAuthenticated) _buildAuthenticatedContent(),
                    if (error.isNotEmpty) _buildErrorDisplay(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAuthButton() {
    return Column(
      children: [
        if (_isAuthLoading)
          const CircularProgressIndicator()
        else
          SignInWithAppleButton(
            onPressed: _handleAppleSignIn,
            style: SignInWithAppleButtonStyle.black,
            height: 50,
          ),
      ],
    );
  }

  Widget _buildAuthenticatedContent() {
    return Column(
      children: [
        _buildHeartRateDisplay(),
        const SizedBox(height: 30),
        _buildAudioStatus(),
        const SizedBox(height: 30),
        _buildLogoutButton(),
      ],
    );
  }

  Widget _buildHeartRateDisplay() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withOpacity(0.1),
            spreadRadius: 2,
            blurRadius: 10,
            offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          if (isLoading)
            const CircularProgressIndicator(color: Colors.red)
          else if (heartRate != null)
            Column(
              children: [
                Text(heartRate!.toStringAsFixed(1)),
                Text('BPM', style: TextStyle(color: Colors.grey.shade600)),
                Icon(Icons.favorite, color: _getHeartRateColor(heartRate!), size: 40),
                Text(_getHeartRateStatus(heartRate!)),
              ],
            )
          else
            const Text('Waiting for heart rate...'),
        ],
      ),
    );
  }

  Widget _buildAudioStatus() {
    return Column(
      children: [
        if (audioController.isMainTrackPlaying)
          Text('Main track: ${audioController.currentPlayTime}s',
              style: TextStyle(color: Colors.grey.shade700)),
        if (audioController.lastPlayedOverlay != null)
          Text('Last overlay: ${audioController.lastPlayedOverlay}',
              style: TextStyle(color: Colors.green.shade800)),
      ],
    );
  }

  Widget _buildLogoutButton() {
    return ElevatedButton.icon(
      icon: const Icon(Icons.logout),
      label: const Text('Logout'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.red[50],
        foregroundColor: Colors.red[800]),
      onPressed: _logout,
    );
  }

  Widget _buildErrorDisplay() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.red.shade100,
          borderRadius: BorderRadius.circular(8)),
      child: Text(error, style: TextStyle(color: Colors.red.shade800)),
    );
  }

  Color _getHeartRateColor(double rate) {
    if (rate < 60) return Colors.blue;
    if (rate < 100) return Colors.green;
    if (rate < 120) return Colors.orange;
    return Colors.red;
  }

  String _getHeartRateStatus(double rate) {
    if (rate < 60) return 'Resting';
    if (rate < 100) return 'Normal';
    if (rate < 120) return 'Elevated';
    return 'High';
  }
}

class AudioController {
  final AudioPlayer mainPlayer = AudioPlayer();
  final List<AudioPlayer> overlayPlayers = [];
  Timer? playbackTimer;
  int currentPlayTime = 0;
  double? currentHeartRate;
  String? lastPlayedOverlay;
  bool isMainTrackPlaying = false;
  final double maxHeartRate = 190.0;

  final List<int> timestamps = [
    107, 165, 212, 236, 279, 296, 420, 510,
    542, 605, 615, 636, 690, 740, 775, 795, 838
  ];

  final Map<int, bool> playedOverlays = {};

  final List<List<double>> targetRanges = [
    [0.50, 0.60], [0.60, 0.70], [0.60, 0.70], [0.64, 0.76], [0.64, 0.76],
    [0.64, 0.76], [0.77, 0.89], [0.77, 0.89], [0.77, 0.89], [0.77, 0.89],
    [0.64, 0.76], [0.64, 0.76], [0.64, 0.0],  [0.64, 0.0],  [0.64, 0.0],
    [0.64, 0.0],  [0.64, 0.0]
  ];

  Future<void> startMainTrack() async {
    try {
      await mainPlayer.stop();
      await mainPlayer.setVolume(0.15);
      await mainPlayer.play(AssetSource('MainTrack_15.mp3'));
      isMainTrackPlaying = true;
      _startPlaybackTimer();
    } catch (e) {
      debugPrint('Error playing main track: $e');
    }
  }

  void _startPlaybackTimer() {
    playbackTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      currentPlayTime = timer.tick;
      _checkForOverlay();
    });
  }

  void _checkForOverlay() {
    for (int i = 0; i < timestamps.length; i++) {
      if (currentPlayTime == timestamps[i] && !playedOverlays.containsKey(i)) {
        playedOverlays[i] = true;
        _playOverlay(i);
        break;
      }
    }
  }

  Future<void> _playOverlay(int index) async {
    if (index >= timestamps.length || currentHeartRate == null) return;
    
    try {
      final range = targetRanges[index];
      final minTarget = maxHeartRate * range[0];
      final maxTarget = maxHeartRate * range[1];
      
      final trackToPlay = (currentHeartRate! >= minTarget && currentHeartRate! <= maxTarget)
          ? 'A_${index + 1}.mp3'
          : 'S_${index + 1}.mp3';

      final overlayPlayer = AudioPlayer();
      overlayPlayers.add(overlayPlayer);
      
      await overlayPlayer.play(AssetSource(trackToPlay));
      lastPlayedOverlay = '${timestamps[index]}s: $trackToPlay';

      overlayPlayer.onPlayerComplete.listen((_) {
        overlayPlayer.dispose();
        overlayPlayers.remove(overlayPlayer);
      });
    } catch (e) {
      debugPrint('Error playing overlay: $e');
    }
  }

  void dispose() {
    playbackTimer?.cancel();
    mainPlayer.dispose();
    for (final player in overlayPlayers) {
      player.dispose();
    }
    isMainTrackPlaying = false;
    playedOverlays.clear();
  }
}