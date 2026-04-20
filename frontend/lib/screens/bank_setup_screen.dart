/// Fabio — Bank Setup Screen
///
/// Step 3: Register bank account (account number, IFSC, holder name).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/theme.dart';
import '../services/api_service.dart';
import '../widgets/fab_button.dart';
import '../widgets/glass_card.dart';

class BankSetupScreen extends ConsumerStatefulWidget {
  const BankSetupScreen({super.key});

  @override
  ConsumerState<BankSetupScreen> createState() => _BankSetupScreenState();
}

class _BankSetupScreenState extends ConsumerState<BankSetupScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _accountController = TextEditingController();
  final _ifscController = TextEditingController();
  final _holderController = TextEditingController();
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
    _accountController.dispose();
    _ifscController.dispose();
    _holderController.dispose();
    super.dispose();
  }

  Future<void> _registerBank() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await ApiService.registerBank(
        accountNumber: _accountController.text.trim(),
        ifscCode: _ifscController.text.trim().toUpperCase(),
        accountHolderName: _holderController.text.trim(),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bank account registered!'),
          backgroundColor: AppTheme.success,
        ),
      );
      Navigator.pushReplacementNamed(context, '/set-pin');
    } catch (e) {
      String msg = 'Bank registration failed. Please try again.';
      if (e.toString().contains('409')) {
        msg = 'Account number already registered.';
      }
      setState(() => _errorMessage = msg);
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
                      child: const Icon(Icons.account_balance_rounded,
                          size: 38, color: Colors.white),
                    ),
                    const SizedBox(height: 24),
                    Text('Link Bank Account',
                        style: Theme.of(context).textTheme.headlineLarge),
                    const SizedBox(height: 8),
                    Text('Step 3 of 4 — Bank Details',
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
                              controller: _accountController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                hintText: 'Account Number',
                                prefixIcon: Icon(Icons.numbers_rounded,
                                    color: AppTheme.textSecondary),
                              ),
                              validator: (v) =>
                                  (v == null || v.length < 8) ? 'Enter valid account number' : null,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _ifscController,
                              textCapitalization: TextCapitalization.characters,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                hintText: 'IFSC Code (e.g. SBIN0001234)',
                                prefixIcon: Icon(Icons.code_rounded,
                                    color: AppTheme.textSecondary),
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) return 'Enter IFSC code';
                                final regex = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');
                                if (!regex.hasMatch(v.toUpperCase())) {
                                  return 'Invalid IFSC format';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _holderController,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                hintText: 'Account Holder Name',
                                prefixIcon: Icon(Icons.person_outline,
                                    color: AppTheme.textSecondary),
                              ),
                              validator: (v) =>
                                  (v == null || v.length < 2) ? 'Enter account holder name' : null,
                            ),
                            if (_errorMessage != null) ...[
                              const SizedBox(height: 12),
                              Text(_errorMessage!,
                                  style: const TextStyle(
                                      color: AppTheme.error, fontSize: 13)),
                            ],
                            const SizedBox(height: 24),
                            FabButton(
                              label: 'Next — Set PIN',
                              onPressed: _registerBank,
                              isLoading: _isLoading,
                              icon: Icons.arrow_forward_rounded,
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
