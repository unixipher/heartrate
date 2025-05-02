import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:testingheartrate/services/audio_manager.dart';
import 'package:testingheartrate/services/socket_service.dart';
import 'package:testingheartrate/views/completion_screen.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class MusicPlayerScreen extends StatefulWidget {
  final String audioUrl;
  final int id;
  final String challengeName;
  final String image;
  final int zoneId;

  const MusicPlayerScreen({
    super.key,
    required this.audioUrl,
    required this.id,
    required this.challengeName,
    required this.image,
    required this.zoneId,
  });

  @override
  State<MusicPlayerScreen> createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends State<MusicPlayerScreen> {
  final AudioManager _audioManager = AudioManager();
  late final SocketService _socketService;

  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  int? _currentHR;
  double? _maxHR;
  List<Duration> _timestamps = [];
  List<bool> _triggered = [];
  bool _hasMaxHR = false;

  @override
  void initState() {
    super.initState();
    _initializeTimestamps();
    _initializeSocketService();
    _initializeAudioListeners();
    _audioManager.play(widget.audioUrl);
  }

  void _initializeTimestamps() {
    List<String> timeStrings = [];
    switch (widget.zoneId) {
      case 0:
        timeStrings = ['2:20', '2:50', '3:20', '3:50', '4:20', '4:50'];
        break;
      case 1:
      case 2:
      case 3:
      case 4:
        timeStrings = [
          '1:20',
          '1:50',
          '2:20',
          '2:50',
          '3:20',
          '3:50',
          '4:20',
          '4:50'
        ];
        break;
      case 5:
        timeStrings = ['1:20', '1:50', '2:20', '2:50', '3:20', '3:50'];
        break;
      default:
        timeStrings = [];
    }

    _timestamps = timeStrings.map((time) {
      final parts = time.split(':');
      return Duration(
        minutes: int.parse(parts[0]),
        seconds: int.parse(parts[1]),
      );
    }).toList();

    _triggered = List<bool>.filled(_timestamps.length, false);
    debugPrint('Timestamps: $_timestamps');
  }

  void _initializeSocketService() {
    _socketService = SocketService(
      onLoadingChanged: (isLoading) => debugPrint('Loading: $isLoading'),
      onErrorChanged: (error) => debugPrint('Error: $error'),
      onHeartRateChanged: _handleHeartRateUpdate,
    );
    _socketService.fetechtoken();
  }

  void _initializeAudioListeners() {
    _audioManager.audioPlayer.onDurationChanged
        .listen((d) => setState(() => _totalDuration = d));
    _audioManager.audioPlayer.onPositionChanged.listen(_handlePositionUpdate);
    _audioManager.audioPlayer.onPlayerComplete.listen(_handleAudioCompletion);
  }

  void _handleHeartRateUpdate(double? heartRate) async {
    if (heartRate == null) return;

    if (!_hasMaxHR) await _fetchMaxHR();

    setState(() => _currentHR = heartRate.toInt());

    if (_maxHR == null) return;

    final currentHRPercent = (_currentHR! / _maxHR!) * 100;
    final inValidRange = currentHRPercent >= 50 && currentHRPercent <= 80;

    if (!inValidRange) return;

    _checkForOverlayTrigger(_currentPosition);
  }

  Future<void> _fetchMaxHR() async {
    setState(() {
      _maxHR = 180;
      _hasMaxHR = true;
    });
    debugPrint('Max HR: $_maxHR');
  }

  void _handlePositionUpdate(Duration position) {
    setState(() => _currentPosition = position);
    if (_currentHR != null && _maxHR != null) _checkForOverlayTrigger(position);
    debugPrint(widget.zoneId.toString());
    debugPrint('Checking overlay trigger at: ${_formatDuration(position)}');
    debugPrint('Current HR: $_currentHR');
  }

  void _checkForOverlayTrigger(Duration position) {
    final hrPercentage = (_currentHR! / _maxHR!) * 100;
    final overlayType = _determineOverlayType(hrPercentage);

    for (int i = 0; i < _timestamps.length; i++) {
      if (!_triggered[i] && _isInTimestampRange(position, _timestamps[i])) {
        _triggered[i] = true;
        debugPrint('Triggered overlay at index $i');
        _audioManager.playOverlay('audio/${overlayType}_$i.mp3');
        debugPrint('Playing overlay: ${overlayType}_$i.mp3');
        debugPrint('Timestamp: ${_timestamps[i]}');
        debugPrint('Current Position: $position');
      }
    }
  }

  String _determineOverlayType(double hrPercentage) {
    if (hrPercentage > 50 && hrPercentage <= 60) {
      return 'S';
    } else if (hrPercentage > 60 && hrPercentage <= 70) {
      return 'S';
    } else if (hrPercentage > 70 && hrPercentage <= 80) {
      return 'S';
    } else {
      return 'A';
    }
  }

  bool _isInTimestampRange(Duration position, Duration target) {
    final positionMs = position.inMilliseconds;
    final targetMs = target.inMilliseconds;
    return (positionMs >= targetMs - 1000 && positionMs <= targetMs + 1000);
  }

  Future<void> _handleAudioCompletion(event) async {
    _audioManager.stop();
    await _updateChallengeStatus();
    _navigateToCompletionScreen();
  }

  Future<void> _updateChallengeStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    try {
      final response = await http.post(
        Uri.parse('https://authcheck.co/updatechallenge'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'challengeId': widget.id,
          'status': true,
        }),
      );

      if (response.statusCode != 200) {
        debugPrint('Challenge update failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Update challenge error: $e');
    }
  }

  void _navigateToCompletionScreen() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => CompletionScreen(
          storyName: widget.challengeName,
          backgroundImage: widget.image,
          storyId: widget.id,
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${twoDigits(duration.inMinutes)}:${twoDigits(duration.inSeconds.remainder(60))}";
  }

  void _togglePlayPause() {
    if (_audioManager.isPlaying) {
      _audioManager.pause();
    } else {
      _audioManager.resume();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: Text(
          widget.challengeName,
          style: const TextStyle(
            fontFamily: 'Thewitcher',
            fontSize: 24,
            letterSpacing: 2,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage(widget.image),
                fit: BoxFit.cover,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withOpacity(0.8),
                  Colors.black.withOpacity(0.2),
                  Colors.black.withOpacity(0.8),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          Column(
            children: [
              const Spacer(flex: 4),
              GestureDetector(
                onTap: _togglePlayPause,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7B1FA2), Color(0xFFE040FB)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.purple.withOpacity(0.6),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Icon(
                    _audioManager.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 80,
                  ),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        thumbColor: Colors.purple,
                        activeTrackColor: Colors.purple,
                        inactiveTrackColor: Colors.white30,
                        trackHeight: 8.0,
                      ),
                      child: Slider(
                        value: _currentPosition.inSeconds.toDouble(),
                        min: 0,
                        max: _totalDuration.inSeconds.toDouble() > 0
                            ? _totalDuration.inSeconds.toDouble()
                            : 1,
                        onChanged: (value) async {
                          final position = Duration(seconds: value.toInt());
                          await _audioManager.audioPlayer.seek(position);
                        },
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(_currentPosition),
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 14),
                        ),
                        Text(
                          _formatDuration(_totalDuration),
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 14),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Spacer(flex: 2),
            ],
          ),
        ],
      ),
    );
  }
}
