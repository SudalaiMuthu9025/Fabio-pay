/// Fabio — Spending Analytics Screen
///
/// Premium charts showing weekly/monthly spending breakdown with
/// bar charts, summary cards, and animated transitions.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart';

class SpendingAnalyticsScreen extends ConsumerStatefulWidget {
  const SpendingAnalyticsScreen({super.key});

  @override
  ConsumerState<SpendingAnalyticsScreen> createState() =>
      _SpendingAnalyticsScreenState();
}

class _SpendingAnalyticsScreenState
    extends ConsumerState<SpendingAnalyticsScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _data;
  bool _isLoading = true;
  String? _error;
  int _selectedView = 0; // 0 = Weekly, 1 = Monthly

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  final _currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final data = await ApiService.getSpendingSummary();
      if (!mounted) return;
      setState(() {
        _data = data;
        _isLoading = false;
      });
      _animController.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load analytics';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Spending Analytics'),
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
                          const Icon(Icons.analytics_outlined,
                              color: AppTheme.textSecondary, size: 64),
                          const SizedBox(height: 16),
                          Text(_error!,
                              style:
                                  const TextStyle(color: AppTheme.textSecondary)),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _isLoading = true;
                                _error = null;
                              });
                              _loadData();
                            },
                            child: const Text('Retry',
                                style: TextStyle(color: AppTheme.accent)),
                          ),
                        ],
                      ),
                    )
                  : FadeTransition(
                      opacity: _fadeAnim,
                      child: RefreshIndicator(
                        onRefresh: _loadData,
                        color: AppTheme.accent,
                        child: ListView(
                          padding: const EdgeInsets.all(20),
                          children: [
                            // ── Summary Cards ──
                            Row(
                              children: [
                                Expanded(
                                  child: _SummaryCard(
                                    title: 'Total Sent',
                                    amount: _parseDecimal(
                                        _data?['total_sent']),
                                    icon: Icons.arrow_upward_rounded,
                                    color: AppTheme.error,
                                    format: _currencyFormat,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _SummaryCard(
                                    title: 'Total Received',
                                    amount: _parseDecimal(
                                        _data?['total_received']),
                                    icon: Icons.arrow_downward_rounded,
                                    color: AppTheme.success,
                                    format: _currencyFormat,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Net balance card
                            GlassCard(
                              child: Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color:
                                          AppTheme.accent.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: const Icon(
                                        Icons.swap_vert_rounded,
                                        color: AppTheme.accent,
                                        size: 24),
                                  ),
                                  const SizedBox(width: 14),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text('Net Flow',
                                          style: TextStyle(
                                              color: AppTheme.textSecondary,
                                              fontSize: 12)),
                                      Text(
                                        _currencyFormat.format(
                                          _parseDecimal(
                                                  _data?['total_received']) -
                                              _parseDecimal(
                                                  _data?['total_sent']),
                                        ),
                                        style: TextStyle(
                                          color: _parseDecimal(
                                                      _data?[
                                                          'total_received']) >=
                                                  _parseDecimal(
                                                      _data?['total_sent'])
                                              ? AppTheme.success
                                              : AppTheme.error,
                                          fontSize: 20,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            // ── View Toggle ──
                            GlassCard(
                              padding: const EdgeInsets.all(4),
                              child: Row(
                                children: [
                                  _ViewTab(
                                    label: 'Weekly',
                                    selected: _selectedView == 0,
                                    onTap: () =>
                                        setState(() => _selectedView = 0),
                                  ),
                                  _ViewTab(
                                    label: 'Monthly',
                                    selected: _selectedView == 1,
                                    onTap: () =>
                                        setState(() => _selectedView = 1),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

                            // ── Chart ──
                            GlassCard(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedView == 0
                                        ? 'Last 7 Days'
                                        : 'Last 6 Months',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  const SizedBox(height: 20),
                                  SizedBox(
                                    height: 220,
                                    child: _selectedView == 0
                                        ? _buildWeeklyChart()
                                        : _buildMonthlyChart(),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // ── Legend ──
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _Legend(
                                    color: AppTheme.error, label: 'Sent'),
                                const SizedBox(width: 24),
                                _Legend(
                                    color: AppTheme.success,
                                    label: 'Received'),
                              ],
                            ),
                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
                    ),
        ),
      ),
    );
  }

  Widget _buildWeeklyChart() {
    final weekly = (_data?['weekly'] as List?) ?? [];
    if (weekly.isEmpty) {
      return const Center(
        child: Text('No data yet',
            style: TextStyle(color: AppTheme.textSecondary)),
      );
    }

    final maxVal = weekly.fold<double>(0, (prev, d) {
      final sent = _parseDecimal(d['sent']);
      final received = _parseDecimal(d['received']);
      final m = sent > received ? sent : received;
      return m > prev ? m : prev;
    });

    return BarChart(
      BarChartData(
        maxY: maxVal > 0 ? maxVal * 1.2 : 1000,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final label = rodIndex == 0 ? 'Sent' : 'Received';
              return BarTooltipItem(
                '$label\n${_currencyFormat.format(rod.toY)}',
                const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= weekly.length) return const Text('');
                final date = weekly[value.toInt()]['date'] ?? '';
                final day = date.length >= 10
                    ? DateFormat('E')
                        .format(DateTime.tryParse(date) ?? DateTime.now())
                    : '';
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(day,
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11)),
                );
              },
            ),
          ),
          leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxVal > 0 ? maxVal / 4 : 250,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.white.withValues(alpha: 0.05),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(weekly.length, (i) {
          final sent = _parseDecimal(weekly[i]['sent']);
          final received = _parseDecimal(weekly[i]['received']);
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: sent,
                color: AppTheme.error,
                width: 8,
                borderRadius: BorderRadius.circular(4),
              ),
              BarChartRodData(
                toY: received,
                color: AppTheme.success,
                width: 8,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
            barsSpace: 4,
          );
        }),
      ),
    );
  }

  Widget _buildMonthlyChart() {
    final monthly = (_data?['monthly'] as List?) ?? [];
    if (monthly.isEmpty) {
      return const Center(
        child: Text('No data yet',
            style: TextStyle(color: AppTheme.textSecondary)),
      );
    }

    final maxVal = monthly.fold<double>(0, (prev, d) {
      final sent = _parseDecimal(d['sent']);
      final received = _parseDecimal(d['received']);
      final m = sent > received ? sent : received;
      return m > prev ? m : prev;
    });

    return BarChart(
      BarChartData(
        maxY: maxVal > 0 ? maxVal * 1.2 : 1000,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final label = rodIndex == 0 ? 'Sent' : 'Received';
              return BarTooltipItem(
                '$label\n${_currencyFormat.format(rod.toY)}',
                const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= monthly.length) return const Text('');
                final month = monthly[value.toInt()]['month'] ?? '';
                final label = month.length >= 7
                    ? DateFormat('MMM').format(
                        DateTime.tryParse('$month-01') ?? DateTime.now())
                    : month;
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(label,
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11)),
                );
              },
            ),
          ),
          leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxVal > 0 ? maxVal / 4 : 250,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.white.withValues(alpha: 0.05),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(monthly.length, (i) {
          final sent = _parseDecimal(monthly[i]['sent']);
          final received = _parseDecimal(monthly[i]['received']);
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: sent,
                color: AppTheme.error,
                width: 14,
                borderRadius: BorderRadius.circular(4),
              ),
              BarChartRodData(
                toY: received,
                color: AppTheme.success,
                width: 14,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
            barsSpace: 4,
          );
        }),
      ),
    );
  }

  double _parseDecimal(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }
}

// ── Summary Card ─────────────────────────────────────────────────────────────
class _SummaryCard extends StatelessWidget {
  final String title;
  final double amount;
  final IconData icon;
  final Color color;
  final NumberFormat format;

  const _SummaryCard({
    required this.title,
    required this.amount,
    required this.icon,
    required this.color,
    required this.format,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            format.format(amount),
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ── View Tab ─────────────────────────────────────────────────────────────────
class _ViewTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ViewTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: selected ? AppTheme.primaryGradient : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : AppTheme.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Legend ────────────────────────────────────────────────────────────────────
class _Legend extends StatelessWidget {
  final Color color;
  final String label;

  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 12)),
      ],
    );
  }
}
