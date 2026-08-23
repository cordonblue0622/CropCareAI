import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../auth/screens/register_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyOnboardingDone, true);
    if (mounted) {
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const RegisterScreen()));
    }
  }

  void _next() {
    if (_page < 2) {
      _controller.nextPage(
          duration: const Duration(milliseconds: 380), curve: Curves.easeInOut);
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          PageView(
            controller: _controller,
            onPageChanged: (i) => setState(() => _page = i),
            children: [
              _Page1(onNext: _next),
              _Page2(onNext: _next),
              _Page3(onFinish: _finish),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  PAGE 1 — Identify Crop Diseases Instantly
// ═══════════════════════════════════════════════════════════════════════════

class _Page1 extends StatelessWidget {
  final VoidCallback onNext;
  const _Page1({required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Image section (60 % height) ─────────────────────────────────
        Expanded(
          flex: 60,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
                  ),
                ),
              ),

              // Simulated photo overlay
              Opacity(
                opacity: 0.35,
                child: Container(color: const Color(0xFF0A3D1F)),
              ),

              // "CropCare AI" white italic top-left
              const SafeArea(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      'CropCare AI',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ),
              ),

              // Orange camera card (bottom-right of image)
              Positioned(
                right: 28,
                bottom: 28,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.buttonOrange,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.buttonOrange.withValues(alpha: 0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.camera_alt_rounded,
                      color: Colors.white, size: 38),
                ),
              ),
            ],
          ),
        ),

        // ── White bottom section ─────────────────────────────────────────
        Expanded(
          flex: 40,
          child: Container(
            color: AppColors.backgroundCream,
            padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                RichText(
                  text: const TextSpan(
                    style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        height: 1.15),
                    children: [
                      TextSpan(
                          text: 'Identify Crop\n',
                          style: TextStyle(color: Color(0xFF1A4D2E))),
                      TextSpan(
                          text: 'Diseases ',
                          style: TextStyle(color: AppColors.accentOrange)),
                      TextSpan(
                          text: 'Instantly',
                          style: TextStyle(color: Color(0xFF1A4D2E))),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Description
                RichText(
                  text: const TextSpan(
                    style: TextStyle(
                        fontSize: 14, color: AppColors.textGray, height: 1.55),
                    children: [
                      TextSpan(
                          text:
                              'Snap a photo or record a short video of your '),
                      TextSpan(
                          text: 'tomato, pechay, pepper, eggplant,',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1A4D2E))),
                      TextSpan(text: ' or '),
                      TextSpan(
                          text: 'squash',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1A4D2E))),
                      TextSpan(text: '.'),
                    ],
                  ),
                ),

                const Spacer(),
                _BottomRow(page: 0, onNext: onNext, label: 'Get Started'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  PAGE 2 — Talk to Your Vegetable Doctor
// ═══════════════════════════════════════════════════════════════════════════

class _Page2 extends StatelessWidget {
  final VoidCallback onNext;
  const _Page2({required this.onNext});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Step badge
            const _StepBadge(label: 'STEP 02'),
            const SizedBox(height: 18),

            // Title
            RichText(
              text: const TextSpan(
                style: TextStyle(height: 1.2),
                children: [
                  TextSpan(
                      text: 'Talk to Your\n',
                      style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textDark)),
                  TextSpan(
                      text: 'Vegetable ',
                      style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textDark)),
                  TextSpan(
                      text: 'Doctor',
                      style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                          color: AppColors.accentOrange)),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Description
            RichText(
              text: const TextSpan(
                style: TextStyle(
                    fontSize: 14, color: AppColors.textGray, height: 1.6),
                children: [
                  TextSpan(text: 'Use voice commands like '),
                  TextSpan(
                      text: '"Start Diagnosis"',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A5C2E))),
                  TextSpan(text: ' or '),
                  TextSpan(
                      text: '"Show Treatment"',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A5C2E))),
                  TextSpan(
                      text: ' to get instant help while working in the field.'),
                ],
              ),
            ),
            const SizedBox(height: 22),

            // Voice UI card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F0EE),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  // Mic button
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.35),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.mic_rounded,
                        color: Colors.white, size: 28),
                  ),
                  const SizedBox(height: 14),

                  // Waveform
                  _Waveform(),
                  const SizedBox(height: 10),

                  Text(
                    'LISTENING...',
                    style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade500),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '"Is my corn healthy?"',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Voice command chips
            const _VoiceChip(
                icon: Icons.person_outlined, text: '"Identify this pest"'),
            const SizedBox(height: 8),
            const _VoiceChip(
                icon: Icons.history_rounded, text: '"Read last treatment"'),

            const Spacer(),
            _BottomRow(page: 1, onNext: onNext, label: 'Next'),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  PAGE 3 — Track Recovery & Get Reminders
// ═══════════════════════════════════════════════════════════════════════════

