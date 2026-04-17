/// Fabio — Active Liveness Verification Screen
///
/// Camera preview with challenge overlay, countdown timer, progress dots,
/// and WebSocket real-time frame streaming to the backend.

import 'dart:async';
import 'dart:convert';


import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/api_config.dart';
import '../config/theme.dart';
import '../services/auth_service.dart';

class LivenessScreen extends StatefulWidget {
  const LivenessScreen({super.key});

  @override
  State<LivenessScreen> createState() => _LivenessScreenState();
}

class _LivenessScreenState extends State<LivenessScreen>
    with TickerProviderStateMixin {
  CameraController? _cameraController;
  WebSocketChannel? _channel;

  List<String> _challengeSequence = [];
  int _currentIndex = 0;
  String _currentAction = '';

  String _status = 'connecting';
  String _message = 'Initializing camera...';
  double _remainingTime = 15.0;
  List<bool> _results = [];
  bool _transactionCompleted = false;

  Timer? _timer;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _actionFadeController;

  bool _isStreaming = false;

  // Route arguments from TransferScreen
  String? _transactionId;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _actionFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _initCamera();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Read route arguments passed from TransferScreen
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      _transactionId ??= args['transactionId'] as String?;
    }
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
      setState(() => _message = 'Camera ready');

      _connectWebSocket();
    } catch (e) {
      setState(() {
        _status = 'error';
        _message = 'Camera initialization failed';
      });
    }
  }

  void _connectWebSocket() async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        setState(() {
          _status = 'error';
          _message = 'Not authenticated. Please login again.';
        });
        return;
      }

      final wsUrl = _transactionId != null && _transactionId!.isNotEmpty
          ? '${ApiConfig.wsUrl(token)}&transaction_id=$_transactionId'
          : ApiConfig.wsUrl(token);

      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _channel!.stream.listen(
        (data) {
          final msg = jsonDecode(data as String) as Map<String, dynamic>;
          _handleMessage(msg);
        },
        onError: (e) {
          if (mounted) {
            setState(() {
              _status = 'error';
              _message = 'Connection lost';
            });
          }
        },
        onDone: () {
          _stopStreaming();
        },
      );
    } catch (e) {
      setState(() {
        _status = 'error';
        _message = 'Could not connect to server';
      });
    }
  }

  void _handleMessage(Map<String, dynamic> msg) {
    if (!mounted) return;
    final type = msg['type'];

    switch (type) {
      case 'challenge':
        final seq = List<String>.from(msg['sequence'] ?? []);
        setState(() {
          _challengeSequence = seq;
          _currentAction = msg['current_action'] ?? '';
          _remainingTime = (msg['timeout'] ?? 15).toDouble();
          _status = 'in_progress';
          _message = 'Perform the actions below';
        });
        _actionFadeController.forward();
        _startStreaming();
        _startTimer();
        break;

      case 'feedback':
        final progress = msg['progress'] as Map<String, dynamic>?;
        if (progress != null) {
          setState(() {
            _currentIndex = progress['current_index'] ?? _currentIndex;
            _currentAction = progress['current_action'] ?? '';
            _remainingTime =
                (progress['remaining_time'] ?? _remainingTime).toDouble();
            _results = List<bool>.from(progress['results'] ?? []);
            // detected action available in msg['detected']
          });
          // Trigger action text animation on change
          _actionFadeController.reset();
          _actionFadeController.forward();
        }
        if (msg['message'] != null) {
          setState(() => _message = msg['message']);
        }
        break;

      case 'result':
        final status = msg['status'];
        final txnCompleted = msg['transaction_completed'] == true;
        setState(() {
          _status = status;
          _transactionCompleted = txnCompleted;
          if (status == 'passed') {
            _message = txnCompleted
                ? '✅ Verification passed — transfer completed!'
                : '✅ Verification passed!';
          } else {
            _message = msg['message'] ?? '❌ Verification failed';
          }
        });
        _stopStreaming();
        _timer?.cancel();
        // Auto-pop after showing result
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Navigator.pop(context, status == 'passed');
        });
        break;

      case 'error':
        setState(() => _message = msg['message'] ?? 'Error');
        break;
    }
  }

  void _startStreaming() {
    if (_isStreaming || _cameraController == null) return;
    _isStreaming = true;

    // Stream frames at ~5 FPS to avoid overloading
    Timer.periodic(const Duration(milliseconds: 200), (timer) async {
      if (!_isStreaming || !mounted || _cameraController == null) {
        timer.cancel();
        return;
      }
      try {
        final image = await _cameraController!.takePicture();
        final bytes = await image.readAsBytes();
        final b64 = base64Encode(bytes);

        _channel?.sink.add(jsonEncode({'frame': b64}));
      } catch (_) {}
    });
  }

  void _stopStreaming() {
    _isStreaming = false;
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _remainingTime = (_remainingTime - 0.1).clamp(0.0, 999.0);
      });
      if (_remainingTime <= 0) {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    _actionFadeController.dispose();
    _stopStreaming();
    _cameraController?.dispose();
    _channel?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Camera Preview ────────────────────────────────
          if (_cameraController != null &&
              _cameraController!.value.isInitialized)
            CameraPreview(_cameraController!)
          else
            const Center(
              child: CircularProgressIndicator(color: AppTheme.accent),
            ),

          // ── Dark Overlay ──────────────────────────────────
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.6),
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black.withOpacity(0.8),
                ],
                stops: const [0.0, 0.25, 0.7, 1.0],
              ),
            ),
          ),

          // ── Face Guide Ring ───────────────────────────────
          Center(
            child: ScaleTransition(
              scale: _pulseAnimation,
              child: Container(
                width: 260,
                height: 320,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(130),
                  border: Border.all(
                    color: _status == 'passed'
                        ? AppTheme.success
                        : _status == 'failed' || _status == 'timed_out'
                            ? AppTheme.error
                            : AppTheme.accent.withOpacity(0.6),
                    width: 3,
                  ),
                ),
              ),
            ),
          ),

          // ── Top Bar ───────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context, false),
                      icon: const Icon(Icons.close,
                          color: Colors.white, size: 28),
                    ),
                    // Timer
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: _remainingTime < 5
                            ? AppTheme.error.withOpacity(0.3)
                            : Colors.black.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.timer_outlined,
                              color: _remainingTime < 5
                                  ? AppTheme.error
                                  : Colors.white,
                              size: 18),
                          const SizedBox(width: 6),
                          Text(
                            '${_remainingTime.toStringAsFixed(1)}s',
                            style: TextStyle(
                              color: _remainingTime < 5
                                  ? AppTheme.error
                                  : Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
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

          // ── Bottom Overlay (Instructions) ─────────────────
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
                    // Progress dots
                    if (_challengeSequence.isNotEmpty) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          _challengeSequence.length,
                          (i) => Container(
                            width: 12,
                            height: 12,
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i < _results.length
                                  ? (_results[i]
                                      ? AppTheme.success
                                      : AppTheme.error)
                                  : i == _currentIndex
                                      ? AppTheme.accent
                                      : Colors.white.withOpacity(0.3),
                              boxShadow: i == _currentIndex
                                  ? [
                                      BoxShadow(
                                        color: AppTheme.accent.withOpacity(0.5),
                                        blurRadius: 8,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Current action instruction
                    FadeTransition(
                      opacity: _actionFadeController,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 28, vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: AppTheme.accent.withOpacity(0.3)),
                        ),
                        child: Column(
                          children: [
                            if (_currentAction.isNotEmpty) ...[
                              Icon(
                                _getActionIcon(_currentAction),
                                color: AppTheme.accent,
                                size: 36,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _getActionText(_currentAction),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                            if (_message.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                _message,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),
                    // UX hints
                    if (_status == 'in_progress')
                      Text(
                        '💡 Sit 50-70cm from camera · Ensure good lighting',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
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

  IconData _getActionIcon(String action) {
    switch (action) {
      case 'Blink':
        return Icons.visibility_off_rounded;
      case 'Smile':
        return Icons.sentiment_very_satisfied_rounded;
      case 'Smirk':
        return Icons.sentiment_satisfied_alt_rounded;
      default:
        return Icons.face_rounded;
    }
  }

  String _getActionText(String action) {
    switch (action) {
      case 'Blink':
        return 'Blink Now';
      case 'Smile':
        return 'Smile Wide';
      case 'Smirk':
        return 'Smirk Now';
      default:
        return action;
    }
  }
}
