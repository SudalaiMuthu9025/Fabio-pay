/// Fabio — Transaction History Screen
///
/// Displays all past transactions with status, amount, and date.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart';

class TransactionHistoryScreen extends ConsumerStatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  ConsumerState<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState
    extends ConsumerState<TransactionHistoryScreen> {
  List<TransactionModel> _transactions = [];
  bool _isLoading = true;
  String? _error;

  final _currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final txns = await ApiService.getTransactionHistory();
      if (!mounted) return;
      setState(() {
        _transactions = txns;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load transaction history.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction History'),
        backgroundColor: Colors.transparent,
        elevation: 0,
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
                          const SizedBox(height: 16),
                          TextButton(
                            onPressed: _loadHistory,
                            child: const Text('Retry',
                                style: TextStyle(color: AppTheme.accent)),
                          ),
                        ],
                      ),
                    )
                  : _transactions.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.receipt_long_rounded,
                                  color:
                                      AppTheme.textSecondary.withOpacity(0.4),
                                  size: 64),
                              const SizedBox(height: 16),
                              Text('No transactions yet',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        color: AppTheme.textSecondary,
                                      )),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadHistory,
                          color: AppTheme.accent,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(20),
                            itemCount: _transactions.length,
                            itemBuilder: (context, index) {
                              final txn = _transactions[index];
                              return _TransactionCard(
                                transaction: txn,
                                currencyFormat: _currencyFormat,
                              );
                            },
                          ),
                        ),
        ),
      ),
    );
  }
}

class _TransactionCard extends StatelessWidget {
  final TransactionModel transaction;
  final NumberFormat currencyFormat;

  const _TransactionCard({
    required this.transaction,
    required this.currencyFormat,
  });

  @override
  Widget build(BuildContext context) {
    final isSuccess = transaction.status == 'success';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        child: Row(
          children: [
            // Status icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: (isSuccess ? AppTheme.success : AppTheme.error)
                    .withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                isSuccess
                    ? Icons.arrow_upward_rounded
                    : Icons.close_rounded,
                color: isSuccess ? AppTheme.success : AppTheme.error,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),

            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'To: ${transaction.toAccountIdentifier}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      // Auth method badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: transaction.authMethod == 'biometric'
                              ? AppTheme.accent.withOpacity(0.2)
                              : AppTheme.textSecondary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          transaction.authMethod == 'biometric'
                              ? '🔒 Biometric'
                              : '🔑 PIN',
                          style: TextStyle(
                            color: transaction.authMethod == 'biometric'
                                ? AppTheme.accent
                                : AppTheme.textSecondary,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        DateFormat('dd MMM yyyy, hh:mm a')
                            .format(transaction.createdAt.toLocal()),
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  if (transaction.description != null &&
                      transaction.description!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      transaction.description!,
                      style: TextStyle(
                        color: AppTheme.textSecondary.withOpacity(0.7),
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),

            // Amount
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '- ${currencyFormat.format(transaction.amount)}',
                  style: TextStyle(
                    color: isSuccess ? AppTheme.success : AppTheme.error,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: (isSuccess ? AppTheme.success : AppTheme.error)
                        .withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    transaction.status.toUpperCase(),
                    style: TextStyle(
                      color: isSuccess ? AppTheme.success : AppTheme.error,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
