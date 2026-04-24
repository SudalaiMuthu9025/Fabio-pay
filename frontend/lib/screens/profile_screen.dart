/// Fabio — Profile Screen
///
/// View/edit profile, change password, login history, re-register face.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/fab_button.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen>
    with SingleTickerProviderStateMixin {
  User? _user;
  List<LoginLog> _loginLogs = [];
  bool _isLoading = true;
  bool _isEditing = false;

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  late AnimationController _slideCtrl;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final user = await ApiService.getMe();
      List<LoginLog> logs = [];
      try {
        logs = await ApiService.getLoginHistory();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _user = user;
        _loginLogs = logs;
        _nameController.text = user.fullName;
        _phoneController.text = user.phone ?? '';
        _isLoading = false;
      });
      _slideCtrl.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    try {
      final user = await ApiService.updateProfile(
        fullName: _nameController.text.trim(),
        phone: _phoneController.text.trim().isNotEmpty
            ? _phoneController.text.trim()
            : null,
      );
      setState(() {
        _user = user;
        _isEditing = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Profile updated'),
              backgroundColor: AppTheme.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Update failed'),
              backgroundColor: AppTheme.error),
        );
      }
    }
  }

  void _showChangePasswordDialog() {
    _currentPasswordController.clear();
    _newPasswordController.clear();
    _confirmPasswordController.clear();
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
            left: 24, right: 24, top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Change Password',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: _currentPasswordController,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Current Password',
                  prefixIcon: Icon(Icons.lock_outline, color: AppTheme.textSecondary),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _newPasswordController,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'New Password',
                  prefixIcon: Icon(Icons.lock_rounded, color: AppTheme.textSecondary),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmPasswordController,
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
              FabButton(
                label: 'Change Password',
                icon: Icons.vpn_key_rounded,
                onPressed: () async {
                  if (_newPasswordController.text !=
                      _confirmPasswordController.text) {
                    setModalState(() => error = 'Passwords do not match');
                    return;
                  }
                  if (_newPasswordController.text.length < 8) {
                    setModalState(() => error = 'Min 8 characters');
                    return;
                  }
                  try {
                    await ApiService.changePassword(
                      currentPassword: _currentPasswordController.text,
                      newPassword: _newPasswordController.text,
                    );
                    Navigator.pop(ctx);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Password changed!'),
                            backgroundColor: AppTheme.success),
                      );
                    }
                  } catch (_) {
                    setModalState(
                        () => error = 'Failed. Check current password.');
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (!_isEditing)
            IconButton(
              onPressed: () => setState(() => _isEditing = true),
              icon: const Icon(Icons.edit_rounded, color: AppTheme.accent),
            ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration:
            const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: SafeArea(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.accent))
              : SlideTransition(
                  position: _slideAnim,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      // Avatar
                      Center(
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            gradient: AppTheme.primaryGradient,
                            borderRadius: BorderRadius.circular(28),
                          ),
                          child: Center(
                            child: Text(
                              _user?.initials ?? '?',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Profile info
                      GlassCard(
                        child: Column(
                          children: [
                            if (_isEditing) ...[
                              TextField(
                                controller: _nameController,
                                style: const TextStyle(color: Colors.white),
                                decoration: const InputDecoration(
                                  labelText: 'Full Name',
                                  labelStyle:
                                      TextStyle(color: AppTheme.textSecondary),
                                  prefixIcon: Icon(Icons.person_outline,
                                      color: AppTheme.textSecondary),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _phoneController,
                                style: const TextStyle(color: Colors.white),
                                keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(
                                  labelText: 'Phone',
                                  labelStyle:
                                      TextStyle(color: AppTheme.textSecondary),
                                  prefixIcon: Icon(Icons.phone_outlined,
                                      color: AppTheme.textSecondary),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextButton(
                                      onPressed: () =>
                                          setState(() => _isEditing = false),
                                      child: const Text('Cancel',
                                          style: TextStyle(
                                              color: AppTheme.textSecondary)),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: FabButton(
                                      label: 'Save',
                                      icon: Icons.check_rounded,
                                      onPressed: _saveProfile,
                                    ),
                                  ),
                                ],
                              ),
                            ] else ...[
                              _ProfileRow(
                                  icon: Icons.person_outline,
                                  label: 'Name',
                                  value: _user?.fullName ?? ''),
                              _ProfileRow(
                                  icon: Icons.email_outlined,
                                  label: 'Email',
                                  value: _user?.email ?? ''),
                              _ProfileRow(
                                  icon: Icons.phone_outlined,
                                  label: 'Phone',
                                  value: _user?.phone ?? 'Not set'),
                              _ProfileRow(
                                  icon: Icons.shield_rounded,
                                  label: 'Role',
                                  value: _user?.role ?? 'USER'),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Security status
                      GlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Security Status',
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 12),
                            _StatusRow(
                                label: 'PIN',
                                isSet: _user?.hasPin ?? false),
                            _StatusRow(
                                label: 'Face ID',
                                isSet: _user?.isFaceRegistered ?? false),
                            _StatusRow(
                                label: 'Bank Account',
                                isSet: _user?.hasBankAccount ?? false),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Actions
                      GlassCard(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          children: [
                            _ActionTile(
                              icon: Icons.vpn_key_rounded,
                              label: 'Change Password',
                              color: AppTheme.accent,
                              onTap: _showChangePasswordDialog,
                            ),
                            _ActionTile(
                              icon: Icons.face_rounded,
                              label: 'Re-register Face',
                              color: AppTheme.primary,
                              onTap: () => Navigator.pushNamed(
                                      context, '/face-capture')
                                  .then((_) => _loadProfile()),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Login History
                      Text('Login History',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      if (_loginLogs.isEmpty)
                        const GlassCard(
                          child: Center(
                            child: Text('No login history',
                                style:
                                    TextStyle(color: AppTheme.textSecondary)),
                          ),
                        )
                      else
                        ...(_loginLogs.take(10).map((log) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: GlassCard(
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  children: [
                                    Icon(
                                      log.success
                                          ? Icons.check_circle_rounded
                                          : Icons.cancel_rounded,
                                      color: log.success
                                          ? AppTheme.success
                                          : AppTheme.error,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            DateFormat('dd MMM yyyy, hh:mm a')
                                                .format(
                                                    log.createdAt.toLocal()),
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 13),
                                          ),
                                          Text(
                                            log.ipAddress ?? 'Unknown IP',
                                            style: const TextStyle(
                                                color: AppTheme.textSecondary,
                                                fontSize: 11),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      log.success ? 'Success' : 'Failed',
                                      style: TextStyle(
                                        color: log.success
                                            ? AppTheme.success
                                            : AppTheme.error,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
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
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ProfileRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.textSecondary, size: 20),
          const SizedBox(width: 12),
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13)),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final bool isSet;

  const _StatusRow({required this.label, required this.isSet});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            isSet ? Icons.check_circle_rounded : Icons.pending_rounded,
            color: isSet ? AppTheme.success : AppTheme.warning,
            size: 20,
          ),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(color: Colors.white)),
          const Spacer(),
          Text(
            isSet ? 'Configured' : 'Not Set',
            style: TextStyle(
              color: isSet ? AppTheme.success : AppTheme.warning,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      trailing:
          const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
      onTap: onTap,
    );
  }
}
