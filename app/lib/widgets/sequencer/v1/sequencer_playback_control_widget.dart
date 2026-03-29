import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../utils/app_colors.dart';
import '../../../state/sequencer/playback.dart';
import '../../../state/sequencer/recording.dart';
import '../../../state/sequencer/table.dart';
import '../../../state/sequencer/multitask_panel.dart';

class SequencerPlaybackControlWidget extends StatelessWidget {
  const SequencerPlaybackControlWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceBase,
        border: Border(
          top: BorderSide(
            color: AppColors.sequencerBorder,
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Consumer3<TableState, PlaybackState, RecordingState>(
          builder: (context, tableState, playbackState, recordingState, child) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final barHeight = constraints.maxHeight;
                
                return Row(
                  children: [
                    // Left side: Section chain
                    Expanded(
                      flex: 3,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12), // Add left padding to outer container
                        child: Container(
                          height: barHeight,
                          decoration: BoxDecoration(
                            color: const Color.fromARGB(255, 80, 80, 80), // Lighter gray background
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              return Center(
                                child: SizedBox(
                                  width: constraints.maxWidth,
                                  child: _buildSectionChain(tableState.sectionsCount, playbackState),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    
                    const SizedBox(width: 8),
                    
                    // Right side: Master, Record and Play buttons
                    Expanded(
                      flex: 2,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Master settings button (replaces the leftmost button)
                          _buildMasterButton(context),
                          
                          // Record button (pass tableState for layer context)
                          _buildRecordButton(recordingState, tableState),
                          
                          // Play button
                          _buildPlayButton(playbackState),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionChain(int numSections, PlaybackState playbackState) {
    return ValueListenableBuilder<int>(
      valueListenable: playbackState.currentSectionNotifier,
      builder: (context, currentSection, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            // Calculate the width of each section square including margins
            const double squareWidth = 15.0;
            const double horizontalMargin = 4.0; // 2px on each side
            const double totalSquareWidth = squareWidth + horizontalMargin;
            
            // Calculate how many squares can fit in the available width
            final double availableWidth = constraints.maxWidth;
            final int maxVisibleSquares = (availableWidth / totalSquareWidth).floor();
            
            // Determine the visible range to keep current section centered
            int startIndex = 0;
            int endIndex = numSections - 1;
            
            if (numSections > maxVisibleSquares) {
              // Center the current section in the visible area
              final int halfVisible = maxVisibleSquares ~/ 2;
              startIndex = (currentSection - halfVisible).clamp(0, numSections - maxVisibleSquares);
              endIndex = startIndex + maxVisibleSquares - 1;
            }
            
            return ClipRect(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(endIndex - startIndex + 1, (visibleIndex) {
                  final actualIndex = startIndex + visibleIndex;
                  final isCurrentSection = actualIndex == currentSection;
                  
                  // Square representing a section
                  return Container(
                    width: squareWidth,
                    height: 15,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: isCurrentSection 
                          ? const Color.fromARGB(255, 180, 180, 180) // Lighter color for current section
                          : const Color.fromARGB(255, 121, 121, 121), // Normal color for other sections
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                        color: isCurrentSection 
                            ? AppColors.sequencerAccent // Accent border for current section
                            : AppColors.sequencerBorder, // Normal border for other sections
                        width: isCurrentSection ? 2 : 1, // Thicker border for current section
                      ),
                    ),
                  );
                }),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRecordButton(RecordingState recordingState, TableState tableState) {
    return ValueListenableBuilder<bool>(
      valueListenable: recordingState.isRecordingNotifier,
      builder: (context, isRecording, child) {
        if (isRecording) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.sequencerAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.sequencerAccent.withOpacity(0.5),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _RecordingIndicatorDot(),
                    const SizedBox(width: 4),
                    ValueListenableBuilder<Duration>(
                      valueListenable: recordingState.recordingDurationNotifier,
                      builder: (context, duration, child) {
                        final minutes = duration.inMinutes;
                        final seconds = duration.inSeconds % 60;
                        final text = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
                        return Text(
                          text,
                          style: TextStyle(
                            color: AppColors.sequencerAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace',
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(
                  Icons.stop,
                  color: Colors.red,
                ),
                onPressed: () => recordingState.stopRecording(),
                iconSize: 16,
                padding: const EdgeInsets.all(2),
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          );
        } else {
          return IconButton(
            icon: Icon(
              Icons.fiber_manual_record,
              color: AppColors.sequencerAccent,
            ),
            onPressed: () async {
              if (!context.read<PlaybackState>().isPlaying) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Start playback before pattern recording.'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
                return;
              }

              // Pass current layer to recording state
              final layer = tableState.uiSelectedLayer;
              await recordingState.requestRecording(layer: layer);
            },
            iconSize: 20,
            padding: const EdgeInsets.all(2),
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          );
        }
      },
    );
  }

  Widget _buildMasterButton(BuildContext context) {
    return IconButton(
      icon: Icon(
        Icons.tune, // Use tune icon for master settings
        color: AppColors.sequencerAccent,
      ),
      onPressed: () {
        debugPrint('🎛️ Master settings button pressed');
        final panelState = context.read<MultitaskPanelState>();
        panelState.showMasterSettings();
      },
      iconSize: 20,
      padding: const EdgeInsets.all(2),
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
    );
  }

  Widget _buildPlayButton(PlaybackState playbackState) {
    return ValueListenableBuilder<bool>(
      valueListenable: playbackState.isPlayingNotifier,
      builder: (context, isPlaying, child) {
        return IconButton(
          icon: Icon(
            isPlaying ? Icons.stop : Icons.play_arrow,
            color: AppColors.sequencerAccent,
          ),
          onPressed: () {
            if (isPlaying) {
              playbackState.stop();
            } else {
              playbackState.start();
            }
          },
          iconSize: 22,
          padding: const EdgeInsets.all(2),
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        );
      },
    );
  }
}

// Helper widget for pulsing recording indicator
class _RecordingIndicatorDot extends StatefulWidget {
  @override
  _RecordingIndicatorDotState createState() => _RecordingIndicatorDotState();
}

class _RecordingIndicatorDotState extends State<_RecordingIndicatorDot>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _animation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    
    // Start repeating animation
    _animationController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(_animation.value),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}
