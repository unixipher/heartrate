import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:testingheartrate/screens/splash/splash_screen.dart';

class ProfilePage extends StatefulWidget {
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String name = '';
  String email = '';
  String age = '';
  String gender = '';
  String maxHr = '';
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchUserData();
  }

  Future<void> fetchUserData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('token');
    if (token == null) {
      setState(() {
        isLoading = false;
      });
      return;
    }

    final response = await http.get(
      Uri.parse('https://authcheck.co/getuser'),
      headers: {
        'Accept': '*/*',
        'User-Agent': 'Thunder Client (https://www.thunderclient.com)',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final user = data['user'] ?? {};
      setState(() {
        name = user['name'] ?? '';
        email = user['email'] ?? '';
        age = user['age']?.toString() ?? '';
        gender = user['gender'] ?? '';
        maxHr = user['maxhr']?.toString() ?? '';
        isLoading = false;
      });
      debugPrint(response.body);
    } else {
      setState(() {
        isLoading = false;
      });
      // Optionally show error
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Profile',
          style: TextStyle(
              fontFamily: 'TheWitcher', fontSize: 24, color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.white),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('token');
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const SplashScreen()),
              );
            },
          ),
        ],
        backgroundColor: const Color(0xFF0A0D29),
      ),
      backgroundColor: const Color(0xFF0A0D29),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _profileItem('Name', name),
                  _profileItem('Email', email),
                  _profileItem('Age', age),
                  _profileItem('Max HR', maxHr),
                  _profileItem('Gender', gender),
                  const SizedBox(height: 360),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: () async {
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (BuildContext context) {
                              return const Center(
                                  child: CircularProgressIndicator());
                            },
                          );

                          SharedPreferences prefs =
                              await SharedPreferences.getInstance();
                          String? token = prefs.getString('token');

                          if (token != null) {
                            final response = await http.post(
                              Uri.parse('https://authcheck.co/deleteuser'),
                              headers: {
                                'Accept': '*/*',
                                'User-Agent':
                                    'Thunder Client (https://www.thunderclient.com)',
                                'Authorization': 'Bearer $token',
                              },
                            );
                            Navigator.of(context).pop();
                            if (response.statusCode == 200) {
                              await prefs.remove('token');
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                    builder: (context) => const SplashScreen()),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text(
                                    'Error deleting account',
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
                            }
                          } else {
                            Navigator.of(context).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text(
                                  'No token found',
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
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          shadowColor: Colors.red,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24.0,
                            vertical: 12.0,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                        ),
                        child: const Text(
                          'Delete Account',
                          style: TextStyle(
                            fontFamily: 'TheWitcher',
                            fontSize: 18,
                            color: Colors.white,
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

  Widget _profileItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 6),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              fontWeight: FontWeight.normal,
              fontSize: 22,
              fontFamily: 'TheWitcher',
              color: Colors.white,
            ),
          ),
          Expanded(
            child: Text(
              value.length > 22 ? '${value.substring(0, 20)}...' : value,
              style: const TextStyle(
            fontSize: 18, color: Colors.white, fontFamily: 'TheWitcher'),
            ),
          ),
        ],
      ),
    );
  }
}
