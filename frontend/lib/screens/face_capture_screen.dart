/// Fabio — Face Capture Screen
///
/// Step 2: Capture face via camera, detect face with ML Kit,
/// send base64 image to backend for embedding storage.
///
/// Resilience features:
///   • Auto-enables capture after 5 s even if ML Kit can't detect a face
///   • Compresses to 320 px / JPEG 50 % to keep payload small
///   • Retries upload up to 3 × with exponential backoff
///   • Shows detailed error messages for debugging

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
  FaceDetector? _faceDetector;
  bool _isCameraReady = false;
  bool _faceDetected = false;
  bool _isCapturing = false;
  bool _isUploading = false;
  String? _errorMessage;
  String _statusMessage = 'Position your face in the oval';

  /// If ML Kit never fires, we still let the user capture after this timeout.
  bool _manualCaptureEnabled = false;

  @override
  void initState() {
    super.initState();
    _initFaceDetector();
    _initCamera();
    // Fallback: enable manual capture after 5 seconds regardless of ML Kit
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && !_faceDetected) {
        setState(() {
          _manualCaptureEnabled = true;
          _statusMessage = 'Tap capture when ready';
        });
      }
    });
  }

  void _initFaceDetector() {
    try {
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableClassification: true,
          performanceMode: FaceDetectorMode.fast,
        ),
      );
    } catch (e) {
      debugPrint('ML Kit FaceDetector init failed: $e');
      // If ML Kit fails, just enable manual capture
      setState(() {
        _manualCaptureEnabled = true;
        _statusMessage = 'Tap capture when ready';
      });
    }
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

      // Start face detection stream (best-effort)
      _startFaceDetection();
    } catch (e) {
      debugPrint('Camera init error: $e');
      setState(() {
        _errorMessage = 'Camera initialization failed: $e';
        _manualCaptureEnabled = true;
      });
    }
  }

  void _startFaceDetection() {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _faceDetector == null) {
      return;
    }

    try {
      _cameraController!.startImageStream((image) async {
        if (_isCapturing || _isUploading) return;

        final inputImage = _convertCameraImage(image);
        if (inputImage == null) return;

        try {
          final faces = await _faceDetector!.processImage(inputImage);
          if (!mounted) return;

          setState(() {
            _faceDetected = faces.isNotEmpty;
            if (_faceDetected) {
              _statusMessage = 'Face detected! Tap capture when ready.';
              _manualCaptureEnabled = true;
            }
          });
        } catch (_) {}
      });
    } catch (e) {
      debugPrint('startImageStream failed: $e');
      // Enable manual capture as fallback
      if (mounted) {
        setState(() {
          _manualCaptureEnabled = true;
          _statusMessage = 'Tap capture when ready';
        });
      }
    }
  }

  InputImage? _convertCameraImage(CameraImage image) {
    try {
      final camera = _cameraController!.description;
      final rotation =
          InputImageRotationValue.fromRawValue(camera.sensorOrientation);
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

  /// Whether the capture button should be enabled
  bool get _canCapture =>
      (_faceDetected || _manualCaptureEnabled) && !_isUploading;

  Future<void> _captureAndUpload() async {
    if (!_canCapture) return;

    setState(() {
      _isCapturing = true;
      _isUploading = true;
      _errorMessage = null;
      _statusMessage = 'Capturing...';
    });

    try {
      // Stop the stream before capturing
      try {
        await _cameraController!.stopImageStream();
      } catch (_) {
        // Stream may not be running — that's fine
      }

      final xFile = await _cameraController!.takePicture();
      final rawBytes = await xFile.readAsBytes();

      setState(() => _statusMessage = 'Processing image...');

      // ── Aggressive compression (320 px wide, JPEG 50 %) ──────────────
      final original = img.decodeImage(rawBytes);
      Uint8List finalBytes;
      if (original != null) {
        final resized = original.width > 320
            ? img.copyResize(original, width: 320)
            : original;
        finalBytes = Uint8List.fromList(img.encodeJpg(resized, quality: 50));
      } else {
        finalBytes = rawBytes;
      }
      final base64Image = base64Encode(finalBytes);
      debugPrint('Face image payload: ${base64Image.length} chars '
          '(~${(base64Image.length / 1024).toStringAsFixed(1)} KB)');

      // ── Upload with retry ────────────────────────────────────────────
      await _uploadWithRetry(base64Image);
    } on DioException catch (e) {
      _handleDioError(e);
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
        _statusMessage = 'Try again';
        _isCapturing = false;
        _isUploading = false;
      });
      _restartDetection();
    }
  }

  Future<void> _uploadWithRetry(String base64Image) async {
    const maxAttempts = 3;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        setState(() {
          _statusMessage = attempt == 1
              ? 'Uploading face data...'
              : 'Retrying upload ($attempt/$maxAttempts)...';
        });

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
          return; // ← success, exit retry loop
        } else {
          // Backend returned success=false
          final msg = result['message'] ?? 'Face registration failed';
          if (attempt == maxAttempts) {
            setState(() {
              _errorMessage = msg;
              _statusMessage = 'Try again';
              _isCapturing = false;
              _isUploading = false;
            });
            _restartDetection();
          }
          // else: fall through to retry
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

        if (attempt == maxAttempts) {
          _handleDioError(e);
          return;
        }
      } catch (e) {
        if (attempt == maxAttempts) {
          setState(() {
            _errorMessage = 'Error after $maxAttempts attempts: $e';
            _statusMessage = 'Try again';
            _isCapturing = false;
            _isUploading = false;
          });
          _restartDetection();
          return;
        }
      }

      // Exponential backoff before next attempt
      if (attempt < maxAttempts) {
        final delay = Duration(seconds: attempt * 2);
        setState(() => _statusMessage = 'Waiting ${delay.inSeconds}s before retry...');
        await Future.delayed(delay);
      }
    }
  }

  void _handleDioError(DioException e) {
    final statusCode = e.response?.statusCode;
    final data = e.response?.data;
    final detail = data is Map ? (data['detail'] ?? data['message']) : null;

    String errorMsg;
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      errorMsg = 'Server timeout — the face engine may be starting up. '
          'Please wait 30 seconds and try again.';
    } else if (statusCode != null) {
      errorMsg = detail?.toString() ??
          'Server error ($statusCode). Please try again.';
    } else if (e.type == DioExceptionType.connectionError) {
      errorMsg = 'Cannot reach server. Check your internet connection.';
    } else {
      errorMsg = 'Network error: ${e.message}';
    }

    setState(() {
      _errorMessage = errorMsg;
      _statusMessage = 'Try again';
      _isCapturing = false;
      _isUploading = false;
    });
    _restartDetection();
  }

  void _restartDetection() {
    try {
      _startFaceDetection();
    } catch (_) {
      // Camera may be in a bad state — enable manual capture
      if (mounted) {
        setState(() => _manualCaptureEnabled = true);
      }
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceDetector?.close();
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
                                  if (_isUploading)
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppTheme.accent,
                                      ),
                                    )
                                  else
                                    Icon(
                                      _faceDetected
                                          ? Icons.check_circle
                                          : _manualCaptureEnabled
                                              ? Icons.camera_alt
                                              : Icons.face_retouching_natural,
                                      color: _faceDetected
                                          ? AppTheme.success
                                          : AppTheme.accent,
                                      size: 18,
                                    ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(_statusMessage,
                                        style: const TextStyle(
                                            color: Colors.white, fontSize: 14)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : const Center(
                        child:
                            CircularProgressIndicator(color: AppTheme.accent),
                      ),
              ),

              // Error message
              if (_errorMessage != null)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppTheme.error.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: AppTheme.error, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_errorMessage!,
                              style: const TextStyle(
                                  color: AppTheme.error, fontSize: 12),
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
                ),

              // Capture button
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: FabButton(
                  label: _isUploading ? 'Uploading...' : 'Capture Face',
                  onPressed: _canCapture ? _captureAndUpload : null,
                  isLoading: _isUploading,
                  icon: Icons.camera_alt_rounded,
                ),
              ),

              // Skip button
              Padding(
                padding:
                    const EdgeInsets.only(left: 24, right: 24, bottom: 24),
                child: TextButton(
                  onPressed: _isUploading
                      ? null
                      : () {
                          Navigator.pushReplacementNamed(
                              context, '/bank-setup');
                        },
                  child: const Text(
                    'Skip for now →',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 14),
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
    canvas.drawLine(Offset(ovalRect.left + 20, ovalRect.top),
        Offset(ovalRect.left + 20 + markerLen, ovalRect.top), markerPaint);
    canvas.drawLine(Offset(ovalRect.left + 10, ovalRect.top + 10),
        Offset(ovalRect.left + 10, ovalRect.top + 10 + markerLen), markerPaint);
    // Top-right
    canvas.drawLine(Offset(ovalRect.right - 20 - markerLen, ovalRect.top),
        Offset(ovalRect.right - 20, ovalRect.top), markerPaint);
    canvas.drawLine(Offset(ovalRect.right - 10, ovalRect.top + 10),
        Offset(ovalRect.right - 10, ovalRect.top + 10 + markerLen), markerPaint);
    // Bottom-left
    canvas.drawLine(Offset(ovalRect.left + 20, ovalRect.bottom),
        Offset(ovalRect.left + 20 + markerLen, ovalRect.bottom), markerPaint);
    canvas.drawLine(
        Offset(ovalRect.left + 10, ovalRect.bottom - 10 - markerLen),
        Offset(ovalRect.left + 10, ovalRect.bottom - 10), markerPaint);
    // Bottom-right
    canvas.drawLine(Offset(ovalRect.right - 20 - markerLen, ovalRect.bottom),
        Offset(ovalRect.right - 20, ovalRect.bottom), markerPaint);
    canvas.drawLine(
        Offset(ovalRect.right - 10, ovalRect.bottom - 10 - markerLen),
        Offset(ovalRect.right - 10, ovalRect.bottom - 10), markerPaint);
  }

  @override
  bool shouldRepaint(covariant _OvalOverlayPainter oldDelegate) =>
      oldDelegate.faceDetected != faceDetected;
}
