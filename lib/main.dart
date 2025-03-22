import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _token = '';
  double? heartRate;
  String error = '';
  late io.Socket socket;
  bool isAuthenticated = false;
  bool isLoading = false;
  bool _isAuthLoading = false;
  String? otp;

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token != null) {
      setState(() {
        _token = token;
        isAuthenticated = true;
      });
      _initSocket(token);
    }
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
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final userIdentifier = credential.userIdentifier;
      final identityToken = credential.identityToken;

      if (userIdentifier == null || identityToken == null) {
        throw Exception('Missing required authentication data');
      }

      // Send token to your API
      final response = await http.post(
        Uri.parse('https://authcheck.co/auth'),
        headers: {
          'Accept': '*/*',
          'Content-Type': 'application/json',
        },
        body: json.encode({'token': userIdentifier}),
      );

      if (response.statusCode == 201) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', userIdentifier);

        setState(() {
          _token = userIdentifier;
          isAuthenticated = true;
        });

        _initSocket(userIdentifier);
      } else {
        throw Exception('Failed to authenticate: ${response.body}');
      }
    } catch (error) {
      setState(() => this.error = "Authentication failed: ${error.toString()}");
    } finally {
      setState(() => _isAuthLoading = false);
    }
  }

  void _initSocket(String token) {
    try {
      setState(() => isLoading = true);

      socket = io.io(
        'https://authcheck.co',
        io.OptionBuilder()
            .setTransports(['websocket'])
            .enableAutoConnect()
            .enableForceNew()
            .setExtraHeaders({'Authorization': 'Bearer $token'})
            .build(),
      );

      socket
        ..onConnect((_) => setState(() => isLoading = false))
        ..onDisconnect((_) => setState(() => isLoading = false))
        ..onError((err) => setState(() => error = 'Connection error: $err'))
        ..on('watchdataSaved', (data) {
          if (data?['heartRate'] != null) {
            setState(() => heartRate = data['heartRate'].toDouble());
          }
        })
        ..connect();
    } catch (e) {
      setState(() => error = 'Connection failed: $e');
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');

    if (socket.connected) {
      socket.disconnect();
      socket.dispose();
    }

    setState(() {
      _token = '';
      isAuthenticated = false;
      heartRate = null;
      otp = null;
      error = '';
    });
  }

  Future<void> fetchOTP() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    if (token == null) {
      setState(() => error = 'Not authenticated');
      return;
    }

    try {
      final response = await http.get(
        Uri.parse('https://authcheck.co/otp'),
        headers: {
          'Accept': '*/*',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() => otp = data['otp']?.toString());
      } else {
        setState(() => error = 'OTP Error: ${response.statusCode}');
      }
    } catch (e) {
      setState(() => error = 'OTP Error: ${e.toString()}');
    }
  }

  @override
  void dispose() {
    if (isAuthenticated) socket.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        primarySwatch: Colors.red,
        brightness: Brightness.light,
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      darkTheme: ThemeData(
        primarySwatch: Colors.red,
        brightness: Brightness.dark,
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      themeMode: ThemeMode.system,
      home: _buildMainScreen(),
    );
  }

  Widget _buildMainScreen() {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.red.shade100, Colors.red.shade50],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.favorite, color: Colors.red, size: 80),
                  const SizedBox(height: 16),
                  Text('Heart Rate Monitor',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade800,
                    ),
                  ),
                  const SizedBox(height: 50),
                  if (!isAuthenticated) _buildAuthButton(),
                  if (isAuthenticated) _buildAuthenticatedContent(),
                  if (error.isNotEmpty) _buildErrorDisplay(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAuthButton() {
    return Column(
      children: [
        if (_isAuthLoading)
          const CircularProgressIndicator()
        else
          SignInWithAppleButton(
            onPressed: _handleAppleSignIn,
            style: SignInWithAppleButtonStyle.black,
            height: 50,
          ),
        if (_token.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12.0),
            child: Text('Token: $_token',
                style: const TextStyle(color: Colors.grey)),
          ),
      ],
    );
  }

  Widget _buildAuthenticatedContent() {
    return Column(
      children: [
        _buildHeartRateDisplay(),
        const SizedBox(height: 20),
        _buildOTPSection(),
        const SizedBox(height: 20),
        _buildLogoutButton(),
      ],
    );
  }

  Widget _buildHeartRateDisplay() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.red.withOpacity(0.1),
              spreadRadius: 2,
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          if (isLoading)
            const CircularProgressIndicator(color: Colors.red)
          else if (heartRate != null)
            Column(
              children: [
                Text(heartRate!.toStringAsFixed(1)),
                Text('BPM', style: TextStyle(color: Colors.grey.shade600)),
                Icon(Icons.favorite, color: _getHeartRateColor(heartRate!)),
                Text(_getHeartRateStatus(heartRate!),
                    style: TextStyle(color: _getHeartRateColor(heartRate!))),
              ],
            )
          else
            const Text('Waiting for heart rate...'),
        ],
      ),
    );
  }

  Widget _buildOTPSection() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('OTP: ${otp ?? "Tap refresh"}',
            style: TextStyle(color: Colors.grey.shade700)),
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.red),
          onPressed: fetchOTP,
        ),
      ],
    );
  }

  Widget _buildLogoutButton() {
    return ElevatedButton.icon(
      icon: const Icon(Icons.logout),
      label: const Text('Logout'),
      style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red[50],
          foregroundColor: Colors.red[800]),
      onPressed: _logout,
    );
  }

  Widget _buildErrorDisplay() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.red.shade100,
          borderRadius: BorderRadius.circular(8)),
      child: Text(error, style: TextStyle(color: Colors.red.shade800)),
    );
  }

  Color _getHeartRateColor(double rate) {
    if (rate < 60) return Colors.blue;
    if (rate < 100) return Colors.green;
    if (rate < 120) return Colors.orange;
    return Colors.red;
  }

  String _getHeartRateStatus(double rate) {
    if (rate < 60) return 'Resting';
    if (rate < 100) return 'Normal';
    if (rate < 120) return 'Elevated';
    return 'High';
  }
}