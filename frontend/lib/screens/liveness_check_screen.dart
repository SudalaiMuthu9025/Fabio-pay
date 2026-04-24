/// Fabio — Liveness Check Screen (Enhanced Simon Says)
///
/// Randomly selects 3 actions from: SMILE, BLINK, SMIRK, TURN LEFT, TURN RIGHT.
/// Displays them one at a time as "Simon says… [ACTION]".
/// Uses google_mlkit_face_detection with classifications + head pose to detect each action.
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

enum SimonAction { smile, blink, smirk, turnLeft, turnRight }

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
  bool _isProcessing = false;

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

  // Timer for each action (6 seconds)
  Timer? _actionTimer;
  int _timeRemaining = 6;

  // Animations
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _checkmarkController;
  late Animation<double> _checkmarkAnimation;

  static const _actionLabels = {
    SimonAction.smile: 'SMILE 😄',
    SimonAction.blink: 'BLINK 😑',
    SimonAction.smirk: 'SMIRK 😏',
    SimonAction.turnLeft: 'TURN LEFT ←',
    SimonAction.turnRight: 'TURN RIGHT →',
  };

  static const _actionIcons = {
    SimonAction.smile: Icons.sentiment_very_satisfied_rounded,
    SimonAction.blink: Icons.visibility_off_rounded,
    SimonAction.smirk: Icons.sentiment_neutral_rounded,
    SimonAction.turnLeft: Icons.turn_left_rounded,
    SimonAction.turnRight: Icons.turn_right_rounded,
  };

  // Predefined difficulty combos — ensures logical sequences
  static const _actionCombos = [
    [SimonAction.blink, SimonAction.smile, SimonAction.turnLeft],
    [SimonAction.smile, SimonAction.turnRight, SimonAction.blink],
    [SimonAction.turnLeft, SimonAction.blink, SimonAction.smirk],
    [SimonAction.smirk, SimonAction.turnLeft, SimonAction.smile],
    [SimonAction.blink, SimonAction.turnRight, SimonAction.smile],
    [SimonAction.turnRight, SimonAction.smirk, SimonAction.blink],
    [SimonAction.smile, SimonAction.blink, SimonAction.turnRight],
    [SimonAction.turnLeft, SimonAction.smile, SimonAction.turnRight],
    [SimonAction.blink, SimonAction.smirk, SimonAction.turnRight],
    [SimonAction.smirk, SimonAction.blink, SimonAction.turnLeft],
  ];

  @override
  void initState() {
    super.initState();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        enableTracking: true,
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

    _checkmarkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _checkmarkAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _checkmarkController, curve: Curves.elasticOut),
    );

    // Pick a random combo from predefined difficulty sets
    final combo = _actionCombos[Random().nextInt(_actionCombos.length)];
    _actions = List.from(combo);

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
      _captureAndVerifyFace();
      return;
    }

    setState(() {
      _actionDetected = false;
      _timeRemaining = 6;
      _statusMessage =
          'Simon says… ${_actionLabels[_actions[_currentStep]]}';
    });

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

    _startDetectionStream();
  }

  void _startDetectionStream() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    _cameraController!.startImageStream((image) async {
      if (_actionDetected || _allStepsPassed || _isVerifying || _isProcessing) {
        return;
      }

      _isProcessing = true;

      final inputImage = _convertCameraImage(image);
      if (inputImage == null) {
        _isProcessing = false;
        return;
      }

      try {
        final faces = await _faceDetector.processImage(inputImage);
        if (!mounted || faces.isEmpty) {
          _isProcessing = false;
          return;
        }

        final face = faces.first;
        final detected = _checkAction(face, _actions[_currentStep]);

        if (detected) {
          _actionDetected = true;
          _actionTimer?.cancel();

          await _cameraController!.stopImageStream();

          if (!mounted) return;
          _checkmarkController.forward(from: 0.0);
          setState(() {
            _statusMessage = 'Action detected! ✓';
          });

          await Future.delayed(const Duration(milliseconds: 900));
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

      _isProcessing = false;
    });
  }

  bool _checkAction(Face face, SimonAction action) {
    final smiling = face.smilingProbability ?? 0.0;
    final leftEyeOpen = face.leftEyeOpenProbability ?? 1.0;
    final rightEyeOpen = face.rightEyeOpenProbability ?? 1.0;
    final headEulerY = face.headEulerAngleY ?? 0.0; // Left/Right rotation

    switch (action) {
      case SimonAction.smile:
        return smiling > 0.75;
      case SimonAction.blink:
        return leftEyeOpen < 0.15 && rightEyeOpen < 0.15;
      case SimonAction.smirk:
        // One side smiling — asymmetric expression
        return smiling > 0.30 && smiling < 0.60;
      case SimonAction.turnLeft:
        // Head turned left (positive Y angle on front camera)
        return headEulerY > 25.0;
      case SimonAction.turnRight:
        // Head turned right (negative Y angle on front camera)
        return headEulerY < -25.0;
    }
  }

  void _onActionTimeout() {
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
      try {
        await _cameraController!.stopImageStream();
      } catch (_) {}

      final xFile = await _cameraController!.takePicture();
      final bytes = await xFile.readAsBytes();
      final base64Image = base64Encode(bytes);

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
    _checkmarkController.dispose();
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
              // ── Header ──
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
                    const SizedBox(height: 12),

                    // ── Step Progress Bar ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_actions.length, (i) {
                        final isCompleted = i < _currentStep;
                        final isCurrent = i == _currentStep && !_allStepsPassed;
                        return Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            height: 6,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: isCompleted
                                  ? AppTheme.success
                                  : isCurrent
                                      ? AppTheme.accent
                                      : AppTheme.textSecondary.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 8),

                    // ── Action Icons Row ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_actions.length, (i) {
                        final isCompleted = i < _currentStep;
                        final isCurrent = i == _currentStep && !_allStepsPassed;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isCompleted
                                ? AppTheme.success.withOpacity(0.2)
                                : isCurrent
                                    ? AppTheme.accent.withOpacity(0.15)
                                    : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isCompleted
                                  ? AppTheme.success
                                  : isCurrent
                                      ? AppTheme.accent
                                      : AppTheme.textSecondary.withOpacity(0.3),
                              width: isCurrent ? 2 : 1,
                            ),
                          ),
                          child: Icon(
                            isCompleted
                                ? Icons.check_rounded
                                : _actionIcons[_actions[i]]!,
                            color: isCompleted
                                ? AppTheme.success
                                : isCurrent
                                    ? AppTheme.accent
                                    : AppTheme.textSecondary,
                            size: 24,
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

              // ── Camera Preview ──
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
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  gradient: _timeRemaining <= 2
                                      ? LinearGradient(colors: [
                                          AppTheme.error,
                                          AppTheme.error.withOpacity(0.7),
                                        ])
                                      : LinearGradient(colors: [
                                          Colors.black54,
                                          Colors.black38,
                                        ]),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _timeRemaining <= 2
                                        ? AppTheme.error
                                        : Colors.white24,
                                    width: 2,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    '$_timeRemaining',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),

                          // Checkmark on action detect
                          if (_actionDetected)
                            ScaleTransition(
                              scale: _checkmarkAnimation,
                              child: Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  color: AppTheme.success.withOpacity(0.9),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                  size: 48,
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
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _verificationSuccess
                                          ? Icons.verified_rounded
                                          : Icons.cancel_rounded,
                                      color: _verificationSuccess
                                          ? AppTheme.success
                                          : AppTheme.error,
                                      size: 80,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      _verificationSuccess
                                          ? 'Identity Verified'
                                          : 'Verification Failed',
                                      style: TextStyle(
                                        color: _verificationSuccess
                                            ? AppTheme.success
                                            : AppTheme.error,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
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

              // ── Status & Action Prompt ──
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
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
                          if (_isVerifying) const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (!_allStepsPassed &&
                                  !_verificationComplete &&
                                  _currentStep < _actions.length)
                                Padding(
                                  padding: const EdgeInsets.only(right: 10),
                                  child: Icon(
                                    _actionIcons[_actions[_currentStep]]!,
                                    color: AppTheme.accent,
                                    size: 28,
                                  ),
                                ),
                              Flexible(
                                child: Text(
                                  _statusMessage,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage!,
                        style:
                            const TextStyle(color: AppTheme.error, fontSize: 13),
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

    // Draw corner brackets for premium look
    final bracketPaint = Paint()
      ..color = color.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    const bracketLen = 30.0;
    final rect = ovalRect.inflate(20);

    // Top-left
    canvas.drawLine(
        rect.topLeft, Offset(rect.left + bracketLen, rect.top), bracketPaint);
    canvas.drawLine(
        rect.topLeft, Offset(rect.left, rect.top + bracketLen), bracketPaint);

    // Top-right
    canvas.drawLine(
        rect.topRight, Offset(rect.right - bracketLen, rect.top), bracketPaint);
    canvas.drawLine(
        rect.topRight, Offset(rect.right, rect.top + bracketLen), bracketPaint);

    // Bottom-left
    canvas.drawLine(rect.bottomLeft,
        Offset(rect.left + bracketLen, rect.bottom), bracketPaint);
    canvas.drawLine(rect.bottomLeft,
        Offset(rect.left, rect.bottom - bracketLen), bracketPaint);

    // Bottom-right
    canvas.drawLine(rect.bottomRight,
        Offset(rect.right - bracketLen, rect.bottom), bracketPaint);
    canvas.drawLine(rect.bottomRight,
        Offset(rect.right, rect.bottom - bracketLen), bracketPaint);
  }

  @override
  bool shouldRepaint(covariant _OvalGuidePainter oldDelegate) =>
      oldDelegate.color != color;
}
