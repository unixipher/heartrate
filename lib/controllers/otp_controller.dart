import 'dart:async';
import '../services/api_service.dart';

class OTPController {
  final ApiService _apiService;
  String? otp;
  Function(String)? onError;
  Function(String)? onOTPReceived;

  OTPController({
    required ApiService apiService,
    this.onError,
    this.onOTPReceived,
  }) : _apiService = apiService;

  Future<void> fetchOTP(String token) async {
    try {
      final result = await _apiService.getOTP(token);
      otp = result;
      if (onOTPReceived != null) onOTPReceived!(result);
    } catch (e) {
      if (onError != null) onError!('OTP Error: ${e.toString()}');
    }
  }
}