import 'package:just_audio/just_audio.dart';
import 'package:flutter/material.dart';

class AudioManager {
  static final AudioManager _instance = AudioManager._internal();
  final AudioPlayer _mainPlayer = AudioPlayer();
  final AudioPlayer _overlayPlayer = AudioPlayer();
  AudioPlayer _pacingPlayer = AudioPlayer();

  factory AudioManager() => _instance;

  AudioManager._internal() {
    _mainPlayer.playerStateStream.listen((state) {
      debugPrint(
          'Player state: ${state.processingState}, playing: ${state.playing}');
    });
  }

  AudioPlayer get audioPlayer => _mainPlayer;
  bool get isPlaying => _mainPlayer.playing;

  // Stream getters
  Stream<Duration> get positionStream => _mainPlayer.positionStream;
  Stream<Duration?> get durationStream => _mainPlayer.durationStream;
  Stream<PlayerState> get playerStateStream => _mainPlayer.playerStateStream;
  Duration get bufferedPosition => _mainPlayer.bufferedPosition;

  Future<void> play(String url, {Duration? seekTo}) async {
    try {
      debugPrint('AudioManager: Playing URL: $url');

      // Validate URL format
      if (url.isEmpty || url == 'null') {
        throw Exception('Invalid audio URL: $url');
      }

      // Ensure proper URI formatting
      final uri = Uri.parse(url);
      if (!uri.isAbsolute) {
        throw Exception('Malformed audio URL: $url');
      }

      // Stop current playback
      await _mainPlayer.stop();

      // Set audio source with proper URI handling
      await _mainPlayer.setAudioSource(AudioSource.uri(uri));

      // Seek if needed
      if (seekTo != null) {
        await _mainPlayer.seek(seekTo);
      }

      // Start playback immediately
      await _mainPlayer.play();

      debugPrint('AudioManager: Play command sent successfully');
    } catch (e) {
      debugPrint('AudioManager: Error playing audio: $e');
      rethrow;
    }
  }

  Future<void> playOverlay(String assetPath) async {
    try {
      await _overlayPlayer.stop();
      await _overlayPlayer.setAsset(assetPath);
      await _overlayPlayer.play();
    } catch (e) {
      debugPrint('AudioManager: Error playing overlay: $e');
    }
  }

  Future<void> playPacing(String assetPath, {double volume = 0.3}) async {
    try {
      await _pacingPlayer.stop();
      await _pacingPlayer.setVolume(volume);
      await _pacingPlayer.setAsset(assetPath);
      await _pacingPlayer.play();
    } catch (e) {
      debugPrint('AudioManager: Error playing pacing: $e');
    }
  }

// In AudioManager
  Future<void> playPacingLoop(String path, {double volume = 0.3}) async {
    try {
      await _pacingPlayer.stop();
      // Remove player recreation - causes plugin errors
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
      await _pacingPlayer.play();
    } catch (e) {
      debugPrint('AudioManager: Error resuming: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _mainPlayer.stop();
      await _overlayPlayer.stop();
      await _pacingPlayer.stop();
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
  bool get isBuffering =>
      _mainPlayer.processingState == ProcessingState.buffering;
  bool get isReady => _mainPlayer.processingState == ProcessingState.ready;
  ProcessingState get processingState => _mainPlayer.processingState;

  Future<void> dispose() async {
    try {
      await _mainPlayer.dispose();
      await _overlayPlayer.dispose();
      await _pacingPlayer.dispose();
    } catch (e) {
      debugPrint('AudioManager: Error disposing: $e');
    }
  }
}
