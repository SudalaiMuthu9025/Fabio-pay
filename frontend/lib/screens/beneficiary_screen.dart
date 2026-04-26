/// Fabio — Beneficiary Screen (Contacts/Saved Recipients)
///
/// List, add, delete, and favorite saved recipients.
/// Tap a beneficiary to navigate to Send Money with pre-filled details.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/theme.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/fab_button.dart';

class BeneficiaryScreen extends ConsumerStatefulWidget {
  const BeneficiaryScreen({super.key});

  @override
  ConsumerState<BeneficiaryScreen> createState() => _BeneficiaryScreenState();
}

class _BeneficiaryScreenState extends ConsumerState<BeneficiaryScreen>
    with SingleTickerProviderStateMixin {
  List<Beneficiary> _beneficiaries = [];
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
    _loadBeneficiaries();
  }

  Future<void> _loadBeneficiaries() async {
    try {
      final list = await ApiService.getBeneficiaries();
      if (!mounted) return;
      setState(() {
        _beneficiaries = list;
        _isLoading = false;
      });
      _slideCtrl.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _showAddDialog() {
    final nameCtrl = TextEditingController();
    final accountCtrl = TextEditingController();
    final ifscCtrl = TextEditingController();
    final nicknameCtrl = TextEditingController();
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
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.textSecondary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Row(
                children: [
                  Icon(Icons.person_add_rounded, color: AppTheme.accent, size: 24),
                  SizedBox(width: 10),
                  Text('Add Contact',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Full Name',
                  prefixIcon: Icon(Icons.person_outline, color: AppTheme.textSecondary),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: accountCtrl,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: 'Account Number or UPI ID',
                  prefixIcon: Icon(Icons.account_balance_rounded, color: AppTheme.textSecondary),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ifscCtrl,
                style: const TextStyle(color: Colors.white),
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  hintText: 'IFSC Code (optional)',
                  prefixIcon: Icon(Icons.code_rounded, color: AppTheme.textSecondary),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nicknameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Nickname (optional)',
                  prefixIcon: Icon(Icons.label_outline_rounded, color: AppTheme.textSecondary),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
              ],
              const SizedBox(height: 20),
              FabButton(
                label: 'Add Contact',
                icon: Icons.person_add_rounded,
                onPressed: () async {
                  if (nameCtrl.text.trim().length < 2) {
                    setModalState(() => error = 'Name is required');
                    return;
                  }
                  if (accountCtrl.text.trim().length < 3) {
                    setModalState(() => error = 'Account/UPI ID is required');
                    return;
                  }
                  try {
                    await ApiService.addBeneficiary(
                      name: nameCtrl.text.trim(),
                      accountNumber: accountCtrl.text.trim(),
                      ifscCode: ifscCtrl.text.trim().isNotEmpty
                          ? ifscCtrl.text.trim()
                          : null,
                      nickname: nicknameCtrl.text.trim().isNotEmpty
                          ? nicknameCtrl.text.trim()
                          : null,
                    );
                    Navigator.pop(ctx);
                    _loadBeneficiaries();
                  } catch (e) {
                    setModalState(() {
                      if (e.toString().contains('409')) {
                        error = 'Contact with this account already exists';
                      } else {
                        error = 'Failed to add contact';
                      }
                    });
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteBeneficiary(Beneficiary b) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Contact',
            style: TextStyle(color: Colors.white)),
        content: Text('Remove ${b.displayName}?',
            style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ApiService.deleteBeneficiary(b.id);
      _loadBeneficiaries();
    }
  }

  Future<void> _toggleFavorite(Beneficiary b) async {
    await ApiService.toggleFavorite(b.id);
    _loadBeneficiaries();
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
        title: const Text('Saved Contacts'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _showAddDialog,
            icon: const Icon(Icons.person_add_rounded, color: AppTheme.accent),
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        backgroundColor: AppTheme.primary,
        child: const Icon(Icons.add_rounded),
      ),
      body: Container(
        decoration:
            const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: SafeArea(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.accent))
              : _beneficiaries.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.people_outline_rounded,
                              color: AppTheme.textSecondary.withValues(alpha: 0.4),
                              size: 64),
                          const SizedBox(height: 16),
                          const Text('No saved contacts yet',
                              style:
                                  TextStyle(color: AppTheme.textSecondary)),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: _showAddDialog,
                            icon: const Icon(Icons.add_rounded,
                                color: AppTheme.accent),
                            label: const Text('Add Contact',
                                style: TextStyle(color: AppTheme.accent)),
                          ),
                        ],
                      ),
                    )
                  : SlideTransition(
                      position: _slideAnim,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(20),
                        itemCount: _beneficiaries.length,
                        itemBuilder: (ctx, i) {
                          final b = _beneficiaries[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Dismissible(
                              key: ValueKey(b.id),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 20),
                                decoration: BoxDecoration(
                                  color: AppTheme.error.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Icon(Icons.delete_rounded,
                                    color: AppTheme.error),
                              ),
                              onDismissed: (_) => _deleteBeneficiary(b),
                              confirmDismiss: (_) async {
                                return await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    backgroundColor: AppTheme.surfaceCard,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(20)),
                                    title: const Text('Delete?',
                                        style:
                                            TextStyle(color: Colors.white)),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text('Delete',
                                            style: TextStyle(
                                                color: AppTheme.error)),
                                      ),
                                    ],
                                  ),
                                );
                              },
                              child: GlassCard(
                                padding: const EdgeInsets.all(16),
                                child: InkWell(
                                  onTap: () {
                                    // Navigate to send money with pre-filled recipient
                                    Navigator.pushNamed(
                                      context,
                                      '/send-money',
                                    );
                                  },
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              AppTheme.primary
                                                  .withValues(alpha: 0.6),
                                              AppTheme.accent
                                                  .withValues(alpha: 0.4),
                                            ],
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                        child: Center(
                                          child: Text(
                                            b.name.substring(0, 1).toUpperCase(),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Text(b.displayName,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    )),
                                                if (b.nickname != null &&
                                                    b.nickname != b.name) ...[
                                                  const SizedBox(width: 6),
                                                  Text('(${b.name})',
                                                      style: const TextStyle(
                                                        color: AppTheme
                                                            .textSecondary,
                                                        fontSize: 12,
                                                      )),
                                                ],
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              b.accountNumber,
                                              style: const TextStyle(
                                                color: AppTheme.textSecondary,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () => _toggleFavorite(b),
                                        icon: Icon(
                                          b.isFavorite
                                              ? Icons.star_rounded
                                              : Icons.star_border_rounded,
                                          color: b.isFavorite
                                              ? AppTheme.warning
                                              : AppTheme.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
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
