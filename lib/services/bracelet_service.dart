import 'dart:async';
import 'dart:math';
import '../models/stress_reading.dart';
import 'stress_ai_service.dart';

class BraceletService {
  static final BraceletService _instance = BraceletService._internal();
  factory BraceletService() => _instance;
  BraceletService._internal();

  bool _isConnected = false;
  Timer? _timer;
  final _random = Random();
  final _controller = StreamController<StressReading>.broadcast();

  // Current sensor values
  int _heartRate = 72;
  double _skinTemp = 36.5;
  double _accelX = 0.0;
  double _accelY = 0.0;
  double _accelZ = 9.8;

  bool get isConnected => _isConnected;
  Stream<StressReading> get readings => _controller.stream;

  int get currentHeartRate => _heartRate;
  double get currentSkinTemp => _skinTemp;
  double get accelX => _accelX;
  double get accelY => _accelY;
  double get accelZ => _accelZ;

  void connect() {
    if (_isConnected) return;
    _isConnected = true;
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _emitReading());
    _emitReading();
  }

  void disconnect() {
    _isConnected = false;
    _timer?.cancel();
    _timer = null;
  }

  void _emitReading() {
    // Simulate realistic sensor drift
    _heartRate = (_heartRate + _random.nextInt(7) - 3).clamp(55, 120);
    _skinTemp = double.parse(
      (_skinTemp + (_random.nextDouble() * 0.4 - 0.2)).toStringAsFixed(1),
    ).clamp(35.0, 38.5);

    // Accelerometer: mostly 0-2 range with occasional jumps (movement)
    _accelX = double.parse((_random.nextDouble() * 2 - 1).toStringAsFixed(3));
    _accelY = double.parse((_random.nextDouble() * 2 - 1).toStringAsFixed(3));
    _accelZ = double.parse(
      (9.8 + _random.nextDouble() * 1.0 - 0.5).toStringAsFixed(3),
    );

    final score = StressAiService.calculateStressScore(
      heartRate: _heartRate,
      skinTemp: _skinTemp,
      accelX: _accelX,
      accelY: _accelY,
      accelZ: _accelZ,
    );

    final reading = StressReading(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      timestamp: DateTime.now(),
      heartRate: _heartRate,
      skinTemp: _skinTemp,
      accelX: _accelX,
      accelY: _accelY,
      accelZ: _accelZ,
      stressScore: score,
    );

    _controller.add(reading);
  }

  void dispose() {
    disconnect();
    _controller.close();
  }
}
