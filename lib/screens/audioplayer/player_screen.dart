import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:testingheartrate/services/audio_manager.dart';
import 'package:testingheartrate/services/socket_service.dart';
import 'package:testingheartrate/screens/completion/completion_screen.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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
  late final SocketService _socketService;
  bool _currentAudioStarted = false;
  int totalNudges = 0;

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

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

// Function to initialize the player
  Future<void> _initializePlayer() async {
    await _fetchMaxHR();
    _calculatePacingTimestamps();
    _pacingTriggered = List<bool>.filled(_pacingAudioFiles.length, false);
    _initializeTimestamps();
    _initializeSocketService();
    _initializeAudioListeners();
    _playCurrentAudio();
    _audioManager.audioPlayer.setVolume(0.4);
    debugPrint(
        'Main audio started: ${widget.audioData[_currentAudioIndex]['audioUrl']} at ${_formatDuration(Duration.zero)}');
  }

// Function to play the current audio
  void _playCurrentAudio() async {
    setState(() => _currentAudioStarted = false);
    if (_currentAudioIndex < widget.audioData.length) {
      try {
        await _audioManager.stop();
        _audioManager.stopPacing();
        _initializeTimestamps();
        final currentAudio = widget.audioData[_currentAudioIndex];
        await _audioManager.play(currentAudio['audioUrl']);
        await _startChallenge();
        debugPrint('Now playing: ${currentAudio['challengeName']}');
      } catch (e) {
        debugPrint('Error playing audio: $e');

        _handleAudioCompletion();
      }
    }
  }
// Function to calculate the total number of timestamps for completion.

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
    _audioManager.audioPlayer.onDurationChanged
        .listen((d) => setState(() => _totalDuration = d));
    _audioManager.audioPlayer.onPositionChanged.listen((position) {
      if (position > Duration.zero) {
        setState(() => _currentAudioStarted = true);
      }
      if (_currentPosition == Duration.zero && position > Duration.zero) {
        _checkForPacingAudio(position);
      }
      _handlePositionUpdate(position);
    });
    _audioManager.audioPlayer.onPlayerComplete.listen((event) {
      _handleAudioCompletion();
    });
  }

// Function to handle audio completion
  Future<void> _handleAudioCompletion() async {
    await _updateChallengeStatus();
    _currentAudioIndex++;
    if (_currentAudioIndex < widget.audioData.length) {
      setState(() {});
      _playCurrentAudio();
    } else {
      _audioManager.stop();
      _navigateToCompletionScreen();
    }
  }

// Function to navigate to the completion screen
  void _navigateToCompletionScreen() {
    final lastAudio = widget.audioData.last;
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

// Function to initialize socket service
  void _initializeSocketService() {
    _socketService = SocketService(
      onLoadingChanged: (isLoading) => debugPrint('Loading: $isLoading'),
      onErrorChanged: (error) => debugPrint('Error: $error'),
      onHeartRateChanged: _handleHeartRateUpdate,
    );
    _socketService.fetechtoken();
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

// Function to handle heart rate updates
  void _handleHeartRateUpdate(double? heartRate) async {
    if (heartRate == null) return;

    if (!_hasMaxHR) await _fetchMaxHR();

    setState(() => _currentHR = heartRate.toInt());

    if (_maxHR == null) return;

    final currentHRPercent = (_currentHR! / _maxHR!) * 100;
    final currentAudio = widget.audioData[_currentAudioIndex];
    final int zoneId = currentAudio['zoneId'];

    int lowerBound = 0, upperBound = 0;
    switch (zoneId) {
      case 1:
        lowerBound = 40;
        upperBound = 70;
        break;
      case 2:
        lowerBound = 50;
        upperBound = 80;
        break;
      case 3:
        lowerBound = 60;
        upperBound = 90;
        break;
    }

    if (currentHRPercent < lowerBound || currentHRPercent > upperBound) {
      if (_audioManager.isPlaying) {
        Future.delayed(const Duration(seconds: 10), () {
          if (currentHRPercent < lowerBound || currentHRPercent > upperBound) {
            _audioManager.pause();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'Music paused',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                backgroundColor: Colors.white.withOpacity(0.5),
                elevation: 0,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                width: 180,
              ),
            );
            debugPrint('Music paused due to HR out of range for 10 seconds');
          }
        });
      }
    } else {
      if (!_audioManager.isPlaying) {
        _audioManager.resume();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Music resumed',
              style: TextStyle(
                color: Colors.black,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            backgroundColor: Colors.white.withOpacity(0.5),
            elevation: 0,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            width: 180,
          ),
        );
        debugPrint('Music resumed');
      }
    }

    if (currentHRPercent >= 50 && currentHRPercent <= 80) {
      _checkForOverlayTrigger(_currentPosition);
    }
  }

