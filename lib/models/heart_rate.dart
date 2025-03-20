class HeartRate {
  final double value;
  final DateTime timestamp;

  HeartRate({
    required this.value,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  String get status {
    if (value < 60) return 'Resting';
    if (value < 100) return 'Normal';
    if (value < 120) return 'Elevated';
    return 'High';
  }

  String get formattedValue => value.toStringAsFixed(1);
}