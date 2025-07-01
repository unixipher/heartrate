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
  final int score; // Add score parameter

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
    required this.score, // Add score parameter
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
  double _percentageInsideZone = 0.0;
  int _nudgeCount = 0;

  bool _isAppActive = true;
  bool _isLoading = true;
  bool _hasFetchedData = false;

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
    }
  }

  Future<void> _updateChallengeAndFetchData() async {
    // First update challenge status
    await _updateChallengeStatus();

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

  Future<void> _updateChallengeStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    final List<int> challengeIds =
        (widget.audioData as List).map((item) => item['id'] as int).toList();

    try {
      final response = await http.post(
        Uri.parse('https://authcheck.co/updatechallenge'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'challengeId': challengeIds,
          'status': true,
          'score': widget.score,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('Challenge updated successfully: ${response.statusCode}');
        debugPrint(widget.audioData.toString());
      }
    } catch (e) {
      debugPrint('Update challenge error: $e');
    }
  }

  Future<void> _fetchDataAndAnimate() async {
    try {
      final analysisData = await analyseHeartRate();
      if (!_isAppActive) return;

      debugPrint('Setting state with analysis data: $analysisData');

      setState(() {
        _averageHeartRate = analysisData['averageHeartRate'] ?? 0.0;
        _percentageInsideZone = analysisData['percentageInsideZone'] ?? 0.0;
        _hasFetchedData = true;
      });

      debugPrint(
          'State updated - avgHR: $_averageHeartRate, zonePercentage: $_percentageInsideZone');
      final maxHr = widget.maxheartRate ?? 200.0;
      final hrProgress = _averageHeartRate / maxHr;
      final zoneProgress = _percentageInsideZone / 100.0;
      final nudgeProgress = _nudgeCount / 7.0;

      debugPrint('Animation progress values:');
      debugPrint('- HR Progress: $hrProgress (${_averageHeartRate}/$maxHr)');
      debugPrint(
          '- Zone Progress: $zoneProgress (${_percentageInsideZone}/100)');
      debugPrint('- Nudge Progress: $nudgeProgress ($_nudgeCount/7)');

      _heartRateAnimation =
          Tween<double>(begin: 0.0, end: hrProgress.clamp(0.0, 1.0)).animate(
              CurvedAnimation(
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _confettiController.dispose();
    _animationController.dispose();
    super.dispose();
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
        debugPrint('Analysis response data: $data');

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

        double zone1Lower = (restingHR + (maxHR - restingHR) * 0.35)
            .toDouble(); // 35% intensity
        double zone1Upper = (restingHR + (maxHR - restingHR) * 0.75)
            .toDouble(); // 75% intensity
        double zone2Lower = (restingHR + (maxHR - restingHR) * 0.45)
            .toDouble(); // 45% intensity
        double zone2Upper = (restingHR + (maxHR - restingHR) * 0.85)
            .toDouble(); // 85% intensity
        double zone3Lower = (restingHR + (maxHR - restingHR) * 0.55)
            .toDouble(); // 55% intensity
        double zone3Upper = (restingHR + (maxHR - restingHR) * 0.95)
            .toDouble(); // 95% intensity

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

        debugPrint('Analysis results:');
        debugPrint('- Average Heart Rate: $averageHeartRate');
        debugPrint(
            '- Percentage Inside Target Zone: $percentageInsideTargetZone');
        debugPrint('- Percentage Inside Any Zone: $percentageInsideAnyZone');
        debugPrint('- Display Percentage: $displayPercentage');
        debugPrint(
            '- Target Zone bounds: $targetLowerBound - $targetUpperBound');

        return {
          'insideZone': insideTargetZone,
          'outsideZone': outsideZone,
          'averageHeartRate': averageHeartRate,
          'percentageInsideZone': displayPercentage,
        };
      } else {
        debugPrint('Analysis API error: ${response.statusCode}');
        debugPrint('Response body: ${response.body}');
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
        AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return Column(
              children: [
                _buildProgressBar(
                  animation: _heartRateAnimation,
                  label: 'Heart Rate',
                  icon: Icons.favorite_rounded,
                  progressColor: Colors.purple,
                  valueText: '${_averageHeartRate.toInt()} BPM',
                ),
                _buildProgressBar(
                  animation: _zoneTimeAnimation,
                  label: 'Zone Time',
                  icon: Icons.access_time,
                  progressColor: Colors.purple,
                  valueText: '${_percentageInsideZone.toInt()}%',
                ),
                _buildProgressBar(
                  animation: _nudgeAnimation,
                  label: 'Zone Nudges',
                  icon: Icons.notifications_active_rounded,
                  progressColor: Colors.purple,
                  valueText: '$_nudgeCount times',
                ),
              ],
            );
          },
        ),
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
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: [
                                      Colors.purple.shade300,
                                      Colors.purple.shade700
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.3),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: item['zoneId'] == 1
                                              ? Colors.purple.withOpacity(0.3)
                                              : item['zoneId'] == 2
                                                  ? Colors.purple
                                                      .withOpacity(0.3)
                                                  : Colors.purple
                                                      .withOpacity(0.3),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          'Zone: ${item['zoneId'] == 1 ? 'Walk' : item['zoneId'] == 2 ? 'Jog' : item['zoneId'] == 3 ? 'Run' : 'No Zone'}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontFamily: 'Battambang',
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              trailing: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withOpacity(0.1),
                                ),
                                child: const Icon(
                                  Icons.arrow_forward_ios,
                                  color: Colors.white54,
                                  size: 16,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
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
