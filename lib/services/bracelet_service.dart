import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:math' show Random;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/stress_reading.dart';
import 'wesad_ml_service.dart';
import 'stress_ai_service.dart';
import 'lightgbm_ml_service.dart';
import 'feature_extractor.dart';

class BraceletService {
  static final BraceletService _instance = BraceletService._internal();
  factory BraceletService() => _instance;
  BraceletService._internal() {
    _initMl();
  }

  // WESAD AI model service
  final WesadMlService _wesadService = WesadMlService();

  // LightGBM AI model service
  final LightGbmMlService _lightGbmService = LightGbmMlService();

  // Connection & Scan status
  bool _isConnected = false;
  bool _isMockMode = false;
  bool _isFingerDetected = false;
  bool _isScanning = false;

  // BLE references
  BluetoothDevice? _device;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<bool>? _isScanningSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<int>>? _charSub;

  final List<ScanResult> _scanResults = [];
  final _controller = StreamController<StressReading>.broadcast();

  // Simulated timer
  Timer? _mockTimer;
  final _random = Random();

  // Downsampling sliding window buffers
  final List<double> _tempHistory = [];
  final List<double> _hrHistory = [];
  final List<List<double>> _accelHistory = [];

  // Downsampling timestamp trackers
  DateTime? _lastTempSampleTime;
  DateTime? _lastHrSampleTime;
  DateTime? _lastAccelSampleTime;
  DateTime? _lastPredictionTime;

  // Incoming line buffer for BLE UART chunks
  String _bleLineBuffer = "";

  // Current live sensor values
  int _heartRate = 72;
  double _skinTemp = 36.5;
  double _accelX = 0.0;
  double _accelY = 0.0;
  double _accelZ = 9.8;

  // Getters
  bool get isConnected => _isConnected;
  bool get isMockMode => _isMockMode;
  bool get isFingerDetected => _isFingerDetected;
  bool get isScanning => _isScanning;
  List<ScanResult> get scanResults => List.unmodifiable(_scanResults);
  Stream<StressReading> get readings => _controller.stream;

  int get currentHeartRate => _heartRate;
  double get currentSkinTemp => _skinTemp;
  double get accelX => _accelX;
  double get accelY => _accelY;
  double get accelZ => _accelZ;

  Future<void> _initMl() async {
    await _wesadService.initialize();
    await _lightGbmService.initialize();
  }

  // ── BLE SCANNING ──────────────────────────────────────────────────────────

