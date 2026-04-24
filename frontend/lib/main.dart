/// Fabio — Main Entry Point
///
/// App initialization, Riverpod, theme, and route configuration.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/theme.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/face_capture_screen.dart';
import 'screens/bank_setup_screen.dart';
import 'screens/set_pin_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/send_money_screen.dart';
import 'screens/liveness_check_screen.dart';
import 'screens/transaction_history_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/beneficiary_screen.dart';
import 'screens/admin_panel_screen.dart';
import 'screens/settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppTheme.surface,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const ProviderScope(child: FabioApp()));
}

class FabioApp extends StatelessWidget {
  const FabioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fabio',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,

      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/face-capture': (context) => const FaceCaptureScreen(),
        '/bank-setup': (context) => const BankSetupScreen(),
        '/set-pin': (context) => const SetPinScreen(),
        '/dashboard': (context) => const DashboardScreen(),
        '/send-money': (context) => const SendMoneyScreen(),
        '/liveness-check': (context) => const LivenessCheckScreen(),
        '/transaction-history': (context) => const TransactionHistoryScreen(),
        '/profile': (context) => const ProfileScreen(),
        '/beneficiaries': (context) => const BeneficiaryScreen(),
        '/admin': (context) => const AdminPanelScreen(),
        '/settings': (context) => const SettingsScreen(),
      },
    );
  }
}
