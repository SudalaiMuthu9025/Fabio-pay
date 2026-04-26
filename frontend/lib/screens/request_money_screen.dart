/// Fabio — Request Money Screen
///
/// Create, view incoming, and view outgoing payment requests.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/fab_button.dart';

class RequestMoneyScreen extends ConsumerStatefulWidget {
  const RequestMoneyScreen({super.key});
  @override
  ConsumerState<RequestMoneyScreen> createState() => _RequestMoneyScreenState();
}

class _RequestMoneyScreenState extends ConsumerState<RequestMoneyScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _formKey = GlobalKey<FormState>();
  final _accountCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _isCreating = false;
  List<Map<String, dynamic>> _incoming = [];
  List<Map<String, dynamic>> _outgoing = [];
  bool _loadingIncoming = true;
  bool _loadingOutgoing = true;
  final _fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    try {
      final inc = await ApiService.getIncomingRequests();
      if (mounted) setState(() { _incoming = inc; _loadingIncoming = false; });
    } catch (_) { if (mounted) setState(() => _loadingIncoming = false); }
    try {
      final out = await ApiService.getOutgoingRequests();
      if (mounted) setState(() { _outgoing = out; _loadingOutgoing = false; });
    } catch (_) { if (mounted) setState(() => _loadingOutgoing = false); }
  }

  Future<void> _createRequest() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isCreating = true);
    try {
      await ApiService.createPaymentRequest(
        toAccountIdentifier: _accountCtrl.text.trim(),
        amount: double.parse(_amountCtrl.text.trim()),
        description: _descCtrl.text.trim().isNotEmpty ? _descCtrl.text.trim() : null,
      );
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request sent!'), backgroundColor: AppTheme.success));
      _accountCtrl.clear(); _amountCtrl.clear(); _descCtrl.clear();
      _loadRequests();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: ${e.toString().contains('404') ? 'Account not found' : 'Try again'}'),
          backgroundColor: AppTheme.error));
    } finally { if (mounted) setState(() => _isCreating = false); }
  }

  Future<void> _payRequest(String id) async {
    final pinCtrl = TextEditingController();
    final result = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.surfaceCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Enter PIN to Pay', style: TextStyle(color: Colors.white)),
      content: TextField(controller: pinCtrl, keyboardType: TextInputType.number,
        maxLength: 4, obscureText: true, textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 20, letterSpacing: 8),
        decoration: const InputDecoration(counterText: '', hintText: '••••')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Pay', style: TextStyle(color: Colors.white))),
      ],
    ));
    if (result != true || pinCtrl.text.length != 4) return;
    try {
      await ApiService.payRequest(id, pinCtrl.text);
      HapticFeedback.heavyImpact();
      
      // Look up amount from data
      final reqData = _incoming.firstWhere((e) => e['id'] == id, orElse: () => {});
      final amount = reqData['amount']?.toString() ?? 'the requested amount';
      final name = reqData['requester_name']?.toString() ?? 'user';
      
      NotificationService.showNotification(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: 'Request Paid',
        body: 'You successfully paid ₹$amount to $name',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment completed!'), backgroundColor: AppTheme.success));
      _loadRequests();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: ${e.toString().contains('401') ? 'Invalid PIN' : 'Error'}'),
          backgroundColor: AppTheme.error));
    }
  }

  Future<void> _declineRequest(String id) async {
    try {
      await ApiService.declineRequest(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request declined'), backgroundColor: AppTheme.textSecondary));
      _loadRequests();
    } catch (_) {}
  }

  @override
  void dispose() { _tabController.dispose(); _accountCtrl.dispose();
    _amountCtrl.dispose(); _descCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Request Money'), backgroundColor: Colors.transparent, elevation: 0),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: SafeArea(child: Column(children: [
          Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: GlassCard(padding: const EdgeInsets.all(4), child: TabBar(
              controller: _tabController, indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(gradient: AppTheme.primaryGradient, borderRadius: BorderRadius.circular(14)),
              dividerColor: Colors.transparent, labelColor: Colors.white,
              unselectedLabelColor: AppTheme.textSecondary,
              labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              tabs: const [Tab(text: 'Create'), Tab(text: 'Incoming'), Tab(text: 'Outgoing')],
            ))),
          Expanded(child: TabBarView(controller: _tabController, children: [
            _buildCreateTab(), _buildIncomingTab(), _buildOutgoingTab()])),
        ])),
      ),
    );
  }

  Widget _buildCreateTab() {
    return SingleChildScrollView(padding: const EdgeInsets.all(20), child: Form(key: _formKey, child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.request_page_rounded, color: AppTheme.accent, size: 20),
            const SizedBox(width: 8),
            Text('Request Payment', style: Theme.of(context).textTheme.titleMedium),
          ]),
          const SizedBox(height: 16),
          TextFormField(controller: _accountCtrl, style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(hintText: 'Recipient Account Number',
              prefixIcon: Icon(Icons.person_outline, color: AppTheme.textSecondary)),
            validator: (v) => (v == null || v.length < 8) ? 'Enter valid account number' : null),
          const SizedBox(height: 14),
          TextFormField(controller: _amountCtrl, keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white, fontSize: 22),
            decoration: const InputDecoration(hintText: 'Amount (₹)',
              prefixIcon: Icon(Icons.currency_rupee_rounded, color: AppTheme.textSecondary)),
            validator: (v) { if (v == null || v.isEmpty) return 'Enter amount';
              final a = double.tryParse(v); return (a == null || a <= 0) ? 'Invalid amount' : null; }),
          const SizedBox(height: 14),
          TextFormField(controller: _descCtrl, style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(hintText: 'Description (optional)',
              prefixIcon: Icon(Icons.note_outlined, color: AppTheme.textSecondary))),
          const SizedBox(height: 24),
          FabButton(label: 'Send Request', onPressed: _createRequest, isLoading: _isCreating,
            icon: Icons.send_rounded),
        ])),
      ],
    )));
  }

  Widget _buildIncomingTab() {
    if (_loadingIncoming) return const Center(child: CircularProgressIndicator(color: AppTheme.accent));
    if (_incoming.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.inbox_rounded, color: AppTheme.textSecondary.withOpacity(0.3), size: 64),
      const SizedBox(height: 12),
      const Text('No incoming requests', style: TextStyle(color: AppTheme.textSecondary)),
    ]));
    return RefreshIndicator(onRefresh: _loadRequests, color: AppTheme.accent,
      child: ListView.builder(padding: const EdgeInsets.all(20), itemCount: _incoming.length,
        itemBuilder: (_, i) => _RequestCard(data: _incoming[i], isIncoming: true, fmt: _fmt,
          onPay: () => _payRequest(_incoming[i]['id']),
          onDecline: () => _declineRequest(_incoming[i]['id']))));
  }

  Widget _buildOutgoingTab() {
    if (_loadingOutgoing) return const Center(child: CircularProgressIndicator(color: AppTheme.accent));
    if (_outgoing.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.outbox_rounded, color: AppTheme.textSecondary.withOpacity(0.3), size: 64),
      const SizedBox(height: 12),
      const Text('No outgoing requests', style: TextStyle(color: AppTheme.textSecondary)),
    ]));
    return RefreshIndicator(onRefresh: _loadRequests, color: AppTheme.accent,
      child: ListView.builder(padding: const EdgeInsets.all(20), itemCount: _outgoing.length,
        itemBuilder: (_, i) => _RequestCard(data: _outgoing[i], isIncoming: false, fmt: _fmt)));
  }
}

