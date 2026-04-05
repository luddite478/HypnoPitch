import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/sample_asset_resolver.dart';
import '../utils/app_colors.dart';
import '../utils/audio_duration_probe.dart';
import '../widgets/library_header_widget.dart';
import '../widgets/bottom_audio_player.dart';
import '../models/library_item.dart';
import '../state/audio_player_state.dart';
import '../state/library_state.dart';
import '../state/library_samples_state.dart';
import '../state/app_state.dart';
import '../state/patterns_state.dart';
import '../state/sequencer/table.dart';
import '../state/sequencer/sample_bank.dart';
import '../ffi/table_bindings.dart';
import '../ffi/playback_bindings.dart';
import '../ffi/sample_bank_bindings.dart';
import '../utils/local_audio_path.dart';
import '../widgets/tutorial_pulse_widget.dart';
import 'sequencer_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({Key? key}) : super(key: key);
  
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with TickerProviderStateMixin, AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  late TabController _tabController;
  bool _isCallbackActive = false;
  bool _isOpeningPattern = false;
  final Map<String, String> _builtInSampleTempPaths = {};
  
  @override
  bool get wantKeepAlive => true;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onLibraryTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadLibrary();
      _loadLibrarySamples();
      _onLibraryTabChanged();
    });
    _setupAudioPlayerCallback();
    WidgetsBinding.instance.addObserver(this);
  }

  void _onLibraryTabChanged() {
    if (!mounted) return;
    if (_tabController.index != 0) return;
    final appState = context.read<AppState>();
    if (appState.showLibraryLatestRecordingPointer) {
      appState.markLibraryLatestRecordingOpenAction();
    }
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _setupAudioPlayerCallback();
    } else if (state == AppLifecycleState.paused) {
      _clearAudioPlayerCallback();
    }
  }
  
  Future<void> _loadLibrary() async {
    final libraryState = context.read<LibraryState>();
    await libraryState.loadLibrary();
  }

  Future<void> _loadLibrarySamples() async {
    await context.read<LibrarySamplesState>().initialize();
  }
  
  void _setupAudioPlayerCallback() {
    if (_isCallbackActive) return;
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final audioPlayer = context.read<AudioPlayerState>();
      
      audioPlayer.setTrackCompletionCallback(() {
        if (mounted && _isCallbackActive) {
          _playNextTrack(autoAdvance: true);
        }
      });
      
      audioPlayer.setNextTrackCallback(() {
        if (mounted && _isCallbackActive) {
          _playNextTrack();
        }
      });
      
      audioPlayer.setPreviousTrackCallback(() {
        if (mounted && _isCallbackActive) {
          _playPreviousTrack();
        }
      });
      
      _isCallbackActive = true;
    });
  }
  
  void _clearAudioPlayerCallback() {
    if (!_isCallbackActive) return;
    
    try {
      final audioPlayer = context.read<AudioPlayerState>();
      audioPlayer.setTrackCompletionCallback(null);
      audioPlayer.setNextTrackCallback(null);
      audioPlayer.setPreviousTrackCallback(null);
      _isCallbackActive = false;
    } catch (_) {}
  }
  
  void _playNextTrack({bool autoAdvance = false}) {
    final libraryState = context.read<LibraryState>();
    final audioPlayer = context.read<AudioPlayerState>();
    final library = libraryState.library;
    
    if (library.isEmpty) return;
    
    final currentItemId = audioPlayer.currentlyPlayingItemId;
    if (currentItemId == null) return;
    
    final currentIndex = library.indexWhere((item) => item.id == currentItemId);
    if (currentIndex == -1) return;
    
    int nextIndex;
    
    if (audioPlayer.shuffleEnabled && library.length > 1) {
      do {
        nextIndex = (DateTime.now().millisecondsSinceEpoch % library.length);
      } while (nextIndex == currentIndex);
    } else {
      nextIndex = currentIndex + 1;
      
      if (nextIndex >= library.length) {
        if (autoAdvance && audioPlayer.loopMode == LoopMode.playlist) {
          nextIndex = 0;
        } else {
          audioPlayer.pause();
          return;
        }
      }
    }
    
    final nextItem = library[nextIndex];
    _playLibraryItem(nextItem);
  }
  
  void _playPreviousTrack() {
    final libraryState = context.read<LibraryState>();
    final audioPlayer = context.read<AudioPlayerState>();
    final library = libraryState.library;
    
    if (library.isEmpty) return;
    
    final currentItemId = audioPlayer.currentlyPlayingItemId;
    if (currentItemId == null) return;
    
    final currentIndex = library.indexWhere((item) => item.id == currentItemId);
    if (currentIndex == -1) return;
    
    if (audioPlayer.position.inSeconds > 3) {
      audioPlayer.seek(Duration.zero);
      return;
    }
    
    int prevIndex;
    
    if (audioPlayer.shuffleEnabled && library.length > 1) {
      do {
        prevIndex = (DateTime.now().millisecondsSinceEpoch % library.length);
      } while (prevIndex == currentIndex);
    } else {
      prevIndex = currentIndex - 1;
      
      if (prevIndex < 0) {
        if (audioPlayer.loopMode == LoopMode.playlist) {
          prevIndex = library.length - 1;
        } else {
          audioPlayer.seek(Duration.zero);
          return;
        }
      }
    }
    
    final prevItem = library[prevIndex];
    _playLibraryItem(prevItem);
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clearAudioPlayerCallback();
    _tabController.removeListener(_onLibraryTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final appState = context.watch<AppState>();
    
    return WillPopScope(
      onWillPop: () async {
        try {
          context.read<AudioPlayerState>().stop();
        } catch (_) {}
        return true;
      },
      child: Scaffold(
        backgroundColor: AppColors.sequencerPageBackground,
        body: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: SafeArea(
                    child: Column(
                      children: [
                        const LibraryHeaderWidget(),
                        if (appState.activeTutorialStep ==
                            TutorialStep.sequencerLibraryLatestRecordingHint)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            color: AppColors.tutorialTextOverlayColor,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    appState.libraryLatestRecordingStepInstruction,
                                    style: TextStyle(
                                      color: AppColors.sequencerText,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (!appState.showLibraryLatestRecordingPointer &&
                                    !appState.showLibraryLatestRecordingSharePointer)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 10),
                                    child: ElevatedButton(
                                      onPressed: appState.stopTutorial,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            AppColors.sequencerSurfaceRaised,
                                        foregroundColor: AppColors.sequencerText,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 7),
                                        minimumSize: const Size(0, 0),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: const Text(
                                        'Done',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.sequencerSurfaceRaised,
                            border: Border(
                              bottom: BorderSide(
                                color: AppColors.sequencerBorder,
                                width: 1,
                              ),
                            ),
                          ),
                          child: TabBar(
                            controller: _tabController,
                            tabs: [
                              Tab(
                                key: appState.showLibraryLatestRecordingPointer
                                    ? appState.libraryLatestRecordingTutorialKey
                                    : null,
                                child: TutorialPulseWidget(
                                  enabled: appState.showLibraryLatestRecordingPointer,
                                  borderRadius: BorderRadius.circular(8),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 8),
                                    child: Text('RECORDINGS'),
                                  ),
                                ),
                              ),
                              const Tab(text: 'SAMPLES'),
                            ],
                            labelColor: AppColors.sequencerText,
                            unselectedLabelColor: AppColors.sequencerLightText,
                            labelStyle: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.5,
                            ),
                            unselectedLabelStyle: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 1.5,
                            ),
                            indicatorColor: AppColors.sequencerText,
                            indicatorWeight: 2,
                          ),
                        ),
                        
                        Expanded(
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              _buildLibraryTab(),
                              _buildSamplesTab(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const BottomAudioPlayer(),
              ],
            ),
            if (_isOpeningPattern)
              Positioned.fill(
                child: Container(
                  color: AppColors.sequencerPageBackground.withOpacity(0.75),
                  child: Center(
                    child: Text(
                      'Loading pattern...',
                      style: TextStyle(
                        color: AppColors.sequencerText,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLibraryTab() {
    return Consumer3<LibraryState, AudioPlayerState, AppState>(
      builder: (context, libraryState, audioPlayer, appState, _) {
        if (libraryState.isLoading && !libraryState.hasLoaded) {
          return const Center(child: CircularProgressIndicator());
        }
        
        if (libraryState.library.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Your library is empty',
                  style: TextStyle(
                    color: AppColors.sequencerLightText,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Add audio recordings from the sequencer',
                  style: TextStyle(
                    color: AppColors.sequencerLightText,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          );
        }
        
        return ListView.builder(
          padding: const EdgeInsets.only(top: 2),
          itemCount: libraryState.library.length,
          itemBuilder: (context, index) {
            final item = libraryState.library[index];
            final isPlaying = audioPlayer.currentlyPlayingItemId == item.id && audioPlayer.isPlaying;
            final isLatestRecordingStep =
                appState.activeTutorialStep ==
                TutorialStep.sequencerLibraryLatestRecordingHint;
            final isLatestItem = index == 0;
            final showLatestRecordingSharePointer =
                isLatestRecordingStep &&
                isLatestItem &&
                appState.showLibraryLatestRecordingSharePointer;
        
            return Container(
              height: 60,
              margin: const EdgeInsets.only(bottom: 2),
              decoration: BoxDecoration(
                color: isPlaying 
                    ? AppColors.sequencerAccent.withOpacity(0.1)
                    : AppColors.sequencerSurfaceRaised,
                border: Border(
                  bottom: BorderSide(
                    color: showLatestRecordingSharePointer
                        ? AppColors.sequencerAccent
                        : AppColors.sequencerBorder,
                    width: showLatestRecordingSharePointer
                        ? 1.2
                        : 0.5,
                  ),
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _playLibraryItem(item),
                  onLongPress: () => _showRemoveDialog(item),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.music_note,
                          color: AppColors.sequencerText,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                item.name,
                                style: TextStyle(
                                  color: AppColors.sequencerText,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (item.duration != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  _formatDuration(item.duration!),
                                  style: TextStyle(
                                    color: AppColors.sequencerLightText,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        
                        const SizedBox(width: 8),
                        Builder(
                          builder: (buttonContext) => TutorialPulseWidget(
                            enabled: showLatestRecordingSharePointer,
                            borderRadius: BorderRadius.circular(10),
                            child: IconButton(
                              key: showLatestRecordingSharePointer
                                  ? appState.libraryLatestRecordingShareTutorialKey
                                  : null,
                              icon: Icon(
                                Icons.share,
                                color: showLatestRecordingSharePointer
                                    ? AppColors.sequencerAccent
                                    : AppColors.sequencerLightText,
                                size: 20,
                              ),
                              onPressed: () {
                                if (showLatestRecordingSharePointer) {
                                  appState.markLibraryLatestRecordingShareAction();
                                }
                                _shareLibraryItem(item, buttonContext);
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 40,
                                minHeight: 40,
                              ),
                            ),
                          ),
                        ),
                        PopupMenuButton<String>(
                          icon: Icon(
                            Icons.more_vert,
                            color: AppColors.sequencerLightText,
                            size: 20,
                          ),
                          padding: EdgeInsets.zero,
                          color: AppColors.sequencerSurfaceRaised,
                          onSelected: (value) {
                            if (value == 'open_pattern') {
                              _openLinkedPattern(item);
                            } else if (value == 'delete') {
                              _showRemoveDialog(item);
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'open_pattern',
                              child: Text(
                                'Open Pattern',
                                style: TextStyle(
                                  color: AppColors.sequencerText,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text(
                                'Delete',
                                style: TextStyle(
                                  color: AppColors.sequencerAccent,
                                  fontSize: 13,
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
          },
        );
      },
    );
  }
  
  String _formatDuration(double duration) {
    final minutes = (duration / 60).floor();
    final seconds = (duration % 60).floor();
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
  
  Future<void> _playLibraryItem(LibraryItem item) async {
    final audioPlayer = context.read<AudioPlayerState>();
    
    await audioPlayer.playFromPath(
      itemId: item.id,
      localPath: item.localPath,
    );
  }
  
  void _showRemoveDialog(LibraryItem item) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.sequencerSurfaceRaised,
          title: Text(
            'Remove from Library',
            style: TextStyle(
              color: AppColors.sequencerText,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            'Are you sure you want to remove "${item.name}" from your library?',
            style: TextStyle(
              color: AppColors.sequencerLightText,
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: AppColors.sequencerLightText,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _removeFromLibrary(item);
              },
              child: Text(
                'Remove',
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
  
  Future<void> _removeFromLibrary(LibraryItem item) async {
    final libraryState = context.read<LibraryState>();
    final success = await libraryState.removeFromLibrary(item.id);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Removed from library' : 'Failed to remove'),
          backgroundColor: success ? AppColors.sequencerAccent : Colors.red.shade900,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _shareLibraryItem(LibraryItem item, BuildContext buttonContext) async {
    await _shareAudioFile(
      localPath: item.localPath,
      title: item.name,
      buttonContext: buttonContext,
    );
  }

  Future<void> _shareAudioFile({
    required String localPath,
    required String title,
    required BuildContext buttonContext,
  }) async {
    try {
      final resolved = await LocalAudioPath.resolve(localPath);
      if (resolved == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Audio file not found'),
              backgroundColor: Colors.red.shade900,
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return;
      }
      
      final box = buttonContext.findRenderObject() as RenderBox?;
      final Rect sharePositionOrigin = box == null
          ? Rect.fromLTWH(0, 0, 100, 100)
          : box.localToGlobal(Offset.zero) & box.size;
      
      final xFile = XFile(resolved);
      await Share.shareXFiles(
        [xFile],
        subject: title,
        text: title,
        sharePositionOrigin: sharePositionOrigin,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to share: $e'),
            backgroundColor: Colors.red.shade900,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<String?> _ensureBuiltInTempFile(String sampleId) async {
    final existing = _builtInSampleTempPaths[sampleId];
    if (existing != null) {
      try {
        if (await File(existing).exists()) return existing;
      } catch (_) {}
      _builtInSampleTempPaths.remove(sampleId);
    }
    final resolver = SampleAssetResolver.instance;
    final assetPath = await resolver.resolveAssetPathFromSampleId(sampleId);
    if (assetPath == null || assetPath.isEmpty) {
      return null;
    }
    final temp = await resolver.copyAssetToTempFile(assetPath);
    if (temp != null) {
      _builtInSampleTempPaths[sampleId] = temp;
    }
    return temp;
  }

  Future<void> _playBuiltInSample(String sampleId) async {
    try {
      final path = await _ensureBuiltInTempFile(sampleId);
      if (path == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Sample file not available'),
            backgroundColor: Colors.red.shade900,
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }
      await context.read<AudioPlayerState>().playFromPath(
            itemId: 'builtin:$sampleId',
            localPath: path,
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to play sample: $e'),
          backgroundColor: Colors.red.shade900,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _playCustomSample({
    required String folderName,
    required String filePath,
  }) async {
    try {
      final resolved = await LocalAudioPath.resolve(filePath);
      if (resolved == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Audio file not found'),
            backgroundColor: Colors.red.shade900,
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }
      final itemId = LibrarySamplesState.customSampleIdFor(
        folderName: folderName,
        filePath: filePath,
      );
      await context.read<AudioPlayerState>().playFromPath(
            itemId: itemId,
            localPath: resolved,
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to play file: $e'),
          backgroundColor: Colors.red.shade900,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showRemoveCustomSampleDialog({
    required String folderName,
    required String filePath,
  }) {
    final fileName = filePath.split('/').last;
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.sequencerSurfaceRaised,
          title: Text(
            'Delete custom sample',
            style: TextStyle(
              color: AppColors.sequencerText,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            'Delete "$fileName" from "$folderName"?',
            style: TextStyle(
              color: AppColors.sequencerLightText,
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: AppColors.sequencerLightText,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _removeCustomSample(
                  folderName: folderName,
                  filePath: filePath,
                );
              },
              child: Text(
                'Delete',
                style: TextStyle(
                  color: AppColors.sequencerAccent,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _removeCustomSample({
    required String folderName,
    required String filePath,
  }) async {
    final success = await context.read<LibrarySamplesState>().removeCustomFile(
          folderName: folderName,
          filePath: filePath,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? 'Custom sample deleted' : 'Failed to delete sample',
        ),
        backgroundColor: success ? AppColors.sequencerAccent : Colors.red.shade900,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showRemoveCustomFolderDialog(String folderName) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.sequencerSurfaceRaised,
          title: Text(
            'Delete folder',
            style: TextStyle(
              color: AppColors.sequencerText,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            'Delete "$folderName" and all samples inside? This cannot be undone.',
            style: TextStyle(
              color: AppColors.sequencerLightText,
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: AppColors.sequencerLightText,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _removeCustomFolder(folderName);
              },
              child: Text(
                'Delete',
                style: TextStyle(
                  color: AppColors.sequencerAccent,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _removeCustomFolder(String folderName) async {
    final samples = context.read<LibrarySamplesState>();
    final success = await samples.removeCustomFolder(folderName);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? 'Folder deleted' : 'Failed to delete folder',
        ),
        backgroundColor: success ? AppColors.sequencerAccent : Colors.red.shade900,
        duration: const Duration(seconds: 2),
      ),
    );
  }
  
  Future<void> _openLinkedPattern(LibraryItem item) async {
    final sourcePatternId = item.sourcePatternId;
    if (sourcePatternId == null) {
      if (mounted) {
        _showPatternNotFoundDialog();
      }
      return;
    }

    try {
      if (mounted) {
        setState(() {
          _isOpeningPattern = true;
        });
      }
      // Let Flutter paint the loading overlay before doing heavy work.
      await Future<void>.delayed(const Duration(milliseconds: 16));
      await WidgetsBinding.instance.endOfFrame;

      final patternsState = context.read<PatternsState>();
      final audioPlayer = context.read<AudioPlayerState>();
      final tableState = context.read<TableState>();
      final sampleBankState = context.read<SampleBankState>();

      await patternsState.loadPatterns();

      final index = patternsState.patterns.indexWhere((p) => p.id == sourcePatternId);
      if (index < 0) {
        if (!mounted) return;
        _showPatternNotFoundDialog();
        return;
      }

      final pattern = patternsState.patterns[index];

      await audioPlayer.stop();
      await patternsState.setActivePattern(pattern);

      tableState.resetAllLayerModes();
      tableState.setUiSelectedLayer(0);
      tableState.setUiSelectedSection(0);

      try {
        TableBindings().tableInit();
        PlaybackBindings().playbackInit();
        SampleBankBindings().sampleBankInit();
        sampleBankState.syncSampleBankState();
      } catch (e) {
        debugPrint('❌ Failed to init native systems from library: $e');
      }

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const PatternScreen(),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to open source pattern: $e'),
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningPattern = false;
        });
      }
    }
  }

  void _showPatternNotFoundDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.sequencerSurfaceRaised,
          title: Text(
            'Pattern Not Found',
            style: TextStyle(
              color: AppColors.sequencerText,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            'This pattern does not exist anymore.',
            style: TextStyle(
              color: AppColors.sequencerLightText,
              fontSize: 14,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'OK',
                style: TextStyle(
                  color: AppColors.sequencerAccent,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSamplesTab() {
    return Consumer<LibrarySamplesState>(
      builder: (context, samplesState, _) {
        if (samplesState.isLoading && !samplesState.isInitialized) {
          return const Center(child: CircularProgressIndicator());
        }

        return Column(
          children: [
            _buildSamplesNavBar(samplesState),
            Expanded(
              child: samplesState.isAtRoot
                  ? _buildSamplesRootGrid(samplesState)
                  : _buildSamplesContent(samplesState),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSamplesNavBar(LibrarySamplesState state) {
    final canGoBack = !state.isAtRoot;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceRaised,
        border: Border(
          bottom: BorderSide(color: AppColors.sequencerBorder, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          if (canGoBack)
            GestureDetector(
              onTap: state.navigateBack,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.sequencerSurfaceBase,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.sequencerBorder, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back, color: AppColors.sequencerText, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      'BACK',
                      style: TextStyle(
                        color: AppColors.sequencerText,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (canGoBack) const SizedBox(width: 8),
          Expanded(
            child: Text(
              state.currentPathLabel,
              style: TextStyle(
                color: AppColors.sequencerLightText,
                fontSize: 11,
                fontWeight: FontWeight.w400,
                letterSpacing: 0.3,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSamplesRootGrid(LibrarySamplesState state) {
    final customFolders = state.customFolders;
    final totalTiles = 2 + customFolders.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = constraints.maxWidth * 0.02;
        return GridView.builder(
          padding: EdgeInsets.all(spacing),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: 2.0,
          ),
          itemCount: totalTiles,
          itemBuilder: (context, index) {
            if (index == 0) {
              return _buildFolderTile(
                title: LibrarySamplesState.defaultRootName(),
                icon: Icons.folder,
                onTap: state.openDefaultRoot,
              );
            }
            if (index == totalTiles - 1) {
              return _buildFolderTile(
                title: '',
                icon: Icons.add,
                onTap: _handleAddCustomSamples,
              );
            }

            final folder = customFolders[index - 1];
            return _buildFolderTile(
              title: folder,
              icon: Icons.folder,
              onTap: () => state.openCustomFolder(folder),
              onLongPress: () => _showRemoveCustomFolderDialog(folder),
            );
          },
        );
      },
    );
  }

  Widget _buildFolderTile({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    final hasTitle = title.trim().isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.sequencerSurfaceRaised,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.sequencerBorder, width: 1),
          boxShadow: [
            BoxShadow(
              color: AppColors.sequencerShadow,
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.sequencerAccent, size: 28),
              if (hasTitle) const SizedBox(height: 4),
              if (hasTitle)
                Flexible(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: AppColors.sequencerText,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSamplesContent(LibrarySamplesState state) {
    if (state.isInDefault) {
      final items = state.currentBuiltInItems;
      if (items.isEmpty) {
        return _buildEmptySamplesMessage('No samples found in this folder.');
      }

      return ListView.builder(
        padding: const EdgeInsets.only(top: 2),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          if (item.isFolder) {
            return _buildDefaultFolderListRow(
              title: item.name,
              onTap: () => state.openDefaultFolder(item.name),
            );
          }
          final sampleId = item.sampleId;
          if (sampleId == null) {
            return const SizedBox.shrink();
          }
          return Consumer<AudioPlayerState>(
            builder: (context, audioPlayer, _) {
              final itemId = 'builtin:$sampleId';
              final isPlaying = audioPlayer.currentlyPlayingItemId == itemId &&
                  audioPlayer.isPlaying;
              return _LibraryBuiltInSampleRow(
                key: ValueKey(itemId),
                title: item.name,
                isPlaying: isPlaying,
                onEnsureTempPath: () => _ensureBuiltInTempFile(sampleId),
                onTap: () => _playBuiltInSample(sampleId),
              );
            },
          );
        },
      );
    }

    final files = state.currentCustomFiles;
    if (files.isEmpty) {
      return _buildEmptySamplesMessage('This custom folder has no imported files.');
    }
    final folderName = state.currentCustomFolder;
    if (folderName == null) {
      return _buildEmptySamplesMessage('This custom folder has no imported files.');
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 2),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final filePath = files[index];
        return _buildCustomSampleListItem(
          filePath: filePath,
          folderName: folderName,
        );
      },
    );
  }

  Widget _buildDefaultFolderListRow({
    required String title,
    required VoidCallback onTap,
  }) {
    return Container(
      height: 60,
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceRaised,
        border: Border(
          bottom: BorderSide(
            color: AppColors.sequencerBorder,
            width: 0.5,
          ),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.folder,
                  color: AppColors.sequencerText,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: AppColors.sequencerText,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Folder',
                        style: TextStyle(
                          color: AppColors.sequencerLightText,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: AppColors.sequencerLightText,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomSampleListItem({
    required String filePath,
    required String folderName,
  }) {
    final fileName = filePath.split('/').last;
    final itemId = LibrarySamplesState.customSampleIdFor(
      folderName: folderName,
      filePath: filePath,
    );

    return Consumer<AudioPlayerState>(
      builder: (context, audioPlayer, _) {
        final isPlaying =
            audioPlayer.currentlyPlayingItemId == itemId && audioPlayer.isPlaying;
        return _LibraryCustomSampleRow(
          key: ValueKey(itemId),
          filePath: filePath,
          fileName: fileName,
          isPlaying: isPlaying,
          onTap: () => _playCustomSample(
                folderName: folderName,
                filePath: filePath,
              ),
          onDelete: () => _showRemoveCustomSampleDialog(
                folderName: folderName,
                filePath: filePath,
              ),
        );
      },
    );
  }

  Widget _buildEmptySamplesMessage(String message) {
    return Center(
      child: Text(
        message,
        style: TextStyle(
          color: AppColors.sequencerLightText,
          fontSize: 12,
        ),
      ),
    );
  }

  Future<void> _handleAddCustomSamples() async {
    final folderName = await _showFolderNameDialog();
    if (!mounted || folderName == null || folderName.trim().isEmpty) {
      return;
    }

    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['wav', 'mp3', 'm4a', 'aif', 'aiff', 'flac', 'ogg'],
    );
    if (!mounted || picked == null || picked.files.isEmpty) {
      return;
    }

    final result = await context.read<LibrarySamplesState>().importFilesToCustomFolder(
      folderName: folderName.trim(),
      files: picked.files,
    );
    if (!mounted) return;

    final isSuccess = result.importedCount > 0;
    final message = isSuccess
        ? 'Imported ${result.importedCount} file(s) to "$folderName"'
        : (result.errorMessage ?? 'No files were imported.');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isSuccess ? AppColors.sequencerAccent : Colors.red.shade900,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<String?> _showFolderNameDialog() async {
    String folderName = '';
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.sequencerSurfaceRaised,
          title: Text(
            'Create custom folder',
            style: TextStyle(
              color: AppColors.sequencerText,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: TextField(
            autofocus: true,
            onChanged: (value) => folderName = value,
            style: TextStyle(color: AppColors.sequencerText),
            decoration: InputDecoration(
              hintText: 'Folder name',
              hintStyle: TextStyle(color: AppColors.sequencerLightText),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(color: AppColors.sequencerLightText),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(folderName),
              child: Text(
                'Continue',
                style: TextStyle(color: AppColors.sequencerAccent),
              ),
            ),
          ],
        );
      },
    );
    return result;
  }
}

String _formatSampleDurationLine(double durationSeconds) {
  final minutes = (durationSeconds / 60).floor();
  final seconds = (durationSeconds % 60).floor();
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

class _LibraryCustomSampleRow extends StatefulWidget {
  const _LibraryCustomSampleRow({
    super.key,
    required this.filePath,
    required this.fileName,
    required this.isPlaying,
    required this.onTap,
    required this.onDelete,
  });

  final String filePath;
  final String fileName;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  State<_LibraryCustomSampleRow> createState() =>
      _LibraryCustomSampleRowState();
}

class _LibraryCustomSampleRowState extends State<_LibraryCustomSampleRow> {
  double? _durationSec;

  @override
  void initState() {
    super.initState();
    _loadDuration();
  }

  Future<void> _loadDuration() async {
    final resolved = await LocalAudioPath.resolve(widget.filePath);
    if (!mounted || resolved == null) return;
    final sec = await AudioDurationProbe.secondsForFilePath(resolved);
    if (mounted) setState(() => _durationSec = sec);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: widget.isPlaying
            ? AppColors.sequencerAccent.withOpacity(0.1)
            : AppColors.sequencerSurfaceRaised,
        border: Border(
          bottom: BorderSide(
            color: AppColors.sequencerBorder,
            width: 0.5,
          ),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onDelete,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.music_note,
                  color: AppColors.sequencerText,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.fileName,
                        style: TextStyle(
                          color: AppColors.sequencerText,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_durationSec != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          _formatSampleDurationLine(_durationSec!),
                          style: TextStyle(
                            color: AppColors.sequencerLightText,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    color: AppColors.sequencerLightText,
                    size: 20,
                  ),
                  padding: EdgeInsets.zero,
                  color: AppColors.sequencerSurfaceRaised,
                  onSelected: (value) {
                    if (value == 'delete') {
                      widget.onDelete();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        'Delete',
                        style: TextStyle(
                          color: AppColors.sequencerAccent,
                          fontSize: 13,
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
}

class _LibraryBuiltInSampleRow extends StatefulWidget {
  const _LibraryBuiltInSampleRow({
    super.key,
    required this.title,
    required this.isPlaying,
    required this.onEnsureTempPath,
    required this.onTap,
  });

  final String title;
  final bool isPlaying;
  final Future<String?> Function() onEnsureTempPath;
  final VoidCallback onTap;

  @override
  State<_LibraryBuiltInSampleRow> createState() =>
      _LibraryBuiltInSampleRowState();
}

class _LibraryBuiltInSampleRowState extends State<_LibraryBuiltInSampleRow> {
  double? _durationSec;

  @override
  void initState() {
    super.initState();
    _loadDuration();
  }

  Future<void> _loadDuration() async {
    final path = await widget.onEnsureTempPath();
    if (!mounted || path == null) return;
    final sec = await AudioDurationProbe.secondsForFilePath(path);
    if (mounted) setState(() => _durationSec = sec);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: widget.isPlaying
            ? AppColors.sequencerAccent.withOpacity(0.1)
            : AppColors.sequencerSurfaceRaised,
        border: Border(
          bottom: BorderSide(
            color: AppColors.sequencerBorder,
            width: 0.5,
          ),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.music_note,
                  color: AppColors.sequencerText,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.title,
                        style: TextStyle(
                          color: AppColors.sequencerText,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_durationSec != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          _formatSampleDurationLine(_durationSec!),
                          style: TextStyle(
                            color: AppColors.sequencerLightText,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
