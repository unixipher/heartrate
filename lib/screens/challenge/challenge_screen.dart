import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:testingheartrate/screens/audioplayer/player_screen.dart';
import 'package:path_provider/path_provider.dart';
import 'package:just_audio/just_audio.dart';

class ChallengeScreen extends StatefulWidget {
  final String title;
  final String description;
  final String jarekImagePath;
  final String backgroundImagePath;
  final String storydescription;
  final int storyId;
  final String characterName;

  const ChallengeScreen({
    Key? key,
    required this.title,
    required this.description,
    required this.jarekImagePath,
    required this.backgroundImagePath,
    required this.storyId,
    required this.storydescription,
    required this.characterName,
  }) : super(key: key);

  @override
  State<ChallengeScreen> createState() => _ChallengeScreenState();
}

class _ChallengeScreenState extends State<ChallengeScreen> {
  int selectedChallenge = 0;
  List<Map<String, dynamic>> filteredChallenges = [];
  late String _displayedDescription;
  int _descriptionIndex = 0;
  Timer? _typewriterTimer;
  final ScrollController _descScrollController = ScrollController();
  final FirebaseAnalytics analytics = FirebaseAnalytics.instance;
  final Map<int, bool> _downloadStatus = {};
  final Map<int, bool> _isDownloading = {};
  final Map<int, List<int>> _challengeScores =
      {}; // Store completion scores for each challenge
  final Map<int, int> _challengePlayCounts =
      {}; // Store play counts for each challenge
  final Map<int, Duration> _audioDurations =
      {}; // Store audio durations for each challenge
  final Map<int, bool> _durationLoading =
      {}; // Track which durations are being loaded
  int _maxHR = 200; // Default value

  @override
  void initState() {
    analytics.setAnalyticsCollectionEnabled(true);
    super.initState();
    fetchChallenges();
    _displayedDescription = '';
    _startTypewriter();
    _loadDownloadStatus();
    _loadMaxHR();
    // Load challenge scores after a brief delay to ensure filteredChallenges is populated
    Future.delayed(const Duration(milliseconds: 500), () {
      if (filteredChallenges.isNotEmpty) {
        _loadChallengeScores();
        _loadChallengePlayCounts();
        _loadAudioDurations();
      }
    });
  }

  @override
  void dispose() {
    _typewriterTimer?.cancel();
    _descScrollController.dispose();
    super.dispose();
  }

