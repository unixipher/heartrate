import 'dart:async';
import 'package:flutter/material.dart';
import 'package:testingheartrate/services/audio_manager.dart';
import 'package:testingheartrate/screens/completion/completion_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:just_audio/just_audio.dart';
import 'package:testingheartrate/services/socket_service.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter/services.dart';

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
  int currentTrackNudges = 0;
  final FirebaseAnalytics analytics = FirebaseAnalytics.instance;

  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;

  int? _currentPlaylistIndex;
  late StreamSubscription<int?> _currentIndexSubscription;

  Duration get _globalPosition {
    int completedTracks = _currentAudioIndex;
    return Duration(minutes: completedTracks * 5) + _currentPosition;
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

  // --- Lock state ---
  bool _isLocked = false;
  double? _previousBrightness;
  double _unlockProgress = 0.0;
  Timer? _unlockTimer;

  @override
  void initState() {
    analytics.setAnalyticsCollectionEnabled(true);
    super.initState();
    _initializePlayer();
    _initializeSocketService();
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

  // --- Lock/Unlock logic ---
  Future<void> _lockScreen() async {
    try {
      _previousBrightness = await ScreenBrightness().current;
      await ScreenBrightness().setScreenBrightness(0.01);
    } catch (_) {}
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    setState(() {
      _isLocked = true;
    });
  }

  Future<void> _unlockScreen() async {
    if (_previousBrightness != null) {
      try {
        await ScreenBrightness().setScreenBrightness(_previousBrightness!);
      } catch (_) {}
    }
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    setState(() {
      _isLocked = false;
      _unlockProgress = 0.0;
    });
  }

  Future<bool> _onWillPop() async {
    return !_isLocked;
  }

  void _startUnlockHold() {
    _unlockTimer?.cancel();
    _unlockProgress = 0.0;
    _unlockTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      setState(() {
        _unlockProgress += 0.01;
        if (_unlockProgress >= 1.0) {
          _unlockTimer?.cancel();
          _unlockScreen();
        }
      });
    });
  }

  void _cancelUnlockHold() {
    _unlockTimer?.cancel();
    setState(() {
      _unlockProgress = 0.0;
    });
  }

  // Function to initialize the player
  Future<void> _initializePlayer() async {
    try {
      await _audioManager.reset();
      debugPrint('=== INITIALIZING PLAYLIST ===');
      for (int i = 0; i < widget.audioData.length; i++) {
        final audio = widget.audioData[i];
        debugPrint(
            'Audio $i: ${audio['challengeName']} - URL: ${audio['audioUrl']}');
      }

      await _fetchMaxHR();
      _calculatePacingTimestamps();
      _pacingTriggered = List<bool>.filled(_pacingAudioFiles.length, false);

      // Initialize playlist instead of single audio
      await _audioManager.initializePlaylist(widget.audioData);
      _initializeAudioListeners();

      // Start playing from first track
      await _audioManager.playFromIndex(0);
      await _audioManager.setVolume(1);

      _initializeTimestamps();
      debugPrint('Playlist initialized and started');
    } catch (e) {
      debugPrint('Initialization error: $e');
      _showCenterNotification('Initialization failed');
      Future.delayed(const Duration(seconds: 2), _handleAudioCompletion);
    }
  }

  // --- SOCKET LOGIC START ---
  void _initializeSocketService() {
    _socketService = SocketService(
      onLoadingChanged: (isLoading) => debugPrint('Socket loading: $isLoading'),
      onErrorChanged: (error) => debugPrint('Socket error: $error'),
      onHeartRateChanged: _handleHeartRateUpdate,
    );
    _socketService.fetechtoken();
  }

  void _handleHeartRateUpdate(double? heartRate) async {
    if (heartRate == null) return;

    if (!_hasMaxHR) await _fetchMaxHR();

    setState(() => _currentHR = heartRate.toInt());

    if (_maxHR == null) return;

    final currentheartrate = _currentHR;
    final currentAudio = widget.audioData[_currentAudioIndex];
    final int zoneId = currentAudio['zoneId'];

    int lowerBound = 0, upperBound = 0;
    switch (zoneId) {
      case 1:
        lowerBound = (72 + (_maxHR! - 72) * 0.35).toInt();
        upperBound = (72 + (_maxHR! - 72) * 0.75).toInt();
        break;
      case 2:
        lowerBound = (72 + (_maxHR! - 72) * 0.45).toInt();
        upperBound = (72 + (_maxHR! - 72) * 0.85).toInt();
        break;
      case 3:
        lowerBound = (72 + (_maxHR! - 72) * 0.55).toInt();
        upperBound = (72 + (_maxHR! - 72) * 0.95).toInt();
        break;
    }

    if (currentheartrate != null &&
        (currentheartrate < lowerBound || currentheartrate > upperBound)) {
      if (_audioManager.isPlaying) {
        Future.delayed(const Duration(seconds: 10), () {
          if (currentheartrate < lowerBound) {
            _audioManager.pause();
            _playlowerOutOfRangeAudio();
            _showCenterNotification('Music paused');
            debugPrint('Playing out of range audio due to low HR');
          }
          if (currentheartrate > upperBound) {
            _audioManager.pause();
            _playupperOutOfRangeAudio();
            _showCenterNotification('Music paused');
            debugPrint('Playing out of range audio due to high HR');
          }
        });
      }
    } else {
      if (!_audioManager.isPlaying) {
        _audioManager.resume();
        _audioManager.resumePacing();
        debugPrint('Music resumed');
      }
    }
  }
  // --- SOCKET LOGIC END ---

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
      debugPrint('Now playing: ${currentAudio['challengeName']}');
    } catch (e) {
      debugPrint('Error playing audio: $e');
      Future.delayed(Duration(seconds: 2), _handleAudioCompletion);
    }
  }

  void _playlowerOutOfRangeAudio() {
    String outOfRangeAudioPath = 'assets/audio/stop/slow.wav';
    _audioManager.playOverlay(outOfRangeAudioPath, volume: 2.0);
    debugPrint('Playing out of range audio: $outOfRangeAudioPath');
  }

  void _playupperOutOfRangeAudio() {
    String outOfRangeAudioPath = 'assets/audio/stop/fast.wav';
    _audioManager.playOverlay(outOfRangeAudioPath, volume: 2.0);
    debugPrint('Playing out of range audio: $outOfRangeAudioPath');
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

    _currentIndexSubscription =
        _audioManager.currentIndexStream.listen((index) {
      if (index != null && index != _currentPlaylistIndex) {
        setState(() {
          _currentAudioIndex = index;
          _currentPlaylistIndex = index;
        });
        _onTrackChanged();
      }
    });

    _playerStateSubscription = _audioManager.playerStateStream.listen((state) {
      debugPrint('Player state: ${state.processingState}');
      if (state.processingState == ProcessingState.completed) {
        if (_currentAudioIndex + 1 < widget.audioData.length) {
          debugPrint('Moving to next track automatically');
        } else {
          _navigateToCompletionScreen();
        }
      }
      setState(() {});
    });
  }

  void _onTrackChanged() {
    debugPrint('Track changed to index: $_currentAudioIndex');
    _initializeTimestamps();
    _pacingTriggered = List.filled(_pacingAudioFiles.length, false);
    _currentAudioStarted = false;
    currentTrackNudges = 0;
  }

  Future<void> _handleAudioCompletion() async {
    if (_currentAudioIndex + 1 >= widget.audioData.length) {
      _navigateToCompletionScreen();
    }
  }

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

  String _determineOverlayType(
      double hr, int lowerbound, int zoneId, int upperbound) {
    if (zoneId == 1) {
      if (hr >= lowerbound && hr < upperbound) {
        return 'A';
      } else if (hr < lowerbound) {
        return 'A';
      } else if (hr >= upperbound) {
        return 'S';
      }
    } else if (zoneId == 2) {
      if (hr >= lowerbound && hr < upperbound) {
        return 'A';
      } else if (hr < lowerbound) {
        return 'A';
      } else if (hr >= upperbound) {
        return 'S';
      }
    } else if (zoneId == 3) {
      if (hr >= lowerbound && hr < upperbound) {
        return 'A';
      } else if (hr < lowerbound) {
        return 'A';
      } else if (hr >= upperbound) {
        return 'S';
      }
    }
    return 'A';
  }

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

  void _handlePositionUpdate(Duration position) {
    setState(() => _currentPosition = position);
    _checkForOverlayTrigger(position);
    _checkForPacingAudio(position);
  }

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
        String pacingAudioPath =
            'assets/audio/pacing/${_pacingAudioFiles[_currentPacingSegment]}';
        _audioManager.playPacingLoop(pacingAudioPath);
        debugPrint('Playing pacing audio: $pacingAudioPath');
      }
    }
  }

  void _checkForOverlayTrigger(Duration position) {
    final currentAudio = widget.audioData[_currentAudioIndex];
    final int storyId = currentAudio['storyId'];
    String overlayType = 'A';

    if (_currentHR != null && _maxHR != null) {
      final int zoneId = currentAudio['zoneId'];
      final double hr = _currentHR!.toDouble();
      int lowerbound = 0;
      int upperbound = 0;
      if (zoneId == 1) {
        lowerbound = (72 + (_maxHR! - 72) * 0.5).toInt();
        upperbound = (72 + (_maxHR! - 72) * 0.6).toInt();
      } else if (zoneId == 2) {
        lowerbound = (72 + (_maxHR! - 72) * 0.6).toInt();
        upperbound = (72 + (_maxHR! - 72) * 0.7).toInt();
      } else if (zoneId == 3) {
        lowerbound = (72 + (_maxHR! - 72) * 0.7).toInt();
        upperbound = (72 + (_maxHR! - 72) * 0.8).toInt();
      }
      overlayType = _determineOverlayType(hr, lowerbound, zoneId, upperbound);
    }

    for (int i = 0; i < _timestamps.length; i++) {
      if (!_triggered[i] && _isInTimestampRange(position, _timestamps[i])) {
        _triggered[i] = true;
        totalNudges++;
        currentTrackNudges++;
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
          _audioManager.playOverlay(overlayPath, volume: 2.0);
          debugPrint('Playing overlay: $overlayPath');
        }
      }
    }
  }

  bool _isInTimestampRange(Duration position, Duration target) {
    final positionMs = position.inMilliseconds;
    final targetMs = target.inMilliseconds;
    return (positionMs >= targetMs - 1000 && positionMs <= targetMs + 1000);
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${twoDigits(duration.inMinutes)}:${twoDigits(duration.inSeconds.remainder(60))}";
  }

  void _togglePlayPause() async {
    if (_audioManager.isPlaying) {
      await _audioManager.pause();
      _startBlinking();
    } else {
      if (!_audioManager.isPlaying) {
        _audioManager.resume();
        _audioManager.resumePacing();
        debugPrint('Music resumed');
      }
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
    _currentIndexSubscription.cancel();
    _unlockTimer?.cancel();
    try {
      _socketService.dispose();
    } catch (_) {}
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

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
            onPressed: () {
              if (!_isLocked) Navigator.pop(context);
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
          actions: [
            if (!_isLocked)
              IconButton(
                icon: const Icon(Icons.lock_outline, color: Colors.white),
                tooltip: 'Lock',
                onPressed: _lockScreen,
              ),
          ],
        ),
        body: Stack(
          children: [
            if (!_isLocked) ...[
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
                                                child:
                                                    CircularProgressIndicator(
                                                  valueColor:
                                                      AlwaysStoppedAnimation<
                                                          Color>(Colors.white),
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
            ] else
              // LOCKED UI
              Container(
                color: Colors.black,
                alignment: Alignment.center,
                child: GestureDetector(
                  onLongPressStart: (_) => _startUnlockHold(),
                  onLongPressEnd: (_) => _cancelUnlockHold(),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 120,
                        height: 120,
                        child: CircularProgressIndicator(
                          value: _unlockProgress,
                          strokeWidth: 8,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.purple),
                          backgroundColor: Colors.white12,
                        ),
                      ),
                      Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          color: Colors.purple,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.purple.withOpacity(0.4),
                              blurRadius: 20,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(Icons.lock_open,
                              color: Colors.white, size: 48),
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
