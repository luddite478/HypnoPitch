import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:wheel_chooser/wheel_chooser.dart';
import '../../../utils/app_colors.dart';
import '../../tutorial_pulse_widget.dart';

/// A reusable horizontal wheel selector widget for numeric values
/// 
/// Features:
/// - Horizontal scrolling wheel with visible neighboring values
/// - Haptic feedback on value changes
/// - Customizable value range and display formatting
/// - Clean, minimal design with no visual overlaps
class WheelSelectWidget extends StatelessWidget {
  /// Current selected value
  final int value;
  
  /// Minimum value (inclusive)
  final int minValue;
  
  /// Maximum value (inclusive)
  final int maxValue;
  
  /// Callback when value changes
  final ValueChanged<int> onValueChanged;
  
  /// Optional function to format the display value
  /// If null, displays the raw integer value
  final String Function(int)? valueFormatter;
  
  /// Whether to trigger haptic feedback on value change (default: true)
  final bool enableHaptic;

  /// When set with [tutorialItemKey], uses the custom wheel so this value's
  /// label can be anchored (e.g. tutorial highlight on "2").
  final int? tutorialHighlightValue;

  final GlobalKey? tutorialItemKey;

  const WheelSelectWidget({
    super.key,
    required this.value,
    required this.minValue,
    required this.maxValue,
    required this.onValueChanged,
    this.valueFormatter,
    this.enableHaptic = true,
    this.tutorialHighlightValue,
    this.tutorialItemKey,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        final availableWidth = constraints.maxWidth;

        final bool useCustomWheel =
            valueFormatter != null || tutorialItemKey != null;

        // Custom list wheel (formatter and/or tutorial anchor on one item).
        if (useCustomWheel) {
          final items = List.generate(
            maxValue - minValue + 1,
            (index) => valueFormatter != null
                ? valueFormatter!(minValue + index)
                : '${minValue + index}',
          );
          final int? highlightIndex = tutorialHighlightValue != null
              ? (tutorialHighlightValue! - minValue).clamp(0, items.length - 1)
              : null;

          return ClipRect(
            child: SizedBox(
              height: availableHeight,
              width: availableWidth,
              child: _CustomWheelWithGradient(
                items: items,
                selectedIndex: (value - minValue).clamp(0, items.length - 1),
                onValueChanged: (index) {
                  final intValue = minValue + index;
                  onValueChanged(intValue);
                  if (enableHaptic) {
                    HapticFeedback.selectionClick();
                  }
                },
                availableHeight: availableHeight,
                availableWidth: availableWidth,
                tutorialItemKey: tutorialItemKey,
                tutorialHighlightIndex: highlightIndex,
              ),
            ),
          );
        }

        // Default: use integer wheel
        return ClipRect(
          child: SizedBox(
            height: availableHeight,
            width: availableWidth,
            child: WheelChooser.integer(
              onValueChanged: (newValue) {
                onValueChanged(newValue);
                if (enableHaptic) {
                  HapticFeedback.selectionClick();
                }
              },
              maxValue: maxValue,
              minValue: minValue,
              initValue: value.clamp(minValue, maxValue),
              horizontal: true,
              listHeight: availableHeight,
              listWidth: availableWidth,
              squeeze: 0.8, // Tighter squeeze for better centering
              itemSize: availableWidth * 0.10, // Tighter spacing between values
              perspective: 0.003, // Slightly more perspective for depth
              magnification: 1.3, // Magnify center item
              selectTextStyle: GoogleFonts.crimsonPro(
                color: AppColors.sequencerAccent,
                fontSize: availableHeight * 0.38,
                fontWeight: FontWeight.w700,
                height: 1.0, // Tight line height to prevent overflow
              ),
              unSelectTextStyle: GoogleFonts.crimsonPro(
                color: AppColors.sequencerLightText.withOpacity(0.6),
                fontSize: availableHeight * 0.28,
                fontWeight: FontWeight.w500,
                height: 1.0, // Tight line height to prevent overflow
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A specialized wheel selector for musical semitones (-12 to +12)
/// Displays values as musical note names
class SemitoneWheelWidget extends StatelessWidget {
  final int semitones;
  final ValueChanged<int> onSemitonesChanged;
  final bool enableHaptic;
  final VoidCallback? onChangeStart;
  final VoidCallback? onChangeEnd;

  const SemitoneWheelWidget({
    super.key,
    required this.semitones,
    required this.onSemitonesChanged,
    this.enableHaptic = true,
    this.onChangeStart,
    this.onChangeEnd,
  });

  static const List<String> _noteNames = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'
  ];

  String _formatSemitones(int value) {
    // Convert semitones to note name
    final normalizedSemitones = value % 12;
    final noteIndex = normalizedSemitones < 0 ? normalizedSemitones + 12 : normalizedSemitones;
    return _noteNames[noteIndex];
  }

  @override
  Widget build(BuildContext context) {
    return _SemitoneWheelWithPreview(
      semitones: semitones,
      onSemitonesChanged: onSemitonesChanged,
      valueFormatter: _formatSemitones,
      enableHaptic: enableHaptic,
      onChangeStart: onChangeStart,
      onChangeEnd: onChangeEnd,
    );
  }
}

/// Internal stateful widget to handle preview callbacks
class _SemitoneWheelWithPreview extends StatefulWidget {
  final int semitones;
  final ValueChanged<int> onSemitonesChanged;
  final String Function(int) valueFormatter;
  final bool enableHaptic;
  final VoidCallback? onChangeStart;
  final VoidCallback? onChangeEnd;

  const _SemitoneWheelWithPreview({
    required this.semitones,
    required this.onSemitonesChanged,
    required this.valueFormatter,
    required this.enableHaptic,
    this.onChangeStart,
    this.onChangeEnd,
  });

  @override
  State<_SemitoneWheelWithPreview> createState() => _SemitoneWheelWithPreviewState();
}

class _SemitoneWheelWithPreviewState extends State<_SemitoneWheelWithPreview> {
  bool _isChanging = false;

  void _handleValueChanged(int value) {
    if (!_isChanging) {
      _isChanging = true;
      widget.onChangeStart?.call();
    }
    widget.onSemitonesChanged(value);
  }

  void _handleChangeEnd() {
    if (_isChanging) {
      _isChanging = false;
      widget.onChangeEnd?.call();
    }
  }

  @override
  void dispose() {
    _handleChangeEnd();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanEnd: (_) => _handleChangeEnd(),
      onPanCancel: () => _handleChangeEnd(),
      child: WheelSelectWidget(
        value: widget.semitones,
        minValue: -12,
        maxValue: 12,
        onValueChanged: _handleValueChanged,
        valueFormatter: widget.valueFormatter,
        enableHaptic: widget.enableHaptic,
      ),
    );
  }
}

/// Custom wheel chooser with gradient coloring for unselected items
class _CustomWheelWithGradient extends StatefulWidget {
  final List<String> items;
  final int selectedIndex;
  final ValueChanged<int> onValueChanged;
  final double availableHeight;
  final double availableWidth;
  final GlobalKey? tutorialItemKey;
  final int? tutorialHighlightIndex;

  const _CustomWheelWithGradient({
    required this.items,
    required this.selectedIndex,
    required this.onValueChanged,
    required this.availableHeight,
    required this.availableWidth,
    this.tutorialItemKey,
    this.tutorialHighlightIndex,
  });

  @override
  State<_CustomWheelWithGradient> createState() => _CustomWheelWithGradientState();
}

class _CustomWheelWithGradientState extends State<_CustomWheelWithGradient> {
  late FixedExtentScrollController _scrollController;
  bool _isUserScrolling = false;

  @override
  void initState() {
    super.initState();
    _scrollController = FixedExtentScrollController(initialItem: widget.selectedIndex);
    
    // Listen to scroll activity to detect when user is actively scrolling
    _scrollController.addListener(_onScrollChanged);
  }

  void _onScrollChanged() {
    // User is scrolling if the controller is actively being dragged
    final isScrolling = _scrollController.position.isScrollingNotifier.value;
    if (_isUserScrolling != isScrolling) {
      setState(() {
        _isUserScrolling = isScrolling;
      });
    }
  }

  @override
  void didUpdateWidget(_CustomWheelWithGradient oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only jump to new position if user is not actively scrolling
    // This prevents fighting between user gesture and programmatic updates
    if (oldWidget.selectedIndex != widget.selectedIndex && !_isUserScrolling) {
      _scrollController.jumpToItem(widget.selectedIndex);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScrollChanged);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotatedBox(
      quarterTurns: 3,
      child: ListWheelScrollView.useDelegate(
        controller: _scrollController,
        itemExtent: widget.availableWidth * 0.10,
        diameterRatio: 5.0,
        perspective: 0.003,
        squeeze: 0.8,
        magnification: 1.3,
        useMagnifier: true,
        onSelectedItemChanged: (index) {
          widget.onValueChanged(index);
        },
        physics: const FixedExtentScrollPhysics(),
        childDelegate: ListWheelChildBuilderDelegate(
          builder: (context, index) {
            if (index < 0 || index >= widget.items.length) return null;
            
            return RotatedBox(
              quarterTurns: 1,
              child: Center(
                child: AnimatedBuilder(
                  animation: _scrollController,
                  builder: (context, child) {
                    // Calculate opacity and color based on distance from selected item
                    double scrollOffset = 0.0;
                    if (_scrollController.hasClients && _scrollController.position.hasContentDimensions) {
                      scrollOffset = _scrollController.offset / (widget.availableWidth * 0.10);
                    }
                    
                    final distance = (index - scrollOffset).abs();
                    // Increased minimum opacity from 0.2 to 0.5 for better visibility
                    // Reduced fade rate from 0.4 to 0.25 for gentler gradient
                    final opacity = (1.0 - (distance * 0.25)).clamp(0.7, 1.0);
                    final isSelected = distance < 0.5;

                    Widget label = Text(
                      widget.items[index],
                      textAlign: TextAlign.center,
                      style: GoogleFonts.crimsonPro(
                        color: isSelected
                            ? AppColors.sequencerAccent
                            : AppColors.sequencerLightText.withOpacity(opacity),
                        fontSize: widget.availableHeight * 0.38,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        height: 1.0,
                      ),
                    );
                    if (widget.tutorialItemKey != null &&
                        widget.tutorialHighlightIndex != null &&
                        index == widget.tutorialHighlightIndex) {
                      label = KeyedSubtree(
                        key: widget.tutorialItemKey,
                        child: TutorialPulseWidget(
                          enabled: true,
                          borderRadius: BorderRadius.circular(4),
                          child: label,
                        ),
                      );
                    }
                    return label;
                  },
                ),
              ),
            );
          },
          childCount: widget.items.length,
        ),
      ),
    );
  }
}
