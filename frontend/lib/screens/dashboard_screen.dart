/// Fabio — Dashboard Screen
///
/// Shows balance, user info, quick actions (Send Money, History).

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
      });
      _fadeController.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
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
          decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
          child: const Center(
            child: CircularProgressIndicator(color: AppTheme.accent),
          ),
        ),
      );
    }

    final totalBalance = _accounts.fold<double>(
        0.0, (sum, acc) => sum + acc.balance);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
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
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
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

                  // ── Balance Card ──
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
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: AppTheme.textSecondary,
                                    )),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _currencyFormat.format(totalBalance),
                          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 36,
                              ),
                        ),
                        if (_accounts.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'A/C: ${_accounts.first.accountNumber}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Quick Actions ──
                  Row(
                    children: [
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.send_rounded,
                          label: 'Send Money',
                          gradient: AppTheme.primaryGradient,
                          onTap: () => Navigator.pushNamed(context, '/send-money'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.history_rounded,
                          label: 'History',
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6C63FF), Color(0xFF4834D4)],
                          ),
                          onTap: () => Navigator.pushNamed(context, '/transaction-history'),
                        ),
                      ),
                    ],
                  ),
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
                                  color: AppTheme.textSecondary.withOpacity(0.5),
                                  size: 48),
                              const SizedBox(height: 12),
                              Text('No transactions yet',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: AppTheme.textSecondary,
                                      )),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    ...(_recentTxns.map((txn) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: GlassCard(
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: txn.status == 'success'
                                        ? AppTheme.success.withOpacity(0.15)
                                        : AppTheme.error.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    txn.status == 'success'
                                        ? Icons.arrow_upward_rounded
                                        : Icons.close_rounded,
                                    color: txn.status == 'success'
                                        ? AppTheme.success
                                        : AppTheme.error,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'To: ${txn.toAccountIdentifier}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
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
                                Text(
                                  '- ${_currencyFormat.format(txn.amount)}',
                                  style: TextStyle(
                                    color: txn.status == 'success'
                                        ? AppTheme.success
                                        : AppTheme.error,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
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
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Gradient gradient;
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
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(height: 8),
            Text(label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                )),
          ],
        ),
      ),
    );
  }
}
