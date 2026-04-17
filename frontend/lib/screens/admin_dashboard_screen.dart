/// Fabio — Admin Dashboard Screen
///
/// Stats overview, user management, session control.
/// Protected by role check — redirects non-admins.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';
import '../config/theme.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  AdminDashboardStats? _stats;
  List<User> _users = [];
  User? _currentUser;
  bool _isLoading = true;
  String? _searchQuery;

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
        ApiService.getAdminDashboard(),
        ApiService.getAdminUsers(),
        ApiService.getMe(),
      ]);
      if (!mounted) return;
      setState(() {
        _stats = results[0] as AdminDashboardStats;
        _users = results[1] as List<User>;
        _currentUser = results[2] as User;
        _isLoading = false;
      });
      _fadeController.forward();
    } catch (e) {
      if (mounted) {
        if (e is DioException && e.response?.statusCode == 403) {
          // Not an admin — redirect
          Navigator.pushReplacementNamed(context, '/dashboard');
          return;
        }
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _searchUsers(String query) async {
    try {
      final users = await ApiService.getAdminUsers(search: query);
      if (!mounted) return;
      setState(() {
        _users = users;
        _searchQuery = query.isEmpty ? null : query;
      });
    } catch (_) {}
  }

  Future<void> _toggleUserStatus(User user) async {
    try {
      await ApiService.changeUserStatus(user.id, !user.isActive);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${user.fullName} ${!user.isActive ? "activated" : "deactivated"}'),
          backgroundColor: AppTheme.success,
        ),
      );
      _loadData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update status'), backgroundColor: AppTheme.error),
      );
    }
  }

  Future<void> _changeRole(User user, String newRole) async {
    try {
      await ApiService.changeUserRole(user.id, newRole);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${user.fullName} role changed to $newRole'),
          backgroundColor: AppTheme.success,
        ),
      );
      _loadData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to change role'), backgroundColor: AppTheme.error),
      );
    }
  }

  Future<void> _revokeAllSessions(User user) async {
    try {
      await ApiService.revokeUserSessions(user.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('All sessions revoked for ${user.fullName}'),
          backgroundColor: AppTheme.success,
        ),
      );
      _loadData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to revoke sessions'), backgroundColor: AppTheme.error),
      );
    }
  }

  Future<void> _resetUserFace(User user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Reset Face Data', style: TextStyle(color: Colors.white)),
        content: Text(
          'This will remove face registration data for ${user.fullName}. '
          'They will need to re-register their face for biometric transactions.',
          style: const TextStyle(color: AppTheme.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ApiService.resetUserFace(user.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Face data reset for ${user.fullName}'),
          backgroundColor: AppTheme.success,
        ),
      );
      _loadData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to reset face data'), backgroundColor: AppTheme.error),
      );
    }
  }

  Future<void> _logout() async {
    await ApiService.logout();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

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
              ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
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
                        _buildStatsGrid(),
                        const SizedBox(height: 24),
                        _buildQuickActions(),
                        const SizedBox(height: 24),
                        _buildUserSearch(),
                        const SizedBox(height: 14),
                        _buildUserList(),
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
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('ADMIN',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 1.5)),
                  ),
                  const SizedBox(width: 10),
                  const Text('Control Panel',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _currentUser?.fullName ?? 'Admin',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ],
          ),
        ),
        Row(
          children: [
            _headerButton(Icons.person_outline, () {
              Navigator.pushNamed(context, '/dashboard');
            }),
            const SizedBox(width: 4),
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

  Widget _buildStatsGrid() {
    if (_stats == null) return const SizedBox();
    return Column(
      children: [
        Row(
          children: [
            _statCard('Total Users', _stats!.totalUsers.toString(),
                Icons.people_alt_rounded, AppTheme.primary),
            const SizedBox(width: 12),
            _statCard('Active Users', _stats!.activeUsers.toString(),
                Icons.person_pin_circle_rounded, AppTheme.success),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _statCard('Transactions', _stats!.totalTransactions.toString(),
                Icons.receipt_long_rounded, AppTheme.accent),
            const SizedBox(width: 12),
            _statCard('Active Sessions', _stats!.activeSessions.toString(),
                Icons.devices_rounded, AppTheme.warning),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _statCard('Face Registered', _stats!.faceRegisteredUsers.toString(),
                Icons.face_unlock_rounded, AppTheme.success),
            const SizedBox(width: 12),
            _statCard('Pending Txns', _stats!.pendingTransactions.toString(),
                Icons.schedule_rounded, AppTheme.warning),
          ],
        ),
        const SizedBox(height: 12),
        // Volume card — full width
        GlassCard(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.success.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.trending_up_rounded,
                    color: AppTheme.success, size: 26),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Total Volume',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(
                    _currencyFormat.format(_stats!.totalVolume),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _miniStat('✅', _stats!.successfulTransactions),
                  _miniStat('❌', _stats!.failedTransactions),
                  _miniStat('⏳', _stats!.pendingTransactions),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _miniStat(String emoji, int count) {
    return Text('$emoji $count',
        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12));
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: GlassCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick Actions', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 14),
        Row(
          children: [
            _actionButton(
              icon: Icons.shield_outlined,
              label: 'Security',
              color: AppTheme.warning,
              onTap: () => Navigator.pushNamed(context, '/settings'),
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
              icon: Icons.send_rounded,
              label: 'Transfer',
              color: AppTheme.primary,
              onTap: () => Navigator.pushNamed(context, '/transfer'),
            ),
            const SizedBox(width: 12),
            _actionButton(
              icon: Icons.refresh_rounded,
              label: 'Refresh',
              color: AppTheme.accent,
              onTap: _loadData,
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
                  style: TextStyle(
                      color: color, fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserSearch() {
    return TextFormField(
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: 'Search users by name or email...',
        prefixIcon: const Icon(Icons.search, color: AppTheme.textSecondary),
        suffixIcon: _searchQuery != null
            ? IconButton(
                icon: const Icon(Icons.clear, color: AppTheme.textSecondary),
                onPressed: () {
                  _searchUsers('');
                },
              )
            : null,
      ),
      onChanged: (v) {
        if (v.length >= 2 || v.isEmpty) _searchUsers(v);
      },
    );
  }

  Widget _buildUserList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Users (${_users.length})',
                style: Theme.of(context).textTheme.titleLarge),
            if (_searchQuery != null)
              Text('Searching: "$_searchQuery"',
                  style: const TextStyle(color: AppTheme.accent, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 14),
        ..._users.map((user) => _buildUserTile(user)),
      ],
    );
  }

  Widget _buildUserTile(User user) {
    final isCurrentUser = user.id == _currentUser?.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCurrentUser
              ? AppTheme.accent.withOpacity(0.3)
              : AppTheme.border,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Avatar
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(user.initials,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(user.fullName,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (isCurrentUser) ...[
                          const SizedBox(width: 6),
                          const Text('(You)',
                              style: TextStyle(
                                  color: AppTheme.accent, fontSize: 11)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(user.email,
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12),
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              // Role badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _roleColor(user.role).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  user.role.replaceAll('_', ' '),
                  style: TextStyle(
                      color: _roleColor(user.role),
                      fontSize: 10,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (!isCurrentUser) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                // Status indicator
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: user.isActive ? AppTheme.success : AppTheme.error,
                  ),
                ),
                const SizedBox(width: 6),
                Text(user.isActive ? 'Active' : 'Inactive',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 11)),
                const SizedBox(width: 8),
                if (user.isFaceRegistered) ...[
                  const Icon(Icons.face, color: AppTheme.success, size: 14),
                  const SizedBox(width: 4),
                  const Text('Face',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11)),
                ],
                const Spacer(),
                // Action buttons
                _tileAction(
                  icon: user.isActive
                      ? Icons.block_rounded
                      : Icons.check_circle_outline,
                  color: user.isActive ? AppTheme.error : AppTheme.success,
                  tooltip: user.isActive ? 'Deactivate' : 'Activate',
                  onTap: () => _toggleUserStatus(user),
                ),
                const SizedBox(width: 6),
                _tileAction(
                  icon: Icons.admin_panel_settings_outlined,
                  color: AppTheme.accent,
                  tooltip: 'Change Role',
                  onTap: () => _showRoleDialog(user),
                ),
                const SizedBox(width: 6),
                _tileAction(
                  icon: Icons.logout_rounded,
                  color: AppTheme.warning,
                  tooltip: 'Revoke Sessions',
                  onTap: () => _revokeAllSessions(user),
                ),
                if (user.isFaceRegistered) ...[
                  const SizedBox(width: 6),
                  _tileAction(
                    icon: Icons.face_retouching_off,
                    color: AppTheme.error,
                    tooltip: 'Reset Face Data',
                    onTap: () => _resetUserFace(user),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _tileAction({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
      ),
    );
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'ADMIN':
        return AppTheme.error;
      case 'VICE_ADMIN':
        return AppTheme.warning;
      default:
        return AppTheme.accent;
    }
  }

  void _showRoleDialog(User user) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title:
            const Text('Change Role', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Change role for ${user.fullName}',
                style: const TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 20),
            _roleOption(ctx, user, 'USER', 'Regular User'),
            const SizedBox(height: 8),
            _roleOption(ctx, user, 'VICE_ADMIN', 'Vice Admin'),
            const SizedBox(height: 8),
            _roleOption(ctx, user, 'ADMIN', 'Administrator'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
        ],
      ),
    );
  }

  Widget _roleOption(BuildContext ctx, User user, String role, String label) {
    final isSelected = user.role == role;
    return GestureDetector(
      onTap: isSelected
          ? null
          : () {
              Navigator.pop(ctx);
              _changeRole(user, role);
            },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withOpacity(0.15)
              : AppTheme.surfaceCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                isSelected ? AppTheme.primary : AppTheme.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Text(label,
                style: TextStyle(
                  color: isSelected ? Colors.white : AppTheme.textSecondary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                )),
          ],
        ),
      ),
    );
  }
}
