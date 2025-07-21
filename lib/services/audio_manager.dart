import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';

class AudioManager {
  static final AudioManager _instance = AudioManager._internal();
  AudioPlayer _mainPlayer = AudioPlayer();
  AudioPlayer _overlayPlayer = AudioPlayer();
  AudioPlayer _pacingPlayer = AudioPlayer();
  AudioPlayer _introPlayer = AudioPlayer(); // Add intro player

  // Add playlist management
  ConcatenatingAudioSource? _playlist;
  bool _isPlaylistInitialized = false;

  factory AudioManager() => _instance;

  AudioManager._internal() {
    _initializeAudioSession();
    _mainPlayer.playerStateStream.listen((state) {
      debugPrint(
          'Player state: ${state.processingState}, playing: ${state.playing}');
    });
  }

  // Initialize audio session for background playback
  Future<void> _initializeAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.mixWithOthers,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        avAudioSessionRouteSharingPolicy:
            AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          flags: AndroidAudioFlags.none,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: false,
      ));
    } catch (e) {
      debugPrint('Error initializing audio session: $e');
    }
  }

  Future<void> reset() async {
    try {
      await _mainPlayer.dispose();
      await _overlayPlayer.dispose();
      await _pacingPlayer.dispose();
      await _introPlayer.dispose();
    } catch (_) {}
    _mainPlayer = AudioPlayer();
    _overlayPlayer = AudioPlayer();
    _pacingPlayer = AudioPlayer();
    _introPlayer = AudioPlayer();
    _playlist = null;
    _isPlaylistInitialized = false;
    _initializeAudioSession();
    _mainPlayer.playerStateStream.listen((state) {
      debugPrint(
          'Player state: ${state.processingState}, playing: ${state.playing}');
    });
  }

  AudioPlayer get audioPlayer => _mainPlayer;
  AudioPlayer get introPlayer => _introPlayer; // Add intro player getter
  bool get isPlaying => _mainPlayer.playing;
  bool get isIntroPlaying => _introPlayer.playing; // Add intro playing status

  // Stream getters
  Stream<Duration> get positionStream => _mainPlayer.positionStream;
  Stream<Duration?> get durationStream => _mainPlayer.durationStream;
  Stream<PlayerState> get playerStateStream => _mainPlayer.playerStateStream;
  Stream<int?> get currentIndexStream => _mainPlayer.currentIndexStream;
  Duration get bufferedPosition => _mainPlayer.bufferedPosition;

  // Intro stream getters
  Stream<Duration> get introPositionStream => _introPlayer.positionStream;
  Stream<Duration?> get introDurationStream => _introPlayer.durationStream;
  Stream<PlayerState> get introPlayerStateStream =>
      _introPlayer.playerStateStream;

  // Initialize playlist with all audio URLs
  Future<void> initializePlaylist(List<Map<String, dynamic>> audioData) async {
    try {
      final List<AudioSource> audioSources = audioData.map((audio) {
        return AudioSource.uri(
          Uri.parse(audio['audioUrl']),
          tag: MediaItem(
            id: audio['id'].toString(),
            title: audio['challengeName'] ?? 'Audio Track',
            artist: 'Aexlrt',
            album: audio['challengeName'] ?? 'Audio Track',
            artUri: Uri.parse(
                'https://framerusercontent.com/images/lfx5q2JMlHryRKYaNgLOKmU4nDY.png'),
            duration: const Duration(minutes: 5),
          ),
        );
      }).toList();

      _playlist = ConcatenatingAudioSource(children: audioSources);
      await _mainPlayer.setAudioSource(_playlist!);
      _isPlaylistInitialized = true;

      debugPrint('Playlist initialized with ${audioSources.length} tracks');
    } catch (e) {
      debugPrint('Error initializing playlist: $e');
      rethrow;
    }
  }

  // Play from specific index in playlist
  Future<void> playFromIndex(int index) async {
    try {
      if (!_isPlaylistInitialized || _playlist == null) {
        throw Exception('Playlist not initialized');
      }

      await _mainPlayer.seek(Duration.zero, index: index);
      await _mainPlayer.play();

      debugPrint('Playing track at index: $index');
    } catch (e) {
      debugPrint('Error playing from index: $e');
      rethrow;
    }
  }

  // Legacy method for backward compatibility - now uses playlist
  Future<void> play(String url, {Duration? seekTo}) async {
    try {
      debugPrint('AudioManager: Playing URL: $url');

      if (url.isEmpty || url == 'null') {
        throw Exception('Invalid audio URL: $url');
      }

      final uri = Uri.parse(url);
      if (!uri.isAbsolute) {
        throw Exception('Malformed audio URL: $url');
      }

      await _mainPlayer.stop();
      await _mainPlayer.setAudioSource(
        AudioSource.uri(
          uri,
          tag: MediaItem(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            title: 'Audio Track',
            artist: 'Your App Name',
          ),
        ),
      );

      if (seekTo != null) {
        await _mainPlayer.seek(seekTo);
      }

      await _mainPlayer.play();
      debugPrint('AudioManager: Play command sent successfully');
    } catch (e) {
      debugPrint('AudioManager: Error playing audio: $e');
      rethrow;
    }
  }

  // Skip to next track in playlist
  Future<void> skipToNext() async {
    try {
      if (_mainPlayer.hasNext) {
        await _mainPlayer.seekToNext();
      }
    } catch (e) {
      debugPrint('Error skipping to next: $e');
    }
  }

  // Skip to previous track in playlist
  Future<void> skipToPrevious() async {
    try {
      if (_mainPlayer.hasPrevious) {
        await _mainPlayer.seekToPrevious();
      }
    } catch (e) {
      debugPrint('Error skipping to previous: $e');
    }
  }

  Future<void> playOverlay(String assetPath, {double volume = 1.5}) async {
    try {
      await _overlayPlayer.stop();
      await _overlayPlayer.setVolume(volume);
      await _overlayPlayer.setAsset(assetPath);
      await _overlayPlayer.play();
    } catch (e) {
      debugPrint('AudioManager: Error playing overlay: $e');
    }
  }

  // Add intro audio methods
  Future<void> playIntro(String assetPath, {double volume = 1.0}) async {
    try {
      debugPrint('AudioManager: Playing intro audio: $assetPath');
      await _introPlayer.stop();
      await _introPlayer.setVolume(volume);
      await _introPlayer.setAsset(assetPath);
      await _introPlayer.play();
    } catch (e) {
      debugPrint('AudioManager: Error playing intro: $e');
      rethrow;
    }
  }

  Future<void> stopIntro() async {
    try {
      await _introPlayer.stop();
    } catch (e) {
      debugPrint('AudioManager: Error stopping intro: $e');
    }
  }

  Future<void> playPacing(String assetPath, {double volume = 1}) async {
    try {
      await _pacingPlayer.stop();
      await _pacingPlayer.setVolume(volume);
      await _pacingPlayer.setAsset(assetPath);
      await _pacingPlayer.play();
    } catch (e) {
      debugPrint('AudioManager: Error playing pacing: $e');
    }
  }

  Future<void> playPacingLoop(String path, {double volume = 1}) async {
    try {
      await _pacingPlayer.stop();
      await _pacingPlayer.setVolume(volume);
      await _pacingPlayer.setAsset(path);
      await _pacingPlayer.setLoopMode(LoopMode.one);
      await _pacingPlayer.play();
    } catch (e) {
      debugPrint('AudioManager: Error playing pacing loop: $e');
    }
  }

  Future<void> stopPacing() async {
    try {
      await _pacingPlayer.stop();
    } catch (e) {
      debugPrint('AudioManager: Error stopping pacing: $e');
    }
  }

  Future<void> resumePacing() async {
    try {
      if (_pacingPlayer.processingState != ProcessingState.idle &&
          !_pacingPlayer.playing) {
        await _pacingPlayer.play();
        debugPrint('AudioManager: Resumed pacing audio');
      }
    } catch (e) {
      debugPrint('AudioManager: Error resuming pacing: $e');
    }
  }

  Future<void> pause() async {
    try {
      await _mainPlayer.pause();
      await _pacingPlayer.pause();
    } catch (e) {
      debugPrint('AudioManager: Error pausing: $e');
    }
  }

  Future<void> resume() async {
    try {
      await _mainPlayer.play();
      if (_pacingPlayer.processingState != ProcessingState.idle) {
        await _pacingPlayer.play();
      }
    } catch (e) {
      debugPrint('AudioManager: Error resuming: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _mainPlayer.stop();
      await _overlayPlayer.stop();
      await _pacingPlayer.stop();
      await _introPlayer.stop();
    } catch (e) {
      debugPrint('AudioManager: Error stopping: $e');
    }
  }

  Future<void> seek(Duration position) async {
    try {
      await _mainPlayer.seek(position);
    } catch (e) {
      debugPrint('AudioManager: Error seeking: $e');
    }
  }

  Future<void> setVolume(double volume) async {
    try {
      await _mainPlayer.setVolume(volume);
    } catch (e) {
      debugPrint('AudioManager: Error setting volume: $e');
    }
  }

  // Getters
  Duration get currentPosition => _mainPlayer.position;
  Duration? get totalDuration => _mainPlayer.duration;
  int? get currentIndex => _mainPlayer.currentIndex;
  bool get isBuffering =>
      _mainPlayer.processingState == ProcessingState.buffering;
  bool get isReady => _mainPlayer.processingState == ProcessingState.ready;
  ProcessingState get processingState => _mainPlayer.processingState;

  Future<void> dispose() async {
    try {
      await _mainPlayer.dispose();
      await _overlayPlayer.dispose();
      await _pacingPlayer.dispose();
      await _introPlayer.dispose();
    } catch (e) {
      debugPrint('AudioManager: Error disposing: $e');
    }
  }
}
