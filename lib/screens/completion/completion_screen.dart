import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:confetti/confetti.dart';
import 'package:testingheartrate/screens/home/home_screen.dart';

class CompletionScreen extends StatefulWidget {
  final String storyName;
  final String backgroundImage;
  final int storyId;
  final double? maxheartRate;
  final int zoneId;

  const CompletionScreen({
    super.key,
    required this.storyName,
    required this.backgroundImage,
    required this.storyId,
    this.maxheartRate,
    required this.zoneId,
  });

  @override
  State<CompletionScreen> createState() => _CompletionScreenState();
}

class _CompletionScreenState extends State<CompletionScreen> {
  late ConfettiController _confettiController;

  @override
  void initState() {
    super.initState();
    _confettiController =
        ConfettiController(duration: const Duration(seconds: 10));
    _confettiController.play();

    Future.delayed(const Duration(seconds: 600), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    });
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  Future<String?> fetchCompletedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final url = Uri.parse('https://authcheck.co/userchallenge');

    final response = await http.get(
      url,
      headers: {
        'Accept': '/',
        'User-Agent': 'Thunder Client (https://www.thunderclient.com)',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final List<dynamic> challenges = json.decode(response.body);
      final challenge = challenges.firstWhere(
        (challenge) => challenge['id'] == widget.storyId,
        orElse: () => null,
      );
      return challenge?['completedAt'];
    } else {
      throw Exception('Failed to load challenges');
    }
  }

  Future<Map<String, dynamic>> analyseHeartRate() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final url = Uri.parse('https://authcheck.co/analyse');

    final response = await http.post(
      url,
      headers: {
        'Accept': '*/*',
        'User-Agent': 'Thunder Client (https://www.thunderclient.com)',
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        "challengeId": widget.storyId,
        "zoneId": widget.zoneId,
      }),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final heartRateData = data['heartRateData'] as List<dynamic>;
      final zoneId = data['zoneId'];

      double lowerBound, upperBound;
      if (zoneId == 1) {
        lowerBound = 0.5 * (widget.maxheartRate ?? 0);
        upperBound = 0.6 * (widget.maxheartRate ?? 0);
      } else if (zoneId == 2) {
        lowerBound = 0.6 * (widget.maxheartRate ?? 0);
        upperBound = 0.7 * (widget.maxheartRate ?? 0);
      } else if (zoneId == 3) {
        lowerBound = 0.7 * (widget.maxheartRate ?? 0);
        upperBound = 0.8 * (widget.maxheartRate ?? 0);
      } else {
        throw Exception('Invalid zoneId');
      }

      int insideZone = 0;
      int outsideZone = 0;
      int totalHeartRate = 0;

      for (var entry in heartRateData) {
        final heartRate = entry['heartRate'] as int;
        totalHeartRate += heartRate;
        if (heartRate >= lowerBound && heartRate <= upperBound) {
          insideZone++;
        } else {
          outsideZone++;
        }
      }

