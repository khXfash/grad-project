import 'package:cloud_firestore/cloud_firestore.dart';

class MoodLog {
  final String id;
  final DateTime timestamp;
  final String emotion;
  final String notes;
  final int stressScore;
  /// 'camera' for auto-detected from emotion screen, 'manual' for user-entered
  final String source;
  /// Confidence percentage (0-100) when source == 'camera', else null
  final int? confidence;

  const MoodLog({
    required this.id,
    required this.timestamp,
    required this.emotion,
    required this.notes,
    required this.stressScore,
    this.source = 'manual',
    this.confidence,
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
      case 'stressed':
        return '😤';
      case 'angry':
        return '😠';
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
    'source': source,
    if (confidence != null) 'confidence': confidence,
  };

  factory MoodLog.fromMap(String id, Map<String, dynamic> map) => MoodLog(
    id: id,
    timestamp: (map['timestamp'] as Timestamp).toDate(),
    emotion: map['emotion'] as String,
    notes: map['notes'] as String? ?? '',
    stressScore: (map['stressScore'] as num).toInt(),
    source: map['source'] as String? ?? 'manual',
    confidence: map['confidence'] != null ? (map['confidence'] as num).toInt() : null,
  );
}
