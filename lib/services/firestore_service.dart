import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/stress_reading.dart';
import '../models/mood_log.dart';

class FirestoreService {
  static final FirestoreService _instance = FirestoreService._internal();
  factory FirestoreService() => _instance;
  FirestoreService._internal();

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  CollectionReference<Map<String, dynamic>> get _stressCol =>
      _db.collection('users').doc(_uid).collection('stress_readings');

  CollectionReference<Map<String, dynamic>> get _moodCol =>
      _db.collection('users').doc(_uid).collection('mood_logs');

  // ── Stress Readings ──────────────────────────────────────────────────────

  Future<void> saveReading(StressReading reading) async {
    if (_uid == null) return;
    await _stressCol.add(reading.toMap());
  }

  Stream<List<StressReading>> watchReadings({int limit = 30}) {
    if (_uid == null) return const Stream.empty();
    return _stressCol
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (s) =>
              s.docs.map((d) => StressReading.fromMap(d.id, d.data())).toList(),
        );
  }

  Future<List<StressReading>> getReadings({int limit = 50}) async {
    if (_uid == null) return [];
    final snap = await _stressCol
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map((d) => StressReading.fromMap(d.id, d.data())).toList();
  }

  // ── Mood Logs ────────────────────────────────────────────────────────────

  Future<void> saveMoodLog(MoodLog log) async {
    if (_uid == null) return;
    await _moodCol.add(log.toMap());
  }

  Stream<List<MoodLog>> watchMoodLogs({int limit = 30}) {
    if (_uid == null) return const Stream.empty();
    return _moodCol
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (s) => s.docs.map((d) => MoodLog.fromMap(d.id, d.data())).toList(),
        );
  }

  Future<void> deleteMoodLog(String id) async {
    if (_uid == null) return;
    await _moodCol.doc(id).delete();
  }
}
