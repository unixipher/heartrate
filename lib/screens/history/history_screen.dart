import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with SingleTickerProviderStateMixin {
  List<dynamic> completedChallenges = [];
  List<dynamic> workoutHistory = [];
  Map<String, dynamic>? userData;
  bool isLoading = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    fetchCompletedChallenges();
    fetchWorkoutHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> fetchCompletedChallenges() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';
      final response = await http.get(
        Uri.parse('https://authcheck.co/getuser'),
        headers: {
          'Accept': '*/*',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final userChallenges = data['user']['UserChallenge'] as List<dynamic>;
        setState(() {
          userData = data['user'];
          completedChallenges = userChallenges
              .where((challenge) => challenge['completedAt'] != null)
              .toList();
          workoutHistory = data['user']['Workout'] ?? [];
          isLoading = false;
        });
      } else {
        throw Exception('Failed to load challenges');
      }
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Error fetching challenges',
            style: TextStyle(
              color: Colors.black,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          backgroundColor: Colors.white,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          width: 180,
        ),
      );
      debugPrint('Error fetching challenges: $e');
    }
  }

  // Fetch workout history from the same getuser endpoint
  Future<void> fetchWorkoutHistory() async {
    // Workout history is now fetched along with completed challenges
    // in the fetchCompletedChallenges method
  }

  Future<Map<String, dynamic>> analyzeWorkoutData(
      Map<String, dynamic> workout) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final url = Uri.parse('https://authcheck.co/analyse');

      final challengeIds = List<int>.from(workout['challengeIds'] ?? []);

      if (challengeIds.isEmpty) {
        return {};
      }

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
          "zoneId": 1, // Default zone, can be adjusted based on your needs
        }),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);

        List<dynamic> allHeartRateEntries = [];
        int? responseZoneId;
        for (var challengeData in data) {
          if (responseZoneId == null && challengeData['zoneId'] != null) {
            responseZoneId = challengeData['zoneId'];
          }
          if (challengeData['heartRateData'] != null) {
            allHeartRateEntries.addAll(challengeData['heartRateData']);
          }
        }

        if (allHeartRateEntries.isEmpty) return {};

        final maxHR = userData?['maxhr']?.toDouble() ?? 200.0;
        double lowerBound, upperBound;

        final zoneIdToUse = responseZoneId ?? 1;
        if (zoneIdToUse == 1) {
          lowerBound = (72 + (maxHR - 72) * 0.35).toDouble(); // 35% intensity
          upperBound = (72 + (maxHR - 72) * 0.75).toDouble(); // 75% intensity
        } else if (zoneIdToUse == 2) {
          lowerBound = (72 + (maxHR - 72) * 0.45).toDouble(); // 45% intensity
          upperBound = (72 + (maxHR - 72) * 0.85).toDouble(); // 85% intensity
        } else if (zoneIdToUse == 3) {
          lowerBound = (72 + (maxHR - 72) * 0.55).toDouble(); // 55% intensity
          upperBound = (72 + (maxHR - 72) * 0.95).toDouble(); // 95% intensity
        } else {
          throw Exception('Invalid zoneId');
        }

        int insideZone = 0;
        int outsideZone = 0;
        double totalHeartRate = 0.0;

        for (var entry in allHeartRateEntries) {
          final heartRate = (entry['heartRate'] as num).toDouble();
          totalHeartRate += heartRate;
          if (heartRate >= lowerBound && heartRate <= upperBound) {
            insideZone++;
          } else {
            outsideZone++;
          }
        }

        double averageHeartRate = totalHeartRate / allHeartRateEntries.length;
        double percentageInsideZone =
            (insideZone / allHeartRateEntries.length) * 100;

        return {
          'watchData': allHeartRateEntries,
          'heartRates': allHeartRateEntries.map((e) => e['heartRate']).toList(),
          'averageHR': averageHeartRate,
          'insideZone': insideZone,
          'outsideZone': outsideZone,
          'zoneThreshold': lowerBound,
          'upperBound': upperBound,
          'lowerBound': lowerBound,
          'percentageInsideZone': percentageInsideZone,
          'zoneId': zoneIdToUse,
          'challengeIds': challengeIds,
        };
      } else {
        throw Exception('Failed to analyse workout data');
      }
    } catch (e) {
      debugPrint('Error in analyzeWorkoutData: $e');
      return {};
    }
  }

  Future<Map<String, dynamic>> analyzeHeartRateData(
      Map<String, dynamic> challenge) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final url = Uri.parse('https://authcheck.co/analyse');

      final challengeId = challenge['challengeId'];
      final zoneId = challenge['challenge']?['zoneId'] ?? 1;

      final response = await http.post(
        url,
        headers: {
          'Accept': '*/*',
          'User-Agent': 'Thunder Client (https://www.thunderclient.com)',
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          "challengeId": [challengeId],
          "zoneId": zoneId,
        }),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);

        List<dynamic> allHeartRateEntries = [];
        int? responseZoneId;
        for (var challengeData in data) {
          if (responseZoneId == null && challengeData['zoneId'] != null) {
            responseZoneId = challengeData['zoneId'];
          }
          if (challengeData['heartRateData'] != null) {
            allHeartRateEntries.addAll(challengeData['heartRateData']);
          }
        }

        if (allHeartRateEntries.isEmpty) return {};

        final maxHR = userData?['maxhr']?.toDouble() ?? 200.0;
        double lowerBound, upperBound;

        final zoneIdToUse = responseZoneId ?? zoneId;
        if (zoneIdToUse == 1) {
          lowerBound = (72 + (maxHR - 72) * 0.35).toDouble(); // 35% intensity
          upperBound = (72 + (maxHR - 72) * 0.75).toDouble(); // 75% intensity
        } else if (zoneIdToUse == 2) {
          lowerBound = (72 + (maxHR - 72) * 0.45).toDouble(); // 45% intensity
          upperBound = (72 + (maxHR - 72) * 0.85).toDouble(); // 85% intensity
        } else if (zoneIdToUse == 3) {
          lowerBound = (72 + (maxHR - 72) * 0.55).toDouble(); // 55% intensity
          upperBound = (72 + (maxHR - 72) * 0.95).toDouble(); // 95% intensity
        } else {
          throw Exception('Invalid zoneId');
        }

        int insideZone = 0;
        int outsideZone = 0;
        double totalHeartRate = 0.0;

        for (var entry in allHeartRateEntries) {
          final heartRate = (entry['heartRate'] as num).toDouble();
          totalHeartRate += heartRate;
          if (heartRate >= lowerBound && heartRate <= upperBound) {
            insideZone++;
          } else {
            outsideZone++;
          }
        }

        double averageHeartRate = totalHeartRate / allHeartRateEntries.length;
        double percentageInsideZone =
            (insideZone / allHeartRateEntries.length) * 100;

        return {
          'watchData': allHeartRateEntries,
          'heartRates': allHeartRateEntries.map((e) => e['heartRate']).toList(),
          'averageHR': averageHeartRate,
          'insideZone': insideZone,
          'outsideZone': outsideZone,
          'zoneThreshold': lowerBound,
          'upperBound': upperBound,
          'lowerBound': lowerBound,
          'percentageInsideZone': percentageInsideZone,
          'zoneId': zoneIdToUse,
        };
      } else {
        throw Exception('Failed to analyse heart rate');
      }
    } catch (e) {
      debugPrint('Error in analyzeHeartRateData: $e');
      return {};
    }
  }

  void showHeartRateAnalytics(Map<String, dynamic> challenge) async {
    // Show loading first
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A0D29),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(20),
          child: const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        );
      },
    );

    final analytics = await analyzeHeartRateData(challenge);

    // Close loading modal
    Navigator.of(context).pop();

    if (analytics.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'No heart rate data',
            style: TextStyle(
              color: Colors.black,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          backgroundColor: Colors.white,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          width: 180,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A0D29),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        final zoneType = analytics['zoneId'] == 1
            ? 'Walk'
            : analytics['zoneId'] == 2
                ? 'Jog'
                : 'Run';

        return Container(
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        challenge['challenge']['title'] ??
                            'Challenge Analytics',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Average Heart Rate
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Average Heart Rate',
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${analytics['averageHR'].toStringAsFixed(1)} BPM',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Zone Info
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$zoneType Zone (${analytics['lowerBound'].toInt()}-${analytics['upperBound'].toInt()} BPM)',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${analytics['percentageInsideZone'].toStringAsFixed(1)}% Time in Zone',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Heart Rate Line Chart
                const Text(
                  'Heart Rate Over Time',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),

                Container(
                  height: 350,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withOpacity(0.15),
                        Colors.white.withOpacity(0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: LineChart(
                    LineChartData(
                      lineTouchData: LineTouchData(
                        enabled: true,
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipItems: (touchedSpots) {
                            return touchedSpots.map((touchedSpot) {
                              if (touchedSpot.barIndex == 0) {
                                // Heart rate line
                                return LineTooltipItem(
                                  'Heart Rate\n${touchedSpot.y.toInt()} BPM',
                                  const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                );
                              } else if (touchedSpot.barIndex == 1) {
                                // Lower bound line
                                return LineTooltipItem(
                                  'Target Zone Lower\n${touchedSpot.y.toInt()} BPM',
                                  const TextStyle(
                                    color: Color(0xFF00FF88),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                );
                              } else if (touchedSpot.barIndex == 2) {
                                // Upper bound line
                                return LineTooltipItem(
                                  'Target Zone Upper\n${touchedSpot.y.toInt()} BPM',
                                  const TextStyle(
                                    color: Color(0xFF00FF88),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                );
                              }
                              return null;
                            }).toList();
                          },
                        ),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: true,
                        horizontalInterval: 20,
                        verticalInterval:
                            analytics['watchData'].length > 30 ? 3 : 1,
                        getDrawingHorizontalLine: (value) {
                          return FlLine(
                            color: Colors.white.withOpacity(0.15),
                            strokeWidth: 0.8,
                            dashArray: [3, 3],
                          );
                        },
                        getDrawingVerticalLine: (value) {
                          return FlLine(
                            color: Colors.white.withOpacity(0.1),
                            strokeWidth: 0.5,
                            dashArray: [2, 4],
                          );
                        },
                      ),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 50,
                            getTitlesWidget: (value, meta) {
                              return Text(
                                '${value.toInt()}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              );
                            },
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            interval: analytics['watchData'].length > 10
                                ? (analytics['watchData'].length / 5)
                                    .ceilToDouble()
                                : 1,
                            getTitlesWidget: (value, meta) {
                              if (value.toInt() >= 0 &&
                                  value.toInt() <
                                      analytics['watchData'].length) {
                                final data =
                                    analytics['watchData'][value.toInt()];
                                try {
                                  final timestamp = DateTime.parse(
                                      data['createdAt']?.toString() ?? '');
                                  final istTimestamp = timestamp.add(
                                      const Duration(hours: 5, minutes: 30));
                                  final formatter = DateFormat('HH:mm');
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Text(
                                      formatter.format(istTimestamp),
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 10,
                                      ),
                                    ),
                                  );
                                } catch (e) {
                                  return const Padding(
                                    padding: EdgeInsets.only(top: 8.0),
                                    child: Text(
                                      '--:--',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 10,
                                      ),
                                    ),
                                  );
                                }
                              }
                              return const Text('');
                            },
                          ),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      borderData: FlBorderData(
                        show: true,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                          width: 1.5,
                        ),
                      ),
                      minX: 0,
                      maxX: (analytics['watchData'].length - 1).toDouble(),
                      minY: [
                        analytics['heartRates']
                                .reduce((a, b) => a < b ? a : b)
                                .toDouble() -
                            10,
                        analytics['lowerBound'] - 20,
                      ].reduce((a, b) => a < b ? a : b),
                      maxY: [
                        analytics['heartRates']
                                .reduce((a, b) => a > b ? a : b)
                                .toDouble() +
                            10,
                        analytics['upperBound'] + 20,
                      ].reduce((a, b) => a > b ? a : b),
                      lineBarsData: [
                        // Heart rate line with gradient
                        LineChartBarData(
                          spots: List.generate(
                            analytics['watchData'].length,
                            (index) => FlSpot(
                              index.toDouble(),
                              analytics['watchData'][index]['heartRate']
                                  .toDouble(),
                            ),
                          ),
                          isCurved: true,
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF00D4FF),
                              const Color(0xFF0099FF),
                              const Color(0xFF0066FF),
                            ],
                          ),
                          barWidth: 4,
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                const Color(0xFF00D4FF).withOpacity(0.3),
                                const Color(0xFF0099FF).withOpacity(0.1),
                                Colors.transparent,
                              ],
                            ),
                          ),
                          dotData: FlDotData(
                            show: analytics['watchData'].length <= 50,
                            getDotPainter: (spot, percent, barData, index) {
                              return FlDotCirclePainter(
                                radius: 2.5,
                                color: Colors.white,
                                strokeWidth: 1.5,
                                strokeColor: const Color(0xFF0099FF),
                              );
                            },
                          ),
                        ),
                        // Target zone lower bound
                        LineChartBarData(
                          spots: List.generate(
                            analytics['watchData'].length,
                            (index) => FlSpot(
                              index.toDouble(),
                              analytics['lowerBound'].toDouble(),
                            ),
                          ),
                          isCurved: false,
                          color: const Color(0xFF00FF88),
                          barWidth: 2.5,
                          belowBarData: BarAreaData(show: false),
                          dotData: const FlDotData(show: false),
                          dashArray: [8, 4],
                        ),
                        // Target zone upper bound
                        LineChartBarData(
                          spots: List.generate(
                            analytics['watchData'].length,
                            (index) => FlSpot(
                              index.toDouble(),
                              analytics['upperBound'].toDouble(),
                            ),
                          ),
                          isCurved: false,
                          color: const Color(0xFF00FF88),
                          barWidth: 2.5,
                          belowBarData: BarAreaData(show: false),
                          dotData: const FlDotData(show: false),
                          dashArray: [8, 4],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Legend
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 24,
                          height: 4,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF00D4FF),
                                Color(0xFF0099FF),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Heart Rate',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Container(
                          width: 24,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFF00FF88),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Target Zone',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void showWorkoutAnalytics(Map<String, dynamic> workout) async {
    // Show loading first
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A0D29),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(20),
          child: const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        );
      },
    );

    final analytics = await analyzeWorkoutData(workout);

    // Close loading modal
    Navigator.of(context).pop();

    if (analytics.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'No heart rate data',
            style: TextStyle(
              color: Colors.black,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          backgroundColor: Colors.white,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          width: 180,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A0D29),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        final zoneType = analytics['zoneId'] == 1
            ? 'Walk'
            : analytics['zoneId'] == 2
                ? 'Jog'
                : 'Run';

        Duration duration = Duration.zero;
        String formattedDuration = '0h 0m 0s';

        try {
          if (workout['startTime'] != null && workout['endTime'] != null) {
            final startTime = DateTime.parse(workout['startTime'].toString());
            final endTime = DateTime.parse(workout['endTime'].toString());
            duration = endTime.difference(startTime);
            formattedDuration =
                '${duration.inHours}h ${duration.inMinutes.remainder(60)}m ${duration.inSeconds.remainder(60)}s';
          }
        } catch (e) {
          debugPrint('Error parsing workout duration: $e');
        }

        return Container(
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Workout Analytics',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Workout Info
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Workout Duration',
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        formattedDuration,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Challenges: ${analytics['challengeIds'].length}',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Average Heart Rate
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Average Heart Rate',
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${analytics['averageHR'].toStringAsFixed(1)} BPM',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Zone Info
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$zoneType Zone (${analytics['lowerBound'].toInt()}-${analytics['upperBound'].toInt()} BPM)',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${analytics['percentageInsideZone'].toStringAsFixed(1)}% Time in Zone',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Heart Rate Line Chart
                const Text(
                  'Heart Rate Over Time',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),

                Container(
                  height: 350,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withOpacity(0.15),
                        Colors.white.withOpacity(0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: LineChart(
                    LineChartData(
                      lineTouchData: LineTouchData(
                        enabled: true,
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipItems: (touchedSpots) {
                            return touchedSpots.map((touchedSpot) {
                              if (touchedSpot.barIndex == 0) {
                                // Heart rate line
                                return LineTooltipItem(
                                  'Heart Rate\n${touchedSpot.y.toInt()} BPM',
                                  const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                );
                              } else if (touchedSpot.barIndex == 1) {
                                // Lower bound line
                                return LineTooltipItem(
                                  'Target Zone Lower\n${touchedSpot.y.toInt()} BPM',
                                  const TextStyle(
                                    color: Color(0xFF00FF88),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                );
                              } else if (touchedSpot.barIndex == 2) {
                                // Upper bound line
                                return LineTooltipItem(
                                  'Target Zone Upper\n${touchedSpot.y.toInt()} BPM',
                                  const TextStyle(
                                    color: Color(0xFF00FF88),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                );
                              }
                              return null;
                            }).toList();
                          },
                        ),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: true,
                        horizontalInterval: 20,
                        verticalInterval:
                            analytics['watchData'].length > 30 ? 3 : 1,
                        getDrawingHorizontalLine: (value) {
                          return FlLine(
                            color: Colors.white.withOpacity(0.15),
                            strokeWidth: 0.8,
                            dashArray: [3, 3],
                          );
                        },
                        getDrawingVerticalLine: (value) {
                          return FlLine(
                            color: Colors.white.withOpacity(0.1),
                            strokeWidth: 0.5,
                            dashArray: [2, 4],
                          );
                        },
                      ),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 50,
                            getTitlesWidget: (value, meta) {
                              return Text(
                                '${value.toInt()}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              );
                            },
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            interval: analytics['watchData'].length > 10
                                ? (analytics['watchData'].length / 5)
                                    .ceilToDouble()
                                : 1,
                            getTitlesWidget: (value, meta) {
                              if (value.toInt() >= 0 &&
                                  value.toInt() <
                                      analytics['watchData'].length) {
                                final data =
                                    analytics['watchData'][value.toInt()];
                                try {
                                  final timestamp = DateTime.parse(
                                      data['createdAt']?.toString() ?? '');
                                  final istTimestamp = timestamp.add(
                                      const Duration(hours: 5, minutes: 30));
                                  final formatter = DateFormat('HH:mm');
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Text(
                                      formatter.format(istTimestamp),
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 10,
                                      ),
                                    ),
                                  );
                                } catch (e) {
                                  return const Padding(
                                    padding: EdgeInsets.only(top: 8.0),
                                    child: Text(
                                      '--:--',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 10,
                                      ),
                                    ),
                                  );
                                }
                              }
                              return const Text('');
                            },
                          ),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      borderData: FlBorderData(
                        show: true,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                          width: 1.5,
                        ),
                      ),
                      minX: 0,
                      maxX: (analytics['watchData'].length - 1).toDouble(),
                      minY: [
                        analytics['heartRates']
                                .reduce((a, b) => a < b ? a : b)
                                .toDouble() -
                            10,
                        analytics['lowerBound'] - 20,
                      ].reduce((a, b) => a < b ? a : b),
                      maxY: [
                        analytics['heartRates']
                                .reduce((a, b) => a > b ? a : b)
                                .toDouble() +
                            10,
                        analytics['upperBound'] + 20,
                      ].reduce((a, b) => a > b ? a : b),
                      lineBarsData: [
                        // Heart rate line with gradient
                        LineChartBarData(
                          spots: List.generate(
                            analytics['watchData'].length,
                            (index) => FlSpot(
                              index.toDouble(),
                              analytics['watchData'][index]['heartRate']
                                  .toDouble(),
                            ),
                          ),
                          isCurved: true,
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFFFF6B6B),
                              const Color(0xFFFF8E53),
                              const Color(0xFFFF6B35),
                            ],
                          ),
                          barWidth: 4,
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                const Color(0xFFFF6B6B).withOpacity(0.3),
                                const Color(0xFFFF8E53).withOpacity(0.1),
                                Colors.transparent,
                              ],
                            ),
                          ),
                          dotData: FlDotData(
                            show: analytics['watchData'].length <= 50,
                            getDotPainter: (spot, percent, barData, index) {
                              return FlDotCirclePainter(
                                radius: 2.5,
                                color: Colors.white,
                                strokeWidth: 1.5,
                                strokeColor: const Color(0xFFFF6B35),
                              );
                            },
                          ),
                        ),
                        // Target zone lower bound
                        LineChartBarData(
                          spots: List.generate(
                            analytics['watchData'].length,
                            (index) => FlSpot(
                              index.toDouble(),
                              analytics['lowerBound'].toDouble(),
                            ),
                          ),
                          isCurved: false,
                          color: const Color(0xFF00FF88),
                          barWidth: 2.5,
                          belowBarData: BarAreaData(show: false),
                          dotData: const FlDotData(show: false),
                          dashArray: [8, 4],
                        ),
                        // Target zone upper bound
                        LineChartBarData(
                          spots: List.generate(
                            analytics['watchData'].length,
                            (index) => FlSpot(
                              index.toDouble(),
                              analytics['upperBound'].toDouble(),
                            ),
                          ),
                          isCurved: false,
                          color: const Color(0xFF00FF88),
                          barWidth: 2.5,
                          belowBarData: BarAreaData(show: false),
                          dotData: const FlDotData(show: false),
                          dashArray: [8, 4],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Legend
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 24,
                          height: 4,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFFFF6B6B),
                                Color(0xFFFF8E53),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Heart Rate',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Container(
                          width: 24,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFF00FF88),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Target Zone',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWorkoutHistoryTab() {
    return RefreshIndicator(
      onRefresh: fetchCompletedChallenges,
      child: ListView.builder(
        itemCount: workoutHistory.length,
        itemBuilder: (context, index) {
          final workout = workoutHistory[index];

          // Safe parsing of start and end times
          DateTime? startTime;
          DateTime? endTime;
          Duration duration = Duration.zero;
          String formattedDate = 'Invalid Date';

          try {
            if (workout['startTime'] != null) {
              startTime = DateTime.parse(workout['startTime'].toString());
              formattedDate =
                  DateFormat('MMM dd, yyyy HH:mm').format(startTime.toLocal());
            }
            if (workout['endTime'] != null) {
              endTime = DateTime.parse(workout['endTime'].toString());
            }
            if (startTime != null && endTime != null) {
              duration = endTime.difference(startTime);
            }
          } catch (e) {
            debugPrint('Error parsing workout times: $e');
          }

          final formattedDuration =
              '${duration.inHours}h ${duration.inMinutes.remainder(60)}m ${duration.inSeconds.remainder(60)}s';
          final challengeCount =
              (workout['challengeIds'] as List?)?.length ?? 0;

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            color: Colors.white10,
            child: InkWell(
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              onTap: () {
                showWorkoutAnalytics(workout);
              },
              child: ListTile(
                leading: const Icon(Icons.fitness_center, color: Colors.white),
                title: Text(
                  'Workout #${index + 1}',
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Duration: $formattedDuration',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    Text(
                      'Challenges: $challengeCount',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    Text(
                      formattedDate,
                      style: const TextStyle(color: Colors.white54),
                    ),
                  ],
                ),
                trailing: const Icon(Icons.show_chart, color: Colors.white),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildChallengeHistoryTab() {
    return RefreshIndicator(
      onRefresh: fetchCompletedChallenges,
      child: ListView.builder(
        itemCount: completedChallenges.length,
        itemBuilder: (context, index) {
          final challenge = completedChallenges[index];

          // Parse and format the timestamp to local time
          String formattedCompletedAt = 'No Timestamp';
          if (challenge['completedAt'] != null) {
            try {
              final completedAtUtc =
                  DateTime.parse(challenge['completedAt'].toString());
              final completedAtLocal = completedAtUtc.toLocal();
              formattedCompletedAt =
                  DateFormat('MMM dd, yyyy HH:mm').format(completedAtLocal);
              debugPrint('⏰⏰⏰Formatted Completed At: $formattedCompletedAt');
            } catch (e) {
              formattedCompletedAt =
                  challenge['completedAt']?.toString() ?? 'Invalid Date';
            }
          }

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            color: Colors.white10,
            child: InkWell(
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              onTap: () {
                showHeartRateAnalytics(challenge);
              },
              child: ListTile(
                leading: const Icon(Icons.music_note, color: Colors.white),
                title: Text(
                  challenge['challenge']['title'] ?? 'No Title',
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      challenge['challenge']['story']?['title'] ?? 'No Story',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    Text(
                      formattedCompletedAt,
                      style: const TextStyle(color: Colors.white54),
                    ),
                  ],
                ),
                trailing: const Icon(Icons.check_circle, color: Colors.white),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0D29),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0A0D29),
          title: const Text(
            'History',
            style: TextStyle(
              fontFamily: 'TheWitcher',
              color: Colors.white,
            ),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            tabs: const [
              Tab(
                icon: Icon(Icons.fitness_center),
                text: 'Workout History',
              ),
              Tab(
                icon: Icon(Icons.music_note),
                text: 'Challenge History',
              ),
            ],
          ),
        ),
        body: isLoading
            ? const Center(
                child: CircularProgressIndicator(
                color: Colors.white,
              ))
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildWorkoutHistoryTab(),
                  _buildChallengeHistoryTab(),
                ],
              ),
      ),
    );
  }
}
