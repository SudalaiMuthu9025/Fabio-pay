/// Fabio — Dashboard Screen
///
/// Shows balance (hidden until PIN), user info, setup status,
/// quick actions (Send, Deposit, Beneficiaries, History, Profile).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with SingleTickerProviderStateMixin {
  User? _user;
  List<BankAccount> _accounts = [];
  List<TransactionModel> _recentTxns = [];
  bool _isLoading = true;
  bool _balanceVisible = false;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  final _currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final user = await ApiService.getMe();
      final accounts = await ApiService.getAccounts();
      List<TransactionModel> txns = [];
      try {
        txns = await ApiService.getTransactionHistory();
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _user = user;
        _accounts = accounts;
        _recentTxns = txns.take(5).toList();
        _isLoading = false;
        _balanceVisible = false; // Always hide on refresh
      });
      _fadeController.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _toggleBalance() {
    // Require PIN to show balance
    if (!_balanceVisible) {
      _showPinDialog();
    } else {
      setState(() => _balanceVisible = false);
    }
  }

  void _showPinDialog() {
    final pinController = TextEditingController();
    bool isVerifying = false;
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.surfaceCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.lock_outline, color: AppTheme.accent, size: 22),
              SizedBox(width: 8),
              Text('Enter PIN', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: pinController,
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
                autofocus: true,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  letterSpacing: 12,
                ),
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  hintText: '• • • •',
                  counterText: '',
                  hintStyle: TextStyle(color: AppTheme.textSecondary),
                ),
                onSubmitted: (v) async {
                  if (v.length == 4 && !isVerifying) {
                    setDialogState(() { isVerifying = true; error = null; });
                    final valid = await ApiService.verifyPin(v);
                    if (!ctx.mounted) return;
                    if (valid) {
                      Navigator.pop(ctx);
                      setState(() => _balanceVisible = true);
                      Future.delayed(const Duration(seconds: 30), () {
                        if (mounted) setState(() => _balanceVisible = false);
                      });
                    } else {
                      setDialogState(() { isVerifying = false; error = 'Invalid PIN'; });
                      pinController.clear();
                    }
                  }
                },
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
            ),
            TextButton(
              onPressed: isVerifying ? null : () async {
                if (pinController.text.length == 4) {
                  setDialogState(() { isVerifying = true; error = null; });
                  final valid = await ApiService.verifyPin(pinController.text);
                  if (!ctx.mounted) return;
                  if (valid) {
                    Navigator.pop(ctx);
                    setState(() => _balanceVisible = true);
                    Future.delayed(const Duration(seconds: 30), () {
                      if (mounted) setState(() => _balanceVisible = false);
                    });
                  } else {
                    setDialogState(() { isVerifying = false; error = 'Invalid PIN'; });
                    pinController.clear();
                  }
                }
              },
              child: isVerifying
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent))
                  : const Text('Reveal', style: TextStyle(color: AppTheme.accent)),
            ),
          ],
        ),
      ),
    );
  }

  void _showDepositDialog() {
    final amountController = TextEditingController();
    final pinController = TextEditingController();
    bool isLoading = false;
    String? error;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.textSecondary.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Row(
                children: [
                  Icon(Icons.add_circle_outline_rounded,
                      color: AppTheme.success, size: 24),
                  SizedBox(width: 10),
                  Text('Add Money',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 20),

              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white, fontSize: 22),
                decoration: const InputDecoration(
                  hintText: 'Amount (₹)',
                  prefixIcon: Icon(Icons.currency_rupee_rounded,
                      color: AppTheme.textSecondary),
                ),
              ),

              const SizedBox(height: 12),

              // Quick amounts
              Row(
                children: [1000, 5000, 10000, 25000].map((amt) {
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: GestureDetector(
                        onTap: () => amountController.text = amt.toString(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.success.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: AppTheme.success.withOpacity(0.3)),
                          ),
                          child: Center(
                            child: Text(
                              '₹${NumberFormat('#,##,###').format(amt)}',
                              style: const TextStyle(
                                color: AppTheme.success,
                                fontSize: 12,
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

              const SizedBox(height: 16),
              TextField(
                controller: pinController,
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
                style: const TextStyle(
                    color: Colors.white, fontSize: 20, letterSpacing: 8),
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  hintText: 'Enter PIN',
                  counterText: '',
                  prefixIcon:
                      Icon(Icons.lock_outline, color: AppTheme.textSecondary),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          final amount =
                              double.tryParse(amountController.text.trim());
                          if (amount == null || amount <= 0) {
                            setModalState(() => error = 'Enter valid amount');
                            return;
                          }
                          if (pinController.text.length != 4) {
                            setModalState(() => error = 'Enter 4-digit PIN');
                            return;
                          }
                          setModalState(() {
                            isLoading = true;
                            error = null;
                          });
                          try {
                            await ApiService.deposit(
                              amount: amount,
                              pin: pinController.text,
                            );
                            Navigator.pop(ctx);
                            _loadData(); // Refresh dashboard
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      '₹${NumberFormat('#,##,###').format(amount)} added!'),
                                  backgroundColor: AppTheme.success,
                                ),
                              );
                            }
                          } catch (e) {
                            setModalState(() {
                              isLoading = false;
                              error = 'Failed. Check PIN and try again.';
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.success,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Add Money',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _logout() async {
    await ApiService.logout();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Container(
          decoration:
              const BoxDecoration(gradient: AppTheme.backgroundGradient),
          child: const Center(
            child: CircularProgressIndicator(color: AppTheme.accent),
          ),
        ),
      );
    }

    final totalBalance =
        _accounts.fold<double>(0.0, (sum, acc) => sum + acc.balance);

    return Scaffold(
      body: Container(
        decoration:
            const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: RefreshIndicator(
              onRefresh: _loadData,
              color: AppTheme.accent,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // ── Header ──
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: AppTheme.primaryGradient,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: Text(
                            _user?.initials ?? '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hello, ${_user?.fullName.split(' ').first ?? 'User'}',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            Text(
                              _user?.email ?? '',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _logout,
                        icon: const Icon(Icons.logout_rounded,
                            color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // ── Balance Card (Hidden until PIN) ──
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.account_balance_wallet_rounded,
                                color: AppTheme.accent, size: 20),
                            const SizedBox(width: 8),
                            Text('Total Balance',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: AppTheme.textSecondary)),
                            const Spacer(),
                            GestureDetector(
                              onTap: _toggleBalance,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _balanceVisible
                                      ? AppTheme.accent.withOpacity(0.15)
                                      : Colors.white.withOpacity(0.06),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _balanceVisible
                                          ? Icons.visibility_rounded
                                          : Icons.visibility_off_rounded,
                                      color: _balanceVisible
                                          ? AppTheme.accent
                                          : AppTheme.textSecondary,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _balanceVisible ? 'Hide' : 'Show',
                                      style: TextStyle(
                                        color: _balanceVisible
                                            ? AppTheme.accent
                                            : AppTheme.textSecondary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: _balanceVisible
                              ? Text(
                                  _currencyFormat.format(totalBalance),
                                  key: const ValueKey('visible'),
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 36,
                                      ),
                                )
                              : Text(
                                  '₹ • • • • •',
                                  key: const ValueKey('hidden'),
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 36,
                                        color: AppTheme.textSecondary,
                                      ),
                                ),
                        ),
                        if (_accounts.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'A/C: ${_maskAccount(_accounts.first.accountNumber)}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppTheme.textSecondary),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Setup Status Chips ──
                  if (_user != null &&
                      (!_user!.hasPin ||
                          !_user!.isFaceRegistered ||
                          !_user!.hasBankAccount))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (!_user!.hasPin)
                            _SetupChip(
                              label: 'Set PIN',
                              icon: Icons.pin_rounded,
                              color: AppTheme.warning,
                              onTap: () =>
                                  Navigator.pushNamed(context, '/set-pin')
                                      .then((_) => _loadData()),
                            ),
                          if (!_user!.isFaceRegistered)
                            _SetupChip(
                              label: 'Register Face',
                              icon: Icons.face_rounded,
                              color: AppTheme.accent,
                              onTap: () =>
                                  Navigator.pushNamed(context, '/face-capture')
                                      .then((_) => _loadData()),
                            ),
                          if (!_user!.hasBankAccount)
                            _SetupChip(
                              label: 'Add Bank',
                              icon: Icons.account_balance_rounded,
                              color: AppTheme.primary,
                              onTap: () =>
                                  Navigator.pushNamed(context, '/bank-setup')
                                      .then((_) => _loadData()),
                            ),
                        ],
                      ),
                    ),

                  // ── Quick Actions Grid ──
                  GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.0,
                    children: [
                      _QuickAction(
                        icon: Icons.send_rounded,
                        label: 'Send',
                        gradient: AppTheme.primaryGradient,
                        onTap: () async {
                          final result = await Navigator.pushNamed(
                              context, '/send-money');
                          if (result == true) _loadData();
                        },
                      ),
                      _QuickAction(
                        icon: Icons.add_circle_outline_rounded,
                        label: 'Add Money',
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00E676), Color(0xFF00C853)],
                        ),
                        onTap: _showDepositDialog,
                      ),
                      _QuickAction(
                        icon: Icons.qr_code_scanner_rounded,
                        label: 'QR Pay',
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF6D00), Color(0xFFFF9100)],
                        ),
                        onTap: () async {
                          final result = await Navigator.pushNamed(
                              context, '/qr-payment');
                          if (result == true) _loadData();
                        },
                      ),
                      _QuickAction(
                        icon: Icons.request_page_rounded,
                        label: 'Request',
                        gradient: const LinearGradient(
                          colors: [Color(0xFFE040FB), Color(0xFFAA00FF)],
                        ),
                        onTap: () => Navigator.pushNamed(context, '/request-money'),
                      ),
                      _QuickAction(
                        icon: Icons.analytics_rounded,
                        label: 'Analytics',
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00BCD4), Color(0xFF0097A7)],
                        ),
                        onTap: () =>
                            Navigator.pushNamed(context, '/analytics'),
                      ),
                      _QuickAction(
                        icon: Icons.history_rounded,
                        label: 'History',
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6C63FF), Color(0xFF4834D4)],
                        ),
                        onTap: () =>
                            Navigator.pushNamed(context, '/transaction-history'),
                      ),
                      _QuickAction(
                        icon: Icons.people_rounded,
                        label: 'Contacts',
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFAB40), Color(0xFFFF6D00)],
                        ),
                        onTap: () =>
                            Navigator.pushNamed(context, '/beneficiaries'),
                      ),
                      _QuickAction(
                        icon: Icons.person_rounded,
                        label: 'Profile',
                        gradient: const LinearGradient(
                          colors: [Color(0xFF26C6DA), Color(0xFF00838F)],
                        ),
                        onTap: () =>
                            Navigator.pushNamed(context, '/profile'),
                      ),
                      _QuickAction(
                        icon: Icons.settings_rounded,
                        label: 'Settings',
                        gradient: const LinearGradient(
                          colors: [Color(0xFF9C27B0), Color(0xFF7B1FA2)],
                        ),
                        onTap: () =>
                            Navigator.pushNamed(context, '/settings')
                                .then((_) => _loadData()),
                      ),
                    ],
                  ),

                  // Admin button
                  if (_user?.role == 'ADMIN') ...[
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () => Navigator.pushNamed(context, '/admin'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 14, horizontal: 16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFD32F2F), Color(0xFFB71C1C)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.admin_panel_settings_rounded,
                                color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text('Admin Panel',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // ── Recent Transactions ──
                  Text('Recent Transactions',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),

                  if (_recentTxns.isEmpty)
                    GlassCard(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              Icon(Icons.receipt_long_rounded,
                                  color:
                                      AppTheme.textSecondary.withOpacity(0.5),
                                  size: 48),
                              const SizedBox(height: 12),
                              Text('No transactions yet',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                          color: AppTheme.textSecondary)),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    ...(_recentTxns.map((txn) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: GlassCard(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            child: Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: txn.status == 'SUCCESS'
                                        ? AppTheme.success.withOpacity(0.15)
                                        : AppTheme.error.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: Text(txn.modeIcon,
                                        style: const TextStyle(fontSize: 20)),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              txn.toAccountIdentifier,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppTheme.accent
                                                  .withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              txn.paymentMode,
                                              style: const TextStyle(
                                                color: AppTheme.accent,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        DateFormat('dd MMM, hh:mm a')
                                            .format(txn.createdAt.toLocal()),
                                        style: TextStyle(
                                          color: AppTheme.textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${txn.isCredit ? '+' : '-'} ${_currencyFormat.format(txn.amount)}',
                                      style: TextStyle(
                                        color: txn.isCredit
                                            ? AppTheme.success
                                            : AppTheme.error,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    Text(
                                      txn.directionLabel,
                                      style: TextStyle(
                                        color: txn.isCredit
                                            ? AppTheme.success.withOpacity(0.7)
                                            : AppTheme.textSecondary,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _maskAccount(String acc) {
    if (acc.length <= 4) return acc;
    return '••••${acc.substring(acc.length - 4)}';
  }
}

// ── Setup Chip ──────────────────────────────────────────────────────────────
class _SetupChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _SetupChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            Icon(Icons.arrow_forward_rounded, color: color, size: 14),
          ],
        ),
      ),
    );
  }
}

// ── Quick Action Grid Button ────────────────────────────────────────────────
class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Gradient gradient;
  final VoidCallback onTap;

  const _QuickAction({
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
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(height: 8),
            Text(label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                )),
          ],
        ),
      ),
    );
  }
}
