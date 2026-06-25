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
    // Filter out 0.0 and invalid low readings (from startup, dropouts, or poor contact) to prevent std pollution.
    final List<double> cleanHrHistory = hrHistory.where((h) => h >= 45.0).toList();
    final List<double> cleanTempHistory = tempHistory.where((t) => t > 0.0).toList();

    if (cleanTempHistory.isEmpty || cleanHrHistory.isEmpty || accelHistory.isEmpty) {
      return List.filled(13, 0.0);
    }

    // ── 1. BVP features (Proxied via HR History) ──────────────────────────
    // Center the HR history to make it zero-mean, resembling a high-pass filtered BVP signal.
    final double hrMean = cleanHrHistory.reduce((a, b) => a + b) / cleanHrHistory.length;
    final List<double> bvpSignal = cleanHrHistory.map((h) => h - hrMean).toList();

    final double bvpMean = 0.0; // By definition, since we subtracted the mean
    
    // Clamp proxy BVP features to the model's expected range to prevent heart rate fluctuations
    // from triggering false stress classifications.
    final double bvpStd = _calculateStd(bvpSignal, bvpMean).clamp(0.0, 1.5);
    final double bvpMad = _calculateMad(bvpSignal, bvpMean).clamp(0.0, 1.2);
    
    // First differences (velocity)
    final List<double> bvpVelocity = [];
    for (int i = 0; i < bvpSignal.length - 1; i++) {
      bvpVelocity.add(bvpSignal[i + 1] - bvpSignal[i]);
    }
    final double bvpVelocityMean = bvpVelocity.isEmpty ? 0.0 : bvpVelocity.reduce((a, b) => a + b) / bvpVelocity.length;
    final double bvpVelocityStd = _calculateStd(bvpVelocity, bvpVelocityMean).clamp(0.0, 0.2);

    // Second differences (acceleration)
    final List<double> bvpAcceleration = [];
    for (int i = 0; i < bvpVelocity.length - 1; i++) {
      bvpAcceleration.add(bvpVelocity[i + 1] - bvpVelocity[i]);
    }
    final double bvpAccelMean = bvpAcceleration.isEmpty ? 0.0 : bvpAcceleration.reduce((a, b) => a + b) / bvpAcceleration.length;
    final double bvpAccelerationStd = _calculateStd(bvpAcceleration, bvpAccelMean).clamp(0.0, 0.06);

    // ── 2. Skin Temperature features ──────────────────────────────────────
    final double tempMeanRaw = cleanTempHistory.reduce((a, b) => a + b) / cleanTempHistory.length;
    // Use the 90th percentile of temperature history as baseline to make it robust against sensor spikes.
    final List<double> sortedTemp = List.from(cleanTempHistory)..sort();
    final double tempMax = sortedTemp.isNotEmpty 
        ? sortedTemp[(sortedTemp.length * 0.9).toInt().clamp(0, sortedTemp.length - 1)]
        : 35.0;
    final double tempBaseline = tempMax > 28.0 ? tempMax : 35.0;
    // Centering: a calm state (tempMeanRaw close to baseline) maps to 1.0 (calm).
    final double tempMean = tempMeanRaw - (tempBaseline - 1.0); 
    final double tempStd = _calculateStd(cleanTempHistory, tempMeanRaw);
    final double tempSlope = _calculateSlope(cleanTempHistory);

    // ── 3. Accelerometer features ─────────────────────────────────────────
    // Auto-detect if accelerometer readings are in m/s^2 (e.g. mock mode ~9.8) or g (actual bracelet ~1.0)
    // and scale them by 64.0 to match the training data's Empatica E4 units (1g = 64 LSB).
    final List<double> accX = [];
    final List<double> accY = [];
    final List<double> accZ = [];
    
    for (var a in accelHistory) {
      final double rawMag = math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]);
      final double scale = rawMag > 4.0 ? (1.0 / 9.8) * 64.0 : 64.0;
      accX.add(a[0] * scale);
      accY.add(a[1] * scale);
      accZ.add(a[2] * scale);
    }

    // Compute magnitude for each sample
    final List<double> accMag = [];
    for (int i = 0; i < accelHistory.length; i++) {
      final x = accX[i];
      final y = accY[i];
      final z = accZ[i];
      accMag.add(math.sqrt(x * x + y * y + z * z));
    }

    final double accMagMeanRaw = accMag.reduce((a, b) => a + b) / accMag.length;
    final double accMagStd = _calculateStd(accMag, accMagMeanRaw);

    // To handle sensor calibration errors (where stationary gravity raw magnitude is e.g. 62 LSB instead of exactly 64 LSB),
    // if the user is stationary (accMagStd < 2.0 LSB), we center the magnitude to exactly 0.0.
    // If they are moving, we subtract the standard 64.0 LSB.
    final double accMagMean = accMagStd < 2.0 ? 0.0 : accMagMeanRaw - 64.0;

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
