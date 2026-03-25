import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../state/sequencer/playback.dart';
import '../state/sequencer/recording.dart';
import '../state/sequencer/microphone.dart';
import '../state/patterns_state.dart';
import '../screens/sequencer_settings_screen.dart';
import '../utils/app_colors.dart';

enum HeaderMode {
  checkpoints,
  sequencer,
  sequencerSettings,
}

class AppHeaderWidget extends StatelessWidget implements PreferredSizeWidget {
  final HeaderMode mode;
  final String? title;
  final String? subtitle;
  final VoidCallback? onBack;
  final VoidCallback? onSave;
  final VoidCallback? onInfo;
  final bool showProjectInfo;

  const AppHeaderWidget({
    super.key,
    required this.mode,
    this.title,
    this.subtitle,
    this.onBack,
    this.onSave,
    this.onInfo,
    this.showProjectInfo = false,
    this.threadsService, // Add optional ThreadsService parameter
  });

  final dynamic threadsService;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  bool get _isPhoneBookMode => mode == HeaderMode.checkpoints;
  bool get _isSequencerMode => mode == HeaderMode.sequencer || mode == HeaderMode.sequencerSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _isPhoneBookMode 
          ? BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: AppColors.menuBorder,
                  width: 1,
                ),
              ),
            )
          : _isSequencerMode
              ? BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: AppColors.menuBorder,
                      width: 1,
                    ),
                  ),
                )
              : null,
      child: AppBar(
        backgroundColor: _isPhoneBookMode 
            ? AppColors.menuEntryBackground 
            : _isSequencerMode 
                ? AppColors.sequencerSurfaceBase
                : const Color(0xFF111827),
        foregroundColor: _isPhoneBookMode 
            ? AppColors.menuText 
            : _isSequencerMode 
                ? AppColors.sequencerText
                : Colors.white,
        elevation: 0,
        leading: onBack != null 
            ? IconButton(
                icon: Icon(
                  Icons.arrow_back, 
                  color: _isPhoneBookMode 
                      ? AppColors.menuText 
                      : _isSequencerMode 
                          ? AppColors.sequencerText
                          : Colors.orangeAccent,
                ),
                onPressed: onBack,
                iconSize: 20,
              )
            : null,
        title: _buildTitle(context),
        actions: _buildActions(context),
      ),
    );
  }

  Widget _buildTitle(BuildContext context) {
    switch (mode) {
      case HeaderMode.sequencer:
        // No title for sequencer mode to save space
        return const SizedBox.shrink();
      case HeaderMode.sequencerSettings:
        // Show title for settings screen
        return Text(
          title ?? 'Settings',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.sequencerText,
            letterSpacing: 0.5,
          ),
        );
      case HeaderMode.checkpoints:
        return Consumer<PatternsState>(
          builder: (context, patternsState, child) {
            final pattern = patternsState.activePattern;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title ?? (pattern != null ? 'Pattern ${pattern.id.substring(0, 8)}' : 'Pattern'),
                  style: _isPhoneBookMode 
                      ? TextStyle(
                          fontSize: 16, 
                          fontWeight: FontWeight.w700,
                          color: AppColors.menuText,
                          letterSpacing: 0.5,
                        )
                      : const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                if (subtitle != null || pattern != null)
                  Text(
                    subtitle ?? '${pattern?.checkpointIds.length ?? 0} checkpoints',
                    style: _isPhoneBookMode
                        ? TextStyle(
                            fontSize: 11,
                            color: AppColors.menuLightText,
                            fontWeight: FontWeight.w400,
                          )
                        : TextStyle(
                            fontSize: 11,
                            color: Colors.grey[300],
                          ),
                  ),
              ],
            );
          },
        );
    }
  }

  List<Widget> _buildActions(BuildContext context) {
    switch (mode) {
      case HeaderMode.sequencer:
        return _buildSequencerActions(context);
      case HeaderMode.sequencerSettings:
        // No actions for settings screen (just back button)
        return [];
      case HeaderMode.checkpoints:
        return []; // No actions for checkpoints
    }
  }

  List<Widget> _buildSequencerActions(BuildContext context) {
    // 🎛️ MASTER SPACING CONTROL: Adjust this one variable (0.5% to 3.0% of screen width)
    final double spacingPercentage = 0; // ← Change this to control all spacing
    
    final screenWidth = MediaQuery.of(context).size.width;
    final spacingWidth = screenWidth * (spacingPercentage / 100);
    
    return [
      // Test button - for testing scrollable elements
      // IconButton(
      //   icon: Icon(
      //     Icons.science,
      //     color: AppColors.sequencerAccent,
      //   ),
      //   onPressed: () => _navigateToTestScreen(context),
      //   iconSize: 14,
      //   padding: const EdgeInsets.all(2),
      //   constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      // ),
      
      // Percentage-based spacing
      SizedBox(width: spacingWidth),
      
      // Settings gear button - access to all other functions
      IconButton(
        icon: Icon(
          Icons.settings,
          color: AppColors.sequencerAccent,
        ),
        onPressed: () => _navigateToSequencerSettings(context),
        iconSize: 14,
        padding: const EdgeInsets.all(2),
        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      ),
      
      // Percentage-based spacing
      SizedBox(width: spacingWidth),
      
      // V2: hide legacy checkpoints control
      const SizedBox.shrink(),
      
      // Percentage-based spacing
      SizedBox(width: spacingWidth),
      
      // V2: hide legacy save/send control
      const SizedBox.shrink(),
      
      // Percentage-based spacing
      SizedBox(width: spacingWidth),
      
      // Share button (legacy hidden)
      // const SizedBox.shrink(),
      
      // Percentage-based spacing
      SizedBox(width: spacingWidth),
      
      // V2: hide legacy master settings control
      const SizedBox.shrink(),
      
      // Percentage-based spacing
      SizedBox(width: spacingWidth),
      
      // Recording controls - core functionality (V2 only)
      Builder(
        builder: (context) {
          final playbackState = context.watch<PlaybackState?>();
          final recordingState = context.watch<RecordingState?>();
          final useNewPlayback = playbackState != null;
          
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (useNewPlayback && recordingState != null) ...[
                ...(){
                  final rs = recordingState;
                  return [
                ValueListenableBuilder<bool>(
                  valueListenable: rs.isRecordingNotifier,
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
                                SizedBox(width: spacingWidth * 0.2),
                                ValueListenableBuilder<Duration>(
                                  valueListenable: rs.recordingDurationNotifier,
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
                          SizedBox(width: spacingWidth * 0.3),
                          IconButton(
                            icon: Icon(
                              Icons.stop,
                              color: Colors.red,
                            ),
                            onPressed: () => rs.stopRecording(),
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
                          final playbackState = context.read<PlaybackState>();
                          if (!playbackState.isPlaying) {
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
                          await rs.requestRecording();
                        },
                        iconSize: 16,
                        padding: const EdgeInsets.all(2),
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      );
                    }
                  },
                ),
                  ];
                }(),
              ] else ...[const SizedBox.shrink()],
              
              // Spacing between recording and sequencer controls
              SizedBox(width: spacingWidth * 0.5),
              
              // Sequencer play/stop button - V2 only
              if (useNewPlayback) ...[
                ...(){
                  final ps = playbackState;
                  return [
                ValueListenableBuilder<bool>(
                  valueListenable: ps.isPlayingNotifier,
                  builder: (context, isPlaying, child) {
                    return IconButton(
                      icon: Icon(
                        isPlaying ? Icons.stop : Icons.play_arrow,
                        color: AppColors.sequencerAccent,
                      ),
                      onPressed: () {
                        if (isPlaying) {
                          ps.stop();
                        } else {
                          ps.start();
                        }
                      },
                      iconSize: 16,
                      padding: const EdgeInsets.all(2),
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    );
                  },
                ),
                  ];
                }(),
              ] else ...[const SizedBox.shrink()],
            ],
          );
        },
      ),
    ];
  }

  // _buildThreadActions removed in offline transformation

  void _navigateToSequencerSettings(BuildContext context) {
    // Try to pass MicrophoneState if available (from sequencer screen)
    // If not available (from other screens), settings will show placeholder
    try {
      final microphoneState = Provider.of<MicrophoneState>(context, listen: false);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChangeNotifierProvider.value(
            value: microphoneState,
            child: const SequencerSettingsScreen(),
          ),
        ),
      );
    } catch (e) {
      // MicrophoneState not available - navigate without it
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const SequencerSettingsScreen(),
        ),
      );
    }
  }

  // Test navigation removed (unused)
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