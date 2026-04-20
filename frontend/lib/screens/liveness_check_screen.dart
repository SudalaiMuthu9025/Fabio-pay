/// Fabio — Liveness Check Screen (Simon Says)
///
/// Randomly selects 2 actions from: SMIRK, SMILE, BLINK.
/// Displays them one at a time as "Simon says… [ACTION]".
/// Uses google_mlkit_face_detection with classifications to detect each action.
/// After all steps pass, captures a still frame and sends to backend for
/// face verification against the stored embedding.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../config/theme.dart';
import '../services/api_service.dart';

enum SimonAction { smile, blink, smirk }

class LivenessCheckScreen extends ConsumerStatefulWidget {
  const LivenessCheckScreen({super.key});

  @override
  ConsumerState<LivenessCheckScreen> createState() =>
      _LivenessCheckScreenState();
}

class _LivenessCheckScreenState extends ConsumerState<LivenessCheckScreen>
    with TickerProviderStateMixin {
  CameraController? _cameraController;
  late FaceDetector _faceDetector;
  bool _isCameraReady = false;

  // Simon Says state
  late List<SimonAction> _actions;
  int _currentStep = 0;
  bool _actionDetected = false;
  bool _allStepsPassed = false;
  bool _isVerifying = false;
  bool _verificationComplete = false;
  bool _verificationSuccess = false;
  String _statusMessage = 'Preparing...';
  String? _errorMessage;

  // Timer for each action (5 seconds)
  Timer? _actionTimer;
  int _timeRemaining = 5;

  // Animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  static const _actionLabels = {
    SimonAction.smile: 'SMILE 😄',
    SimonAction.blink: 'BLINK 😑',
    SimonAction.smirk: 'SMIRK 😏',
  };

  @override
  void initState() {
    super.initState();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        performanceMode: FaceDetectorMode.fast,
      ),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Randomly pick 2 actions
    final allActions = List<SimonAction>.from(SimonAction.values);
    allActions.shuffle(Random());
    _actions = allActions.take(2).toList();

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
      setState(() {
        _isCameraReady = true;
        _statusMessage = 'Get ready...';
      });

      // Start with a brief delay
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      _startCurrentAction();
    } catch (e) {
      setState(() => _errorMessage = 'Camera initialization failed');
    }
  }

  void _startCurrentAction() {
    if (_currentStep >= _actions.length) {
      // All Simon Says steps passed — capture frame for face verification
      _captureAndVerifyFace();
      return;
    }

    setState(() {
      _actionDetected = false;
      _timeRemaining = 5;
      _statusMessage =
          'Simon says… ${_actionLabels[_actions[_currentStep]]}';
    });

    // Start countdown timer
    _actionTimer?.cancel();
    _actionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _timeRemaining--);
      if (_timeRemaining <= 0) {
        timer.cancel();
        _onActionTimeout();
      }
    });

    // Start detection stream
    _startDetectionStream();
  }

  void _startDetectionStream() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    _cameraController!.startImageStream((image) async {
      if (_actionDetected || _allStepsPassed || _isVerifying) return;

      final inputImage = _convertCameraImage(image);
      if (inputImage == null) return;

      try {
        final faces = await _faceDetector.processImage(inputImage);
        if (!mounted || faces.isEmpty) return;

        final face = faces.first;
        final detected = _checkAction(face, _actions[_currentStep]);

        if (detected) {
          _actionDetected = true;
          _actionTimer?.cancel();

          // Stop stream
          await _cameraController!.stopImageStream();

          if (!mounted) return;
          setState(() {
            _statusMessage = 'Action detected! ✓';
          });

          // Brief pause then move to next step
          await Future.delayed(const Duration(milliseconds: 800));
          if (!mounted) return;

          _currentStep++;
          if (_currentStep >= _actions.length) {
            setState(() => _allStepsPassed = true);
            _captureAndVerifyFace();
          } else {
            _startCurrentAction();
          }
        }
      } catch (_) {}
    });
  }

  bool _checkAction(Face face, SimonAction action) {
    final smiling = face.smilingProbability ?? 0.0;
    final leftEyeOpen = face.leftEyeOpenProbability ?? 1.0;
    final rightEyeOpen = face.rightEyeOpenProbability ?? 1.0;

    switch (action) {
      case SimonAction.smile:
        return smiling > 0.75;
      case SimonAction.blink:
        return leftEyeOpen < 0.2 && rightEyeOpen < 0.2;
      case SimonAction.smirk:
        return smiling > 0.35 && smiling < 0.65;
    }
  }

  void _onActionTimeout() {
    // Liveness failed — action not detected in time
    try {
      _cameraController?.stopImageStream();
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _errorMessage = 'Action not detected in time. Verification failed.';
      _verificationComplete = true;
      _verificationSuccess = false;
    });

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) Navigator.pop(context, false);
    });
  }

  Future<void> _captureAndVerifyFace() async {
    setState(() {
      _isVerifying = true;
      _statusMessage = 'Verifying your identity...';
    });

    try {
      // Stop stream if running
      try {
        await _cameraController!.stopImageStream();
      } catch (_) {}

      // Capture still frame
      final xFile = await _cameraController!.takePicture();
      final bytes = await xFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      // Send to backend for face verification
      final result = await ApiService.verifyFace(base64Image);

      if (!mounted) return;

      if (result['verified'] == true) {
        setState(() {
          _verificationComplete = true;
          _verificationSuccess = true;
          _statusMessage = 'Verification successful! ✓';
        });

        await Future.delayed(const Duration(seconds: 1));
        if (mounted) Navigator.pop(context, true);
      } else {
        setState(() {
          _verificationComplete = true;
          _verificationSuccess = false;
          _errorMessage = result['message'] ?? 'Face does not match.';
        });

        await Future.delayed(const Duration(seconds: 2));
        if (mounted) Navigator.pop(context, false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _verificationComplete = true;
        _verificationSuccess = false;
        _errorMessage = 'Face verification failed. Please try again.';
      });

      await Future.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.pop(context, false);
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

  @override
  void dispose() {
    _actionTimer?.cancel();
    _cameraController?.dispose();
    _faceDetector.close();
    _pulseController.dispose();
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
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context, false),
                          icon: const Icon(Icons.close_rounded,
                              color: Colors.white),
                        ),
                        Text('Liveness Check',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(width: 48),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Progress indicator
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_actions.length, (i) {
                        Color dotColor;
                        if (i < _currentStep) {
                          dotColor = AppTheme.success;
                        } else if (i == _currentStep && !_allStepsPassed) {
                          dotColor = AppTheme.accent;
                        } else {
                          dotColor = AppTheme.textSecondary.withOpacity(0.3);
                        }
                        return Container(
                          width: 12,
                          height: 12,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: dotColor,
                            shape: BoxShape.circle,
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _allStepsPassed
                          ? 'Verifying face...'
                          : 'Step ${_currentStep + 1} of ${_actions.length}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),

              // Camera preview with oval overlay
              Expanded(
                child: _isCameraReady
                    ? Stack(
                        alignment: Alignment.center,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: AspectRatio(
                              aspectRatio: 3 / 4,
                              child: CameraPreview(_cameraController!),
                            ),
                          ),

                          // Oval guide
                          ScaleTransition(
                            scale: _pulseAnimation,
                            child: CustomPaint(
                              size: Size(
                                MediaQuery.of(context).size.width * 0.85,
                                MediaQuery.of(context).size.width * 0.85 * 4 / 3,
                              ),
                              painter: _OvalGuidePainter(
                                color: _verificationComplete
                                    ? (_verificationSuccess
                                        ? AppTheme.success
                                        : AppTheme.error)
                                    : (_actionDetected
                                        ? AppTheme.success
                                        : AppTheme.accent),
                              ),
                            ),
                          ),

                          // Timer badge
                          if (!_allStepsPassed && !_verificationComplete)
                            Positioned(
                              top: 16,
                              right: 16,
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: _timeRemaining <= 2
                                      ? AppTheme.error.withOpacity(0.8)
                                      : Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '$_timeRemaining',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),

                          // Result overlay
                          if (_verificationComplete)
                            Container(
                              decoration: BoxDecoration(
                                color: (_verificationSuccess
                                        ? AppTheme.success
                                        : AppTheme.error)
                                    .withOpacity(0.3),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Center(
                                child: Icon(
                                  _verificationSuccess
                                      ? Icons.check_circle_rounded
                                      : Icons.cancel_rounded,
                                  color: _verificationSuccess
                                      ? AppTheme.success
                                      : AppTheme.error,
                                  size: 80,
                                ),
                              ),
                            ),
                        ],
                      )
                    : const Center(
                        child: CircularProgressIndicator(color: AppTheme.accent),
                      ),
              ),

              // Status & action prompt
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    // Simon Says prompt
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.primary.withOpacity(0.3),
                            AppTheme.accent.withOpacity(0.15),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppTheme.accent.withOpacity(0.3),
                        ),
                      ),
                      child: Column(
                        children: [
                          if (_isVerifying)
                            const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.accent,
                              ),
                            ),
                          const SizedBox(height: 8),
                          Text(
                            _statusMessage,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),

                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: AppTheme.error, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OvalGuidePainter extends CustomPainter {
  final Color color;

  _OvalGuidePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final center = Offset(size.width / 2, size.height / 2);
    final ovalRect = Rect.fromCenter(
      center: center,
      width: size.width * 0.6,
      height: size.height * 0.55,
    );

    canvas.drawOval(ovalRect, paint);
  }

  @override
  bool shouldRepaint(covariant _OvalGuidePainter oldDelegate) =>
      oldDelegate.color != color;
}
