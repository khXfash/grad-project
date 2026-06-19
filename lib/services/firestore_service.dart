import 'dart:developer';
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

  /// Deletes stress readings older than 7 days to keep Firestore storage clean.
  /// Limits to 100 items per prune run to ensure safe batch size limits.
  Future<void> pruneOldReadings() async {
    if (_uid == null) return;
    try {
      final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
      final oldDocs = await _stressCol
          .where('timestamp', isLessThan: Timestamp.fromDate(sevenDaysAgo))
          .limit(100)
          .get();

      if (oldDocs.docs.isNotEmpty) {
        final batch = _db.batch();
        for (var doc in oldDocs.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
        log("FirestoreService: Pruned ${oldDocs.docs.length} old readings.");
      }
    } catch (e) {
      log("FirestoreService error pruning: $e");
    }
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

  // ── User Profile ─────────────────────────────────────────────────────────

  DocumentReference<Map<String, dynamic>> get _profileDoc =>
      _db.collection('users').doc(_uid).collection('profile').doc('data');

  Future<void> saveProfile(Map<String, dynamic> data) async {
    if (_uid == null) return;
    await _profileDoc.set(data, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>?> getProfile() async {
    if (_uid == null) return null;
    final snap = await _profileDoc.get();
    return snap.exists ? snap.data() : null;
  }

  // ── Weekly Report ─────────────────────────────────────────────────────────

  Future<List<StressReading>> getReadingsSince(DateTime since) async {
    if (_uid == null) return [];
    final snap = await _stressCol
        .where('timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .orderBy('timestamp', descending: false)
        .get();
    return snap.docs.map((d) => StressReading.fromMap(d.id, d.data())).toList();
  }

  Future<List<MoodLog>> getMoodLogsSince(DateTime since) async {
    if (_uid == null) return [];
    final snap = await _moodCol
        .where('timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .orderBy('timestamp', descending: false)
        .get();
    return snap.docs.map((d) => MoodLog.fromMap(d.id, d.data())).toList();
  }
}
