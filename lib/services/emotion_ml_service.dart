import 'dart:developer';
import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
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
      _interpreter = await Interpreter.fromAsset('assets/models/mobilenet_7.tflite', options: options);
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

  Future<Map<String, dynamic>?> processFrame(
      CameraImage image, Face face, int sensorOrientation, CameraLensDirection lensDirection) async {
    if (!_isInitialized || _interpreter == null) return null;

    final result = await compute(_analyzeImageIsolate, {
      'image': _ImageInput(
        planes: image.planes.map((p) => _PlaneInput(bytes: p.bytes, bytesPerRow: p.bytesPerRow, bytesPerPixel: p.bytesPerPixel)).toList(),
        width: image.width,
        height: image.height,
        formatGroup: image.format.group,
      ),
      'bbox': face.boundingBox,
      'orientation': sensorOrientation,
      'lensDirection': lensDirection,
    });

    if (result == null) return null;

    final inputShape = _interpreter!.getInputTensor(0).shape;
    final inputType = _interpreter!.getInputTensor(0).type;
    
    dynamic rawInput;
    if (inputType == TensorType.uint8) {
      var uint8Data = Uint8List(result.length);
      for (int i = 0; i < result.length; i++) {
         // Assuming result originated from (r-mean)/std, map it back loosely, 
         // But let's just do a robust denormalization
         uint8Data[i] = ((result[i] * 0.225 + 0.450) * 255).clamp(0, 255).toInt();
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

    // Map AffectNet to our App Emotions
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

class _PlaneInput {
  final Uint8List bytes;
  final int bytesPerRow;
  final int? bytesPerPixel;
  _PlaneInput({required this.bytes, required this.bytesPerRow, this.bytesPerPixel});
}

class _ImageInput {
  final List<_PlaneInput> planes;
  final int width;
  final int height;
  final ImageFormatGroup formatGroup;
  _ImageInput({required this.planes, required this.width, required this.height, required this.formatGroup});
}

// Background isolate text 
Float32List? _analyzeImageIsolate(Map<String, dynamic> params) {
  try {
    final imageInput = params['image'] as _ImageInput;
    final bbox = params['bbox'] as Rect;
    final orientation = params['orientation'] as int;
    final lensDirection = params['lensDirection'] as CameraLensDirection;

    img.Image? decodedImage;

    if (imageInput.formatGroup == ImageFormatGroup.yuv420) {
      decodedImage = _convertYUV420ToImage(imageInput);
    } else if (imageInput.formatGroup == ImageFormatGroup.bgra8888) {
      decodedImage = _convertBGRA8888ToImage(imageInput);
    } else {
      return null;
    }

    if (decodedImage == null) return null;

    // Handle rotation and mirroring
    if (Platform.isAndroid) {
      decodedImage = img.copyRotate(decodedImage, angle: orientation);
    } else if (Platform.isIOS) {
      // iOS gives image upright already if correctly handled, but let's be safe
      // Adjust if necessary
    }
    
    // Removed flipHorizontal because MLKit bounding box is based on the un-flipped rotated image!
    // Flipping it beforehand causes the crop to extract the wrong side of the image (often just background).    // Now, crop the face. We need to clamp the bbox to prevent out of bounds
    int x1 = bbox.left.toInt().clamp(0, decodedImage.width);
    int y1 = bbox.top.toInt().clamp(0, decodedImage.height);
    int x2 = bbox.right.toInt().clamp(0, decodedImage.width);
    int y2 = bbox.bottom.toInt().clamp(0, decodedImage.height);
    
    int w = x2 - x1;
    int h = y2 - y1;
    
    if (w <= 0 || h <= 0) return null;

    img.Image croppedImage = img.copyCrop(decodedImage, x: x1, y: y1, width: w, height: h);
    
    // Resize to 224x224
    img.Image resizedImage = img.copyResize(croppedImage, width: 224, height: 224);

    // Keras typically normalizes with either / 255.0 or specific mean/std
    // MobilenetV2 default keras preprocessing is: (x / 127.5) - 1.0 (range [-1, 1])
    // HSEmotion often uses std imagenet `[0.485, 0.456, 0.406]`, `[0.229, 0.224, 0.225]`
    // Or just [0, 1] normalization. PyTorch models expect (x/255.0 - mean)/std
    
    Float32List rgbData = Float32List(1 * 224 * 224 * 3);
    int bufferIndex = 0;

    for (var y = 0; y < 224; y++) {
      for (var x = 0; x < 224; x++) {
        final pixel = resizedImage.getPixel(x, y);
        
        // Standard MobileNet / Teachable-Machine Normalization [-1, 1]
        double r = (pixel.r / 127.5) - 1.0;
        double g = (pixel.g / 127.5) - 1.0;
        double b = (pixel.b / 127.5) - 1.0;

        rgbData[bufferIndex++] = r;
        rgbData[bufferIndex++] = g;
        rgbData[bufferIndex++] = b;
      }
    }
    return rgbData;

  } catch (e) {
    return null;
  }
}

img.Image? _convertYUV420ToImage(_ImageInput image) {
  try {
    final int width = image.width;
    final int height = image.height;
    final img.Image result = img.Image(width: width, height: height, numChannels: 3);

    final Uint8List yPlane = image.planes[0].bytes;
    final Uint8List uPlane = image.planes[1].bytes;
    final Uint8List vPlane = image.planes[2].bytes;

    final int yRowStride = image.planes[0].bytesPerRow;
    final int uvRowStride = image.planes[1].bytesPerRow;
    final int uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int uvIndex = uvPixelStride * (x / 2).floor() + uvRowStride * (y / 2).floor();
        final int index = y * yRowStride + x;

        final yp = yPlane[index];
        final up = uPlane[uvIndex];
        final vp = vPlane[uvIndex];

        int r = (yp + vp * 1436 / 1024 - 179).round().clamp(0, 255);
        int g = (yp - up * 46549 / 131072 + 44 - vp * 93604 / 131072 + 91).round().clamp(0, 255);
        int b = (yp + up * 1814 / 1024 - 227).round().clamp(0, 255);

        result.setPixelRgb(x, y, r, g, b);
      }
    }
    return result;
  } catch (e) {
    return null;
  }
}

img.Image? _convertBGRA8888ToImage(_ImageInput image) {
  try {
    return img.Image.fromBytes(
        width: image.width,
        height: image.height,
        bytes: image.planes[0].bytes.buffer,
        order: img.ChannelOrder.bgra);
  } catch (e) {
    return null;
  }
}
