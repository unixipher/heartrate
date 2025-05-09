import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:testingheartrate/screens/challenge/challenge_screen.dart';
import 'package:testingheartrate/screens/history/history_screen.dart';
import 'package:testingheartrate/screens/splash/splash_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PageController _pageController = PageController(viewportFraction: 0.8);
  int _currentPage = 0;

  final List<CharacterData> _characters = [
    CharacterData(
      name: 'Jarek',
      image: 'assets/images/jarek.png',
      challengeCount: 18,
      description:
          'The true heir to the throne of Aradium. With only his father’s pocket watch to guide him, Jarek must reach the mountain top before his treacherous cousin Kaelen’s coronation.',
      page: const ChallengeScreen(
        storyId: 1,
        title: 'Aradium',
        description:
            'Known for its vast sulphur reserves, Aradium is guarded by sacred, unscalable mountains. Jarek must survive the Chakravyuh, brave the enchanted forest, and reach the sulphur peaks to reclaim his legacy and avenge his father’s death',
        jarekImagePath: 'assets/images/jarek.png',
        backgroundImagePath: 'assets/images/aradium.png',
      ),
    ),
    CharacterData(
      name: 'Maya',
      image: 'assets/images/maya.png',
      challengeCount: 30,
      description:
          'The only survivor in a dystopian world taken over by bots. With only an AI agent Luther to guide her, Maya must take down the uprising before they exterminate the human race.',
      page: const ChallengeScreen(
        storyId: 3,
        title: 'Luther',
        description:
            'The only survivor in a dystopian world taken over by bots. With only an AI agent Luther to guide her, Maya must take down the uprising before they exterminate the human race.',
        jarekImagePath: 'assets/images/maya.png',
        backgroundImagePath: 'assets/images/luther.png',
      ),
    ),
    // CharacterData(
    //   name: 'Agent Scarn',
    //   image: 'assets/images/nyc.png',
    //   challengeCount: 6,
    //   description:
    //       'An undercover agent on a secret mission to deliver a package to 191 Bedford Hills. Agent Tokyo as his guide he must navigate the streets of NYC and board the bus in time',
    //   page: const ChallengeScreen(
    //     storyId: 4,
    //     title: 'New York',
    //     description:
    //         'An undercover agent on a secret mission to deliver a package to 191 Bedford Hills. With Agent Tokyo as his only guide he must navigate the streets of New York and board the bus in time.',
    //     jarekImagePath: 'assets/images/nyc.png',
    //     backgroundImagePath: 'assets/images/nycbg.png',
    //   ),
    // ),
    CharacterData(
      name: 'Agent Seahorse',
      image: 'assets/images/horse.png',
      challengeCount: 30,
      description:
          'An undercover agent on a secret mission to take down the sand mafia. With Stingray and Starfish, Seahorse must find the mastermind before the operation turns deadly.',
      page: const ChallengeScreen(
        storyId: 2,
        title: 'Project\nsmm',
        description:
            'An undercover agent on a secret mission to take down the sand mafia. With Stingray and Starfish, Seahorse must find the mastermind before the operation turns deadly.',
        jarekImagePath: 'assets/images/horse.png',
        backgroundImagePath: 'assets/images/smm.png',
      ),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _checkUserData();
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
          _showBottomSheet(user);
        }
      } else {
        debugPrint('Failed to fetch user data: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching user data: $e');
    }
  }

  void _showBottomSheet(Map<String, dynamic> user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ProfileForm(user: user),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
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
            const SizedBox(height: 24),
            const Center(
              child: Text(
                'Today I Want to Be',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontFamily: 'Thewitcher',
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
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
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => character.page),
                            );
                          },
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.transparent,
                                    width: 2,
                                  ),
                                  image: const DecorationImage(
                                    image:
                                        AssetImage('assets/images/image.png'),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              Container(
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 8),
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
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF0A0D29),
        selectedItemColor: Colors.purple,
        unselectedItemColor: Colors.white70,
        currentIndex: 0,
        onTap: (index) {
          if (index == 0) {
          } else if (index == 1) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => HistoryScreen()),
            );
          } else if (index == 2) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const SplashScreen()),
            );
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.logout),
            label: 'Logout',
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

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user['name'] ?? '');
    _ageController = TextEditingController();
    _gender = widget.user['gender'] ?? 'male';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    super.dispose();
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
        }),
      );

      if (response.statusCode == 200) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Profile updated successfully!',
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
        debugPrint('User data updated successfully');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Failed to update profile. Please try again.',
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
        debugPrint('Failed to update user data: ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Error updating profile. Please try again.',
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
      debugPrint('Error updating user data: $e');
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            color: Colors.black.withOpacity(0.5),
          ),
        ),
        DraggableScrollableSheet(
          initialChildSize: 0.5,
          maxChildSize: 0.9,
          minChildSize: 0.3,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFF0A0D29),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SingleChildScrollView(
                controller: scrollController,
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
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
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'Name',
                        labelStyle: const TextStyle(
                            fontFamily: 'Battambang', color: Colors.white70),
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
                    TextField(
                      controller: _ageController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Age',
                        labelStyle: const TextStyle(
                            fontFamily: 'Battambang', color: Colors.white70),
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
                          .map((g) => DropdownMenuItem(
                                value: g,
                                child: Text(
                                  g[0].toUpperCase() + g.substring(1),
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ))
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          _gender = value!;
                        });
                      },
                      decoration: InputDecoration(
                        labelText: 'Gender',
                        labelStyle: const TextStyle(
                            fontFamily: 'Battambang', color: Colors.white70),
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
                              borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 24),
                        ),
                        child: _isSubmitting
                            ? const CircularProgressIndicator(
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              )
                            : const Text(
                                'Save',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 16),
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
    );
  }
}

class CharacterData {
  final String name;
  final String image;
  final int challengeCount;
  final String description;
  final Widget page;

  CharacterData({
    required this.name,
    required this.image,
    required this.challengeCount,
    required this.description,
    required this.page,
  });
}
