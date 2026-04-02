/// Fabio — Dashboard Screen
///
/// Account balance cards, quick action buttons, recent transactions, and logout.
/// Simple button-based navigation — no complex flows.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';
import '../config/theme.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  User? _user;
  List<BankAccount> _accounts = [];
  List<TransactionLog> _transactions = [];
  bool _isLoading = true;

  late AnimationController _fadeController;

  final _currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        ApiService.getMe(),
        ApiService.getAccounts(),
        ApiService.getTransactions(),
      ]);
      if (!mounted) return;
      setState(() {
        _user = results[0] as User;
        _accounts = results[1] as List<BankAccount>;
        _transactions = results[2] as List<TransactionLog>;
        _isLoading = false;
      });
      _fadeController.forward();
    } catch (e) {
      if (mounted) {
        // Check if session expired (401)
        if (e is DioException && e.response?.statusCode == 401) {
          await ApiService.logout();
          if (!mounted) return;
          Navigator.pushReplacementNamed(context, '/login');
          return;
        }
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load data: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _logout() async {
    await ApiService.logout();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  double get _totalBalance =>
      _accounts.fold(0.0, (sum, a) => sum + a.balance);

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: SafeArea(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.accent))
              : FadeTransition(
                  opacity: _fadeController,
                  child: RefreshIndicator(
                    onRefresh: _loadData,
                    color: AppTheme.accent,
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        _buildHeader(),
                        const SizedBox(height: 24),
                        _buildTotalBalance(),
                        const SizedBox(height: 20),
                        _buildAccountCards(),
                        const SizedBox(height: 24),
                        _buildQuickActions(),
                        const SizedBox(height: 28),
                        _buildTransactionsSection(),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hello,',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontSize: 16)),
              Text(
                _user?.fullName ?? 'User',
                style: Theme.of(context).textTheme.headlineMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Row(
          children: [
            // Settings button
            _headerButton(Icons.settings_outlined, () {
              Navigator.pushNamed(context, '/settings');
            }),
            const SizedBox(width: 4),
            // Logout button
            _headerButton(Icons.logout_rounded, _logout),
          ],
        ),
      ],
    );
  }

  Widget _headerButton(IconData icon, VoidCallback onPressed) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: AppTheme.textSecondary, size: 22),
        padding: const EdgeInsets.all(10),
        constraints: const BoxConstraints(),
      ),
    );
  }

  Widget _buildTotalBalance() {
    return GlassCard(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.account_balance_wallet_rounded,
                    color: AppTheme.accent, size: 22),
              ),
              const SizedBox(width: 12),
              const Text('Total Balance',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _currencyFormat.format(_totalBalance),
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${_accounts.length} account${_accounts.length != 1 ? 's' : ''} linked',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCards() {
    if (_accounts.isEmpty) {
      return GlassCard(
        child: Column(
          children: [
            const Icon(Icons.account_balance_outlined,
                color: AppTheme.textSecondary, size: 40),
            const SizedBox(height: 12),
            const Text('No accounts linked',
                style: TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _showAddAccountDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Account'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 140,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _accounts.length + 1, // +1 for "Add" card
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          if (index == _accounts.length) {
            // "Add Account" card
            return GestureDetector(
              onTap: _showAddAccountDialog,
              child: Container(
                width: 100,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceCard,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppTheme.border),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_circle_outline, color: AppTheme.accent, size: 32),
                    SizedBox(height: 8),
                    Text('Add', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                  ],
                ),
              ),
            );
          }
          final acc = _accounts[index];
          return Container(
            width: 220,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: index == 0
                  ? AppTheme.primaryGradient
                  : AppTheme.cardGradient,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: index == 0 ? Colors.transparent : AppTheme.border,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(acc.bankName,
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (acc.isPrimary)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('PRIMARY',
                            style: TextStyle(
                                fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white)),
                      ),
                  ],
                ),
                Text(acc.maskedNumber,
                    style: const TextStyle(color: Colors.white70, fontSize: 14, letterSpacing: 2)),
                Text(
                  _currencyFormat.format(acc.balance),
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Simple grid of action buttons — easy to use
  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick Actions', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 14),
        Row(
          children: [
            _actionButton(
              icon: Icons.send_rounded,
              label: 'Transfer',
              color: AppTheme.primary,
              onTap: () => Navigator.pushNamed(context, '/transfer'),
            ),
            const SizedBox(width: 12),
            _actionButton(
              icon: Icons.add_card_rounded,
              label: 'Add Account',
              color: AppTheme.accent,
              onTap: _showAddAccountDialog,
            ),
            const SizedBox(width: 12),
            _actionButton(
              icon: Icons.fingerprint_rounded,
              label: 'Liveness',
              color: AppTheme.success,
              onTap: () => Navigator.pushNamed(context, '/liveness'),
            ),
            const SizedBox(width: 12),
            _actionButton(
              icon: Icons.shield_outlined,
              label: 'Security',
              color: AppTheme.warning,
              onTap: () => Navigator.pushNamed(context, '/settings'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(height: 8),
              Text(label,
                  style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Recent Transactions',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 14),
        if (_transactions.isEmpty)
          const GlassCard(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('No transactions yet',
                    style: TextStyle(color: AppTheme.textSecondary)),
              ),
            ),
          )
        else
          ..._transactions.take(10).map((txn) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: txn.status == 'success'
                            ? AppTheme.success.withOpacity(0.15)
                            : txn.status == 'pending'
                                ? AppTheme.warning.withOpacity(0.15)
                                : AppTheme.error.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        txn.status == 'success'
                            ? Icons.check_circle_outline
                            : txn.status == 'pending'
                                ? Icons.schedule
                                : Icons.error_outline,
                        color: txn.status == 'success'
                            ? AppTheme.success
                            : txn.status == 'pending'
                                ? AppTheme.warning
                                : AppTheme.error,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            txn.description ?? 'Transfer',
                            style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${txn.authMethod.toUpperCase()} · ${DateFormat.MMMd().format(txn.createdAt)}',
                            style: const TextStyle(
                                color: AppTheme.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '-${_currencyFormat.format(txn.amount)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              )),
      ],
    );
  }

  // ── Add Account Dialog ──────────────────────────────────────────────────
  void _showAddAccountDialog() {
    final numberController = TextEditingController();
    final bankController = TextEditingController();
    final balanceController = TextEditingController(text: '0');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Add Bank Account', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: numberController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Account Number',
                  prefixIcon: Icon(Icons.numbers, color: AppTheme.textSecondary),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bankController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Bank Name',
                  prefixIcon: Icon(Icons.account_balance, color: AppTheme.textSecondary),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: balanceController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Initial Balance',
                  prefixIcon: Icon(Icons.currency_rupee, color: AppTheme.textSecondary),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (numberController.text.length < 8 || bankController.text.length < 2) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Fill all fields correctly'), backgroundColor: AppTheme.error),
                );
                return;
              }
              try {
                await ApiService.createAccount(
                  accountNumber: numberController.text.trim(),
                  bankName: bankController.text.trim(),
                  balance: double.tryParse(balanceController.text) ?? 0,
                );
                Navigator.pop(ctx);
                _loadData();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Account added!'), backgroundColor: AppTheme.success),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed: $e'), backgroundColor: AppTheme.error),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}
