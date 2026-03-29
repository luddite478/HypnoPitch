import 'package:flutter/material.dart';
import '../../../utils/app_colors.dart';
import '../../../utils/sample_offset_calculator.dart';
import '../../../state/sequencer/recording_waveform.dart';

class LineMicWaveformWidget extends StatelessWidget {
  final List<int> samples;  // Single line of samples
  final int lineIndex;      // Which line this is (1-based)
  final int loopsNum;       // Total number of loops
  final bool isRecording;
  final double lineHeight;  // Fixed height per line
  final int? currentStep;   // Current playback step (for position indicator)
  final int? totalSteps;    // Total steps in section (for position calculation)
  final bool isSongMode;    // Whether in song mode (affects label format)
  final bool isActive;      // Whether this line is within the active loop range
  final RecordingWaveformState? waveformState;  // Optional: for offset indicator
  final int? layer;         // Optional: layer index (for offset lookup)
  final int? section;       // Optional: section index (for offset lookup)

  const LineMicWaveformWidget({
    super.key,
    required this.samples,
    required this.lineIndex,
    required this.loopsNum,
    required this.isRecording,
    required this.lineHeight,
    this.currentStep,
    this.totalSteps,
    required this.isSongMode,
    required this.isActive,
    this.waveformState,
    this.layer,
    this.section,
  });

  @override
  Widget build(BuildContext context) {
    // Get offset if waveformState is provided
    final offsetFrames = (waveformState != null && layer != null && section != null)
        ? waveformState!.getOffset(layer!, section!)
        : 0;
    
    return SizedBox(
      height: lineHeight,
      child: CustomPaint(
        painter: _LineMicWaveformPainter(
          samples: samples,
          lineIndex: lineIndex,
          loopsNum: loopsNum,
          lineHeight: lineHeight,
          currentStep: currentStep,
          totalSteps: totalSteps,
          isSongMode: isSongMode,
          isActive: isActive,
          offsetFrames: offsetFrames,
          waveformColor: isRecording ? AppColors.sequencerAccent : AppColors.sequencerText,
          gridColor: AppColors.sequencerBorder.withOpacity(0.5),
          labelColor: AppColors.sequencerLightText,
          positionColor: AppColors.sequencerAccent,
        ),
      ),
    );
  }
}

class _LineMicWaveformPainter extends CustomPainter {
  final List<int> samples;  // Single line of samples
  final int lineIndex;      // Which line this is (1-based)
  final int loopsNum;       // Total number of loops
  final double lineHeight;  // Fixed height for this line
  final int? currentStep;   // Current playback step
  final int? totalSteps;    // Total steps in section
  final bool isSongMode;    // Whether in song mode (affects label format)
  final bool isActive;      // Whether this line is within the active loop range
  final int offsetFrames;   // Sample offset in frames
  final Color waveformColor;
  final Color gridColor;
  final Color labelColor;
  final Color positionColor;

  static const double _labelWidth = 42;
  static const double _gridLineWidth = 0.5;

