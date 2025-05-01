import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:testingheartrate/views/splash_screen.dart';

void main() {
  runApp(const ProviderScope(
    child: MaterialApp(
      home: SplashScreen(),
    ),
  ));
}