  void _startTypewriter() {
    final words = widget.storydescription.split(' ');
    _displayedDescription = '';
    _descriptionIndex = 0;
    _typewriterTimer =
        Timer.periodic(const Duration(milliseconds: 300), (timer) {
      if (_descriptionIndex < words.length) {
        setState(() {
          if (_displayedDescription.isEmpty) {
            _displayedDescription = words[_descriptionIndex];
          } else {
            _displayedDescription += ' ${words[_descriptionIndex]}';
          }
          _descriptionIndex++;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_descScrollController.hasClients) {
            _descScrollController.jumpTo(
              _descScrollController.position.maxScrollExtent,
            );
          }
        });
      } else {
        timer.cancel();
        _typewriterTimer = null;
      }
    });
  }

  Future<void> _loadDownloadStatus() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      for (var challenge in filteredChallenges) {
        final id = challenge['id'] as int;
        _downloadStatus[id] = prefs.getBool('downloaded_$id') ?? false;
        _isDownloading[id] = false;
      }
    });
  }

  Future<void> _loadMaxHR() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _maxHR = prefs.getInt('maxhr') ?? 200;
    });
  }

  Future<void> _loadChallengeScores() async {
    final prefs = await SharedPreferences.getInstance();

    for (var challenge in filteredChallenges) {
      final challengeId = challenge['id'] as int;
      final challengeName = challenge['title'] as String;
      List<int> scores = [];

      // Look for all completion entries for this challenge
      // We'll check up to 10 possible completions (can be adjusted)
      for (int completion = 1; completion <= 10; completion++) {
        final String audioKey =
            'audio_completion_${challengeId}_${challengeName}_completion_$completion';
        final String? completionDataJson = prefs.getString(audioKey);

        if (completionDataJson != null) {
          try {
            final Map<String, dynamic> completionData =
                jsonDecode(completionDataJson);
            final int score = completionData['score'] ?? 0;
            scores.add(score);
          } catch (e) {
            debugPrint('Error parsing completion data for $audioKey: $e');
          }
        }
      }

      if (scores.isNotEmpty) {
        setState(() {
          _challengeScores[challengeId] = scores;
        });
      }
    }

    debugPrint('Loaded challenge scores: $_challengeScores');
  }

  Future<void> _loadChallengePlayCounts() async {
    final prefs = await SharedPreferences.getInstance();

    for (var challenge in filteredChallenges) {
      final challengeId = challenge['id'] as int;
      final playCount = prefs.getInt('challenge_play_count_$challengeId') ?? 0;

      setState(() {
        _challengePlayCounts[challengeId] = playCount;
      });
    }

    debugPrint('Loaded challenge play counts: $_challengePlayCounts');
  }

  Future<void> _loadAudioDurations() async {
    final prefs = await SharedPreferences.getInstance();

    for (var challenge in filteredChallenges) {
      final challengeId = challenge['id'] as int;

      // Check if duration is cached
      final cachedDurationMs = prefs.getInt('audio_duration_$challengeId');
      if (cachedDurationMs != null) {
        setState(() {
          _audioDurations[challengeId] =
              Duration(milliseconds: cachedDurationMs);
        });
        continue;
      }

      // Skip if already loaded or loading
      if (_audioDurations.containsKey(challengeId) ||
          _durationLoading[challengeId] == true) {
        continue;
      }

      setState(() {
        _durationLoading[challengeId] = true;
      });

      _loadSingleAudioDuration(challenge);
    }
  }

  Future<void> _loadSingleAudioDuration(Map<String, dynamic> challenge) async {
    final challengeId = challenge['id'] as int;
    final audioUrl = challenge['audiourl'] as String?;
    final prefs = await SharedPreferences.getInstance();

    if (audioUrl != null && audioUrl.isNotEmpty) {
      try {
        final player = AudioPlayer();
        await player.setUrl(audioUrl);
        final duration = player.duration;

        if (duration != null && mounted) {
          // Cache the duration
          await prefs.setInt(
              'audio_duration_$challengeId', duration.inMilliseconds);

          setState(() {
            _audioDurations[challengeId] = duration;
            _durationLoading[challengeId] = false;
          });
        }

        await player.dispose();
      } catch (e) {
        debugPrint('Error getting duration for challenge $challengeId: $e');
        // Set a default duration if we can't get the actual duration
        final defaultDuration = const Duration(minutes: 5);
        await prefs.setInt(
            'audio_duration_$challengeId', defaultDuration.inMilliseconds);

        if (mounted) {
          setState(() {
            _audioDurations[challengeId] = defaultDuration;
            _durationLoading[challengeId] = false;
          });
        }
      }
    } else {
      final defaultDuration = const Duration(minutes: 5);
      await prefs.setInt(
          'audio_duration_$challengeId', defaultDuration.inMilliseconds);

      if (mounted) {
        setState(() {
          _audioDurations[challengeId] = defaultDuration;
          _durationLoading[challengeId] = false;
        });
      }
    }
  }

  String _formatDuration(Duration? duration, {bool isLoading = false}) {
    if (isLoading) return 'Loading...';
    if (duration == null) return '5:00 minutes'; // fallback

    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;

    if (minutes == 0) {
      return '${seconds}s';
    } else if (seconds == 0) {
      return '${minutes}:00 minutes';
    } else {
      return '${minutes}:${seconds.toString().padLeft(2, '0')} minutes';
    }
  }

  Future<void> _incrementPlayCount(int challengeId) async {
    final prefs = await SharedPreferences.getInstance();
    final currentCount = prefs.getInt('challenge_play_count_$challengeId') ?? 0;
    final newCount = currentCount + 1;

    await prefs.setInt('challenge_play_count_$challengeId', newCount);

    setState(() {
      _challengePlayCounts[challengeId] = newCount;
    });

    debugPrint(
        'Incremented play count for challenge $challengeId to $newCount');
  }

  bool _isChallengeUnlocked(int index) {
    // First challenge is always unlocked
    if (index == 0) return true;

    // Check if previous challenge play count is not 0
    final previousChallenge = filteredChallenges[index - 1];
    final previousChallengeId = previousChallenge['id'] as int;
    final previousPlayCount = _challengePlayCounts[previousChallengeId] ?? 0;

    return previousPlayCount != 0;
  }

  Map<String, int> _calculateHeartRateRange(int zone) {
    int lowerBound, upperBound;

    switch (zone) {
      case 1:
        lowerBound = (72 + (_maxHR - 72) * 0.35).round();
        upperBound = (72 + (_maxHR - 72) * 0.75).round();
        break;
      case 2:
        lowerBound = (72 + (_maxHR - 72) * 0.45).round();
        upperBound = (72 + (_maxHR - 72) * 0.85).round();
        break;
      case 3:
        lowerBound = (72 + (_maxHR - 72) * 0.55).round();
        upperBound = (72 + (_maxHR - 72) * 0.95).round();
        break;
      default:
        lowerBound = 72;
        upperBound = _maxHR;
    }

    return {'lower': lowerBound, 'upper': upperBound};
  }

  Future<String> _downloadAudio(String url, int challengeId) async {
    try {
      setState(() {
        _isDownloading[challengeId] = true;
      });

      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception('Failed to download audio: ${response.statusCode}');
      }

      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/challenge_$challengeId.mp3';
      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('downloaded_$challengeId', true);

      setState(() {
        _downloadStatus[challengeId] = true;
        _isDownloading[challengeId] = false;
      });

      debugPrint('Audio downloaded to: $filePath');
      return filePath;
    } catch (e) {
      setState(() {
        _isDownloading[challengeId] = false;
      });
      debugPrint('Error downloading audio: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to download challenge audio.'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      rethrow;
    }
  }

  Future<void> fetchChallenges() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    if (token.isEmpty) {
      debugPrint('Token not found');
      return;
    }

    final response = await http.get(
      Uri.parse('https://authcheck.co/userchallenge'),
      headers: {
        'Accept': '/',
        'Authorization': 'Bearer $token',
        'User-Agent': 'Thunder Client (https://www.thunderclient.com)',
      },
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);

      final filtered = data.where((item) {
        return item['challenge'] != null &&
            item['challenge']['storyId'] == widget.storyId;
      }).map<Map<String, dynamic>>((item) {
        return {
          'id': item['challenge']['id'],
          'title': item['challenge']['title'],
          'audiourl': item['challenge']['audiourl'],
          'imageurl': item['challenge']['imageurl'],
          'status': item['status'],
          'completedAt': item['completedAt'],
        };
      }).toList();

      filtered.sort((a, b) => a['id'].compareTo(b['id']));

      setState(() {
        filteredChallenges = filtered;
        for (var challenge in filteredChallenges) {
          final id = challenge['id'] as int;
          _downloadStatus[id] = false;
          _isDownloading[id] = false;
        }
      });

      await _loadDownloadStatus();
      await _loadChallengeScores();
      await _loadChallengePlayCounts();
      _loadAudioDurations(); // Load durations in background
    } else {
      debugPrint('Failed to fetch challenges: ${response.statusCode}');
    }
  }

  Future<void> _startChallenge(
      List<Map<String, dynamic>> audioData, int zoneId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    try {
      final List<int> challengeIds =
          audioData.map((item) => item['id'] as int).toList();

      final response = await http.post(
        Uri.parse('https://authcheck.co/startchallenge'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'challengeId': challengeIds,
          'zoneId': zoneId,
        }),
      );

      debugPrint('Start challenge IDs: $challengeIds');

      if (response.statusCode == 200) {
        debugPrint('Challenge started successfully: ${response.statusCode}');
        return;
      } else {
        debugPrint('Failed to start challenge: ${response.statusCode}');
        throw Exception('Failed to start challenge');
      }
    } catch (e) {
      debugPrint('Start challenge error: $e');
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(widget.backgroundImagePath),
            colorFilter: ColorFilter.mode(
              Colors.black.withOpacity(0.5),
              BlendMode.darken,
            ),
            fit: BoxFit.cover,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              flex: 4,
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 62.0, left: 12.0),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back_ios,
                            color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    width: MediaQuery.of(context).size.width * 0.7,
                    child: Image.asset(
                      widget.jarekImagePath,
                      fit: BoxFit.contain,
                    ),
                  ),
                  Positioned(
                    left: 20,
                    bottom: 200,
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 20,
                        fontFamily: 'Battambang',
                        fontWeight: FontWeight.bold,
                        letterSpacing: 5,
                      ),
                    ),
                  ),
                  const Positioned(
                    left: 20,
                    bottom: 225,
                    child: Text(
                      "in",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                        fontFamily: 'Battambang',
                        fontWeight: FontWeight.bold,
                        letterSpacing: 5,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    bottom: 240,
                    child: Text(
                      widget.characterName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontFamily: 'Thewitcher',
                        fontWeight: FontWeight.bold,
                        letterSpacing: 5,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    bottom: 10,
                    child: SizedBox(
                      width: MediaQuery.of(context).size.width / 3,
                      child: _buildStoryDescription(),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 4,
              child: Container(
                color: Colors.black.withOpacity(0.7),
                child: filteredChallenges.isEmpty
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: fetchChallenges,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 16),
                          itemCount: filteredChallenges.length,
                          itemBuilder: (context, index) {
                            final challenge = filteredChallenges[index];
                            final challengeId = challenge['id'] as int;
                            final isDownloaded =
                                _downloadStatus[challengeId] ?? false;
                            final isDownloading =
                                _isDownloading[challengeId] ?? false;
                            final isUnlocked = _isChallengeUnlocked(index);
                            final isCompleted =
                                _challengeScores[challengeId] != null &&
                                    _challengeScores[challengeId]!.isNotEmpty;

                            return _buildTimelineItem(
                              context,
                              index,
                              challenge,
                              challengeId,
                              isDownloaded,
                              isDownloading,
                              isUnlocked,
                              isCompleted,
                            );
                          },
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineItem(
    BuildContext context,
    int index,
    Map<String, dynamic> challenge,
    int challengeId,
    bool isDownloaded,
    bool isDownloading,
    bool isUnlocked,
    bool isCompleted,
  ) {
    final isLast = index == filteredChallenges.length - 1;

    // Calculate dynamic content height based on actual content structure
    final containerPadding =
        40.0; // padding: EdgeInsets.all(20) = 20 top + 20 bottom
    final containerMargin = 20.0; // margin: EdgeInsets.only(bottom: 20)
    final titleHeight = 24.0; // Approximate height for title (fontSize: 18)
    final spacingAfterTitle = 6.0; // SizedBox(height: 6)
    final durationHeight =
        18.0; // Approximate height for duration text (fontSize: 14)
    final scoreDisplayHeight = 30.0; // Height for score display area
    final completedSectionSpacing = isCompleted
        ? 12.0
        : 0.0; // SizedBox(height: 12) before completed section
    final completedSectionHeight =
        isCompleted ? 32.0 : 0.0; // Height for completed section if shown

    final totalContentHeight = containerPadding +
        titleHeight +
        spacingAfterTitle +
        durationHeight +
        scoreDisplayHeight +
        completedSectionSpacing +
        completedSectionHeight +
        containerMargin;
    final timelineLineHeight =
        totalContentHeight - 35; // Position to connect properly to next circle

    return Stack(
      children: [
        // Timeline line
        if (!isLast)
          Positioned(
            left: 35,
            top: 80,
            child: Container(
              width: 3,
              height: timelineLineHeight,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    isCompleted ? Colors.purple[400]! : Colors.grey[600]!,
                    _isChallengeUnlocked(index + 1) &&
                            _challengeScores[filteredChallenges[index + 1]
                                    ['id']] !=
                                null
                        ? Colors.purple[400]!
                        : Colors.grey[600]!,
                  ],
                ),
              ),
            ),
          ),

        // Timeline item
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Timeline node
            Column(
              children: [
                InkWell(
                  onTap: isDownloading
                      ? null
                      : () async {
                          if (!isUnlocked) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text(
                                  'Complete previous challenges to unlock this one.',
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
                                width: 240,
                              ),
                            );
                            return;
                          }

                          if (!isDownloaded) {
                            await _downloadAudio(
                                challenge['audiourl'], challengeId);
                          } else {
                            await analytics.logEvent(
                              name: 'challenge_selected',
                              parameters: {
                                'challenge_id': challenge['id'] ?? '',
                                'challenge_title': challenge['title'] ?? '',
                              },
                            );
                            setState(() {
                              selectedChallenge = index;
                            });
                            _showZoneSelector(context);
                          }
                        },
                  borderRadius: BorderRadius.circular(35),
                  child: Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: !isUnlocked
                          ? Colors.grey[800]!.withOpacity(0.5)
                          : isCompleted
                              ? Colors.purple[600]
                              : isDownloaded
                                  ? Colors.blue[600]
                                  : Colors.grey[600],
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 2,
                      ),
                      boxShadow: [
                        if (isCompleted || (isUnlocked && isDownloaded))
                          BoxShadow(
                            color: (isCompleted
                                    ? Colors.purple[600]!
                                    : Colors.blue[600]!)
                                .withOpacity(0.3),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                      ],
                    ),
                    child: Center(
                      child: isDownloading
                          ? const CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            )
                          : !isUnlocked
                              ? const Icon(
                                  Icons.lock_outline,
                                  color: Colors.white54,
                                  size: 32,
                                )
                              : isCompleted
                                  ? const Icon(
                                      Icons.check_circle,
                                      color: Colors.white,
                                      size: 32,
                                    )
                                  : isDownloaded
                                      ? const Icon(
                                          Icons.play_arrow_rounded,
                                          color: Colors.white,
                                          size: 32,
                                        )
                                      : const Icon(
                                          Icons.play_arrow,
                                          color: Colors.white,
                                          size: 32,
                                        ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),

            const SizedBox(width: 20),

            // Challenge content
            Expanded(
              child: Opacity(
                opacity: isUnlocked ? (isDownloaded ? 1.0 : 0.7) : 0.4,
                child: InkWell(
                  onTap: isDownloading
                      ? null
                      : () async {
                          if (!isUnlocked) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text(
                                  'Complete previous challenges to unlock this one.',
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
                                width: 240,
                              ),
                            );
                            return;
                          }

                          if (!isDownloaded) {
                            await _downloadAudio(
                                challenge['audiourl'], challengeId);
                          } else {
                            await analytics.logEvent(
                              name: 'challenge_selected',
                              parameters: {
                                'challenge_id': challenge['id'] ?? '',
                                'challenge_title': challenge['title'] ?? '',
                              },
                            );
                            setState(() {
                              selectedChallenge = index;
                            });
                            _showZoneSelector(context);
                          }
                        },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: !isUnlocked
                          ? Colors.grey[800]!.withOpacity(0.3)
                          : index == selectedChallenge && isDownloaded
                              ? Colors.purple[600]!.withOpacity(0.8)
                              : Colors.blueGrey[700]!.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    challenge['title'] ?? '',
                                    style: TextStyle(
                                      color: isUnlocked
                                          ? Colors.white
                                          : Colors.white54,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  // Text(
                                  //   _formatDuration(
                                  //     _audioDurations[challengeId],
                                  //     isLoading:
                                  //         _durationLoading[challengeId] ??
                                  //             false,
                                  //   ),
                                  //   style: TextStyle(
                                  //     color: isUnlocked
                                  //         ? Colors.white70
                                  //         : Colors.white38,
                                  //     fontSize: 14,
                                  //   ),
                                  // ),
                                  if ((_challengePlayCounts[challengeId] ??
                                          0) !=
                                      0)
                                    Text(
                                      'Completed ${_challengePlayCounts[challengeId]} time${(_challengePlayCounts[challengeId] ?? 0) == 1 ? '' : 's'}',
                                      style: TextStyle(
                                        color: isUnlocked
                                            ? Colors.white70
                                            : Colors.white38,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            _buildScoreDisplay(challengeId, isUnlocked),
                          ],
                        ),
                        // if (isCompleted) ...[
                        //   const SizedBox(height: 12),
                        //   Container(
                        //     padding: const EdgeInsets.symmetric(
                        //         horizontal: 12, vertical: 6),
                        //     child: Text(
                        //       'Challenge Completed ${_challengePlayCounts[challengeId] ?? 0} time',
                        //       style: const TextStyle(
                        //         color: Colors.white,
                        //         fontSize: 12,
                        //         fontWeight: FontWeight.w500,
                        //       ),
                        //     ),
                        //   ),
                        // ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildScoreDisplay(int challengeId, [bool isUnlocked = true]) {
    final scores = _challengeScores[challengeId];
    final playCount = _challengePlayCounts[challengeId] ?? 0;

    // If challenge is locked, show locked message
    if (!isUnlocked) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey[800]!.withOpacity(0.6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'Locked',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    if (scores == null || scores.isEmpty) {
      // No scores available, show play count or download status
      if (playCount > 0) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange[600]!.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'In Progress',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      }
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.blue[600]!.withOpacity(0.7),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'Ready',
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    // Show the latest (highest completion number) score and play count
    final latestScore = scores.last;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.purple[600]!, Colors.purple[400]!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
              BoxShadow(
                color: Colors.purple[600]!.withOpacity(0.3),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 4),
              Text(
                '$latestScore/40 pts',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showZoneSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0A0D29),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon:
                          const Icon(Icons.arrow_back_ios, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Text(
                      'Select Zone',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildZoneButton('ZONE 1', 'WALK', zoneId: 1,
                        onTap: () async {
                      await analytics.logEvent(
                        name: 'zone_1_selected',
                        parameters: {
                          'zone': 1,
                        },
                      );
                      Navigator.pop(context);
                      _showWorkoutTenureSelector(context, 1);
                    }),
                    _buildZoneButton('ZONE 2', 'JOG', zoneId: 2,
                        onTap: () async {
                      await analytics.logEvent(
                        name: 'zone_2_selected',
                        parameters: {
                          'zone': 2,
                        },
                      );
                      Navigator.pop(context);
                      _showWorkoutTenureSelector(context, 2);
                    }),
                    _buildZoneButton('ZONE 3', 'RUN', zoneId: 3,
                        onTap: () async {
                      await analytics.logEvent(
                        name: 'zone_3_selected',
                        parameters: {
                          'zone': 3,
                        },
                      );
                      Navigator.pop(context);
                      _showWorkoutTenureSelector(context, 3);
                    }),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStoryDescription() {
    const textStyle = TextStyle(
      color: Colors.white70,
      fontFamily: 'Battambang',
      fontSize: 16,
      letterSpacing: 1,
    );

    return SizedBox(
      height: 180,
      child: SingleChildScrollView(
        controller: _descScrollController,
        child: Text(
          _displayedDescription,
          style: textStyle,
          textAlign: TextAlign.left,
        ),
      ),
    );
  }

  Widget _buildZoneButton(String title, String action,
      {VoidCallback? onTap, required int zoneId}) {
    final heartRateRange = _calculateHeartRateRange(zoneId);
    final hrText = '${heartRateRange['lower']}-${heartRateRange['upper']} BPM';

    // Speed ranges for each zone
    String speedText;
    switch (zoneId) {
      case 1:
        speedText = '3.0-7.0 km/h';
        break;
      case 2:
        speedText = '5.0-9.0 km/h';
        break;
      case 3:
        speedText = '7.0-13.0 km/h';
        break;
      default:
        speedText = '';
    }

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 90,
            height: 90,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.purple[600],
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    action,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            width: 90,
            margin: const EdgeInsets.only(bottom: 16),
            child: Column(
              children: [
                Text(
                  hrText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  speedText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showWorkoutTenureSelector(BuildContext context, int zoneId) {
    // Calculate the maximum possible workout duration in minutes based on the selected starting challenge.
    final int maxMinutes = (filteredChallenges.length - selectedChallenge) * 5;
    final int maxHours = maxMinutes ~/ 60;

    // Initialize selected time.
    int selectedHour = 0;
    // Default to 5 minutes, clamped by the maximum possible duration.
    int selectedMinute = 5.clamp(0, maxMinutes);

    // Controllers for the time pickers to allow resetting their position.
    final FixedExtentScrollController hourScrollController =
        FixedExtentScrollController(initialItem: selectedHour);
    final FixedExtentScrollController minuteScrollController =
        FixedExtentScrollController(initialItem: (selectedMinute ~/ 5) - 1);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (context) {
        bool isLoading = false;

        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            // Determine the number of minute options for the currently selected hour.
            int maxMinutesForSelectedHour =
                (selectedHour < maxHours) ? 55 : maxMinutes % 60;
            int minuteOptionsCount = (maxMinutesForSelectedHour ~/ 5);

            return Stack(
              children: [
                Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFF0A0D29),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: AbsorbPointer(
                    absorbing: isLoading,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back_ios,
                                    color: Colors.white),
                                onPressed: isLoading
                                    ? null
                                    : () => Navigator.pop(context),
                              ),
                              const Text(
                                'Set Workout Time',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              TextButton(
                                onPressed: isLoading
                                    ? null
                                    : () {
                                        Navigator.pop(context);
                                        _showZoneSelector(context);
                                      },
                                child: const Text(
                                  'Skip',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Time Selector
                        Container(
                          height: 150,
                          child: Stack(
                            children: [
                              Positioned(
                                top: 55,
                                left: 0,
                                right: 0,
                                child: Container(
                                  height: 40,
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 20),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.3),
                                      width: 1,
                                    ),
                                  ),
                                ),
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // Hours Selector
                                  if (maxHours > 0)
                                    SizedBox(
                                      width: 120,
                                      height: 150,
                                      child: ListWheelScrollView.useDelegate(
                                        controller: hourScrollController,
                                        itemExtent: 40,
                                        physics:
                                            const FixedExtentScrollPhysics(),
                                        onSelectedItemChanged: (index) {
                                          if (!isLoading) {
                                            setModalState(() {
                                              selectedHour = index;
                                              // If the selected minute is now invalid, reset it.
                                              int newMaxMinutes =
                                                  (selectedHour < maxHours)
                                                      ? 55
                                                      : maxMinutes % 60;
                                              if (selectedMinute >
                                                  newMaxMinutes) {
                                                selectedMinute = 5;
                                                minuteScrollController
                                                    .jumpToItem(0);
                                              }
                                            });
                                          }
                                        },
                                        childDelegate:
                                            ListWheelChildBuilderDelegate(
                                          builder: (context, index) => Center(
                                            child: Text(
                                              '$index hr',
                                              style: TextStyle(
                                                color: selectedHour == index
                                                    ? Colors.white
                                                    : Colors.grey
                                                        .withOpacity(0.6),
                                                fontSize: 22,
                                              ),
                                            ),
                                          ),
                                          childCount: maxHours + 1,
                                        ),
                                      ),
                                    ),
                                  if (maxHours > 0) const SizedBox(width: 4),
                                  // Minutes Selector
                                  SizedBox(
                                    width: 120,
                                    height: 150,
                                    child: ListWheelScrollView.useDelegate(
                                      controller: minuteScrollController,
                                      itemExtent: 40,
                                      physics: const FixedExtentScrollPhysics(),
                                      onSelectedItemChanged: (index) {
                                        if (!isLoading) {
                                          setModalState(() {
                                            selectedMinute = 5 + (index * 5);
                                          });
                                        }
                                      },
                                      childDelegate:
                                          ListWheelChildBuilderDelegate(
                                        builder: (context, index) {
                                          final minute = 5 + (index * 5);
                                          return Center(
                                            child: Text(
                                              '$minute min',
                                              style: TextStyle(
                                                color: selectedMinute == minute
                                                    ? Colors.white
                                                    : Colors.grey
                                                        .withOpacity(0.6),
                                                fontSize: 22,
                                              ),
                                            ),
                                          );
                                        },
                                        childCount: minuteOptionsCount,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Confirm Button
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                isLoading ? Colors.grey : Colors.purple,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            minimumSize: const Size(150, 48),
                          ),
                          onPressed: isLoading
                              ? null
                              : () async {
                                  // Same logic as before
                                  setModalState(() {
                                    isLoading = true;
                                  });

                                  try {
                                    final duration = Duration(
                                      hours: selectedHour,
                                      minutes: selectedMinute,
                                    );
                                    // ... rest of your existing logic
                                    final totalMinutes = duration.inMinutes;
                                    final challengesToSend =
                                        (totalMinutes / 5).floor();

                                    final audioData = filteredChallenges
                                        .skip(selectedChallenge)
                                        .take(challengesToSend)
                                        .map((challenge) async {
                                      final challengeId =
                                          challenge['id'] as int;
                                      final isDownloaded =
                                          _downloadStatus[challengeId] ?? false;
                                      String audioPath;
                                      if (isDownloaded) {
                                        final directory =
                                            await getApplicationDocumentsDirectory();
                                        audioPath =
                                            '${directory.path}/challenge_$challengeId.mp3';
                                      } else {
                                        audioPath = await _downloadAudio(
                                            challenge['audiourl'], challengeId);
                                      }
                                      if (!audioPath.startsWith('file://')) {
                                        audioPath = 'file://$audioPath';
                                      }
                                      return {
                                        'audioUrl': audioPath,
                                        'id': challenge['id'] ?? '',
                                        'challengeName':
                                            challenge['title'] ?? '',
                                        'image': widget.backgroundImagePath,
                                        'zoneId': zoneId,
                                        'indexid': filteredChallenges
                                            .indexOf(challenge),
                                        'storyId': widget.storyId,
                                      };
                                    }).toList();

                                    final resolvedAudioData =
                                        await Future.wait(audioData);

                                    await _startChallenge(
                                        resolvedAudioData, zoneId);

                                    // Increment play count for each challenge that will be played
                                    for (var audioItem in resolvedAudioData) {
                                      final challengeId =
                                          audioItem['id'] as int;
                                      await _incrementPlayCount(challengeId);
                                    }

                                    await analytics.logEvent(
                                      name: 'workout_started',
                                      parameters: {
                                        'zone_id': zoneId,
                                        'duration_minutes': totalMinutes,
                                        'challenge_count': challengesToSend,
                                        'story_id': widget.storyId,
                                      },
                                    );

                                    if (mounted) {
                                      Navigator.pop(context);
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => PlayerScreen(
                                            audioData:
                                                List<Map<String, dynamic>>.from(
                                                    resolvedAudioData)
                                                  ..sort((a, b) => a['indexid']
                                                      .compareTo(b['indexid'])),
                                            challengeCount:
                                                filteredChallenges.length,
                                            playingChallengeCount:
                                                challengesToSend,
                                          ),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    debugPrint('Error starting challenge: $e');
                                    // ... error handling
                                  } finally {
                                    if (mounted) {
                                      setModalState(() {
                                        isLoading = false;
                                      });
                                    }
                                  }
                                },
                          child: isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Confirm',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'Thewitcher',
                                    fontSize: 18,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
