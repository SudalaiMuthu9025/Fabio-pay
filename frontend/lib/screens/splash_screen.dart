/// Fabio — Splash Screen
///
/// Checks for stored JWT token and navigates accordingly.

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/theme.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _controller.forward();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    // Check if onboarding has been completed
    final onboardingDone = await _isOnboardingCompleted();

    final token = await AuthService.getToken();
    if (token != null) {
      try {
        await ApiService.getMe();
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/dashboard');
        return;
      } catch (_) {
        await AuthService.clearAll();
      }
    }
    if (!mounted) return;

    // Show onboarding for first-time users
    if (!onboardingDone) {
      await _setOnboardingCompleted();
      Navigator.pushReplacementNamed(context, '/onboarding');
    } else {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  Future<bool> _isOnboardingCompleted() async {
    try {
      const storage = FlutterSecureStorage();
      final val = await storage.read(key: 'fabio_onboarding_done');
      return val == 'true';
    } catch (_) {
      return false;
    }
  }

  Future<void> _setOnboardingCompleted() async {
    try {
      const storage = FlutterSecureStorage();
      await storage.write(key: 'fabio_onboarding_done', value: 'true');
    } catch (_) {}
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primary.withOpacity(0.4),
                        blurRadius: 32,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.fingerprint_rounded,
                      size: 52, color: Colors.white),
                ),
                const SizedBox(height: 24),
                Text('Fabio',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        )),
                const SizedBox(height: 8),
                Text('Secure Biometric Payments',
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 40),
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
