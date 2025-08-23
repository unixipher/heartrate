import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:confetti/confetti.dart';
import 'package:testingheartrate/screens/home/home_screen.dart';
import 'package:path_provider/path_provider.dart';

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
  final int score; // This is the total score for the session
  final Map<int, int>
      challengeScores; // This map holds the individual scores

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
    required this.score,
    required this.challengeScores,
  });

  @override
  State<CompletionScreen> createState() => _CompletionScreenState();
}

class _CompletionScreenState extends State<CompletionScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late ConfettiController _confettiController;
  late AnimationController _animationController;
  late Animation<double> _heartRateAnimation;
  late Animation<double> _zoneTimeAnimation;
  late Animation<double> _nudgeAnimation;

  // Values to animate to
  double _averageHeartRate = 0.0;
  double _averageSpeed = 0.0; // Add average speed for non-Apple Watch users
  double _percentageInsideZone = 0.0;
  int _nudgeCount = 0;

  bool _isAppActive = true;
  bool _isLoading = true;
  bool _hasFetchedData = false;

  // Leaderboard related variables
  List<dynamic> leaderboardData = [];
  Map<String, dynamic>? userData;
  bool isLeaderboardLoading = false;
  final ScrollController _leaderboardScrollController = ScrollController();

  // Helper method to determine if using heart rate or speed
  bool get _useHeartRateData {
    if (Platform.isAndroid) return false;
    if (Platform.isIOS)
      return true; // Always use heart rate on iOS (via socket)
    return false;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _confettiController =
        ConfettiController(duration: const Duration(seconds: 10));
    // _confettiController.play();
    _nudgeCount = widget.timestampcount;
    _animationController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );
    _heartRateAnimation =
        Tween<double>(begin: 0.0, end: 0.0).animate(_animationController);
    _zoneTimeAnimation =
        Tween<double>(begin: 0.0, end: 0.0).animate(_animationController);
    _nudgeAnimation =
        Tween<double>(begin: 0.0, end: 0.0).animate(_animationController);
    if (_isAppActive) {
      _updateChallengeAndFetchData();
      // Fetch leaderboard data
      fetchUserData();
      fetchLeaderboard();
    }
  }

  Future<void> _updateChallengeAndFetchData() async {
    // Update user score
    await _updateUserScore();

    // Wait for 2 seconds
    await Future.delayed(const Duration(seconds: 2));

    // Then fetch data and animate
    if (_isAppActive) {
      await _fetchDataAndAnimate();

      // After all analysis is complete, delete audio files
      await _deleteAudioFiles();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    setState(() {
      _isAppActive = state == AppLifecycleState.resumed;
    });

    // Handle app coming to foreground
    if (_isAppActive) {
      if (!_hasFetchedData) {
        // Show loader and fetch data if not already done
        setState(() => _isLoading = true);
        _fetchDataAndAnimate();
      } else {
        // Just show content if data already exists
        setState(() => _isLoading = false);
        if (!_animationController.isAnimating &&
            !_animationController.isCompleted) {
          _animationController.forward();
        }
      }
      _confettiController.play();
    } else {
      // App went to background
      _confettiController.stop();
    }
  }

  Future<void> _fetchDataAndAnimate() async {
    try {
      final analysisData = await analyseData();
      if (!_isAppActive) return;

      debugPrint('Setting state with analysis data: $analysisData');

      setState(() {
        _averageHeartRate = analysisData['averageHeartRate'] ?? 0.0;
        _averageSpeed = analysisData['averageSpeed'] ?? 0.0;
        _percentageInsideZone = analysisData['percentageInsideZone'] ?? 0.0;
        _hasFetchedData = true;
      });

      debugPrint(
          'State updated - avgHR: $_averageHeartRate, avgSpeed: $_averageSpeed, zonePercentage: $_percentageInsideZone');

      // Calculate animation progress based on data type
      bool isHeartRateData = _useHeartRateData;
      double primaryProgress = 0.0;

      if (isHeartRateData) {
        final maxHr = widget.maxheartRate ?? 200.0;
        primaryProgress = _averageHeartRate / maxHr;
      } else {
        // For speed data, use a reasonable max speed for progress calculation
        const double maxSpeed = 15.0; // 15 km/h as max for progress bar
        primaryProgress = _averageSpeed / maxSpeed;
      }

      final zoneProgress = _percentageInsideZone / 100.0;
      final nudgeProgress = _nudgeCount / 7.0;

      debugPrint('Animation progress values:');
      debugPrint('- Primary Progress: $primaryProgress');
      debugPrint(
          '- Zone Progress: $zoneProgress (${_percentageInsideZone}/100)');
      debugPrint('- Nudge Progress: $nudgeProgress ($_nudgeCount/7)');

      _heartRateAnimation =
          Tween<double>(begin: 0.0, end: primaryProgress.clamp(0.0, 1.0))
              .animate(CurvedAnimation(
                  parent: _animationController, curve: Curves.easeOut));

      _zoneTimeAnimation =
          Tween<double>(begin: 0.0, end: zoneProgress.clamp(0.0, 1.0)).animate(
              CurvedAnimation(
                  parent: _animationController, curve: Curves.elasticOut));

      _nudgeAnimation =
          Tween<double>(begin: 0.0, end: nudgeProgress.clamp(0.0, 1.0)).animate(
              CurvedAnimation(
                  parent: _animationController, curve: Curves.bounceOut));

      _animationController.forward();
      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Error fetching data: $e');
      if (_isAppActive) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteAudioFiles() async {
    try {
      debugPrint('Starting audio file cleanup...');

      final directory = await getApplicationDocumentsDirectory();
      final prefs = await SharedPreferences.getInstance();

      int deletedCount = 0;

      // Iterate through audioData and delete files
      for (var audioItem in (widget.audioData as List)) {
        final int challengeId = audioItem['id'] as int;
        final String audioUrl = audioItem['audioUrl'] as String? ?? '';

        // Check if this is a local file (downloaded)
        if (audioUrl.startsWith('file://')) {
          final String filePath = audioUrl.replaceFirst('file://', '');
          final File audioFile = File(filePath);

          try {
            if (await audioFile.exists()) {
              await audioFile.delete();
              deletedCount++;
              debugPrint('Deleted audio file: $filePath');
            }
          } catch (e) {
            debugPrint('Error deleting file $filePath: $e');
          }
        }

        // Also try the standard naming convention used in challenge_screen
        final String standardPath =
            '${directory.path}/challenge_$challengeId.mp3';
        final File standardFile = File(standardPath);

        try {
          if (await standardFile.exists()) {
            await standardFile.delete();
            deletedCount++;
            debugPrint('Deleted standard audio file: $standardPath');
          }
        } catch (e) {
          debugPrint('Error deleting standard file $standardPath: $e');
        }

        // Remove download status from SharedPreferences
        await prefs.remove('downloaded_$challengeId');
        debugPrint('Removed download status for challenge $challengeId');
      }

      debugPrint('Audio cleanup completed. Deleted $deletedCount files.');
    } catch (e) {
      debugPrint('Error during audio file cleanup: $e');
    }
  }

  Future<void> _updateUserScore() async {
    debugPrint("💯💯💯💯score: ${widget.score}");
  }

  // Leaderboard related methods
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

        // Try to scroll to current user if leaderboard is already loaded
        _scrollToCurrentUser();
      } else {
        throw Exception('Failed to load user data');
      }
    } catch (e) {
      debugPrint('Error fetching user data: $e');
    }
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

        // Sort by score (highest to lowest)
        data.sort((a, b) {
          final scoreA = (a['score'] ?? 0) as num;
          final scoreB = (b['score'] ?? 0) as num;
          return scoreB.compareTo(scoreA);
        });

        setState(() {
          leaderboardData = data;
          isLeaderboardLoading = false;
        });

        // Auto-scroll to current user after a short delay
        _scrollToCurrentUser();
      } else {
        throw Exception('Failed to load leaderboard');
      }
    } catch (e) {
      setState(() {
        isLeaderboardLoading = false;
      });
      debugPrint('Error fetching leaderboard: $e');
    }
  }

  void _scrollToCurrentUser() {
    debugPrint('_scrollToCurrentUser called');
    debugPrint('userData: ${userData != null ? "available" : "null"}');
    debugPrint('leaderboardData: ${leaderboardData.length} items');

    if (userData == null || leaderboardData.isEmpty) {
      debugPrint('Cannot scroll: userData or leaderboardData not ready');
      return;
    }

    // Find current user's position in leaderboard
    int currentUserIndex = -1;
    for (int i = 0; i < leaderboardData.length; i++) {
      if (leaderboardData[i]['id'] == userData!['id']) {
        currentUserIndex = i;
        break;
      }
    }

    debugPrint('Current user found at index: $currentUserIndex');

    if (currentUserIndex != -1) {
      // Delay scroll to ensure the ListView is built
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (_leaderboardScrollController.hasClients) {
          // Calculate scroll position (each item is approximately 80 pixels high including margins)
          double scrollPosition = currentUserIndex * 80.0;

          debugPrint('Scrolling to position: $scrollPosition');

          // Scroll to position with animation
          _leaderboardScrollController.animateTo(
            scrollPosition,
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeInOut,
          );
        } else {
          debugPrint('ScrollController does not have clients yet');
        }
      });
    } else {
      debugPrint('Current user not found in leaderboard');
    }
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
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _confettiController.dispose();
    _animationController.dispose();
    _leaderboardScrollController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> analyseData() async {
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
        debugPrint('Analysis response data: $data');

        // Determine data type based on platform and Apple Watch usage
        bool useHeartRate = _useHeartRateData;

        if (useHeartRate) {
          return _analyseHeartRateData(data);
        } else {
          return _analyseSpeedData(data);
        }
      } else {
        debugPrint('Analysis API error: ${response.statusCode}');
        debugPrint('Response body: ${response.body}');
        throw Exception('Failed to analyse data');
      }
    } catch (e) {
      debugPrint('Error in analyseData: $e');
      rethrow;
    }
  }

  Map<String, dynamic> _analyseHeartRateData(List<dynamic> data) {
    List<dynamic> allHeartRateEntries = [];
    int? zoneId;

    for (var challenge in data) {
      debugPrint('Processing challenge: $challenge');
      if (zoneId == null && challenge['zoneId'] != null) {
        zoneId = challenge['zoneId'];
      }
      if (challenge['heartRateData'] != null) {
        debugPrint('Heart rate data found: ${challenge['heartRateData']}');
        allHeartRateEntries.addAll(challenge['heartRateData']);
      }
    }
    debugPrint('Total heart rate entries: ${allHeartRateEntries.length}');

    // Calculate zone boundaries for all zones using Karvonen method
    final maxHR = widget.maxheartRate ?? 0;
    final restingHR = 72.0;

    double zone1Lower =
        (restingHR + (maxHR - restingHR) * 0.35).toDouble(); // 35% intensity
    double zone1Upper =
        (restingHR + (maxHR - restingHR) * 0.75).toDouble(); // 75% intensity
    double zone2Lower =
        (restingHR + (maxHR - restingHR) * 0.45).toDouble(); // 45% intensity
    double zone2Upper =
        (restingHR + (maxHR - restingHR) * 0.85).toDouble(); // 85% intensity
    double zone3Lower =
        (restingHR + (maxHR - restingHR) * 0.55).toDouble(); // 55% intensity
    double zone3Upper =
        (restingHR + (maxHR - restingHR) * 0.95).toDouble(); // 95% intensity

    debugPrint('Zone boundaries (Karvonen method):');
    debugPrint(
        '- Zone 1 (Walk): ${zone1Lower.toInt()}-${zone1Upper.toInt()} BPM');
    debugPrint(
        '- Zone 2 (Jog): ${zone2Lower.toInt()}-${zone2Upper.toInt()} BPM');
    debugPrint(
        '- Zone 3 (Run): ${zone3Lower.toInt()}-${zone3Upper.toInt()} BPM');

    int insideTargetZone = 0;
    int insideActualZone = 0;
    int outsideZone = 0;
    double totalHeartRate = 0.0;

    // Determine target zone boundaries
    double targetLowerBound, targetUpperBound;
    if (zoneId == 1) {
      targetLowerBound = zone1Lower;
      targetUpperBound = zone1Upper;
    } else if (zoneId == 2) {
      targetLowerBound = zone2Lower;
      targetUpperBound = zone2Upper;
    } else if (zoneId == 3) {
      targetLowerBound = zone3Lower;
      targetUpperBound = zone3Upper;
    } else {
      throw Exception('Invalid zoneId');
    }

    for (var entry in allHeartRateEntries) {
      final heartRate = (entry['heartRate'] as num).toDouble();
      totalHeartRate += heartRate;

      // Check if in target zone
      if (heartRate >= targetLowerBound && heartRate <= targetUpperBound) {
        insideTargetZone++;
      }

      // Check which zone they were actually in
      if (heartRate >= zone1Lower && heartRate <= zone1Upper) {
        insideActualZone++; // Zone 1
      } else if (heartRate >= zone2Lower && heartRate <= zone2Upper) {
        insideActualZone++; // Zone 2
      } else if (heartRate >= zone3Lower && heartRate <= zone3Upper) {
        insideActualZone++; // Zone 3
      } else {
        outsideZone++;
      }
    }

    double averageHeartRate = allHeartRateEntries.isNotEmpty
        ? totalHeartRate / allHeartRateEntries.length
        : 0.0;

    // Use the higher percentage between target zone and actual zone performance
    double percentageInsideTargetZone = allHeartRateEntries.isNotEmpty
        ? (insideTargetZone / allHeartRateEntries.length) * 100
        : 0.0;
    double percentageInsideAnyZone = allHeartRateEntries.isNotEmpty
        ? (insideActualZone / allHeartRateEntries.length) * 100
        : 0.0;

    // Use the better percentage to show user achievement
    double displayPercentage = percentageInsideTargetZone > 0
        ? percentageInsideTargetZone
        : percentageInsideAnyZone;

    debugPrint('Heart Rate Analysis results:');
    debugPrint('- Average Heart Rate: $averageHeartRate');
    debugPrint('- Percentage Inside Target Zone: $percentageInsideTargetZone');
    debugPrint('- Percentage Inside Any Zone: $percentageInsideAnyZone');
    debugPrint('- Display Percentage: $displayPercentage');
    debugPrint('- Target Zone bounds: $targetLowerBound - $targetUpperBound');

    return {
      'insideZone': insideTargetZone,
      'outsideZone': outsideZone,
      'averageHeartRate': averageHeartRate,
      'averageSpeed': 0.0, // Not applicable for heart rate analysis
      'percentageInsideZone': displayPercentage,
      'dataType': 'heartRate',
    };
  }

  Map<String, dynamic> _analyseSpeedData(List<dynamic> data) {
    List<dynamic> allSpeedEntries = [];
    int? zoneId;

    for (var challenge in data) {
      debugPrint('Processing challenge: $challenge');
      if (zoneId == null && challenge['zoneId'] != null) {
        zoneId = challenge['zoneId'];
      }
      if (challenge['speedData'] != null) {
        debugPrint('Speed data found: ${challenge['speedData']}');
        allSpeedEntries.addAll(challenge['speedData']);
      }
    }
    debugPrint('Total speed entries: ${allSpeedEntries.length}');

    // Define speed zone boundaries (same as in player_screen.dart)
    double zone1Lower,
        zone1Upper,
        zone2Lower,
        zone2Upper,
        zone3Lower,
        zone3Upper;

    zone1Lower = 4.0; // Zone 1: Walk
    zone1Upper = 6.0;
    zone2Lower = 6.01; // Zone 2: Jog (slight gap to avoid overlap)
    zone2Upper = 8.0;
    zone3Lower = 8.01; // Zone 3: Run (slight gap to avoid overlap)
    zone3Upper = 12.0;

    debugPrint('Speed Zone boundaries:');
    debugPrint('- Zone 1 (Walk): $zone1Lower-$zone1Upper km/h');
    debugPrint('- Zone 2 (Jog): $zone2Lower-$zone2Upper km/h');
    debugPrint('- Zone 3 (Run): $zone3Lower-$zone3Upper km/h');

    int insideTargetZone = 0;
    int insideActualZone = 0;
    int outsideZone = 0;
    double totalSpeed = 0.0;

    // Determine target zone boundaries
    double targetLowerBound, targetUpperBound;
    if (zoneId == 1) {
      targetLowerBound = zone1Lower;
      targetUpperBound = zone1Upper;
    } else if (zoneId == 2) {
      targetLowerBound = zone2Lower;
      targetUpperBound = zone2Upper;
    } else if (zoneId == 3) {
      targetLowerBound = zone3Lower;
      targetUpperBound = zone3Upper;
    } else {
      throw Exception('Invalid zoneId');
    }

    for (var entry in allSpeedEntries) {
      final speed =
          (entry['speed'] as num).toDouble(); // Speed is already in km/h
      totalSpeed += speed;

      // Check if in target zone
      if (speed >= targetLowerBound && speed <= targetUpperBound) {
        insideTargetZone++;
      }

      // Check which zone they were actually in
      if (speed >= zone1Lower && speed <= zone1Upper) {
        insideActualZone++; // Zone 1
      } else if (speed >= zone2Lower && speed <= zone2Upper) {
        insideActualZone++; // Zone 2
      } else if (speed >= zone3Lower && speed <= zone3Upper) {
        insideActualZone++; // Zone 3
      } else {
        outsideZone++;
      }
    }

    double averageSpeed =
        allSpeedEntries.isNotEmpty ? totalSpeed / allSpeedEntries.length : 0.0;

    // Use the higher percentage between target zone and actual zone performance
    double percentageInsideTargetZone = allSpeedEntries.isNotEmpty
        ? (insideTargetZone / allSpeedEntries.length) * 100
        : 0.0;
    double percentageInsideAnyZone = allSpeedEntries.isNotEmpty
        ? (insideActualZone / allSpeedEntries.length) * 100
        : 0.0;

    // Use the better percentage to show user achievement
    double displayPercentage = percentageInsideTargetZone > 0
        ? percentageInsideTargetZone
        : percentageInsideAnyZone;

    debugPrint('Speed Analysis results:');
    debugPrint('- Average Speed: $averageSpeed km/h');
    debugPrint('- Percentage Inside Target Zone: $percentageInsideTargetZone');
    debugPrint('- Percentage Inside Any Zone: $percentageInsideAnyZone');
    debugPrint('- Display Percentage: $displayPercentage');
    debugPrint(
        '- Target Zone bounds: $targetLowerBound - $targetUpperBound km/h');

    return {
      'insideZone': insideTargetZone,
      'outsideZone': outsideZone,
      'averageHeartRate': 0.0, // Not applicable for speed analysis
      'averageSpeed': averageSpeed,
      'percentageInsideZone': displayPercentage,
      'dataType': 'speed',
    };
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

  // Custom progress bar widget
  Widget _buildProgressBar({
    required Animation<double> animation,
    required String label,
    required IconData icon,
    Color progressColor = Colors.green,
    Color backgroundColor = Colors.grey,
    Color iconColor = Colors.white,
    String? valueText,
    double padding = 32.0,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: padding, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Colors.purple.shade400, Colors.purple.shade700],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    icon,
                    color: iconColor,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 18,
                  fontFamily: 'TheWitcher',
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      color: Colors.black54,
                      blurRadius: 2,
                      offset: Offset(1, 1),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (valueText != null)
                Text(
                  valueText,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'TheWitcher',
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        color: Colors.black54,
                        blurRadius: 2,
                        offset: Offset(1, 1),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              return Container(
                height: 24,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.blueGrey.withOpacity(0.7),
                    width: 2,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    children: [
                      // Background
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              backgroundColor.withOpacity(0.2),
                              backgroundColor.withOpacity(0.1),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                      // Progress
                      FractionallySizedBox(
                        widthFactor: animation.value,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                progressColor.withOpacity(0.8),
                                progressColor.withOpacity(0.6),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                      ),
                      // Shine effect
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: 8,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.white.withOpacity(0.4),
                                Colors.white.withOpacity(0.0),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                      ),
                      // Tick marks
                      Row(
                        children: List.generate(
                          10,
                          (index) => Expanded(
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              child: Container(
                                height: double.infinity,
                                width: 1,
                                color: Colors.black12,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCompletionContent() {
    bool isHeartRateData = _useHeartRateData;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ShaderMask(
          shaderCallback: (bounds) {
            return const LinearGradient(
              colors: [Colors.white, Colors.white],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ).createShader(bounds);
          },
          child: const Text(
            'CHALLENGE COMPLETE',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              fontFamily: 'TheWitcher',
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 20),
        // Transparent cards section (similar to player screen)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    children: [
                      Text(
                        _useHeartRateData ? "HR" : "Speed",
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _isLoading
                            ? "--"
                            : (_useHeartRateData
                                ? "${_averageHeartRate.toInt()}"
                                : "${_averageSpeed.toStringAsFixed(1)} kmph"),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 15), // Space between cards
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    children: [
                      const Text(
                        "Zone Time",
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _isLoading ? "--" : "${_percentageInsideZone.toInt()}%",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 15), // Space between cards
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    children: [
                      const Text(
                        "Score",
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _isLoading ? "--" : "${widget.score}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20), // Space below cards
        // Leaderboard title
        ShaderMask(
          shaderCallback: (bounds) {
            return const LinearGradient(
              colors: [Colors.white, Colors.white],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ).createShader(bounds);
          },
          child: const Text(
            'GLOBAL LEADERBOARD',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              fontFamily: 'TheWitcher',
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
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
                  color: Colors.black.withOpacity(0.6),
                ),
              ],
            ),
            if (_isAppActive)
              Align(
                alignment: Alignment.topCenter,
                child: ConfettiWidget(
                  confettiController: _confettiController,
                  blastDirection: pi / 2,
                  maxBlastForce: 5,
                  minBlastForce: 2,
                  emissionFrequency: 0.05,
                  numberOfParticles: 10,
                  gravity: 0.1,
                  colors: const [
                    Colors.amber,
                    Colors.red,
                    Colors.green,
                    Colors.blue,
                    Colors.purple,
                  ],
                ),
              ),
            if (_isLoading && _isAppActive)
              Container(
                color: Colors.black.withOpacity(0.7),
                child: const Center(
                  child: CircularProgressIndicator(
                    color: Colors.purple,
                    strokeWidth: 6,
                  ),
                ),
              ),
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 70.0),
                  child: _buildCompletionContent(),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10.0),
                    child: isLeaderboardLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: Colors.purple,
                            ),
                          )
                        : leaderboardData.isEmpty
                            ? const Center(
                                child: Text(
                                  'No leaderboard data available',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: () async {
                                  await fetchLeaderboard();
                                },
                                child: ListView.builder(
                                  controller: _leaderboardScrollController,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                  itemCount: leaderboardData.length,
                                  itemBuilder: (context, index) {
                                    final user = leaderboardData[index];
                                    final position = index + 1;
                                    final userName = (user['name'] == null ||
                                            user['name']
                                                .toString()
                                                .trim()
                                                .isEmpty)
                                        ? 'Anonymous'
                                        : user['name'];
                                    final userScore =
                                        (user['score'] ?? 0) as num;
                                    final isCurrentUser =
                                        user['id'] == userData?['id'];
                                    final userEmoji = _getUserEmoji(position);

                                    return Container(
                                      margin: const EdgeInsets.symmetric(
                                          vertical: 4),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Colors.white.withOpacity(0.15),
                                            Colors.white.withOpacity(0.05),
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: isCurrentUser
                                              ? Colors.purple.withOpacity(0.6)
                                              : Colors.white.withOpacity(0.2),
                                          width: isCurrentUser ? 2 : 1.2,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color:
                                                Colors.black.withOpacity(0.08),
                                            blurRadius: 8,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
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
                                                _getPositionColor(position)
                                                    .withOpacity(0.8),
                                                _getPositionColor(position)
                                                    .withOpacity(0.4),
                                              ],
                                            ),
                                            border: Border.all(
                                              color:
                                                  _getPositionColor(position),
                                              width: 2,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color:
                                                    _getPositionColor(position)
                                                        .withOpacity(0.3),
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
                                                  fontWeight: isCurrentUser
                                                      ? FontWeight.bold
                                                      : FontWeight.normal,
                                                  fontSize:
                                                      isCurrentUser ? 16 : 14,
                                                  fontFamily: 'TheWitcher',
                                                  shadows: const [
                                                    Shadow(
                                                      color: Colors.black26,
                                                      blurRadius: 2,
                                                      offset: Offset(1, 1),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            if (isCurrentUser)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    colors: [
                                                      Colors.purple
                                                          .withOpacity(0.8),
                                                      Colors.purple
                                                          .withOpacity(0.6),
                                                    ],
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                                child: const Text(
                                                  'You',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    fontFamily: 'Battambang',
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        trailing: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              '$userScore',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 18,
                                                fontFamily: 'TheWitcher',
                                                shadows: [
                                                  Shadow(
                                                    color: Colors.black26,
                                                    blurRadius: 2,
                                                    offset: Offset(1, 1),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const Text(
                                              'points',
                                              style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: 12,
                                                fontFamily: 'Battambang',
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 40.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      gradient: LinearGradient(
                        colors: [
                          Colors.purple.withOpacity(0.7),
                          Colors.purple.withOpacity(0.5),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.purple.withOpacity(0.5),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => const HomeScreen()),
                        );
                      },
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "Return to Home",
                            style: TextStyle(
                              fontSize: 20,
                              fontFamily: 'TheWitcher',
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(
                            Icons.home,
                            color: Colors.white,
                            size: 24,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}