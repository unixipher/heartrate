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
  List<dynamic> leaderboardData = [];
  Map<String, dynamic>? userData;
  bool isLoading = true;
  bool isLeaderboardLoading = false;
  String selectedLeaderboardType = 'global'; // 'global' or 'local'
  String currentCityName = 'Local'; // Default fallback
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    fetchCompletedChallenges();
    fetchWorkoutHistory();
    fetchLeaderboard();
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
        // Fetch current city after we have user data
        fetchCurrentCity();
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

  Future<void> fetchLeaderboard() async {
    setState(() {
      isLeaderboardLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';
      final response = await http.get(
        Uri.parse('https://authcheck.co/leaderboard'),
        headers: {
          'Accept': '*/*',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final dynamic responseData = json.decode(response.body);
        List<dynamic> data = [];

        // Handle different response formats
        if (responseData is List) {
          data = responseData;
        } else if (responseData is Map<String, dynamic>) {
          // If it's a map, check for common keys that might contain the user list
          if (responseData.containsKey('users')) {
            data = responseData['users'] as List<dynamic>;
          } else if (responseData.containsKey('leaderboard')) {
            data = responseData['leaderboard'] as List<dynamic>;
          } else if (responseData.containsKey('data')) {
            data = responseData['data'] as List<dynamic>;
          } else {
            // If it's a single user object, wrap it in a list
            data = [responseData];
          }
        }

        setState(() {
          leaderboardData = data;
          isLeaderboardLoading = false;
        });
      } else {
        throw Exception('Failed to load leaderboard');
      }
    } catch (e) {
      setState(() {
        isLeaderboardLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Error fetching leaderboard',
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
      debugPrint('Error fetching leaderboard: $e');
    }
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

      // Parse workout start and end times
      DateTime? workoutStartTime;
      DateTime? workoutEndTime;

      try {
        if (workout['startTime'] != null) {
          workoutStartTime = DateTime.parse(workout['startTime'].toString());
        }
        if (workout['endTime'] != null) {
          workoutEndTime = DateTime.parse(workout['endTime'].toString());
        }
      } catch (e) {
        debugPrint('Error parsing workout times: $e');
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
        List<dynamic> allSpeedEntries = [];
        int? responseZoneId;

        for (var challengeData in data) {
          if (responseZoneId == null && challengeData['zoneId'] != null) {
            responseZoneId = challengeData['zoneId'];
          }
          if (challengeData['heartRateData'] != null) {
            allHeartRateEntries.addAll(challengeData['heartRateData']);
          }
          if (challengeData['speedData'] != null) {
            allSpeedEntries.addAll(challengeData['speedData']);
          }
        }

        // Filter data by workout time range
        if (workoutStartTime != null && workoutEndTime != null) {
          debugPrint(
              'Filtering data for workout period: $workoutStartTime to $workoutEndTime');
          debugPrint(
              'Original heart rate entries: ${allHeartRateEntries.length}');
          debugPrint('Original speed entries: ${allSpeedEntries.length}');

          allHeartRateEntries = allHeartRateEntries.where((entry) {
            try {
              final entryTime = DateTime.parse(entry['createdAt'].toString());
              return entryTime.isAfter(workoutStartTime!) &&
                  entryTime.isBefore(workoutEndTime!);
            } catch (e) {
              debugPrint('Error parsing entry time: $e');
              return false;
            }
          }).toList();

          allSpeedEntries = allSpeedEntries.where((entry) {
            try {
              final entryTime = DateTime.parse(entry['createdAt'].toString());
              return entryTime.isAfter(workoutStartTime!) &&
                  entryTime.isBefore(workoutEndTime!);
            } catch (e) {
              debugPrint('Error parsing entry time: $e');
              return false;
            }
          }).toList();

          debugPrint(
              'Filtered heart rate entries: ${allHeartRateEntries.length}');
          debugPrint('Filtered speed entries: ${allSpeedEntries.length}');
        } else {
          debugPrint('No workout time range available, showing all data');
        }

        // Check if we have heart rate data, otherwise use speed data
        if (allHeartRateEntries.isNotEmpty) {
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
            'dataType': 'heart_rate',
            'watchData': allHeartRateEntries,
            'heartRates':
                allHeartRateEntries.map((e) => e['heartRate']).toList(),
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
        } else if (allSpeedEntries.isNotEmpty) {
          // Process speed data
          double totalSpeed = 0.0;
          double maxSpeed = 0.0;
          double minSpeed = double.infinity;

          // Define speed zone bounds (km/hr)
          final zoneIdToUse = responseZoneId ?? 1;
          double lowerBound, upperBound;

          if (zoneIdToUse == 1) {
            lowerBound = 4.0; // Zone 1: Walk
            upperBound = 6.0;
          } else if (zoneIdToUse == 2) {
            lowerBound = 6.01; // Zone 2: Jog
            upperBound = 8.0;
          } else if (zoneIdToUse == 3) {
            lowerBound = 8.01; // Zone 3: Run
            upperBound = 12.0;
          } else {
            lowerBound = 4.0; // Default to Zone 1
            upperBound = 6.0;
          }

          int insideZone = 0;
          int outsideZone = 0;

          for (var entry in allSpeedEntries) {
            final speed = (entry['speed'] as num).toDouble();
            totalSpeed += speed;
            if (speed > maxSpeed) maxSpeed = speed;
            if (speed < minSpeed) minSpeed = speed;

            if (speed >= lowerBound && speed <= upperBound) {
              insideZone++;
            } else {
              outsideZone++;
            }
          }

          double averageSpeed = totalSpeed / allSpeedEntries.length;
          double percentageInsideZone =
              (insideZone / allSpeedEntries.length) * 100;

          return {
            'dataType': 'speed',
            'watchData': allSpeedEntries,
            'speeds': allSpeedEntries.map((e) => e['speed']).toList(),
            'averageSpeed': averageSpeed,
            'maxSpeed': maxSpeed,
            'minSpeed': minSpeed,
            'lowerBound': lowerBound,
            'upperBound': upperBound,
            'insideZone': insideZone,
            'outsideZone': outsideZone,
            'percentageInsideZone': percentageInsideZone,
            'zoneId': zoneIdToUse,
            'challengeIds': challengeIds,
          };
        }

        return {};
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
        List<dynamic> allSpeedEntries = [];
        int? responseZoneId;

        for (var challengeData in data) {
          if (responseZoneId == null && challengeData['zoneId'] != null) {
            responseZoneId = challengeData['zoneId'];
          }
          if (challengeData['heartRateData'] != null) {
            allHeartRateEntries.addAll(challengeData['heartRateData']);
          }
          if (challengeData['speedData'] != null) {
            allSpeedEntries.addAll(challengeData['speedData']);
          }
        }

        debugPrint(
            'Challenge analysis - Heart rate entries: ${allHeartRateEntries.length}');
        debugPrint(
            'Challenge analysis - Speed entries: ${allSpeedEntries.length}');

        // Check if we have heart rate data, otherwise use speed data
        if (allHeartRateEntries.isNotEmpty) {
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
            'dataType': 'heart_rate',
            'watchData': allHeartRateEntries,
            'heartRates':
                allHeartRateEntries.map((e) => e['heartRate']).toList(),
            'averageHR': averageHeartRate,
            'insideZone': insideZone,
            'outsideZone': outsideZone,
            'zoneThreshold': lowerBound,
            'upperBound': upperBound,
            'lowerBound': lowerBound,
            'percentageInsideZone': percentageInsideZone,
            'zoneId': zoneIdToUse,
          };
        } else if (allSpeedEntries.isNotEmpty) {
          // Process speed data
          double totalSpeed = 0.0;
          double maxSpeed = 0.0;
          double minSpeed = double.infinity;

          // Define speed zone bounds (km/hr)
          final zoneIdToUse = responseZoneId ?? zoneId;
          double lowerBound, upperBound;

          if (zoneIdToUse == 1) {
            lowerBound = 4.0; // Zone 1: Walk
            upperBound = 6.0;
          } else if (zoneIdToUse == 2) {
            lowerBound = 6.01; // Zone 2: Jog
            upperBound = 8.0;
          } else if (zoneIdToUse == 3) {
            lowerBound = 8.01; // Zone 3: Run
            upperBound = 12.0;
          } else {
            lowerBound = 4.0; // Default to Zone 1
            upperBound = 6.0;
          }

          int insideZone = 0;
          int outsideZone = 0;

          for (var entry in allSpeedEntries) {
            final speed = (entry['speed'] as num).toDouble();
            totalSpeed += speed;
            if (speed > maxSpeed) maxSpeed = speed;
            if (speed < minSpeed) minSpeed = speed;

            if (speed >= lowerBound && speed <= upperBound) {
              insideZone++;
            } else {
              outsideZone++;
            }
          }

          double averageSpeed = totalSpeed / allSpeedEntries.length;
          double percentageInsideZone =
              (insideZone / allSpeedEntries.length) * 100;

          return {
            'dataType': 'speed',
            'watchData': allSpeedEntries,
            'speeds': allSpeedEntries.map((e) => e['speed']).toList(),
            'averageSpeed': averageSpeed,
            'maxSpeed': maxSpeed,
            'minSpeed': minSpeed,
            'lowerBound': lowerBound,
            'upperBound': upperBound,
            'insideZone': insideZone,
            'outsideZone': outsideZone,
            'percentageInsideZone': percentageInsideZone,
            'zoneId': zoneIdToUse,
          };
        }

        return {};
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
            'No analytics data available',
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
        final isSpeedData = analytics['dataType'] == 'speed';

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

                // Average Heart Rate or Speed
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        isSpeedData ? 'Average Speed' : 'Average Heart Rate',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isSpeedData
                            ? '${analytics['averageSpeed'].toStringAsFixed(1)} km/h'
                            : '${analytics['averageHR'].toStringAsFixed(1)} BPM',
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
                        isSpeedData
                            ? '$zoneType Zone (${analytics['lowerBound'].toStringAsFixed(1)}-${analytics['upperBound'].toStringAsFixed(1)} km/h)'
                            : '$zoneType Zone (${analytics['lowerBound'].toInt()}-${analytics['upperBound'].toInt()} BPM)',
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

                // Heart Rate or Speed Line Chart
                Text(
                  isSpeedData ? 'Speed Over Time' : 'Heart Rate Over Time',
                  style: const TextStyle(
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
                                // Main data line
                                return LineTooltipItem(
                                  isSpeedData
                                      ? 'Speed\n${touchedSpot.y.toStringAsFixed(1)} km/h'
                                      : 'Heart Rate\n${touchedSpot.y.toInt()} BPM',
                                  const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                );
                              } else if (touchedSpot.barIndex == 1) {
                                // Lower bound line
                                return LineTooltipItem(
                                  isSpeedData
                                      ? 'Target Zone Lower\n${touchedSpot.y.toStringAsFixed(1)} km/h'
                                      : 'Target Zone Lower\n${touchedSpot.y.toInt()} BPM',
                                  const TextStyle(
                                    color: Color(0xFF00FF88),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                );
                              } else if (touchedSpot.barIndex == 2) {
                                // Upper bound line
                                return LineTooltipItem(
                                  isSpeedData
                                      ? 'Target Zone Upper\n${touchedSpot.y.toStringAsFixed(1)} km/h'
                                      : 'Target Zone Upper\n${touchedSpot.y.toInt()} BPM',
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
                        horizontalInterval: isSpeedData ? 2 : 20,
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
                                isSpeedData
                                    ? '${value.toStringAsFixed(1)}'
                                    : '${value.toInt()}',
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
                      minY: isSpeedData
                          ? [
                              analytics['speeds']?.isNotEmpty == true
                                  ? analytics['speeds']
                                          .reduce((a, b) => a < b ? a : b)
                                          .toDouble() -
                                      1
                                  : 0.0,
                              analytics['lowerBound'] - 1,
                            ].reduce((a, b) => a < b ? a : b)
                          : [
                              analytics['heartRates']
                                      .reduce((a, b) => a < b ? a : b)
                                      .toDouble() -
                                  10,
                              analytics['lowerBound'] - 20,
                            ].reduce((a, b) => a < b ? a : b),
                      maxY: isSpeedData
                          ? [
                              analytics['speeds']?.isNotEmpty == true
                                  ? analytics['speeds']
                                          .reduce((a, b) => a > b ? a : b)
                                          .toDouble() +
                                      1
                                  : 15.0,
                              analytics['upperBound'] + 1,
                            ].reduce((a, b) => a > b ? a : b)
                          : [
                              analytics['heartRates']
                                      .reduce((a, b) => a > b ? a : b)
                                      .toDouble() +
                                  10,
                              analytics['upperBound'] + 20,
                            ].reduce((a, b) => a > b ? a : b),
                      lineBarsData: [
                        // Main data line with gradient
                        LineChartBarData(
                          spots: List.generate(
                            analytics['watchData'].length,
                            (index) => FlSpot(
                              index.toDouble(),
                              isSpeedData
                                  ? analytics['watchData'][index]['speed']
                                      .toDouble()
                                  : analytics['watchData'][index]['heartRate']
                                      .toDouble(),
                            ),
                          ),
                          isCurved: true,
                          gradient: LinearGradient(
                            colors: isSpeedData
                                ? [
                                    const Color(0xFF00FF88),
                                    const Color(0xFF00CC66),
                                    const Color(0xFF009944),
                                  ]
                                : [
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
                              colors: isSpeedData
                                  ? [
                                      const Color(0xFF00FF88).withOpacity(0.3),
                                      const Color(0xFF00CC66).withOpacity(0.1),
                                      Colors.transparent,
                                    ]
                                  : [
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
                                strokeColor: isSpeedData
                                    ? const Color(0xFF00CC66)
                                    : const Color(0xFF0099FF),
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
                            gradient: LinearGradient(
                              colors: isSpeedData
                                  ? [
                                      const Color(0xFF00FF88),
                                      const Color(0xFF00CC66),
                                    ]
                                  : [
                                      const Color(0xFF00D4FF),
                                      const Color(0xFF0099FF),
                                    ],
                            ),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isSpeedData ? 'Speed' : 'Heart Rate',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
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
            'No analytics data available',
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
        final isSpeedData = analytics['dataType'] == 'speed';

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

                // Average Heart Rate or Speed
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        isSpeedData ? 'Average Speed' : 'Average Heart Rate',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isSpeedData
                            ? '${analytics['averageSpeed'].toStringAsFixed(1)} km/h'
                            : '${analytics['averageHR'].toStringAsFixed(1)} BPM',
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
                        isSpeedData
                            ? '$zoneType Zone (${analytics['lowerBound'].toStringAsFixed(1)}-${analytics['upperBound'].toStringAsFixed(1)} km/h)'
                            : '$zoneType Zone (${analytics['lowerBound'].toInt()}-${analytics['upperBound'].toInt()} BPM)',
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

                // Heart Rate or Speed Line Chart
                Text(
                  isSpeedData ? 'Speed Over Time' : 'Heart Rate Over Time',
                  style: const TextStyle(
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
                                // Main data line
                                return LineTooltipItem(
                                  isSpeedData
                                      ? 'Speed\n${touchedSpot.y.toStringAsFixed(1)} km/h'
                                      : 'Heart Rate\n${touchedSpot.y.toInt()} BPM',
                                  const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                );
                              } else if (touchedSpot.barIndex == 1) {
                                // Lower bound line
                                return LineTooltipItem(
                                  isSpeedData
                                      ? 'Target Zone Lower\n${touchedSpot.y.toStringAsFixed(1)} km/h'
                                      : 'Target Zone Lower\n${touchedSpot.y.toInt()} BPM',
                                  const TextStyle(
                                    color: Color(0xFF00FF88),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                );
                              } else if (touchedSpot.barIndex == 2) {
                                // Upper bound line
                                return LineTooltipItem(
                                  isSpeedData
                                      ? 'Target Zone Upper\n${touchedSpot.y.toStringAsFixed(1)} km/h'
                                      : 'Target Zone Upper\n${touchedSpot.y.toInt()} BPM',
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
                        horizontalInterval: isSpeedData ? 2 : 20,
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
                                isSpeedData
                                    ? '${value.toStringAsFixed(1)}'
                                    : '${value.toInt()}',
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
                      minY: isSpeedData
                          ? [
                              analytics['speeds']?.isNotEmpty == true
                                  ? analytics['speeds']
                                          .reduce((a, b) => a < b ? a : b)
                                          .toDouble() -
                                      1
                                  : 0.0,
                              analytics['lowerBound'] - 1,
                            ].reduce((a, b) => a < b ? a : b)
                          : [
                              analytics['heartRates']
                                      .reduce((a, b) => a < b ? a : b)
                                      .toDouble() -
                                  10,
                              analytics['lowerBound'] - 20,
                            ].reduce((a, b) => a < b ? a : b),
                      maxY: isSpeedData
                          ? [
                              analytics['speeds']?.isNotEmpty == true
                                  ? analytics['speeds']
                                          .reduce((a, b) => a > b ? a : b)
                                          .toDouble() +
                                      1
                                  : 15.0,
                              analytics['upperBound'] + 1,
                            ].reduce((a, b) => a > b ? a : b)
                          : [
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
                              isSpeedData
                                  ? analytics['watchData'][index]['speed']
                                      .toDouble()
                                  : analytics['watchData'][index]['heartRate']
                                      .toDouble(),
                            ),
                          ),
                          isCurved: true,
                          gradient: LinearGradient(
                            colors: isSpeedData
                                ? [
                                    const Color(0xFF00FF88),
                                    const Color(0xFF00CC66),
                                    const Color(0xFF009944),
                                  ]
                                : [
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
                              colors: isSpeedData
                                  ? [
                                      const Color(0xFF00FF88).withOpacity(0.3),
                                      const Color(0xFF00CC66).withOpacity(0.1),
                                      Colors.transparent,
                                    ]
                                  : [
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
                                strokeColor: isSpeedData
                                    ? const Color(0xFF00CC66)
                                    : const Color(0xFFFF6B35),
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
                            gradient: LinearGradient(
                              colors: isSpeedData
                                  ? [
                                      const Color(0xFF00FF88),
                                      const Color(0xFF00CC66),
                                    ]
                                  : [
                                      const Color(0xFFFF6B6B),
                                      const Color(0xFFFF8E53),
                                    ],
                            ),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isSpeedData ? 'Speed' : 'Heart Rate',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
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

  Future<void> fetchCurrentCity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';

      // Get cityId from userData if available, otherwise return
      dynamic userCityId;
      if (userData != null && userData!.containsKey('cityId')) {
        userCityId = userData!['cityId'];
        debugPrint(
            'User cityId: $userCityId (type: ${userCityId.runtimeType})');
      }

      if (userCityId == null) {
        // If no cityId available, keep the default city name
        debugPrint(
            'No cityId found, keeping default city name: $currentCityName');
        return;
      }

      final response = await http.get(
        Uri.parse('https://authcheck.co/city'),
        headers: {
          'Accept': '*/*',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final dynamic responseData = json.decode(response.body);
        List<dynamic> cities = [];

        // Handle different response formats
        if (responseData is List) {
          cities = responseData;
        } else if (responseData is Map<String, dynamic>) {
          // If it's a map, check for common keys that might contain the cities list
          if (responseData.containsKey('cities')) {
            cities = responseData['cities'] as List<dynamic>;
          } else if (responseData.containsKey('data')) {
            cities = responseData['data'] as List<dynamic>;
          } else {
            // If it's a single city object, wrap it in a list
            cities = [responseData];
          }
        }

        // Find the city that matches the user's cityId
        String? foundCityName;
        for (var city in cities) {
          // Handle both string and int cityId comparisons
          var cityId = city['id'];
          bool isMatch = false;

          debugPrint(
              'Comparing user cityId: $userCityId (${userCityId.runtimeType}) with city id: $cityId (${cityId.runtimeType})');

          if (userCityId is String && cityId is String) {
            isMatch = userCityId == cityId;
          } else if (userCityId is int && cityId is int) {
            isMatch = userCityId == cityId;
          } else if (userCityId is String && cityId is int) {
            isMatch = int.tryParse(userCityId) == cityId;
          } else if (userCityId is int && cityId is String) {
            isMatch = userCityId == int.tryParse(cityId);
          }

          if (isMatch) {
            foundCityName = city['name'] ?? 'Local Area';
            debugPrint('Found matching city: $foundCityName');
            break;
          }
        }

        if (foundCityName != null) {
          setState(() {
            currentCityName = foundCityName!;
          });
          debugPrint('Current city name set to: $currentCityName');
        } else {
          debugPrint(
              'City with ID $userCityId not found in response. Available cities: ${cities.map((c) => '${c['id']} (${c['id'].runtimeType}): ${c['name']}').join(', ')}');
        }
      } else {
        throw Exception(
            'Failed to load cities (Status: ${response.statusCode})');
      }
    } catch (e) {
      debugPrint('Error fetching current city: $e');
      // Keep the default 'Local Area' if there's an error
    }
  }

  Future<void> fetchUserData() async {
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
        setState(() {
          userData = data['user'];
        });

        // After fetching user data, fetch the current city
        fetchCurrentCity();
      } else {
        throw Exception('Failed to load user data');
      }
    } catch (e) {
      debugPrint('Error fetching user data: $e');
    }
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

  Widget _buildLeaderboardTab() {
    return Column(
      children: [
        // Selection bar for Global/Local
        Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(25),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      selectedLeaderboardType = 'global';
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: selectedLeaderboardType == 'global'
                          ? Colors.white
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Text(
                      'Global',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: selectedLeaderboardType == 'global'
                            ? Colors.black
                            : Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      selectedLeaderboardType = 'local';
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: selectedLeaderboardType == 'local'
                          ? Colors.white
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Text(
                      currentCityName,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: selectedLeaderboardType == 'local'
                            ? Colors.black
                            : Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Leaderboard content
        Expanded(
          child: isLeaderboardLoading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: Colors.white,
                  ),
                )
              : _buildLeaderboardContent(),
        ),
      ],
    );
  }

  Widget _buildLeaderboardContent() {
    if (leaderboardData.isEmpty) {
      return const Center(
        child: Text(
          'No leaderboard data available',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
          ),
        ),
      );
    }

    // Filter and sort leaderboard data
    List<dynamic> filteredData = [];

    if (selectedLeaderboardType == 'global') {
      // Show all users, sorted by score (highest to lowest)
      filteredData = List.from(leaderboardData);
    } else {
      // Show only users from the same city
      final userCityId = userData?['cityId'];
      if (userCityId != null) {
        filteredData = leaderboardData.where((user) {
          var cityId = user['cityId'];

          // Handle both string and int cityId comparisons
          if (userCityId is String && cityId is String) {
            return userCityId == cityId;
          } else if (userCityId is int && cityId is int) {
            return userCityId == cityId;
          } else if (userCityId is String && cityId is int) {
            return int.tryParse(userCityId) == cityId;
          } else if (userCityId is int && cityId is String) {
            return userCityId == int.tryParse(cityId);
          }

          return false;
        }).toList();
      }
    }

    // Sort by score (highest to lowest)
    filteredData.sort((a, b) {
      final scoreA = (a['score'] ?? 0) as num;
      final scoreB = (b['score'] ?? 0) as num;
      return scoreB.compareTo(scoreA);
    });

    return RefreshIndicator(
      onRefresh: () async {
        await fetchLeaderboard();
        await fetchCurrentCity();
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: filteredData.length,
        itemBuilder: (context, index) {
          final user = filteredData[index];
          final position = index + 1;
          final userName =
              (user['name'] == null || user['name'].toString().trim().isEmpty)
                  ? 'Anonymous'
                  : user['name'];
          final userScore = (user['score'] ?? 0) as num;
          final isCurrentUser = user['id'] == userData?['id'];
          final userEmoji = _getUserEmoji(position);

          return Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: isCurrentUser
                  ? Colors.white.withOpacity(0.2)
                  : Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: isCurrentUser
                  ? Border.all(color: Colors.white, width: 1)
                  : null,
            ),
            child: ListTile(
              leading: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _getPositionColor(position).withOpacity(0.8),
                      _getPositionColor(position).withOpacity(0.4),
                    ],
                  ),
                  border: Border.all(
                    color: _getPositionColor(position),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _getPositionColor(position).withOpacity(0.3),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    userEmoji,
                    style: const TextStyle(
                      fontSize: 24,
                    ),
                  ),
                ),
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      userName,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight:
                            isCurrentUser ? FontWeight.bold : FontWeight.normal,
                        fontSize: isCurrentUser ? 16 : 14,
                      ),
                    ),
                  ),
                  if (isCurrentUser)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'You',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              subtitle:
                  selectedLeaderboardType == 'local' && user['city'] != null
                      ? Text(
                          user['city'],
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        )
                      : null,
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$userScore',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const Text(
                    'points',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Color _getPositionColor(int position) {
    switch (position) {
      case 1:
        return Colors.amber; // Gold
      case 2:
        return Colors.grey[400]!; // Silver
      case 3:
        return Colors.orange[800]!; // Bronze
      default:
        return Colors.blue[700]!; // Default blue
    }
  }

  String _getUserEmoji(int position) {
    switch (position) {
      case 1:
        return '🥇'; // Gold medal
      case 2:
        return '🥈'; // Silver medal
      case 3:
        return '🥉'; // Bronze medal
      case 4:
        return '🔥'; // Fire
      case 5:
        return '⭐'; // Star
      case 6:
        return '💪'; // Muscle
      case 7:
        return '🚀'; // Rocket
      case 8:
        return '⚡'; // Lightning
      case 9:
        return '🎯'; // Target
      case 10:
        return '💎'; // Diamond
      default:
        return '🏃'; // Runner
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
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
              Tab(
                icon: Icon(Icons.leaderboard),
                text: 'Leader Board',
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
                  _buildLeaderboardTab(),
                ],
              ),
      ),
    );
  }
}
