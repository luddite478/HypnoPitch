import 'package:flutter/material.dart';
import '../../../state/sequencer/recording_waveform.dart';
import '../../../utils/sample_offset_calculator.dart';

/// UI controls for adjusting sample offset timing
/// 
/// Provides nudge buttons for fine-tuning sample start position
/// with millisecond precision. Shows current offset in ms and frames.
class OffsetControlsWidget extends StatelessWidget {
  final RecordingWaveformState waveformState;
  final int layer;
  final int section;
  
  const OffsetControlsWidget({
    Key? key,
    required this.waveformState,
    required this.layer,
    required this.section,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: waveformState,
      builder: (context, _) {
        final offsetFrames = waveformState.getOffset(layer, section);
        final offsetMs = SampleOffsetCalculator.framesToTime(offsetFrames).inMilliseconds;
        
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Sample Offset',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Adjust the timing of when the sample starts playing',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Text(
                      '${offsetMs > 0 ? '+' : ''}${offsetMs}ms',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$offsetFrames frames @ 48kHz',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Nudge:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _nudgeButton('◀◀◀', -100),
                  _nudgeButton('◀◀', -10),
                  _nudgeButton('◀', -1),
                  _resetButton(),
                  _nudgeButton('▶', 1),
                  _nudgeButton('▶▶', 10),
                  _nudgeButton('▶▶▶', 100),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Text('-100ms', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                  Text('-10ms', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                  Text('-1ms', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                  Text('0', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                  Text('+1ms', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                  Text('+10ms', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                  Text('+100ms', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Info',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
              const SizedBox(height: 4),
              Text(
                '• Positive values delay the sample\n'
                '• Negative values start the sample earlier\n'
                '• Precision: 1 frame = 0.02ms @ 48kHz',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ],
          ),
        );
      },
    );
  }
  
  Widget _nudgeButton(String label, int deltaMs) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: ElevatedButton(
          onPressed: () => waveformState.nudgeOffset(layer, section, deltaMs),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            backgroundColor: Colors.grey[800],
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
  
  Widget _resetButton() {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: ElevatedButton(
          onPressed: () => waveformState.setOffset(layer, section, 0),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            backgroundColor: Colors.orange,
          ),
          child: const Text(
            'RESET',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
