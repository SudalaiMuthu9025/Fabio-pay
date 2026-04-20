/// Fabio — Send Money Screen
///
/// Enter recipient, amount, PIN. If amount >= ₹5000 threshold,
/// navigates to LivenessCheckScreen before completing.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../services/api_service.dart';
import '../widgets/fab_button.dart';
import '../widgets/glass_card.dart';
import 'liveness_check_screen.dart';

class SendMoneyScreen extends ConsumerStatefulWidget {
  const SendMoneyScreen({super.key});

  @override
  ConsumerState<SendMoneyScreen> createState() => _SendMoneyScreenState();
}

class _SendMoneyScreenState extends ConsumerState<SendMoneyScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _recipientController = TextEditingController();
  final _amountController = TextEditingController();
  final _pinController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  final _currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

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
    _recipientController.dispose();
    _amountController.dispose();
    _pinController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _sendMoney({bool faceVerified = false}) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final amount = double.parse(_amountController.text.trim());

      final result = await ApiService.sendMoney(
        toAccount: _recipientController.text.trim(),
        amount: amount,
        pin: _pinController.text,
        description: _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        faceVerified: faceVerified,
      );

      if (result.requiresLiveness) {
        // Navigate to liveness check
        setState(() => _isLoading = false);
        if (!mounted) return;

        final livenessResult = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => const LivenessCheckScreen(),
          ),
        );

        if (livenessResult == true) {
          // Liveness passed — retry with faceVerified = true
          await _sendMoney(faceVerified: true);
        } else {
          setState(() {
            _errorMessage = 'Liveness verification failed. Transaction blocked.';
          });
        }
        return;
      }

      if (result.status == 'success') {
        setState(() {
          _successMessage = 'Transfer of ${_currencyFormat.format(amount)} completed!';
        });

        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        Navigator.pop(context);
      } else {
        setState(() => _errorMessage = result.message);
      }
    } catch (e) {
      String msg = 'Transaction failed. Please try again.';
      if (e.toString().contains('401')) {
        msg = 'Invalid PIN.';
      } else if (e.toString().contains('400')) {
        msg = 'Insufficient balance or missing requirements.';
      }
      setState(() => _errorMessage = msg);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send Money'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: SlideTransition(
              position: _slideAnimation,
              child: Column(
                children: [
                  const SizedBox(height: 20),

                  // Success message
                  if (_successMessage != null) ...[
                    GlassCard(
                      child: Column(
                        children: [
                          const Icon(Icons.check_circle_rounded,
                              color: AppTheme.success, size: 64),
                          const SizedBox(height: 16),
                          Text(_successMessage!,
                              style: const TextStyle(
                                color: AppTheme.success,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  ] else ...[
                    GlassCard(
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Transfer Details',
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _recipientController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                hintText: 'Recipient Account Number',
                                prefixIcon: Icon(Icons.person_outline,
                                    color: AppTheme.textSecondary),
                              ),
                              validator: (v) => (v == null || v.length < 8)
                                  ? 'Enter valid account number'
                                  : null,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _amountController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 22),
                              decoration: const InputDecoration(
                                hintText: 'Amount (₹)',
                                prefixIcon: Icon(Icons.currency_rupee_rounded,
                                    color: AppTheme.textSecondary),
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) return 'Enter amount';
                                final amount = double.tryParse(v);
                                if (amount == null || amount <= 0) {
                                  return 'Enter valid amount';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _descriptionController,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                hintText: 'Description (optional)',
                                prefixIcon: Icon(Icons.note_outlined,
                                    color: AppTheme.textSecondary),
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _pinController,
                              keyboardType: TextInputType.number,
                              maxLength: 4,
                              obscureText: true,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                letterSpacing: 8,
                              ),
                              textAlign: TextAlign.center,
                              decoration: const InputDecoration(
                                hintText: 'Enter PIN',
                                counterText: '',
                                prefixIcon: Icon(Icons.lock_outline,
                                    color: AppTheme.textSecondary),
                              ),
                              validator: (v) {
                                if (v == null || v.length != 4) return 'Enter 4-digit PIN';
                                if (!RegExp(r'^\d{4}$').hasMatch(v)) return 'Digits only';
                                return null;
                              },
                            ),

                            // Threshold notice
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppTheme.accent.withOpacity(0.3),
                                ),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.info_outline,
                                      color: AppTheme.accent, size: 18),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Transactions ≥ ₹5,000 require face liveness verification.',
                                      style: TextStyle(
                                        color: AppTheme.accent,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            if (_errorMessage != null) ...[
                              const SizedBox(height: 12),
                              Text(_errorMessage!,
                                  style: const TextStyle(
                                      color: AppTheme.error, fontSize: 13)),
                            ],
                            const SizedBox(height: 24),
                            FabButton(
                              label: 'Send Money',
                              onPressed: () => _sendMoney(),
                              isLoading: _isLoading,
                              icon: Icons.send_rounded,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
