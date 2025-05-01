import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:testingheartrate/views/auth_screen.dart';
import 'package:testingheartrate/views/home_screen.dart';
import 'package:testingheartrate/providers/auth_provider.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    authState.when(
      data: (isAuthenticated) {
        Future.delayed(const Duration(seconds: 1), () {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  isAuthenticated ? const HomeScreen() : const AuthScreen(),
            ),
          );
        });
      },
      loading: () {},
      error: (error, stack) {},
    );

    return Scaffold(
      backgroundColor: Color(0xFF0A0D29),
      body: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            Image.asset(
              'assets/images/image.png',
              width: 900,
              height: 900,
              fit: BoxFit.cover,
            ),
            Image.asset(
              'assets/images/icon.png',
              width: 350,
              height: 350,
            ),
          ],
        ),
      ),
    );
  }
}
