/// Fabio — Set PIN Screen
///
/// Step 4: Set a 4-digit transaction PIN with confirmation.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/theme.dart';
import '../services/api_service.dart';
import '../widgets/fab_button.dart';
import '../widgets/glass_card.dart';

class SetPinScreen extends ConsumerStatefulWidget {
  const SetPinScreen({super.key});

  @override
  ConsumerState<SetPinScreen> createState() => _SetPinScreenState();
}

class _SetPinScreenState extends ConsumerState<SetPinScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));
    _slideController.forward();
  }

  @override
  void dispose() {
    _slideController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  Future<void> _setPin() async {
    if (!_formKey.currentState!.validate()) return;

    if (_pinController.text != _confirmPinController.text) {
      setState(() => _errorMessage = 'PINs do not match');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await ApiService.setPin(_pinController.text);

      if (!mounted) return;

      // Registration complete — logout and go to login
      await ApiService.logout();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Registration complete! Please sign in.'),
          backgroundColor: AppTheme.success,
        ),
      );
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    } catch (e) {
      setState(() => _errorMessage = 'Failed to set PIN. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SlideTransition(
                position: _slideAnimation,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withOpacity(0.35),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.pin_rounded,
                          size: 38, color: Colors.white),
                    ),
                    const SizedBox(height: 24),
                    Text('Set Transaction PIN',
                        style: Theme.of(context).textTheme.headlineLarge),
                    const SizedBox(height: 8),
                    Text('Step 4 of 4 — Secure Your Payments',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppTheme.accent,
                            )),
                    const SizedBox(height: 32),

                    GlassCard(
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _pinController,
                              keyboardType: TextInputType.number,
                              maxLength: 4,
                              obscureText: true,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                letterSpacing: 12,
                              ),
                              textAlign: TextAlign.center,
                              decoration: const InputDecoration(
                                hintText: '● ● ● ●',
                                hintStyle: TextStyle(
                                  letterSpacing: 12,
                                  color: AppTheme.textSecondary,
                                ),
                                counterText: '',
                                prefixIcon: Icon(Icons.lock_outline,
                                    color: AppTheme.textSecondary),
                              ),
                              validator: (v) {
                                if (v == null || v.length != 4) return 'Enter 4 digits';
                                if (!RegExp(r'^\d{4}$').hasMatch(v)) return 'Digits only';
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _confirmPinController,
                              keyboardType: TextInputType.number,
                              maxLength: 4,
                              obscureText: true,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                letterSpacing: 12,
                              ),
                              textAlign: TextAlign.center,
                              decoration: const InputDecoration(
                                hintText: 'Confirm PIN',
                                hintStyle: TextStyle(
                                  color: AppTheme.textSecondary,
                                ),
                                counterText: '',
                                prefixIcon: Icon(Icons.lock_outline,
                                    color: AppTheme.textSecondary),
                              ),
                              validator: (v) {
                                if (v == null || v.length != 4) return 'Confirm your PIN';
                                return null;
                              },
                            ),
                            if (_errorMessage != null) ...[
                              const SizedBox(height: 12),
                              Text(_errorMessage!,
                                  style: const TextStyle(
                                      color: AppTheme.error, fontSize: 13)),
                            ],
                            const SizedBox(height: 24),
                            FabButton(
                              label: 'Complete Registration',
                              onPressed: _setPin,
                              isLoading: _isLoading,
                              icon: Icons.check_circle_rounded,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