class _Page3 extends StatelessWidget {
  final VoidCallback onFinish;
  const _Page3({required this.onFinish});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Step row
                    Row(
                      children: [
                        Row(
                          children: List.generate(
                              3,
                              (i) => Container(
                                    width: i == 2 ? 28 : 22,
                                    height: 4,
                                    margin: const EdgeInsets.only(right: 4),
                                    decoration: BoxDecoration(
                                      color: i == 2
                                          ? AppColors.primary
                                          : Colors.grey.shade300,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  )),
                        ),
                        const Spacer(),
                        const Text(
                          'STEP 3/3',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textGray,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Title
                    RichText(
                      text: const TextSpan(
                        style: TextStyle(height: 1.2),
                        children: [
                          TextSpan(
                              text: 'Track Recovery &\n',
                              style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.textDark)),
                          TextSpan(
                              text: 'Get Reminders',
                              style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.primary)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Follow your personalized treatment plan, mark tasks on your calendar, and see your crops get healthy again.',
                      style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textGray,
                          height: 1.55),
                    ),
                    const SizedBox(height: 18),

                    // Mini calendar
                    _MiniCalendar(),
                    const SizedBox(height: 10),

                    // Task card
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 10,
                              offset: const Offset(0, 3)),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF0E0),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.water_drop_outlined,
                                color: AppColors.buttonOrange, size: 22),
                          ),
                          const SizedBox(width: 12),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Apply Fungicide',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: AppColors.textDark)),
                              Text('Scheduled for 08:30 AM',
                                  style: TextStyle(
                                      fontSize: 12, color: AppColors.textGray)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Vitality Index card
                    _VitalityCard(),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _BottomRow(
              page: 2,
              onNext: onFinish,
              label: 'Finish',
              trailingIcon: const Icon(Icons.check_circle_outline,
                  size: 20, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Shared sub-widgets ───────────────────────────────────────────────────────

class _BottomRow extends StatelessWidget {
  final int page;
  final VoidCallback onNext;
  final String label;
  final Widget? trailingIcon;

  const _BottomRow({
    required this.page,
    required this.onNext,
    required this.label,
    this.trailingIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Dots
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final active = i == page;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: active ? 28 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: active ? AppColors.primary : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 16),

        // Button
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: onNext,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                trailingIcon ??
                    const Icon(Icons.arrow_forward,
                        size: 18, color: Colors.white),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StepBadge extends StatelessWidget {
  final String label;
  const _StepBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8),
      ),
    );
  }
}

class _Waveform extends StatelessWidget {
  final List<double> bars = const [
    0.4,
    0.7,
    1.0,
    0.6,
    0.9,
    0.5,
    0.8,
    1.0,
    0.6,
    0.4
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: bars
            .map((h) => Container(
                  width: 4,
                  height: 36 * h,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _VoiceChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _VoiceChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0EE),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textGray),
          const SizedBox(width: 10),
          Text(text,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMedium)),
        ],
      ),
    );
  }
}

class _MiniCalendar extends StatelessWidget {
  final List<String> days = const ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monthLabel = DateFormat('MMMM yyyy').format(now);
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final visibleDays = List.generate(
      7,
      (i) => DateTime(weekStart.year, weekStart.month, weekStart.day + i),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(monthLabel,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15)),
              const Spacer(),
              Icon(Icons.chevron_left, color: Colors.grey.shade500),
              Icon(Icons.chevron_right, color: Colors.grey.shade500),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: days
                .map((d) => SizedBox(
                      width: 32,
                      child: Center(
                        child: Text(d,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textGray)),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 6),
          // Week row — simplified for demo
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: visibleDays.map((day) {
              final active = _isSameDay(day, now);
              final isOutsideCurrentMonth = day.month != now.month;
              return Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: active ? AppColors.primary : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${day.day}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: active
                          ? Colors.white
                          : (isOutsideCurrentMonth
                              ? Colors.grey.shade400
                              : AppColors.textDark),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _VitalityCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart_rounded,
                  color: Colors.white70, size: 20),
              const SizedBox(width: 8),
              const Text('Vitality Index',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('+24% Weekly',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Simple line chart mockup
          CustomPaint(
            size: const Size(double.infinity, 50),
            painter: _ChartPainter(),
          ),
          const SizedBox(height: 12),
          const Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ESTIMATED RECOVERY',
                      style: TextStyle(
                          color: Colors.white60,
                          fontSize: 10,
                          letterSpacing: 0.8)),
                  SizedBox(height: 2),
                  Text('4 Days Left',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                ],
              ),
              Spacer(),
              Icon(Icons.monitor_heart_outlined,
                  color: Colors.white60, size: 26),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    final points = [
      Offset(0, size.height * 0.8),
      Offset(size.width * 0.2, size.height * 0.75),
      Offset(size.width * 0.4, size.height * 0.6),
      Offset(size.width * 0.55, size.height * 0.55),
      Offset(size.width * 0.7, size.height * 0.35),
      Offset(size.width * 0.85, size.height * 0.2),
      Offset(size.width, size.height * 0.1),
    ];

    path.moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final cpX = (prev.dx + curr.dx) / 2;
      path.cubicTo(cpX, prev.dy, cpX, curr.dy, curr.dx, curr.dy);
    }

    // Fill
    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.25),
            Colors.white.withValues(alpha: 0.02),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    // Line
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Dot at end
    canvas.drawCircle(
      points.last,
      5,
      Paint()..color = AppColors.buttonOrange,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
