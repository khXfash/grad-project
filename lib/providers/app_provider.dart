import 'dart:async';
import 'dart:developer';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';
import '../models/stress_reading.dart';
import '../models/mood_log.dart';
import '../services/bracelet_service.dart';
import '../services/firestore_service.dart';
import '../services/gemini_service.dart';
import '../helpers/stress_evaluator.dart';


class AppProvider extends ChangeNotifier {
  // ── Core services ────────────────────────────────────────
  final _bracelet = BraceletService();
  final _firestore = FirestoreService();
  final _gemini = GeminiService();

  // ── Auth ─────────────────────────────────────────────────
  User? _currentUser;
  bool _authLoading = true;

  User? get currentUser => _currentUser;
  bool get authLoading => _authLoading;
  bool get isAuthenticated => _currentUser != null;

  // ── Profile ────────────────────────────────────────────────
  String _profileName = '';
  String _doctorEmail = '';
  bool _profileLoading = false;

  String get profileName => _profileName;
  String get doctorEmail => _doctorEmail;
  String get reportEmail => _doctorEmail; // backward compatibility
  bool get profileLoading => _profileLoading;

  // ── Bracelet / sensor data ─────────────────────────────────
  StressReading? _latestReading;
  final List<StressReading> _recentReadings = [];
  final List<StressReading> _dbSaveBuffer = [];
  StreamSubscription<StressReading>? _braceletSub;
  bool _savingReadings = true;
  DateTime? _lastAlertSentTime;

  StressReading? get latestReading => _latestReading;
  List<StressReading> get recentReadings => List.unmodifiable(_recentReadings);
  bool get isConnected => _bracelet.isConnected;
  bool get isMockMode => _bracelet.isMockMode;
  bool get isFingerDetected => _bracelet.isFingerDetected;
  bool get isScanning => _bracelet.isScanning;
  List<dynamic> get scanResults => _bracelet.scanResults;
  bool get savingReadings => _savingReadings;
  int get currentHR => _bracelet.currentHeartRate;
  double get currentTemp => _bracelet.currentSkinTemp;

  // ── Recommendations ───────────────────────────────────────
  String? _recommendations;
  bool _recommendationsLoading = false;
  String? _recommendationsError;

  String? get recommendations => _recommendations;
  bool get recommendationsLoading => _recommendationsLoading;
  String? get recommendationsError => _recommendationsError;

  // ── Emotion detection ─────────────────────────────────────
  String _detectedEmotion = 'Unknown';
  String get detectedEmotion => _detectedEmotion;

  double get faceStressProbability {
    switch (_detectedEmotion) {
      case 'Fear':
        return 0.90;
      case 'Anger':
        return 0.85;
      case 'Disgust':
        return 0.70;
      case 'Sad':
        return 0.60;
      case 'Surprise':
        return 0.30;
      case 'Neutral':
        return 0.10;
      case 'Happy':
        return 0.00;
      default:
        return 0.00;
    }
  }

  // ── Stress evaluation ─────────────────────────────────────
    // Stress evaluation delegated to helper
  bool get isStressed => StressEvaluator.isStressed(
    latestReading: _latestReading,
    detectedEmotion: _detectedEmotion,
    faceStressProbability: faceStressProbability,
  );

  bool get isCriticalStress => StressEvaluator.isCriticalStress(
    latestReading: _latestReading,
    detectedEmotion: _detectedEmotion,
    faceStressProbability: faceStressProbability,
  );



  // ── Constructor ─────────────────────────────────────────────
  AppProvider() {
    _initAuth();
    _initGemini();
    _loadProfile();
  }

  // ── Firebase auth handling ─────────────────────────────────
  Future<void> _initAuth() async {
    final auth = FirebaseAuth.instance;
    // Safety fallback: unblock UI after 8 seconds if auth hangs
    Future.delayed(const Duration(seconds: 8), () {
      if (_authLoading) {
        _authLoading = false;
        notifyListeners();
      }
    });
    try {
      auth.authStateChanges().listen(
        (user) async {
          if (user == null) {
            try {
              await auth.signInAnonymously();
            } catch (_) {
              _authLoading = false;
              notifyListeners();
            }
          } else {
            _currentUser = user;
            _authLoading = false;
            notifyListeners();
            _loadHistory();
          }
        },
        onError: (_) {
          _authLoading = false;
          notifyListeners();
        },
      );
    } catch (_) {
      _authLoading = false;
      notifyListeners();
    }
  }

  void _initGemini() {
    try {
      final key = dotenv.env['GEMINI_API_KEY'] ?? '';
      if (key.isNotEmpty && key != 'YOUR_GEMINI_API_KEY_HERE') {
        _gemini.initialize(key);
      }
    } catch (_) {}
  }

  // ── Firestore interactions ─────────────────────────────────
  Future<void> _loadHistory() async {
    try {
      final readings = await _firestore.getReadings(limit: 20);
      _recentReadings.clear();
      _recentReadings.addAll(readings.reversed);
      notifyListeners();
      // Cleanup old records in background
      _firestore.pruneOldReadings();
    } catch (_) {}
  }

  Future<void> _loadProfile() async {
    _profileLoading = true;
    notifyListeners();
    try {
      final data = await _firestore.getProfile();
      if (data != null) {
        _profileName = data['name'] as String? ?? '';
        _doctorEmail =
            data['doctorEmail'] as String? ??
            data['reportEmail'] as String? ??
            '';
      }
    } catch (_) {}
    _profileLoading = false;
    notifyListeners();
  }

