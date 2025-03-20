import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/constants.dart';

class ApiService {
  Future<String> getOTP(String token) async {
    if (token.isEmpty) {
      throw Exception('Not authenticated');
    }

    final response = await http.get(
      Uri.parse('$kServerUrl/otp'),
      headers: {
        'Accept': '*/*',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['otp']?.toString() ?? '';
    } else {
      throw Exception('OTP Error: ${response.statusCode}');
    }
  }
}