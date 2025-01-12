import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:audioplayers/audioplayers.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Heart Rate Monitor',
      theme: ThemeData(
        primarySwatch: Colors.red,
        useMaterial3: true,
      ),
      home: const HeartRateScreen(),
    );
  }
}

class HeartRateDisplay extends StatelessWidget {
  final double heartRate; // Change to double

  const HeartRateDisplay({
    super.key,
    required this.heartRate,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.favorite,
          color: Colors.red,
          size: 32,
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(
                  opacity: animation,
                  child: child,
                );
              },
              child: Text(
                '$heartRate', // This will now display a double
                key: ValueKey<double>(heartRate), // Change to double
                style: const TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Text(
              'BPM',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class AudioManager {
  final AudioPlayer mainPlayer = AudioPlayer();
  final List<AudioPlayer> overlayPlayers = [];
  Timer? playbackTimer;
  int currentPlayTime = 0;

  final List<int> timestamps = [
    107, 165, 212, 236, 279, 296, 420, 510,
    542, 605, 615, 636, 690, 740, 775, 795, 838
  ];

  final Map<int, bool> playedOverlays = {};
  final double maxHeartRate = 190.0;

  final List<List<double>> targetRanges = [
    [0.50, 0.60], [0.60, 0.70], [0.60, 0.70], [0.64, 0.76], [0.64, 0.76],
    [0.64, 0.76], [0.77, 0.89], [0.77, 0.89], [0.77, 0.89], [0.77, 0.89],
    [0.64, 0.76], [0.64, 0.76], [0.64, 0.0], [0.64, 0.0], [0.64, 0.0],
    [0.64, 0.0], [0.64, 0.0]
  ];

  Future<void> startMainTrack() async {
    try {
      await mainPlayer.setVolume(0.15);
      await mainPlayer.play(AssetSource('MainTrack_15.mp3'));
      startPlaybackTimer();
      print('Main track started');
    } catch (e) {
      print('Error playing main track: $e');
    }
  }

  void startPlaybackTimer() {
    playbackTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      currentPlayTime = timer.tick;
      print('Current play time: $currentPlayTime seconds');
      checkTimeForOverlay();
    });
  }

  void checkTimeForOverlay() {
    for (int i = 0; i < timestamps.length; i++) {
      if (currentPlayTime == timestamps[i] && playedOverlays[i] != true) {
        playedOverlays[i] = true;
        print('Timestamp matched: ${timestamps[i]} seconds');
        playOverlay(i);
        break;
      }
    }
  }

  Future<void> playOverlay(int index) async {
    if (index >= timestamps.length) return;

    try {
      String trackToPlay;
      double minTarget = maxHeartRate * targetRanges[index][0];
      double maxTarget = maxHeartRate * targetRanges[index][1];

      // Get current heart rate (you'll need to implement this connection)
      double currentHeartRate = 0.0; // Replace with actual heart rate

      if (currentHeartRate >= minTarget && currentHeartRate <= maxTarget) {
        trackToPlay = 'A_${index + 1}.mp3';
        print('Playing A track for index $index');
      } else {
        trackToPlay = 'S_${index + 1}.mp3';
        print('Playing S track for index $index');
      }

      final overlayPlayer = AudioPlayer();
      overlayPlayers.add(overlayPlayer);
      await overlayPlayer.play(AssetSource(trackToPlay));

      overlayPlayer.onPlayerComplete.listen((event) {
        overlayPlayer.dispose();
        overlayPlayers.remove(overlayPlayer);
        print('Overlay track completed and cleaned up');
      });
    } catch (e) {
      print('Error playing overlay track: $e');
    }
  }

  void dispose() {
    playbackTimer?.cancel();
    mainPlayer.dispose();
    for (var player in overlayPlayers) {
      player.dispose();
    }
    print('Audio manager disposed');
  }
}

class HeartRateScreen extends StatefulWidget {
  const HeartRateScreen({super.key});

  @override
  State<HeartRateScreen> createState() => _HeartRateScreenState();
}

class _HeartRateScreenState extends State<HeartRateScreen> {
  Map<String, dynamic>? heartRateData;
  bool isLoading = false;
  String error = '';
  Timer? _refreshTimer;
  late AudioManager audioManager;
  bool isMainTrackStarted = false;

  @override
  void initState() {
    super.initState();
    audioManager = AudioManager();
    fetchHeartRate();
    _startAutoRefresh();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      fetchHeartRate();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    audioManager.dispose();
    super.dispose();
  }

  Future<void> fetchHeartRate() async {
    try {
      final response = await http.get(
        Uri.parse('https://server-toza.onrender.com/api/results'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final newData = json.decode(response.body);
        setState(() {
          heartRateData = newData;
          isLoading = false;
        });

        if (!isMainTrackStarted) {
          isMainTrackStarted = true;
          await audioManager.startMainTrack();
          print('Started main track after first heart rate data');
        }
      } else {
        setState(() {
          error = 'Failed to fetch data: ${response.statusCode}';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        error = 'Error: $e';
        isLoading = false;
      });
    }
  }

  String formatDateTime(String dateTimeString) {
    final dateTime = DateTime.parse(dateTimeString);
    final formatter = DateFormat('MMM d, y HH:mm:ss');
    return formatter.format(dateTime.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Heart Rate Monitor'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isLoading)
              const Center(child: CircularProgressIndicator())
            else if (error.isNotEmpty)
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      error,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: fetchHeartRate,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            else if (heartRateData != null)
                Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        HeartRateDisplay(
                          heartRate: heartRateData!['heartRate'].toDouble(), // Ensure heartRate is a double
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Reading ID: ${heartRateData!['id']}',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Measured at: ${formatDateTime(heartRateData!['createdAt'])}',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
