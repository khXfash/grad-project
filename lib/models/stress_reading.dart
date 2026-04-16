import 'package:cloud_firestore/cloud_firestore.dart';

class StressReading {
  final String id;
  final DateTime timestamp;
  final int heartRate;
  final double skinTemp;
  final double accelX;
  final double accelY;
  final double accelZ;
  final int stressScore;

  const StressReading({
    required this.id,
    required this.timestamp,
    required this.heartRate,
    required this.skinTemp,
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    required this.stressScore,
  });

  double get accelMagnitude =>
      accelX * accelX + accelY * accelY + accelZ * accelZ;

  Map<String, dynamic> toMap() => {
    'timestamp': Timestamp.fromDate(timestamp),
    'heartRate': heartRate,
    'skinTemp': skinTemp,
    'accelX': accelX,
    'accelY': accelY,
    'accelZ': accelZ,
    'stressScore': stressScore,
  };

  factory StressReading.fromMap(String id, Map<String, dynamic> map) =>
      StressReading(
        id: id,
        timestamp: (map['timestamp'] as Timestamp).toDate(),
        heartRate: (map['heartRate'] as num).toInt(),
        skinTemp: (map['skinTemp'] as num).toDouble(),
        accelX: (map['accelX'] as num).toDouble(),
        accelY: (map['accelY'] as num).toDouble(),
        accelZ: (map['accelZ'] as num).toDouble(),
        stressScore: (map['stressScore'] as num).toInt(),
      );
}
