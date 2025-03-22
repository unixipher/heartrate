import 'package:flutter/material.dart';

class OTPSection extends StatelessWidget {
  final String? otp;
  final VoidCallback onRefresh;
  
  const OTPSection({
    super.key,
    this.otp,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'OTP: ${otp ?? "Tap refresh"}',
          style: TextStyle(color: Colors.grey.shade700),
        ),
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.red),
          onPressed: onRefresh,
        ),
      ],
    );
  }
}