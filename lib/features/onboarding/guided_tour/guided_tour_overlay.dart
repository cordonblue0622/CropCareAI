import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import 'guided_tour_targets.dart';

class GuidedTourOverlay extends StatelessWidget {
  static const cardKey = ValueKey<String>('guided_tour_card');
  static const nextButtonKey = ValueKey<String>('guided_tour_next');
  static const backButtonKey = ValueKey<String>('guided_tour_back');
  static const skipButtonKey = ValueKey<String>('guided_tour_skip');
  static const finishButtonKey = ValueKey<String>('guided_tour_finish');

  final GuidedTourStep step;
  final int index;
  final int total;
  final Rect? targetRect;
  final bool isResolving;
  final VoidCallback onNext;
  final VoidCallback onBack;
  final VoidCallback onSkip;

  const GuidedTourOverlay({
    super.key,
    required this.step,
    required this.index,
    required this.total,
    required this.targetRect,
    required this.isResolving,
    required this.onNext,
    required this.onBack,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Guided app tour step ${index + 1} of $total',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: CustomPaint(
                    painter: _TourDimmerPainter(targetRect: targetRect),
                  ),
                ),
              ),
              if (isResolving)
                const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primaryLight,
                  ),
                )
              else
                _positionCard(context, size),
            ],
          );
        },
      ),
    );
  }

  Widget _positionCard(BuildContext context, Size size) {
    final padding = MediaQuery.paddingOf(context);
    final horizontalMargin = size.width < 360 ? 12.0 : 16.0;
    final topBound = padding.top + 12;
    final bottomBound = size.height - padding.bottom - 12;
    final availableHeight = (bottomBound - topBound).clamp(120.0, size.height);
    final card = _animatedCard();
    final rect = targetRect;

    if (rect == null) {
      return Positioned(
        left: horizontalMargin,
        right: horizontalMargin,
        top: topBound,
        bottom: size.height - bottomBound,
        child: Align(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 420,
              maxHeight: availableHeight,
            ),
            child: card,
          ),
        ),
      );
    }

    final aboveSpace = (rect.top - 12 - topBound).clamp(0.0, size.height);
    final belowSpace = (bottomBound - rect.bottom - 12).clamp(0.0, size.height);
    final placeAbove = aboveSpace > belowSpace;
    final maxHeight = placeAbove ? aboveSpace : belowSpace;

    // Very large targets can leave too little room on either side. In that
    // case, use a safe centered card rather than overflowing the viewport.
    if (maxHeight < 100) {
      return Positioned(
        left: horizontalMargin,
        right: horizontalMargin,
        top: topBound,
        bottom: size.height - bottomBound,
        child: Align(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 420,
              maxHeight: availableHeight,
            ),
            child: card,
          ),
        ),
      );
    }

    return Positioned(
      left: horizontalMargin,
      right: horizontalMargin,
      top: placeAbove ? null : rect.bottom + 12,
      bottom: placeAbove ? size.height - rect.top + 12 : null,
      child: Align(
        alignment: placeAbove ? Alignment.bottomCenter : Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 420, maxHeight: maxHeight),
          child: card,
        ),
      ),
    );
  }

  Widget _animatedCard() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey<int>(index),
        child: _buildCard(),
      ),
    );
  }

  Widget _buildCard() {
    final isLastStep = index == total - 1;
    return Material(
      key: cardKey,
      color: AppColors.backgroundWhite,
      elevation: 14,
      shadowColor: AppColors.primaryDark.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.backgroundGreenLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(step.icon, color: AppColors.primary, size: 24),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Step ${index + 1} of $total',
                    style: const TextStyle(
                      color: AppColors.textGray,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (!isLastStep)
                  TextButton(
                    key: skipButtonKey,
                    onPressed: onSkip,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(58, 44),
                      foregroundColor: AppColors.textMedium,
                    ),
                    child: const Text('Skip'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      step.title,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      step.description,
                      style: const TextStyle(
                        color: AppColors.textMedium,
                        fontSize: 14.5,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (index + 1) / total,
                minHeight: 4,
                backgroundColor: AppColors.backgroundGreenLight,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                if (index > 0) ...[
                  Expanded(
                    child: OutlinedButton(
                      key: backButtonKey,
                      onPressed: onBack,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 50),
                        foregroundColor: AppColors.primaryDark,
                        side: const BorderSide(color: AppColors.borderGreen),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Back'),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: ElevatedButton(
                    key: isLastStep ? finishButtonKey : nextButtonKey,
                    onPressed: onNext,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 50),
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      isLastStep ? 'Get Started' : 'Next',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TourDimmerPainter extends CustomPainter {
  final Rect? targetRect;

  const _TourDimmerPainter({required this.targetRect});

  @override
  void paint(Canvas canvas, Size size) {
    final screenPath = Path()..addRect(Offset.zero & size);
    final rect = targetRect;
    if (rect == null) {
      canvas.drawPath(
        screenPath,
        Paint()..color = Colors.black.withValues(alpha: 0.68),
      );
      return;
    }

    final highlight = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(16),
    );
    final highlightPath = Path()..addRRect(highlight);
    canvas.drawPath(
      Path.combine(PathOperation.difference, screenPath, highlightPath),
      Paint()..color = Colors.black.withValues(alpha: 0.68),
    );
    canvas.drawRRect(
      highlight,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.96)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    canvas.drawRRect(
      highlight.inflate(3),
      Paint()
        ..color = AppColors.primaryLight.withValues(alpha: 0.72)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _TourDimmerPainter oldDelegate) =>
      oldDelegate.targetRect != targetRect;
}
