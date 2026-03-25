import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/app_header_widget.dart';
import '../utils/app_colors.dart';
import 'package:provider/provider.dart';
import '../state/sequencer/microphone.dart';

class SequencerSettingsScreen extends StatefulWidget {
  const SequencerSettingsScreen({super.key});

  @override
  State<SequencerSettingsScreen> createState() => _SequencerSettingsScreenState();
}

class _SequencerSettingsScreenState extends State<SequencerSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.sequencerPageBackground,
      appBar: AppHeaderWidget(
        mode: HeaderMode.sequencerSettings,
        title: 'Settings',
        onBack: () => Navigator.of(context).pop(),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              _buildOutputDeviceSelection(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOutputDeviceSelection() {
    // Try to get MicrophoneState, but handle gracefully if not available
    MicrophoneState? micState;
    try {
      micState = context.watch<MicrophoneState>();
    } catch (e) {
      // MicrophoneState not provided - show placeholder
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.sequencerSurfaceBase,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppColors.sequencerBorder,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.volume_up,
                  color: AppColors.sequencerAccent.withOpacity(0.5),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Output',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.sequencerText.withOpacity(0.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Available when in sequencer screen',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.sequencerText.withOpacity(0.5),
              ),
            ),
          ],
        ),
      );
    }
    
    final availableOutputs = micState.getAvailableOutputs();
    final currentOutputType = micState.getCurrentOutputType();
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceBase,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.sequencerBorder,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.volume_up,
                color: AppColors.sequencerAccent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Output',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.sequencerText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (availableOutputs.isEmpty)
            Text(
              'No output devices available',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.sequencerText.withOpacity(0.5),
              ),
            )
          else
            ...availableOutputs.map((device) {
              final isActive = currentOutputType != null && device.type == currentOutputType;
              
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: GestureDetector(
                  onTap: () {
                    if (device.type.contains("Speaker")) {
                      micState?.setOutputRoute('speaker');
                    } else {
                      micState?.setOutputRoute('default');
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isActive 
                          ? AppColors.sequencerAccent.withOpacity(0.2)
                          : AppColors.sequencerSurfaceRaised,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isActive 
                            ? AppColors.sequencerAccent 
                            : AppColors.sequencerBorder,
                        width: isActive ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          device.isBluetooth ? Icons.bluetooth : Icons.speaker,
                          color: isActive 
                              ? AppColors.sequencerAccent 
                              : AppColors.sequencerText.withOpacity(0.7),
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            device.name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                              color: isActive 
                                  ? AppColors.sequencerAccent 
                                  : AppColors.sequencerText,
                            ),
                          ),
                        ),
                        if (isActive)
                          Icon(
                            Icons.check_circle,
                            color: AppColors.sequencerAccent,
                            size: 20,
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
        ],
      ),
    );
  }
}
