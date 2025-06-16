import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:testingheartrate/screens/audioplayer/player_screen.dart';
import 'package:path_provider/path_provider.dart';

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

  @override
  void initState() {
    analytics.setAnalyticsCollectionEnabled(true);
    super.initState();
    fetchChallenges();
    _displayedDescription = '';
    _startTypewriter();
    _loadDownloadStatus();
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
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 16),
                          itemCount: filteredChallenges.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final challenge = filteredChallenges[index];
                            final challengeId = challenge['id'] as int;
                            final isDownloaded =
                                _downloadStatus[challengeId] ?? false;
                            final isDownloading =
                                _isDownloading[challengeId] ?? false;

                            return Opacity(
                              opacity: isDownloaded ? 1.0 : 0.5,
                              child: InkWell(
                                onTap: isDownloading
                                    ? null
                                    : () async {
                                        if (!isDownloaded) {
                                          await _downloadAudio(
                                              challenge['audiourl'],
                                              challengeId);
                                        } else {
                                          await analytics.logEvent(
                                            name: 'challenge_selected',
                                            parameters: {
                                              'challenge_id':
                                                  challenge['id'] ?? '',
                                              'challenge_title':
                                                  challenge['title'] ?? '',
                                            },
                                          );
                                          setState(() {
                                            selectedChallenge = index;
                                          });
                                          _showConfirmationDialog(context);
                                        }
                                      },
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: index == selectedChallenge &&
                                            isDownloaded
                                        ? Colors.purple[600]
                                        : Colors.blueGrey[700]!
                                            .withOpacity(0.8),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 50,
                                        height: 50,
                                        decoration: BoxDecoration(
                                          color: Colors.white24,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Center(
                                          child: isDownloading
                                              ? const CircularProgressIndicator(
                                                  color: Colors.white,
                                                  strokeWidth: 2,
                                                )
                                              : isDownloaded
                                                  ? const Icon(
                                                      Icons.play_arrow_rounded,
                                                      color: Colors.white,
                                                      size: 28,
                                                    )
                                                  : const Icon(
                                                      Icons.lock,
                                                      color: Colors.white,
                                                      size: 28,
                                                    ),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              challenge['title'] ?? '',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                                letterSpacing: 1,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            const Text(
                                              '5:00',
                                              style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.chevron_right,
                                          color: Colors.white54),
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
          ],
        ),
      ),
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

  void _showConfirmationDialog(BuildContext context) {
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
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Center(
                  child: Text(
                    'Continue with apple watch',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      minimumSize: const Size(150, 48),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      _showZoneSelector(context);
                    },
                    child: const Text(
                      'No',
                      style: TextStyle(
                          color: Colors.white,
                          fontFamily: 'Thewitcher',
                          fontSize: 18),
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      minimumSize: const Size(150, 48),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      _showZoneSelector(context);
                    },
                    child: const Text(
                      'Yes',
                      style: TextStyle(
                          color: Colors.white,
                          fontFamily: 'Thewitcher',
                          fontSize: 18),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 64),
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
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 90,
            height: 90,
            margin: const EdgeInsets.only(bottom: 48),
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
        ],
      ),
    );
  }

  void _showWorkoutTenureSelector(BuildContext context, int zoneId) {
    int selectedHour = 0;
    int selectedMinute = 5;
    int challengeCount = filteredChallenges.length;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (context) {
        bool isLoading = false;

        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
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
                        // Time Selector with Selection Bar
                        Container(
                          height: 150,
                          child: Stack(
                            children: [
                              // Selection Bar Background
                              Positioned(
                                top: 55, // Center of the wheel (150/2 - 40/2)
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
                              // Time Selectors
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // Hours Selector (only show if challenge count > 11)
                                  if (challengeCount > 11)
                                    SizedBox(
                                      width: 120,
                                      child: SizedBox(
                                        height: 150,
                                        child: ListWheelScrollView.useDelegate(
                                          itemExtent: 40,
                                          physics:
                                              const FixedExtentScrollPhysics(),
                                          onSelectedItemChanged: (index) {
                                            if (!isLoading) {
                                              setModalState(() {
                                                selectedHour = index;
                                                int maxMinute =
                                                    (challengeCount * 5)
                                                        .clamp(5, 55);
                                                int upper = maxMinute < 30
                                                    ? maxMinute
                                                    : 30;
                                                if (selectedHour == 1 &&
                                                    selectedMinute > upper) {
                                                  selectedMinute = upper;
                                                }
                                              });
                                            }
                                          },
                                          childDelegate:
                                              ListWheelChildBuilderDelegate(
                                            builder: (context, index) {
                                              return Center(
                                                child: index == 0
                                                    ? const SizedBox.shrink()
                                                    : Text(
                                                        '$index hr',
                                                        style: TextStyle(
                                                          color: selectedHour ==
                                                                  index
                                                              ? Colors.white
                                                              : Colors.grey
                                                                  .withOpacity(
                                                                      0.6),
                                                          fontSize: 22,
                                                          fontWeight:
                                                              selectedHour == index
                                                                  ? FontWeight
                                                                      .normal
                                                                  : FontWeight
                                                                      .normal,
                                                        ),
                                                      ),
                                              );
                                            },
                                            childCount: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (challengeCount > 11)
                                    const SizedBox(width: 4),
                                  // Minutes Selector
                                  SizedBox(
                                    width: 120,
                                    child: SizedBox(
                                      height: 150,
                                      child: ListWheelScrollView.useDelegate(
                                        itemExtent: 40,
                                        physics:
                                            const FixedExtentScrollPhysics(),
                                        onSelectedItemChanged: (index) {
                                          if (!isLoading) {
                                            setModalState(() {
                                              int maxMinute =
                                                  (challengeCount * 5)
                                                      .clamp(5, 55);
                                              if (selectedHour == 0) {
                                                int count = (maxMinute ~/ 5);
                                                selectedMinute =
                                                    5 + (index % count) * 5;
                                              } else {
                                                int upper = maxMinute < 30
                                                    ? maxMinute
                                                    : 30;
                                                int count = (upper ~/ 5);
                                                selectedMinute =
                                                    5 + (index % count) * 5;
                                              }
                                            });
                                          }
                                        },
                                        childDelegate:
                                            ListWheelChildBuilderDelegate(
                                          builder: (context, index) {
                                            int maxMinute = (challengeCount * 5)
                                                .clamp(5, 55);
                                            int minute;
                                            if (selectedHour == 0) {
                                              int count = (maxMinute ~/ 5);
                                              minute = 5 + (index % count) * 5;
                                            } else {
                                              int upper = maxMinute < 30
                                                  ? maxMinute
                                                  : 30;
                                              int count = (upper ~/ 5);
                                              minute = 5 + (index % count) * 5;
                                            }
                                            return Center(
                                              child: Text(
                                                '$minute min',
                                                style: TextStyle(
                                                  color:
                                                      selectedMinute == minute
                                                          ? Colors.white
                                                          : Colors.grey
                                                              .withOpacity(0.6),
                                                  fontSize: 22,
                                                  fontWeight:
                                                      selectedMinute == minute
                                                          ? FontWeight.normal
                                                          : FontWeight.normal,
                                                ),
                                              ),
                                            );
                                          },
                                          childCount: 100000,
                                        ),
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
                                  setModalState(() {
                                    isLoading = true;
                                  });

                                  try {
                                    final duration = Duration(
                                      hours: selectedHour,
                                      minutes: selectedMinute,
                                    );

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
                                            challengeCount: challengeCount,
                                            playingChallengeCount:
                                                challengesToSend,
                                          ),
                                        ),
                                      );
                                    }

                                    debugPrint('Selected Duration: $duration');
                                    debugPrint(
                                        'Challenges to send: $resolvedAudioData');
                                  } catch (e) {
                                    debugPrint('Error starting challenge: $e');

                                    if (mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Failed to start challenge. Please try again.',
                                            style: const TextStyle(
                                                color: Colors.white),
                                          ),
                                          backgroundColor: Colors.red,
                                          duration: const Duration(seconds: 3),
                                          action: SnackBarAction(
                                            label: 'Retry',
                                            textColor: Colors.white,
                                            onPressed: () {},
                                          ),
                                        ),
                                      );
                                    }
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
