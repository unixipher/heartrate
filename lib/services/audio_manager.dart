import 'package:audioplayers/audioplayers.dart';

class AudioManager {
  static final AudioManager _instance = AudioManager._internal();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;

  factory AudioManager() {
    return _instance;
  }

  AudioManager._internal();

  AudioPlayer get audioPlayer => _audioPlayer;

  bool get isPlaying => _isPlaying;

  Future<void> play(String url, {Duration? seekTo}) async {
    await _audioPlayer.stop();
    await _audioPlayer.play(UrlSource(url));
    _isPlaying = true;
  }

  Future<void> pause() async {
    await _audioPlayer.pause();
    _isPlaying = false;
  }

  Future<void> resume() async {
    await _audioPlayer.resume();
    _isPlaying = true;
  }

  Future<void> stop() async {
    await _audioPlayer.stop();
    _isPlaying = false;
  }

  void dispose() {}
}