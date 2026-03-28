import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

class TutorialPulseWidget extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final BorderRadius borderRadius;

  const TutorialPulseWidget({
    super.key,
    required this.child,
    required this.enabled,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  @override
  State<TutorialPulseWidget> createState() => _TutorialPulseWidgetState();
}

class _TutorialPulseWidgetState extends State<TutorialPulseWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulse = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant TutorialPulseWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    if (widget.enabled) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return AnimatedBuilder(
      animation: _pulse,
      child: widget.child,
      builder: (context, child) {
        final t = _pulse.value;
        return Stack(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: widget.borderRadius,
                border: Border.all(
                  color: AppColors.tutorialPulseColor.withOpacity(0.35 + (0.45 * t)),
                  width: 1.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.tutorialPulseColor.withOpacity(0.18 + (0.20 * t)),
                    blurRadius: 8 + (4 * t),
                    spreadRadius: 0.8 + (0.8 * t),
                  ),
                ],
              ),
              child: child,
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.tutorialPulseColor.withOpacity(0.10 + (0.22 * t)),
                    borderRadius: widget.borderRadius,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

