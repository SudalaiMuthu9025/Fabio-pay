/// Fabio — QR Payment Screen
///
/// Two tabs: "My QR" to show your payment QR code,
/// and "Scan QR" to scan and pay someone.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../config/theme.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart';
import 'send_money_screen.dart';

class QrPaymentScreen extends ConsumerStatefulWidget {
  const QrPaymentScreen({super.key});
  @override
  ConsumerState<QrPaymentScreen> createState() => _QrPaymentScreenState();
}

class _QrPaymentScreenState extends ConsumerState<QrPaymentScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic>? _qrData;
  bool _isLoading = true;
  String? _error;
  bool _scanned = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadQrData();
  }

  Future<void> _loadQrData() async {
    try {
      final data = await ApiService.getMyQrCode();
      if (!mounted) return;
      setState(() { _qrData = data; _isLoading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = 'Set up a bank account first'; _isLoading = false; });
    }
  }

  void _onQrDetected(BarcodeCapture capture) {
    if (_scanned) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue == null) return;
    setState(() => _scanned = true);
    HapticFeedback.heavyImpact();
    try {
      final data = jsonDecode(barcode!.rawValue!);
      final acct = data['account_number'] ?? '';
      final name = data['name'] ?? '';
      if (acct.isEmpty) { _resetScan('Invalid QR'); return; }
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.surfaceCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Pay via QR', style: TextStyle(color: Colors.white)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 64, height: 64, decoration: BoxDecoration(
              color: AppTheme.success.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
              child: const Icon(Icons.qr_code_scanner_rounded, color: AppTheme.success, size: 32)),
            const SizedBox(height: 16),
            Text('Account: $acct', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            if (name.isNotEmpty) Text('Name: $name', style: const TextStyle(color: AppTheme.textSecondary)),
          ]),
          actions: [
            TextButton(onPressed: () { Navigator.pop(ctx); setState(() => _scanned = false); },
              child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () { Navigator.pop(ctx); Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SendMoneyScreen())); },
              child: const Text('Pay Now', style: TextStyle(color: Colors.white))),
          ],
        ),
      );
    } catch (_) { _resetScan('Could not read QR'); }
  }

  void _resetScan(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: AppTheme.error));
    Future.delayed(const Duration(seconds: 2), () { if (mounted) setState(() => _scanned = false); });
  }

  @override
  void dispose() { _tabController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QR Payments'), backgroundColor: Colors.transparent, elevation: 0),
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
              tabs: const [Tab(icon: Icon(Icons.qr_code_rounded, size: 20), text: 'My QR'),
                Tab(icon: Icon(Icons.qr_code_scanner_rounded, size: 20), text: 'Scan QR')],
            ))),
          Expanded(child: TabBarView(controller: _tabController, children: [_buildMyQr(), _buildScan()])),
        ])),
      ),
    );
  }

  Widget _buildMyQr() {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: AppTheme.accent));
    if (_qrData == null) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.qr_code_rounded, color: AppTheme.textSecondary.withOpacity(0.3), size: 80),
      const SizedBox(height: 16),
      Text(_error ?? 'Unable to generate QR', style: const TextStyle(color: AppTheme.textSecondary)),
    ]));
    final payload = jsonEncode(_qrData);
    final name = _qrData!['name'] ?? '';
    final acct = _qrData!['account_number'] ?? '';
    return SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(children: [
      const SizedBox(height: 20),
      GlassCard(child: Column(children: [
        const Text('Your Payment QR', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text('Others can scan this to pay you', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        const SizedBox(height: 20),
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(20)),
          child: QrImageView(data: payload, version: QrVersions.auto, size: 200, backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF1a1a2e)),
            dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF1a1a2e)))),
        const SizedBox(height: 20),
        Text(name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        GestureDetector(onTap: () { Clipboard.setData(ClipboardData(text: acct)); HapticFeedback.lightImpact();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied'), backgroundColor: AppTheme.success)); },
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('A/C: $acct', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontFamily: 'monospace')),
            const SizedBox(width: 6), const Icon(Icons.copy_rounded, color: AppTheme.accent, size: 14)])),
      ])),
    ]));
  }

  Widget _buildScan() {
    return Padding(padding: const EdgeInsets.all(20), child: Column(children: [
      const Text('Point camera at a Fabio QR code', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
      const SizedBox(height: 16),
      Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(24), child: Stack(children: [
        MobileScanner(onDetect: _onQrDetected),
        Center(child: Container(width: 250, height: 250, decoration: BoxDecoration(
          border: Border.all(color: AppTheme.accent.withOpacity(0.5), width: 2),
          borderRadius: BorderRadius.circular(20)))),
        Positioned(bottom: 20, left: 0, right: 0, child: Center(child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(20)),
          child: Text(_scanned ? '✅ QR Detected!' : 'Scanning...',
            style: TextStyle(color: _scanned ? AppTheme.success : Colors.white, fontSize: 13))))),
      ]))),
    ]));
  }
}
