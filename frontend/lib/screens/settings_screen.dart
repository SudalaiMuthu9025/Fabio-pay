/// Fabio — Settings Screen
///
/// Simple button-based settings: threshold, biometric toggle, PIN change,
/// active sessions list, and profile info.

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
  List<SessionInfo> _sessions = [];
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
        ApiService.getSessions(),
      ]);
      if (!mounted) return;
      setState(() {
        _settings = results[0] as SecuritySettings;
        _user = results[1] as User;
        _sessions = results[2] as List<SessionInfo>;
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
      final updated = await ApiService.updateSecurity(thresholdAmount: amount);
      if (!mounted) return;
      setState(() => _settings = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Threshold updated'), backgroundColor: AppTheme.success),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update'), backgroundColor: AppTheme.error),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _toggleBiometric() async {
    final newVal = !(_settings?.biometricEnabled ?? false);
    try {
      final updated = await ApiService.updateSecurity(biometricEnabled: newVal);
      if (!mounted) return;
      setState(() => _settings = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Biometric ${newVal ? "enabled" : "disabled"}'),
          backgroundColor: AppTheme.success,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed'), backgroundColor: AppTheme.error),
      );
    }
  }

  void _showChangePinDialog() {
    final pinController = TextEditingController();
    final confirmController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Change PIN', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              style: const TextStyle(color: Colors.white, fontSize: 20, letterSpacing: 8),
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                hintText: 'New PIN',
                counterText: '',
                prefixIcon: Icon(Icons.pin_outlined, color: AppTheme.textSecondary),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              style: const TextStyle(color: Colors.white, fontSize: 20, letterSpacing: 8),
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                hintText: 'Confirm PIN',
                counterText: '',
                prefixIcon: Icon(Icons.pin_outlined, color: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (pinController.text.length < 4) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('PIN must be 4-6 digits'), backgroundColor: AppTheme.error),
                );
                return;
              }
              if (pinController.text != confirmController.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('PINs do not match'), backgroundColor: AppTheme.error),
                );
                return;
              }
              try {
                await ApiService.updateSecurity(pin: pinController.text);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('PIN updated'), backgroundColor: AppTheme.success),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Failed to update PIN'), backgroundColor: AppTheme.error),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  Future<void> _revokeSession(String sessionId) async {
    try {
      await ApiService.revokeSession(sessionId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session revoked'), backgroundColor: AppTheme.success),
      );
      _loadData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to revoke'), backgroundColor: AppTheme.error),
      );
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
        title: const Text('Settings & Security'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // ── User Info Card ──────────────────────────────
                  GlassCard(
                    child: Row(
                      children: [
                        Container(
                          width: 52, height: 52,
                          decoration: BoxDecoration(
                            gradient: AppTheme.primaryGradient,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: _user?.avatarUrl != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Image.network(_user!.avatarUrl!, fit: BoxFit.cover),
                                )
                              : Center(
                                  child: Text(
                                    _user?.initials ?? '?',
                                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_user?.fullName ?? '', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                              Text(_user?.email ?? '', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            (_user?.role ?? '').toUpperCase().replaceAll('_', ' '),
                            style: const TextStyle(color: AppTheme.accent, fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_user?.googleId != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.success.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.success.withOpacity(0.2)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.check_circle, color: AppTheme.success, size: 16),
                          SizedBox(width: 8),
                          Text('Google Account Connected', style: TextStyle(color: AppTheme.success, fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),

                  // ── Quick Action Buttons ──────────────────────────
                  Text('Security Actions', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 14),

                  // Biometric Toggle Button
                  _settingsButton(
                    icon: Icons.fingerprint,
                    label: 'Biometric Verification',
                    subtitle: _settings?.biometricEnabled == true ? 'Enabled — tap to disable' : 'Disabled — tap to enable',
                    color: _settings?.biometricEnabled == true ? AppTheme.success : AppTheme.error,
                    onTap: _toggleBiometric,
                  ),
                  const SizedBox(height: 10),

                  // Change PIN Button
                  _settingsButton(
                    icon: Icons.pin_outlined,
                    label: 'Change Transaction PIN',
                    subtitle: 'Update your 4-6 digit PIN',
                    color: AppTheme.accent,
                    onTap: _showChangePinDialog,
                  ),
                  const SizedBox(height: 10),

                  // Test Liveness Button
                  _settingsButton(
                    icon: Icons.face_retouching_natural,
                    label: 'Test Liveness Verification',
                    subtitle: 'Run a face liveness test',
                    color: AppTheme.primary,
                    onTap: () => Navigator.pushNamed(context, '/liveness'),
                  ),
                  const SizedBox(height: 10),

                  // Face Registration Button
                  _settingsButton(
                    icon: Icons.face_unlock_rounded,
                    label: _user?.isFaceRegistered == true
                        ? 'Update Face Data'
                        : 'Register Face',
                    subtitle: _user?.isFaceRegistered == true
                        ? 'Face registered ✓ — tap to update'
                        : 'Required for biometric transactions',
                    color: _user?.isFaceRegistered == true
                        ? AppTheme.success
                        : AppTheme.warning,
                    onTap: () async {
                      final result = await Navigator.pushNamed(
                          context, '/face-register');
                      if (result == true) _loadData(); // Refresh status
                    },
                  ),
                  const SizedBox(height: 24),

                  // ── Threshold Setting ──────────────────────────────
                  Text('Liveness Threshold', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Transfers above this amount require biometric verification instead of PIN.',
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
                              child: const Icon(Icons.shield_outlined, color: AppTheme.warning, size: 22),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Text('Current Threshold', style: TextStyle(color: AppTheme.textSecondary)),
                            ),
                            Text(
                              _currencyFormat.format(_settings?.thresholdAmount ?? 0),
                              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
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
                            prefixIcon: Icon(Icons.currency_rupee, color: AppTheme.textSecondary),
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

                  // ── Security Status ──────────────────────────────
                  Text('Security Status', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 14),
                  _buildStatusRow(
                    icon: Icons.face_unlock_rounded,
                    label: 'Face Data',
                    value: _user?.isFaceRegistered == true ? 'Registered' : 'Not Registered',
                    color: _user?.isFaceRegistered == true ? AppTheme.success : AppTheme.warning,
                  ),
                  const SizedBox(height: 10),
                  _buildStatusRow(
                    icon: Icons.fingerprint,
                    label: 'Biometric',
                    value: _settings?.biometricEnabled == true ? 'Enabled' : 'Disabled',
                    color: _settings?.biometricEnabled == true ? AppTheme.success : AppTheme.error,
                  ),
                  const SizedBox(height: 10),
                  _buildStatusRow(
                    icon: Icons.error_outline,
                    label: 'Failed Attempts',
                    value: '${_settings?.failedAttempts ?? 0} / ${_settings?.maxAttempts ?? 5}',
                    color: (_settings?.failedAttempts ?? 0) > 3 ? AppTheme.error : AppTheme.success,
                  ),
                  const SizedBox(height: 10),
                  _buildStatusRow(
                    icon: Icons.lock_clock,
                    label: 'Lockout Duration',
                    value: '${_settings?.lockoutDurationMinutes ?? 30} min',
                    color: AppTheme.textSecondary,
                  ),
                  const SizedBox(height: 24),

                  // ── Active Sessions ──────────────────────────────
                  Text('Active Sessions', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text('${_sessions.length} active session(s)',
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 14),
                  ..._sessions.map((s) => Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceCard,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.devices, color: AppTheme.textSecondary, size: 22),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.ipAddress ?? 'Unknown IP',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 14),
                              ),
                              Text(
                                'Created: ${DateFormat.MMMd().add_jm().format(s.createdAt)}',
                                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => _revokeSession(s.id),
                          icon: const Icon(Icons.close, color: AppTheme.error, size: 20),
                          tooltip: 'Revoke',
                        ),
                      ],
                    ),
                  )),
                ],
              ),
      ),
    );
  }

  Widget _settingsButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
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
            child: Text(label, style: const TextStyle(color: AppTheme.textSecondary)),
          ),
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
