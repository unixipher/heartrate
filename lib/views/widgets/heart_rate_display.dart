import 'package:flutter/material.dart';
import '../../models/heart_rate.dart';
import '../../utils/helpers.dart';

class HeartRateDisplay extends StatelessWidget {
  final HeartRate? heartRate;
  final bool isLoading;
  
  const HeartRateDisplay({
    Key? key,
    this.heartRate,
    this.isLoading = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withOpacity(0.1),
            spreadRadius: 2,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          if (isLoading)
            const CircularProgressIndicator(color: Colors.red)
          else if (heartRate != null)
            Column(
              children: [
                Text(
                  heartRate!.formattedValue,
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'BPM',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                Icon(
                  Icons.favorite,
                  color: getHeartRateColor(heartRate!.value),
                  size: 36,
                ),
                Text(
                  heartRate!.status,
                  style: TextStyle(
                    color: getHeartRateColor(heartRate!.value),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            )
          else
            const Text('Waiting for heart rate...'),
        ],
      ),
    );
  }
}