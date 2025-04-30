import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:testingheartrate/views/splash_screen.dart';
// import 'package:testingheartrate/services/audio_manager.dart';

void main() {
  runApp(const ProviderScope(
    child: MaterialApp(
      home: SplashScreen(),
    ),
  ));
}
// void main() async {
//   WidgetsFlutterBinding.ensureInitialized();
//   await AudioManager().init();
//   runApp(const ProviderScope(child: MaterialApp(home: SplashScreen())));
// }
