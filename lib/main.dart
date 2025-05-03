import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:testingheartrate/screens/splash/splash_screen.dart';

void main() {
  runApp(const ProviderScope(
    child: MaterialApp(
      home: SplashScreen(),
    ),
  ));
}
