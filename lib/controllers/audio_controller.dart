import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

class AudioController {
  final AudioPlayer mainPlayer = AudioPlayer();
  final List<AudioPlayer> overlayPlayers = [];
  Timer? playbackTimer;
  int currentPlayTime = 0;
  double? currentHeartRate;
  final double maxHeartRate = 190.0;

  final List<int> timestamps = [
    107, 165, 212, 236, 279, 296, 420, 510,
    542, 605, 615, 636, 690, 740, 775, 795, 838
  ];

  final Map<int, bool> playedOverlays = {};

  final List<List<double>> targetRanges = [
    [0.50, 0.60], [0.60, 0.70], [0.60, 0.70], [0.64, 0.76], [0.64, 0.76],
    [0.64, 0.76], [0.77, 0.89], [0.77, 0.89], [0.77, 0.89], [0.77, 0.89],
    [0.64, 0.76], [0.64, 0.76], [0.64, 0.0],  [0.64, 0.0],  [0.64, 0.0],
    [0.64, 0.0],  [0.64, 0.0]
  ];

  Future<void> startMainTrack() async {
    try {
      await mainPlayer.setVolume(0.15);
      await mainPlayer.play(AssetSource('MainTrack_15.mp3'));
      _startPlaybackTimer();
    } catch (e) {
      debugPrint('Error playing main track: $e');
    }
  }

  void _startPlaybackTimer() {
    playbackTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      currentPlayTime = timer.tick;
      _checkForOverlay();
    });
  }

  void _checkForOverlay() {
    for (int i = 0; i < timestamps.length; i++) {
      if (currentPlayTime == timestamps[i] && playedOverlays[i] != true) {
        playedOverlays[i] = true;
        _playOverlay(i);
        break;
      }
    }
  }

  Future<void> _playOverlay(int index) async {
    if (index >= timestamps.length || currentHeartRate == null) return;
    try {
      String trackToPlay;
      double minTarget = maxHeartRate * targetRanges[index][0];
      double maxTarget = maxHeartRate * targetRanges[index][1];

      if (currentHeartRate! >= minTarget && currentHeartRate! <= maxTarget) {
        trackToPlay = 'A_${index + 1}.mp3';
      } else {
        trackToPlay = 'S_${index + 1}.mp3';
      }

      final overlayPlayer = AudioPlayer();
      overlayPlayers.add(overlayPlayer);
      await overlayPlayer.play(AssetSource(trackToPlay));
      overlayPlayer.onPlayerComplete.listen((_) {
        overlayPlayer.dispose();
        overlayPlayers.remove(overlayPlayer);
      });
    } catch (e) {
      debugPrint('Error playing overlay: $e');
    }
  }

  void dispose() {
    playbackTimer?.cancel();
    mainPlayer.dispose();
    for (var player in overlayPlayers) {
      player.dispose();
    }
  }
}