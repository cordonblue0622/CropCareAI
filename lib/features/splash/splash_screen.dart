import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../auth/providers/auth_provider.dart';
import '../auth/screens/login_screen.dart';
import '../home/home_screen.dart';
import '../onboarding/onboarding_screen.dart';

/// Landing / splash screen.
/// On app start it checks whether the user is already authenticated
/// and routes accordingly.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    _autoRoute();
  }

  Future<void> _autoRoute() async {
    // Small delay so the splash is visible before navigating
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    _routeIfAuthenticated();
  }

  void _routeIfAuthenticated() {
    if (_navigating) return;

    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) {
      return;
    }

    _navigating = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AuthProvider>();
    _routeIfAuthenticated();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.splashGrad1,
              AppColors.splashGrad2,
              AppColors.splashGrad3,
              AppColors.splashGrad4,
            ],
            stops: [0.0, 0.28, 0.62, 1.0],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // ── Decorative geometric blobs ──────────────────────
              const Positioned(
                  top: -40, right: -60, child: _Blob(size: 240, opacity: 0.30)),
              const Positioned(
                  top: 110, right: 40, child: _Blob(size: 110, opacity: 0.18)),
              const Positioned(
                  bottom: 160,
                  left: -80,
                  child: _Blob(size: 280, opacity: 0.22)),
              const Positioned(
                  bottom: -20,
                  right: -20,
                  child: _Blob(size: 150, opacity: 0.17)),

              // ── Main content ────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  children: [
                    const SizedBox(height: 14),
                    // Pull-handle dash
                    Center(
                      child: Container(
                        width: 56,
                        height: 4,
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF5A8878).withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    const Spacer(),

                    // ── App icon ────────────────────────────────────
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEEEEE),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.eco_rounded,
                              color: Color(0xFF2E7D45), size: 52),
                        ),
                      ),
                    ),

                    const SizedBox(height: 30),

                    // ── Title ───────────────────────────────────────
                    const Text(
                      'CropCare AI',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1A4D2E),
                        letterSpacing: -1,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── Subtitle ────────────────────────────────────
                    RichText(
                      textAlign: TextAlign.center,
                      text: const TextSpan(
                        style: TextStyle(
                            fontSize: 16,
                            color: Color(0xFF4A6055),
                            height: 1.55),
                        children: [
                          TextSpan(text: 'Precision diagnostics for a '),
                          TextSpan(
                            text: 'flourishing',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1A5C2E),
                            ),
                          ),
                          TextSpan(text: '\nharvest.'),
                        ],
                      ),
                    ),

                    const Spacer(flex: 2),

                    // ── Get Started button (orange) ─────────────────
                    _GetStartedButton(
                      onTap: () => _goToOnboarding(context),
                    ),
                    const SizedBox(height: 22),

                    // ── Sign In link ────────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Already a partner? ',
                          style: TextStyle(
                              fontSize: 14, color: Color(0xFF5A6E66)),
                        ),
                        GestureDetector(
                          onTap: () => _goToLogin(context),
                          child: const Text(
                            'Sign In',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1A4D2E),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // ── Enterprise badge ────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shield_outlined,
                            size: 13, color: Colors.grey.shade600),
                        const SizedBox(width: 6),
                        Text(
                          'ENTERPRISE GRADE AGRONOMY',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _goToOnboarding(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool(AppConstants.keyOnboardingDone) ?? false;
    if (!context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          done ? const LoginScreen() : const OnboardingScreen(),
    ));
  }

  void _goToLogin(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }
}

// ─── Private widgets ──────────────────────────────────────────────────────────

class _Blob extends StatelessWidget {
  final double size;
  final double opacity;
  const _Blob({required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF9ABFB0).withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(size * 0.35),
      ),
    );
  }
}

class _GetStartedButton extends StatelessWidget {
  final VoidCallback onTap;
  const _GetStartedButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.buttonOrange,
          foregroundColor: const Color(0xFF3D1800),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Get Started',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF3D1800)),
            ),
            SizedBox(width: 8),
            Icon(Icons.arrow_forward, size: 20, color: Color(0xFF3D1800)),
          ],
        ),
      ),
    );
  }
}
