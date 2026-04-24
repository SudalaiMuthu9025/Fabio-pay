/// Fabio — Admin Panel Screen
///
/// View all users, toggle active status, and change roles.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart';

class AdminPanelScreen extends ConsumerStatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  ConsumerState<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends ConsumerState<AdminPanelScreen>
    with SingleTickerProviderStateMixin {
  List<User> _users = [];
  bool _isLoading = true;

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
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final users = await ApiService.getAdminUsers();
      if (!mounted) return;
      setState(() {
        _users = users;
        _isLoading = false;
      });
      _slideCtrl.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Failed to load users. Ensure you are an Admin.'),
            backgroundColor: AppTheme.error),
      );
    }
  }

  Future<void> _toggleStatus(User user) async {
    try {
      await ApiService.toggleUserStatus(user.id, !user.isActive);
      _loadUsers();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Failed to update status'),
            backgroundColor: AppTheme.error),
      );
    }
  }

  Future<void> _changeRole(User user) async {
    final newRole = user.role == 'ADMIN' ? 'USER' : 'ADMIN';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Change Role', style: TextStyle(color: Colors.white)),
        content: Text('Change ${user.fullName}\'s role to $newRole?',
            style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm', style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ApiService.changeUserRole(user.id, newRole);
        _loadUsers();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Failed to update role'),
              backgroundColor: AppTheme.error),
        );
      }
    }
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
        title: const Text('Admin Panel'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _loadUsers,
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.accent),
          ),
        ],
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
                  child: ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: _users.length,
                    itemBuilder: (ctx, i) {
                      final u = _users[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: GlassCard(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: u.role == 'ADMIN'
                                          ? AppTheme.error.withOpacity(0.2)
                                          : AppTheme.primary.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Center(
                                      child: Text(
                                        u.initials,
                                        style: TextStyle(
                                          color: u.role == 'ADMIN'
                                              ? AppTheme.error
                                              : AppTheme.primary,
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
                                          u.fullName,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600),
                                        ),
                                        Text(
                                          u.email,
                                          style: const TextStyle(
                                              color: AppTheme.textSecondary,
                                              fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: u.isActive
                                          ? AppTheme.success.withOpacity(0.1)
                                          : AppTheme.error.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      u.isActive ? 'Active' : 'Disabled',
                                      style: TextStyle(
                                        color: u.isActive
                                            ? AppTheme.success
                                            : AppTheme.error,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Divider(color: Colors.white.withOpacity(0.1)),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Joined: ${DateFormat('dd MMM yyyy').format(u.createdAt.toLocal())}',
                                        style: const TextStyle(
                                            color: AppTheme.textSecondary,
                                            fontSize: 12),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(
                                            u.hasPin
                                                ? Icons.pin_rounded
                                                : Icons.pin_outlined,
                                            size: 14,
                                            color: u.hasPin
                                                ? AppTheme.success
                                                : AppTheme.textSecondary,
                                          ),
                                          const SizedBox(width: 4),
                                          Icon(
                                            u.isFaceRegistered
                                                ? Icons.face_rounded
                                                : Icons.face_outlined,
                                            size: 14,
                                            color: u.isFaceRegistered
                                                ? AppTheme.success
                                                : AppTheme.textSecondary,
                                          ),
                                          const SizedBox(width: 4),
                                          Icon(
                                            u.hasBankAccount
                                                ? Icons.account_balance_rounded
                                                : Icons.account_balance_outlined,
                                            size: 14,
                                            color: u.hasBankAccount
                                                ? AppTheme.success
                                                : AppTheme.textSecondary,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      TextButton.icon(
                                        onPressed: () => _changeRole(u),
                                        icon: Icon(
                                            u.role == 'ADMIN'
                                                ? Icons.security_rounded
                                                : Icons.person_rounded,
                                            size: 16,
                                            color: u.role == 'ADMIN'
                                                ? AppTheme.error
                                                : AppTheme.primary),
                                        label: Text(
                                          u.role,
                                          style: TextStyle(
                                              color: u.role == 'ADMIN'
                                                  ? AppTheme.error
                                                  : AppTheme.primary,
                                              fontSize: 12),
                                        ),
                                      ),
                                      Switch(
                                        value: u.isActive,
                                        onChanged: (_) => _toggleStatus(u),
                                        activeColor: AppTheme.success,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ),
    );
  }
}
