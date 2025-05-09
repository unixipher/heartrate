import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

class AudioManager {
  static final AudioManager _instance = AudioManager._internal();
  final AudioPlayer _mainPlayer = AudioPlayer();
  final AudioPlayer _overlayPlayer = AudioPlayer();
  AudioPlayer _pacingPlayer = AudioPlayer();
  bool _isPlaying = false;

  factory AudioManager() => _instance;

  AudioManager._internal();

  AudioPlayer get audioPlayer => _mainPlayer;

  bool get isPlaying => _isPlaying;

  Future<void> play(String url, {Duration? seekTo}) async {
    await _mainPlayer.stop();
    await _mainPlayer.play(UrlSource(url));
    _isPlaying = true;
  }

  Future<void> playOverlay(String assetPath) async {
    try {
      await _overlayPlayer.stop();
      await _overlayPlayer.play(AssetSource(assetPath));
    } catch (e) {
      debugPrint('Error playing overlay: $e');
    }
  }

  Future<void> playPacing(String assetPath, {double volume = 0.3}) async {
    try {
      await _pacingPlayer.stop();
      await _pacingPlayer.setVolume(volume);
      await _pacingPlayer.play(AssetSource(assetPath));
    } catch (e) {
      debugPrint('Error playing pacing: $e');
    }
  }

  void playPacingLoop(String path, {double volume = 0.3}) async {
    try {
      await _pacingPlayer.stop();
      _pacingPlayer = AudioPlayer();
      await _pacingPlayer.setReleaseMode(ReleaseMode.loop);
      await _pacingPlayer.setVolume(volume);
      await _pacingPlayer.play(AssetSource(path));
    } catch (e) {
      debugPrint('Error playing pacing loop: $e');
    }
  }

  void stopPacing() async {
    await _pacingPlayer.stop();
  }

  Future<void> pause() async {
    await _mainPlayer.pause();
    await _pacingPlayer.pause();
    _isPlaying = false;
  }

  Future<void> resume() async {
    await _mainPlayer.resume();
    await _pacingPlayer.resume();
    _isPlaying = true;
  }

  Future<void> stop() async {
    await _mainPlayer.stop();
    await _overlayPlayer.stop();
    await _pacingPlayer.stop();
    _isPlaying = false;
  }

  Future<void> dispose() async {
    await _mainPlayer.dispose();
    await _overlayPlayer.dispose();
    await _pacingPlayer.dispose();
  }
}
