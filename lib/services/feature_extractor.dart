import 'dart:math' as math;

class FeatureExtractor {
  /// Extracts the 13 required features from raw sliding window buffers.
  /// 
  /// Parameters:
  /// - tempHistory: List of skin temperatures (Celsius).
  /// - hrHistory: List of heart rates (BPM).
  /// - accelHistory: List of accelerometer readings, where each is [ax, ay, az] in m/s^2.
  /// 
  /// Returns a List of 13 features in the exact order expected by the model.
  static List<double> extractFeatures({
    required List<double> tempHistory,
    required List<double> hrHistory,
    required List<List<double>> accelHistory,
  }) {
    if (tempHistory.isEmpty || hrHistory.isEmpty || accelHistory.isEmpty) {
      return List.filled(13, 0.0);
    }

    // ── 1. BVP features (Proxied via HR History) ──────────────────────────
    // Center the HR history to make it zero-mean, resembling a high-pass filtered BVP signal.
    final double hrMean = hrHistory.reduce((a, b) => a + b) / hrHistory.length;
    final List<double> bvpSignal = hrHistory.map((h) => h - hrMean).toList();

    final double bvpMean = 0.0; // By definition, since we subtracted the mean
    final double bvpStd = _calculateStd(bvpSignal, bvpMean);
    final double bvpMad = _calculateMad(bvpSignal, bvpMean);
    
    // First differences (velocity)
    final List<double> bvpVelocity = [];
    for (int i = 0; i < bvpSignal.length - 1; i++) {
      bvpVelocity.add(bvpSignal[i + 1] - bvpSignal[i]);
    }
    final double bvpVelocityMean = bvpVelocity.isEmpty ? 0.0 : bvpVelocity.reduce((a, b) => a + b) / bvpVelocity.length;
    final double bvpVelocityStd = _calculateStd(bvpVelocity, bvpVelocityMean);

    // Second differences (acceleration)
    final List<double> bvpAcceleration = [];
    for (int i = 0; i < bvpVelocity.length - 1; i++) {
      bvpAcceleration.add(bvpVelocity[i + 1] - bvpVelocity[i]);
    }
    final double bvpAccelMean = bvpAcceleration.isEmpty ? 0.0 : bvpAcceleration.reduce((a, b) => a + b) / bvpAcceleration.length;
    final double bvpAccelerationStd = _calculateStd(bvpAcceleration, bvpAccelMean);

    // ── 2. Skin Temperature features ──────────────────────────────────────
    final double tempMeanRaw = tempHistory.reduce((a, b) => a + b) / tempHistory.length;
    // Normalize temperature mean by subtracting typical baseline (35.0 C)
    // This maps a range of 33-37 C to -2.0 to +2.0, matching model's expectations.
    final double tempMean = tempMeanRaw - 35.0; 
    final double tempStd = _calculateStd(tempHistory, tempMeanRaw);
    final double tempSlope = _calculateSlope(tempHistory);

    // ── 3. Accelerometer features ─────────────────────────────────────────
    // Convert from m/s^2 to g (gravity units) by dividing by 9.8
    final List<double> accX = accelHistory.map((a) => a[0] / 9.8).toList();
    final List<double> accY = accelHistory.map((a) => a[1] / 9.8).toList();
    final List<double> accZ = accelHistory.map((a) => a[2] / 9.8).toList();

    // Compute magnitude for each sample
    final List<double> accMag = [];
    for (int i = 0; i < accelHistory.length; i++) {
      final x = accX[i];
      final y = accY[i];
      final z = accZ[i];
      accMag.add(math.sqrt(x * x + y * y + z * z));
    }

    final double accMagMeanRaw = accMag.reduce((a, b) => a + b) / accMag.length;
    // Subtract 1.0 g (standard gravity) to center magnitude around 0
    final double accMagMean = accMagMeanRaw - 1.0;
    final double accMagStd = _calculateStd(accMag, accMagMeanRaw);

    final double accXMean = accX.reduce((a, b) => a + b) / accX.length;
    final double accXStd = _calculateStd(accX, accXMean);

    final double accYMean = accY.reduce((a, b) => a + b) / accY.length;
    final double accYStd = _calculateStd(accY, accYMean);

    final double accZMean = accZ.reduce((a, b) => a + b) / accZ.length;
    final double accZStd = _calculateStd(accZ, accZMean);

    // Return features in exact model feature order
    return [
      bvpMean,              // 0: bvp_mean
      bvpStd,               // 1: bvp_std
      bvpMad,               // 2: bvp_mad
      bvpVelocityStd,       // 3: bvp_velocity_std
      bvpAccelerationStd,   // 4: bvp_acceleration_std
      tempMean,             // 5: temp_mean
      tempStd,              // 6: temp_std
      tempSlope,            // 7: temp_slope
      accMagMean,           // 8: acc_mag_mean
      accMagStd,            // 9: acc_mag_std
      accXStd,              // 10: acc_x_std
      accYStd,              // 11: acc_y_std
      accZStd,              // 12: acc_z_std
    ];
  }

  /// Calculates the standard deviation of a list of values.
  static double _calculateStd(List<double> values, double mean) {
    if (values.length <= 1) return 0.0;
    double sumSqDiff = 0.0;
    for (final val in values) {
      final diff = val - mean;
      sumSqDiff += diff * diff;
    }
    return math.sqrt(sumSqDiff / values.length);
  }

  /// Calculates the mean absolute deviation (MAD).
  static double _calculateMad(List<double> values, double mean) {
    if (values.isEmpty) return 0.0;
    double sumAbsDiff = 0.0;
    for (final val in values) {
      sumAbsDiff += (val - mean).abs();
    }
    return sumAbsDiff / values.length;
  }

  /// Calculates the least squares linear regression slope over time series indexes.
  static double _calculateSlope(List<double> values) {
    final int n = values.length;
    if (n <= 1) return 0.0;

    final double xMean = (n - 1) / 2.0;
    final double yMean = values.reduce((a, b) => a + b) / n;

    double numerator = 0.0;
    double denominator = 0.0;

    for (int i = 0; i < n; i++) {
      final double xDiff = i - xMean;
      numerator += xDiff * (values[i] - yMean);
      denominator += xDiff * xDiff;
    }

    if (denominator == 0.0) return 0.0;
    return numerator / denominator;
  }
}
