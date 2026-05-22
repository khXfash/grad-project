import 'dart:developer';
import 'package:tflite_flutter/tflite_flutter.dart';

class WesadMlService {
  Interpreter? _interpreter;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  /// Loads the multi-modal WESAD model from assets.
  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      final options = InterpreterOptions()..threads = 4;
      _interpreter = await Interpreter.fromAsset(
        'assets/models/wesad_hardware_classifier.tflite',
        options: options,
      );
      _isInitialized = true;
      log("WesadMlService: Initialized successfully with multi-modal classifier");
    } catch (e) {
      log("WesadMlService error on initialization: $e");
    }
  }

  /// Closes the TFLite interpreter.
  void dispose() {
    _interpreter?.close();
    _isInitialized = false;
  }

  /// Predicts affective states from skin temperature, heart rate, and 3-axis accelerometer.
  /// Inputs details:
  /// - tempHistory: List of size 240 (4Hz * 60s)
  /// - hrHistory: List of size 60 (1Hz * 60s)
  /// - accelHistory: List of size 1920 (32Hz * 60s), where each element is [x, y, z]
  ///
  /// Returns a List of probabilities: [Baseline/Calm, Stress, Amusement]
  Future<List<double>> predict({
    required List<double> tempHistory,
    required List<double> hrHistory,
    required List<List<double>> accelHistory,
  }) async {
    if (!_isInitialized || _interpreter == null) {
      log("WesadMlService: Not initialized, returning default calm probabilities");
      return [1.0, 0.0, 0.0];
    }

    try {
      // 1. Prepare inputs shaped exactly to the model requirements
      // temp shape: [1, 240, 1]
      var tempInput = [
        tempHistory.map((t) => [t]).toList()
      ];

      // hr shape: [1, 60, 1]
      var hrInput = [
        hrHistory.map((h) => [h]).toList()
      ];

      // accel shape: [1, 1920, 3]
      var accelInput = [
        accelHistory.map((a) => [a[0], a[1], a[2]]).toList()
      ];

      // Package inputs into a list matching model's inputs sequence:
      // Input 0: serving_default_input_temp:0
      // Input 1: serving_default_input_hr:0
      // Input 2: serving_default_input_acc:0
      List<Object> inputs = [tempInput, hrInput, accelInput];

      // 2. Prepare outputs buffer matching the output shape [1, 3]
      var output = List.filled(3, 0.0).reshape([1, 3]);
      Map<int, Object> outputs = {0: output};

      // 3. Run multi-input inference
      _interpreter!.runForMultipleInputs(inputs, outputs);

      // Extract results from [1, 3] shape
      List<double> probabilities = (output[0] as List).cast<double>();
      return probabilities;
    } catch (e) {
      log("WesadMlService inference error: $e");
      return [1.0, 0.0, 0.0]; // default fallback
    }
  }
}
