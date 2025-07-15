import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

class FirebaseNotification {
  final _firebaseMessaging = FirebaseMessaging.instance;

  Future<void> handleBackgroundMessage(RemoteMessage message) async {
    if (kDebugMode) {
      print("🔔 Background Message: ${message.data}");
    }
  }

  Future<void> initNotification() async {
    // Request permissions first
    final settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
    );

    if (kDebugMode) {
      print("🔐 Permission status: ${settings.authorizationStatus}");
    }

    if (Platform.isIOS) {
      await _firebaseMessaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // Wait for APNS token to be available
      String? apnsToken;
      int retryCount = 0;
      const maxRetries = 10;

      while (apnsToken == null && retryCount < maxRetries) {
        await Future.delayed(Duration(seconds: retryCount == 0 ? 1 : 2));
        apnsToken = await _firebaseMessaging.getAPNSToken();
        retryCount++;

        if (kDebugMode) {
          print("🍎 APNS Token attempt $retryCount: ${apnsToken ?? 'null'}");
        }
      }

      if (apnsToken == null) {
        if (kDebugMode) {
          print("🍎 Failed to get APNS token after $maxRetries attempts");
        }
        return;
      }
    }

    // Get Firebase token after APNS is ready
    final token = await _firebaseMessaging.getToken();
    if (token != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fcmToken', token);
      if (kDebugMode) {
        print("🔗 Firebase Messaging Token: $token");
      }
    } else {
      if (kDebugMode) {
        print("🔗 Failed to get Firebase Messaging Token");
      }
    }

    // Set up background message handler
    FirebaseMessaging.onBackgroundMessage(handleBackgroundMessage);

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (kDebugMode) {
        print("🔔 Foreground Message: ${message.data}");
        print(
            "🔔 Notification: ${message.notification?.title} - ${message.notification?.body}");
      }
    });

    // Handle notification taps when app is in background/terminated
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      if (kDebugMode) {
        print("🔔 App opened from notification: ${message.data}");
      }
    });
  }
}