  Future<void> saveProfile({
    required String name,
    required String email,
  }) async {
    _profileName = name;
    _doctorEmail = email;
    notifyListeners();
    await _firestore.saveProfile({'name': name, 'doctorEmail': email});
  }

  // ── Authentication helpers ─────────────────────────────────
  Future<String?> signInWithEmail(String email, String password) async {
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return null;
    } on FirebaseAuthException catch (e) {
      return _friendlyAuthError(e.code);
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> registerWithEmail(String email, String password) async {
    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return null;
    } on FirebaseAuthException catch (e) {
      return _friendlyAuthError(e.code);
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> signInAnonymously() async {
    try {
      await FirebaseAuth.instance.signInAnonymously();
    } catch (_) {
      _authLoading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    disconnectBracelet();
    _recentReadings.clear();
    _latestReading = null;
    _recommendations = null;
    _currentUser = null;
    notifyListeners();
    await FirebaseAuth.instance.signOut();
  }

  String _friendlyAuthError(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Check your internet connection.';
      default:
        return 'Authentication failed ($code). Please try again.';
    }
  }

  // ── Bracelet control ───────────────────────────────────────
  void connectBracelet() {
    _braceletSub?.cancel();
    _bracelet.connect();
    _braceletSub = _bracelet.readings.listen(_onReading);
    notifyListeners();
  }

  void disconnectBracelet() {
    _bracelet.disconnect();
    _braceletSub?.cancel();
    notifyListeners();
  }

  Future<void> startScan() async {
    await _bracelet.startScan();
    notifyListeners();
  }

  Future<void> stopScan() async {
    await _bracelet.stopScan();
    notifyListeners();
  }

  Future<void> connectToDevice(dynamic device) async {
    _braceletSub?.cancel();
    await _bracelet.connectToDevice(device);
    _braceletSub = _bracelet.readings.listen(_onReading);
    notifyListeners();
  }

  void startSimulationMode() {
    _braceletSub?.cancel();
    _bracelet.startSimulationMode();
    _braceletSub = _bracelet.readings.listen(_onReading);
    notifyListeners();
  }

  void toggleSavingReadings() {
    _savingReadings = !_savingReadings;
    notifyListeners();
  }

  // ── Reading handling ─────────────────────────────────────
  void _onReading(StressReading reading) {
    _latestReading = reading;
    _recentReadings.add(reading);
    if (_recentReadings.length > 20) _recentReadings.removeAt(0);
    notifyListeners();

    if (_savingReadings && _currentUser != null) {
      _firestore.saveReading(reading);
    }
    _checkEmergencyAlert(reading);
  }

  // ── Emergency alert ─────────────────────────────────────
  void _checkEmergencyAlert(StressReading reading) {
    if (isCriticalStress && _doctorEmail.isNotEmpty) {
      final now = DateTime.now();
      if (_lastAlertSentTime == null ||
          now.difference(_lastAlertSentTime!).inMinutes >= 15) {
        _lastAlertSentTime = now;
        _firestore.sendEmergencyEmail(
          recipientEmail: _doctorEmail,
          patientName: _profileName.isNotEmpty ? _profileName : 'Patient',
          heartRate: reading.heartRate,
          skinTemp: reading.skinTemp,
          emotion: _detectedEmotion,
        );
        log(
          'AppProvider: Automatically triggered emergency alert email to $_doctorEmail',
        );
      }
    }
  }



  // ── Mood logging ───────────────────────────────────────
  Future<void> logMood({
    required String emotion,
    required String notes,
    String source = 'manual',
    int? confidence,
  }) async {
    final log = MoodLog(
      id: '',
      timestamp: DateTime.now(),
      emotion: emotion,
      notes: notes,
      stressScore: _latestReading?.stressScore ?? 0,
      source: source,
      confidence: confidence,
    );
    await _firestore.saveMoodLog(log);
  }

  void setDetectedEmotion(String emotion) {
    _detectedEmotion = emotion;
    notifyListeners();
  }

  // ── Gemini recommendations ───────────────────────────────
  Future<void> fetchRecommendations() async {
    if (_recommendationsLoading) return;
    _recommendationsLoading = true;
    _recommendationsError = null;
    notifyListeners();
    try {
      _recommendations = await _gemini.getStressRecommendations(
        isStressed: isStressed,
        emotion: _detectedEmotion == 'Unknown' ? null : _detectedEmotion,
      );
    } catch (e) {
      _recommendationsError = e.toString().replaceAll('Exception:', '').trim();
    } finally {
      _recommendationsLoading = false;
      notifyListeners();
    }
  }

  Future<String> sendChatMessage(String message) async {
    try {
      return await _gemini.chat(message, isStressed);
    } catch (e) {
      return "Sorry, I couldn't process that. Please check your API key.";
    }
  }

  // ── Firestore streams ─────────────────────────────────────
  // ── Weekly Report ─────────────────────────────────────
  Future<(List<StressReading>, List<MoodLog>)> getWeeklyReport() async {
    final since = DateTime.now().subtract(const Duration(days: 7));
    final readings = await _firestore.getReadingsSince(since);
    final moods = await _firestore.getMoodLogsSince(since);
    return (readings, moods);
  }

  Stream<List<StressReading>> watchReadings() => _firestore.watchReadings();
  Stream<List<MoodLog>> watchMoodLogs() => _firestore.watchMoodLogs();

  Future<void> deleteMoodLog(String id) => _firestore.deleteMoodLog(id);
}
