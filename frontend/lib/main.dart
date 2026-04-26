/// Fabio — Main Entry Point
///
/// App initialization, Riverpod, theme, and route configuration.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/theme.dart';
import 'services/notification_service.dart';
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
import 'screens/spending_analytics_screen.dart';
import 'screens/qr_payment_screen.dart';
import 'screens/request_money_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/onboarding_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();

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

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class AutoLockWrapper extends StatefulWidget {
  final Widget child;
  const AutoLockWrapper({super.key, required this.child});

  @override
  State<AutoLockWrapper> createState() => _AutoLockWrapperState();
}

class _AutoLockWrapperState extends State<AutoLockWrapper> {
  Timer? _timer;
  static const _timeout = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    _resetTimer();
  }

  void _resetTimer() {
    _timer?.cancel();
    _timer = Timer(_timeout, _lockApp);
  }

  void _lockApp() {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    final currentRoute = ModalRoute.of(ctx)?.settings.name;
    if (currentRoute != '/' && currentRoute != '/login' && currentRoute != '/register' && currentRoute != '/onboarding' && currentRoute != '/lock') {
      navigatorKey.currentState?.pushNamed('/lock');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _resetTimer(),
      onPointerMove: (_) => _resetTimer(),
      onPointerUp: (_) => _resetTimer(),
      child: widget.child,
    );
  }
}

class FabioApp extends StatelessWidget {
  const FabioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AutoLockWrapper(
      child: MaterialApp(
        title: 'Fabio',
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,

        initialRoute: '/',
      onGenerateRoute: (settings) {
        final routes = <String, WidgetBuilder>{
          '/': (_) => const SplashScreen(),
          '/login': (_) => const LoginScreen(),
          '/register': (_) => const RegisterScreen(),
          '/face-capture': (_) => const FaceCaptureScreen(),
          '/bank-setup': (_) => const BankSetupScreen(),
          '/set-pin': (_) => const SetPinScreen(),
          '/dashboard': (_) => const DashboardScreen(),
          '/send-money': (_) => const SendMoneyScreen(),
          '/liveness-check': (_) => const LivenessCheckScreen(),
          '/transaction-history': (_) => const TransactionHistoryScreen(),
          '/profile': (_) => const ProfileScreen(),
          '/beneficiaries': (_) => const BeneficiaryScreen(),
          '/admin': (_) => const AdminPanelScreen(),
          '/settings': (_) => const SettingsScreen(),
          '/analytics': (_) => const SpendingAnalyticsScreen(),
          '/qr-payment': (_) => const QrPaymentScreen(),
          '/request-money': (_) => const RequestMoneyScreen(),
          '/lock': (_) => const LockScreen(),
          '/onboarding': (_) => const OnboardingScreen(),
        };

        final builder = routes[settings.name];
        if (builder == null) return null;

        return PageRouteBuilder(
          settings: settings,
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder:
              (context, animation, secondaryAnimation, child) {
            const begin = Offset(1.0, 0.0);
            const end = Offset.zero;
            const curve = Curves.easeInOutCubic;
            final tween =
                Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
            final fadeTween = Tween(begin: 0.0, end: 1.0);
            return SlideTransition(
              position: animation.drive(tween),
              child: FadeTransition(
                opacity: animation.drive(fadeTween),
                child: child,
              ),
            );
          },
          transitionDuration: const Duration(milliseconds: 350),
        );
      },
    ));
  }
}
