import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:testingheartrate/screens/challenge/challenge_screen.dart';
import 'package:testingheartrate/screens/history/history_screen.dart';
import 'package:testingheartrate/screens/leaderboard/leaderboard.dart';
import 'package:testingheartrate/screens/profile/profile_page.dart';
import 'package:testingheartrate/services/time_tracking_service.dart';
import 'package:permission_handler/permission_handler.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PageController _pageController = PageController(viewportFraction: 0.8);
  int _currentPage = 0;
  final FirebaseAnalytics analytics = FirebaseAnalytics.instance;
  int _userScore = 0;

  final List<CharacterData> _characters = [
    CharacterData(
      name: 'Jarek',
      image: 'assets/images/jarek.png',
      challengeCount: 0,
      storyId: 1,
      description:
          'Jarek is the true heir to the throne of Aradium. He fights powerful enemies with great valour.',
      page: const ChallengeScreen(
        storyId: 1,
        title: 'Aradium',
        characterName: 'Jarek',
        description:
            'Known for its vast sulphur reserves, Aradium is guarded by sacred, unscalable mountains. Jarek must survive the Chakravyuh, brave the enchanted forest, and reach the sulphur peaks to reclaim his legacy and avenge his father’s death',
        storydescription:
            "Known for its vast sulphur reserves, Aradium is guarded by sacred, unscalable mountains. With only his father’s pocket watch to guide him, Jarek must survive the Chakravyuh, brave the enchanted forest, and reach the sulphur peaks to reclaim his legacy and avenge his father’s death.",
        jarekImagePath: 'assets/images/jarek.png',
        backgroundImagePath: 'assets/images/aradium.png',
      ),
    ),
    CharacterData(
      name: 'Maya',
      image: 'assets/images/maya.png',
      challengeCount: 0,
      storyId: 3,
      description:
          'Maya is the only survivor of a bot attack. She must stop the revolution with her quick wit',
      page: const ChallengeScreen(
        storyId: 3,
        title: 'Luther',
        characterName: 'Maya',
        description:
            'The only survivor in a dystopian world taken over by bots. With only an AI agent Luther to guide her, Maya must take down the uprising before they exterminate the human race.',
        storydescription:
            "The Earth is under siege by rogue bots, clearing entire areas to build factories for their GPUs. Maya and Luther race to stop them, only to uncover a dark secret—these bots are part of a sinister plan to eliminate low-IQ humans. With time running out, they must expose the conspiracy before it’s too late.",
        jarekImagePath: 'assets/images/maya.png',
        backgroundImagePath: 'assets/images/luther.png',
      ),
    ),
    CharacterData(
      name: 'Agent Seahorse',
      image: 'assets/images/horse.png',
      challengeCount: 0,
      description:
          'Seahorse is the only agent who can take down the sand mafia of Cutna.',
      storyId: 2,
      page: const ChallengeScreen(
        storyId: 2,
        title: 'Project SMM',
        characterName: 'Agent\nSeahorse',
        description:
            'An undercover agent on a secret mission to take down the sand mafia. With Stingray and Starfish, Seahorse must find the mastermind before the operation turns deadly.',
        jarekImagePath: 'assets/images/horse.png',
        storydescription:
            "The Sone River in Bihar is under the control of a powerful sand mafia. As the mafia heads prepare for a bloody power struggle, Agent Seahorse must expose the kingpins, uncover their allegiances, and take down the mastermind behind the operation before it descends into chaos.",
        backgroundImagePath: 'assets/images/smm.png',
      ),
    ),
  ];

  @override
  void initState() {
    analytics.setAnalyticsCollectionEnabled(true);
    super.initState();
    _initializePermissionsAndData();
  }

  Future<void> _initializePermissionsAndData() async {
    // Request permissions sequentially to avoid conflicts
    await _requestActivityRecognitionPermission();
    await _requestLocationPermissionIfAndroid();

    // NEW: Request pedometer permission for iOS
    if (Platform.isIOS) {
      await _requestPedometerPermission();
    }

    // Initialize other services and data
    await _initializeTimeTracking();
    await _checkUserData();
    await _updatefcmToken();
    await _fetchChallenges();
  }

  Future<void> _updatefcmToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    final fcmToken = prefs.getString('fcmToken') ?? '';

    try {
      final response = await http.post(
        Uri.parse('https://authcheck.co/updateuser'),
        headers: {
          'Accept': '/',
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({'fcmToken': fcmToken}),
      );

      if (response.statusCode == 200) {
        debugPrint('FCM token updated successfully');
      } else {
        debugPrint('Failed to update FCM token: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error updating FCM token: $e');
    }
  }

  // NEW: Added pedometer permission request for iOS
  Future<void> _requestPedometerPermission() async {
    debugPrint('=== REQUESTING PEDOMETER PERMISSION FOR IOS ===');
    bool granted = await Permission.sensors.isGranted;
    if (!granted) {
      granted = await Permission.sensors.request() == PermissionStatus.granted;
    }
    debugPrint('Pedometer permission granted: $granted');
  }

  Future<void> _requestLocationPermissionIfAndroid() async {
    if (Platform.isAndroid) {
      debugPrint('=== REQUESTING LOCATION PERMISSION FOR ANDROID ===');
      bool granted = await Permission.location.isGranted;
      debugPrint('Location permission initially granted: $granted');

      if (!granted) {
        debugPrint('Requesting location permission...');
        final status = await Permission.location.request();
        granted = status == PermissionStatus.granted;
        debugPrint(
            'Location permission request result: $granted (status: $status)');
      }

      if (!granted) {
        debugPrint('Location permission denied');
      } else {
        debugPrint('Location permission granted successfully');
      }

      debugPrint('=== LOCATION PERMISSION REQUEST COMPLETE ===');
    }
  }

  Future<void> _initializeTimeTracking() async {
    try {
      await TimeTrackingService().initialize();
      debugPrint('Time tracking service initialized successfully');
    } catch (e) {
      debugPrint('Error initializing time tracking service: $e');
    }
  }

  Future<void> _requestActivityRecognitionPermission() async {
    debugPrint('=== REQUESTING ACTIVITY RECOGNITION PERMISSION ===');

    // Request activity recognition permission for both iOS and Android
    bool granted = await Permission.activityRecognition.isGranted;
    debugPrint('Activity recognition permission initially granted: $granted');

    if (!granted) {
      debugPrint('Requesting activity recognition permission...');
      granted = await Permission.activityRecognition.request() ==
          PermissionStatus.granted;
      debugPrint('Permission request result: $granted');
    }

    if (!granted) {
      debugPrint('Activity recognition permission denied');
    } else {
      debugPrint('Activity recognition permission granted successfully');
    }

    debugPrint('=== PERMISSION REQUEST COMPLETE ===');
  }

  Future<void> _fetchChallenges() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';

      final response = await http.get(
        Uri.parse('https://authcheck.co/getChallenges'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        List<dynamic> challenges = json.decode(response.body);
        Map<int, int> counts = {};

        for (var challenge in challenges) {
          int storyId = challenge['storyId'];
          if (_characters.any((character) => character.storyId == storyId)) {
            counts[storyId] = (counts[storyId] ?? 0) + 1;
          }
        }

        for (var character in _characters) {
          int count = counts[character.storyId] ?? 0;
          character.challengeCount = count;
        }

        setState(() {});
      }
    } catch (e) {
      debugPrint('Error fetching challenges: $e');
    }
  }

  Future<void> _checkUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';
      debugPrint('Token: $token');

      final response = await http.get(
        Uri.parse('https://authcheck.co/getuser'),
        headers: {
          'Accept': '/',
          'Authorization': 'Bearer $token',
          'User-Agent': 'Thunder Client (https://www.thunderclient.com)',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final user = data['user'];

        if (user['age'] == null) {
          _showProfileDialog(user);
        }

        if (user['maxhr'] != null) {
          final maxHr = user['maxhr'];
          await prefs.setInt('maxhr', maxHr.toInt());
          debugPrint('MaxHR stored: $maxHr');
        }

        if (user['id'] != null) {
          await prefs.setString('userId', user['id'].toString());
          debugPrint('User ID stored: ${user['id']}');
        }

        if (user['score'] != null) {
          setState(() {
            _userScore = user['score'];
          });
          debugPrint('Score fetched: $_userScore');
        }
      } else {
        debugPrint('Failed to fetch user data: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching user data: $e');
    }
  }

  void _showProfileDialog(Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20.0),
          ),
          backgroundColor: const Color(0xFF0A0D29),
          child: ProfileForm(user: user),
        );
      },
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    TimeTrackingService().dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0D29),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.emoji_events,
                        color: Colors.white,
                        size: 22,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$_userScore',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.normal,
                          fontFamily: 'Thewitcher',
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Center(
              child: Text(
                'Choose The Character \nyou want to be',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                _characters[_currentPage].name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontFamily: 'Thewitcher',
                  letterSpacing: 2.0,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _characters.length,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                itemBuilder: (context, index) {
                  final character = _characters[index];
                  return AnimatedBuilder(
                    animation: _pageController,
                    builder: (context, child) {
                      double scale = 1.0;
                      if (_pageController.position.haveDimensions) {
                        scale = (_pageController.page! - index).abs();
                        scale = (1 - (scale * 0.2)).clamp(0.8, 1.0);
                      }
                      return Transform.scale(
                        scale: scale,
                        child: GestureDetector(
                          onTap: () async {
                            await analytics.logEvent(
                              name: 'character_selected',
                              parameters: {'character_name': character.name},
                            );
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => character.page),
                            );
                          },
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.transparent,
                                    width: 2,
                                  ),
                                  image: const DecorationImage(
                                    image: AssetImage(
                                      'assets/images/image.png',
                                    ),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.transparent,
                                    width: 2,
                                  ),
                                  image: DecorationImage(
                                    image: AssetImage(character.image),
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Left Arrow
                  IconButton(
                    onPressed: _currentPage > 0
                        ? () {
                            _pageController.previousPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          }
                        : null,
                    icon: Icon(
                      Icons.arrow_back_ios,
                      color: _currentPage > 0
                          ? Colors.white
                          : Colors.white.withOpacity(0.3),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Page Indicators (Three Dots)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      _characters.length,
                      (index) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _currentPage == index
                              ? Colors.purple
                              : Colors.grey.withOpacity(0.5),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Right Arrow
                  IconButton(
                    onPressed: _currentPage < _characters.length - 1
                        ? () {
                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          }
                        : null,
                    icon: Icon(
                      Icons.arrow_forward_ios,
                      color: _currentPage < _characters.length - 1
                          ? Colors.white
                          : Colors.white.withOpacity(0.3),
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                '${_characters[_currentPage].challengeCount} Challenges',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _characters[_currentPage].description,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Start Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    final character = _characters[_currentPage];
                    await analytics.logEvent(
                      name: 'character_selected',
                      parameters: {'character_name': character.name},
                    );
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => character.page),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 5,
                  ),
                  child: const Text(
                    'START',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Thewitcher',
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF0A0D29),
        selectedItemColor: Colors.purple,
        unselectedItemColor: Colors.white70,
        currentIndex: 0,
        onTap: (index) async {
          if (index == 0) {
          } else if (index == 1) {
            await analytics.logEvent(
              name: 'history_screen_opened',
              parameters: {},
            );
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => HistoryScreen()),
            );
          } else if (index == 2) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => LeaderboardScreen()),
            );
          } else if (index == 3) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => ProfilePage()),
            );
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
          BottomNavigationBarItem(
              icon: Icon(Icons.leaderboard), label: 'Leaderboard'),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class ProfileForm extends StatefulWidget {
  final Map<String, dynamic> user;

  const ProfileForm({super.key, required this.user});

  @override
  State<ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<ProfileForm> {
  late TextEditingController _nameController;
  late TextEditingController _ageController;
  late String _gender;
  bool _isSubmitting = false;
  List<Map<String, dynamic>> _cities = [];
  String? _selectedCityId;
  bool _isLoadingCities = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user['name'] ?? '');
    _ageController = TextEditingController();
    _gender = widget.user['gender'] ?? 'male';
    _selectedCityId = widget.user['cityId'];
    _fetchCities();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  Future<void> _fetchCities() async {
    setState(() {
      _isLoadingCities = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';

      final response = await http.get(
        Uri.parse('https://authcheck.co/city'),
        headers: {
          'Accept': '/',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _cities = List<Map<String, dynamic>>.from(data['cities']);
        });
        debugPrint('Cities fetched successfully: ${_cities.length} cities');
      } else {
        debugPrint('Failed to fetch cities: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching cities: $e');
    } finally {
      setState(() {
        _isLoadingCities = false;
      });
    }
  }

  Future<void> _submitForm() async {
    setState(() {
      _isSubmitting = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';

      final response = await http.post(
        Uri.parse('https://authcheck.co/updateuser'),
        headers: {
          'Accept': '/',
          'Authorization': 'Bearer $token',
          'User-Agent': 'Thunder Client (https://www.thunderclient.com)',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'name': _nameController.text,
          'age': int.tryParse(_ageController.text) ?? 0,
          'gender': _gender,
          'cityId': _selectedCityId,
        }),
      );

      if (response.statusCode == 200) {
        // Store cityId in SharedPreferences
        if (_selectedCityId != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('cityId', _selectedCityId!);
          debugPrint('CityId stored in SharedPreferences: $_selectedCityId');
        }

        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Profile updated',
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
        debugPrint('User data updated successfully');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Profile update failed',
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
        debugPrint('Failed to update user data: ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Error',
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
      debugPrint('Error updating user data: $e');
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Complete Your Profile',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontFamily: 'Thewitcher',
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _ageController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Age',
              labelStyle: const TextStyle(
                fontFamily: 'Battambang',
                color: Colors.white70,
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: Colors.white70),
                borderRadius: BorderRadius.circular(10),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: Colors.white),
                borderRadius: BorderRadius.circular(10),
              ),
              filled: true,
              fillColor: const Color(0xFF1E1F2D),
            ),
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _gender,
            items: ['male', 'female']
                .map(
                  (g) => DropdownMenuItem(
                    value: g,
                    child: Text(
                      g[0].toUpperCase() + g.substring(1),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              setState(() {
                _gender = value!;
              });
            },
            decoration: InputDecoration(
              labelText: 'Gender',
              labelStyle: const TextStyle(
                fontFamily: 'Battambang',
                color: Colors.white70,
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: Colors.white70),
                borderRadius: BorderRadius.circular(10),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: Colors.white),
                borderRadius: BorderRadius.circular(10),
              ),
              filled: true,
              fillColor: const Color(0xFF1E1F2D),
            ),
            dropdownColor: const Color(0xFF0A0D29),
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 16),
          _isLoadingCities
              ? const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.purple,
                    ),
                  ),
                )
              : DropdownButtonFormField<String>(
                  value: _selectedCityId,
                  hint: const Text(
                    'Select City',
                    style: TextStyle(color: Colors.white70),
                  ),
                  items: _cities
                      .map(
                        (city) => DropdownMenuItem<String>(
                          value: city['id'],
                          child: Text(
                            city['name'],
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedCityId = value;
                    });
                  },
                  decoration: InputDecoration(
                    labelText: 'City',
                    labelStyle: const TextStyle(
                      fontFamily: 'Battambang',
                      color: Colors.white70,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.white70),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.white),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    filled: true,
                    fillColor: const Color(0xFF1E1F2D),
                  ),
                  dropdownColor: const Color(0xFF0A0D29),
                  style: const TextStyle(color: Colors.white),
                ),
          const SizedBox(height: 24),
          Center(
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submitForm,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7B1FA2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 24,
                ),
              ),
              child: _isSubmitting
                  ? const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.white,
                      ),
                    )
                  : const Text(
                      'Save',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class CharacterData {
  final String name;
  final String image;
  int challengeCount;
  final String description;
  final Widget page;
  final String? storydescription;
  final int storyId;

  CharacterData({
    required this.name,
    required this.image,
    required this.challengeCount,
    required this.description,
    required this.page,
    this.storydescription,
    required this.storyId,
  });
}
