/// Fabio — Face Registration Screen
///
/// Camera-based face capture with oval guide overlay.
/// Captures a selfie and uploads it to register the face embedding in the DB.

import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../services/api_service.dart';

class FaceRegisterScreen extends StatefulWidget {
  const FaceRegisterScreen({super.key});

  @override
  State<FaceRegisterScreen> createState() => _FaceRegisterScreenState();
}

class _FaceRegisterScreenState extends State<FaceRegisterScreen>
    with TickerProviderStateMixin {
  CameraController? _cameraController;
  String? _capturedPath;
  String _status = 'initializing'; // initializing, ready, captured, uploading, success, error
  String _message = 'Initializing camera...';

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        front,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();
      if (!mounted) return;
      setState(() {
        _status = 'ready';
        _message = 'Position your face inside the oval and tap capture';
      });
      _fadeController.forward();
    } catch (e) {
      setState(() {
        _status = 'error';
        _message = 'Camera initialization failed';
      });
    }
  }

  Future<void> _capture() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    try {
      final image = await _cameraController!.takePicture();
      setState(() {
        _capturedPath = image.path;
        _status = 'captured';
        _message = 'Photo captured — review and register';
      });
    } catch (e) {
      setState(() {
        _message = 'Failed to capture photo';
      });
    }
  }

  void _retake() {
    setState(() {
      _capturedPath = null;
      _status = 'ready';
      _message = 'Position your face inside the oval and tap capture';
    });
  }

  Future<void> _registerFace() async {
    if (_capturedPath == null) return;

    setState(() {
      _status = 'uploading';
      _message = 'Processing face data...';
    });

    try {
      final result = await ApiService.registerFace(_capturedPath!);
      if (!mounted) return;

      setState(() {
        _status = 'success';
        _message = result['message'] ?? 'Face registered successfully!';
      });

      // Auto-pop after showing success
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) Navigator.pop(context, true);
      });
    } catch (e) {
      if (!mounted) return;
      String errorMsg = 'Failed to register face.';
      if (e.toString().contains('No face detected')) {
        errorMsg = 'No face detected. Please ensure good lighting and try again.';
      }
      setState(() {
        _status = 'error';
        _message = errorMsg;
      });
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _fadeController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Camera Preview / Captured Image ──────────────────
          if (_capturedPath != null)
            Image.file(
              File(_capturedPath!),
              fit: BoxFit.cover,
            )
          else if (_cameraController != null &&
              _cameraController!.value.isInitialized)
            CameraPreview(_cameraController!)
          else
            const Center(
              child: CircularProgressIndicator(color: AppTheme.accent),
            ),

          // ── Dark Overlay ──────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.6),
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black.withOpacity(0.85),
                ],
                stops: const [0.0, 0.2, 0.65, 1.0],
              ),
            ),
          ),

          // ── Face Guide Oval ───────────────────────────────────
          Center(
            child: ScaleTransition(
              scale: _pulseAnimation,
              child: Container(
                width: 240,
                height: 310,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(120),
                  border: Border.all(
                    color: _status == 'success'
                        ? AppTheme.success
                        : _status == 'error'
                            ? AppTheme.error
                            : _status == 'uploading'
                                ? AppTheme.warning
                                : AppTheme.accent.withOpacity(0.7),
                    width: 3,
                  ),
                ),
              ),
            ),
          ),

          // ── Top Bar ───────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context, false),
                      icon: const Icon(Icons.close,
                          color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Face Registration',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    // Status indicator
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _status == 'success'
                            ? AppTheme.success.withOpacity(0.2)
                            : _status == 'error'
                                ? AppTheme.error.withOpacity(0.2)
                                : AppTheme.accent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _status == 'success'
                                ? Icons.check_circle
                                : _status == 'error'
                                    ? Icons.error
                                    : Icons.face_retouching_natural,
                            color: _status == 'success'
                                ? AppTheme.success
                                : _status == 'error'
                                    ? AppTheme.error
                                    : AppTheme.accent,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _status == 'success'
                                ? 'Done'
                                : _status == 'error'
                                    ? 'Error'
                                    : 'Face ID',
                            style: TextStyle(
                              color: _status == 'success'
                                  ? AppTheme.success
                                  : _status == 'error'
                                      ? AppTheme.error
                                      : AppTheme.accent,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Bottom Panel ──────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Status message
                    FadeTransition(
                      opacity: _fadeController,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _status == 'success'
                                ? AppTheme.success.withOpacity(0.3)
                                : _status == 'error'
                                    ? AppTheme.error.withOpacity(0.3)
                                    : AppTheme.accent.withOpacity(0.2),
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              _status == 'success'
                                  ? Icons.check_circle_rounded
                                  : _status == 'error'
                                      ? Icons.error_rounded
                                      : _status == 'uploading'
                                          ? Icons.cloud_upload_rounded
                                          : Icons.face_rounded,
                              color: _status == 'success'
                                  ? AppTheme.success
                                  : _status == 'error'
                                      ? AppTheme.error
                                      : AppTheme.accent,
                              size: 32,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _message,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Action buttons
                    if (_status == 'ready') ...[
                      // Capture button
                      GestureDetector(
                        onTap: _capture,
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 4),
                          ),
                          child: Center(
                            child: Container(
                              width: 58,
                              height: 58,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: AppTheme.primaryGradient,
                              ),
                              child: const Icon(
                                Icons.camera_alt_rounded,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ] else if (_status == 'captured') ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Retake
                          GestureDetector(
                            onTap: _retake,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 28, vertical: 14),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceCard,
                                borderRadius: BorderRadius.circular(16),
                                border:
                                    Border.all(color: AppTheme.border),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.refresh_rounded,
                                      color: Colors.white, size: 20),
                                  SizedBox(width: 8),
                                  Text('Retake',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Register
                          GestureDetector(
                            onTap: _registerFace,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 28, vertical: 14),
                              decoration: BoxDecoration(
                                gradient: AppTheme.primaryGradient,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.check_rounded,
                                      color: Colors.white, size: 20),
                                  SizedBox(width: 8),
                                  Text('Register Face',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ] else if (_status == 'uploading') ...[
                      const CircularProgressIndicator(color: AppTheme.accent),
                    ] else if (_status == 'error') ...[
                      GestureDetector(
                        onTap: _retake,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 28, vertical: 14),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceCard,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.refresh_rounded,
                                  color: Colors.white, size: 20),
                              SizedBox(width: 8),
                              Text('Try Again',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 12),

                    // Tips
                    if (_status == 'ready' || _status == 'captured')
                      Text(
                        '💡 Ensure good lighting · Look straight ahead · Remove glasses',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
