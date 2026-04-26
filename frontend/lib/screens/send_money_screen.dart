/// Fabio — Send Money Screen (GPay/PhonePe Style)
///
/// Three payment tabs: UPI ID, Account Number, QR Code.
/// Enter recipient, amount, PIN. If amount >= ₹5000 threshold,
/// navigates to LivenessCheckScreen before completing.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../widgets/fab_button.dart';
import '../widgets/glass_card.dart';
import 'liveness_check_screen.dart';
import 'transaction_receipt_screen.dart';

class SendMoneyScreen extends ConsumerStatefulWidget {
  const SendMoneyScreen({super.key});

  @override
  ConsumerState<SendMoneyScreen> createState() => _SendMoneyScreenState();
}

class _SendMoneyScreenState extends ConsumerState<SendMoneyScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _recipientController = TextEditingController();
  final _amountController = TextEditingController();
  final _pinController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  // Payment mode
  int _selectedTab = 0; // 0 = UPI, 1 = Account, 2 = QR
  static const _modes = ['UPI', 'ACCOUNT', 'QR'];

  late TabController _tabController;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  late AnimationController _successController;
  late Animation<double> _successScale;

  final _currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

  // Quick amount buttons
  static const _quickAmounts = [500, 1000, 2000, 5000];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      setState(() => _selectedTab = _tabController.index);
      _recipientController.clear();
      _errorMessage = null;
    });

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

    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _successScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _successController, curve: Curves.elasticOut),
    );

    _slideController.forward();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _slideController.dispose();
    _successController.dispose();
    _recipientController.dispose();
    _amountController.dispose();
    _pinController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  String get _currentPaymentMode => _modes[_selectedTab];

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
        paymentMode: _currentPaymentMode,
        faceVerified: faceVerified,
      );

      if (result.requiresLiveness) {
        setState(() => _isLoading = false);
        if (!mounted) return;

        final livenessResult = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => const LivenessCheckScreen(),
          ),
        );

        if (livenessResult == true) {
          await _sendMoney(faceVerified: true);
        } else {
          setState(() {
            _errorMessage = 'Liveness verification failed. Transaction blocked.';
          });
        }
        return;
      }

      if (result.status == 'SUCCESS') {
        HapticFeedback.heavyImpact();
        
        // Trigger push notification
        NotificationService.showNotification(
          id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          title: 'Payment Successful',
          body: 'You sent ${_currencyFormat.format(amount)} to ${_recipientController.text.trim()}',
        );

        if (!mounted) return;
        // Navigate to receipt screen
        final receiptResult = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TransactionReceiptScreen(
              transactionId: result.transactionId,
            ),
          ),
        );
        if (!mounted) return;
        Navigator.pop(context, true); // Return to dashboard
        return;
      } else {
        setState(() => _errorMessage = result.message);
      }
    } catch (e) {
      String msg = 'Transaction failed. Please try again.';
      if (e.toString().contains('401')) {
        msg = 'Invalid PIN.';
      } else if (e.toString().contains('400')) {
        final errStr = e.toString().toLowerCase();
        if (errStr.contains('upi')) {
          msg = 'Invalid UPI ID format.';
        } else if (errStr.contains('balance')) {
          msg = 'Insufficient balance.';
        } else {
          msg = 'Missing requirements. Check your details.';
        }
      }
      setState(() => _errorMessage = msg);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String? _validateRecipient(String? v) {
    if (v == null || v.isEmpty) return 'Required';
    switch (_selectedTab) {
      case 0: // UPI
        if (!v.contains('@')) return 'Enter valid UPI ID (e.g. name@bank)';
        break;
      case 1: // Account
        if (v.length < 8) return 'Enter valid account number';
        break;
      case 2: // QR
        if (v.length < 3) return 'Enter scanned identifier';
        break;
    }
    return null;
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
            padding: const EdgeInsets.all(20),
            child: SlideTransition(
              position: _slideAnimation,
              child: Column(
                children: [
                  // ── Success State ──
                  if (_successMessage != null) ...[
                    const SizedBox(height: 40),
                    ScaleTransition(
                      scale: _successScale,
                      child: GlassCard(
                        child: Column(
                          children: [
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppTheme.success,
                                    AppTheme.success.withOpacity(0.7),
                                  ],
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.check_rounded,
                                  color: Colors.white, size: 48),
                            ),
                            const SizedBox(height: 20),
                            Text(_successMessage!,
                                style: const TextStyle(
                                  color: AppTheme.success,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.center),
                            const SizedBox(height: 8),
                            Text(
                              _currentPaymentMode == 'UPI'
                                  ? 'Sent via UPI ⚡'
                                  : _currentPaymentMode == 'QR'
                                      ? 'Sent via QR 📱'
                                      : 'Bank Transfer 🏦',
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    // ── Payment Mode Tabs ──
                    GlassCard(
                      padding: const EdgeInsets.all(6),
                      child: TabBar(
                        controller: _tabController,
                        indicatorSize: TabBarIndicatorSize.tab,
                        indicator: BoxDecoration(
                          gradient: AppTheme.primaryGradient,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        dividerColor: Colors.transparent,
                        labelColor: Colors.white,
                        unselectedLabelColor: AppTheme.textSecondary,
                        labelStyle: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        tabs: const [
                          Tab(
                            icon: Icon(Icons.flash_on_rounded, size: 20),
                            text: 'UPI ID',
                          ),
                          Tab(
                            icon: Icon(Icons.account_balance_rounded, size: 20),
                            text: 'Account',
                          ),
                          Tab(
                            icon: Icon(Icons.qr_code_scanner_rounded, size: 20),
                            text: 'QR Code',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Form ──
                    GlassCard(
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _selectedTab == 0
                                      ? Icons.flash_on_rounded
                                      : _selectedTab == 1
                                          ? Icons.account_balance_rounded
                                          : Icons.qr_code_scanner_rounded,
                                  color: AppTheme.accent,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _selectedTab == 0
                                      ? 'Pay via UPI'
                                      : _selectedTab == 1
                                          ? 'Bank Transfer'
                                          : 'QR Payment',
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Recipient
                            TextFormField(
                              controller: _recipientController,
                              keyboardType: _selectedTab == 0
                                  ? TextInputType.emailAddress
                                  : TextInputType.number,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: _selectedTab == 0
                                    ? 'Enter UPI ID (e.g. name@oksbi)'
                                    : _selectedTab == 1
                                        ? 'Account Number'
                                        : 'QR Scanned ID',
                                prefixIcon: Icon(
                                  _selectedTab == 0
                                      ? Icons.alternate_email_rounded
                                      : _selectedTab == 1
                                          ? Icons.person_outline
                                          : Icons.qr_code_2_rounded,
                                  color: AppTheme.textSecondary,
                                ),
                                // Show popular UPI app hints
                                suffixIcon: _selectedTab == 0
                                    ? PopupMenuButton<String>(
                                        icon: const Icon(Icons.expand_more,
                                            color: AppTheme.textSecondary),
                                        color: AppTheme.surfaceCard,
                                        onSelected: (suffix) {
                                          final current =
                                              _recipientController.text
                                                  .split('@')
                                                  .first;
                                          _recipientController.text =
                                              '$current@$suffix';
                                        },
                                        itemBuilder: (_) => [
                                          _upiMenuItem('oksbi', 'SBI'),
                                          _upiMenuItem('okhdfcbank', 'HDFC'),
                                          _upiMenuItem('okicici', 'ICICI'),
                                          _upiMenuItem('okaxis', 'Axis'),
                                          _upiMenuItem('ybl', 'PhonePe'),
                                          _upiMenuItem('paytm', 'Paytm'),
                                          _upiMenuItem('gpay', 'GPay'),
                                          _upiMenuItem('ibl', 'IDBI'),
                                        ],
                                      )
                                    : null,
                              ),
                              validator: _validateRecipient,
                            ),
                            const SizedBox(height: 14),

                            // Amount
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

                            // Quick Amount Buttons
                            const SizedBox(height: 12),
                            Row(
                              children: _quickAmounts.map((amt) {
                                return Expanded(
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.symmetric(horizontal: 3),
                                    child: GestureDetector(
                                      onTap: () {
                                        _amountController.text = amt.toString();
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 8),
                                        decoration: BoxDecoration(
                                          color: AppTheme.accent.withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border.all(
                                            color:
                                                AppTheme.accent.withOpacity(0.3),
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            '₹$amt',
                                            style: const TextStyle(
                                              color: AppTheme.accent,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),

                            const SizedBox(height: 14),

                            // Description
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

                            // PIN
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
                                if (v == null || v.length != 4) {
                                  return 'Enter 4-digit PIN';
                                }
                                if (!RegExp(r'^\d{4}$').hasMatch(v)) {
                                  return 'Digits only';
                                }
                                return null;
                              },
                            ),

                            // Threshold notice
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppTheme.accent.withOpacity(0.2),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.shield_rounded,
                                      color: AppTheme.accent, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Transactions ≥ ₹5,000 require face liveness verification for security.',
                                      style: TextStyle(
                                        color: AppTheme.accent.withOpacity(0.9),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            if (_errorMessage != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppTheme.error.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.error_outline,
                                        color: AppTheme.error, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(_errorMessage!,
                                          style: const TextStyle(
                                              color: AppTheme.error,
                                              fontSize: 13)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 24),
                            FabButton(
                              label: _selectedTab == 0
                                  ? 'Pay via UPI ⚡'
                                  : _selectedTab == 2
                                      ? 'Pay via QR'
                                      : 'Send Money',
                              onPressed: () => _sendMoney(),
                              isLoading: _isLoading,
                              icon: _selectedTab == 0
                                  ? Icons.flash_on_rounded
                                  : Icons.send_rounded,
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

  PopupMenuItem<String> _upiMenuItem(String suffix, String label) {
    return PopupMenuItem(
      value: suffix,
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppTheme.accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Icon(Icons.account_balance_rounded,
                  color: AppTheme.accent, size: 16),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
              Text('@$suffix',
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}