      double averageHeartRate = heartRateData.isNotEmpty
          ? totalHeartRate / heartRateData.length
          : 0.0;
      double percentageInsideZone = (insideZone / heartRateData.length) * 100;
      return {
        'insideZone': insideZone,
        'outsideZone': outsideZone,
        'averageHeartRate': averageHeartRate,
        'percentageInsideZone': percentageInsideZone,
      };
    } else {
      throw Exception('Failed to analyse heart rate');
    }
  }

  Path drawStar(Size size) {
    double w = size.width;
    double h = size.height;
    const int numPoints = 5;
    const double outerRadius = 10;
    const double innerRadius = 4;
    const double rotation = -pi / 2;

    final path = Path();
    const double step = pi / numPoints;
    for (int i = 0; i < numPoints * 2; i++) {
      final isEven = i % 2 == 0;
      final radius = isEven ? outerRadius : innerRadius;
      final angle = i * step + rotation;
      final x = radius * cos(angle) + w / 2;
      final y = radius * sin(angle) + h / 2;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  widget.backgroundImage,
                  fit: BoxFit.cover,
                ),
                Container(
                  color: Colors.black.withOpacity(0.5),
                ),
              ],
            ),
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 70.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.storyName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontFamily: 'TheWitcher',
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FutureBuilder<String?>(
                      future: fetchCompletedAt(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          );
                        } else if (snapshot.hasData && snapshot.data != null) {
                          final completedAt = DateTime.tryParse(snapshot.data!);
                          final formattedDate = completedAt != null
                              ? '${completedAt.year}-${completedAt.month.toString().padLeft(2, '0')}-${completedAt.day.toString().padLeft(2, '0')} '
                                  '${completedAt.hour.toString().padLeft(2, '0')}:${completedAt.minute.toString().padLeft(2, '0')}'
                              : 'Not Found';
                          return Text(
                            'Completed at: $formattedDate',
                            style: const TextStyle(
                              fontSize: 16,
                              fontFamily: 'Battambang',
                              color: Colors.white70,
                            ),
                          );
                        } else {
                          return const Text(
                            'Completed at: Not Found',
                            style: TextStyle(
                              fontSize: 16,
                              fontFamily: 'Battambang',
                              color: Colors.white70,
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const Align(
              alignment: Alignment(0, -0.4),
              child: Text(
                'Challenge Completed!',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'TheWitcher',
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      blurRadius: 10.0,
                      color: Colors.black,
                      offset: Offset(2.0, 2.0),
                    ),
                  ],
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TweenAnimationBuilder(
                    tween: Tween<double>(begin: 0, end: 1),
                    duration: const Duration(seconds: 600),
                    builder: (context, value, child) {
                      return SizedBox(
                        width: 100,
                        height: 100,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            GestureDetector(
                              onTap: () {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => HomeScreen(),
                                  ),
                                );
                              },
                              child: SizedBox(
                                width: 100,
                                height: 100,
                                child: CircularProgressIndicator(
                                  value: value,
                                  strokeWidth: 5,
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                  backgroundColor:
                                      Colors.white.withOpacity(0.3),
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => HomeScreen(),
                                  ),
                                );
                              },
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Container(
                                    width: 90,
                                    height: 90,
                                    decoration: BoxDecoration(
                                      color: Colors.purple.withOpacity(0.5),
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.purple.withOpacity(0.7),
                                          blurRadius: 20,
                                          spreadRadius: 5,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    width: 70,
                                    height: 70,
                                    decoration: const BoxDecoration(
                                      color: Colors.purple,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.fast_forward_rounded,
                                      size: 36,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Reveal Next Challenge',
                    style: TextStyle(
                      fontSize: 18,
                      fontFamily: 'Battambang',
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: FutureBuilder<Map<String, dynamic>>(
                  future: analyseHeartRate(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      );
                    } else if (snapshot.hasData) {
                      final insideZone = snapshot.data!['insideZone']!;
                      final outsideZone = snapshot.data!['outsideZone']!;
                      final averageHeartRate =
                          snapshot.data!['averageHeartRate'] as double;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 100.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Average Heart Rate: ${averageHeartRate.toStringAsFixed(1)} BPM',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 22,
                                fontFamily: 'Battambang',
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'You got ${insideZone + outsideZone} nudges to stay in the zone You were in the zone for ${snapshot.data!['percentageInsideZone'].toStringAsFixed(1)}%',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 22,
                                fontFamily: 'Battambang',
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Percentage Inside Zone: ${snapshot.data!['percentageInsideZone'].toStringAsFixed(1)}%',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 22,
                                fontFamily: 'Battambang',
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      );
                    } else {
                      return const Text(
                        'Failed to analyse heart rate.',
                        style: TextStyle(
                          fontSize: 16,
                          fontFamily: 'Battambang',
                          color: Colors.white70,
                        ),
                      );
                    }
                  },
                ),
              ),
            ),
            Align(
              alignment: Alignment.center,
              child: ConfettiWidget(
                confettiController: _confettiController,
                blastDirectionality: BlastDirectionality.explosive,
                emissionFrequency: 0.1,
                numberOfParticles: 8,
                shouldLoop: false,
                colors: const [
                  Colors.yellow,
                  Colors.white,
                  Colors.blue,
                  Colors.pink,
                ],
                createParticlePath: drawStar,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
