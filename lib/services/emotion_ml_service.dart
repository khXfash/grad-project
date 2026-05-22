import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class EmotionMlService {
  Interpreter? _interpreter;
  bool _isInitialized = false;

  static const _labels = [
    'Anger',     // 0
    'Disgust',   // 1
    'Fear',      // 2
    'Happy',     // 3
    'Neutral',   // 4
    'Sad',       // 5
    'Surprise'   // 6
  ];

  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      final options = InterpreterOptions()..threads = 4;
      _interpreter = await Interpreter.fromAsset('assets/models/emotion_model.tflite', options: options);
      _isInitialized = true;
      log("EmotionMlService: Initialized successfully");
    } catch (e) {
      log("EmotionMlService error on initialization: $e");
    }
  }

  void dispose() {
    _interpreter?.close();
    _isInitialized = false;
  }

  Future<Map<String, dynamic>?> processFile(String imagePath, Rect bbox) async {
    if (!_isInitialized || _interpreter == null) return null;

    final result = await compute(_analyzeFileIsolate, {
      'imagePath': imagePath,
      'bbox': bbox,
    });

    if (result == null) return null;

    final inputShape = _interpreter!.getInputTensor(0).shape; // [1, 48, 48, 1]
    final inputType = _interpreter!.getInputTensor(0).type;
    
    dynamic rawInput;
    if (inputType == TensorType.uint8) {
      var uint8Data = Uint8List(result.length);
      for (int i = 0; i < result.length; i++) {
         uint8Data[i] = (result[i] * 255).clamp(0, 255).toInt();
      }
      rawInput = uint8Data.reshape(inputShape);
    } else {
      rawInput = result.reshape(inputShape);
    }
    
    var outputTensor = _interpreter!.getOutputTensor(0);
    var outputShape = outputTensor.shape;
    dynamic output;
    if (outputTensor.type == TensorType.float32) {
      output = List.filled(outputShape.reduce((a, b) => a * b), 0.0).reshape(outputShape);
    } else {
      output = List.filled(outputShape.reduce((a, b) => a * b), 0).reshape(outputShape);
    }
    
    try {
      _interpreter!.run(rawInput, output);
    } catch (e) {
      log("Interpreter run failed: $e");
      return null;
    }

    List<double> probs = [];
    if (outputTensor.type == TensorType.float32) {
      probs = (output[0] as List).cast<double>();
    } else {
      probs = (output[0] as List).map((e) => (e as int) / 255.0).toList();
    }

    // Apply Softmax iteratively in case these are raw logits
    double sumExp = 0.0;
    bool needsSoftmax = false;
    for (double p in probs) {
      if (p < 0 || p > 1.0) needsSoftmax = true;
    }
    if (needsSoftmax || probs.reduce((a,b)=>a+b) > 1.5) {
      double maxLogit = probs.reduce((a, b) => a > b ? a : b);
      for (int i = 0; i < probs.length; i++) {
        probs[i] = math.exp(probs[i] - maxLogit);
        sumExp += probs[i];
      }
      for (int i = 0; i < probs.length; i++) {
        probs[i] /= sumExp;
      }
    }

    double maxProb = -1.0;
    int maxIdx = -1;

    for (int i = 0; i < probs.length; i++) {
      if (probs[i] > maxProb) {
        maxProb = probs[i];
        maxIdx = i;
      }
    }

    if (maxIdx == -1) return null;

    String emotionRaw = _labels[maxIdx];

    // Map AffectNet/FER2013 to our App Emotions
    String mappedEmotion = 'Neutral';
    if (emotionRaw == 'Anger' || emotionRaw == 'Disgust') {
      mappedEmotion = 'Stressed';
    } else if (emotionRaw == 'Fear') {
      mappedEmotion = 'Anxious';
    } else if (emotionRaw == 'Happy') {
      mappedEmotion = 'Happy';
    } else if (emotionRaw == 'Sad') {
      mappedEmotion = 'Sad';
    } else if (emotionRaw == 'Surprise') {
      mappedEmotion = 'Neutral'; 
    } else {
      mappedEmotion = 'Neutral';
    }

    return {
      'emotion': mappedEmotion,
      'raw': emotionRaw,
      'confidence': (maxProb * 100).toInt()
    };
  }
}

// Background isolate task
Float32List? _analyzeFileIsolate(Map<String, dynamic> params) {
  try {
    final imagePath = params['imagePath'] as String;
    final bbox = params['bbox'] as Rect;

    final bytes = File(imagePath).readAsBytesSync();
    img.Image? decodedImage = img.decodeImage(bytes);

    if (decodedImage == null) return null;

    // Fix orientation based on EXIF to match ML Kit's upright bounding box
    decodedImage = img.bakeOrientation(decodedImage);

    // Crop the face. Clamp the bbox to prevent out of bounds
    int x1 = bbox.left.toInt().clamp(0, decodedImage.width);
    int y1 = bbox.top.toInt().clamp(0, decodedImage.height);
    int x2 = bbox.right.toInt().clamp(0, decodedImage.width);
    int y2 = bbox.bottom.toInt().clamp(0, decodedImage.height);
    
    int w = x2 - x1;
    int h = y2 - y1;
    
    if (w <= 0 || h <= 0) return null;

    img.Image croppedImage = img.copyCrop(decodedImage, x: x1, y: y1, width: w, height: h);
    
    // Resize to 48x48
    img.Image resizedImage = img.copyResize(croppedImage, width: 48, height: 48);
    
    Float32List grayscaleData = Float32List(1 * 48 * 48 * 1);
    int bufferIndex = 0;

    for (var y = 0; y < 48; y++) {
      for (var x = 0; x < 48; x++) {
        final pixel = resizedImage.getPixel(x, y);
        
        // Standard Grayscale conversion
        double l = pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114;
        
        // Normalized [0, 1]
        grayscaleData[bufferIndex++] = l / 255.0;
      }
    }
    return grayscaleData;

  } catch (e) {
    return null;
  }
}
