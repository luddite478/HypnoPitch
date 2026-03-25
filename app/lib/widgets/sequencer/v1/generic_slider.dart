import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../state/sequencer/slider_overlay.dart';
// musical note formatting handled externally if needed
class MusicalNotes {
  static const List<String> _noteNames = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'
  ];
  
  static Map<String, String> getNoteInfo(int semitones) {
    final normalizedSemitones = semitones % 12;
    final noteIndex = normalizedSemitones < 0 ? normalizedSemitones + 12 : normalizedSemitones;
    final noteName = _noteNames[noteIndex];
    
    return {
      'note': noteName,
      'semitones': semitones.toString(),
    };
  }
}

enum SliderType {
  volume,
  pitch,
  bpm,
  steps,
}

// Custom thumb shape that displays the current value
class ValueDisplayThumbShape extends SliderComponentShape {
  final String value;
  final double thumbRadius;
  
  const ValueDisplayThumbShape({
    required this.value,
    required this.thumbRadius,
  });

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size.fromRadius(thumbRadius);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;
    
    // Draw the thumb background
    final Paint thumbPaint = Paint()
      ..color = const Color(0xFF8B7355) // AppColors.sequencerAccent
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(center, thumbRadius, thumbPaint);
    
    // Draw border
    final Paint borderPaint = Paint()
      ..color = const Color(0xFF5A5A57) // AppColors.sequencerBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    
    canvas.drawCircle(center, thumbRadius, borderPaint);
    
    // Draw the value text
    final TextPainter textPainter = TextPainter(
      text: TextSpan(
        text: this.value,
        style: TextStyle(
          color: Colors.white,
          fontSize: thumbRadius * 0.6,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    
    textPainter.layout();
    textPainter.paint(
      canvas,
      center - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }
}

class GenericSlider extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final int divisions;
  final SliderType type;
  final Function(double) onChanged;
  final double height;
  final SliderOverlayState? sliderOverlay; // optional overlay state
  final String? contextLabel;
  final ValueListenable<bool>? processingSource;

  const GenericSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.type,
    required this.onChanged,
    required this.height,
    required this.sliderOverlay,
    this.contextLabel,
    this.processingSource,
  });

  @override
  State<GenericSlider> createState() => _GenericSliderState();
}

class _GenericSliderState extends State<GenericSlider> {
  double? _transientValue;

  String _getSettingName() {
    switch (widget.type) {
      case SliderType.volume:
        return 'VOLUME';
      case SliderType.pitch:
        return 'PITCH';
      case SliderType.bpm:
        return 'BPM';
      case SliderType.steps:
        return 'JUMP';
    }
  }

  String _formatValue(double value) {
    switch (widget.type) {
      case SliderType.volume:
        final volumePercent = (value * 100).round();
        return '$volumePercent';
      case SliderType.pitch:
        final semitones = (value * 24 - 12).round();
        final noteInfo = MusicalNotes.getNoteInfo(semitones);
        return '${noteInfo['note']}';
      case SliderType.bpm:
        return '${value.round()}';
      case SliderType.steps:
        return '${value.round()}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final thumbRadius = (widget.height * 0.15).clamp(20.0, 40.0); // Much larger thumb
    final double displayedValue = _transientValue ?? widget.value;
    final currentValueText = _formatValue(displayedValue);
    
    final sliderTheme = SliderTheme.of(context).copyWith(
      activeTrackColor: const Color(0xFF8B7355),
      inactiveTrackColor: const Color(0xFF5A5A57),
      thumbColor: const Color(0xFF8B7355),
      trackHeight: (widget.height * 0.04).clamp(2.0, 8.0),
      thumbShape: ValueDisplayThumbShape(
        value: currentValueText,
        thumbRadius: thumbRadius,
      ),
    );

    // legacy buildSlider removed

    // Always allow moving the slider instantly; processing is handled by debounced commit
    final sliderWidget = Slider(
      value: displayedValue,
      onChanged: (newValue) {
        setState(() {
          _transientValue = newValue;
        });
        widget.onChanged(newValue);
        if (widget.sliderOverlay != null) {
          widget.sliderOverlay!.updateValue(_formatValue(newValue));
        }
      },
      onChangeStart: (newValue) {
        setState(() {
          _transientValue = newValue;
        });
        if (widget.sliderOverlay != null) {
          // Bind processing source for this interaction
          widget.sliderOverlay!.setProcessingSource(widget.processingSource);
          widget.sliderOverlay!.startInteraction(
            _getSettingName(),
            _formatValue(newValue),
            contextLabel: widget.contextLabel ?? '',
          );
        }
      },
      onChangeEnd: (newValue) {
        setState(() {
          _transientValue = null; // return control to external value
        });
        if (widget.sliderOverlay != null) {
          widget.sliderOverlay!.stopInteraction();
        }
      },
      min: widget.min,
      max: widget.max,
      divisions: widget.divisions,
    );

    return SliderTheme(
      data: sliderTheme,
      child: Listener(
        onPointerDown: (_) {
          if (widget.sliderOverlay != null) {
            // Ensure overlay opens even if onChangeStart doesn't fire yet
            widget.sliderOverlay!.setProcessingSource(widget.processingSource);
            widget.sliderOverlay!.startInteraction(
              _getSettingName(),
              _formatValue(displayedValue),
              contextLabel: widget.contextLabel ?? '',
            );
            // Slider overlay processing source is set by parent builders in sound_settings.dart
          }
        },
        onPointerUp: (_) {
          if (widget.sliderOverlay != null) {
            widget.sliderOverlay!.stopInteraction();
          }
        },
        child: sliderWidget,
      ),
    );
  }
} 