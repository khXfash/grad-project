import 'dart:developer';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/stress_reading.dart';
import '../models/mood_log.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

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

  Future<void> sendEmergencyEmail({
    required String recipientEmail,
    required String patientName,
    required int heartRate,
    required double skinTemp,
    required String emotion,
  }) async {
    final String subject = 'URGENT: Critical Stress Alert - $patientName';
    final String bodyText = '''
URGENT MEDICAL ALERT: Critical stress levels detected for patient $patientName.

Current Metrics:
- Status: Critical Stress Detected
- Heart Rate: $heartRate bpm
- Skin Temp: ${skinTemp.toStringAsFixed(1)}°C
- Facial Emotion: $emotion
- Timestamp: ${DateTime.now().toLocal().toString()}

Please review this alert as soon as possible.
''';

    // 1. Save alert record to Firestore for tracking history
    try {
      final mailDoc = {
        'to': recipientEmail,
        'message': {
          'subject': subject,
          'text': bodyText,
        },
        'createdAt': FieldValue.serverTimestamp(),
      };
      await _db.collection('mail').add(mailDoc);
      log("FirestoreService: Saved alert record to Firestore 'mail' collection.");
    } catch (e) {
      log("FirestoreService: Failed to save record to Firestore: $e");
    }

    // 2. Send email directly using SMTP in the background automatically
    final senderEmail = dotenv.env['SENDER_EMAIL'] ?? '';
    final appPassword = dotenv.env['SENDER_APP_PASSWORD'] ?? '';

    if (senderEmail.isEmpty || appPassword.isEmpty) {
      log("FirestoreService: SENDER_EMAIL or SENDER_APP_PASSWORD is not set in .env. Skipping SMTP send.");
      throw Exception("SMTP sender credentials are not configured in the app. Please add SENDER_EMAIL and SENDER_APP_PASSWORD to .env");
    }

    final smtpServer = gmail(senderEmail, appPassword);

    final message = Message()
      ..from = Address(senderEmail, 'EmoHealth Alerts')
      ..recipients.add(recipientEmail)
      ..subject = subject
      ..text = bodyText;

    try {
      await send(message, smtpServer);
      log('FirestoreService: Emergency alert email successfully sent directly to $recipientEmail via Gmail SMTP!');
    } on MailerException catch (e) {
      log('FirestoreService SMTP error: $e');
      for (var p in e.problems) {
        log('SMTP Problem: ${p.code} - ${p.msg}');
      }
      throw Exception("Failed to send email: ${e.toString()}");
    } catch (e) {
      log('FirestoreService General error sending email: $e');
      throw Exception("General email sending error: $e");
    }
  }
}
