/// Fabio — Settings Screen
///
/// Premium settings page with security options, preferences, and about section.
/// Includes: Change Password, Change PIN, Re-register Face, Notifications,
/// App Lock, About, Help, and Logout.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/theme.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/fab_button.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with SingleTickerProviderStateMixin {
  User? _user;
  bool _isLoading = true;
  bool _notificationsEnabled = true;
  bool _appLockEnabled = false;

  late AnimationController _slideCtrl;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    _loadUser();
  }

  Future<void> _loadUser() async {
    try {
      final user = await ApiService.getMe();
      if (!mounted) return;
      setState(() {
        _user = user;
        _isLoading = false;
      });
      _slideCtrl.forward();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  // ── Change Password ─────────────────────────────────────────────────────
  void _showChangePasswordSheet() {
    final currentPwCtrl = TextEditingController();
    final newPwCtrl = TextEditingController();
    final confirmPwCtrl = TextEditingController();
    String? error;
    bool isLoading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.textSecondary.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Row(
                children: [
                  Icon(Icons.lock_rounded, color: AppTheme.accent, size: 22),
                  SizedBox(width: 8),
                  Text('Change Password',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: currentPwCtrl,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Current Password',
                  prefixIcon: Icon(Icons.lock_outline, color: AppTheme.textSecondary),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newPwCtrl,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'New Password (min 8 chars)',
                  prefixIcon: Icon(Icons.lock_rounded, color: AppTheme.textSecondary),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmPwCtrl,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Confirm New Password',
                  prefixIcon: Icon(Icons.lock_rounded, color: AppTheme.textSecondary),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          if (newPwCtrl.text != confirmPwCtrl.text) {
                            setSheetState(() => error = 'Passwords do not match');
                            return;
                          }
                          if (newPwCtrl.text.length < 8) {
                            setSheetState(() => error = 'Minimum 8 characters');
                            return;
                          }
                          setSheetState(() { isLoading = true; error = null; });
                          try {
                            await ApiService.changePassword(
                              currentPassword: currentPwCtrl.text,
                              newPassword: newPwCtrl.text,
                            );
                            Navigator.pop(ctx);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Password changed successfully!'),
                                    backgroundColor: AppTheme.success),
                              );
                            }
                          } catch (_) {
                            setSheetState(() {
                              isLoading = false;
                              error = 'Failed. Check your current password.';
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: isLoading
                      ? const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Update Password',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Change PIN ──────────────────────────────────────────────────────────
  void _showChangePinSheet() {
    final currentPinCtrl = TextEditingController();
    final newPinCtrl = TextEditingController();
    final confirmPinCtrl = TextEditingController();
    String? error;
    bool isLoading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.textSecondary.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Row(
                children: [
                  Icon(Icons.pin_rounded, color: AppTheme.warning, size: 22),
                  SizedBox(width: 8),
                  Text('Change Transaction PIN',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: currentPinCtrl,
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
                style: const TextStyle(color: Colors.white, fontSize: 20, letterSpacing: 8),
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  hintText: 'Current PIN',
                  counterText: '',
                  prefixIcon: Icon(Icons.lock_outline, color: AppTheme.textSecondary),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newPinCtrl,
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
                style: const TextStyle(color: Colors.white, fontSize: 20, letterSpacing: 8),
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  hintText: 'New PIN',
                  counterText: '',
                  prefixIcon: Icon(Icons.pin_rounded, color: AppTheme.textSecondary),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmPinCtrl,
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
                style: const TextStyle(color: Colors.white, fontSize: 20, letterSpacing: 8),
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  hintText: 'Confirm New PIN',
                  counterText: '',
                  prefixIcon: Icon(Icons.pin_rounded, color: AppTheme.textSecondary),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          if (currentPinCtrl.text.length != 4) {
                            setSheetState(() => error = 'Enter 4-digit current PIN');
                            return;
                          }
                          if (newPinCtrl.text.length != 4) {
                            setSheetState(() => error = 'New PIN must be 4 digits');
                            return;
                          }
                          if (newPinCtrl.text != confirmPinCtrl.text) {
                            setSheetState(() => error = 'PINs do not match');
                            return;
                          }
                          if (currentPinCtrl.text == newPinCtrl.text) {
                            setSheetState(() => error = 'New PIN must be different');
                            return;
                          }
                          setSheetState(() { isLoading = true; error = null; });
                          try {
                            await ApiService.changePin(
                              currentPin: currentPinCtrl.text,
                              newPin: newPinCtrl.text,
                            );
                            Navigator.pop(ctx);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Transaction PIN changed!'),
                                    backgroundColor: AppTheme.success),
                              );
                            }
                          } catch (_) {
                            setSheetState(() {
                              isLoading = false;
                              error = 'Failed. Check your current PIN.';
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.warning,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: isLoading
                      ? const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Change PIN',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Logout ──────────────────────────────────────────────────────────────
  void _showLogoutConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Logout', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to logout?',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ApiService.logout();
              if (!mounted) return;
              Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
            },
            child: const Text('Logout', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
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
              : SlideTransition(
                  position: _slideAnim,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      // ── User Card ──
                      GlassCard(
                        child: Row(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                gradient: AppTheme.primaryGradient,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Center(
                                child: Text(
                                  _user?.initials ?? '?',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _user?.fullName ?? 'User',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _user?.email ?? '',
                                    style: const TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: () => Navigator.pushNamed(context, '/profile')
                                  .then((_) => _loadUser()),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppTheme.accent.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text('Edit',
                                    style: TextStyle(
                                        color: AppTheme.accent,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ── Security Section ──
                      _SectionHeader(title: 'Security'),
                      const SizedBox(height: 8),
                      GlassCard(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          children: [
                            _SettingsTile(
                              icon: Icons.lock_rounded,
                              title: 'Change Password',
                              subtitle: 'Update your login password',
                              iconColor: AppTheme.accent,
                              onTap: _showChangePasswordSheet,
                            ),
                            _divider(),
                            _SettingsTile(
                              icon: Icons.pin_rounded,
                              title: 'Change Transaction PIN',
                              subtitle: 'Update your 4-digit PIN',
                              iconColor: AppTheme.warning,
                              onTap: _user?.hasPin == true
                                  ? _showChangePinSheet
                                  : () => Navigator.pushNamed(context, '/set-pin')
                                      .then((_) => _loadUser()),
                              trailing: _user?.hasPin == true
                                  ? null
                                  : Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppTheme.warning.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text('Set Up',
                                          style: TextStyle(
                                              color: AppTheme.warning,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600)),
                                    ),
                            ),
                            _divider(),
                            _SettingsTile(
                              icon: Icons.face_rounded,
                              title: 'Face Authentication',
                              subtitle: _user?.isFaceRegistered == true
                                  ? 'Re-register your face'
                                  : 'Set up face recognition',
                              iconColor: const Color(0xFF00BCD4),
                              onTap: () =>
                                  Navigator.pushNamed(context, '/face-capture')
                                      .then((_) => _loadUser()),
                              trailing: _user?.isFaceRegistered == true
                                  ? const Icon(Icons.check_circle_rounded,
                                      color: AppTheme.success, size: 20)
                                  : Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppTheme.error.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text('Not Set',
                                          style: TextStyle(
                                              color: AppTheme.error,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600)),
                                    ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ── Preferences Section ──
                      _SectionHeader(title: 'Preferences'),
                      const SizedBox(height: 8),
                      GlassCard(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          children: [
                            _SettingsToggle(
                              icon: Icons.notifications_rounded,
                              title: 'Push Notifications',
                              subtitle: 'Transaction alerts & updates',
                              iconColor: const Color(0xFFFF6D00),
                              value: _notificationsEnabled,
                              onChanged: (val) =>
                                  setState(() => _notificationsEnabled = val),
                            ),
                            _divider(),
                            _SettingsToggle(
                              icon: Icons.fingerprint_rounded,
                              title: 'App Lock',
                              subtitle: 'Require biometric to open app',
                              iconColor: const Color(0xFF9C27B0),
                              value: _appLockEnabled,
                              onChanged: (val) =>
                                  setState(() => _appLockEnabled = val),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ── Account Section ──
                      _SectionHeader(title: 'Account'),
                      const SizedBox(height: 8),
                      GlassCard(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          children: [
                            _SettingsTile(
                              icon: Icons.account_balance_rounded,
                              title: 'Bank Accounts',
                              subtitle: 'Manage linked bank accounts',
                              iconColor: AppTheme.primary,
                              onTap: () =>
                                  Navigator.pushNamed(context, '/bank-setup'),
                            ),
                            _divider(),
                            _SettingsTile(
                              icon: Icons.history_rounded,
                              title: 'Login History',
                              subtitle: 'View recent login activity',
                              iconColor: const Color(0xFF6C63FF),
                              onTap: () =>
                                  Navigator.pushNamed(context, '/profile'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ── About Section ──
                      _SectionHeader(title: 'About'),
                      const SizedBox(height: 8),
                      GlassCard(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          children: [
                            _SettingsTile(
                              icon: Icons.info_outline_rounded,
                              title: 'About Fabio',
                              subtitle: 'Version 2.0.0',
                              iconColor: AppTheme.textSecondary,
                              onTap: () => _showAboutDialog(),
                            ),
                            _divider(),
                            _SettingsTile(
                              icon: Icons.privacy_tip_outlined,
                              title: 'Privacy Policy',
                              subtitle: 'How we protect your data',
                              iconColor: AppTheme.textSecondary,
                              onTap: () {},
                            ),
                            _divider(),
                            _SettingsTile(
                              icon: Icons.help_outline_rounded,
                              title: 'Help & Support',
                              subtitle: 'Get help with Fabio',
                              iconColor: AppTheme.textSecondary,
                              onTap: () {},
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ── Logout Button ──
                      GestureDetector(
                        onTap: _showLogoutConfirmation,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: AppTheme.error.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: AppTheme.error.withOpacity(0.3)),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.logout_rounded,
                                  color: AppTheme.error, size: 20),
                              SizedBox(width: 8),
                              Text('Logout',
                                  style: TextStyle(
                                      color: AppTheme.error,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16)),
                            ],
                          ),
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

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.account_balance_wallet_rounded,
                color: AppTheme.accent, size: 24),
            SizedBox(width: 8),
            Text('Fabio', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Version 2.0.0',
                style: TextStyle(color: AppTheme.textSecondary)),
            SizedBox(height: 8),
            Text(
              'Fabio is a secure FinTech application with biometric face verification, '
              'real-time transactions, and enterprise-grade security.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            SizedBox(height: 12),
            Text('Features:',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
            SizedBox(height: 4),
            Text('• Face ID Authentication\n• Real-time P2P Transfers\n'
                '• UPI & Bank Transfers\n• Transaction PIN Security\n'
                '• Liveness Detection',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Divider(
        color: Colors.white.withOpacity(0.06),
        height: 1,
        indent: 56,
      );
}

// ── Section Header ──────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: AppTheme.textSecondary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
    );
  }
}

// ── Settings Tile ───────────────────────────────────────────────────────────
class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color iconColor;
  final VoidCallback onTap;
  final Widget? trailing;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.iconColor,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(title,
          style: const TextStyle(color: Colors.white, fontSize: 15)),
      subtitle: Text(subtitle,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
      trailing: trailing ??
          const Icon(Icons.chevron_right_rounded,
              color: AppTheme.textSecondary, size: 20),
      onTap: onTap,
    );
  }
}

// ── Settings Toggle ─────────────────────────────────────────────────────────
class _SettingsToggle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color iconColor;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsToggle({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.iconColor,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(title,
          style: const TextStyle(color: Colors.white, fontSize: 15)),
      subtitle: Text(subtitle,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
      trailing: Switch.adaptive(
        value: value,
        onChanged: onChanged,
        activeColor: AppTheme.accent,
      ),
    );
  }
}
