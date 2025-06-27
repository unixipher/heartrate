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

class _HistoryScreenState extends State<HistoryScreen> {
  List<dynamic> completedChallenges = [];
  Map<String, dynamic>? userData;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchCompletedChallenges();
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
        const SnackBar(
          content: Text('No heart rate data available for this challenge'),
          backgroundColor: Colors.orange,
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
                  height: 300,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: LineChart(
                    LineChartData(
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: true,
                        horizontalInterval: 20,
                        verticalInterval: 1,
                        getDrawingHorizontalLine: (value) {
                          return FlLine(
                            color: Colors.white24,
                            strokeWidth: 1,
                          );
                        },
                        getDrawingVerticalLine: (value) {
                          return FlLine(
                            color: Colors.white24,
                            strokeWidth: 1,
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
                                final timestamp =
                                    DateTime.parse(data['createdAt']);
                                final istTimestamp = timestamp
                                    .add(const Duration(hours: 5, minutes: 30));
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
                        border: Border.all(color: Colors.white24),
                      ),
                      minX: 0,
                      maxX: (analytics['watchData'].length - 1).toDouble(),
                      minY: (analytics['heartRates']
                                  .reduce((a, b) => a < b ? a : b) -
                              10)
                          .toDouble(),
                      maxY: (analytics['heartRates']
                                  .reduce((a, b) => a > b ? a : b) +
                              10)
                          .toDouble(),
                      lineBarsData: [
                        // Heart rate line
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
                          color: Colors.blue,
                          barWidth: 3,
                          belowBarData: BarAreaData(show: false),
                          dotData: const FlDotData(show: false),
                        ),
                        // Zone bounds
                        LineChartBarData(
                          spots: List.generate(
                            analytics['watchData'].length,
                            (index) => FlSpot(
                              index.toDouble(),
                              analytics['lowerBound'].toDouble(),
                            ),
                          ),
                          isCurved: false,
                          color: Colors.green,
                          barWidth: 2,
                          belowBarData: BarAreaData(show: false),
                          dotData: const FlDotData(show: false),
                          dashArray: [5, 5],
                        ),
                        LineChartBarData(
                          spots: List.generate(
                            analytics['watchData'].length,
                            (index) => FlSpot(
                              index.toDouble(),
                              analytics['upperBound'].toDouble(),
                            ),
                          ),
                          isCurved: false,
                          color: Colors.transparent,
                          barWidth: 2,
                          belowBarData: BarAreaData(show: false),
                          dotData: const FlDotData(show: false),
                          dashArray: [5, 5],
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
                          width: 20,
                          height: 3,
                          color: Colors.blue,
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
                          width: 20,
                          height: 3,
                          color: Colors.green,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0D29),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0D29),
        title: const Text(
          style: TextStyle(
            fontFamily: 'TheWitcher',
            color: Colors.white,
          ),
          'Completed Challenges',
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(
              color: Colors.white,
            ))
          : RefreshIndicator(
              onRefresh: fetchCompletedChallenges,
              child: ListView.builder(
                itemCount: completedChallenges.length,
                itemBuilder: (context, index) {
                  final challenge = completedChallenges[index];
                  return Card(
                    margin:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    color: Colors.white10,
                    child: InkWell(
                      splashColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                      onTap: () {
                        showHeartRateAnalytics(challenge);
                      },
                      child: ListTile(
                        leading:
                            const Icon(Icons.music_note, color: Colors.white),
                        title: Text(
                          challenge['challenge']['title'] ?? 'No Title',
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              challenge['challenge']['story']?['title'] ??
                                  'No Story',
                              style: const TextStyle(color: Colors.white70),
                            ),
                            Text(
                              challenge['completedAt'] ?? 'No Timestamp',
                              style: const TextStyle(color: Colors.white54),
                            ),
                          ],
                        ),
                        trailing:
                            const Icon(Icons.check_circle, color: Colors.white),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
