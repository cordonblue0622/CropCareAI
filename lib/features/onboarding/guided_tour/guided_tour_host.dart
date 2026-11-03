import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'guided_tour_overlay.dart';
import 'guided_tour_service.dart';
import 'guided_tour_targets.dart';

/// Coordinates automatic launch, cross-tab navigation, target measurement,
/// and safe dismissal for the interactive app tour.
class GuidedTourHost extends StatefulWidget {
  final String userId;
  final Widget child;
  final ValueChanged<int> onSelectTab;
  final GuidedTourService service;
  final ScrollController? dashboardScrollController;
  final bool autoStart;

  const GuidedTourHost({
    super.key,
    required this.userId,
    required this.child,
    required this.onSelectTab,
    this.service = const GuidedTourService(),
    this.dashboardScrollController,
    this.autoStart = true,
  });

  @override
  State<GuidedTourHost> createState() => GuidedTourHostState();
}

class GuidedTourHostState extends State<GuidedTourHost>
    with WidgetsBindingObserver {
  final GlobalKey _rootKey = GlobalKey(debugLabel: 'guidedTourRoot');
  int _stepIndex = 0;
  int _transitionToken = 0;
  bool _active = false;
  bool _resolving = false;
  Rect? _targetRect;
  String? _autoStartUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoStart());
  }

  @override
  void didUpdateWidget(covariant GuidedTourHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId == widget.userId &&
        oldWidget.autoStart == widget.autoStart) {
      return;
    }
    _transitionToken++;
    _active = false;
    _resolving = false;
    _targetRect = null;
    _stepIndex = 0;
    _autoStartUserId = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoStart());
  }

  @override
  void dispose() {
    _transitionToken++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (!_active) return;
    final token = _transitionToken;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || token != _transitionToken || !_active) return;
      setState(() {
        _targetRect = _resolveTargetRect(GuidedTourSteps.values[_stepIndex]);
      });
    });
  }

  Future<void> _maybeAutoStart() async {
    final userId = widget.userId;
    if (!widget.autoStart ||
        userId.trim().isEmpty ||
        _active ||
        _autoStartUserId == userId) {
      return;
    }
    _autoStartUserId = userId;
    try {
      final complete = await widget.service.isComplete(userId);
      if (!mounted ||
          complete ||
          _active ||
          widget.userId != userId ||
          !widget.autoStart) {
        return;
      }
      await startTour();
    } catch (error) {
      debugPrint('[GuidedTour] Could not read local tour status: $error');
    }
  }

  /// Starts from the welcome step even when the automatic tour was completed.
  Future<void> startTour() async {
    if (_active || widget.userId.trim().isEmpty) return;
    _autoStartUserId = widget.userId;
    setState(() => _active = true);
    await _showStep(0);
  }

  Future<void> _showStep(int index) async {
    if (!_active || index < 0 || index >= GuidedTourSteps.values.length) {
      return;
    }
    final token = ++_transitionToken;
    final step = GuidedTourSteps.values[index];
    setState(() {
      _stepIndex = index;
      _resolving = true;
      _targetRect = null;
    });

    widget.onSelectTab(step.tabIndex);
    await WidgetsBinding.instance.endOfFrame;
    if (!_isCurrent(token)) return;

    if (step.scrollToTop) await _scrollDashboardToTop();
    if (!_isCurrent(token)) return;
    await _revealTarget(step);
    if (!_isCurrent(token)) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!_isCurrent(token)) return;

    setState(() {
      _targetRect = _resolveTargetRect(step);
      _resolving = false;
    });
  }

  bool _isCurrent(int token) => mounted && _active && token == _transitionToken;

  Future<void> _scrollDashboardToTop() async {
    final controller = widget.dashboardScrollController;
    if (controller == null || !controller.hasClients) return;
    if (controller.position.pixels == 0) return;
    await controller.animateTo(
      0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _revealTarget(GuidedTourStep step) async {
    final key = step.targetKey;
    if (key == null) return;

    for (var attempt = 0; attempt < 8; attempt++) {
      if (!mounted) return;
      final targetContext = key.currentContext;
      final renderObject = targetContext?.findRenderObject();
      if (targetContext != null &&
          targetContext.mounted &&
          renderObject is RenderBox &&
          renderObject.attached) {
        await Scrollable.ensureVisible(
          targetContext,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: 0.18,
        );
        return;
      }

      final controller = widget.dashboardScrollController;
      if (step.searchScrollable &&
          controller != null &&
          controller.hasClients) {
        final position = controller.position;
        if (position.pixels >= position.maxScrollExtent) return;
        await controller.animateTo(
          math.min(
            position.maxScrollExtent,
            position.pixels + position.viewportDimension * 0.7,
          ),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      } else {
        await WidgetsBinding.instance.endOfFrame;
      }
    }
  }

  Rect? _resolveTargetRect(GuidedTourStep step) {
    final key = step.targetKey;
    if (key == null) return null;
    final targetContext = key.currentContext;
    final targetBox = targetContext?.findRenderObject();
    final rootBox = _rootKey.currentContext?.findRenderObject();
    if (targetBox is! RenderBox ||
        rootBox is! RenderBox ||
        !targetBox.attached ||
        !targetBox.hasSize ||
        !rootBox.hasSize) {
      return null;
    }

    final origin = targetBox.localToGlobal(Offset.zero, ancestor: rootBox);
    final bounds = Offset.zero & rootBox.size;
    final visible = (origin & targetBox.size).intersect(bounds);
    if (visible.isEmpty) return null;

    return Rect.fromLTRB(
      math.max(0, visible.left - 6),
      math.max(0, visible.top - 6),
      math.min(bounds.width, visible.right + 6),
      math.min(bounds.height, visible.bottom + 6),
    );
  }

  void _goBack() {
    if (!_active || _resolving || _stepIndex == 0) return;
    _showStep(_stepIndex - 1);
  }

  Future<void> _dismiss() async {
    if (!_active) return;
    final userId = widget.userId;
    _transitionToken++;
    setState(() {
      _active = false;
      _resolving = false;
      _targetRect = null;
    });
    try {
      await widget.service.markComplete(userId);
    } catch (error) {
      debugPrint('[GuidedTour] Could not save local tour status: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = GuidedTourSteps.values[_stepIndex];
    return PopScope(
      canPop: !_active,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || !_active) return;
        if (_stepIndex > 0) {
          _goBack();
        } else {
          _dismiss();
        }
      },
      child: Stack(
        key: _rootKey,
        children: [
          ExcludeSemantics(
            excluding: _active,
            child: AbsorbPointer(absorbing: _active, child: widget.child),
          ),
          if (_active)
            Positioned.fill(
              child: GuidedTourOverlay(
                step: step,
                index: _stepIndex,
                total: GuidedTourSteps.values.length,
                targetRect: _targetRect,
                isResolving: _resolving,
                onNext: () {
                  if (_resolving) return;
                  if (_stepIndex == GuidedTourSteps.values.length - 1) {
                    _dismiss();
                  } else {
                    _showStep(_stepIndex + 1);
                  }
                },
                onBack: _goBack,
                onSkip: _dismiss,
              ),
            ),
        ],
      ),
    );
  }
}
