/// Fabio — Transaction Receipt Screen
///
/// Premium receipt view with animated status, full transaction details,
/// and share/copy functionality. Shown after payment or from history.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../config/theme.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart';

class TransactionReceiptScreen extends ConsumerStatefulWidget {
  final String? transactionId;
  final TransactionModel? transaction;

  const TransactionReceiptScreen({
    super.key,
    this.transactionId,
    this.transaction,
  });

  @override
  ConsumerState<TransactionReceiptScreen> createState() =>
      _TransactionReceiptScreenState();
}

class _TransactionReceiptScreenState
    extends ConsumerState<TransactionReceiptScreen>
    with TickerProviderStateMixin {
  TransactionModel? _txn;
  Map<String, dynamic>? _detail;
  bool _isLoading = true;
  String? _error;

  late AnimationController _statusController;
  late Animation<double> _statusScale;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnim;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;

  final _currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

  @override
  void initState() {
    super.initState();

    _statusController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _statusScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _statusController, curve: Curves.elasticOut),
    );

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(_fadeController);

    _loadTransaction();
  }

  Future<void> _loadTransaction() async {
    try {
      if (widget.transaction != null) {
        _txn = widget.transaction;
        // Also fetch enriched detail
        try {
          final resp =
              await ApiService.getTransactionDetail(widget.transaction!.id);
          _txn = resp;
        } catch (_) {}
      } else if (widget.transactionId != null) {
        _txn = await ApiService.getTransactionDetail(widget.transactionId!);
      }

      if (!mounted) return;
      setState(() => _isLoading = false);

      // Trigger haptic on successful transaction
      if (_txn?.status == 'SUCCESS') {
        HapticFeedback.heavyImpact();
      }

      _statusController.forward();
      await Future.delayed(const Duration(milliseconds: 200));
      _slideController.forward();
      await Future.delayed(const Duration(milliseconds: 200));
      _fadeController.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Failed to load transaction details';
      });
    }
  }

  void _shareReceipt() {
    if (_txn == null) return;
    final isSuccess = _txn!.status == 'SUCCESS';
    final isCredit = _txn!.isCredit;

    final text = '''
━━━━━━━━━━━━━━━━━━━━━━
  FABIO PAY — RECEIPT
━━━━━━━━━━━━━━━━━━━━━━

Status: ${isSuccess ? '✅ SUCCESS' : '❌ FAILED'}
Type: ${isCredit ? '📥 Received' : '📤 Sent'}
Amount: ${_currencyFormat.format(_txn!.amount)}

${isCredit ? 'From' : 'To'}: ${_txn!.toAccountIdentifier}
Payment Mode: ${_txn!.paymentMode}
Auth: ${_txn!.authMethod}
Date: ${DateFormat('dd MMM yyyy, hh:mm a').format(_txn!.createdAt.toLocal())}

Transaction ID:
${_txn!.id}

━━━━━━━━━━━━━━━━━━━━━━
  Powered by Fabio Pay
━━━━━━━━━━━━━━━━━━━━━━
''';

    SharePlus.instance.share(ShareParams(text: text));
  }

  void _copyTransactionId() {
    if (_txn == null) return;
    Clipboard.setData(ClipboardData(text: _txn!.id));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Transaction ID copied'),
        backgroundColor: AppTheme.success,
        duration: Duration(seconds: 2),
      ),
    );
    HapticFeedback.lightImpact();
  }

  @override
  void dispose() {
    _statusController.dispose();
    _slideController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSuccess = _txn?.status == 'SUCCESS';
    final isCredit = _txn?.isCredit ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction Receipt'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context, true),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: SafeArea(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.accent))
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline,
                              color: AppTheme.error, size: 48),
                          const SizedBox(height: 12),
                          Text(_error!,
                              style: const TextStyle(color: AppTheme.error)),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          const SizedBox(height: 20),

                          // ── Status Icon ──
                          ScaleTransition(
                            scale: _statusScale,
                            child: Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: isSuccess
                                      ? [
                                          const Color(0xFF00E676),
                                          const Color(0xFF00C853)
                                        ]
                                      : [
                                          const Color(0xFFFF5252),
                                          const Color(0xFFD32F2F)
                                        ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: (isSuccess
                                            ? AppTheme.success
                                            : AppTheme.error)
                                        .withOpacity(0.4),
                                    blurRadius: 24,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Icon(
                                isSuccess
                                    ? Icons.check_rounded
                                    : Icons.close_rounded,
                                color: Colors.white,
                                size: 56,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // ── Status Text ──
                          SlideTransition(
                            position: _slideAnim,
                            child: Column(
                              children: [
                                Text(
                                  isSuccess
                                      ? 'Payment Successful!'
                                      : 'Payment Failed',
                                  style: TextStyle(
                                    color: isSuccess
                                        ? AppTheme.success
                                        : AppTheme.error,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _currencyFormat.format(_txn?.amount ?? 0),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 40,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -1,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: (isCredit
                                            ? AppTheme.success
                                            : AppTheme.accent)
                                        .withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    isCredit
                                        ? '📥 Money Received'
                                        : '📤 Money Sent',
                                    style: TextStyle(
                                      color: isCredit
                                          ? AppTheme.success
                                          : AppTheme.accent,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),

                          // ── Receipt Details Card ──
                          FadeTransition(
                            opacity: _fadeAnim,
                            child: GlassCard(
                              child: Column(
                                children: [
                                  _ReceiptRow(
                                    icon: Icons.person_outline,
                                    label: isCredit ? 'From' : 'To',
                                    value: _txn?.toAccountIdentifier ?? '',
                                  ),
                                  _receiptDivider(),
                                  if (_txn?.senderName != null) ...[
                                    _ReceiptRow(
                                      icon: Icons.account_circle_outlined,
                                      label: 'Sender',
                                      value: _txn!.senderName!,
                                    ),
                                    _receiptDivider(),
                                  ],
                                  if (_txn?.receiverName != null) ...[
                                    _ReceiptRow(
                                      icon: Icons.account_circle_outlined,
                                      label: 'Receiver',
                                      value: _txn!.receiverName!,
                                    ),
                                    _receiptDivider(),
                                  ],
                                  _ReceiptRow(
                                    icon: Icons.flash_on_rounded,
                                    label: 'Payment Mode',
                                    value: _paymentModeLabel(
                                        _txn?.paymentMode ?? 'ACCOUNT'),
                                  ),
                                  _receiptDivider(),
                                  _ReceiptRow(
                                    icon: Icons.shield_rounded,
                                    label: 'Auth Method',
                                    value: _txn?.authMethod ?? '',
                                  ),
                                  _receiptDivider(),
                                  _ReceiptRow(
                                    icon: Icons.calendar_today_rounded,
                                    label: 'Date & Time',
                                    value: _txn != null
                                        ? DateFormat('dd MMM yyyy, hh:mm a')
                                            .format(_txn!.createdAt.toLocal())
                                        : '',
                                  ),
                                  if (_txn?.description != null &&
                                      _txn!.description!.isNotEmpty) ...[
                                    _receiptDivider(),
                                    _ReceiptRow(
                                      icon: Icons.note_outlined,
                                      label: 'Note',
                                      value: _txn!.description!,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // ── Transaction ID ──
                          FadeTransition(
                            opacity: _fadeAnim,
                            child: GlassCard(
                              child: InkWell(
                                onTap: _copyTransactionId,
                                borderRadius: BorderRadius.circular(16),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color:
                                            AppTheme.accent.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                          Icons.tag_rounded,
                                          color: AppTheme.accent,
                                          size: 18),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text('Transaction ID',
                                              style: TextStyle(
                                                  color:
                                                      AppTheme.textSecondary,
                                                  fontSize: 11)),
                                          Text(
                                            _txn?.id ?? '',
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontFamily: 'monospace'),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.copy_rounded,
                                        color: AppTheme.accent, size: 18),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // ── Action Buttons ──
                          FadeTransition(
                            opacity: _fadeAnim,
                            child: Row(
                              children: [
                                Expanded(
                                  child: _ActionButton(
                                    icon: Icons.share_rounded,
                                    label: 'Share',
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF6C63FF),
                                        Color(0xFF4834D4)
                                      ],
                                    ),
                                    onTap: _shareReceipt,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _ActionButton(
                                    icon: Icons.home_rounded,
                                    label: 'Home',
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF00BCD4),
                                        Color(0xFF0097A7)
                                      ],
                                    ),
                                    onTap: () {
                                      Navigator.pushNamedAndRemoveUntil(
                                          context,
                                          '/dashboard',
                                          (route) => false);
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }

  Widget _receiptDivider() => Divider(
        color: Colors.white.withOpacity(0.06),
        height: 1,
      );

  String _paymentModeLabel(String mode) {
    switch (mode) {
      case 'UPI':
        return '⚡ UPI Transfer';
      case 'QR':
        return '📱 QR Payment';
      default:
        return '🏦 Bank Transfer';
    }
  }
}

// ── Receipt Row ──────────────────────────────────────────────────────────────
class _ReceiptRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ReceiptRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.textSecondary, size: 18),
          const SizedBox(width: 12),
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13)),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Action Button ────────────────────────────────────────────────────────────
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final LinearGradient gradient;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: gradient.colors.first.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15)),
          ],
        ),
      ),
    );
  }
}