// Function to fetch maximum heart rate
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
        debugPrint('Max HR: $_maxHR');
        setState(() {
          _maxHR = data['user']['maxhr']?.toDouble();
        });
        int zoneId = widget.audioData[_currentAudioIndex]['zoneId'];
        if (_maxHR != null) {
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
            '${roundedLower}.wav',
            '${roundedLower + 10}.wav',
            '${roundedLower + 20}.wav',
            '${roundedLower + 20}.wav',
            '${roundedLower + 10}.wav',
          ]);
        }
      } else {
        debugPrint('Failed to fetch maxHR: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching maxHR: $e');
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
                'audio/aradium/pacing/${_pacingAudioFiles[_currentPacingSegment]}';
            break;
          case 2:
            pacingAudioPath =
                'audio/smm/pacing/${_pacingAudioFiles[_currentPacingSegment]}';
            break;
          case 3:
            pacingAudioPath =
                'audio/luther/pacing/${_pacingAudioFiles[_currentPacingSegment]}';
            break;
          case 4:
            pacingAudioPath =
                'audio/dare/pacing/${_pacingAudioFiles[_currentPacingSegment]}';
            break;
          default:
            pacingAudioPath =
                'audio/pacing/${_pacingAudioFiles[_currentPacingSegment]}';
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
            pacingAudioPath = 'audio/aradium/pacing/${_pacingAudioFiles[i]}';
            break;
          case 2:
            pacingAudioPath = 'audio/smm/pacing/${_pacingAudioFiles[i]}';
            break;
          case 3:
            pacingAudioPath = 'audio/luther/pacing/${_pacingAudioFiles[i]}';
            break;
          case 4:
            pacingAudioPath = 'audio/dare/pacing/${_pacingAudioFiles[i]}';
            break;
          default:
            pacingAudioPath = 'audio/pacing/${_pacingAudioFiles[i]}';
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
                'audio/aradium/overlay/${challengeId}/${overlayType}_$i.wav';
            break;
          case 2:
            overlayPath =
                'audio/smm/overlay/${challengeId}/${overlayType}_$i.wav';
            break;
          case 3:
            overlayPath =
                'audio/luther/overlay/${challengeId}/${overlayType}_$i.wav';
            break;
          case 4:
            overlayPath =
                'audio/dare/overlay/${challengeId}/${overlayType}_$i.wav';
            break;
          default:
            overlayPath = 'audio/overlay/${challengeId}/${overlayType}_$i.wav';
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

// Function to start the challenge
  Future<void> _startChallenge() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    try {
      final currentAudio = widget.audioData[_currentAudioIndex];
      final response = await http.post(
        Uri.parse('https://authcheck.co/startchallenge'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'challengeId': currentAudio['id'],
          'zoneId': currentAudio['zoneId'],
        }),
      );
      debugPrint('Start challenge id: ${currentAudio['id']}');

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Challenge started',
              style: TextStyle(
                color: Colors.black,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            backgroundColor: Colors.white.withOpacity(0.5),
            elevation: 0,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            width: 180,
          ),
        );
        debugPrint('Challenge started successfully: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Start challenge error: $e');
    }
  }

// Function to update the challenge status
  Future<void> _updateChallengeStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    try {
      final currentAudio = widget.audioData[_currentAudioIndex];
      final response = await http.post(
        Uri.parse('https://authcheck.co/updatechallenge'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'challengeId': currentAudio['id'],
          'status': true,
        }),
      );
      debugPrint('Current audio id: ${currentAudio['id']}');

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Challenge updated',
              style: TextStyle(
                color: Colors.black,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            backgroundColor: Colors.white.withOpacity(0.5),
            elevation: 0,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            width: 180,
          ),
        );
        debugPrint('Challenge updated successfully: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Update challenge error: $e');
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${twoDigits(duration.inMinutes)}:${twoDigits(duration.inSeconds.remainder(60))}";
  }

// Function to toggle play/pause
  void _togglePlayPause() async {
    if (_audioManager.isPlaying) {
      await _audioManager.pause();
    } else {
      await _audioManager.resume();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
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
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Text(
                  'Workout left: ${_formatDuration(remaining > Duration.zero ? remaining : Duration.zero)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Thewitcher',
                    letterSpacing: 1.2,
                  ),
                ),
              ),
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
                  child: Center(
                    child: _currentAudioStarted
                        ? Icon(
                            _audioManager.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 80,
                          )
                        : const SizedBox(
                            width: 60,
                            height: 60,
                            child: CircularProgressIndicator(
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                              strokeWidth: 6,
                            ),
                          ),
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
                          // Enlarge thumb when near a timestamp
                          enabledThumbRadius: _timestamps.any((timestamp) =>
                                  (timestamp.inSeconds -
                                          _currentPosition.inSeconds)
                                      .abs() <=
                                  1)
                              ? 12.0
                              : 0.0,
                        ),
                        // trackShape: CustomSliderTrackShape(
                        //   timestamps: _timestamps,
                        //   totalDuration: _totalDuration,
                        // ),
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
