import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<dynamic> completedChallenges = [];
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
        Uri.parse('https://authcheck.co/userchallenge'),
        headers: {
          'Accept': '*/*',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List<dynamic>;
        setState(() {
          completedChallenges = data
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
            'Failed to fetch challenges',
            style: TextStyle(
              color: Colors.black,
              fontFamily: 'Thewitcher',
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: Colors.white,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );
      debugPrint('Error fetching challenges: $e');
    }
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
                        // showModalBottomSheet(
                        //   context: context,
                        //   backgroundColor: const Color(0xFF0A0D29),
                        //   builder: (BuildContext context) {
                        //     return Container();
                        //   },
                        // );
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
                              challenge['challenge']['story']['title'] ??
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
