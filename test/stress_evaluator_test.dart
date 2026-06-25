import 'package:flutter_test/flutter_test.dart';
import 'package:emo_health/helpers/stress_evaluator.dart';
import 'package:emo_health/models/stress_reading.dart';

void main() {
  group('StressReading Tests', () {
    test('accelMagnitude calculation', () {
      final reading = StressReading(
        id: '1',
        timestamp: DateTime.now(),
        heartRate: 75,
        skinTemp: 31.5,
        accelX: 2.0,
        accelY: 3.0,
        accelZ: 4.0,
        stressScore: 45,
      );

      // 2^2 + 3^2 + 4^2 = 4 + 9 + 16 = 29
      expect(reading.accelMagnitude, equals(29.0));
    });
  });

  group('StressEvaluator.isStressed Tests', () {
    test('Stressed based on sensor reading >= 50', () {
      final reading = StressReading(
        id: '1',
        timestamp: DateTime.now(),
        heartRate: 80,
        skinTemp: 32.0,
        accelX: 0.1,
        accelY: 0.2,
        accelZ: 0.1,
        stressScore: 55,
      );

      final result = StressEvaluator.isStressed(
        latestReading: reading,
        detectedEmotion: 'Neutral',
        faceStressProbability: 0.10,
      );

      expect(result, isTrue);
    });

    test('Not Stressed based on sensor reading < 50', () {
      final reading = StressReading(
        id: '2',
        timestamp: DateTime.now(),
        heartRate: 70,
        skinTemp: 32.0,
        accelX: 0.1,
        accelY: 0.2,
        accelZ: 0.1,
        stressScore: 45,
      );

      final result = StressEvaluator.isStressed(
        latestReading: reading,
        detectedEmotion: 'Sad',
        faceStressProbability: 0.80, // ignored because sensor data is present
      );

      expect(result, isFalse);
    });

    test('Fallback to facial emotion when sensor reading is null', () {
      // Scenario A: Face probability >= 0.50
      final resultStressed = StressEvaluator.isStressed(
        latestReading: null,
        detectedEmotion: 'Sad',
        faceStressProbability: 0.60,
      );
      expect(resultStressed, isTrue);

      // Scenario B: Face probability < 0.50
      final resultNotStressed = StressEvaluator.isStressed(
        latestReading: null,
        detectedEmotion: 'Happy',
        faceStressProbability: 0.30,
      );
      expect(resultNotStressed, isFalse);

      // Scenario C: Detected emotion is Unknown
      final resultUnknown = StressEvaluator.isStressed(
        latestReading: null,
        detectedEmotion: 'Unknown',
        faceStressProbability: 0.80,
      );
      expect(resultUnknown, isFalse);
    });
  });

  group('StressEvaluator.isCriticalStress Tests', () {
    test('Always false if latestReading is null', () {
      final result = StressEvaluator.isCriticalStress(
        latestReading: null,
        detectedEmotion: 'Sad',
        faceStressProbability: 0.95,
      );
      expect(result, isFalse);
    });

    test('Sensor-only threshold (> 90) when emotion is Unknown', () {
      final readingAbove = StressReading(
        id: '1',
        timestamp: DateTime.now(),
        heartRate: 110,
        skinTemp: 34.0,
        accelX: 0.0,
        accelY: 0.0,
        accelZ: 0.0,
        stressScore: 91,
      );
      expect(
        StressEvaluator.isCriticalStress(
          latestReading: readingAbove,
          detectedEmotion: 'Unknown',
          faceStressProbability: 0.10,
        ),
        isTrue,
      );

      final readingBelow = StressReading(
        id: '2',
        timestamp: DateTime.now(),
        heartRate: 110,
        skinTemp: 34.0,
        accelX: 0.0,
        accelY: 0.0,
        accelZ: 0.0,
        stressScore: 90,
      );
      expect(
        StressEvaluator.isCriticalStress(
          latestReading: readingBelow,
          detectedEmotion: 'Unknown',
          faceStressProbability: 0.99, // ignored because emotion is Unknown
        ),
        isFalse,
      );
    });

    test('Blended weighting (60% sensor, 40% facial) threshold (> 0.90)', () {
      // 95 score (0.95 prob) and 90 face probability
      // (0.95 * 0.6) + (0.90 * 0.4) = 0.57 + 0.36 = 0.93 (> 0.90) -> Critical
      final reading1 = StressReading(
        id: '1',
        timestamp: DateTime.now(),
        heartRate: 100,
        skinTemp: 33.0,
        accelX: 0.0,
        accelY: 0.0,
        accelZ: 0.0,
        stressScore: 95,
      );
      expect(
        StressEvaluator.isCriticalStress(
          latestReading: reading1,
          detectedEmotion: 'Fear',
          faceStressProbability: 0.90,
        ),
        isTrue,
      );

      // 80 score (0.80 prob) and 85 face probability
      // (0.80 * 0.6) + (0.85 * 0.4) = 0.48 + 0.34 = 0.82 (<= 0.90) -> Not Critical
      final reading2 = StressReading(
        id: '2',
        timestamp: DateTime.now(),
        heartRate: 100,
        skinTemp: 33.0,
        accelX: 0.0,
        accelY: 0.0,
        accelZ: 0.0,
        stressScore: 80,
      );
      expect(
        StressEvaluator.isCriticalStress(
          latestReading: reading2,
          detectedEmotion: 'Sad',
          faceStressProbability: 0.85,
        ),
        isFalse,
      );
    });
  });
}
