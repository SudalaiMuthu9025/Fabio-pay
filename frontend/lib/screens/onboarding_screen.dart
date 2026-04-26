/// Fabio — Onboarding Screen
///
/// First-time user walkthrough with animated carousel pages.

import 'package:flutter/material.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import '../config/theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _currentPage = 0;

  static const _pages = [
    _OnboardingPage(
      icon: Icons.shield_rounded,
      gradient: [Color(0xFF6C63FF), Color(0xFF4834D4)],
      title: 'Secure Payments',
      subtitle: 'Bank-grade security with biometric face verification and PIN protection for every transaction.',
    ),
    _OnboardingPage(
      icon: Icons.flash_on_rounded,
      gradient: [Color(0xFF00BCD4), Color(0xFF0097A7)],
      title: 'Instant Transfers',
      subtitle: 'Send money via UPI, bank account, or QR code — lightning fast and completely secure.',
    ),
    _OnboardingPage(
      icon: Icons.analytics_rounded,
      gradient: [Color(0xFF00E676), Color(0xFF00C853)],
      title: 'Smart Analytics',
      subtitle: 'Track your spending with beautiful charts. Know where your money goes, weekly and monthly.',
    ),
    _OnboardingPage(
      icon: Icons.rocket_launch_rounded,
      gradient: [Color(0xFFFF6B6B), Color(0xFFEE5A24)],
      title: 'Get Started',
      subtitle: 'Your premium fintech experience awaits. Create your account and start transacting today!',
    ),
  ];

  Future<void> _complete() async {
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isLast = _currentPage == _pages.length - 1;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: SafeArea(child: Column(children: [
          // Skip button
          Align(alignment: Alignment.topRight, child: Padding(
            padding: const EdgeInsets.all(16),
            child: TextButton(onPressed: _complete,
              child: Text(isLast ? '' : 'Skip',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 15))))),

          // Pages
          Expanded(child: PageView.builder(
            controller: _controller, itemCount: _pages.length,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemBuilder: (_, i) {
              final page = _pages[i];
              return Padding(padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  // Icon
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.elasticOut,
                    builder: (_, val, child) => Transform.scale(scale: val, child: child),
                    child: Container(width: 120, height: 120, decoration: BoxDecoration(
                      gradient: LinearGradient(colors: page.gradient),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: page.gradient[0].withValues(alpha: 0.4), blurRadius: 30, offset: const Offset(0, 10))]),
                      child: Icon(page.icon, color: Colors.white, size: 56))),
                  const SizedBox(height: 48),
                  Text(page.title, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800),
                    textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  Text(page.subtitle, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 16, height: 1.5),
                    textAlign: TextAlign.center),
                ]));
            },
          )),

          // Indicator + Button
          Padding(padding: const EdgeInsets.all(32), child: Column(children: [
            SmoothPageIndicator(controller: _controller, count: _pages.length,
              effect: ExpandingDotsEffect(
                activeDotColor: AppTheme.accent, dotColor: AppTheme.textSecondary.withValues(alpha: 0.3),
                dotHeight: 8, dotWidth: 8, expansionFactor: 3)),
            const SizedBox(height: 32),
            SizedBox(width: double.infinity, height: 56, child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isLast ? AppTheme.accent : Colors.white.withValues(alpha: 0.1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
              onPressed: () {
                if (isLast) { _complete(); }
                else { _controller.nextPage(duration: const Duration(milliseconds: 400), curve: Curves.easeInOut); }
              },
              child: Text(isLast ? 'Get Started 🚀' : 'Next',
                style: TextStyle(color: isLast ? Colors.white : AppTheme.accent,
                  fontSize: 16, fontWeight: FontWeight.w600)))),
          ])),
        ])),
      ),
    );
  }
}

class _OnboardingPage {
  final IconData icon;
  final List<Color> gradient;
  final String title;
  final String subtitle;
  const _OnboardingPage({required this.icon, required this.gradient, required this.title, required this.subtitle});
}

