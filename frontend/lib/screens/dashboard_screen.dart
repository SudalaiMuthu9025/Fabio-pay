/// Fabio — Dashboard Screen
///
/// Account balance cards, recent transactions, quick-transfer FAB, and logout.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    await AuthService.deleteToken();
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
                        const SizedBox(height: 28),
                        _buildTransactionsSection(),
                      ],
                    ),
                  ),
                ),
        ),
      ),
      floatingActionButton: _isLoading
          ? null
          : Container(
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withOpacity(0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: FloatingActionButton.extended(
                onPressed: () => Navigator.pushNamed(context, '/transfer'),
                backgroundColor: Colors.transparent,
                elevation: 0,
                icon: const Icon(Icons.send_rounded, color: Colors.white),
                label: const Text('Transfer',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
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
            ),
          ],
        ),
        Row(
          children: [
            IconButton(
              onPressed: () => Navigator.pushNamed(context, '/settings'),
              icon: const Icon(Icons.settings_outlined,
                  color: AppTheme.textSecondary),
            ),
            IconButton(
              onPressed: _logout,
              icon: const Icon(Icons.logout_rounded,
                  color: AppTheme.textSecondary),
            ),
          ],
        ),
      ],
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
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {},
              child: const Text('Add Account',
                  style: TextStyle(color: AppTheme.accent)),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 140,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _accounts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
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
                color: index == 0
                    ? Colors.transparent
                    : AppTheme.border,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(acc.bankName,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13)),
                    if (acc.isPrimary)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('PRIMARY',
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                      ),
                  ],
                ),
                Text(acc.maskedNumber,
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        letterSpacing: 2)),
                Text(
                  _currencyFormat.format(acc.balance),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          );
        },
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
              child: Text('No transactions yet',
                  style: TextStyle(color: AppTheme.textSecondary)),
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
                                color: Colors.white,
                                fontWeight: FontWeight.w500),
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
}
