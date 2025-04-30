import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:testingheartrate/views/playing_screen.dart';

class AradiumHomePage extends StatefulWidget {
  final String title;
  final String description;
  final String jarekImagePath;
  final String backgroundImagePath;
  final int storyId;

  const AradiumHomePage({
    Key? key,
    required this.title,
    required this.description,
    required this.jarekImagePath,
    required this.backgroundImagePath,
    required this.storyId,
  }) : super(key: key);

  @override
  State<AradiumHomePage> createState() => _AradiumHomePageState();
}

class _AradiumHomePageState extends State<AradiumHomePage> {
  int selectedChallenge = 0;
  List<Map<String, dynamic>> filteredChallenges = [];

  @override
  void initState() {
    super.initState();
    fetchChallenges();
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
      });
    } else {
      debugPrint('Failed to fetch challenges: ${response.statusCode}');
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
                    bottom: 170,
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 42,
                        fontFamily: 'Thewitcher',
                        fontWeight: FontWeight.bold,
                        letterSpacing: 5,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    right: 40,
                    bottom: 20,
                    child: Text(
                      widget.description,
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'Battambang',
                        fontSize: 16,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Challenge List
            Expanded(
              flex: 5,
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

                            bool isLocked = false;

                            if (index == 0) {
                              isLocked = false;
                            } else {
                              final previousChallenge =
                                  filteredChallenges[index - 1];
                              isLocked =
                                  previousChallenge['completedAt'] == null;
                            }

                            return Opacity(
                              opacity: isLocked ? 0.5 : 1.0,
                              child: InkWell(
                                onTap: isLocked
                                    ? null
                                    : () {
                                        setState(() {
                                          selectedChallenge = index;
                                        });
                                        _showZoneSelector(context);
                                      },
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: index == selectedChallenge
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
                                          child: isLocked
                                              ? const Icon(Icons.lock,
                                                  color: Colors.white, size: 28)
                                              : const Icon(Icons.music_note,
                                                  color: Colors.white,
                                                  size: 28),
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
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildZoneButton('ZONE 1', 'WALK', zoneId: 1, onTap: () {
                    final audioUrl =
                        filteredChallenges[selectedChallenge]['audiourl'] ?? '';
                    final challengeId =
                        filteredChallenges[selectedChallenge]['id'] ?? '';
                    final challengeName =
                        filteredChallenges[selectedChallenge]['title'] ?? '';
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => MusicPlayerScreen(
                                  audioUrl: audioUrl,
                                  id: challengeId,
                                  challengeName: challengeName,
                                  image: widget.backgroundImagePath,
                                  zoneId: 1,
                                )));
                  }),
                  _buildZoneButton('ZONE 2', 'JOG', zoneId: 2, onTap: () {
                    final audioUrl =
                        filteredChallenges[selectedChallenge]['audiourl'] ?? '';
                    final challengeId =
                        filteredChallenges[selectedChallenge]['id'] ?? '';
                    final challengeName =
                        filteredChallenges[selectedChallenge]['title'] ?? '';
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => MusicPlayerScreen(
                                  audioUrl: audioUrl,
                                  id: challengeId,
                                  challengeName: challengeName,
                                  image: widget.backgroundImagePath,
                                  zoneId: 2,
                                )));
                  }),
                  _buildZoneButton('ZONE 3', 'RUN', zoneId: 3, onTap: () {
                    final audioUrl =
                        filteredChallenges[selectedChallenge]['audiourl'] ?? '';
                    final challengeId =
                        filteredChallenges[selectedChallenge]['id'] ?? '';
                    final challengeName =
                        filteredChallenges[selectedChallenge]['title'] ?? '';
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => MusicPlayerScreen(
                                  audioUrl: audioUrl,
                                  id: challengeId,
                                  challengeName: challengeName,
                                  image: widget.backgroundImagePath,
                                  zoneId: 3,
                                )));
                  }),
                ],
              ),
            ),
        );
      },
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
}
