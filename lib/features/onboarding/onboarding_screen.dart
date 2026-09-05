import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../auth/screens/register_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  static const _pages = [
    _OnboardingPageData(
      step: '01',
      eyebrow: 'SCAN WITH CONFIDENCE',
      title: 'See crop problems\nmore clearly.',
      description:
          'Capture a focused photo of tomato, pechay, pepper, eggplant, or squash and review an AI-assisted crop health assessment.',
      icon: Icons.document_scanner_rounded,
      accent: Color(0xFFE4B63E),
      features: [
        (Icons.center_focus_strong_rounded, 'Guided crop scanning'),
        (Icons.health_and_safety_outlined, 'Safety-first recommendations'),
      ],
    ),
    _OnboardingPageData(
      step: '02',
      eyebrow: 'ASK NATURALLY',
      title: 'Your crop assistant,\nready in the field.',
      description:
          'Ask by text or voice, attach a crop photo, and get guidance grounded in the crop and symptoms you provide.',
      icon: Icons.graphic_eq_rounded,
      accent: Color(0xFF68C990),
      features: [
        (Icons.mic_none_rounded, 'Hands-free voice support'),
        (Icons.chat_bubble_outline_rounded, 'Conversation history'),
      ],
    ),
    _OnboardingPageData(
      step: '03',
      eyebrow: 'CARE WITH CONTEXT',
      title: 'Turn guidance into\nsteady recovery.',
      description:
          'Track real crop health scores, complete scheduled care tasks, and review progress from one organized workspace.',
      icon: Icons.monitor_heart_outlined,
      accent: Color(0xFFF08A42),
      features: [
        (Icons.task_alt_rounded, 'Daily treatment tasks'),
        (Icons.insights_rounded, 'Health and recovery trends'),
      ],
    ),
  ];

  final PageController _controller = PageController();
  late final AnimationController _liquidController;
  int _page = 0;
  bool _isFinishing = false;

  @override
  void initState() {
    super.initState();
    _liquidController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    _liquidController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_isFinishing) return;
    setState(() => _isFinishing = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyOnboardingDone, true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
    );
  }

  Future<void> _next() async {
    if (_page == _pages.length - 1) {
      await _finish();
      return;
    }
    await _controller.nextPage(
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryDark,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _Atmosphere(),
          SafeArea(
            child: Column(
              children: [
                _TopBar(onSkip: _finish),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _pages.length,
                    onPageChanged: (page) => setState(() => _page = page),
                    itemBuilder: (_, index) => _OnboardingPage(
                      data: _pages[index],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: _GlassPanel(
                    padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: _LiquidProgress(
                            page: _page,
                            pageCount: _pages.length,
                            animation: _liquidController,
                          ),
                        ),
                        const SizedBox(width: 14),
                        _LiquidActionButton(
                          key: const ValueKey('onboarding_next_button'),
                          label: _page == _pages.length - 1
                              ? 'Start growing'
                              : 'Continue',
                          icon: _page == _pages.length - 1
                              ? Icons.eco_rounded
                              : Icons.arrow_forward_rounded,
                          isLoading: _isFinishing,
                          animation: _liquidController,
                          onPressed: _isFinishing ? null : _next,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final VoidCallback onSkip;

  const _TopBar({required this.onSkip});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
      child: Row(
        children: [
          Image.asset(
            'assets/images/cropcare_logo.png',
            width: 42,
            height: 42,
            filterQuality: FilterQuality.high,
          ),
          const SizedBox(width: 10),
          const Text(
            'CropCare AI',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: onSkip,
            style: TextButton.styleFrom(foregroundColor: Colors.white70),
            child: const Text('Skip'),
          ),
        ],
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  final _OnboardingPageData data;

  const _OnboardingPage({required this.data});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 620;
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(20, compact ? 8 : 20, 20, 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _FeatureVisual(data: data, compact: compact),
                SizedBox(height: compact ? 22 : 32),
                Row(
                  children: [
                    Container(width: 34, height: 2, color: data.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${data.eyebrow}  /  ${data.step}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: data.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  data.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    height: 1.08,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 13),
                Text(
                  data.description,
                  style: const TextStyle(
                    color: Color(0xFFDCEAE1),
                    fontSize: 14,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 9,
                  runSpacing: 9,
                  children: data.features
                      .map(
                        (feature) => _FeatureChip(
                          icon: feature.$1,
                          label: feature.$2,
                          accent: data.accent,
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FeatureVisual extends StatelessWidget {
  final _OnboardingPageData data;
  final bool compact;

  const _FeatureVisual({required this.data, required this.compact});

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      padding: EdgeInsets.all(compact ? 20 : 26),
      child: SizedBox(
        height: compact ? 150 : 205,
        width: double.infinity,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size.infinite,
              painter: _ContourPainter(color: data.accent),
            ),
            Container(
              width: compact ? 106 : 136,
              height: compact ? 106 : 136,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: data.accent.withValues(alpha: 0.14),
                border: Border.all(
                  color: data.accent.withValues(alpha: 0.7),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: data.accent.withValues(alpha: 0.2),
                    blurRadius: 34,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Icon(
                data.icon,
                color: Colors.white,
                size: compact ? 50 : 62,
              ),
            ),
            Positioned(
              right: 4,
              top: 4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  '${data.step} / 03',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;

  const _FeatureChip({
    required this.icon,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 17),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _GlassPanel({required this.child, required this.padding});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.11),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _LiquidProgress extends StatelessWidget {
  final int page;
  final int pageCount;
  final Animation<double> animation;

  const _LiquidProgress({
    required this.page,
    required this.pageCount,
    required this.animation,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Onboarding step ${page + 1} of $pageCount',
      child: SizedBox(
        height: 34,
        child: AnimatedBuilder(
          animation: animation,
          builder: (_, __) => CustomPaint(
            painter: _LiquidProgressPainter(
              progress: (page + 1) / pageCount,
              phase: animation.value,
              activeStep: page,
              pageCount: pageCount,
            ),
          ),
        ),
      ),
    );
  }
}

class _LiquidActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isLoading;
  final Animation<double> animation;
  final VoidCallback? onPressed;

  const _LiquidActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.isLoading,
    required this.animation,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, child) {
        final glow =
            0.18 + (math.sin(animation.value * math.pi * 2) + 1) * 0.06;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryLight.withValues(alpha: glow),
                blurRadius: 18,
                spreadRadius: 1,
              ),
            ],
          ),
          child: child,
        );
      },
      child: FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size(148, 52),
          backgroundColor: AppColors.primaryLight,
          foregroundColor: AppColors.primaryDark,
          disabledBackgroundColor:
              AppColors.primaryLight.withValues(alpha: 0.6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: isLoading
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon, size: 20),
        label: Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _LiquidProgressPainter extends CustomPainter {
  final double progress;
  final double phase;
  final int activeStep;
  final int pageCount;

  const _LiquidProgressPainter({
    required this.progress,
    required this.phase,
    required this.activeStep,
    required this.pageCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const railHeight = 10.0;
    final railTop = (size.height - railHeight) / 2;
    final rail = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, railTop, size.width, railHeight),
      const Radius.circular(5),
    );
    canvas.drawRRect(
      rail,
      Paint()..color = Colors.white.withValues(alpha: 0.14),
    );

    final fillWidth = math.max(railHeight, size.width * progress);
    canvas.save();
    canvas.clipRRect(rail);
    final liquidPath = Path()..moveTo(0, size.height);
    final waveTop = railTop + 1.5;
    for (double x = 0; x <= fillWidth; x += 2) {
      final wave = math.sin((x / 16) + phase * math.pi * 2) * 1.5;
      liquidPath.lineTo(x, waveTop + wave);
    }
    liquidPath
      ..lineTo(fillWidth, size.height)
      ..close();
    canvas.drawPath(
      liquidPath,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFE4B63E), Color(0xFF68C990)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
    canvas.restore();

    for (var index = 0; index < pageCount; index++) {
      final x = pageCount == 1 ? 0.0 : size.width * index / (pageCount - 1);
      canvas.drawCircle(
        Offset(x.clamp(5, size.width - 5), size.height / 2),
        4,
        Paint()
          ..color = index <= activeStep
              ? Colors.white
              : Colors.white.withValues(alpha: 0.32),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LiquidProgressPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.phase != phase ||
      oldDelegate.activeStep != activeStep;
}

class _ContourPainter extends CustomPainter {
  final Color color;

  const _ContourPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var ring = 0; ring < 4; ring++) {
      final inset = 18.0 + ring * 17;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            inset,
            inset * 0.55,
            math.max(0, size.width - inset * 2),
            math.max(0, size.height - inset * 1.1),
          ),
          Radius.circular(28 + ring * 9),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ContourPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _Atmosphere extends StatelessWidget {
  const _Atmosphere();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF102F21), Color(0xFF1D5A39), Color(0xFF173D30)],
          stops: [0, 0.55, 1],
        ),
      ),
      child: CustomPaint(painter: _FieldLinesPainter()),
    );
  }
}

class _FieldLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.045)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var index = -2; index < 12; index++) {
      final path = Path()
        ..moveTo(index * 70.0, size.height)
        ..quadraticBezierTo(
          size.width * 0.5,
          size.height * 0.48,
          size.width * 0.58,
          0,
        );
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _OnboardingPageData {
  final String step;
  final String eyebrow;
  final String title;
  final String description;
  final IconData icon;
  final Color accent;
  final List<(IconData, String)> features;

  const _OnboardingPageData({
    required this.step,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.icon,
    required this.accent,
    required this.features,
  });
}
