/// Fabio — Face Capture Screen
///
/// Step 2: Capture face via camera, detect face with ML Kit,
/// send base64 image to backend for embedding storage.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../config/theme.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/fab_button.dart';

class FaceCaptureScreen extends ConsumerStatefulWidget {
  const FaceCaptureScreen({super.key});

  @override
  ConsumerState<FaceCaptureScreen> createState() => _FaceCaptureScreenState();
}

class _FaceCaptureScreenState extends ConsumerState<FaceCaptureScreen> {
  CameraController? _cameraController;
  late FaceDetector _faceDetector;
  bool _isCameraReady = false;
  bool _faceDetected = false;
  bool _isCapturing = false;
  bool _isUploading = false;
  String? _errorMessage;
  String _statusMessage = 'Position your face in the oval';

  @override
  void initState() {
    super.initState();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        performanceMode: FaceDetectorMode.fast,
      ),
    );
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final frontCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();
      if (!mounted) return;
      setState(() => _isCameraReady = true);

      // Start face detection stream
      _startFaceDetection();
    } catch (e) {
      setState(() => _errorMessage = 'Camera initialization failed: $e');
    }
  }

  void _startFaceDetection() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    _cameraController!.startImageStream((image) async {
      if (_isCapturing || _isUploading) return;

      final inputImage = _convertCameraImage(image);
      if (inputImage == null) return;

      try {
        final faces = await _faceDetector.processImage(inputImage);
        if (!mounted) return;

        setState(() {
          _faceDetected = faces.isNotEmpty;
          _statusMessage = _faceDetected
              ? 'Face detected! Tap capture when ready.'
              : 'Position your face in the oval';
        });
      } catch (_) {}
    });
  }

  InputImage? _convertCameraImage(CameraImage image) {
    try {
      final camera = _cameraController!.description;
      final rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation);
      if (rotation == null) return null;

      final format = InputImageFormatValue.fromRawValue(image.format.raw);
      if (format == null) return null;

      return InputImage.fromBytes(
        bytes: image.planes.first.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _captureAndUpload() async {
    if (!_faceDetected || _isUploading) return;

    setState(() {
      _isCapturing = true;
      _isUploading = true;
      _errorMessage = null;
      _statusMessage = 'Capturing...';
    });

    try {
      // Stop the stream before capturing
      await _cameraController!.stopImageStream();
      final xFile = await _cameraController!.takePicture();
      final rawBytes = await xFile.readAsBytes();

      setState(() => _statusMessage = 'Processing image...');

      // Compress image to reduce payload size (critical for Railway upload)
      final original = img.decodeImage(rawBytes);
      Uint8List finalBytes;
      if (original != null) {
        // Resize to max 480px wide + JPEG compress to 70% quality
        final resized = original.width > 480
            ? img.copyResize(original, width: 480)
            : original;
        finalBytes = Uint8List.fromList(img.encodeJpg(resized, quality: 70));
      } else {
        finalBytes = rawBytes;
      }
      final base64Image = base64Encode(finalBytes);

      setState(() => _statusMessage = 'Uploading face data...');

      final result = await ApiService.registerFace(base64Image);

      if (result['success'] == true) {
        await AuthService.setFaceRegistered(true);
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Face registered successfully!'),
            backgroundColor: AppTheme.success,
          ),
        );
        Navigator.pushReplacementNamed(context, '/bank-setup');
      } else {
        setState(() {
          _errorMessage = result['message'] ?? 'Face registration failed';
          _statusMessage = 'Try again';
          _isCapturing = false;
          _isUploading = false;
        });
        _startFaceDetection();
      }
    } on DioException catch (e) {
      // 409 = face already registered — treat as success
      if (e.response?.statusCode == 409) {
        await AuthService.setFaceRegistered(true);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Face already registered!'),
            backgroundColor: AppTheme.success,
          ),
        );
        Navigator.pushReplacementNamed(context, '/bank-setup');
        return;
      }
      setState(() {
        final data = e.response?.data;
        final detail = data is Map ? (data['detail'] ?? data['message']) : null;
        _errorMessage = detail?.toString() ?? 'Server error (${e.response?.statusCode ?? "timeout"}): ${e.message}';
        _statusMessage = 'Try again';
        _isCapturing = false;
        _isUploading = false;
      });
      _startFaceDetection();
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
        _statusMessage = 'Try again';
        _isCapturing = false;
        _isUploading = false;
      });
      _startFaceDetection();
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text('Capture Your Face',
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 4),
                    Text('Step 2 of 4 — Face Registration',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppTheme.accent,
                            )),
                  ],
                ),
              ),

              // Camera preview with oval overlay
              Expanded(
                child: _isCameraReady
                    ? Stack(
                        alignment: Alignment.center,
                        children: [
                          // Camera preview
                          ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: AspectRatio(
                              aspectRatio: 3 / 4,
                              child: CameraPreview(_cameraController!),
                            ),
                          ),

                          // Oval guide overlay
                          CustomPaint(
                            size: Size(
                              MediaQuery.of(context).size.width * 0.85,
                              MediaQuery.of(context).size.width * 0.85 * 4 / 3,
                            ),
                            painter: _OvalOverlayPainter(
                              faceDetected: _faceDetected,
                            ),
                          ),

                          // Status text
                          Positioned(
                            bottom: 16,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _faceDetected
                                        ? Icons.check_circle
                                        : Icons.face_retouching_natural,
                                    color: _faceDetected
                                        ? AppTheme.success
                                        : AppTheme.accent,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(_statusMessage,
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 14)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : const Center(
                        child: CircularProgressIndicator(color: AppTheme.accent),
                      ),
              ),

              // Error message
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Text(_errorMessage!,
                      style: const TextStyle(color: AppTheme.error, fontSize: 13),
                      textAlign: TextAlign.center),
                ),

              // Capture button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: FabButton(
                  label: 'Capture Face',
                  onPressed: _faceDetected && !_isUploading ? _captureAndUpload : null,
                  isLoading: _isUploading,
                  icon: Icons.camera_alt_rounded,
                ),
              ),

              // Skip button
              Padding(
                padding: const EdgeInsets.only(left: 24, right: 24, bottom: 24),
                child: TextButton(
                  onPressed: _isUploading ? null : () {
                    Navigator.pushReplacementNamed(context, '/bank-setup');
                  },
                  child: const Text(
                    'Skip for now →',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OvalOverlayPainter extends CustomPainter {
  final bool faceDetected;

  _OvalOverlayPainter({required this.faceDetected});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = faceDetected
          ? AppTheme.success.withValues(alpha: 0.8)
          : AppTheme.accent.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final center = Offset(size.width / 2, size.height / 2);
    final ovalRect = Rect.fromCenter(
      center: center,
      width: size.width * 0.6,
      height: size.height * 0.55,
    );

    canvas.drawOval(ovalRect, paint);

    // Corner markers
    final markerPaint = Paint()
      ..color = faceDetected ? AppTheme.success : AppTheme.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    final markerLen = 20.0;
    // Top-left
    canvas.drawLine(
        Offset(ovalRect.left + 20, ovalRect.top),
        Offset(ovalRect.left + 20 + markerLen, ovalRect.top), markerPaint);
    canvas.drawLine(
        Offset(ovalRect.left + 10, ovalRect.top + 10),
        Offset(ovalRect.left + 10, ovalRect.top + 10 + markerLen), markerPaint);
    // Top-right
    canvas.drawLine(
        Offset(ovalRect.right - 20 - markerLen, ovalRect.top),
        Offset(ovalRect.right - 20, ovalRect.top), markerPaint);
    canvas.drawLine(
        Offset(ovalRect.right - 10, ovalRect.top + 10),
        Offset(ovalRect.right - 10, ovalRect.top + 10 + markerLen), markerPaint);
    // Bottom-left
    canvas.drawLine(
        Offset(ovalRect.left + 20, ovalRect.bottom),
        Offset(ovalRect.left + 20 + markerLen, ovalRect.bottom), markerPaint);
    canvas.drawLine(
        Offset(ovalRect.left + 10, ovalRect.bottom - 10 - markerLen),
        Offset(ovalRect.left + 10, ovalRect.bottom - 10), markerPaint);
    // Bottom-right
    canvas.drawLine(
        Offset(ovalRect.right - 20 - markerLen, ovalRect.bottom),
        Offset(ovalRect.right - 20, ovalRect.bottom), markerPaint);
    canvas.drawLine(
        Offset(ovalRect.right - 10, ovalRect.bottom - 10 - markerLen),
        Offset(ovalRect.right - 10, ovalRect.bottom - 10), markerPaint);
  }

  @override
  bool shouldRepaint(covariant _OvalOverlayPainter oldDelegate) =>
      oldDelegate.faceDetected != faceDetected;
}
