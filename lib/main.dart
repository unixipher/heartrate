import 'package:flutter/material.dart';
import 'controllers/auth_controller.dart';
import 'controllers/otp_controller.dart';
import 'services/api_service.dart';
import 'views/screens/auth_screen.dart';
import 'views/screens/home_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late AuthController authController;
  late OTPController otpController;
  late ApiService apiService;
  
  bool isAuthenticated = false;
  String error = '';

  @override
  void initState() {
    super.initState();
    apiService = ApiService();
    
    authController = AuthController(
      onAuthStateChanged: (state) {
        setState(() => isAuthenticated = state);
      },
      onErrorChanged: (errorMsg) {
        setState(() => error = errorMsg);
      },
    );
    
    otpController = OTPController(
      apiService: apiService,
      onError: (errorMsg) {
        setState(() => error = errorMsg);
      },
      onOTPReceived: (otpValue) {
        setState(() {}); // Refresh UI
      },
    );
  }

  void _handleLogout() {
    authController.logout();
  }

  @override
  void dispose() {
    authController.dispose();
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
      home: Scaffold(
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
              child: isAuthenticated
                ? HomeScreen(
                    authController: authController,
                    otpController: otpController,
                    socketController: authController.socketController,
                    onLogout: _handleLogout,
                  )
                : AuthScreen(
                    authController: authController,
                    onAuthSuccess: () {
                      setState(() => isAuthenticated = true);
                    },
                  ),
            ),
          ),
        ),
      ),
    );
  }
}