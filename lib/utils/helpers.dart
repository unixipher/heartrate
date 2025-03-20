import 'package:flutter/material.dart';

// Heart rate helper functions
Color getHeartRateColor(double rate) {
  if (rate < 60) return Colors.blue;
  if (rate < 100) return Colors.green;
  if (rate < 120) return Colors.orange;
  return Colors.red;
}

String getHeartRateStatus(double rate) {
  if (rate < 60) return 'Resting';
  if (rate < 100) return 'Normal';
  if (rate < 120) return 'Elevated';
  return 'High';
}

// DateTime formatting helpers
String formatDateTime(DateTime dateTime) {
  return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute}';
}