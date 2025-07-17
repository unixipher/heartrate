import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  List<dynamic> leaderboardData = [];
  Map<String, dynamic>? userData;
  bool isLoading = true;
  bool isLeaderboardLoading = false;
  String selectedLeaderboardType = 'global'; // 'global' or 'local'
  String currentCityName = 'Local'; // Default fallback
  final ScrollController _leaderboardScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    fetchUserData();
    fetchLeaderboard();
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
          isLoading = false;
        });

        // After fetching user data, fetch the current city
        fetchCurrentCity();

        // Try to scroll to current user if leaderboard is already loaded
        _scrollToCurrentUser();
      } else {
        setState(() {
          isLoading = false;
        });
        throw Exception('Failed to load user data');
      }
    } catch (e) {
      setState(() {
        isLoading = false;
      });
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

  void _scrollToCurrentUser() {
    debugPrint('_scrollToCurrentUser called');
    debugPrint('userData: ${userData != null ? "available" : "null"}');
    debugPrint('leaderboardData: ${leaderboardData.length} items');
    debugPrint('selectedLeaderboardType: $selectedLeaderboardType');

    if (userData == null || leaderboardData.isEmpty) {
      debugPrint('Cannot scroll: userData or leaderboardData not ready');
      return;
    }

    // Filter and sort leaderboard data based on current selection
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

    // Find current user's position in filtered leaderboard
    int currentUserIndex = -1;
    for (int i = 0; i < filteredData.length; i++) {
      if (filteredData[i]['id'] == userData!['id']) {
        currentUserIndex = i;
        break;
      }
    }

    debugPrint(
        'Current user found at index: $currentUserIndex in filtered data (${filteredData.length} items)');

    if (currentUserIndex != -1) {
      // Delay scroll to ensure the ListView is built
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (_leaderboardScrollController.hasClients) {
          // Calculate scroll position to center the user's item
          const double itemHeight = 80.0; // Each item height including margins
          double scrollPosition = currentUserIndex * itemHeight;

          // Get the viewport height to calculate center offset
          double viewportHeight =
              _leaderboardScrollController.position.viewportDimension;
          double centerOffset = viewportHeight - (itemHeight / 2);

          // Adjust scroll position to center the item
          double centeredScrollPosition = scrollPosition - centerOffset;

          // Ensure we don't scroll beyond the bounds
          double maxScrollExtent =
              _leaderboardScrollController.position.maxScrollExtent;
          centeredScrollPosition =
              centeredScrollPosition.clamp(0.0, maxScrollExtent);

          debugPrint(
              'Scrolling to position: $centeredScrollPosition (centered from $scrollPosition)');
          debugPrint(
              'Viewport height: $viewportHeight, Center offset: $centerOffset');

          // Scroll to position with animation
          _leaderboardScrollController.animateTo(
            centeredScrollPosition,
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeInOut,
          );
        } else {
          debugPrint('ScrollController does not have clients yet');
        }
      });
    } else {
      debugPrint('Current user not found in filtered leaderboard');
    }
  }

  @override
  void dispose() {
    _leaderboardScrollController.dispose();
    super.dispose();
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
        controller: _leaderboardScrollController,
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
    return Scaffold(
      backgroundColor: const Color(0xFF0A0D29),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0D29),
        title: const Text(
          'Leaderboard',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Colors.white,
              ),
            )
          : Column(
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
                            // Auto-scroll to current user after switching to global
                            _scrollToCurrentUser();
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
                            // Auto-scroll to current user after switching to local
                            _scrollToCurrentUser();
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
            ),
    );
  }
}
