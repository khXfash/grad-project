import '../models/stress_reading.dart';

/// Helper class that encapsulates the stress‑evaluation logic.
///
/// It provides two static methods that mirror the original getters in
/// `AppProvider`. Keeping the logic in one place makes it easier to test,
/// maintain, and potentially adjust the weighting strategy later.
class StressEvaluator {
  /// Returns `true` when the user is considered stressed.
  ///
  /// - If a sensor reading exists, the threshold is `stressScore >= 50`.
  /// - If there is no sensor data, the facial‑emotion probability is used.
  static bool isStressed({
    required StressReading? latestReading,
    required String detectedEmotion,
    required double faceStressProbability,
  }) {
    // Primary detector: sensor reading
    if (latestReading != null) {
      return latestReading.stressScore >= 50;
    }
    // Fallback to facial emotion when no sensor data
    if (detectedEmotion == 'Unknown') return false;
    return faceStressProbability >= 0.50;
  }

  /// Returns `true` when the stress level is critical.
  ///
  /// - If a sensor reading is missing, returns false.
  /// - If facial emotion is unavailable, uses only the sensor score (> 90).
  /// - Otherwise it blends sensor and facial probabilities with a 60/40
  ///   weighting and checks against a 0.90 threshold.
  static bool isCriticalStress({
    required StressReading? latestReading,
    required String detectedEmotion,
    required double faceStressProbability,
  }) {
    if (latestReading == null) return false;
    // Sensor‑only case (no facial data)
    if (detectedEmotion == 'Unknown') {
      return latestReading.stressScore > 90;
    }
    // Combined sensor + facial probability
    final sensorProb = latestReading.stressScore / 100.0;
    final faceProb = faceStressProbability;
    final combinedProb = (sensorProb * 0.6) + (faceProb * 0.4);
    return combinedProb > 0.90;
  }
}
