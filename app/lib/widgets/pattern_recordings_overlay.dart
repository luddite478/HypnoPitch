import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../state/patterns_state.dart';
import '../state/audio_player_state.dart';
import '../state/library_state.dart';
import '../models/checkpoint.dart';
import '../utils/app_colors.dart';
import '../utils/local_audio_path.dart';
import '../utils/share_utils.dart';

/// Overlay showing all takes (recordings) for the current pattern
class PatternRecordingsOverlay extends StatefulWidget {
  // Width as percentage of screen width (0.98 = 98%)
  static const double kDialogWidthFactor = 0.88;
  
  final bool highlightNewest;
  
  const PatternRecordingsOverlay({
    Key? key,
    this.highlightNewest = false,
  }) : super(key: key);

  @override
  State<PatternRecordingsOverlay> createState() => _PatternRecordingsOverlayState();
}

class _PatternRecordingsOverlayState extends State<PatternRecordingsOverlay> {
  final Set<String> _addingToLibrary = {};
  final Set<String> _addedToLibrary = {};
  String? _highlightedCheckpointId;
  Timer? _timestampUpdateTimer;
  int _refreshKey = 0; // Used to force rebuild of FutureBuilder
  AudioPlayerState? _audioPlayerRef;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _audioPlayerRef ??= context.read<AudioPlayerState>();
  }

  @override
  void initState() {
    super.initState();
    
    // Start timer to update timestamps in real-time
    _timestampUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          // Trigger rebuild to update timestamps
        });
      }
    });
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reloadCheckpointsAndHighlight();
    });
  }
  
  Future<void> _reloadCheckpointsAndHighlight() async {
    final patternsState = context.read<PatternsState>();
    final activePattern = patternsState.activePattern;
    if (activePattern == null) return;

    await patternsState.loadCheckpoints(activePattern.id);
    if (!mounted) return;

    setState(() {
      _refreshKey++;
    });

    if (!widget.highlightNewest) return;
    final checkpoints = patternsState.getCheckpoints(activePattern.id);
    final recordings = checkpoints.where((c) => c.audioFilePath != null).toList();
    debugPrint('💿 [RECORDINGS_OVERLAY] Found ${recordings.length} recordings for pattern ${activePattern.id}');
    if (recordings.isNotEmpty) {
      setState(() {
        _highlightedCheckpointId = recordings.first.id;
      });
      // Remove highlight after 2 seconds
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _highlightedCheckpointId = null;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _timestampUpdateTimer?.cancel();
    _audioPlayerRef?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final patternsState = context.watch<PatternsState>();
    final activePattern = patternsState.activePattern;
    
    if (activePattern == null) {
      return _buildEmptyDialog('No active pattern');
    }

    final checkpoints = patternsState.getCheckpoints(activePattern.id);
    final recordingsWithAudio = checkpoints.where((c) => c.audioFilePath != null).toList();
    
    debugPrint('💿 [RECORDINGS_OVERLAY] Loading ${recordingsWithAudio.length} recordings with audio');

    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = screenSize.width * PatternRecordingsOverlay.kDialogWidthFactor;
    final maxHeight = (screenSize.height * 0.8).clamp(400.0, 700.0);
    
    return FutureBuilder<List<Checkpoint>>(
      key: ValueKey(_refreshKey), // Force rebuild when refreshing
      future: _filterExistingRecordings(recordingsWithAudio),
      builder: (context, snapshot) {
        // Show loading state while checking files
        if (!snapshot.hasData) {
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: EdgeInsets.zero,
            child: Center(
              child: Container(
                width: dialogWidth,
                height: maxHeight,
                decoration: BoxDecoration(
                  color: AppColors.sequencerSurfaceRaised,
                  borderRadius: BorderRadius.circular(1.0),
                  border: Border.all(color: AppColors.sequencerBorder, width: 0.5),
                ),
                child: Center(
                  child: CircularProgressIndicator(
                    color: AppColors.sequencerAccent,
                  ),
                ),
              ),
            ),
          );
        }

        final recordings = snapshot.data!;

        return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Center(
        child: Container(
          width: dialogWidth,
          height: maxHeight,
          decoration: BoxDecoration(
            color: AppColors.sequencerSurfaceRaised,
            borderRadius: BorderRadius.circular(1.0),
            border: Border.all(color: AppColors.sequencerBorder, width: 0.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.sequencerBorder, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.graphic_eq, color: AppColors.sequencerAccent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Takes',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.sequencerText,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: AppColors.sequencerText),
                  onPressed: () => Navigator.of(context).pop(),
                  iconSize: 18,
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              ],
            ),
          ),
          
          // Recordings list
          Expanded(
            child: recordings.isEmpty
                ? _buildEmptyState('No takes yet')
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    itemCount: recordings.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final checkpoint = recordings[index];
                      return _buildRecordingCard(checkpoint);
                    },
                  ),
          ),
            ],
          ),
        ),
      ),
    );
      },
    );
  }
  
  Widget _buildEmptyDialog(String message) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = screenSize.width * PatternRecordingsOverlay.kDialogWidthFactor;
    
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Center(
        child: Container(
          width: dialogWidth,
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: AppColors.sequencerSurfaceRaised,
            borderRadius: BorderRadius.circular(1.0),
            border: Border.all(color: AppColors.sequencerBorder, width: 0.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.graphic_eq,
                size: 64,
                color: AppColors.sequencerLightText.withOpacity(0.3),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.sequencerLightText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.graphic_eq,
            size: 64,
            color: AppColors.sequencerLightText.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 16,
              color: AppColors.sequencerLightText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingCard(Checkpoint checkpoint) {
    final audioPlayerState = context.watch<AudioPlayerState>();
    final isPlaying = audioPlayerState.isPlayingItem(checkpoint.id);
    final isLoadingAudio = audioPlayerState.isLoadingItem(checkpoint.id);
    final isAddingToLibrary = _addingToLibrary.contains(checkpoint.id);
    final isAddedToLibrary = _addedToLibrary.contains(checkpoint.id);
    final isHighlighted = _highlightedCheckpointId == checkpoint.id;
    
    // Get current position and duration for progress bar
    final position = isPlaying ? audioPlayerState.position : Duration.zero;
    final duration = checkpoint.audioDuration != null 
        ? Duration(milliseconds: (checkpoint.audioDuration! * 1000).toInt())
        : Duration.zero;
    final progress = duration.inMilliseconds > 0 
        ? position.inMilliseconds / duration.inMilliseconds 
        : 0.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: isHighlighted 
            ? AppColors.sequencerAccent.withOpacity(0.15)
            : AppColors.sequencerSurfaceBase,
        borderRadius: BorderRadius.circular(1.0),
        border: Border.all(
          color: isHighlighted 
              ? AppColors.sequencerAccent 
              : AppColors.sequencerBorder,
          width: isHighlighted ? 1.0 : 0.5,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Calculate button sizes based on available width
          final availableWidth = constraints.maxWidth;
          final isVerySmall = availableWidth < 350;
          
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Main row with controls
              Row(
                children: [
                  // Play/Pause button - Compact
                  Container(
                    width: 44,
                    height: 44,
                decoration: BoxDecoration(
                  color: AppColors.sequencerSurfaceRaised,
                  border: Border(
                    right: BorderSide(color: AppColors.sequencerBorder, width: 0.5),
                  ),
                ),
                child: FutureBuilder<bool>(
                  future: checkpoint.audioFilePath != null
                      ? LocalAudioPath.resolve(checkpoint.audioFilePath!)
                          .then((p) => p != null)
                      : Future.value(false),
                  builder: (context, snapshot) {
                    final fileExists = snapshot.data ?? false;
                    final showLoading = isLoadingAudio || !fileExists;
                    
                    return IconButton(
                      onPressed: showLoading
                          ? null
                          : () {
                              if (isPlaying) {
                                audioPlayerState.pause();
                              } else if (checkpoint.audioFilePath != null) {
                                audioPlayerState.playFromPath(
                                  itemId: checkpoint.id,
                                  localPath: checkpoint.audioFilePath!,
                                );
                              }
                            },
                      icon: showLoading
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.sequencerAccent,
                              ),
                            )
                          : Icon(
                              isPlaying ? Icons.pause : Icons.play_arrow,
                              size: 22,
                            ),
                      color: AppColors.sequencerAccent,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    );
                  },
                ),
              ),
              
              // Info - Takes remaining space
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isVerySmall ? 6 : 8,
                    vertical: 6,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatDateTime(checkpoint.createdAt),
                        style: TextStyle(
                          fontSize: isVerySmall ? 13 : 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.sequencerText,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            _formatDuration(checkpoint.audioDuration ?? 0),
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.sequencerLightText,
                            ),
                          ),
                          if (checkpoint.audioFilePath != null && !isVerySmall) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: FutureBuilder<int>(
                                future: _getFileSize(checkpoint.audioFilePath!),
                                builder: (context, snapshot) {
                                  if (snapshot.hasData && snapshot.data! > 0) {
                                    return Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.storage, size: 12, color: AppColors.sequencerLightText),
                                        const SizedBox(width: 3),
                                        Flexible(
                                          child: Text(
                                            _formatFileSize(snapshot.data!),
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: AppColors.sequencerLightText,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    );
                                  }
                                  return const SizedBox.shrink();
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              
              // Add to Library button - Icon only
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: AppColors.sequencerBorder, width: 0.5),
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: isAddedToLibrary || isAddingToLibrary
                        ? null
                        : () => _handleAddToLibrary(checkpoint),
                    child: Container(
                      width: 44,
                      height: 44,
                      child: Center(
                        child: isAddingToLibrary
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.sequencerLightText,
                                ),
                              )
                            : Icon(
                                isAddedToLibrary ? Icons.check_circle : Icons.playlist_add,
                                size: 20,
                                color: isAddedToLibrary
                                    ? AppColors.sequencerAccent
                                    : AppColors.sequencerText,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
              
              // Actions menu - Compact
              Container(
                width: isVerySmall ? 36 : 40,
                height: 44,
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: AppColors.sequencerBorder, width: 0.5),
                  ),
                ),
                child: PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, size: 18, color: AppColors.sequencerLightText),
                  padding: EdgeInsets.zero,
                  color: AppColors.sequencerSurfaceRaised,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(1.0),
                    side: BorderSide(color: AppColors.sequencerBorder, width: 0.5),
                  ),
                  onSelected: (value) {
                    if (value == 'share' && checkpoint.audioFilePath != null) {
                      _handleShare(checkpoint.audioFilePath!, context);
                    } else if (value == 'delete') {
                      _handleDelete(checkpoint);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'share',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.ios_share, size: 16, color: AppColors.sequencerText),
                          const SizedBox(width: 10),
                          Text(
                            'Share',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.sequencerText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.delete_outline, size: 16, color: AppColors.sequencerAccent),
                          const SizedBox(width: 10),
                          Text(
                            'Delete',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.sequencerAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
                ],
              ),
          
          // Progress bar
          if (isPlaying || progress > 0)
            GestureDetector(
              onTapDown: (details) {
                // Calculate seek position from tap
                final box = context.findRenderObject() as RenderBox?;
                if (box != null && checkpoint.audioFilePath != null) {
                  final localX = details.localPosition.dx;
                  final width = box.size.width;
                  final seekPercent = (localX / width).clamp(0.0, 1.0);
                  final seekPosition = Duration(
                    milliseconds: (duration.inMilliseconds * seekPercent).toInt(),
                  );
                  audioPlayerState.seek(seekPosition);
                }
              },
              child: Container(
                height: 3,
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: AppColors.sequencerBorder, width: 0.5),
                  ),
                ),
                child: Stack(
                  children: [
                    // Background
                    Container(
                      color: AppColors.sequencerSurfaceRaised,
                    ),
                    // Progress
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: progress.clamp(0.0, 1.0),
                      child: Container(
                        color: AppColors.sequencerAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _handleAddToLibrary(Checkpoint checkpoint) async {
    if (checkpoint.audioFilePath == null) return;
    final resolvedPath = await LocalAudioPath.resolve(checkpoint.audioFilePath!);
    if (resolvedPath == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Take is still processing. Please wait.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    // Generate default name from date
    final defaultName = _formatDateForFilename(checkpoint.createdAt);

    // Show naming dialog
    final name = await _showNameInputDialog(defaultName);
    if (name == null) return; // User cancelled

    setState(() {
      _addingToLibrary.add(checkpoint.id);
    });

    final libraryState = context.read<LibraryState>();

    // Get file size
    final sizeBytes = await File(resolvedPath).length();

    final success = await libraryState.addToLibrary(
      localPath: resolvedPath,
      format: 'mp3',
      duration: checkpoint.audioDuration ?? 0,
      sizeBytes: sizeBytes,
      customName: name,
      sourcePatternId: checkpoint.patternId,
      sourceCheckpointId: checkpoint.id,
    );

    if (mounted) {
      setState(() {
        _addingToLibrary.remove(checkpoint.id);
        if (success) {
          _addedToLibrary.add(checkpoint.id);
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Added to library' : 'Failed to add to library'),
          backgroundColor: AppColors.sequencerAccent,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<String?> _showNameInputDialog(String defaultName) async {
    final controller = TextEditingController(text: defaultName);
    
    return showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Center(
          child: Container(
            width: MediaQuery.of(context).size.width * PatternRecordingsOverlay.kDialogWidthFactor * 0.92,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.sequencerSurfaceRaised,
              borderRadius: BorderRadius.circular(1.0),
              border: Border.all(color: AppColors.sequencerBorder, width: 0.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Add To Library',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.sequencerText,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  style: TextStyle(
                    fontSize: 16,
                    color: AppColors.sequencerText,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Enter name',
                    hintStyle: TextStyle(
                      color: AppColors.sequencerLightText,
                    ),
                    filled: true,
                    fillColor: AppColors.sequencerSurfaceBase,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(1.0),
                      borderSide: BorderSide(color: AppColors.sequencerBorder, width: 0.5),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(1.0),
                      borderSide: BorderSide(color: AppColors.sequencerBorder, width: 0.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(1.0),
                      borderSide: BorderSide(color: AppColors.sequencerAccent, width: 1.0),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  onSubmitted: (value) {
                    Navigator.of(context).pop(value.trim().isEmpty ? defaultName : value.trim());
                  },
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.sequencerLightText,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        final value = controller.text.trim();
                        Navigator.of(context).pop(value.isEmpty ? defaultName : value);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.sequencerAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(1.0),
                        ),
                      ),
                      child: Text(
                        'Add',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDateForFilename(DateTime dateTime) {
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final year = dateTime.year;
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$month-$day-$year $hour:$minute';
  }

  Future<void> _handleShare(String filePath, BuildContext shareContext) async {
    try {
      final resolved = await LocalAudioPath.resolve(filePath);
      if (resolved != null) {
        await Share.shareXFiles(
          [XFile(resolved)],
          text: 'Check out my take!',
          sharePositionOrigin: getSharePositionOrigin(shareContext),
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Audio file not found'),
              backgroundColor: AppColors.sequencerAccent,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to share: $e'),
            backgroundColor: AppColors.sequencerAccent,
          ),
        );
      }
    }
  }

  Future<void> _handleDelete(Checkpoint checkpoint) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.sequencerSurfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(1.0),
          side: BorderSide(color: AppColors.sequencerBorder, width: 0.5),
        ),
        title: Text(
          'Delete Take',
          style: TextStyle(color: AppColors.sequencerText),
        ),
        content: Text(
          'Are you sure you want to delete this take?',
          style: TextStyle(color: AppColors.sequencerLightText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.sequencerLightText),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Delete',
              style: TextStyle(color: AppColors.sequencerAccent),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final patternsState = context.read<PatternsState>();
      await patternsState.deleteCheckpoint(checkpoint.id);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Take deleted'),
            backgroundColor: AppColors.sequencerAccent,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);
    
    // Within 48 hours: show relative time
    if (diff.inHours < 48) {
      if (diff.inSeconds < 10) {
        return 'just now';
      } else if (diff.inMinutes < 1) {
        return '${diff.inSeconds}s ago';
      } else if (diff.inHours < 1) {
        return '${diff.inMinutes}m ago';
      } else {
        return '${diff.inHours}h ago';
      }
    } else {
      // After 48 hours: regular date format
      final month = dateTime.month.toString().padLeft(2, '0');
      final day = dateTime.day.toString().padLeft(2, '0');
      final year = dateTime.year;
      final hour = dateTime.hour.toString().padLeft(2, '0');
      final minute = dateTime.minute.toString().padLeft(2, '0');
      return '$month/$day/$year $hour:$minute';
    }
  }

  String _formatDuration(double seconds) {
    final duration = Duration(seconds: seconds.toInt());
    final minutes = duration.inMinutes;
    final remainingSeconds = duration.inSeconds % 60;
    return '${minutes}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Future<int> _getFileSize(String path) async {
    try {
      final file = File(path);
      return await file.length();
    } catch (e) {
      return 0;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<List<Checkpoint>> _filterExistingRecordings(List<Checkpoint> checkpoints) async {
    final results = await Future.wait(
      checkpoints.map((c) async {
        if (c.audioFilePath == null) {
          debugPrint('💿 [RECORDINGS_OVERLAY] Checkpoint ${c.id} has no audio path');
          return null;
        }
        final resolved = await LocalAudioPath.resolve(c.audioFilePath!);
        if (resolved == null) {
          debugPrint('💿 [RECORDINGS_OVERLAY] Audio file not found: ${c.audioFilePath}');
          return null;
        }
        final size = await File(resolved).length();
        debugPrint('💿 [RECORDINGS_OVERLAY] Found audio file: $resolved (${size} bytes)');
        final updated =
            resolved == c.audioFilePath ? c : c.copyWith(audioFilePath: resolved);
        return updated;
      }),
    );
    final filtered = results.whereType<Checkpoint>().toList();
    debugPrint('💿 [RECORDINGS_OVERLAY] Filtered to ${filtered.length} recordings with existing files');
    return filtered;
  }
}
