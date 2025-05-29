import 'dart:async';
import 'package:flutter/material.dart';
import 'package:testingheartrate/services/audio_manager.dart';
import 'package:testingheartrate/screens/completion/completion_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:just_audio/just_audio.dart';

class PlayerScreen extends StatefulWidget {
  final List<Map<String, dynamic>> audioData;
  final int challengeCount;
  final int playingChallengeCount;

  const PlayerScreen({
    super.key,
    required this.challengeCount,
    required this.audioData,
    required this.playingChallengeCount,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final AudioManager _audioManager = AudioManager();
  bool _currentAudioStarted = false;
  int totalNudges = 0;
  final FirebaseAnalytics analytics = FirebaseAnalytics.instance;

  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;

  Duration get _globalPosition {
    return Duration(minutes: _currentAudioIndex * 5) + _currentPosition;
  }

  Duration get _globalTotalDuration {
    return Duration(minutes: widget.audioData.length * 5);
  }

  int? _currentHR;
  double? _maxHR;
  List<Duration> _timestamps = [];
  List<bool> _triggered = [];
  bool _hasMaxHR = false;
  final List<String> _pacingAudioFiles = [];
  List<Duration> _pacingTimestamps = [];
  List<bool> _pacingTriggered = [];
  int _currentAudioIndex = 0;
  int _currentPacingSegment = -1;
  List<Duration> _pacingSegmentEnds = [];

  // Stream subscriptions
  late StreamSubscription<Duration> _positionSubscription;
  late StreamSubscription<Duration?> _durationSubscription;
  late StreamSubscription<PlayerState> _playerStateSubscription;

  // --- Notification state ---
  String? _centerNotification;
  Timer? _notificationTimer;

  // --- Blinking state ---
  bool _isPausedBlink = false;
  Timer? _blinkTimer;

  @override
  void initState() {
    analytics.setAnalyticsCollectionEnabled(true);
    super.initState();
    _initializePlayer();
  }

  // --- Notification logic ---
  void _showCenterNotification(String message, {int seconds = 2}) {
    setState(() {
      _centerNotification = message;
    });
    _notificationTimer?.cancel();
    _notificationTimer = Timer(Duration(seconds: seconds), () {
      if (mounted) {
        setState(() {
          _centerNotification = null;
        });
      }
    });
  }

  // --- Blinking logic ---
  void _startBlinking() {
    _blinkTimer?.cancel();
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      if (mounted) {
        setState(() {
          _isPausedBlink = !_isPausedBlink;
        });
      }
    });
  }

  void _stopBlinking() {
    _blinkTimer?.cancel();
    setState(() {
      _isPausedBlink = false;
    });
  }

  // Function to initialize the player
  Future<void> _initializePlayer() async {
    try {
      debugPrint('=== AUDIO DATA DEBUG ===');
      for (int i = 0; i < widget.audioData.length; i++) {
        final audio = widget.audioData[i];
        debugPrint(
            'Audio $i: ${audio['challengeName']} - URL: ${audio['audioUrl']}');
      }
      debugPrint('=== END AUDIO DATA DEBUG ===');
      await _fetchMaxHR();
      _calculatePacingTimestamps();
      _pacingTriggered = List<bool>.filled(_pacingAudioFiles.length, false);
      _initializeTimestamps();
      _initializeAudioListeners();
      await _playCurrentAudio();
      await _audioManager.setVolume(0.4);
      debugPrint(
          'Main audio started: ${widget.audioData[_currentAudioIndex]['audioUrl']} at ${_formatDuration(Duration.zero)}');
    } catch (e) {
      debugPrint('Initialization error: $e');
      _showCenterNotification('Initialization failed');
      Future.delayed(const Duration(seconds: 2), _handleAudioCompletion);
    }
  }

// Function to play the current audio
  Future<void> _playCurrentAudio() async {
    if (_currentAudioIndex >= widget.audioData.length) {
      _navigateToCompletionScreen();
      return;
    }

    setState(() => _currentAudioStarted = false);
    final currentAudio = widget.audioData[_currentAudioIndex];
    final audioUrl = currentAudio['audioUrl']?.toString() ?? '';

    try {
      // Clear previous state
      await _audioManager.stop();
      await _audioManager.stopPacing();

      // Reset tracking states
      _initializeTimestamps();
      _pacingTriggered = List.filled(_pacingAudioFiles.length, false);
      _currentAudioStarted = false;

      // Play new audio
      await _audioManager.play(currentAudio['audioUrl']);
      // await _startChallenge();
      debugPrint('Now playing: ${currentAudio['challengeName']}');
    } catch (e) {
      debugPrint('Error playing audio: $e');
      // Handle error then proceed to next
      Future.delayed(Duration(seconds: 2), _handleAudioCompletion);
    }
  }