class _RequestCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isIncoming;
  final NumberFormat fmt;
  final VoidCallback? onPay;
  final VoidCallback? onDecline;
  const _RequestCard({required this.data, required this.isIncoming, required this.fmt, this.onPay, this.onDecline});

  @override
  Widget build(BuildContext context) {
    final amount = double.tryParse(data['amount'].toString()) ?? 0;
    final status = data['status'] ?? 'PENDING';
    final name = data['requester_name'] ?? 'Unknown';
    final desc = data['description'] ?? '';
    final isPending = status == 'PENDING';
    final statusColor = status == 'PAID' ? AppTheme.success : status == 'DECLINED' ? AppTheme.error : AppTheme.accent;

    return Padding(padding: const EdgeInsets.only(bottom: 10), child: GlassCard(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(
            color: (isIncoming ? AppTheme.accent : AppTheme.success).withOpacity(0.15),
            borderRadius: BorderRadius.circular(12)),
            child: Icon(isIncoming ? Icons.call_received_rounded : Icons.call_made_rounded,
              color: isIncoming ? AppTheme.accent : AppTheme.success, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(isIncoming ? 'From: $name' : 'To: ${data['payer_account_identifier'] ?? ''}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 14)),
            if (desc.isNotEmpty) Text(desc, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(fmt.format(amount), style: TextStyle(color: statusColor, fontWeight: FontWeight.w600, fontSize: 16)),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: statusColor.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
              child: Text(status, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w600))),
          ]),
        ]),
        if (isIncoming && isPending) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton(
              style: OutlinedButton.styleFrom(side: const BorderSide(color: AppTheme.error),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: onDecline, child: const Text('Decline', style: TextStyle(color: AppTheme.error)))),
            const SizedBox(width: 10),
            Expanded(child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: onPay, child: const Text('Pay', style: TextStyle(color: Colors.white)))),
          ]),
        ],
      ],
    )));
  }
}
