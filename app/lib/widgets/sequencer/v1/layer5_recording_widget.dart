import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../state/sequencer/recording_waveform.dart';
import '../../../state/sequencer/recording.dart';
import '../../../utils/app_colors.dart';

class Layer5RecordingWidget extends StatelessWidget {
  const Layer5RecordingWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<RecordingState, RecordingWaveformState>(
      builder: (context, recordingState, waveformState, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final columnWidth = constraints.maxWidth / 4;
            final columnHeight = constraints.maxHeight;

            return Row(
              children: List.generate(4, (trackIndex) {
                return SizedBox(
                  width: columnWidth,
                  height: columnHeight,
                  child: _buildTrackColumn(
                    context,
                    trackIndex,
                    recordingState,
                    waveformState,
                    columnWidth,
                    columnHeight,
                  ),
                );
              }),
            );
          },
        );
      },
    );
  }

  Widget _buildTrackColumn(
    BuildContext context,
    int trackIndex,
    RecordingState recordingState,
    RecordingWaveformState waveformState,
    double width,
    double height,
  ) {
    final track = waveformState.getTrack(trackIndex);
    final isSelected = waveformState.selectedTrack == trackIndex;
    final isRecording = recordingState.isRecording && isSelected;

    return GestureDetector(
      onTap: () => waveformState.selectTrack(trackIndex),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.sequencerSurfaceBase,
          border: Border.all(
            color: isSelected
                ? AppColors.sequencerAccent
                : AppColors.sequencerBorder,
            width: isSelected ? 2 : 0.5,
          ),
        ),
        child: _buildTrackContent(
          track,
          isRecording,
          width,
          height,
        ),
      ),
    );
  }

  Widget _buildTrackContent(
    MicTrackData track,
    bool isRecording,
    double width,
    double height,
  ) {
    // Priority 1: Detailed waveform (after recording)
    if (track.isRendered && track.detailedWaveform.isNotEmpty) {
      return CustomPaint(
        painter: VerticalDetailedWaveformPainter(
          waveformSamples: track.detailedWaveform,
          color: AppColors.sequencerText,
        ),
      );
    }

    // Priority 2: Live recording OR live amplitudes from recent recording
    if (track.liveAmplitudes.isNotEmpty) {
      return CustomPaint(
        painter: VerticalLiveWaveformPainter(
          amplitudes: track.liveAmplitudes,
          color: isRecording ? AppColors.sequencerAccent : AppColors.sequencerText.withOpacity(0.6),
        ),
      );
    }

    // Priority 3: Empty track
    return Center(
      child: Icon(
        Icons.mic_none,
        color: AppColors.sequencerLightText.withOpacity(0.3),
        size: 32,
      ),
    );
  }
}

// Live recording painter - vertical bars growing from center
class VerticalLiveWaveformPainter extends CustomPainter {
  final List<double> amplitudes; // 0.0-1.0
  final Color color;

  VerticalLiveWaveformPainter({
    required this.amplitudes,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (amplitudes.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final centerX = size.width / 2;
    final barHeight = size.height / amplitudes.length;

    for (int i = 0; i < amplitudes.length; i++) {
      final amplitude = amplitudes[i];
      final barWidth = amplitude * (size.width / 2); // Max width is half column
      final y = i * barHeight;

      // Draw bar radiating from center line
      final rect = Rect.fromLTWH(
        centerX - barWidth / 2,
        y,
        barWidth,
        barHeight,
      );

      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(VerticalLiveWaveformPainter oldDelegate) {
    return oldDelegate.amplitudes != amplitudes;
  }
}

// Detailed waveform painter - continuous filled curve
class VerticalDetailedWaveformPainter extends CustomPainter {
  final List<int> waveformSamples; // int16 samples (-32768 to 32767)
  final Color color;

  VerticalDetailedWaveformPainter({
    required this.waveformSamples,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (waveformSamples.isEmpty) return;

    final centerX = size.width / 2;
    final paint = Paint()
      ..color = color.withOpacity(0.8)
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(centerX, 0);

    // Draw positive side (right)
    for (int i = 0; i < waveformSamples.length; i++) {
      final sample = waveformSamples[i];
      final normalized = (sample / 32768.0).abs().clamp(0.0, 1.0);
      final x = centerX + normalized * (size.width / 2);
      final y = (i / waveformSamples.length) * size.height;

      if (i == 0) {
        path.lineTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // Draw negative side (left) - back to top
    for (int i = waveformSamples.length - 1; i >= 0; i--) {
      final sample = waveformSamples[i];
      final normalized = (sample / 32768.0).abs().clamp(0.0, 1.0);
      final x = centerX - normalized * (size.width / 2);
      final y = (i / waveformSamples.length) * size.height;

      path.lineTo(x, y);
    }

    path.close();
    canvas.drawPath(path, paint);

    // Draw center line
    final centerLinePaint = Paint()
      ..color = color.withOpacity(0.3)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(centerX, 0),
      Offset(centerX, size.height),
      centerLinePaint,
    );
  }

  @override
  bool shouldRepaint(VerticalDetailedWaveformPainter oldDelegate) {
    return oldDelegate.waveformSamples != waveformSamples;
  }
}
