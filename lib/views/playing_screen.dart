import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:testingheartrate/services/audio_manager.dart';
import 'package:testingheartrate/views/completion_screen.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class MusicPlayerScreen extends StatefulWidget {
  final String audioUrl;
  final int id;
  final String challengeName;
  final String image;
  final int zoneId;

  const MusicPlayerScreen(
      {super.key, required this.audioUrl, required this.id, required this.challengeName, required this.image, required this.zoneId});

  @override
  State<MusicPlayerScreen> createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends State<MusicPlayerScreen> {
  final AudioManager _audioManager = AudioManager();
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  @override
  void initState() {
    super.initState();

    _audioManager.audioPlayer.onDurationChanged.listen((Duration d) {
      setState(() {
        _totalDuration = d;
      });
    });

    _audioManager.audioPlayer.onPositionChanged.listen((Duration p) {
      setState(() {
        _currentPosition = p;
      });
    });

    _audioManager.audioPlayer.onPlayerComplete.listen((event) async {
      setState(() {
        _audioManager.stop();
      });

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';

      final int challengeId = widget.id;
      final Map<String, dynamic> requestBody = {
        'challengeId': challengeId,
        'status': true,
      };

      try {
        final response = await http.post(
          Uri.parse('https://authcheck.co/updatechallenge'),
          headers: {
            'Accept': '*/*',
            'User-Agent': 'Thunder Client (https://www.thunderclient.com)',
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(requestBody),
        );

        if (response.statusCode == 200) {
          debugPrint('Challenge updated successfully!');
        } else {
          debugPrint('Failed to update challenge: ${response.statusCode}');
        }
      } catch (e) {
        debugPrint('Error updating challenge: $e');
      } finally {
        debugPrint('Challenge ID: $challengeId');
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => CompletionScreen(storyName: widget.challengeName, backgroundImage: widget.image, storyId: widget.id)),
      );
    });

    _audioManager.play(widget.audioUrl);
  }

  void _togglePlayPause() {
    if (_audioManager.isPlaying) {
      _audioManager.pause();
    } else {
      _audioManager.resume();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _audioManager.dispose();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${twoDigits(duration.inMinutes)}:${twoDigits(duration.inSeconds.remainder(60))}";
  }

  @override
  Widget build(BuildContext context) {
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
        title: Text(
          widget.challengeName,
          style: const TextStyle(
            fontFamily: 'Thewitcher',
            fontSize: 24,
            letterSpacing: 2,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage(widget.image),
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
                  child: Icon(
                    _audioManager.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 80,
                  ),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        thumbColor: Colors.purpleAccent,
                        activeTrackColor: Colors.purpleAccent,
                        inactiveTrackColor: Colors.white30,
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
              const Spacer(flex: 2),
            ],
          ),
        ],
      ),
    );
  }
}
