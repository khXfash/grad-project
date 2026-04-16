import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/stress_reading.dart';
import '../models/mood_log.dart';
import '../services/bracelet_service.dart';
import '../services/firestore_service.dart';
import '../services/gemini_service.dart';

class AppProvider extends ChangeNotifier {
  final _bracelet = BraceletService();
  final _firestore = FirestoreService();
  final _gemini = GeminiService();

  // ── Auth ──────────────────────────────────────────────────────────────────
  User? _currentUser;
  bool _authLoading = true;

  User? get currentUser => _currentUser;
  bool get authLoading => _authLoading;
  bool get isAuthenticated => _currentUser != null;

  // ── Bracelet ──────────────────────────────────────────────────────────────
  StressReading? _latestReading;
  final List<StressReading> _recentReadings = [];
  StreamSubscription<StressReading>? _braceletSub;
  bool _savingReadings = true;

  StressReading? get latestReading => _latestReading;
  List<StressReading> get recentReadings => List.unmodifiable(_recentReadings);
  bool get isConnected => _bracelet.isConnected;
  bool get savingReadings => _savingReadings;

  int get currentHR => _bracelet.currentHeartRate;
  double get currentTemp => _bracelet.currentSkinTemp;

  // ── Recommendations ───────────────────────────────────────────────────────
  String? _recommendations;
  bool _recommendationsLoading = false;
  String? _recommendationsError;

  String? get recommendations => _recommendations;
  bool get recommendationsLoading => _recommendationsLoading;
  String? get recommendationsError => _recommendationsError;

  // ── Emotion ───────────────────────────────────────────────────────────────
  String _detectedEmotion = 'Unknown';
  String get detectedEmotion => _detectedEmotion;

  // ── Gemini ready ─────────────────────────────────────────────────────────
  bool get geminiReady => _gemini.isInitialized;

  AppProvider() {
    _initAuth();
    _initGemini();
  }

  Future<void> _initAuth() async {
    final auth = FirebaseAuth.instance;

    // Safety fallback: if auth takes > 8s (e.g. Firebase not provisioned), unblock UI anyway
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
            } catch (e) {
              // Anonymous auth failed (e.g. not enabled yet) — unblock UI
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
    } catch (e) {
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

  Future<void> _loadHistory() async {
    try {
      final readings = await _firestore.getReadings(limit: 20);
      _recentReadings.clear();
      _recentReadings.addAll(readings.reversed);
      notifyListeners();
    } catch (_) {
      // Firestore not available yet — silently ignore
    }
  }

  // ── Email / Password auth ─────────────────────────────────────────────────

  /// Returns null on success, or an error message string on failure.
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

  void connectBracelet() {
    _bracelet.connect();
    _braceletSub = _bracelet.readings.listen(_onReading);
    notifyListeners();
  }

  void disconnectBracelet() {
    _bracelet.disconnect();
    _braceletSub?.cancel();
    notifyListeners();
  }

  void toggleSavingReadings() {
    _savingReadings = !_savingReadings;
    notifyListeners();
  }

  void _onReading(StressReading reading) {
    _latestReading = reading;
    _recentReadings.add(reading);
    if (_recentReadings.length > 20) _recentReadings.removeAt(0);
    notifyListeners();

    if (_savingReadings && _currentUser != null) {
      _firestore.saveReading(reading);
    }
  }

  // ── Mood logging ──────────────────────────────────────────────────────────

  Future<void> logMood({required String emotion, required String notes}) async {
    final log = MoodLog(
      id: '',
      timestamp: DateTime.now(),
      emotion: emotion,
      notes: notes,
      stressScore: _latestReading?.stressScore ?? 0,
    );
    await _firestore.saveMoodLog(log);
  }

  // ── Emotion detection ─────────────────────────────────────────────────────

  void setDetectedEmotion(String emotion) {
    _detectedEmotion = emotion;
    notifyListeners();
  }

  // ── Gemini recommendations ────────────────────────────────────────────────

  Future<void> fetchRecommendations() async {
    if (_recommendationsLoading) return;
    _recommendationsLoading = true;
    _recommendationsError = null;
    notifyListeners();

    try {
      final score = _latestReading?.stressScore ?? 50;
      final label = _stressLabel(score);
      _recommendations = await _gemini.getStressRecommendations(
        stressScore: score,
        stressLabel: label,
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
      final score = _latestReading?.stressScore ?? 50;
      return await _gemini.chat(message, score);
    } catch (e) {
      return 'Sorry, I couldn\'t process that. Please check your API key.';
    }
  }

  String _stressLabel(int score) {
    if (score < 33) return 'Calm';
    if (score < 50) return 'Mild';
    if (score < 66) return 'Moderate';
    if (score < 80) return 'High';
    return 'Severe';
  }

  // ── Firestore streams ─────────────────────────────────────────────────────

  Stream<List<StressReading>> watchReadings() => _firestore.watchReadings();

  Stream<List<MoodLog>> watchMoodLogs() => _firestore.watchMoodLogs();

  Future<void> deleteMoodLog(String id) => _firestore.deleteMoodLog(id);

  @override
  void dispose() {
    _braceletSub?.cancel();
    _bracelet.dispose();
    super.dispose();
  }
}
