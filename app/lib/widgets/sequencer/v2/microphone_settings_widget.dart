import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../state/sequencer/microphone.dart';
import '../../../state/sequencer/recording_waveform.dart';
import '../../../utils/app_colors.dart';
import 'generic_slider.dart';
import '../../../state/sequencer/slider_overlay.dart';

/// Widget for microphone settings in the multitask panel
/// Shows input level, monitor toggle, and volume slider
class MicrophoneSettingsWidget extends StatefulWidget {
  const MicrophoneSettingsWidget({super.key});

  @override
  State<MicrophoneSettingsWidget> createState() => _MicrophoneSettingsWidgetState();
}

class _MicrophoneSettingsWidgetState extends State<MicrophoneSettingsWidget> {
  String _selectedControl = 'VOL'; // Default to VOL
  
  // Layout ratios (same as sound settings pattern)
  double _headerButtonsHeight = 0.45;     // 45% for header buttons area
  double _sliderTileHeightPercent = 0.50; // 50% for slider tile area
  double _spacingHeight = 0.02;           // 2% for spacing between areas
  
  // No need for separate level indicator - it's integrated into the Mic label

  @override
  Widget build(BuildContext context) {
    return Consumer<MicrophoneState>(
      builder: (context, micState, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            // Calculate responsive sizes based on available space
            final panelHeight = constraints.maxHeight;
            
            // Padding & ratios
            final padding = panelHeight * 0.03;
            final innerHeight = panelHeight - padding * 2;
            final borderThickness = 1.0;
            final innerHeightAdj = innerHeight - borderThickness * 2;

            // Use the simple variables for layout calculations
            final headerHeight = innerHeightAdj * _headerButtonsHeight;
            final contentHeight = innerHeightAdj * _sliderTileHeightPercent;
            final labelFontSize = (headerHeight * 0.25).clamp(8.0, 11.0);
            
        return Container(
              padding: EdgeInsets.all(padding),
          decoration: BoxDecoration(
                color: AppColors.sequencerSurfaceBase,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
              color: AppColors.sequencerBorder,
                  width: 1,
            ),
            boxShadow: [
                  // Protruding effect
              BoxShadow(
                color: AppColors.sequencerShadow,
                blurRadius: 3,
                offset: const Offset(0, 2),
              ),
              BoxShadow(
                    color: AppColors.sequencerSurfaceRaised,
                blurRadius: 1,
                offset: const Offset(0, -1),
              ),
            ],
          ),
              child: Column(
                children: [
                  // Header buttons area
                  Expanded(
                    flex: (_headerButtonsHeight * 100).round(),
                    child: LayoutBuilder(
                      builder: (context, headerConstraints) {
                        return _buildScrollableHeader(
                          headerHeight, 
                          labelFontSize, 
                          headerConstraints.maxWidth,
                          micState,
                        );
                      },
                    ),
                  ),
                  
                  // Top spacer
                  Spacer(flex: (_spacingHeight * 100).round()),
                  
                  // Control tile area (Monitor button OR Volume slider)
                  Expanded(
                    flex: (_sliderTileHeightPercent * 100).round(),
                    child: _buildActiveControl(micState, contentHeight, padding, labelFontSize),
                  ),
                  
                  // Bottom spacer
                  Spacer(flex: (_spacingHeight * 100).round()),
                  
                  // Remaining space
                  Spacer(flex: ((1.0 - _headerButtonsHeight - _spacingHeight - _sliderTileHeightPercent - _spacingHeight) * 100).round().clamp(0, 100)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildScrollableHeader(double headerHeight, double labelFontSize, double availableWidth, MicrophoneState micState) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Context label "Mic" with level indicator behind it
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: SizedBox(
                width: availableWidth * 0.30,
                height: headerHeight * 0.7,
                child: _MicLabelWithLevel(
                  labelFontSize: labelFontSize,
                  micState: micState,
                ),
              ),
            ),
            // VOL button
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: SizedBox(
                width: 80,
                child: _buildSettingsButton(
                  'VOL', 
                  _selectedControl == 'VOL', 
                  headerHeight * 0.7, 
                  labelFontSize, 
                  () {
                    setState(() {
                      _selectedControl = 'VOL';
                    });
                  }
                ),
              ),
            ),
            // NOTE: MON button removed - monitoring is no longer available
            // INPUT button (device selector)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: SizedBox(
                width: 90,
                child: _buildSettingsButton(
                  _buildInputButtonLabel(micState), 
                  _selectedControl == 'INPUT', 
                  headerHeight * 0.7, 
                  labelFontSize, 
                  () {
                    setState(() {
                      _selectedControl = 'INPUT';
                    });
                  }
                ),
              ),
            ),
            // TRACK button (track selector)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: SizedBox(
                width: 90,
                child: _buildSettingsButton(
                  'TRACK', 
                  _selectedControl == 'TRACK', 
                  headerHeight * 0.7, 
                  labelFontSize, 
                  () {
                    setState(() {
                      _selectedControl = 'TRACK';
                    });
                  }
                ),
              ),
            ),
            ],
          ),
      ),
    );
  }

  Widget _buildSettingsButton(String label, bool isSelected, double height, double fontSize, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: isSelected 
              ? AppColors.sequencerAccent 
              : AppColors.sequencerSurfaceRaised,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: AppColors.sequencerBorder,
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.sequencerShadow,
              blurRadius: 1.5,
              offset: const Offset(0, 1),
            ),
            BoxShadow(
              color: AppColors.sequencerSurfaceRaised,
              blurRadius: 0.5,
              offset: const Offset(0, -0.5),
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected 
                  ? AppColors.sequencerPageBackground 
                  : AppColors.sequencerText,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveControl(MicrophoneState micState, double height, double padding, double fontSize) {
    switch (_selectedControl) {
      case 'VOL':
        return _buildVolumeControl(micState, height, padding);
      // NOTE: MON case removed - monitoring is no longer available
      case 'INPUT':
        return _buildInputSelectorControl(micState, height, padding, fontSize);
      case 'TRACK':
        return _buildTrackSelectorControl(height, padding, fontSize);
      default:
        return _buildVolumeControl(micState, height, padding);
    }
  }

  String _buildInputButtonLabel(MicrophoneState micState) {
    final kind = micState.getCurrentInputKindLabel();
    if (kind == 'WIRED') return 'IN:WIRED';
    if (kind == 'BUILT-IN') return 'IN:BUILT';
    return 'INPUT';
  }

  Widget _buildVolumeControl(MicrophoneState micState, double height, double padding) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: padding * 0.5,
        vertical: padding * 0.3,
      ),
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceRaised,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: AppColors.sequencerBorder,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.sequencerShadow,
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
          BoxShadow(
            color: AppColors.sequencerSurfaceRaised,
            blurRadius: 1,
            offset: const Offset(0, -0.5),
          ),
        ],
      ),
      child: ValueListenableBuilder<double>(
        valueListenable: micState.micVolumeNotifier,
        builder: (context, volume, _) => GenericSlider(
          value: volume,
          min: 0.0,
          max: 1.0,
          divisions: 100,
          type: SliderType.volume,
          onChanged: (value) => micState.setMicVolume(value),
          height: height,
          sliderOverlay: context.read<SliderOverlayState>(),
          contextLabel: 'Mic',
        ),
      ),
    );
  }

  // NOTE: _buildMonitorControl removed - monitoring is no longer available
  // Mic recording now bypasses SunVox entirely

  Widget _buildInputSelectorControl(MicrophoneState micState, double height, double padding, double fontSize) {
    final availableInputs = micState.getAvailableInputs();
    final currentInputUid = micState.getCurrentInputUid();
    
    return Container(
      padding: EdgeInsets.symmetric(horizontal: padding * 0.5, vertical: padding * 0.3),
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceRaised,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: AppColors.sequencerBorder, width: 1),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: availableInputs.map((device) {
            final isSelected = device.uid == currentInputUid;
            
            return Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: GestureDetector(
                onTap: () {
                  micState.setPreferredInput(device.uid);
                  setState(() {});
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  constraints: BoxConstraints(
                    maxWidth: 200, // Prevent overflow on very long device names
                  ),
                  decoration: BoxDecoration(
                    color: isSelected 
                        ? AppColors.sequencerAccent.withOpacity(0.3)
                        : AppColors.sequencerSurfacePressed,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isSelected 
                          ? AppColors.sequencerAccent 
                          : AppColors.sequencerBorder,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        device.isBluetooth ? Icons.bluetooth : Icons.phone_iphone,
                        size: height * 0.30,
                        color: isSelected 
                            ? AppColors.sequencerAccent 
                            : (device.isBluetooth ? Colors.blue : AppColors.sequencerText),
                      ),
                      const SizedBox(width: 8),
                      // Use Flexible to prevent overflow
                      Flexible(
                        child: Text(
                          device.name,
                  style: TextStyle(
                            color: isSelected 
                        ? AppColors.sequencerAccent 
                                : AppColors.sequencerText,
                            fontSize: height * 0.18,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.check_circle,
                          size: height * 0.22,
                          color: AppColors.sequencerAccent,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // Track selector control (4 track buttons)
  Widget _buildTrackSelectorControl(double height, double padding, double fontSize) {
    return Consumer<RecordingWaveformState>(
      builder: (context, waveformState, _) {
        return Container(
          padding: EdgeInsets.symmetric(horizontal: padding * 0.5, vertical: padding * 0.3),
          decoration: BoxDecoration(
            color: AppColors.sequencerSurfaceRaised,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: AppColors.sequencerBorder, width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(4, (trackIndex) {
              final isSelected = waveformState.selectedTrack == trackIndex;
              final hasRecording = waveformState.hasRecording(trackIndex);
              
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: GestureDetector(
                    onTap: () {
                      waveformState.selectTrack(trackIndex);
                    },
                    child: Container(
                      height: height * 0.8,
                      decoration: BoxDecoration(
                        color: isSelected 
                            ? AppColors.sequencerAccent 
                            : (hasRecording 
                                ? AppColors.sequencerSurfaceBase.withOpacity(0.8)
                                : AppColors.sequencerSurfaceBase),
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(
                          color: hasRecording 
                              ? AppColors.sequencerAccent.withOpacity(0.5)
                              : AppColors.sequencerBorder,
                          width: hasRecording ? 1.5 : 0.5,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'T${trackIndex + 1}',
                          style: TextStyle(
                            color: isSelected 
                                ? Colors.white 
                                : AppColors.sequencerText,
                            fontSize: fontSize * 0.9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }

}

/// Mic label with integrated level indicator background
class _MicLabelWithLevel extends StatefulWidget {
  final double labelFontSize;
  final MicrophoneState micState;
  
  const _MicLabelWithLevel({
    required this.labelFontSize,
    required this.micState,
  });
  
  @override
  State<_MicLabelWithLevel> createState() => _MicLabelWithLevelState();
}

class _MicLabelWithLevelState extends State<_MicLabelWithLevel>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  double _currentLevel = 0.0;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 50),
      vsync: this,
    );
    if (widget.micState.isMicEnabled) {
      _startPolling();
    }
  }
  
  @override
  void didUpdateWidget(_MicLabelWithLevel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.micState.isMicEnabled && !oldWidget.micState.isMicEnabled) {
      _startPolling();
    } else if (!widget.micState.isMicEnabled && oldWidget.micState.isMicEnabled) {
      _controller.stop();
      setState(() {
        _currentLevel = 0.0;
      });
    }
  }
  
  void _startPolling() {
    _controller.repeat();
    _controller.addListener(_pollLevel);
  }
  
  void _pollLevel() {
    if (!widget.micState.isMicEnabled) return;
    final level = widget.micState.getAudioLevel();
    setState(() {
      _currentLevel = level;
    });
  }
  
  @override
  void dispose() {
    _controller.removeListener(_pollLevel);
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    // Get audio route info
    final isBluetooth = widget.micState.isBluetoothMicrophone();
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceBase,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: AppColors.sequencerBorder, width: 1),
      ),
      child: Stack(
        children: [
          // Level indicator background
          Positioned.fill(
            child: CustomPaint(
              painter: _LevelBarPainter(
                level: _currentLevel,
                isActive: widget.micState.isMicEnabled,
              ),
            ),
          ),
          // Content on top
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon showing Bluetooth or built-in
                Icon(
                  isBluetooth ? Icons.bluetooth : Icons.phone_iphone,
                  size: widget.labelFontSize * 1.2,
                  color: isBluetooth ? Colors.blue : AppColors.sequencerText,
                ),
                const SizedBox(width: 4),
                // "Mic" text
                Flexible(
                  child: Text(
                    'Mic',
                    style: TextStyle(
                      color: AppColors.sequencerText,
                      fontSize: widget.labelFontSize,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelBarPainter extends CustomPainter {
  final double level;
  final bool isActive;
  
  _LevelBarPainter({required this.level, required this.isActive});
  
  @override
  void paint(Canvas canvas, Size size) {
    // Level bar (from left to right) - only paint if active and level > 0
    if (isActive && level > 0.0) {
      final levelWidth = size.width * level.clamp(0.0, 1.0);
      final levelPaint = Paint()
        ..color = (level > 0.8 
            ? Colors.red 
            : (level > 0.5 ? Colors.orange : Colors.green)).withOpacity(0.3)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, levelWidth, size.height),
          const Radius.circular(2),
        ),
        levelPaint,
      );
    }
  }
  
  @override
  bool shouldRepaint(_LevelBarPainter oldDelegate) => oldDelegate.level != level;
}