  _LineMicWaveformPainter({
    required this.samples,
    required this.lineIndex,
    required this.loopsNum,
    required this.lineHeight,
    this.currentStep,
    this.totalSteps,
    required this.isSongMode,
    required this.isActive,
    required this.offsetFrames,
    required this.waveformColor,
    required this.gridColor,
    required this.labelColor,
    required this.positionColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double waveformWidth = (size.width - _labelWidth).clamp(0.0, size.width);

    // Apply opacity based on active state (dimmed in song mode when beyond loop limit)
    final double opacity = isActive ? 1.0 : 0.35;

    final gridPaint = Paint()
      ..color = gridColor.withOpacity(gridColor.opacity * opacity)
      ..strokeWidth = _gridLineWidth;

    // Draw horizontal line at top
    canvas.drawLine(Offset(0, 0), Offset(size.width, 0), gridPaint);
    // Draw horizontal line at bottom
    canvas.drawLine(Offset(0, lineHeight), Offset(size.width, lineHeight), gridPaint);

    // Draw vertical grid lines
    final verticalGridCount = 8;
    for (int i = 1; i < verticalGridCount; i++) {
      final x = _labelWidth + (waveformWidth / verticalGridCount) * i;
      canvas.drawLine(Offset(x, 0), Offset(x, lineHeight), gridPaint);
    }

    // Draw offset indicator (if offset is set)
    if (offsetFrames != 0 && samples.isNotEmpty) {
      _drawOffsetIndicator(canvas, size, waveformWidth, opacity);
    }

    // Draw line label
    _drawLineLabel(canvas, opacity);

    // Draw waveform if samples exist
    if (samples.isNotEmpty) {
      final centerY = lineHeight / 2;
      final amplitude = lineHeight * 0.8;  // Increased from 0.4 to 0.8
      final path = Path();

      final int sampleCount = samples.length;
      for (int s = 0; s < sampleCount; s++) {
        final double x = _labelWidth + (waveformWidth * s / (sampleCount - 1).clamp(1, sampleCount));
        final double norm = samples[s] / 32768.0;
        final double y = centerY - (norm * amplitude);
        if (s == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }

      canvas.drawPath(
        path,
        Paint()
          ..color = waveformColor.withOpacity(waveformColor.opacity * opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }

    // Draw playback position indicator
    if (currentStep != null && totalSteps != null && totalSteps! > 0) {
      // Calculate which loop this line represents (0-based)
      final currentLoop = lineIndex - 1;
      
      // Calculate step position within this loop
      final stepInLoop = currentStep! % totalSteps!;
      
      // Calculate the current loop based on total steps played
      final playbackLoop = currentStep! ~/ totalSteps!;
      
      // Only draw indicator if we're on the current loop line
      if (playbackLoop == currentLoop) {
        final stepProgress = stepInLoop / totalSteps!;
        final positionX = _labelWidth + (waveformWidth * stepProgress);
        
        // Draw vertical position line (only if line is active)
        if (isActive) {
          final positionPaint = Paint()
            ..color = positionColor
            ..strokeWidth = 2.0;
          
          canvas.drawLine(
            Offset(positionX, 0),
            Offset(positionX, lineHeight),
            positionPaint,
          );
        }
      }
    }
  }

  void _drawLineLabel(Canvas canvas, double opacity) {
    // Song mode: show fraction like "1/4" (loop X of N total)
    // Loop mode: show simple number like "1" (loop number)
    final String label;
    if (isSongMode) {
      final int displayLoops = loopsNum > 0 ? loopsNum : 1;
      label = '$lineIndex/$displayLoops';
    } else {
      label = '$lineIndex';
    }
    
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: labelColor.withOpacity(labelColor.opacity * opacity),
          fontSize: (lineHeight * 0.25).clamp(8.0, 12.0),
          fontWeight: FontWeight.w600,
        ),
      ),
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(maxWidth: _labelWidth - 4);
    final offset = Offset(4, (lineHeight - textPainter.height) / 2);
    textPainter.paint(canvas, offset);
  }

  void _drawOffsetIndicator(Canvas canvas, Size size, double waveformWidth, double opacity) {
    if (offsetFrames == 0) return;
    
    final offsetMs = SampleOffsetCalculator.framesToTime(offsetFrames).inMilliseconds;
    
    // Calculate approximate position (10% from left for visual indication)
    // In the future, this could be calculated based on actual sample duration
    final offsetX = _labelWidth + (waveformWidth * 0.1);
    
    // Draw vertical line to indicate offset position
    final offsetPaint = Paint()
      ..color = Colors.orange.withOpacity(0.8 * opacity)
      ..strokeWidth = 2;
    
    canvas.drawLine(
      Offset(offsetX, 0),
      Offset(offsetX, lineHeight),
      offsetPaint,
    );
    
    // Draw offset label
    final textPainter = TextPainter(
      text: TextSpan(
        text: '${offsetMs > 0 ? '+' : ''}${offsetMs}ms',
        style: TextStyle(
          color: Colors.orange.withOpacity(opacity),
          fontSize: (lineHeight * 0.22).clamp(8.0, 11.0),
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    
    // Position label above the line
    final labelX = (offsetX + 4).clamp(0.0, size.width - textPainter.width);
    textPainter.paint(canvas, Offset(labelX, 4));
  }

  @override
  bool shouldRepaint(_LineMicWaveformPainter oldDelegate) {
    return oldDelegate.samples != samples ||
        oldDelegate.lineIndex != lineIndex ||
        oldDelegate.loopsNum != loopsNum ||
        oldDelegate.currentStep != currentStep ||
        oldDelegate.totalSteps != totalSteps ||
        oldDelegate.isSongMode != isSongMode ||
        oldDelegate.isActive != isActive ||
        oldDelegate.offsetFrames != offsetFrames ||
        oldDelegate.waveformColor != waveformColor;
  }
}
