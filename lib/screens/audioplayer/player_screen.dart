import 'dart:async';
import 'dart:convert';
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
  bool _isCompleting = false;
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
  StreamSubscription? _distanceSubscription; // For GPS distance on Android
  List<Duration> _timestamps = [];
  List<bool> _triggered = [];
  bool _hasMaxHR = false;
  final List<String> _pacingAudioFiles = [];
  List<Duration> _pacingTimestamps = [];
  int _currentAudioIndex = 0;
  int _currentPacingSegment = -1;
  List<Duration> _pacingSegmentEnds = [];
  bool _useSocket = false;

  // Distance tracking variables
  double _totalDistanceKm = 0.0;
  double _initialPedometerDistance = -1.0;

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
    debugPrint(
        'Pedometer data: ${data.numberOfSteps} steps, distance: ${data.distance}m');
    _pedometerData.value = data;

    // --- START: NEW DISTANCE LOGIC ---
    if (data.distance != null) {
      if (_initialPedometerDistance < 0) {
        // Set the initial distance on the first reading
        _initialPedometerDistance = data.distance!;
      }

      // Calculate distance covered since the session started
      final sessionDistanceMeters = data.distance! - _initialPedometerDistance;
      setState(() {
        _totalDistanceKm = sessionDistanceMeters / 1000.0;
      });
    }

    // --- START: MODIFIED SPEED LOGIC ---
    double speedKmph = 0.0; // Default to 0 when no pace
    if (data.currentPace != null && data.currentPace! > 0) {
      double speedMs = 1 / data.currentPace!; // meters per second
      speedKmph = speedMs * 3.6; // km/h
    }
    setState(() {
      _currentSpeedKmph = speedKmph; // Update speed, set to 0 if no pace
    });

    // Only update speed-based logic if heart rate is not available on iOS
    if (!Platform.isIOS || _currentHR == null) {
      _handleSpeedUpdate(speedKmph);
    }
    if (_socketService != null) {
      _socketService!.sendSpeed(speedKmph);
      debugPrint('Sent Pedometer speed data to server: $speedKmph km/h');
    }
    // --- END: MODIFIED SPEED LOGIC ---
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

      // Check story ID to decide on playing intro
      final int storyId = widget.audioData.first['storyId'];
      if (storyId == 1 || storyId == 3) {
        // Skip intro for story 1 and 3
        debugPrint('Story ID is $storyId. Skipping intro audio.');
        setState(() {
          _isPlayingIntro = false;
          _introCompleted = true;
        });
        await _startMainAudio();
      } else {
        // Play intro for other stories
        debugPrint('Story ID is $storyId. Playing intro audio.');
        _initializeIntroAudioListeners();
        await _playIntroAudio();
      }

      _initializeTimestamps();
      debugPrint('Playlist initialized and ready.');
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

      _audioManager.playIntro(introAudioPath, volume: 1.0);
      debugPrint('Playing intro audio: $introAudioPath');

      // Play 100bpm pacing during the intro
      String introPacingPath = 'assets/audio/pacing/100.mp3';
      _audioManager.playPacingLoop(introPacingPath);
      debugPrint('Playing intro pacing audio: $introPacingPath');
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

    // Stop intro pacing audio
    await _audioManager.stopPacing();
    debugPrint('Intro pacing audio stopped.');

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

  Future<void> _initializeService() async {
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
      // Subscribe to the distance stream for Android
      _distanceSubscription =
          GeolocationSpeedService().distanceStream.listen((distanceInMeters) {
        if (mounted) {
          setState(() {
            _totalDistanceKm = distanceInMeters / 1000.0;
          });
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

    // Bounds for pausing/resuming audio
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

    // Bounds for detour scoring and early exit
    int detourLowerBound = 0, detourUpperBound = 0;
    switch (zoneId) {
      case 1:
        detourLowerBound = (72 + (_maxHR! - 72) * 0.5).toInt();
        detourUpperBound = (72 + (_maxHR! - 72) * 0.6).toInt();
        break;
      case 2:
        detourLowerBound = (72 + (_maxHR! - 72) * 0.6).toInt();
        detourUpperBound = (72 + (_maxHR! - 72) * 0.7).toInt();
        break;
      case 3:
        detourLowerBound = (72 + (_maxHR! - 72) * 0.7).toInt();
        detourUpperBound = (72 + (_maxHR! - 72) * 0.8).toInt();
        break;
    }

    // Always use heart rate for iOS when available
    if (Platform.isIOS && _currentHR != null) {
      if (_currentHR! < lowerBound || _currentHR! > upperBound) {
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
        // Check for early detour exit using detour bounds
        if (_isInDetour &&
            _currentHR != null &&
            _currentHR! >= detourLowerBound &&
            _currentHR! <= detourUpperBound) {
          _endDetourEarly();
          return; // Exit to prevent resuming music immediately
        }
        if (!_audioManager.isPlaying && _introCompleted && !_isInDetour) {
          _audioManager.resume();
          _audioManager.resumePacing();
          debugPrint('Music resumed due to heart rate in range');
        }
      }
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
        lowerBound = 3.0;
        upperBound = 7.0;
        break;
      case 2:
        lowerBound = 5.0;
        upperBound = 9.0;
        break;
      case 3:
        lowerBound = 7.0;
        upperBound = 13.0;
        break;
      default:
        lowerBound = 0.0;
        upperBound = 0.0;
    }

    // Use speed only on Android or on iOS when heart rate is unavailable
    if (Platform.isAndroid || (Platform.isIOS && _currentHR == null)) {
      if (speedKmph >= lowerBound && speedKmph <= upperBound) {
        // Check for early detour exit using the same bounds
        if (_isInDetour) {
          _endDetourEarly();
          return; // Exit to prevent resuming music immediately
        }
        if (!_audioManager.isPlaying && _introCompleted && !_isInDetour) {
          _audioManager.resume();
          _audioManager.resumePacing();
          debugPrint('Music resumed due to speed in range');
        }
      } else {
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
    }
  }

  // --- START: Detour Management Functions ---
  Future<void> _startDetour() async {
    setState(() {
      _isInDetour = true;
      _detourStartPosition = _currentPosition; // Note the exact position
      _detourElapsedSeconds = 0;
      _detourTriggered = List<bool>.filled(_detourTimestamps.length, false);
    });

    await _audioManager.pause(); // Pause the main audio player
    await _audioManager.stopPacing();

    // Start the special detour pacing audio based on heart rate or speed
    if (_pacingAudioFiles.length > 1) {
      String detourPacingPath = 'assets/audio/pacing/${_pacingAudioFiles[1]}';
      _audioManager.playPacingLoop(detourPacingPath);
      debugPrint('Playing detour pacing audio: $detourPacingPath');
    }

    debugPrint('--- DETOUR STARTED ---');
    _showCenterNotification('Detour Started');

    _detourTimer?.cancel();
    _detourTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _detourElapsedSeconds++;
      final virtualPosition =
          _detourStartPosition + Duration(seconds: _detourElapsedSeconds);
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

    // Seek back to where the detour started and then resume
    await _audioManager.audioPlayer.seek(_detourStartPosition);
    await _audioManager.resume();

    await _audioManager.stopPacing();

    debugPrint('--- DETOUR ENDED ---');
    _showCenterNotification('Resuming Challenge');

    if (_audioManager.audioPlayer.processingState ==
        ProcessingState.completed) {
      debugPrint(
          'Main audio finished during detour. Triggering completion now.');
      _handleAudioCompletion();
    }
  }

  void _endDetourEarly() {
    if (!_isInDetour) return; // Prevent this from running more than once

    debugPrint('User is back in zone. Ending detour early.');

    // Get the path for dstop.wav
    final currentAudio = widget.audioData[_currentAudioIndex];
    final int storyId = currentAudio['storyId'];
    String dstopPath;
    switch (storyId) {
      case 1:
        dstopPath = 'assets/audio/detour/dstop.wav';
        break;
      case 2:
        dstopPath = 'assets/audio/detour/dstop.wav';
        break;
      case 3:
        dstopPath = 'assets/audio/detour/dstop.wav';
        break;
      case 4:
        dstopPath = 'assets/audio/detour/dstop.wav';
        break;
      default:
        dstopPath = 'assets/audio/detour/dstop.wav';
    }

    // Play the final sound and immediately end the detour
    _audioManager.playOverlay(dstopPath, volume: 2.0);
    _endDetour();
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
    if (_isCompleting) return;
    setState(() {
      _isCompleting = true;
    });

    _consecutiveChallengeCompletions++;

    int challengeCompletionScore;
    if (_consecutiveChallengeCompletions == 1) {
      challengeCompletionScore = 20;
    } else {
      challengeCompletionScore = 20 * _consecutiveChallengeCompletions;
    }

    setState(() {
      _currentScore += challengeCompletionScore;
      _challengeScores.add(challengeCompletionScore);
    });

    // Store individual audio completion score in SharedPreferences
    await _storeAudioCompletionScore(challengeCompletionScore);

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

  Future<void> _storeAudioCompletionScore(int score) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentAudio = widget.audioData[_currentAudioIndex];

      // Create a unique key for this audio completion
      // Using audio ID, challenge name, and completion number for uniqueness
      final String audioKey =
          'audio_completion_${currentAudio['id']}_${currentAudio['challengeName']}_completion_$_consecutiveChallengeCompletions';

      // Store the completion score with timestamp for reference
      final Map<String, dynamic> completionData = {
        'score': score,
        'completionNumber': _consecutiveChallengeCompletions,
        'audioId': currentAudio['id'],
        'challengeName': currentAudio['challengeName'],
        'storyId': currentAudio['storyId'],
        'zoneId': currentAudio['zoneId'],
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'totalNudges': currentTrackNudges,
      };

      // Store as JSON string
      await prefs.setString(audioKey, jsonEncode(completionData));

      debugPrint(
          'Stored audio completion: $audioKey with data: $completionData');
    } catch (e) {
      debugPrint('Error storing audio completion score: $e');
    }
  }

  int roundToNearest10(double value) {
    return (value / 10).round() * 10;
  }

  void _handlePositionUpdate(Duration position) {
    if (_introCompleted && !_isPlayingIntro) {
      // Get the storyId from the current audio data
      final int storyId = widget.audioData[_currentAudioIndex]['storyId'];

      // Only trigger detour logic if storyId is not 1 or 3
      if (storyId != 1 && storyId != 3) {
        if (!_isInDetour &&
            _outOfZoneCount >= 3 &&
            position >= const Duration(minutes: 4, seconds: 20)) {
          _startDetour();
        }
      }

      if (_isInDetour) {
        _checkForDetourAudio(position);
      } else {
        _checkForOverlayTrigger(position);
      }
      _checkForPacingAudio(position);
    }
  }

  void _checkForDetourAudio(Duration position) {
    final currentAudio = widget.audioData[_currentAudioIndex];
    final int storyId = currentAudio['storyId'];
    final filteredChallenges = widget.audioData;
    final challengeId = filteredChallenges.indexWhere(
      (c) => c['id'] == currentAudio['id'],
    );

    for (int i = 0; i < _detourTimestamps.length; i++) {
      if (!_detourTriggered[i] &&
          _isInTimestampRange(position, _detourTimestamps[i])) {
        _detourTriggered[i] = true;
        _currentDetourIndex = i;
        String detourPath = '';

        bool isLastAudio = (i == _detourTimestamps.length - 1);

        // For d1 to d8, check if user is out of zone and apply scoring
        if (i > 0 && !isLastAudio) {
          bool isOutOfZone = false;
          // Prioritize heart rate for iOS
          if (Platform.isIOS && _currentHR != null && _maxHR != null) {
            final int zoneId = currentAudio['zoneId'];
            int lowerBound = 0, upperBound = 0;
            switch (zoneId) {
              case 1:
                lowerBound = (72 + (_maxHR! - 72) * 0.5).toInt();
                upperBound = (72 + (_maxHR! - 72) * 0.6).toInt();
                break;
              case 2:
                lowerBound = (72 + (_maxHR! - 72) * 0.6).toInt();
                upperBound = (72 + (_maxHR! - 72) * 0.7).toInt();
                break;
              case 3:
                lowerBound = (72 + (_maxHR! - 72) * 0.7).toInt();
                upperBound = (72 + (_maxHR! - 72) * 0.8).toInt();
                break;
            }
            isOutOfZone = _currentHR! < lowerBound || _currentHR! > upperBound;
          }
          // Fallback to speed for iOS if heart rate unavailable, or use speed for Android
          else if ((Platform.isIOS &&
                  _currentHR == null &&
                  _currentSpeedKmph != null) ||
              Platform.isAndroid) {
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

          // Apply scoring based on whether the user is in or out of zone
          if (isOutOfZone) {
            // User is out of zone: -1 point
            setState(() {
              _currentScore -= 1;
            });
            debugPrint(
                'Score -1: Out of zone during detour. Total: $_currentScore');
          } else {
            // User is in zone: +5 points
            setState(() {
              _currentScore += 5;
            });
            debugPrint(
                'Score +5: In zone during detour. Total: $_currentScore');
            debugPrint("Skipping detour audio d$i because user is in zone.");
            continue; // Skip playing the out-of-zone audio cue
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
            detourPath =
                'assets/audio/aradium/detour/$challengeId/$audioName.wav';
            break;
          case 2:
            detourPath = 'assets/audio/smm/detour/$challengeId/$audioName.wav';
            break;
          case 3:
            detourPath =
                'assets/audio/luther/detour/$challengeId/$audioName.wav';
            break;
          case 4:
            detourPath = 'assets/audio/dare/detour/$challengeId/$audioName.wav';
            break;
          default:
            detourPath =
                'assets/audio/aradium/detour/$challengeId/$audioName.wav';
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

      // Select pacing audio based on heart rate for iOS, speed for Android or iOS fallback
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
    if (_isInDetour) return;

    final currentAudio = widget.audioData[_currentAudioIndex];
    final int storyId = currentAudio['storyId'];
    String overlayType; // No longer default to 'A'

    // Define bounds for scoring and overlay logic
    double lowerBound = 0.0, upperBound = 0.0;
    bool inZone = false;

    // Prioritize heart rate for iOS
    if (Platform.isIOS && _currentHR != null && _maxHR != null) {
      final int zoneId = currentAudio['zoneId'];
      switch (zoneId) {
        case 1:
          lowerBound = (72 + (_maxHR! - 72) * 0.5);
          upperBound = (72 + (_maxHR! - 72) * 0.6);
          break;
        case 2:
          lowerBound = (72 + (_maxHR! - 72) * 0.6);
          upperBound = (72 + (_maxHR! - 72) * 0.7);
          break;
        case 3:
          lowerBound = (72 + (_maxHR! - 72) * 0.7);
          upperBound = (72 + (_maxHR! - 72) * 0.8);
          break;
      }
      // Scoring is based on being between lower and upper bounds.
      inZone = (_currentHR! <= upperBound && _currentHR! >= lowerBound);
      // **MODIFIED LOGIC**: Overlay 'S' only plays if HR is above the upper bound.
      overlayType = (_currentHR! > upperBound) ? 'S' : 'A';
      debugPrint(
          "Heart rate based - Inside zone (for scoring): $inZone, Overlay Type: $overlayType");
    }
    // Fallback to speed for iOS if heart rate unavailable, or use speed for Android
    else if ((Platform.isIOS &&
            _currentHR == null &&
            _currentSpeedKmph != null) ||
        Platform.isAndroid) {
      final int zoneId = currentAudio['zoneId'];
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
      // Scoring is based on being between lower and upper bounds.
      inZone = (_currentSpeedKmph! <= upperBound &&
          _currentSpeedKmph! >= lowerBound);
      // **MODIFIED LOGIC**: Overlay 'S' only plays if speed is above the upper bound.
      overlayType = (_currentSpeedKmph! > upperBound) ? 'S' : 'A';
      debugPrint(
          "Speed based - Inside zone (for scoring): $inZone, Overlay Type: $overlayType");
    } else {
      // Default case if no sensor data is available
      overlayType = 'A';
      inZone = true; // Assume in zone for scoring if no data
    }

    for (int i = 0; i < _timestamps.length; i++) {
      if (!_triggered[i] && _isInTimestampRange(position, _timestamps[i])) {
        _triggered[i] = true;
        totalNudges++;
        currentTrackNudges++;

        // Apply scoring based on inZone status (between lower and upper bounds)
        if (inZone) {
          setState(() {
            _currentScore += 5;
          });
          debugPrint('Score +5: In zone at overlay, total: $_currentScore');
        } else {
          setState(() {
            _currentScore -= 1;
            _outOfZoneCount++;
          });
          debugPrint(
              'Score -1: Outside zone at overlay, total: $_currentScore, Out of zone count: $_outOfZoneCount');
        }

        String overlayPath;
        const int overlayIndex = 0;
        switch (storyId) {
          case 1:
            overlayPath =
                'assets/audio/aradium/overlay/$overlayIndex/${overlayType}_$i.wav';
            break;
          case 2:
            overlayPath =
                'assets/audio/smm/overlay/$overlayIndex/${overlayType}_$i.wav';
            break;
          case 3:
            overlayPath =
                'assets/audio/luther/overlay/$overlayIndex/${overlayType}_$i.wav';
            break;
          case 4:
            overlayPath =
                'assets/audio/dare/overlay/$overlayIndex/${overlayType}_$i.wav';
            break;
          default:
            overlayPath =
                'assets/audio/overlay/$overlayIndex/${overlayType}_$i.wav';
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
    if (_isInDetour) {
      _showCenterNotification('Cannot pause during detour', seconds: 2);
      return;
    }

    if (_isPlayingIntro) {
      if (_audioManager.introPlayer.playing) {
        await _audioManager.introPlayer.pause();
        await _audioManager.stopPacing();
        _startBlinking();
        debugPrint('Intro audio and pacing paused');
      } else {
        await _audioManager.introPlayer.play();
        String introPacingPath = 'assets/audio/pacing/100.mp3';
        _audioManager.playPacingLoop(introPacingPath);
        _stopBlinking();
        debugPrint('Intro audio and pacing resumed');
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
    _distanceSubscription?.cancel(); // Cancel the new subscription

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
                    child: Column(
                      children: [
                        // First row - Heart Rate and Pacing
                        Row(
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
                                      _currentHR != null
                                          ? "$_currentHR bpm"
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
                                      "Speed",
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
                        const SizedBox(height: 15),
                        // Second row - Live Score and Distance
                        Row(
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
                                      "Live Score",
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      "$_currentScore",
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
                                      "Distance",
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      "${_totalDistanceKm.toStringAsFixed(2)} km",
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
                      ],
                    ),
                  ),
                  const Spacer(flex: 2),
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
            ],
            if (_isLocked)
              Stack(
                children: [
                  Container(
                    color: Colors.black.withOpacity(0.7),
                  ),
                  Positioned(
                    bottom: 160,
                    left: 20,
                    right: 20,
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.3),
                                    width: 1,
                                  ),
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
                                      _currentHR != null
                                          ? "$_currentHR bpm"
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
                            const SizedBox(width: 20),
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  children: [
                                    const Text(
                                      "Speed",
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
                        const SizedBox(height: 15),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  children: [
                                    const Text(
                                      "Live Score",
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      "$_currentScore",
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
                                  color: Colors.white.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  children: [
                                    const Text(
                                      "Distance",
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      "${_totalDistanceKm.toStringAsFixed(2)} km",
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
                      ],
                    ),
                  ),
                  Center(
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
          ],
        ),
      ),
    );
  }
}
