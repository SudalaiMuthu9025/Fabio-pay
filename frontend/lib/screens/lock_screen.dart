/// Fabio — Lock Screen
///
/// Shown on auto-lock timeout. Requires biometric or PIN to resume.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import '../config/theme.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with SingleTickerProviderStateMixin {
  final _pinCtrl = TextEditingController();
  bool _isLoading = false;
  String? _error;
  late AnimationController _animCtrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _scaleAnim = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutBack));
    _animCtrl.forward();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    try {
      final LocalAuthentication auth = LocalAuthentication();
      final canCheck = await auth.canCheckBiometrics || await auth.isDeviceSupported();
      if (!canCheck) return;

      final didAuthenticate = await auth.authenticate(
        localizedReason: 'Please authenticate to unlock Fabio',
        options: const AuthenticationOptions(biometricOnly: true),
      );
      
      if (didAuthenticate && mounted) {
        HapticFeedback.heavyImpact();
        Navigator.pushReplacementNamed(context, '/dashboard');
      }
    } catch (_) {}
  }

  Future<void> _unlock() async {
    if (_pinCtrl.text.length != 4) { setState(() => _error = 'Enter 4-digit PIN'); return; }
    setState(() { _isLoading = true; _error = null; });
    try {
      await ApiService.verifyPin(_pinCtrl.text);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/dashboard');
    } catch (e) {
      setState(() { _error = 'Invalid PIN'; _isLoading = false; });
      HapticFeedback.heavyImpact();
    }
  }

  @override
  void dispose() { _animCtrl.dispose(); _pinCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: SafeArea(child: Center(child: ScaleTransition(
          scale: _scaleAnim,
          child: Padding(padding: const EdgeInsets.all(32), child: Column(
            mainAxisSize: MainAxisSize.min, children: [
              Container(width: 80, height: 80, decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient, shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: AppTheme.accent.withOpacity(0.3), blurRadius: 20)]),
                child: const Icon(Icons.lock_rounded, color: Colors.white, size: 40)),
              const SizedBox(height: 24),
              const Text('Session Locked', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text('Enter your PIN to continue', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
              const SizedBox(height: 32),
              GlassCard(child: Column(children: [
                TextField(controller: _pinCtrl, keyboardType: TextInputType.number,
                  maxLength: 4, obscureText: true, textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 28, letterSpacing: 12),
                  decoration: const InputDecoration(counterText: '', hintText: '••••',
                    border: InputBorder.none),
                  onSubmitted: (_) => _unlock()),
                if (_error != null) Padding(padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 13))),
              ])),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(height: 52, child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                      onPressed: _isLoading ? null : _unlock,
                      child: _isLoading ? const SizedBox(width: 24, height: 24,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Unlock', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)))),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 52,
                    width: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accent.withOpacity(0.2),
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: _checkBiometric,
                      child: const Icon(Icons.fingerprint_rounded, color: AppTheme.accent),
                    ),
                  ),
                ],
              ),
            ],
          )),
        ))),
      ),
    );
  }
}
