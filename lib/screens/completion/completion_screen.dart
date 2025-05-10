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
  final int timestampcount;
  final dynamic audioData;
  final int challengeCount;
  final int playingChallengeCount;

  const CompletionScreen({
    super.key,
    required this.storyName,
    required this.backgroundImage,
    required this.storyId,
    this.maxheartRate,
    required this.zoneId,
    required this.timestampcount,
    required this.audioData,
    required this.challengeCount,
    required this.playingChallengeCount,
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

    Future.delayed(const Duration(seconds: 6000), () {
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
        (challenge) => challenge['challengeId'] == widget.storyId,
        orElse: () => null,
      );
      debugPrint(widget.audioData.toString());
      return challenge?['completedAt'];
    } else {
      throw Exception('Failed to load challenges');
    }
  }

  Future<Map<String, dynamic>> analyseHeartRate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final url = Uri.parse('https://authcheck.co/analyse');

      final List<int> challengeIds =
          (widget.audioData as List).map((item) => item['id'] as int).toList();

      final response = await http.post(
        url,
        headers: {
          'Accept': '*/*',
          'User-Agent': 'Thunder Client (https://www.thunderclient.com)',
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          "challengeId": challengeIds,
          "zoneId": widget.zoneId,
        }),
      );
      debugPrint('Story ID: ${widget.storyId}');
      debugPrint('Zone ID: ${widget.zoneId}');
      debugPrint("Challenge IDs: $challengeIds");

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);

        List<dynamic> allHeartRateEntries = [];
        int? zoneId;
        for (var challenge in data) {
          if (zoneId == null && challenge['zoneId'] != null) {
            zoneId = challenge['zoneId'];
          }
          if (challenge['heartRateData'] != null) {
            allHeartRateEntries.addAll(challenge['heartRateData']);
          }
        }

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

        for (var entry in allHeartRateEntries) {
          final heartRate = entry['heartRate'] as int;
          totalHeartRate += heartRate;
          if (heartRate >= lowerBound && heartRate <= upperBound) {
            insideZone++;
          } else {
            outsideZone++;
          }
        }

        double averageHeartRate = allHeartRateEntries.isNotEmpty
            ? totalHeartRate / allHeartRateEntries.length
            : 0.0;
        double percentageInsideZone = allHeartRateEntries.isNotEmpty
            ? (insideZone / allHeartRateEntries.length) * 100
            : 0.0;
        return {
          'insideZone': insideZone,
          'outsideZone': outsideZone,
          'averageHeartRate': averageHeartRate,
          'percentageInsideZone': percentageInsideZone,
        };
      } else {
        throw Exception('Failed to analyse heart rate');
      }
    } catch (e) {
      debugPrint('Error in analyseHeartRate: $e');
      rethrow;
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
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text(
                    "Challenge Completed",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontFamily: 'TheWitcher',
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Completed ${widget.playingChallengeCount} out of ${widget.challengeCount} challenges',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontFamily: 'Battambang',
                      color: Colors.white,
                    ),
                  ),
                ]),
              ),
            ),
            Align(
              alignment: Alignment.center,
              child: Padding(
                padding: const EdgeInsets.only(top: 120.0, bottom: 150.0),
                child: SizedBox(
                  height: 500,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: (widget.audioData as List).length,
                    itemBuilder: (context, index) {
                      final item = (widget.audioData as List)[index];
                      return GestureDetector(
                        onTap: () {
                          debugPrint(
                              'Tapped on item: ${item['challengeName']}');
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                              vertical: 8, horizontal: 28),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: LinearGradient(
                              colors: [
                                Colors.white.withOpacity(0.15),
                                Colors.white.withOpacity(0.05),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.2),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ListTile(
                            title: item['challengeName'] != null &&
                                    item['challengeName'].length > 20
                                ? SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Text(
                                      item['challengeName'],
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontFamily: 'TheWitcher',
                                        fontWeight: FontWeight.bold,
                                        shadows: [
                                          Shadow(
                                            color: Colors.black26,
                                            blurRadius: 2,
                                            offset: Offset(1, 1),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : Text(
                                    item['challengeName'] ?? 'No Title',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontFamily: 'TheWitcher',
                                      fontWeight: FontWeight.bold,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black26,
                                          blurRadius: 2,
                                          offset: Offset(1, 1),
                                        ),
                                      ],
                                    ),
                                  ),
                            leading: const Icon(
                              Icons.check_circle,
                              color: Colors.lightGreen,
                              size: 30,
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Zone: ${item['zoneId'] == 1 ? 'Walk' : item['zoneId'] == 2 ? 'Jog' : item['zoneId'] == 3 ? 'Run' : 'No Zone'}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 16,
                                    fontFamily: 'Battambang',
                                  ),
                                ),
                                const SizedBox(height: 4),
                                FutureBuilder<String?>(
                                  future: fetchCompletedAt(),
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState ==
                                        ConnectionState.waiting) {
                                      return const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      );
                                    } else if (snapshot.hasData &&
                                        snapshot.data != null) {
                                      final completedAt =
                                          DateTime.tryParse(snapshot.data!);
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
                                          fontSize: 14,
                                          fontFamily: 'Battambang',
                                          color: Colors.white54,
                                        ),
                                      );
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 40.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FutureBuilder<Map<String, dynamic>>(
                      future: analyseHeartRate(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const CircularProgressIndicator(
                            color: Colors.white,
                          );
                        } else if (snapshot.hasData && snapshot.data != null) {
                          final averageHeartRate =
                              snapshot.data!['averageHeartRate'] ?? 0.0;
                          final percentageInsideZone =
                              snapshot.data!['percentageInsideZone'] ?? 0.0;
                          return Column(
                            children: [
                              Text(
                                "Avg Heart Rate: ${averageHeartRate.toStringAsFixed(1)}",
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  fontFamily: 'TheWitcher',
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "You got ${widget.timestampcount} nudges to stay in the zone.",
                                style: const TextStyle(
                                  fontSize: 18,
                                  color: Colors.white70,
                                  fontFamily: 'Battambang',
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'You were in the zone for ${percentageInsideZone.toStringAsFixed(1)}% of the time',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontFamily: 'Battambang',
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          );
                        } else {
                          return Column(
                            children: [
                              const Text(
                                "Avg Heart Rate: N/A",
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  fontFamily: 'TheWitcher',
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "You got ${widget.timestampcount} nudges to stay in the zone.",
                                style: const TextStyle(
                                  fontSize: 18,
                                  color: Colors.white70,
                                  fontFamily: 'Battambang',
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Could not calculate zone time.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 22,
                                  fontFamily: 'Battambang',
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          );
                        }
                      },
                    )
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