  // Function to calculate pacing timestamps
  void _calculatePacingTimestamps() {
    final int numberOfAudios = widget.audioData.length;
    final int totalDurationMinutes = numberOfAudios * 5;
    final int segmentDurationMinutes = totalDurationMinutes ~/ 5;
    _pacingTimestamps = List.generate(
      5,
      (index) => Duration(minutes: index * segmentDurationMinutes),
    );
    _pacingSegmentEnds = List.generate(
      5,
      (index) => Duration(minutes: (index + 1) * segmentDurationMinutes),
    );
    debugPrint('Pacing timestamps: $_pacingTimestamps');
  }

// Function to initialize audio listeners
  void _initializeAudioListeners() {
    _positionSubscription = _audioManager.positionStream.listen((position) {
      if (position > Duration.zero) {
        setState(() {
          _currentPosition = position;
          _currentAudioStarted = true;
        });
        _handlePositionUpdate(position);
      }
    });

    _durationSubscription = _audioManager.durationStream.listen((duration) {
      if (duration != null) {
        setState(() => _totalDuration = duration);
      }
    });

    _playerStateSubscription = _audioManager.playerStateStream.listen((state) {
      debugPrint('Player state: ${state.processingState}');
      if (state.processingState == ProcessingState.completed &&
          _audioManager.isPlaying) {
        debugPrint('Audio completed');
        _handleAudioCompletion();
      }
      setState(() {});
    });
  }

  Future<void> _handleAudioCompletion() async {
    if (_currentAudioIndex + 1 < widget.audioData.length) {
      _currentAudioIndex++;
      await _playCurrentAudio();
    } else {
      _audioManager.stop();
      _navigateToCompletionScreen();
    }
  }

