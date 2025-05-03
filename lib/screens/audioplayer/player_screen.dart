import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:testingheartrate/services/audio_manager.dart';
import 'package:testingheartrate/services/socket_service.dart';
import 'package:testingheartrate/screens/completion/completion_screen.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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

class PlayerScreen extends StatefulWidget {
  final String audioUrl;
  final int id;
  final String challengeName;
  final String image;
  final int zoneId;
  final int indexid;
  final String? duration;
  final int storyId;
  final List<String>? challengequeue;

  const PlayerScreen({
    super.key,
    required this.audioUrl,
    required this.id,
    required this.challengeName,
    required this.image,
    required this.zoneId,
    required this.indexid,
    this.duration,
    required this.storyId,
    this.challengequeue,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
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
    _audioManager.audioPlayer.setVolume(0.4);
    debugPrint(
        'Main audio started: ${widget.audioUrl} at ${_formatDuration(Duration.zero)}');
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
    int lowerBound = 0;
    int upperBound = 0;

    if (widget.zoneId == 1) {
      lowerBound = 50;
      upperBound = 60;
    } else if (widget.zoneId == 2) {
      lowerBound = 60;
      upperBound = 70;
    } else if (widget.zoneId == 3) {
      lowerBound = 70;
      upperBound = 80;
    }

    if (currentHRPercent < lowerBound || currentHRPercent > upperBound) {
      if (_audioManager.isPlaying) {
        Future.delayed(const Duration(seconds: 10), () {
          if (currentHRPercent < lowerBound || currentHRPercent > upperBound) {
            _audioManager.pause();
            debugPrint(
                'Music paused due to HR out of range for 10 seconds: $currentHRPercent');
          }
        });
      }
      return;
    } else {
      if (!_audioManager.isPlaying) {
        _audioManager.resume();
        debugPrint('Music resumed: $currentHRPercent');
      }
    }

    if (!inValidRange) return;

    _checkForOverlayTrigger(_currentPosition);
  }

  Future<void> _fetchMaxHR() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    try {
      final response = await http.get(
        Uri.parse('https://authcheck.co/getuser'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': '*/*',
          'User-Agent': 'Thunder Client (https://www.thunderclient.com)',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _maxHR = data['user']['maxhr']?.toDouble();
        });
      } else {
        debugPrint('Failed to fetch maxHR: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching maxHR: $e');
    }
    setState(() {
      _hasMaxHR = true;
    });
    debugPrint('Max HR: $_maxHR');
  }

  void _handlePositionUpdate(Duration position) {
    setState(() => _currentPosition = position);
    if (_currentHR != null && _maxHR != null) _checkForOverlayTrigger(position);
  }

  void _checkForOverlayTrigger(Duration position) {
    final hrPercentage = (_currentHR! / _maxHR!) * 100;
    final overlayType = _determineOverlayType(hrPercentage);

    // final pacingDurations = [
    //   const Duration(minutes: 0, seconds: 0),
    //   const Duration(minutes: 1, seconds: 0),
    //   const Duration(minutes: 2, seconds: 0),
    //   const Duration(minutes: 3, seconds: 0),
    //   const Duration(minutes: 4, seconds: 0),
    //   const Duration(minutes: 5, seconds: 0),
    // ];
    // int paceHRLowerBound = 0;
    // int paceHRUpperBound = 0;

    // if (widget.zoneId == 1) {
    //   paceHRLowerBound = ((0.50 * _maxHR!) / 10).round() * 10;
    //   paceHRUpperBound = ((0.60 * _maxHR!) / 10).round() * 10;
    // } else if (widget.zoneId == 2) {
    //   paceHRLowerBound = ((0.60 * _maxHR!) / 10).round() * 10;
    //   paceHRUpperBound = ((0.70 * _maxHR!) / 10).round() * 10;
    // } else if (widget.zoneId == 3) {
    //   paceHRLowerBound = ((0.70 * _maxHR!) / 10).round() * 10;
    //   paceHRUpperBound = ((0.80 * _maxHR!) / 10).round() * 10;
    // }

    // final pacingMusic = [
    //   'audio/$paceHRLowerBound.mp3',
    //   'audio/${paceHRLowerBound + 10}.mp3',
    //   'audio/${paceHRLowerBound + 20}.mp3',
    //   'audio/${paceHRLowerBound + 10}.mp3',
    // ];

    // debugPrint('Pace HR Range: $paceHRLowerBound - $paceHRUpperBound');

    // for (int i = 0; i < pacingDurations.length - 1; i++) {
    //   if (position >= pacingDurations[i] && position < pacingDurations[i + 1]) {
    //     final musicFile = pacingMusic[i];
    //     _audioManager.playOverlay(musicFile);
    //     debugPrint('Playing pacing music: $musicFile');
    //     break;
    //   }
    // }

    for (int i = 0; i < _timestamps.length; i++) {
      if (!_triggered[i] && _isInTimestampRange(position, _timestamps[i])) {
        _triggered[i] = true;
        if (widget.storyId == 1) {
          _audioManager.playOverlay('audio/${overlayType}_$i.mp3');
        }
        //i have to change the audio path later for all the audios and stories based on.
        else if (widget.storyId == 2) {
          _audioManager.playOverlay('audio/${overlayType}_$i.mp3');
        } else if (widget.storyId == 3) {
          _audioManager.playOverlay('audio/${overlayType}_$i.mp3');
        } else if (widget.storyId == 4) {
          _audioManager.playOverlay('audio/${overlayType}_$i.mp3');
        }
        debugPrint(hrPercentage.toString());
        debugPrint('Current HR: $_currentHR');
        debugPrint('Max HR: $_maxHR');
        debugPrint('Overlay Type: $overlayType');
        debugPrint(widget.zoneId.toString());
        debugPrint('Triggered overlay at index $i');
        debugPrint('Playing overlay: ${overlayType}_$i.mp3');
        debugPrint('Timestamp: ${_timestamps[i]}');
        debugPrint('Current Position: $position');
      }
    }
  }

  String _determineOverlayType(double hrPercentage) {
    if (widget.zoneId == 1) {
      if (hrPercentage >= 50 && hrPercentage < 60) {
        return 'A';
      } else if (hrPercentage < 50) {
        return 'A';
      } else if (hrPercentage >= 60) {
        return 'S';
      }
    } else if (widget.zoneId == 2) {
      if (hrPercentage >= 60 && hrPercentage < 70) {
        return 'A';
      } else if (hrPercentage < 60) {
        return 'A';
      } else if (hrPercentage >= 70) {
        return 'S';
      }
    } else if (widget.zoneId == 3) {
      if (hrPercentage >= 70 && hrPercentage < 80) {
        return 'A';
      } else if (hrPercentage < 70) {
        return 'A';
      } else if (hrPercentage >= 80) {
        return 'S';
      }
    }
    return 'A';
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
          maxheartRate: _maxHR ?? 0.0,
          zoneId: widget.zoneId,
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
