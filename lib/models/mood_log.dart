import 'package:cloud_firestore/cloud_firestore.dart';

class MoodLog {
  final String id;
  final DateTime timestamp;
  final String emotion;
  final String notes;
  final int stressScore;

  const MoodLog({
    required this.id,
    required this.timestamp,
    required this.emotion,
    required this.notes,
    required this.stressScore,
  });

  String get emotionEmoji {
    switch (emotion.toLowerCase()) {
      case 'happy':
        return '😊';
      case 'calm':
        return '😌';
      case 'sad':
        return '😢';
      case 'anxious':
        return '😰';
      case 'angry':
        return '😤';
      case 'neutral':
        return '😐';
      default:
        return '🙂';
    }
  }

  Map<String, dynamic> toMap() => {
    'timestamp': Timestamp.fromDate(timestamp),
    'emotion': emotion,
    'notes': notes,
    'stressScore': stressScore,
  };

  factory MoodLog.fromMap(String id, Map<String, dynamic> map) => MoodLog(
    id: id,
    timestamp: (map['timestamp'] as Timestamp).toDate(),
    emotion: map['emotion'] as String,
    notes: map['notes'] as String? ?? '',
    stressScore: (map['stressScore'] as num).toInt(),
  );
}
