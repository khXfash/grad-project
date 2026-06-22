import 'dart:async';

import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
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

  bool _isBusy = false;
  String? _result;
  String? _confidence;

  static const _emotions = [
    ('Neutral', '😐', AppColors.secondary),
    ('Anger', '😤', AppColors.stressHigh),
    ('Disgust', '🤢', AppColors.stressHigh),
    ('Fear', '😰', AppColors.stressMedium),
    ('Happy', '😊', Color(0xFF66BB6A)),
    ('Sad', '😢', Color(0xFF42A5F5)),
    ('Surprise', '😲', Color(0xFF9C27B0)),
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
      ResolutionPreset.medium,
      enableAudio: false,
    );
    try {
      await _controller!.initialize();
      if (mounted) {
        setState(() => _isCameraReady = true);
      }
    } catch (_) {}
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    setState(() => _isCameraReady = false);
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _startCamera(_cameraIndex);
  }

  Future<void> _takeSnapshot() async {
    if (!_isCameraReady || _controller == null || !_controller!.value.isInitialized) return;
    if (_isBusy) return;

    setState(() {
      _isBusy = true;
      _result = null;
      _confidence = null;
    });

    try {
      final XFile file = await _controller!.takePicture();
      final inputImage = InputImage.fromFilePath(file.path);
      
      final faces = await _faceDetector.processImage(inputImage);
      if (faces.isEmpty) {
        if (mounted) {
          setState(() {
            _result = "No face detected";
            _confidence = null;
          });
        }
        return;
      }

      // Pick the largest face
      final face = faces.reduce((a, b) => a.boundingBox.width > b.boundingBox.width ? a : b);

      // Process emotion via TFLite
      final res = await _mlService.processFile(file.path, face.boundingBox);

      if (res != null && mounted) {
        final emotion = res['raw'] as String;
        final conf = res['confidence'] as int;
        final provider = context.read<AppProvider>();
        provider.setDetectedEmotion(emotion);

        // Auto-log the mood — same pattern as sensor readings auto-saving
        provider.logMood(
          emotion: emotion,
          notes: '',
          source: 'camera',
          confidence: conf,
        );

        setState(() {
          _result = emotion;
          _confidence = "$conf%";
        });
      } else {
        if (mounted) {
          setState(() {
            _result = "Failed to analyze";
            _confidence = null;
          });
        }
      }

    } catch (e) {
      debugPrint("Error taking picture: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
      setState(() => _isCameraReady = false);
    } else if (state == AppLifecycleState.resumed) {
      _startCamera(_cameraIndex);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

                  // Face guide overlay
                  if (_isCameraReady)
                    Center(
                      child: CustomPaint(
                        painter: _FaceGuidePainter(),
                        size: const Size(220, 270),
                      ),
                    ),

                  // Loading indicator
                  if (_isBusy)
                    const Positioned.fill(
                      child: Center(
                        child: CircularProgressIndicator(color: AppColors.primary),
                      ),
                    ),

                  // Result badge
                  if (_result != null)
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
                    onPressed: _isCameraReady && !_isBusy ? _takeSnapshot : null,
                    icon: const Icon(Icons.camera_alt_rounded),
                    label: const Text('Take Snapshot'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: AppColors.primary,
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
