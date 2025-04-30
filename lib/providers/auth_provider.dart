import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final authProvider = FutureProvider<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
final token = prefs.getString('token') ?? '';
return token.isNotEmpty;
});