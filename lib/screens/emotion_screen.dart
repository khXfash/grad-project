import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../services/emotion_ml_service.dart';
import '../theme/app_theme.dart';

class EmotionScreen extends StatefulWidget {
  const EmotionScreen({super.key});

  @override
  State<EmotionScreen> createState() => _EmotionScreenState();
}

class _EmotionScreenState extends State<EmotionScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isCameraReady = false;
  int _cameraIndex = 0;

  final EmotionMlService _mlService = EmotionMlService();
  late final FaceDetector _faceDetector;

  bool _isAnalyzing = false;
  bool _isBusy = false;
  String? _result;
  String? _confidence;
  Rect? _faceRect;

  static const _emotions = [
    ('Calm', '😌', AppColors.stressLow),
    ('Happy', '😊', Color(0xFF66BB6A)),
    ('Neutral', '😐', AppColors.secondary),
    ('Anxious', '😰', AppColors.stressMedium),
    ('Sad', '😢', Color(0xFF42A5F5)),
    ('Stressed', '😤', AppColors.stressHigh),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableContours: false,
        enableClassification: false,
      ),
    );
    _initMlService();
    _initCamera();
  }

  Future<void> _initMlService() async {
    await _mlService.initialize();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;
      // Prefer front camera
      for (int i = 0; i < _cameras.length; i++) {
        if (_cameras[i].lensDirection == CameraLensDirection.front) {
          _cameraIndex = i;
          break;
        }
      }
      await _startCamera(_cameraIndex);
    } catch (_) {}
  }

  Future<void> _startCamera(int index) async {
    await _controller?.dispose();
    _controller = CameraController(
      _cameras[index],
      ResolutionPreset.low, // Lower resolution for faster processing
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.yuv420
          : ImageFormatGroup.bgra8888,
    );
    try {
      await _controller!.initialize();
      if (mounted) {
        setState(() => _isCameraReady = true);
        if (_isAnalyzing) {
          _startImageStream();
        }
      }
    } catch (_) {}
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    bool wasAnalyzing = _isAnalyzing;
    _stopAnalysis();
    setState(() => _isCameraReady = false);
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _startCamera(_cameraIndex);
    if (wasAnalyzing) {
       _toggleAnalysis(); // Resume parsing
    }
  }

  void _toggleAnalysis() {
    if (!_isCameraReady) return;
    if (_isAnalyzing) {
      _stopAnalysis();
    } else {
      setState(() {
        _isAnalyzing = true;
      });
      _startImageStream();
    }
  }

  void _stopAnalysis() {
    _controller?.stopImageStream();
    setState(() {
      _isAnalyzing = false;
      _isBusy = false;
      _faceRect = null;
    });
  }

  void _startImageStream() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    _controller!.startImageStream((CameraImage image) {
      _processCameraImage(image);
    });
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isBusy || !_isAnalyzing) return;
    _isBusy = true;

    try {
      final inputImage = _createInputImage(image);
      if (inputImage == null) {
        _isBusy = false;
        return;
      }

      final faces = await _faceDetector.processImage(inputImage);
      if (faces.isEmpty) {
        if (mounted) {
          setState(() {
            _faceRect = null;
          });
        }
        _isBusy = false;
        return;
      }

      // Pick the largest face
      final face = faces.reduce((a, b) => a.boundingBox.width > b.boundingBox.width ? a : b);
      
      if (mounted) {
        setState(() {
          _faceRect = face.boundingBox;
        });
      }

      // Process emotion via TFLite
      final cameraDesc = _cameras[_cameraIndex];
      final res = await _mlService.processFrame(
        image, 
        face, 
        cameraDesc.sensorOrientation,
        cameraDesc.lensDirection
      );

      if (res != null && mounted) {
        final emotion = res['emotion'];
        final conf = res['confidence'];
        context.read<AppProvider>().setDetectedEmotion(emotion);
        
        setState(() {
          _result = emotion;
          _confidence = "$conf%";
        });
      }

    } catch (e) {
      debugPrint("Error processing image: $e");
    } finally {
      if (mounted) {
        _isBusy = false;
      }
    }
  }

  InputImage? _createInputImage(CameraImage image) {
    InputImageRotation rotation;
    final sensorOrientation = _cameras[_cameraIndex].sensorOrientation;
    
    switch (sensorOrientation) {
      case 0:
        rotation = InputImageRotation.rotation0deg;
        break;
      case 90:
        rotation = InputImageRotation.rotation90deg;
        break;
      case 180:
        rotation = InputImageRotation.rotation180deg;
        break;
      case 270:
        rotation = InputImageRotation.rotation270deg;
        break;
      default:
        rotation = InputImageRotation.rotation0deg;
    }
    
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    final format = Platform.isAndroid ? InputImageFormat.nv21 : InputImageFormat.bgra8888;
    
    final metadata = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: image.planes[0].bytesPerRow,
    );
    
    return InputImage.fromBytes(bytes: bytes, metadata: metadata);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _stopAnalysis();
      _controller?.dispose();
      setState(() => _isCameraReady = false);
    } else if (state == AppLifecycleState.resumed) {
      _startCamera(_cameraIndex);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopAnalysis();
    _controller?.dispose();
    _faceDetector.close();
    _mlService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.onSurface,
      body: SafeArea(
        child: Column(
          children: [
            // ── App bar ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
              child: Row(
                children: [
                  Text(
                    'Emotion Detection',
                    style: GoogleFonts.manrope(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  if (_cameras.length > 1)
                    IconButton(
                      onPressed: _switchCamera,
                      icon: const Icon(
                        Icons.flip_camera_ios_rounded,
                        color: Colors.white,
                      ),
                    ),
                ],
              ),
            ),

            // ── Camera preview ───────────────────────────────────────────
            Expanded(
              child: Stack(
                children: [
                  // Camera view
                  _isCameraReady && _controller != null
                      ? Positioned.fill(
                          child: _CameraPreviewWidget(controller: _controller!),
                        )
                      : Container(
                          color: const Color(0xFF1A1A2E),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.camera_alt_outlined,
                                  color: Colors.white38,
                                  size: 64,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _cameras.isEmpty
                                      ? 'No camera available'
                                      : 'Loading camera...',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: Colors.white54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                  // Bounding Box overlay
                  if (_isAnalyzing && _faceRect != null && _controller != null)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _FaceRectPainter(
                          _faceRect!,
                          _controller!.value.previewSize!,
                          _cameras[_cameraIndex].sensorOrientation,
                          _cameras[_cameraIndex].lensDirection,
                        ),
                      ),
                    ),

                  // Face guide overlay
                  if (_isCameraReady && !_isAnalyzing)
                    Center(
                      child: CustomPaint(
                        painter: _FaceGuidePainter(),
                        size: const Size(220, 270),
                      ),
                    ),

                  // Result badge
                  if (_result != null && _isAnalyzing)
                    Positioned(
                      top: 16,
                      left: 0,
                      right: 0,
                      child: Center(child: _buildResultBadge()),
                    ),
                ],
              ),
            ),

            // ── Bottom panel ─────────────────────────────────────────────
            Container(
              color: AppColors.surface,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_result != null) ...[
                    _buildEmotionDetails(),
                    const SizedBox(height: 16),
                  ],
                  FilledButton.icon(
                    onPressed: _isCameraReady ? _toggleAnalysis : null,
                    icon: Icon(_isAnalyzing ? Icons.stop_rounded : Icons.face_retouching_natural_rounded),
                    label: Text(
                      _isAnalyzing ? 'Stop Analysis' : 'Start Live Detection',
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: _isAnalyzing ? AppColors.error : AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Position your face within the camera view',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultBadge() {
    final emotion = _emotions.firstWhere(
      (e) => e.$1 == _result,
      orElse: () => _emotions[0],
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: emotion.$3.withAlpha(220),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: emotion.$3.withAlpha(100),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emotion.$2, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 8),
          Text(
            emotion.$1,
            style: GoogleFonts.manrope(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmotionDetails() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.psychology_alt_rounded,
            color: AppColors.primary,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Detected: $_result',
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
                Text(
                  'Confidence: $_confidence',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraPreviewWidget extends StatelessWidget {
  final CameraController controller;
  const _CameraPreviewWidget({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: OverflowBox(
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: controller.value.previewSize?.height ?? 1,
            height: controller.value.previewSize?.width ?? 1,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }
}

// ── Face bounding box painter ────────────────────────────────────────────────
class _FaceRectPainter extends CustomPainter {
  final Rect absoluteRect;
  final Size previewSize;
  final int orientation;
  final CameraLensDirection direction;

  _FaceRectPainter(this.absoluteRect, this.previewSize, this.orientation, this.direction);

  @override
  void paint(Canvas canvas, Size size) {
    // Coordinate translation logic from camera image to screen size 
    final double scaleX = size.width / (orientation == 90 || orientation == 270 ? previewSize.height : previewSize.width);
    final double scaleY = size.height / (orientation == 90 || orientation == 270 ? previewSize.width : previewSize.height);

    double left = absoluteRect.left * scaleX;
    double top = absoluteRect.top * scaleY;
    double right = absoluteRect.right * scaleX;
    double bottom = absoluteRect.bottom * scaleY;

    if (direction == CameraLensDirection.front) {
      final tmp = left;
      left = size.width - right;
      right = size.width - tmp;
    }

    final paint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    canvas.drawRect(Rect.fromLTRB(left, top, right, bottom), paint);
  }

  @override
  bool shouldRepaint(covariant _FaceRectPainter oldDelegate) => true;
}

// ── Face guide painter ───────────────────────────────────────────────────────
class _FaceGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white54
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawOval(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    final accentPaint = Paint()
      ..color = AppColors.primaryContainer
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final cx = size.width / 2;
    final cy = size.height / 2;
    const len = 20.0;

    for (final angle in [0.0, pi / 2, pi, 3 * pi / 2]) {
      final x = cx + cos(angle) * cx;
      final y = cy + sin(angle) * cy;
      canvas.drawLine(
        Offset(x - cos(angle) * len, y - sin(angle) * len),
        Offset(x, y),
        accentPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
