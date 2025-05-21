import 'package:flutter/material.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:testingheartrate/screens/home/home_screen.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  late VideoPlayerController _controller;
  bool _isAuthLoading = false;
  String error = '';
  final FirebaseAnalytics analytics = FirebaseAnalytics.instance;

  @override
  void initState() {
    analytics.setAnalyticsCollectionEnabled(true);
    super.initState();
    _controller = VideoPlayerController.asset('assets/videos/bg.mp4')
      ..initialize().then((_) {
        _controller.setLooping(true);
        _controller.play();
        setState(() {});
      });
  }

  Future<void> _handleAppleSignIn() async {
    setState(() {
      _isAuthLoading = true;
      error = '';
    });

    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName
        ],
      );

      final userIdentifier = credential.userIdentifier;
      final identityToken = credential.identityToken;

      if (userIdentifier == null || identityToken == null) {
        throw Exception('Missing required authentication data');
      }

      final response = await http.post(
        Uri.parse('https://authcheck.co/auth'),
        headers: {'Accept': '*/*', 'Content-Type': 'application/json'},
        body: json.encode({
          'token': userIdentifier,
          'name': credential.givenName,
          'email': credential.email,
        }),
      );

      if (response.statusCode == 201) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', userIdentifier);
        debugPrint(credential.toString());

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      } else {
        throw Exception('Failed to authenticate: ${response.body}');
      }
    } catch (e) {
      setState(() => error = "Authentication failed: ${e.toString()}");
    } finally {
      setState(() => _isAuthLoading = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Stack(
          children: [
            if (_controller.value.isInitialized)
              SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _controller.value.size.width,
                    height: _controller.value.size.height,
                    child: VideoPlayer(_controller),
                  ),
                ),
              ),
            Container(
              color: Color(0xFF0A0D29).withOpacity(0.7),
            ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Start your adventure',
                    style: TextStyle(
                      fontSize: 32,
                      fontFamily: 'Thewitcher',
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  if (_isAuthLoading)
                    const CircularProgressIndicator(
                      color: Colors.white,
                    )
                  else
                    GestureDetector(
                      onTap: _handleAppleSignIn,
                      child: SvgPicture.asset(
                        'assets/images/button.svg',
                      ),
                    ),
                  if (error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        error,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
