class KalmanFilter {
  double _estimate = 0.0;
  double _errorEstimate = 1.0;
  final double processNoise;
  final double measurementNoise;

  KalmanFilter({
    this.processNoise = 0.01,
    this.measurementNoise = 1.0,
  });

  double filter(double measurement) {
    _errorEstimate += processNoise;
    final gain = _errorEstimate / (_errorEstimate + measurementNoise);
    _estimate += gain * (measurement - _estimate);
    _errorEstimate *= (1 - gain);
    return _estimate;
  }
}
