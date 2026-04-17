/// Fabio — Transfer Screen
///
/// Amount input, account picker, risk-based auth routing:
///   amount < threshold → PIN dialog
///   amount ≥ threshold → Liveness camera screen

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/fab_button.dart';
import '../widgets/glass_card.dart';

class TransferScreen extends StatefulWidget {
  const TransferScreen({super.key});

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _recipientController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

  List<BankAccount> _accounts = [];
  SecuritySettings? _settings;
  User? _user;
  BankAccount? _selectedAccount;
  bool _isLoading = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        ApiService.getAccounts(),
        ApiService.getSecuritySettings(),
        ApiService.getMe(),
      ]);
      if (!mounted) return;
      setState(() {
        _accounts = results[0] as List<BankAccount>;
        _settings = results[1] as SecuritySettings;
        _user = results[2] as User;
        if (_accounts.isNotEmpty) {
          _selectedAccount =
              _accounts.firstWhere((a) => a.isPrimary, orElse: () => _accounts.first);
        }
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _initiateTransfer() async {
    if (!_formKey.currentState!.validate() || _selectedAccount == null) return;

    final amount = double.tryParse(_amountController.text) ?? 0;
    final threshold = _settings?.thresholdAmount ?? 10000;

    if (amount < threshold) {
      // Low risk → PIN dialog
      _showPinDialog(amount);
    } else {
      // High risk → check if face is registered first
      if (_user?.isFaceRegistered != true) {
        _showFaceRequiredDialog();
        return;
      }
      // Proceed with biometric challenge
      setState(() => _isSending = true);
      try {
        final result = await ApiService.initiateTransfer(
          fromAccountId: _selectedAccount!.id,
          toAccountIdentifier: _recipientController.text.trim(),
          amount: amount,
          description: _descriptionController.text.trim(),
        );

        if (!mounted) return;

        if (result.requiresBiometric && result.challengeSequence != null) {
          final passed = await Navigator.pushNamed(
            context,
            '/liveness',
            arguments: {
              'transactionId': result.transactionId,
              'challengeSequence': result.challengeSequence,
            },
          );

          if (mounted) {
            if (passed == true) {
              _showSuccess();
            } else {
              setState(() => _isSending = false);
              _showError('Verification failed — transfer cancelled.');
            }
          }
        }
      } catch (e) {
        _showError('Transfer failed. Please try again.');
      } finally {
        if (mounted) setState(() => _isSending = false);
      }
    }
  }

  void _showPinDialog(double amount) {
    final pinController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Enter PIN', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Confirm transfer of ${_currencyFormat.format(amount)}',
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: pinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              style: const TextStyle(
                  color: Colors.white, fontSize: 24, letterSpacing: 12),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                counterText: '',
                hintText: '• • • •',
                hintStyle: TextStyle(
                    color: AppTheme.textSecondary.withOpacity(0.5),
                    letterSpacing: 8),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _submitPinTransfer(amount, pinController.text);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitPinTransfer(double amount, String pin) async {
    setState(() => _isSending = true);
    try {
      await ApiService.initiateTransfer(
        fromAccountId: _selectedAccount!.id,
        toAccountIdentifier: _recipientController.text.trim(),
        amount: amount,
        pin: pin,
        description: _descriptionController.text.trim(),
      );
      if (mounted) _showSuccess();
    } catch (e) {
      _showError('Invalid PIN or insufficient funds.');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _showSuccess() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Transfer completed successfully!'),
        backgroundColor: AppTheme.success,
      ),
    );
    Navigator.pop(context, true);
  }

  void _showFaceRequiredDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.face_unlock_rounded, color: AppTheme.warning, size: 28),
            SizedBox(width: 12),
            Text('Face Registration Required',
                style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: const Text(
          'High-value transfers require biometric verification. '
          'You must register your face data before proceeding.\n\n'
          'This is a one-time setup for secure identity verification.',
          style: TextStyle(color: AppTheme.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              final result =
                  await Navigator.pushNamed(context, '/face-register');
              if (result == true) {
                // Reload user data to get updated face status
                _loadData();
              }
            },
            icon: const Icon(Icons.face_retouching_natural, size: 18),
            label: const Text('Register Now'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppTheme.error),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _recipientController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final threshold = _settings?.thresholdAmount ?? 10000;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Transfer'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppTheme.accent))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Info Banner ─────────────────────────
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: AppTheme.accent.withOpacity(0.2)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline,
                                color: AppTheme.accent, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Transfers above ${_currencyFormat.format(threshold)} require biometric verification.',
                                style: const TextStyle(
                                    color: AppTheme.accent, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ── Source Account ─────────────────────
                      Text('From Account',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 10),
                      if (_accounts.isNotEmpty)
                        GlassCard(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<BankAccount>(
                              value: _selectedAccount,
                              isExpanded: true,
                              dropdownColor: AppTheme.surfaceCard,
                              style: const TextStyle(color: Colors.white),
                              items: _accounts.map((a) {
                                return DropdownMenuItem(
                                  value: a,
                                  child: Text(
                                    '${a.bankName} · ${a.maskedNumber} · ${_currencyFormat.format(a.balance)}',
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                );
                              }).toList(),
                              onChanged: (v) =>
                                  setState(() => _selectedAccount = v),
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),

                      // ── Recipient ─────────────────────────
                      Text('Recipient Account',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _recipientController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: 'Account number',
                          prefixIcon: Icon(Icons.person_outline,
                              color: AppTheme.textSecondary),
                        ),
                        validator: (v) => (v == null || v.length < 8)
                            ? 'Enter a valid account number'
                            : null,
                      ),
                      const SizedBox(height: 20),

                      // ── Amount ─────────────────────────────
                      Text('Amount',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w700),
                        decoration: const InputDecoration(
                          hintText: '0.00',
                          prefixIcon:
                              Icon(Icons.currency_rupee, color: AppTheme.accent),
                        ),
                        validator: (v) {
                          final amount = double.tryParse(v ?? '');
                          if (amount == null || amount <= 0) {
                            return 'Enter a valid amount';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      // ── Description ────────────────────────
                      TextFormField(
                        controller: _descriptionController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: 'Description (optional)',
                          prefixIcon: Icon(Icons.notes_rounded,
                              color: AppTheme.textSecondary),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // ── Submit ─────────────────────────────
                      FabButton(
                        label: 'Send Money',
                        onPressed: _initiateTransfer,
                        isLoading: _isSending,
                        icon: Icons.send_rounded,
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