  Future<void> startScan() async {
    // 1. Request permissions first
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    if (statuses[Permission.bluetoothScan]?.isGranted != true ||
        statuses[Permission.bluetoothConnect]?.isGranted != true) {
      log("BraceletService: Bluetooth permissions denied");
      return;
    }

    _scanResults.clear();
    _isScanning = true;

    // Listen to native scan state changes
    _isScanningSub?.cancel();
    _isScanningSub = FlutterBluePlus.isScanning.listen((scanning) {
      _isScanning = scanning;
    });

    // Listen to discovered devices
    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      _scanResults.clear();
      _scanResults.addAll(results);
    });

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    } catch (e) {
      log("BraceletService startScan error: $e");
      _isScanning = false;
    }
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    _isScanning = false;
    _isScanningSub?.cancel();
    _scanSub?.cancel();
  }

  // ── CONNECTION ────────────────────────────────────────────────────────────

  Future<void> connectToDevice(BluetoothDevice device) async {
    await stopScan();
    disconnect(); // disconnect any current connection first

    _device = device;
    log("BraceletService: Connecting to ${device.platformName}...");

    try {
      // Connect to BLE Device
      await device.connect(autoConnect: false).timeout(const Duration(seconds: 10));

      // Observe connection state
      _connSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.connected) {
          _isConnected = true;
          _isMockMode = false;
          log("BraceletService: BLE device connected!");
        } else if (state == BluetoothConnectionState.disconnected) {
          log("BraceletService: BLE device disconnected.");
          disconnect();
        }
      });

      _isConnected = true;
      _isMockMode = false;

      // ── Discover Services & Characteristics ────────────────────────────────
      List<BluetoothService> services = await device.discoverServices();
      BluetoothCharacteristic? txChar;

      for (var service in services) {
        // Nordic UART Service: "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
        if (service.uuid.toString().toLowerCase() == "6e400001-b5a3-f393-e0a9-e50e24dcca9e") {
          for (var char in service.characteristics) {
            // Nordic UART TX: "6e400003-b5a3-f393-e0a9-e50e24dcca9e"
            if (char.uuid.toString().toLowerCase() == "6e400003-b5a3-f393-e0a9-e50e24dcca9e") {
              txChar = char;
              break;
            }
          }
        }
      }

      if (txChar != null) {
        _bleLineBuffer = "";
        await txChar.setNotifyValue(true);
        _charSub = txChar.lastValueStream.listen((bytes) {
          _onBytesReceived(bytes);
        });
        log("BraceletService: Subscribed to notifications on TX characteristic");
      } else {
        log("BraceletService: Nordic UART TX Characteristic not found. Disconnecting...");
        await device.disconnect();
        disconnect();
      }

    } catch (e) {
      log("BraceletService connectToDevice error: $e");
      disconnect();
      rethrow;
    }
  }

  // ── SIMULATION / DEMO MODE ────────────────────────────────────────────────

  void startSimulationMode() {
    disconnect();
    _isConnected = true;
    _isMockMode = true;
    _isFingerDetected = true;

    // Reset buffers
    _tempHistory.clear();
    _hrHistory.clear();
    _accelHistory.clear();
    _lastTempSampleTime = null;
    _lastHrSampleTime = null;
    _lastAccelSampleTime = null;
    _lastPredictionTime = null;

    // In simulated mode, we generate a high-speed data stream every 100ms
    // to simulate the ESP32 ~10Hz transmission, allowing realistic downsampling
    _mockTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      // Simulate slight drift from base metrics
      _heartRate = (_heartRate + _random.nextInt(3) - 1).clamp(55, 120);
      _skinTemp = double.parse(
        (_skinTemp + (_random.nextDouble() * 0.1 - 0.05)).toStringAsFixed(2),
      ).clamp(35.0, 38.5);

      _accelX = double.parse((_random.nextDouble() * 1.5 - 0.75).toStringAsFixed(3));
      _accelY = double.parse((_random.nextDouble() * 1.5 - 0.75).toStringAsFixed(3));
      _accelZ = double.parse((9.8 + _random.nextDouble() * 0.8 - 0.4).toStringAsFixed(3));

      _processSensorMetrics(
        hr: _heartRate,
        temp: _skinTemp,
        ax: _accelX,
        ay: _accelY,
        az: _accelZ,
      );
    });
  }

  void connect() {
    // Legacy support: defaults to simulation mode
    startSimulationMode();
  }

  void disconnect() {
    _isConnected = false;
    _isMockMode = false;
    _isFingerDetected = false;
    _lastPredictionTime = null;

    // Cancel BLE subscriptions
    _charSub?.cancel();
    _charSub = null;
    _connSub?.cancel();
    _connSub = null;
    _device?.disconnect();
    _device = null;

    // Cancel simulated timer
    _mockTimer?.cancel();
    _mockTimer = null;
  }

  // ── DATA PROCESSING ────────────────────────────────────────────────────────

  void _onBytesReceived(List<int> bytes) {
    try {
      String chunk = utf8.decode(bytes);
      _bleLineBuffer += chunk;

      while (_bleLineBuffer.contains('\n')) {
        int newlineIndex = _bleLineBuffer.indexOf('\n');
        String line = _bleLineBuffer.substring(0, newlineIndex).trim();
        _bleLineBuffer = _bleLineBuffer.substring(newlineIndex + 1);

        if (line.isNotEmpty) {
          _processLine(line);
        }
      }
    } catch (e) {
      log("BraceletService decoder error: $e");
    }
  }

  void _processLine(String line) {
    if (line == "NO_FINGER") {
      if (_isFingerDetected) {
        _isFingerDetected = false;
        log("BraceletService: Sensor Empty (NO_FINGER)");
        // Emit empty finger status via stream
        final reading = StressReading(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          timestamp: DateTime.now(),
          heartRate: 0,
          skinTemp: 0.0,
          accelX: 0.0,
          accelY: 0.0,
          accelZ: 0.0,
          stressScore: 0,
        );
        _controller.add(reading);
      }
      return;
    }

    // Otherwise, parse CSV format:
    // beatAvg, lastTemp, ax, ay, az, gx, gy, gz
    try {
      List<String> tokens = line.split(',');
      if (tokens.length >= 5) {
        int hr = int.parse(tokens[0]);
        double temp = double.parse(tokens[1]);
        double ax = double.parse(tokens[2]);
        double ay = double.parse(tokens[3]);
        double az = double.parse(tokens[4]);

        _isFingerDetected = true;
        _processSensorMetrics(hr: hr, temp: temp, ax: ax, ay: ay, az: az);
      }
    } catch (e) {
      log("BraceletService CSV parse error: $e for line: '$line'");
    }
  }

  /// Downsamples streaming sensors and runs the WESAD multi-modal TFLite AI model.
  Future<void> _processSensorMetrics({
    required int hr,
    required double temp,
    required double ax,
    required double ay,
    required double az,
  }) async {
    final now = DateTime.now();

    // 1. If buffer is completely empty, "pre-fill" it to bypass WESAD's 60-second latency
    if (_tempHistory.isEmpty) {
      _tempHistory.addAll(List.filled(240, temp));
      _hrHistory.addAll(List.filled(60, hr.toDouble()));
      _accelHistory.addAll(List.filled(1920, [ax, ay, az]));
      _lastTempSampleTime = now;
      _lastHrSampleTime = now;
      _lastAccelSampleTime = now;
    } else {
      // 2. Downsample streaming events into FIFO buffers based on targeted sample rates

      // Accelerometer downsampling (~32Hz = every 31.25 ms)
      if (_lastAccelSampleTime == null ||
          now.difference(_lastAccelSampleTime!).inMilliseconds >= 31) {
        _accelHistory.add([ax, ay, az]);
        if (_accelHistory.length > 1920) _accelHistory.removeAt(0);
        _lastAccelSampleTime = now;
      }

      // Skin Temperature downsampling (~4Hz = every 250 ms)
      if (_lastTempSampleTime == null ||
          now.difference(_lastTempSampleTime!).inMilliseconds >= 250) {
        _tempHistory.add(temp);
        if (_tempHistory.length > 240) _tempHistory.removeAt(0);
        _lastTempSampleTime = now;
      }

      // Heart Rate downsampling (~1Hz = every 1000 ms)
      if (_lastHrSampleTime == null ||
          now.difference(_lastHrSampleTime!).inMilliseconds >= 1000) {
        _hrHistory.add(hr.toDouble());
        if (_hrHistory.length > 60) _hrHistory.removeAt(0);
        _lastHrSampleTime = now;
      }
    }

    // 3. Update current variables
    _heartRate = hr;
    _skinTemp = temp;
    _accelX = ax;
    _accelY = ay;
    _accelZ = az;

    // 4. Run the WESAD multi-modal classifier & emit prediction at a throttled rate
    if (_lastPredictionTime == null ||
        now.difference(_lastPredictionTime!).inSeconds >= 2) {
      _lastPredictionTime = now;

      int score = 0;
      if (_lightGbmService.isInitialized) {
        try {
          final List<double> features = FeatureExtractor.extractFeatures(
            tempHistory: List.from(_tempHistory),
            hrHistory: List.from(_hrHistory),
            accelHistory: List.from(_accelHistory),
          );
          final double stressProb = _lightGbmService.predict(features);
          score = (stressProb * 100).round().clamp(0, 100);
        } catch (e) {
          log("BraceletService: LightGBM AI prediction failed: $e");
        }
      }

      // Fallback 1: WESAD model (if LightGBM is not initialized or returned 0 stress)
      if (score == 0 && _wesadService.isInitialized) {
        try {
          List<double> probs = await _wesadService.predict(
            tempHistory: List.from(_tempHistory),
            hrHistory: List.from(_hrHistory),
            accelHistory: List.from(_accelHistory),
          );
          double stressProb = probs[1];
          score = (stressProb * 100).round().clamp(0, 100);
        } catch (e) {
          log("BraceletService: WESAD AI prediction failed: $e");
        }
      }

      // Fallback 2: Rule-based heuristic
      if (score == 0) {
        score = StressAiService.calculateStressScore(
          heartRate: hr,
          skinTemp: temp,
          accelX: ax,
          accelY: ay,
          accelZ: az,
        );
      }

      // Emit stress reading
      final reading = StressReading(
        id: now.millisecondsSinceEpoch.toString(),
        timestamp: now,
        heartRate: _heartRate,
        skinTemp: _skinTemp,
        accelX: _accelX,
        accelY: _accelY,
        accelZ: _accelZ,
        stressScore: score,
      );

      _controller.add(reading);
    }
  }

  void dispose() {
    disconnect();
    _isScanningSub?.cancel();
    _scanSub?.cancel();
    _controller.close();
    _wesadService.dispose();
    _lightGbmService.dispose();
  }
}
