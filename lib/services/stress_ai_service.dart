import 'dart:math';

class StressAiService {
  /// Rule-based stress scoring from bracelet sensors.
  /// Returns a score from 0 (calm) to 100 (severe stress).
  static int calculateStressScore({
    required int heartRate,
    required double skinTemp,
    required double accelX,
    required double accelY,
    required double accelZ,
  }) {
    // ── Heart rate score ──────────────────────────────────────────
    // Resting: 60-75 bpm → score ~0; elevated: 100+ → score ~100
    double hrScore;
    if (heartRate < 60) {
      hrScore = 30; // bradycardia – mild concern
    } else if (heartRate <= 75) {
      hrScore = 0;
    } else if (heartRate <= 90) {
      hrScore = ((heartRate - 75) / 15 * 40).clamp(0, 40);
    } else {
      hrScore = (40 + (heartRate - 90) / 30 * 60).clamp(0, 100);
    }

    // ── Skin temperature score ────────────────────────────────────
    // Normal: 36.0–37.0°C → score 0; deviations increase score
    double tempScore;
    final tempDev = (skinTemp - 36.5).abs();
    if (tempDev < 0.5) {
      tempScore = 0;
    } else {
      tempScore = (tempDev * 40).clamp(0, 100);
    }

    // ── Accelerometer magnitude score ─────────────────────────────
    // Movement energy: sqrt(ax²+ay²+(az-9.8)²)
    // Calm: near 0; agitated/restless: > 2
    final gravityFreeZ = accelZ - 9.8;
    final motionMag = sqrt(
      accelX * accelX + accelY * accelY + gravityFreeZ * gravityFreeZ,
    );
    double accelScore;
    if (motionMag < 0.3) {
      accelScore = 0;
    } else if (motionMag < 1.0) {
      accelScore = (motionMag / 1.0 * 30).clamp(0, 30);
    } else {
      accelScore = (30 + (motionMag - 1.0) / 2.0 * 70).clamp(0, 100);
    }

    // ── Weighted composite ────────────────────────────────────────
    final score = hrScore * 0.40 + accelScore * 0.35 + tempScore * 0.25;
    return score.round().clamp(0, 100);
  }
}