  // Function to navigate to the completion screen
  void _navigateToCompletionScreen() {
    final lastAudio = widget.audioData.last;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => CompletionScreen(
            storyName: lastAudio['challengeName'],
            backgroundImage: lastAudio['image'],
            storyId: lastAudio['id'],
            maxheartRate: _maxHR ?? 0.0,
            zoneId: lastAudio['zoneId'],
            timestampcount: totalNudges,
            audioData: widget.audioData,
            challengeCount: widget.challengeCount,
            playingChallengeCount: widget.playingChallengeCount,
          ),
        ),
      );
    });
  }

  // Function to initialize timestamps main method
  void _initializeTimestamps() {
    final currentAudio = widget.audioData[_currentAudioIndex];
    int adjustedIndexId = currentAudio['indexid'];

    if (adjustedIndexId >= 1) {
      adjustedIndexId = ((adjustedIndexId - 1) % 5) + 1;
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

  // Function to determine overlay type based on heart rate percentage and zone ID
  String _determineOverlayType(double hrPercentage, int zoneId) {
    if (zoneId == 1) {
      if (hrPercentage >= 50 && hrPercentage < 60) {
        return 'A';
      } else if (hrPercentage < 50) {
        return 'A';
      } else if (hrPercentage >= 60) {
        return 'S';
      }
    } else if (zoneId == 2) {
      if (hrPercentage >= 60 && hrPercentage < 70) {
        return 'A';
      } else if (hrPercentage < 60) {
        return 'A';
      } else if (hrPercentage >= 70) {
        return 'S';
      }
    } else if (zoneId == 3) {
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


  // Function to fetch maximum heart rate
  Future<void> _fetchMaxHR() async {
    final prefs = await SharedPreferences.getInstance();
    final maxHR = prefs.getInt('maxhr')?.toDouble();

    if (maxHR != null) {
      setState(() {
        _maxHR = maxHR;
      });
      int zoneId = widget.audioData[_currentAudioIndex]['zoneId'];
      double lowerbound = 0.0;
      if (zoneId == 1) {
        lowerbound = (72 + (_maxHR! - 72) * 0.5);
      }
      if (zoneId == 2) {
        lowerbound = (72 + (_maxHR! - 72) * 0.6);
      }
      if (zoneId == 3) {
        lowerbound = (72 + (_maxHR! - 72) * 0.7);
      }
      int roundedLower = roundToNearest10(lowerbound);
      _pacingAudioFiles.addAll([
        '${roundedLower}.mp3',
        '${roundedLower + 10}.mp3',
        '${roundedLower + 20}.mp3',
        '${roundedLower + 20}.mp3',
        '${roundedLower + 10}.mp3',
      ]);
    } else {
      debugPrint('Failed to fetch maxHR from SharedPreferences');
    }
    setState(() {
      _hasMaxHR = true;
    });
  }

  int roundToNearest10(double value) {
    return (value / 10).round() * 10;
  }

  // Function to handle position updates
  void _handlePositionUpdate(Duration position) {
    setState(() => _currentPosition = position);
    _checkForOverlayTrigger(position);
    _checkForPacingAudio(position);
  }

  // Function to check for pacing audio
  void _checkForPacingAudio(Duration position) {
    final int previousAudiosDuration = _currentAudioIndex * 5;
    final Duration globalPosition =
        Duration(minutes: previousAudiosDuration) + position;
    int newSegment = -1;
    if (!_currentAudioStarted) return;
    for (int i = 0; i < _pacingTimestamps.length; i++) {
      if (globalPosition >= _pacingTimestamps[i] &&
          globalPosition < _pacingSegmentEnds[i]) {
        newSegment = i;
        break;
      }
    }
    if (newSegment != _currentPacingSegment) {
      _audioManager.stopPacing();
      _currentPacingSegment = newSegment;

      if (_currentPacingSegment != -1 &&
          _currentPacingSegment < _pacingAudioFiles.length) {
        final currentAudio = widget.audioData[_currentAudioIndex];
        final int storyId = currentAudio['storyId'];
        String pacingAudioPath;
        switch (storyId) {
          case 1:
            pacingAudioPath =
                'assets/audio/aradium/pacing/${_pacingAudioFiles[_currentPacingSegment]}';
            break;
          case 2:
            pacingAudioPath =
                'assets/audio/smm/pacing/${_pacingAudioFiles[_currentPacingSegment]}';
            break;
          case 3:
            pacingAudioPath =
                'assets/audio/luther/pacing/${_pacingAudioFiles[_currentPacingSegment]}';
            break;
          case 4:
            pacingAudioPath =
                'assets/audio/dare/pacing/${_pacingAudioFiles[_currentPacingSegment]}';
            break;
          default:
            pacingAudioPath =
                'assets/audio/pacing/${_pacingAudioFiles[_currentPacingSegment]}';
        }
        _audioManager.playPacingLoop(pacingAudioPath);
        debugPrint('Playing pacing audio: $pacingAudioPath');
      }
    }

    for (int i = 0; i < _pacingTimestamps.length; i++) {
      if (!_pacingTriggered[i] &&
          _isInTimestampRange(globalPosition, _pacingTimestamps[i])) {
        _pacingTriggered[i] = true;
        final currentAudio = widget.audioData[_currentAudioIndex];
        final int storyId = currentAudio['storyId'];
        String pacingAudioPath;
        switch (storyId) {
          case 1:
            pacingAudioPath =
                'assets/audio/aradium/pacing/${_pacingAudioFiles[i]}';
            break;
          case 2:
            pacingAudioPath = 'assets/audio/smm/pacing/${_pacingAudioFiles[i]}';
            break;
          case 3:
            pacingAudioPath =
                'assets/audio/luther/pacing/${_pacingAudioFiles[i]}';
            break;
          case 4:
            pacingAudioPath =
                'assets/audio/dare/pacing/${_pacingAudioFiles[i]}';
            break;
          default:
            pacingAudioPath = 'assets/audio/pacing/${_pacingAudioFiles[i]}';
        }
        _audioManager.playPacing(pacingAudioPath);
        debugPrint(
            'Playing pacing audio: $pacingAudioPath at ${_formatDuration(globalPosition)}');
      }
    }
  }

  // Function to check for overlay trigger
  void _checkForOverlayTrigger(Duration position) {
    final currentAudio = widget.audioData[_currentAudioIndex];
    final int storyId = currentAudio['storyId'];
    String overlayType = 'A';

    if (_currentHR != null && _maxHR != null) {
      final int zoneId = currentAudio['zoneId'];
      final double hrPercentage = (_currentHR! / _maxHR!) * 100;
      overlayType = _determineOverlayType(hrPercentage, zoneId);
    }

    for (int i = 0; i < _timestamps.length; i++) {
      if (!_triggered[i] && _isInTimestampRange(position, _timestamps[i])) {
        _triggered[i] = true;
        totalNudges++;
        String overlayPath;
        final filteredChallenges = widget.audioData;
        final challengeId =
            filteredChallenges.indexWhere((c) => c['id'] == currentAudio['id']);
        switch (storyId) {
          case 1:
            overlayPath =
                'assets/audio/aradium/overlay/${challengeId}/${overlayType}_$i.wav';
            break;
          case 2:
            overlayPath =
                'assets/audio/smm/overlay/${challengeId}/${overlayType}_$i.wav';
            break;
          case 3:
            overlayPath =
                'assets/audio/luther/overlay/${challengeId}/${overlayType}_$i.wav';
            break;
          case 4:
            overlayPath =
                'assets/audio/dare/overlay/${challengeId}/${overlayType}_$i.wav';
            break;
          default:
            overlayPath =
                'assets/audio/overlay/${challengeId}/${overlayType}_$i.wav';
        }
        if (storyId == 1 || storyId == 2 || storyId == 3 || storyId == 4) {
          _audioManager.playOverlay(overlayPath);
          debugPrint('Playing overlay: $overlayPath');
        }
      }
    }
  }

  // Function to check if the current position is within a timestamp range
  bool _isInTimestampRange(Duration position, Duration target) {
    final positionMs = position.inMilliseconds;
    final targetMs = target.inMilliseconds;
    return (positionMs >= targetMs - 1000 && positionMs <= targetMs + 1000);
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${twoDigits(duration.inMinutes)}:${twoDigits(duration.inSeconds.remainder(60))}";
  }

  // Function to toggle play/pause
  void _togglePlayPause() async {
    if (_audioManager.isPlaying) {
      await _audioManager.pause();
      _startBlinking();
    } else {
      await _audioManager.resume();
      _stopBlinking();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _notificationTimer?.cancel();
    _blinkTimer?.cancel();
    _audioManager.dispose();
    _positionSubscription.cancel();
    _durationSubscription.cancel();
    _playerStateSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.audioData.isEmpty ||
        _currentAudioIndex >= widget.audioData.length) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'No audio data available.',
            style: TextStyle(color: Colors.transparent, fontSize: 18),
          ),
        ),
      );
    }
    final currentAudio = widget.audioData[_currentAudioIndex];
    final Duration remaining = _globalTotalDuration - _globalPosition;

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
        title: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              currentAudio['challengeName'],
              style: const TextStyle(
                fontFamily: 'Thewitcher',
                fontSize: 24,
                letterSpacing: 2,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.clip,
            ),
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage(currentAudio['image']),
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
                child: SizedBox(
                  width: 140,
                  height: 140,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 220,
                        height: 220,
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
                        child: Center(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: _centerNotification != null
                                ? Text(
                                    _centerNotification!,
                                    key: const ValueKey('notif'),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Thewitcher',
                                      letterSpacing: 2,
                                    ),
                                    textAlign: TextAlign.center,
                                  )
                                : (_audioManager.isPlaying
                                    ? (_currentAudioStarted
                                        ? Text(
                                            _formatDuration(remaining),
                                            key: const ValueKey('timer'),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 40,
                                              fontWeight: FontWeight.normal,
                                              fontFamily: 'Thewitcher',
                                              letterSpacing: 2,
                                            ),
                                          )
                                        : const SizedBox(
                                            key: ValueKey('loading'),
                                            width: 60,
                                            height: 60,
                                            child: CircularProgressIndicator(
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                      Colors.white),
                                              strokeWidth: 6,
                                            ),
                                          ))
                                    : (_isPausedBlink
                                        ? Icon(
                                            Icons.play_arrow_rounded,
                                            key: const ValueKey('playicon'),
                                            color: Colors.white,
                                            size: 60,
                                          )
                                        : Text(
                                            _formatDuration(remaining),
                                            key: const ValueKey('timer'),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 40,
                                              fontWeight: FontWeight.normal,
                                              fontFamily: 'Thewitcher',
                                              letterSpacing: 2,
                                            ),
                                          ))),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(flex: 2),
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
                        overlayColor: Colors.purple.withOpacity(0.2),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 28.0,
                        ),
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
              const Spacer(flex: 1),
            ],
          ),
        ],
      ),
    );
  }
}
