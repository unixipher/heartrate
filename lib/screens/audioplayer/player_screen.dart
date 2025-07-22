import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:testingheartrate/services/audio_manager.dart';
import 'package:testingheartrate/screens/completion/completion_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:just_audio/just_audio.dart';
import 'package:testingheartrate/services/socket_service.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter/services.dart';
import 'package:testingheartrate/services/gps_service.dart';
import 'package:cm_pedometer/cm_pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

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
  SocketService? _socketService;
  bool _currentAudioStarted = false;
  int totalNudges = 0;
  int currentTrackNudges = 0;
  final FirebaseAnalytics analytics = FirebaseAnalytics.instance;

  // Scoring system variables
  int _currentScore = 0;
  int _consecutiveChallengeCompletions = 0;
  List<int> _challengeScores = []; // Track score for each challenge

  // --- START: Detour Feature Variables ---
  int _outOfZoneCount = 0;
  bool _isInDetour = false;
  Duration _detourStartPosition = Duration.zero;
  List<Duration> _detourTimestamps = [];
  List<bool> _detourTriggered = [];
  int _currentDetourIndex = -1;
  Timer? _detourTimer;
  Duration _detourTriggerPosition = Duration.zero;
  int _detourElapsedSeconds = 0;
  // --- END: Detour Feature Variables ---

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
  double? _currentSpeedKmph;
  StreamSubscription? _dataSubscription;
  List<Duration> _timestamps = [];
  List<bool> _triggered = [];
  bool _hasMaxHR = false;
  final List<String> _pacingAudioFiles = [];
  List<Duration> _pacingTimestamps = [];
  int _currentAudioIndex = 0;
  int _currentPacingSegment = -1;
  List<Duration> _pacingSegmentEnds = [];
  bool _useSocket = false;

  late StreamSubscription<Duration> _positionSubscription;
  late StreamSubscription<Duration?> _durationSubscription;
  late StreamSubscription<PlayerState> _playerStateSubscription;

  String? _centerNotification;
  Timer? _notificationTimer;

  bool _isPausedBlink = false;
  Timer? _blinkTimer;

  bool _isLocked = false;
  double? _previousBrightness;
  double _unlockProgress = 0.0;
  Timer? _unlockTimer;

  // Intro audio state
  bool _isPlayingIntro = false;
  bool _introCompleted = false;
  Duration _introPosition = Duration.zero;
  Duration _introTotalDuration = Duration.zero;
  late StreamSubscription<Duration> _introPositionSubscription;
  late StreamSubscription<Duration?> _introDurationSubscription;
  late StreamSubscription<PlayerState> _introPlayerStateSubscription;

  // Pedometer variables
  late Stream<CMPedometerData> _pedometerStream;
  final ValueNotifier<CMPedometerData?> _pedometerData = ValueNotifier(null);

  @override
  void initState() {
    analytics.setAnalyticsCollectionEnabled(true);
    super.initState();
    debugPrint('=== INITIALIZING SCORING SYSTEM ===');
    debugPrint('Initial Score: $_currentScore');
    debugPrint(
      'Initial Challenge Completions: $_consecutiveChallengeCompletions',
    );
    debugPrint('===================================');
    _initializePlayer();
    _initializeService();
    _initializeDetourTimestamps(); // Initialize detour timestamps

    // Initialize pedometer for iOS
    if (Platform.isIOS) {
      _initPedometer();
    }
  }

  // Initialize detour timestamps
  void _initializeDetourTimestamps() {
    _detourTimestamps = [
      const Duration(minutes: 4, seconds: 35), // dstart
      const Duration(minutes: 4, seconds: 55), // d1
      const Duration(minutes: 5, seconds: 15), // d2
      const Duration(minutes: 5, seconds: 35), // d3
      const Duration(minutes: 5, seconds: 55), // d4
      const Duration(minutes: 6, seconds: 15), // d5
      const Duration(minutes: 6, seconds: 35), // d6
      const Duration(minutes: 6, seconds: 55), // d7
      const Duration(minutes: 7, seconds: 15), // d8
      const Duration(minutes: 7, seconds: 35), // dstop
    ];
    _detourTriggered = List<bool>.filled(_detourTimestamps.length, false);
  }

  Future<void> _initPedometer() async {
    try {
      // Request pedometer permission
      bool granted = await _checkPedometerPermission();
      if (!granted) {
        debugPrint('Pedometer permission not granted');
        return;
      }

      // Initialize pedometer stream
      _pedometerStream = CMPedometer.stepCounterFirstStream();
      _pedometerStream
          .listen(_handlePedometerUpdate)
          .onError(_handlePedometerError);
    } catch (e) {
      debugPrint('Error initializing pedometer: $e');
    }
  }

  Future<bool> _checkPedometerPermission() async {
    bool granted = await Permission.sensors.isGranted;
    if (!granted) {
      granted = await Permission.sensors.request() == PermissionStatus.granted;
    }
    return granted;
  }

  void _handlePedometerUpdate(CMPedometerData data) {
    debugPrint('Pedometer data: ${data.numberOfSteps} steps');
    _pedometerData.value = data;

    // Calculate speed from current pace
    double? currentPace = data.currentPace; // seconds per meter
    if (currentPace != null && currentPace > 0) {
      double speedMs = 1 / currentPace; // meters per second
      double speedKmph = speedMs * 3.6; // km/h
      _handleSpeedUpdate(speedKmph);

      // Send speed data to socket server
      if (_socketService != null) {
        _socketService!.sendSpeed(speedKmph);
        debugPrint('Sent Pedometer speed data to server: $speedKmph km/h');
      }
    }
  }

  void _handlePedometerError(error) {
    debugPrint('Pedometer error: $error');
    _pedometerData.value = null;
  }

  String get _activeServiceLabel {
    if (_useSocket) return "Apple Watch (Socket)";
    if (Platform.isAndroid) return "GPS";
    if (Platform.isIOS) return "Pedometer + Socket";
    return "Unknown";
  }

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

  Future<void> _initializePlayer() async {
    try {
      await _audioManager.reset();
      debugPrint('=== INITIALIZING PLAYLIST ===');
      for (int i = 0; i < widget.audioData.length; i++) {
        final audio = widget.audioData[i];
        debugPrint(
          'Audio $i: ${audio['challengeName']} - URL: ${audio['audioUrl']}',
        );
      }

      await _fetchMaxHR();
      _calculatePacingTimestamps();

      await _audioManager.initializePlaylist(widget.audioData);
      _initializeAudioListeners();
      _initializeIntroAudioListeners();

      await _playIntroAudio();

      _initializeTimestamps();
      debugPrint('Playlist initialized and intro started');
    } catch (e) {
      debugPrint('Initialization error: $e');
      _showCenterNotification('Initialization failed');
      Future.delayed(const Duration(seconds: 2), _handleAudioCompletion);
    }
  }

  Future<void> _playIntroAudio() async {
    try {
      setState(() {
        _isPlayingIntro = true;
        _introCompleted = false;
      });

      final currentAudio = widget.audioData[_currentAudioIndex];
      final int storyId = currentAudio['storyId'];

      String introAudioPath;
      switch (storyId) {
        case 1:
          introAudioPath = 'assets/audio/aradium/intro.wav';
          break;
        case 2:
          introAudioPath = 'assets/audio/smm/intro.wav';
          break;
        case 3:
          introAudioPath = 'assets/audio/luther/intro.wav';
          break;
        case 4:
          introAudioPath = 'assets/audio/dare/intro.wav';
          break;
        default:
          introAudioPath = 'assets/audio/aradium/intro.wav';
      }

      await _audioManager.playIntro(introAudioPath, volume: 1.0);
      debugPrint('Playing intro audio: $introAudioPath');
    } catch (e) {
      debugPrint('Error playing intro befell: $e');
      _startMainAudio();
    }
  }

  void _initializeIntroAudioListeners() {
    _introPositionSubscription =
        _audioManager.introPositionStream.listen((position) {
      setState(() {
        _introPosition = position;
      });
    });

    _introDurationSubscription =
        _audioManager.introDurationStream.listen((duration) {
      if (duration != null) {
        setState(() => _introTotalDuration = duration);
      }
    });

    _introPlayerStateSubscription =
        _audioManager.introPlayerStateStream.listen((state) {
      debugPrint('Intro player state: ${state.processingState}');
      if (state.processingState == ProcessingState.completed) {
        _onIntroCompleted();
      }
      setState(() {});
    });
  }

  void _onIntroCompleted() async {
    debugPrint('Intro audio completed, starting main challenge audio');
    setState(() {
      _isPlayingIntro = false;
      _introCompleted = true;
    });
    await _audioManager.stopIntro();
    _startMainAudio();
  }

  Future<void> _startMainAudio() async {
    try {
      await _audioManager.playFromIndex(0);
      await _audioManager.setVolume(1);
      debugPrint('Main challenge audio started');
    } catch (e) {
      debugPrint('Error starting main audio: $e');
      _showCenterNotification('Audio playback failed');
      Future.delayed(const Duration(seconds: 2), _handleAudioCompletion);
    }
  }

  void _initializeService() async {
    _socketService = SocketService(
      onLoadingChanged: (isLoading) => debugPrint('Socket loading: $isLoading'),
      onErrorChanged: (error) => debugPrint('Socket error: $error'),
      onHeartRateChanged: _handleHeartRateUpdate,
      onSpeedChanged: (speed) =>
          debugPrint('Speed data saved to server: $speed km/h'),
    );
    await _socketService!.fetechtoken();

    if (Platform.isAndroid) {
      _useSocket = false;
      await GeolocationSpeedService().initialize();
      GeolocationSpeedService().startTracking();
      _dataSubscription = GeolocationSpeedService().speedStream.listen((
        speedMs,
      ) {
        double speedKmph = speedMs * 3.6;
        _handleSpeedUpdate(speedKmph);
        if (_socketService != null) {
          _socketService!.sendSpeed(speedKmph);
          debugPrint('Sent GPS speed data to server: $speedKmph km/h');
        }
      });
    } else if (Platform.isIOS) {
      _useSocket = true;
    }
  }

  void _handleHeartRateUpdate(double? heartRate) async {
    if (heartRate == null) return;

    if (!_hasMaxHR) await _fetchMaxHR();

    setState(() => _currentHR = heartRate.toInt());

    if (_maxHR == null) return;

    final currentAudio = widget.audioData[_currentAudioIndex];
    final int zoneId = currentAudio['zoneId'];
    final currentHeartRate = _currentHR;

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

    if (currentHeartRate != null &&
        (currentHeartRate < lowerBound || currentHeartRate > upperBound)) {
      if (!_isInDetour) {
        setState(() {
          _outOfZoneCount++;
          debugPrint('Heart rate out of zone, count: $_outOfZoneCount');
        });
      }
      if (_audioManager.isPlaying && !_isPlayingIntro && !_isInDetour) {
        Future.delayed(const Duration(seconds: 10), () {
          if (_currentHR != null &&
              (_currentHR! < lowerBound || _currentHR! > upperBound) &&
              !_isPlayingIntro &&
              !_isInDetour) {
            _audioManager.pause();
            if (_currentHR! < lowerBound) {
              _playLowerOutOfRangeAudio('heart');
            } else {
              _playUpperOutOfRangeAudio('heart');
            }
            _showCenterNotification('Music paused');
            debugPrint('Music paused due to heart rate out of range');
          }
        });
      }
    } else {
      if (!_audioManager.isPlaying && _introCompleted && !_isInDetour) {
        _audioManager.resume();
        _audioManager.resumePacing();
        debugPrint('Music resumed due to heart rate in range');
      }
    }

    // Check for detour trigger
    if (!_isInDetour &&
        _outOfZoneCount >= 3 &&
        _currentPosition >= const Duration(minutes: 4, seconds: 20)) {
      _startDetour();
    }
  }

  void _handleSpeedUpdate(double? speedKmph) {
    if (speedKmph == null) return;

    setState(() => _currentSpeedKmph = speedKmph);

    final currentAudio = widget.audioData[_currentAudioIndex];
    final int zoneId = currentAudio['zoneId'];

    double lowerBound, upperBound;
    switch (zoneId) {
      case 1:
        lowerBound = 4.0;
        upperBound = 6.0;
        break;
      case 2:
        lowerBound = 6.01;
        upperBound = 8.0;
        break;
      case 3:
        lowerBound = 8.01;
        upperBound = 12.0;
        break;
      default:
        lowerBound = 0.0;
        upperBound = 0.0;
    }

    if (speedKmph >= lowerBound && speedKmph <= upperBound) {
      if (!_audioManager.isPlaying && _introCompleted && !_isInDetour) {
        _audioManager.resume();
        _audioManager.resumePacing();
        debugPrint('Music resumed due to speed in range');
      }
    } else {
      if (!_isInDetour) {
        setState(() {
          _outOfZoneCount++;
          debugPrint('Speed out of zone, count: $_outOfZoneCount');
        });
      }
      if (_audioManager.isPlaying && !_isPlayingIntro && !_isInDetour) {
        Future.delayed(const Duration(seconds: 10), () {
          if (_currentSpeedKmph != null &&
              (_currentSpeedKmph! < lowerBound ||
                  _currentSpeedKmph! > upperBound) &&
              !_isPlayingIntro &&
              !_isInDetour) {
            _audioManager.pause();
            if (_currentSpeedKmph! < lowerBound) {
              _playLowerOutOfRangeAudio('speed');
            } else {
              _playUpperOutOfRangeAudio('speed');
            }
            _showCenterNotification('Music paused');
            debugPrint('Music paused due to speed out of range');
          }
        });
      }
    }

    // Check for detour trigger
    if (!_isInDetour &&
        _outOfZoneCount >= 3 &&
        _currentPosition >= const Duration(minutes: 4, seconds: 20)) {
      _startDetour();
    }
  }

  // --- START: Detour Management Functions ---
  Future<void> _startDetour() async {
    setState(() {
      _isInDetour = true;
      _detourTriggerPosition = _currentPosition;
      _detourElapsedSeconds = 0;
      _detourTriggered = List<bool>.filled(_detourTimestamps.length, false);
    });

    await _audioManager.setVolume(0);
    await _audioManager.stopPacing(); // Stop any regular pacing

    // --- ADD THIS BLOCK ---
    // Start the specific pacing audio for the detour
    if (_pacingAudioFiles.length > 1) {
      // Safety check
      String detourPacingPath = 'assets/audio/pacing/${_pacingAudioFiles[1]}';
      _audioManager.playPacingLoop(detourPacingPath);
      debugPrint('Playing detour pacing audio: $detourPacingPath');
    }
    // --- END OF BLOCK ---

    debugPrint('--- DETOUR STARTED ---');
    _showCenterNotification('Detour Started');

    _detourTimer?.cancel();
    _detourTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _detourElapsedSeconds++;
      final virtualPosition =
          _detourTriggerPosition + Duration(seconds: _detourElapsedSeconds);
      _checkForDetourAudio(virtualPosition);
    });
  }

  Future<void> _endDetour() async {
    _detourTimer?.cancel();

    setState(() {
      _isInDetour = false;
      _outOfZoneCount = 0;
      _currentDetourIndex = -1;
    });

    await _audioManager.setVolume(1);
    await _audioManager.stopPacing();

    debugPrint('--- DETOUR ENDED ---');
    _showCenterNotification('Resuming Challenge');

    // ADD THIS BLOCK
    // After the detour, check if the main audio had already finished.
    // If so, manually trigger the completion logic.
    if (_audioManager.audioPlayer.processingState ==
        ProcessingState.completed) {
      debugPrint(
          'Main audio finished during detour. Triggering completion now.');
      _handleAudioCompletion();
    }
  }
  // --- END: Detour Management Functions ---

  void _playLowerOutOfRangeAudio(String reason) {
    String outOfRangeAudioPath = 'assets/audio/stop/slow.wav';
    _audioManager.playOverlay(outOfRangeAudioPath, volume: 2.0);
    debugPrint(
      'Playing out of range audio due to low $reason: $outOfRangeAudioPath',
    );
  }

  void _playUpperOutOfRangeAudio(String reason) {
    String outOfRangeAudioPath = 'assets/audio/stop/fast.wav';
    _audioManager.playOverlay(outOfRangeAudioPath, volume: 2.0);
    debugPrint(
      'Playing out of range audio due to high $reason: $outOfRangeAudioPath',
    );
  }

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

  void _initializeAudioListeners() {
    _positionSubscription = _audioManager.positionStream.listen((position) {
      if (position > Duration.zero && !_isPlayingIntro) {
        setState(() {
          _currentPosition = position;
          if (!_currentAudioStarted) _currentAudioStarted = true;
        });
        _handlePositionUpdate(position);
      }
    });

    _durationSubscription = _audioManager.durationStream.listen((duration) {
      if (duration != null) {
        setState(() => _totalDuration = duration);
      }
    });

    _currentIndexSubscription = _audioManager.currentIndexStream.listen((
      index,
    ) {
      if (index != null && index != _currentPlaylistIndex) {
        setState(() {
          _currentAudioIndex = index;
          _currentPlaylistIndex = index;
          _outOfZoneCount = 0;
          _isInDetour = false;
          _currentDetourIndex = -1;
        });
        _onTrackChanged();
      }
    });

    _playerStateSubscription = _audioManager.playerStateStream.listen((state) {
      debugPrint('Player state: ${state.processingState}');
      if (state.processingState == ProcessingState.completed && !_isInDetour) {
        _handleAudioCompletion();
      }
      setState(() {});
    });
  }

  void _onTrackChanged() {
    debugPrint('Track changed to index: $_currentAudioIndex');
    _initializeTimestamps();
    _currentAudioStarted = false;
    currentTrackNudges = 0;
  }

  Future<void> _handleAudioCompletion() async {
    _consecutiveChallengeCompletions++;

    int challengeCompletionScore;
    if (_consecutiveChallengeCompletions == 1) {
      challengeCompletionScore = 20;
    } else {
      challengeCompletionScore = 20 * _consecutiveChallengeCompletions;
    }

    _currentScore += challengeCompletionScore;
    _challengeScores.add(challengeCompletionScore);

    debugPrint(
      'Challenge completed! Score +$challengeCompletionScore (Challenge #$_consecutiveChallengeCompletions). Total: $_currentScore',
    );

    if (_currentAudioIndex + 1 >= widget.audioData.length) {
      _navigateToCompletionScreen();
    } else {
      debugPrint('Moving to next track automatically');
    }
  }

  void _navigateToCompletionScreen() {
    final lastAudio = widget.audioData.last;
    debugPrint('=== FINAL SCORING SUMMARY ===');
    debugPrint('Total Score: $_currentScore');
    debugPrint('Total Challenges Completed: $_consecutiveChallengeCompletions');
    debugPrint('Individual Challenge Scores: $_challengeScores');
    debugPrint('Total Nudges: $totalNudges');
    debugPrint('============================');

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
            score: _currentScore,
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
      case 1:
      case 2:
      case 3:
      case 4:
      case 5:
        timeStrings = [
          '1:20',
          '1:50',
          '2:20',
          '2:50',
          '3:20',
          '3:50',
          '4:20',
          '4:50',
        ];
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
    // This is now the main router for updates based on game state
    if (_introCompleted && !_isPlayingIntro) {
      // ADD THIS BLOCK HERE
      // This check now runs continuously with the audio timer.
      if (!_isInDetour &&
          _outOfZoneCount >= 3 &&
          position >= const Duration(minutes: 4, seconds: 20)) {
        _startDetour();
      }
      // END of new block
      if (_isInDetour) {
        _checkForDetourAudio(position);
      } else {
        _checkForOverlayTrigger(position);
      }
      // Pacing is checked in both modes, but with different rules.
      _checkForPacingAudio(position);
    }
  }

  void _checkForDetourAudio(Duration position) {
    final currentAudio = widget.audioData[_currentAudioIndex];
    final int storyId = currentAudio['storyId'];

    for (int i = 0; i < _detourTimestamps.length; i++) {
      if (!_detourTriggered[i] &&
          _isInTimestampRange(position, _detourTimestamps[i])) {
        _detourTriggered[i] = true;
        _currentDetourIndex = i;
        String detourPath = '';

        bool isLastAudio = (i == _detourTimestamps.length - 1);

        // For d1 to d8, check if user is out of zone
        if (i > 0 && !isLastAudio) {
          bool isOutOfZone = false;
          // Check HR if using socket
          if (_useSocket && _currentHR != null && _maxHR != null) {
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
            isOutOfZone = _currentHR! < lowerBound || _currentHR! > upperBound;
          }
          // Check Speed if not using socket
          else if (!_useSocket && _currentSpeedKmph != null) {
            final int zoneId = currentAudio['zoneId'];
            double lowerBound, upperBound;
            switch (zoneId) {
              case 1:
                lowerBound = 4.0;
                upperBound = 6.0;
                break;
              case 2:
                lowerBound = 6.01;
                upperBound = 8.0;
                break;
              case 3:
                lowerBound = 8.01;
                upperBound = 12.0;
                break;
              default:
                lowerBound = 0.0;
                upperBound = 0.0;
            }
            isOutOfZone = _currentSpeedKmph! < lowerBound ||
                _currentSpeedKmph! > upperBound;
          }

          // If not out of zone, don't play d1-d8 and continue to next check
          if (!isOutOfZone) {
            debugPrint("Skipping detour audio d$i because user is in zone.");
            continue;
          }
        }

        // Determine audio path
        String audioName = (i == 0)
            ? 'dstart'
            : isLastAudio
                ? 'dstop'
                : 'd$i';

        switch (storyId) {
          case 1:
            detourPath = 'assets/audio/aradium/detour/$audioName.wav';
            break;
          case 2:
            detourPath = 'assets/audio/smm/detour/$audioName.wav';
            break;
          case 3:
            detourPath = 'assets/audio/luther/detour/$audioName.wav';
            break;
          case 4:
            detourPath = 'assets/audio/dare/detour/$audioName.wav';
            break;
          default:
            detourPath = 'assets/audio/aradium/detour/$audioName.wav';
        }

        // Play the audio
        _audioManager.playOverlay(detourPath, volume: 2.0);
        debugPrint('Playing detour audio: $detourPath');

        // If it was the last audio, end the detour
        if (isLastAudio) {
          _endDetour();
        }
      }
    }
  }

  void _checkForPacingAudio(Duration position) {
    // Add this guard clause to disable normal pacing during a detour
    if (_isInDetour) return;

    if (!_currentAudioStarted) return;

    final int previousAudiosDuration = _currentAudioIndex * 5;
    final Duration globalPosition =
        Duration(minutes: previousAudiosDuration) + position;
    int newSegment = -1;

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
        debugPrint(
            'Playing pacing audio (segment $_currentPacingSegment): $pacingAudioPath');
      }
    }
  }

  void _checkForOverlayTrigger(Duration position) {
    // This function is only called when not in a detour.
    if (_isInDetour) return;

    final currentAudio = widget.audioData[_currentAudioIndex];
    final int storyId = currentAudio['storyId'];
    String overlayType = 'A'; // Assume in zone

    if (_useSocket) {
      if (_currentHR != null && _maxHR != null) {
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
        overlayType = (_currentHR! >= lowerBound && _currentHR! <= upperBound)
            ? 'A'
            : 'S';
      }
    } else {
      if (_currentSpeedKmph != null) {
        final int zoneId = currentAudio['zoneId'];
        double lowerBound, upperBound;
        switch (zoneId) {
          case 1:
            lowerBound = 4.0;
            upperBound = 6.0;
            break;
          case 2:
            lowerBound = 6.0;
            upperBound = 8.0;
            break;
          case 3:
            lowerBound = 8.0;
            upperBound = 12.0;
            break;
          default:
            lowerBound = 0.0;
            upperBound = 0.0;
        }
        overlayType = (_currentSpeedKmph! >= lowerBound &&
                _currentSpeedKmph! <= upperBound)
            ? 'A'
            : 'S';
      }
    }

    for (int i = 0; i < _timestamps.length; i++) {
      if (!_triggered[i] && _isInTimestampRange(position, _timestamps[i])) {
        _triggered[i] = true;
        totalNudges++;
        currentTrackNudges++;

        // Scoring logic
        if (overlayType == 'A') {
          _currentScore += 5;
          debugPrint('Score +5: In zone at timestamp. Total: $_currentScore');
        } else {
          _currentScore -= 1;
          debugPrint(
              'Score -1: Outside zone at timestamp. Total: $_currentScore');
        }

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
    // Prevent play/pause during a detour
    if (_isInDetour) {
      _showCenterNotification('Cannot pause during detour', seconds: 2);
      return;
    }

    if (_isPlayingIntro) {
      if (_audioManager.introPlayer.playing) {
        await _audioManager.introPlayer.pause();
        _startBlinking();
        debugPrint('Intro audio paused');
      } else {
        await _audioManager.introPlayer.play();
        _stopBlinking();
        debugPrint('Intro audio resumed');
      }
    } else {
      if (_audioManager.isPlaying) {
        await _audioManager.pause();
        _startBlinking();
        debugPrint('Main audio paused');
      } else {
        _audioManager.resume();
        _audioManager.resumePacing();
        _stopBlinking();
        debugPrint('Main audio resumed');
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    _notificationTimer?.cancel();
    _blinkTimer?.cancel();
    _unlockTimer?.cancel();
    _dataSubscription?.cancel();

    _audioManager.dispose();
    _positionSubscription.cancel();
    _durationSubscription.cancel();
    _playerStateSubscription.cancel();
    _currentIndexSubscription.cancel();
    _introPositionSubscription.cancel();
    _introDurationSubscription.cancel();
    _introPlayerStateSubscription.cancel();

    if (_socketService != null) {
      try {
        _socketService!.dispose();
      } catch (_) {}
    }
    if (!_useSocket && Platform.isAndroid) {
      GeolocationSpeedService().stopTracking();
    }
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
            style: TextStyle(color: Colors.white, fontSize: 18),
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
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
              ],
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
                                        maxLines: 3,
                                        overflow: TextOverflow.clip,
                                      )
                                    : _isPlayingIntro
                                        ? Column(
                                            key: const ValueKey('intro'),
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const SizedBox(height: 8),
                                              Text(
                                                _formatDuration(
                                                    _introTotalDuration -
                                                        _introPosition),
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 32,
                                                  fontWeight: FontWeight.normal,
                                                  fontFamily: 'Thewitcher',
                                                  letterSpacing: 2,
                                                ),
                                              ),
                                            ],
                                          )
                                        : (_audioManager.isPlaying
                                            ? (_currentAudioStarted
                                                ? !_isInDetour
                                                    ? Text(
                                                        _formatDuration(
                                                            remaining),
                                                        key: const ValueKey(
                                                            'timer'),
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 40,
                                                          fontWeight:
                                                              FontWeight.normal,
                                                          fontFamily:
                                                              'Thewitcher',
                                                          letterSpacing: 2,
                                                        ),
                                                      )
                                                    : const Icon(
                                                        Icons.alt_route,
                                                        color: Colors.white,
                                                        size: 60,
                                                        key: ValueKey(
                                                            'detour_icon'),
                                                      )
                                                : const SizedBox(
                                                    key: ValueKey('loading'),
                                                    width: 60,
                                                    height: 60,
                                                    child:
                                                        CircularProgressIndicator(
                                                      valueColor:
                                                          AlwaysStoppedAnimation<
                                                                  Color>(
                                                              Colors.white),
                                                      strokeWidth: 6,
                                                    ),
                                                  ))
                                            : (_isPausedBlink
                                                ? Icon(
                                                    Icons.play_arrow_rounded,
                                                    key: const ValueKey(
                                                      'playicon',
                                                    ),
                                                    color: Colors.white,
                                                    size: 60,
                                                  )
                                                : Text(
                                                    _formatDuration(remaining),
                                                    key: const ValueKey(
                                                      'timer',
                                                    ),
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 40,
                                                      fontWeight:
                                                          FontWeight.normal,
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
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              children: [
                                const Text(
                                  "Heart Rate",
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  _currentHR != null ? "$_currentHR bpm" : "--",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              children: [
                                const Text(
                                  "Pacing",
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  _currentSpeedKmph != null
                                      ? "${_currentSpeedKmph!.toStringAsFixed(1)} km/h"
                                      : "--",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(flex: 2),
                  // Hide progress bar during detour
                  if (!_isInDetour) ...[
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
                                enabledThumbRadius: _timestamps.any(
                                  (timestamp) =>
                                      (timestamp.inSeconds -
                                              _currentPosition.inSeconds)
                                          .abs() <=
                                      1,
                                )
                                    ? 12.0
                                    : 0.0,
                              ),
                              overlayColor: Colors.purple.withOpacity(0.2),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 28.0,
                              ),
                            ),
                            // Disable slider seeking during detour
                            child: Slider(
                              value: _isPlayingIntro
                                  ? _introPosition.inSeconds.toDouble()
                                  : _currentPosition.inSeconds.toDouble(),
                              min: 0,
                              max: _isPlayingIntro
                                  ? (_introTotalDuration.inSeconds.toDouble() >
                                          0
                                      ? _introTotalDuration.inSeconds.toDouble()
                                      : 1)
                                  : (_totalDuration.inSeconds.toDouble() > 0
                                      ? _totalDuration.inSeconds.toDouble()
                                      : 1),
                              onChanged: _isInDetour
                                  ? null
                                  : (value) async {
                                      final position =
                                          Duration(seconds: value.toInt());
                                      if (_isPlayingIntro) {
                                        await _audioManager.introPlayer
                                            .seek(position);
                                      } else {
                                        await _audioManager.audioPlayer
                                            .seek(position);
                                      }
                                    },
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _isPlayingIntro
                                    ? _formatDuration(_introPosition)
                                    : _formatDuration(_currentPosition),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                _isPlayingIntro
                                    ? _formatDuration(_introTotalDuration)
                                    : _formatDuration(_totalDuration),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                  const Spacer(flex: 1),
                ],
              ),
            ] else
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
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.purple,
                          ),
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
                          child: Icon(
                            Icons.lock_open,
                            color: Colors.white,
                            size: 48,
                          ),
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
