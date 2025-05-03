import 'package:flutter/material.dart';
import 'package:testingheartrate/services/audio_manager.dart';
import 'package:testingheartrate/screens/completion/completion_screen.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class CustomSliderTrackShape extends RoundedRectSliderTrackShape {
  final List<Duration> timestamps;
  final Duration totalDuration;

  CustomSliderTrackShape(
      {required this.timestamps, required this.totalDuration});

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    double additionalActiveTrackHeight = 0.0,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      textDirection: textDirection,
      thumbCenter: thumbCenter,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final Canvas canvas = context.canvas;
    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final markerPaint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..strokeWidth = 4.0;

    for (final timestamp in timestamps) {
      final positionPercentage =
          timestamp.inMilliseconds / totalDuration.inMilliseconds;
      final markerX = trackRect.left + (trackRect.width * positionPercentage);
      final markerY = trackRect.center.dy;

      canvas.drawLine(
        Offset(markerX, markerY - 6),
        Offset(markerX, markerY + 6),
        markerPaint,
      );
    }
  }
}

class WithoutWatchScreen extends StatefulWidget {
  final String audioUrl;
  final int id;
  final String challengeName;
  final String image;
  final int zoneId;
  final int indexid;

  const WithoutWatchScreen({
    super.key,
    required this.audioUrl,
    required this.id,
    required this.challengeName,
    required this.image,
    required this.zoneId,
    required this.indexid,
  });

  @override
  State<WithoutWatchScreen> createState() => _WithoutWatchScreenState();
}

class _WithoutWatchScreenState extends State<WithoutWatchScreen> {
  final AudioManager _audioManager = AudioManager();

  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  List<Duration> _timestamps = [];
  List<bool> _triggered = [];

  void _togglePlayPause() {
    setState(() {
      if (_audioManager.isPlaying) {
        _audioManager.pause();
      } else {
        _audioManager.play(widget.audioUrl);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _initializeTimestamps();
    _initializeAudioListeners();
    _audioManager.play(widget.audioUrl);
    _audioManager.audioPlayer.setVolume(0.4);
    debugPrint('Main audio started: ${widget.audioUrl}');
  }

  void _initializeTimestamps() {
    int adjustedIndexId = widget.indexid;

    if (widget.indexid >= 1) {
      adjustedIndexId = ((widget.indexid - 1) % 5) + 1;
    }

    List<String> timeStrings = [];
    switch (adjustedIndexId) {
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
          minutes: int.parse(parts[0]), seconds: int.parse(parts[1]));
    }).toList();

    _triggered = List<bool>.filled(_timestamps.length, false);
  }

  void _initializeAudioListeners() {
    _audioManager.audioPlayer.onDurationChanged
        .listen((d) => setState(() => _totalDuration = d));
    _audioManager.audioPlayer.onPositionChanged.listen(_handlePositionUpdate);
    _audioManager.audioPlayer.onPlayerComplete.listen(_handleAudioCompletion);
  }

  void _handlePositionUpdate(Duration position) {
    setState(() => _currentPosition = position);
    _checkForOverlayTrigger(position);
  }

  void _checkForOverlayTrigger(Duration position) {
    for (int i = 0; i < _timestamps.length; i++) {
      if (!_triggered[i] && _isInTimestampRange(position, _timestamps[i])) {
        _triggered[i] = true;
        _audioManager.playOverlay('audio/A_$i.mp3');
        debugPrint('Playing overlay: A_$i.mp3 at ${_formatDuration(position)}');
      }
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
        body: jsonEncode({'challengeId': widget.id, 'status': true}),
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
          zoneId: widget.zoneId,
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${twoDigits(duration.inMinutes)}:${twoDigits(duration.inSeconds.remainder(60))}";
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
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        thumbColor: Colors.purple,
                        activeTrackColor: Colors.purple,
                        inactiveTrackColor: Colors.white30,
                        trackHeight: 12.0,
                        thumbShape: RoundSliderThumbShape(
                          enabledThumbRadius: _timestamps.any((timestamp) =>
                                  (timestamp.inSeconds -
                                          _currentPosition.inSeconds)
                                      .abs() <=
                                  1)
                              ? 12.0
                              : 0.0,
                        ),
                        trackShape: CustomSliderTrackShape(
                          timestamps: _timestamps,
                          totalDuration: _totalDuration,
                        ),
                        overlayColor: Colors.red.withOpacity(0.2),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 28.0,
                        ),
                        disabledThumbColor: Colors.black,
                      ),
                      child: SizedBox(
                        width: MediaQuery.of(context).size.width * 1,
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
