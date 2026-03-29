/// Fabio — Settings Screen
///
/// View/update security threshold, biometric toggle, and account info.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/fab_button.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  SecuritySettings? _settings;
  User? _user;
  bool _isLoading = true;
  final _thresholdController = TextEditingController();
  final _currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        ApiService.getSecuritySettings(),
        ApiService.getMe(),
      ]);
      if (!mounted) return;
      setState(() {
        _settings = results[0] as SecuritySettings;
        _user = results[1] as User;
        _thresholdController.text = _settings!.thresholdAmount.toStringAsFixed(0);
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveThreshold() async {
    final amount = double.tryParse(_thresholdController.text);
    if (amount == null || amount <= 0) return;

    setState(() => _isSaving = true);
    try {
      final updated = await ApiService.updateThreshold(amount);
      if (!mounted) return;
      setState(() => _settings = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Threshold updated'),
          backgroundColor: AppTheme.success,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update'),
          backgroundColor: AppTheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _thresholdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Security Settings'),
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
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // ── User Info ────────────────────────────
                  GlassCard(
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            gradient: AppTheme.primaryGradient,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: Text(
                              (_user?.fullName ?? 'U')[0].toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _user?.fullName ?? '',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                _user?.email ?? '',
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _user?.role.toUpperCase() ?? '',
                            style: const TextStyle(
                              color: AppTheme.accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Threshold Setting ─────────────────────
                  Text('Liveness Threshold',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Transfers above this amount will require Active Liveness verification instead of PIN.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 14),
                  GlassCard(
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.warning.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.shield_outlined,
                                  color: AppTheme.warning, size: 22),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Text(
                                'Current Threshold',
                                style: TextStyle(color: AppTheme.textSecondary),
                              ),
                            ),
                            Text(
                              _currencyFormat
                                  .format(_settings?.thresholdAmount ?? 0),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: _thresholdController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            hintText: 'New threshold amount',
                            prefixIcon: Icon(Icons.currency_rupee,
                                color: AppTheme.textSecondary),
                          ),
                        ),
                        const SizedBox(height: 16),
                        FabButton(
                          label: 'Update Threshold',
                          onPressed: _saveThreshold,
                          isLoading: _isSaving,
                          icon: Icons.save_rounded,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Security Status ───────────────────────
                  Text('Security Status',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 14),
                  _buildStatusRow(
                    icon: Icons.fingerprint,
                    label: 'Biometric Verification',
                    value: _settings?.biometricEnabled == true
                        ? 'Enabled'
                        : 'Disabled',
                    color: _settings?.biometricEnabled == true
                        ? AppTheme.success
                        : AppTheme.error,
                  ),
                  const SizedBox(height: 10),
                  _buildStatusRow(
                    icon: Icons.error_outline,
                    label: 'Failed Attempts',
                    value: '${_settings?.failedAttempts ?? 0} / ${_settings?.maxAttempts ?? 5}',
                    color: (_settings?.failedAttempts ?? 0) > 3
                        ? AppTheme.error
                        : AppTheme.success,
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildStatusRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Text(label,
                style: const TextStyle(color: AppTheme.textSecondary)),
          ),
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
