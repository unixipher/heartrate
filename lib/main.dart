import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:testingheartrate/screens/splash/splash_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  WakelockPlus.enable();
  runApp(const ProviderScope(
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SplashScreen(),
    ),
  ));
}
