import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import '../widgets/sequencer/v2/sample_banks_widget.dart' as v2;
import '../widgets/sequencer/v2/edit_buttons_widget.dart' as v2;
import '../widgets/sequencer/v2/top_multitask_panel_widget.dart' as v2;
import '../widgets/sequencer/v2/sequencer_body.dart';
import '../widgets/sequencer/v2/value_control_overlay.dart';
import '../widgets/sequencer/participants_widget.dart';
import '../widgets/thread/v2/thread_view_widget.dart';
import '../state/threads_state.dart';
import '../state/audio_player_state.dart';
import '../state/user_state.dart';
import '../services/threads_service.dart';
import '../services/snapshot/snapshot_service.dart';
import '../services/http_client.dart';
import '../utils/app_colors.dart';
import '../utils/thread_name_generator.dart';
import '../utils/log.dart';
import '../utils/app_icons.dart';
import '../models/thread/thread.dart';
import '../models/thread/thread_user.dart';
import '../models/thread/message.dart';
// New state imports for migration
import '../state/sequencer/table.dart';
import '../state/sequencer/playback.dart';
import '../state/sequencer/sample_bank.dart';
import '../state/sequencer/sample_browser.dart';
import '../state/sequencer/timer.dart';
import '../state/sequencer/multitask_panel.dart';
import '../state/sequencer/sound_settings.dart';
import '../state/sequencer/recording.dart';
import '../state/sequencer/edit.dart';
import '../state/sequencer/section_settings.dart';
import '../state/sequencer/slider_overlay.dart';
import '../state/sequencer/undo_redo.dart';
import '../state/sequencer/ui_selection.dart';
import '../services/thread_draft_service.dart';
import 'sequencer_settings_screen.dart';
import '../widgets/username_creation_dialog.dart';
import '../state/library_state.dart';

enum _SequencerView { sequencer, thread }

class SequencerScreenV2 extends StatefulWidget {
  final Map<String, dynamic>? initialSnapshot;
  final bool openThreadView; // If true, opens to thread view tab instead of sequencer

  const SequencerScreenV2({super.key, this.initialSnapshot, this.openThreadView = false});

  @override
  State<SequencerScreenV2> createState() => _SequencerScreenV2State();
}

class _SequencerScreenV2State extends State<SequencerScreenV2> with TickerProviderStateMixin, WidgetsBindingObserver {
  late ThreadsService _threadsService;
  
  // New state instances for migration
  late final TableState _tableState;
  late final PlaybackState _playbackState;
  late final SampleBankState _sampleBankState;
  late final SampleBrowserState _sampleBrowserState;
  late final TimerState _timerState;
  late final MultitaskPanelState _multitaskPanelState;
  late final SoundSettingsState _soundSettingsState;
  late final RecordingState _recordingState;
  late final EditState _editState;
  late final UiSelectionState _uiSelectionState;
  late final SectionSettingsState _sectionSettingsState;
  late final SliderOverlayState _sliderOverlayState;
  late final UndoRedoState _undoRedoState;
  late final ThreadDraftService _draftService;
  
  bool _isInitialLoading = false;
  
  // View switching state
  late _SequencerView _currentView;
  late PageController _pageController;
  
  // Thread screen state
  final ScrollController _threadScrollController = ScrollController();
  bool _isLoadingOlderMessages = false;
  bool _hasMoreMessages = true;
  static const int _initialMessageCount = 30;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Initialize view based on openThreadView parameter
    _currentView = widget.openThreadView ? _SequencerView.thread : _SequencerView.sequencer;
    
    // Initialize page controller with appropriate initial page
    // Page 0 = Sequencer, Page 1 = Thread
    _pageController = PageController(initialPage: widget.openThreadView ? 1 : 0);
    
    debugPrint('🎵 [SEQUENCER_V2] Initialized with openThreadView: ${widget.openThreadView}, initialPage: ${widget.openThreadView ? 1 : 0}');
    
    // Initialize thread scroll listener
    _threadScrollController.addListener(_onThreadScroll);
    
    // Initialize new state system (reuse Provider-managed states)
    Log.d('Initializing new state system', 'SEQUENCER_V2');
    _undoRedoState = UndoRedoState();
    _tableState = Provider.of<TableState>(context, listen: false);
    _playbackState = Provider.of<PlaybackState>(context, listen: false);
    _sampleBankState = Provider.of<SampleBankState>(context, listen: false);
    _sampleBrowserState = SampleBrowserState();
    _multitaskPanelState = MultitaskPanelState();
    _soundSettingsState = SoundSettingsState();
    _uiSelectionState = UiSelectionState();
    _recordingState = RecordingState();
    _recordingState.setOnRecordingComplete(() => _onRecordingComplete());
    _editState = EditState(_tableState, _uiSelectionState);
    _sectionSettingsState = SectionSettingsState();
    _sliderOverlayState = SliderOverlayState();
    
    // Initialize timer with dependencies
    _timerState = TimerState(
      tableState: _tableState,
      playbackState: _playbackState,
      sampleBankState: _sampleBankState,
      undoRedoState: _undoRedoState,
    );
    
    // Initialize draft service for thread-specific draft saving
    _draftService = ThreadDraftService(
      tableState: _tableState,
      playbackState: _playbackState,
      sampleBankState: _sampleBankState,
    );
    
    // Use the global ThreadsService from Provider instead of creating a new one
    _threadsService = Provider.of<ThreadsService>(context, listen: false);
    _setupThreadsServiceListeners();
    
    // Attach RecordingState to ThreadsState for audio upload functionality
    final threadsState = Provider.of<ThreadsState>(context, listen: false);
    threadsState.attachRecordingState(_recordingState);
    
    // Start new state system and ensure active thread
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrapInitialLoad();
    });
  }

  void _setupThreadsServiceListeners() async {
    // Setup connection status listener
    _threadsService.connectionStream.listen((connected) {
      Log.d('Connection status changed: $connected', 'THREADS');
      if (connected) {
        Log.i('WebSocket connected and ready for notifications', 'THREADS');
      } else {
        Log.w('WebSocket disconnected', 'THREADS');
      }
    });
    
    // Setup error listener
    _threadsService.errorStream.listen((error) {
      Log.e('ThreadsService error: $error', 'THREADS');
    });
    
    // No need to connect here - it's already connected globally
    Log.i('Using global ThreadsService connection in sequencer V2', 'THREADS');
  }

  Future<void> _importInitialSnapshotIfAny() async {
    final snapshot = widget.initialSnapshot;
    if (snapshot == null) return;
    try {
      final service = SnapshotService(
        tableState: _tableState,
        playbackState: _playbackState,
        sampleBankState: _sampleBankState,
      );
      await service.importFromJson(json.encode(snapshot));
      Log.i('Imported initial snapshot into Sequencer V2', 'SEQUENCER_V2');
    } catch (e) {
      Log.e('Failed to import initial snapshot', 'SEQUENCER_V2', e);
    }
  }

  Future<void> _ensureActiveThread() async {
    final threadsState = Provider.of<ThreadsState>(context, listen: false);
    
    // If there's no active thread, create one (no collaboration logic)
    if (threadsState.activeThread == null) {
      try {
        Log.d('No active thread found, creating new unpublished thread', 'SEQUENCER_V2');
        
        final currentUserId = threadsState.currentUserId;
        final currentUserName = threadsState.currentUserName;
        
        if (currentUserId != null) {
          // Create an unpublished thread for this new project
          // Generate name using timestamp as seed for uniqueness
          final threadName = ThreadNameGenerator.generate(DateTime.now().microsecondsSinceEpoch.toString());
          final threadId = await threadsState.createThread(
            users: [
              ThreadUser(
                id: currentUserId, 
                username: context.read<UserState>().currentUser?.username ?? currentUserName ?? 'User',
                name: currentUserName ?? 'User', 
                joinedAt: DateTime.now(),
              ),
            ],
            name: threadName,
            metadata: {
              'project_type': 'solo',
              'is_public': false,
              'created_from': 'sequencer_v2',
              'layout_version': 'v2',
            },
          );
          
          Log.i('Created new unpublished thread: $threadId with name: $threadName', 'SEQUENCER_V2');
        } else {
          Log.w('Cannot create thread: No current user ID', 'SEQUENCER_V2');
        }
      } catch (e) {
        Log.e('Failed to create initial thread', 'SEQUENCER_V2', e);
        // Not critical - user can still work and publish later
      }
    }
    
    // Preload recent messages in background for instant thread screen navigation
    final activeThread = threadsState.activeThread;
    if (activeThread != null) {
      // Preload only recent 30 messages (not all) for faster loading and instant thread UI
      threadsState.preloadRecentMessages(activeThread.id, limit: 30).catchError((e) {
        Log.d('Background message preload failed (non-critical): $e', 'SEQUENCER_V2');
      });
    }
  }

  Future<void> _bootstrapInitialLoad() async {
    if (mounted) {
      setState(() {
        _isInitialLoading = true;
      });
    }
    try {
      _timerState.start();
      _sampleBrowserState.initialize();
      await _ensureActiveThread();
      
      // Draft functionality disabled - only manual checkpoints are saved
      // Start tracking draft for active thread
      // final threadsState = Provider.of<ThreadsState>(context, listen: false);
      // final activeThread = threadsState.activeThread;
      // if (activeThread != null) {
      //   _draftService.startTracking(activeThread.id);
      // }
      
      // Load server snapshot first (if provided), then draft if no snapshot
      // Draft is only used when there are no saved messages
      await _importInitialSnapshotIfAny();
      // Draft loading disabled
      // if (widget.initialSnapshot == null) {
      //   await _loadDraftIfAny();
      // }
      
      // If opening directly to thread view, load thread messages
      if (widget.openThreadView) {
        debugPrint('🎵 [SEQUENCER_V2] Loading thread messages for initial thread view');
        await _loadThreadMessages();
      }
    } catch (e) {
      Log.e('Initial sequencer bootstrap failed', 'SEQUENCER_V2', e);
    } finally {
      if (mounted) {
        setState(() {
          _isInitialLoading = false;
        });
      }
    }
  }
  
  // Draft loading disabled - only manual checkpoints are saved
  // Future<void> _loadDraftIfAny() async {
  //   final threadsState = Provider.of<ThreadsState>(context, listen: false);
  //   final activeThread = threadsState.activeThread;
  //   
  //   if (activeThread == null) return;
  //   
  //   try {
  //     final draft = await _draftService.loadDraft(activeThread.id);
  //     if (draft != null) {
  //       final service = SnapshotService(
  //         tableState: _tableState,
  //         playbackState: _playbackState,
  //         sampleBankState: _sampleBankState,
  //       );
  //       await service.importFromJson(json.encode(draft));
  //       debugPrint('✅ Loaded draft for thread: ${activeThread.id}');
  //     }
  //   } catch (e) {
  //     debugPrint('❌ Failed to load draft: $e');
  //   }
  // }

  void _switchView(_SequencerView newView) {
    if (_currentView == newView) return;
    
    final threadsState = context.read<ThreadsState>();
    
    // Stop audio playback when switching FROM thread view (audio is only played in thread view)
    if (_currentView == _SequencerView.thread) {
      try {
        context.read<AudioPlayerState>().stop();
        // Exit thread view to stop marking new messages as auto-read
        threadsState.exitThreadView();
        debugPrint('👋 [SEQUENCER_V2] Exited thread view');
      } catch (_) {}
    }
    
    setState(() {
      _currentView = newView;
    });
    
    final targetPage = newView == _SequencerView.sequencer ? 0 : 1;
    _pageController.animateToPage(
      targetPage,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    
    // Load thread messages when switching to thread view
    if (newView == _SequencerView.thread) {
      _loadThreadMessages();
    }
  }

  Future<void> _loadThreadMessages() async {
    final threadsState = context.read<ThreadsState>();
    final activeThread = threadsState.activeThread;
    
    if (activeThread == null) return;
    
    threadsState.enterThreadView(activeThread.id);
    
    try {
      await threadsState.ensureThreadSummary(activeThread.id);
    } catch (_) {}
    
    // Load only recent messages if not already loaded
    final alreadyLoaded = threadsState.hasMessagesLoaded(activeThread.id);
    
    if (!alreadyLoaded) {
      await threadsState.loadMessages(
        activeThread.id,
        includeSnapshot: false,
        order: 'desc',
        limit: _initialMessageCount,
      );
    }
    
    // Mark messages as read (resets unread badge)
    await threadsState.markMessagesAsRead();
    
    final loadedCount = threadsState.activeThreadMessages.length;
    if (mounted) {
      setState(() {
        _hasMoreMessages = loadedCount >= _initialMessageCount;
      });
    }
  }

  void _onThreadScroll() {
    final maxScroll = _threadScrollController.position.maxScrollExtent;
    final currentScroll = _threadScrollController.position.pixels;
    
    if (maxScroll - currentScroll <= 100 && !_isLoadingOlderMessages && _hasMoreMessages) {
      _loadOlderMessages();
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_isLoadingOlderMessages || !_hasMoreMessages) return;
    
    setState(() {
      _isLoadingOlderMessages = true;
    });
    
    try {
      final threadsState = context.read<ThreadsState>();
      final currentMessages = threadsState.activeThreadMessages;
      
      if (currentMessages.isEmpty) {
        setState(() {
          _isLoadingOlderMessages = false;
        });
        return;
      }
      
      debugPrint('📜 Would load older messages');
      
      setState(() {
        _hasMoreMessages = false;
        _isLoadingOlderMessages = false;
      });
    } catch (e) {
      debugPrint('❌ Failed to load older messages: $e');
      setState(() {
        _isLoadingOlderMessages = false;
      });
    }
  }

  @override
  void dispose() {
    Log.d('Disposing new state system', 'SEQUENCER_V2');
    
    try {
      final threadsState = context.read<ThreadsState>();
      threadsState.exitThreadView();
      final audioPlayer = context.read<AudioPlayerState>();
      audioPlayer.stop();
    } catch (_) {}
    
    // Draft saving disabled - only manual checkpoints are saved
    // _draftService.saveDraft();
    _draftService.stopTracking();
    
    _timerState.dispose();
    _sampleBrowserState.dispose();
    _multitaskPanelState.dispose();
    _soundSettingsState.dispose();
    _recordingState.dispose();
    _editState.dispose();
    _sectionSettingsState.dispose();
    _undoRedoState.dispose();
    _pageController.dispose();
    _threadScrollController.dispose();
    
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Log.d('App resumed - reconfiguring Bluetooth audio session', 'SEQUENCER_V2');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _tableState),
        ChangeNotifierProvider.value(value: _playbackState),
        ChangeNotifierProvider.value(value: _sampleBankState),
        ChangeNotifierProvider.value(value: _sampleBrowserState),
        ChangeNotifierProvider.value(value: _multitaskPanelState),
        ChangeNotifierProvider.value(value: _soundSettingsState),
        ChangeNotifierProvider.value(value: _recordingState),
        ChangeNotifierProvider.value(value: _editState),
        ChangeNotifierProvider.value(value: _sectionSettingsState),
        ChangeNotifierProvider.value(value: _sliderOverlayState),
        ChangeNotifierProvider.value(value: _undoRedoState),
        ChangeNotifierProvider.value(value: _uiSelectionState),
      ],
      child: Scaffold(
        backgroundColor: _currentView == _SequencerView.sequencer 
            ? AppColors.sequencerPageBackground 
            : AppColors.sequencerPageBackground, // Dark gray background for thread view
        appBar: _buildCommonHeader(context),
        body: Stack(
          children: [
            // Main content with page view
            PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(), // Disable swipe, only button controls
              children: [
                _buildSequencerView(),
                _buildThreadView(),
              ],
            ),
            
            // Floating playback bar
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildFloatingPlaybackBar(),
            ),
            
            if (_isInitialLoading)
              Positioned.fill(
                child: Container(
                  color: AppColors.sequencerPageBackground.withOpacity(0.8),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.sequencerAccent),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildCommonHeader(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.sequencerSurfaceBase,
      foregroundColor: AppColors.sequencerText,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: AppColors.sequencerText),
        onPressed: () async {
            debugPrint('🔙 [SEQUENCER] Back button pressed');
            
            if (_playbackState.isPlaying) {
              _playbackState.stop();
            }
            // Stop audio player (for render playback from thread view)
            try {
              context.read<AudioPlayerState>().stop();
            } catch (_) {}
            
            // Force auto-save before leaving sequencer
            try {
              debugPrint('💾 [SEQUENCER] Calling forceAutoSave()...');
              await context.read<ThreadsState>().forceAutoSave();
              debugPrint('✅ [SEQUENCER] forceAutoSave() completed');
            } catch (e) {
              debugPrint('⚠️ [SEQUENCER] Failed to auto-save before exit: $e');
            }
            
            // Draft saving disabled - only manual checkpoints are saved
            // _draftService.saveDraft();
            debugPrint('🚪 [SEQUENCER] Calling Navigator.pop()');
            Navigator.of(context).pop();
          },
        iconSize: 20,
      ),
      title: const SizedBox.shrink(),
      actions: [
        // Participants widget (shows if thread has other users) - LEFT of settings
        Consumer<ThreadsState>(
          builder: (context, threadsState, _) {
            final thread = threadsState.activeThread;
            if (thread != null && thread.users.length > 1) {
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: ParticipantsWidget(
                  thread: thread,
                  onTap: () => _showParticipantsMenu(context, thread),
                ),
              );
            }
            return const SizedBox.shrink();
          },
        ),
        
        // Settings button (always visible)
        IconButton(
          icon: Icon(Icons.settings, color: AppColors.sequencerAccent),
          onPressed: () => _navigateToSettings(context),
          iconSize: 18,
          padding: const EdgeInsets.all(2),
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
        ),
        const SizedBox(width: 4),
        
        // Invite button (always visible)
        IconButton(
          icon: Icon(Icons.ios_share , color: AppColors.sequencerAccent),
          onPressed: () => _showInviteCollaboratorsModal(context),
          iconSize: 18,
          padding: const EdgeInsets.all(2),
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
        ),
        const SizedBox(width: 4),
        
        // View toggle buttons (always visible)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: ToggleButtons(
            isSelected: [
              _currentView == _SequencerView.thread,
              _currentView == _SequencerView.sequencer,
            ],
            onPressed: (index) {
              if (index == 0) {
                _switchView(_SequencerView.thread);
              } else {
                _switchView(_SequencerView.sequencer);
              }
            },
            borderRadius: BorderRadius.circular(3),
            constraints: const BoxConstraints(minHeight: 36, minWidth: 50),
            fillColor: AppColors.sequencerPrimaryButton,
            selectedColor: Colors.white,
            color: AppColors.sequencerLightText,
            borderColor: AppColors.sequencerBorder,
            selectedBorderColor: AppColors.sequencerBorder,
            borderWidth: 0.5,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            children: [
              // Thread view icon with unread badge
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: _buildThreadIconWithBadge(),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.my_library_music_rounded, size: 18),
              ),
            ],
          ),
          ),
      ],
    );
  }
  
  /// Build thread view icon with unread message badge
  Widget _buildThreadIconWithBadge() {
    return Consumer<ThreadsState>(
      builder: (context, threadsState, child) {
        final unreadCount = threadsState.unreadMessageCount;
        final iconColor = _currentView == _SequencerView.thread 
            ? Colors.white 
            : AppColors.sequencerLightText;
        
        // No badge if no unread messages
        if (unreadCount == 0) {
          return AppIcons.buildThreadViewIcon(
            size: 18,
            color: iconColor,
          );
        }
        
        // Show badge with unread count
        return Stack(
          clipBehavior: Clip.none,
          children: [
            AppIcons.buildThreadViewIcon(
              size: 18,
              color: iconColor,
            ),
            Positioned(
              right: -8,
              top: -6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.sequencerAccent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.sequencerPageBackground,
                    width: 1,
                  ),
                ),
                constraints: const BoxConstraints(
                  minWidth: 16,
                  minHeight: 16,
                ),
                child: Center(
                  child: Text(
                    unreadCount > 99 ? '99+' : '$unreadCount',
                    style: GoogleFonts.sourceSans3(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSequencerView() {
    return Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  Expanded(
                    flex: 7,
                    child: RepaintBoundary(
                      child: const v2.SampleBanksWidget(),
                    ),
                  ),
                  Expanded(
                flex: 50,
                    child: const SequencerBody(),
                  ),
                  Expanded(
                    flex: 8,
                    child: RepaintBoundary(
                      child: const v2.EditButtonsWidget(),
                    ),
                  ),
                  Expanded(
                flex: 15,
                    child: RepaintBoundary(
                      child: const v2.MultitaskPanelWidget(),
                    ),
                  ),
              const SizedBox(height: 44), // Space for floating playback bar
                ],
              ),
            ),
        // Value overlay
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final h = constraints.maxHeight;
                  const double playbackControl = 44.0;
              const int flexTotal = 7 + 50 + 8 + 15;
                  final double flexRegion = h - playbackControl;
                  final double topInset = flexRegion * (7.0 / flexTotal);
              final double bottomInset = (flexRegion * (15.0 / flexTotal)) + playbackControl;
                  return Padding(
                    padding: EdgeInsets.only(top: topInset, bottom: bottomInset),
                    child: const ValueControlOverlay(),
                  );
                },
              ),
            ),
      ],
    );
  }

  Widget _buildThreadView() {
    return ThreadViewWidget(
      scrollController: _threadScrollController,
      isLoadingOlderMessages: _isLoadingOlderMessages,
      onShowMessageContextMenu: _showMessageContextMenu,
      onApplyMessage: _applyMessage,
      onAddToLibrary: _showAddToLibraryDialog,
    );
  }

  Widget _buildFloatingPlaybackBar() {
    return SafeArea(
      top: false,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.sequencerSurfaceRaised,
          border: Border(
            top: BorderSide(color: AppColors.sequencerBorder, width: 0.5),
          ),
        ),
        child: Consumer4<TableState, PlaybackState, RecordingState, MultitaskPanelState>(
          builder: (context, tableState, playbackState, recordingState, multitaskPanelState, child) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final barHeight = constraints.maxHeight;
                final double innerVerticalMargin = 6;
                final double innerHorizontalMargin = 8;
                final double innerHeight = (barHeight - innerVerticalMargin * 2).clamp(0, double.infinity);

                return Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: innerHorizontalMargin,
                    vertical: innerVerticalMargin,
                  ),
                  child: Container(
                    height: innerHeight,
                    decoration: BoxDecoration(
                      color: AppColors.sequencerSurfaceRaised,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.sequencerBorder, width: 0.5),
                    ),
                    child: LayoutBuilder(
                      builder: (context, rowConstraints) {
                        final totalWidth = rowConstraints.maxWidth;
                        const gap = 8.0;
                        final double chainFraction = _currentView == _SequencerView.thread ? 0.8 : 0.4;
                        final double buttonsFraction = 1 - chainFraction;
                        final double chainWidth = (totalWidth - gap) * chainFraction;
                        final double buttonsWidth = (totalWidth - gap) * buttonsFraction;
                        return Row(
                          children: [
                            // Left side: Section chain (animated width)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                              width: chainWidth,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 10),
                                child: Center(
                                  child: SizedBox(
                                    height: innerHeight - 8,
                                    child: ValueListenableBuilder<bool>(
                                      valueListenable: recordingState.isRecordingNotifier,
                                      builder: (context, isRecording, _) {
                                        return Stack(
                                          children: [
                                            // Section chain (conversion happens in thread view now)
                                            // Make clickable to toggle section management
                                            GestureDetector(
                                              onTap: isRecording ? null : () {
                                                final multitaskPanelState = context.read<MultitaskPanelState>();
                                                if (multitaskPanelState.currentMode == MultitaskPanelMode.sectionManagement) {
                                                  multitaskPanelState.showPlaceholder();
                                                } else {
                                                  multitaskPanelState.showSectionManagement();
                                                }
                                              },
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  color: AppColors.sequencerSurfaceBase,
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(color: AppColors.sequencerBorder, width: 0.5),
                                                ),
                                                clipBehavior: Clip.hardEdge,
                                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                                child: Center(
                                                  child: _buildSectionChain(
                                                    tableState.sectionsCount,
                                                    playbackState,
                                                    allActive: _currentView == _SequencerView.thread,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            // Dark overlay when recording
                                            if (isRecording)
                                              Positioned.fill(
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    color: AppColors.sequencerSurfaceBase.withOpacity(0.9),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                ),
                                              ),
                                            // Recording timer on top
                                            if (isRecording)
                                              Positioned.fill(
                                                child: Center(
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: Colors.transparent,
                                                      borderRadius: BorderRadius.circular(8),
                                                      border: Border.all(color: AppColors.sequencerLightText, width: 1),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        _RecordingIndicatorDot(color: AppColors.sequencerLightText),
                                                        const SizedBox(width: 4),
                                                        ValueListenableBuilder<Duration>(
                                                          valueListenable: recordingState.recordingDurationNotifier,
                                                          builder: (context, duration, __) {
                                                            final minutes = duration.inMinutes;
                                                            final seconds = duration.inSeconds % 60;
                                                            final text = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
                                                            return Text(
                                                              text,
                                                              style: TextStyle(
                                                                color: const Color.fromARGB(255, 231, 229, 226),
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
                                                ),
                                              ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: gap),
                            // Right side: Buttons or Save (animated width)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                              width: buttonsWidth,
                              child: SizedBox(
                                height: innerHeight - 8,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: AppColors.sequencerSurfaceBase,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  clipBehavior: Clip.hardEdge,
                                  child: _currentView != _SequencerView.thread
                                      ? ValueListenableBuilder<bool>(
                                          valueListenable: recordingState.isRecordingNotifier,
                                          builder: (context, isRecording, _) {
                                            return ValueListenableBuilder<bool>(
                                              valueListenable: playbackState.isPlayingNotifier,
                                              builder: (context, isPlaying, __) {
                                                return LayoutBuilder(
                                                  builder: (context, box) {
                                                    final double perButtonWidth = box.maxWidth / 3;
                                                    final double perButtonHeight = box.maxHeight;
                                                    return ToggleButtons(
                                                      isSelected: [
                                                        false, // Never show background selection for master button
                                                        isRecording,
                                                        isPlaying,
                                                      ],
                                                      onPressed: (index) async {
                                                        if (index == 0) {
                                                          // Master settings button - toggle
                                                          Log.d('Master settings button pressed', 'SEQUENCER_V2');
                                                          if (multitaskPanelState.currentMode == MultitaskPanelMode.masterSettings) {
                                                            multitaskPanelState.showPlaceholder();
                                                          } else {
                                                            multitaskPanelState.showMasterSettings();
                                                          }
                                                        } else if (index == 1) {
                                                          if (isRecording) {
                                                            await recordingState.stopRecording();
                                                          } else {
                                                            await recordingState.startRecording();
                                                          }
                                                        } else if (index == 2) {
                                                          if (isPlaying) {
                                                            playbackState.stop();
                                                          } else {
                                                            playbackState.start();
                                                          }
                                                        }
                                                      },
                                                      borderRadius: BorderRadius.circular(4),
                                                      constraints: BoxConstraints.tightFor(width: perButtonWidth, height: perButtonHeight),
                                                      fillColor: AppColors.sequencerPrimaryButton,
                                                      selectedColor: Colors.white,
                                                      color: AppColors.sequencerLightText,
                                                      renderBorder: false,
                                                      splashColor: Colors.transparent,
                                                      highlightColor: Colors.transparent,
                                                      children: [
                                                        Transform.rotate(
                                                          angle: 1.5708, // 90 degrees in radians (π/2)
                                                          child: Icon(
                                                            Icons.tune, 
                                                            size: 18,
                                                            color: multitaskPanelState.currentMode == MultitaskPanelMode.masterSettings
                                                                ? Colors.white // Brighter when active
                                                                : AppColors.sequencerLightText, // Normal color
                                                          ),
                                                        ),
                                                        const Icon(Icons.fiber_manual_record, size: 18),
                                                        Icon(isPlaying ? Icons.stop : Icons.play_arrow, size: 18),
                                                      ],
                                                    );
                                                  },
                                                );
                                              },
                                            );
                                          },
                                        )
                                      : _buildSaveButton(),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionChain(int numSections, PlaybackState playbackState, {bool allActive = false}) {
    return ValueListenableBuilder<int>(
      valueListenable: playbackState.currentSectionNotifier,
      builder: (context, currentSection, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            const double squareWidth = 15.0;
            const double horizontalMargin = 4.0;
            const double totalSquareWidth = squareWidth + horizontalMargin;
            
            final double availableWidth = constraints.maxWidth;
            final int rawVisible = (availableWidth / totalSquareWidth).floor();
            final int visibleCount = rawVisible > 0 ? rawVisible : 1;
            
            // In thread view (allActive), center all sections as a group
            // In sequencer view, center around current section
            final int startIndex;
            if (allActive) {
              // Center the entire group: start from middle of all sections minus half of visible count
              final int centerOfAllSections = numSections ~/ 2;
              final int centerIndexWithinView = visibleCount ~/ 2;
              startIndex = centerOfAllSections - centerIndexWithinView;
            } else {
              // Sequencer view: center around current section
              final int centerIndexWithinView = visibleCount ~/ 2;
              startIndex = currentSection - centerIndexWithinView;
            }
            
            return ClipRect(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(visibleCount, (visibleIndex) {
                  final actualIndex = startIndex + visibleIndex;
                  if (actualIndex < 0 || actualIndex >= numSections) {
                    // Placeholder to keep sections centered
                    return Container(
                      width: squareWidth,
                      height: 15,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    );
                  }
                  final bool isCurrentSection = allActive || actualIndex == currentSection;
                  return Container(
                    width: squareWidth,
                    height: 15,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: isCurrentSection
                          ? AppColors.sequencerLightText // match buttons icon color
                          : const Color.fromARGB(255, 114, 114, 110), // match inactive section settings button bg
                      borderRadius: BorderRadius.circular(2),
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

  

  Widget _buildSaveButton() {
    return Consumer<ThreadsState>(
      builder: (context, threadsState, _) {
        final activeThread = threadsState.activeThread;
        final isMultiUser = (activeThread?.users.length ?? 0) > 1;
        final buttonText = isMultiUser ? 'Send' : 'Save';
        
        return LayoutBuilder(
          builder: (context, constraints) {
            final h = constraints.maxHeight;
            final vPad = (h * 0.18).clamp(6.0, 14.0);
            final borderRadius = 4.0;
            return ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 0),
              child: SizedBox.expand(
                child: ElevatedButton(
                  onPressed: () => _saveCheckpoint(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.sequencerAccent,
                    foregroundColor: AppColors.sequencerText,
                    elevation: 0,
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: vPad),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(borderRadius),
                    ),
                  ),
                  child: Text(
                    buttonText,
                    style: GoogleFonts.sourceSans3(
                      fontSize: (h * 0.35).clamp(10.0, 14.0),
                      fontWeight: FontWeight.w700,
                      color: AppColors.sequencerText,
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

  void _saveCheckpoint(BuildContext context) {
    if (_playbackState.isPlaying) {
      _playbackState.stop();
    }

    final threadsState = context.read<ThreadsState>();
    final activeThread = threadsState.activeThread;
    
    if (activeThread != null) {
      threadsState.sendMessageFromSequencer(threadId: activeThread.id).then((_) {
        // Clear draft when message is successfully saved
        _draftService.clearDraft(activeThread.id);
        // Success: no popup per request
      }).catchError((e) {
        Log.e('Error sending message', 'SEQUENCER_V2', e);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to save checkpoint'),
            backgroundColor: AppColors.sequencerAccent,
            duration: const Duration(seconds: 2),
          ),
          );
        }
      });
    }
  }

  void _onRecordingComplete() {
    Log.i('Recording complete, auto-saving as message...', 'SEQUENCER_V2');
    final threadsState = context.read<ThreadsState>();
    final activeThread = threadsState.activeThread;
    
    if (activeThread != null) {
      threadsState.sendMessageFromSequencer(threadId: activeThread.id).then((_) {
        Log.s('Recording auto-saved successfully', 'SEQUENCER_V2');
        _draftService.clearDraft(activeThread.id);
        
        // Automatically switch to thread view to show the new recording
        if (mounted && _currentView != _SequencerView.thread) {
          Log.d('Auto-switching to thread view', 'SEQUENCER_V2');
          _switchView(_SequencerView.thread);
        }
      }).catchError((e) {
        Log.e('Failed to auto-save recording', 'SEQUENCER_V2', e);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Failed to save recording'),
              backgroundColor: AppColors.sequencerAccent,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      });
    }
  }

  void _navigateToSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SequencerSettingsScreen(),
      ),
    );
  }

  void _showMessageContextMenu(BuildContext context, Message message, Offset globalPos) async {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPos.dx, globalPos.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem<String>(value: 'delete', child: Text('Delete')),
      ],
    );
    if (selected == 'delete') {
      final threadsState = context.read<ThreadsState>();
      final ok = await threadsState.deleteMessage(message.parentThread ?? '', message.id);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to delete message'),
            backgroundColor: AppColors.sequencerAccent,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _applyMessage(BuildContext context, Message message) async {
    final threadsState = context.read<ThreadsState>();
    final thread = threadsState.activeThread;
    
    if (thread == null) {
      Log.w('Cannot apply message - no active thread', 'SEQUENCER_V2');
      return;
    }
    
    // Ensure message has snapshot (fetches from API if needed)
    final snapshot = await threadsState.ensureMessageSnapshot(message);
    
    if (snapshot == null || snapshot.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to load checkpoint'),
          backgroundColor: AppColors.sequencerAccent,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    
    // Use unified loader with fetched snapshot as override
    // This bypasses working state and loads the actual checkpoint
    final ok = await threadsState.loadProjectIntoSequencer(
      thread.id,
      snapshotOverride: snapshot,
    );
    
    if (!mounted) return;
    if (ok) {
      debugPrint('✅ [LOAD_CHECKPOINT] Successfully loaded checkpoint from message ${message.id}');
      // Switch back to sequencer view after loading
      _switchView(_SequencerView.sequencer);
    } else {
      Log.e('Failed to load checkpoint', 'SEQUENCER_V2');
    }
  }

  void _showInviteCollaboratorsModal(BuildContext context) {
    final thread = context.read<ThreadsState>().activeThread;
    if (thread == null) return;
    
    final userState = context.read<UserState>();
    final currentUsername = userState.currentUser?.username ?? '';
    
    // Check if user needs to create a username first
    if (currentUsername.isEmpty) {
      showDialog(
        context: context,
        barrierDismissible: true,
        barrierColor: AppColors.sequencerPageBackground.withOpacity(0.8),
        builder: (context) => UsernameCreationDialog(
          title: 'Create Username',
          message: 'You need to create username before you can share pattern.',
          onSubmit: (username) async {
            // Update username via UserState
            final success = await userState.updateUsername(username);
            if (success) {
              // Close dialog and show invite link
              if (context.mounted) {
                Navigator.pop(context);
                _showInviteLinkDialog(context, thread.id);
              }
            } else {
              throw Exception('Failed to create username. Please try again.');
            }
          },
        ),
      );
    } else {
      // User already has username, show invite link directly
      _showInviteLinkDialog(context, thread.id);
    }
  }

  void _showInviteLinkDialog(BuildContext context, String threadId) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: AppColors.sequencerPageBackground.withOpacity(0.8),
      builder: (context) => _InviteLinkDialog(threadId: threadId),
    );
  }

  void _showAddToLibraryDialog(BuildContext context, Render render) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: AppColors.sequencerPageBackground.withOpacity(0.8),
      builder: (context) => _AddToLibraryDialog(render: render),
    );
  }

  void _showParticipantsMenu(BuildContext context, Thread thread) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: AppColors.sequencerPageBackground.withOpacity(0.8),
      builder: (context) => ParticipantsMenuDialog(thread: thread),
    );
  }

}

class _InviteLinkDialog extends StatelessWidget {
  final String threadId;

  const _InviteLinkDialog({required this.threadId});

  @override
  Widget build(BuildContext context) {
    final inviteLink = '${ApiHttpClient.publicBaseUrl}/join/$threadId';

    final size = MediaQuery.of(context).size;
    final dialogWidth = (size.width * 0.8).clamp(280.0, size.width);
    final dialogHeight = (size.height * 0.42).clamp(240.0, size.height);

    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints.tightFor(width: dialogWidth, height: dialogHeight),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.sequencerSurfaceRaised,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.sequencerBorder, width: 0.5),
            ),
            clipBehavior: Clip.hardEdge,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Share',
                          style: GoogleFonts.sourceSans3(
                            color: AppColors.sequencerText,
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: Icon(Icons.close, color: AppColors.sequencerLightText, size: 28),
                          splashRadius: 22,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Anyone with this link can join',
                      textAlign: TextAlign.left,
                      style: GoogleFonts.sourceSans3(
                        color: AppColors.sequencerLightText,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.sequencerSurfaceBase,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.sequencerBorder, width: 0.5),
                      ),
                      child: SelectableText(
                        inviteLink,
                        textAlign: TextAlign.left,
                        style: GoogleFonts.sourceCodePro(
                          color: AppColors.sequencerText,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.copy, size: 16),
                            label: const Text('Copy Link'),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: inviteLink));
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.sequencerText,
                              side: BorderSide(color: AppColors.sequencerBorder, width: 0.5),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              minimumSize: const Size(0, 44),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
        ),
      ),
    );
  }
}

// Dialog for adding track to library
class _AddToLibraryDialog extends StatefulWidget {
  final Render render;

  const _AddToLibraryDialog({required this.render});

  @override
  State<_AddToLibraryDialog> createState() => _AddToLibraryDialogState();
}

class _AddToLibraryDialogState extends State<_AddToLibraryDialog> {
  final TextEditingController _trackNameController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _trackNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final dialogWidth = (size.width * 0.85).clamp(280.0, size.width);
    
    // Use flexible max height that accounts for keyboard
    final availableHeight = size.height - keyboardHeight;
    final dialogMaxHeight = (availableHeight * 0.35).clamp(220.0, availableHeight - 40);

    return Material(
      type: MaterialType.transparency,
      child: AnimatedPadding(
        // Add padding from bottom to push dialog up when keyboard appears
        padding: EdgeInsets.only(bottom: keyboardHeight),
        duration: const Duration(milliseconds: 100),
        child: Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            // Use maxHeight instead of tightFor to allow flexible height
            constraints: BoxConstraints(
              maxWidth: dialogWidth,
              minWidth: dialogWidth,
              maxHeight: dialogMaxHeight,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.sequencerSurfaceRaised,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.sequencerBorder, width: 0.5),
              ),
              clipBehavior: Clip.hardEdge,
              child: SafeArea(
                child: SingleChildScrollView(
                  // Allow scrolling when keyboard appears
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Add track to the library?',
                              style: GoogleFonts.sourceSans3(
                                color: AppColors.sequencerText,
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: Icon(Icons.close, color: AppColors.sequencerLightText, size: 24),
                              splashRadius: 20,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _trackNameController,
                          autofocus: true,
                          style: GoogleFonts.sourceSans3(
                            color: AppColors.sequencerText,
                            fontSize: 15,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Enter track name',
                            hintStyle: GoogleFonts.sourceSans3(
                              color: AppColors.sequencerLightText.withOpacity(0.5),
                              fontSize: 15,
                            ),
                            filled: true,
                            fillColor: AppColors.sequencerSurfaceBase,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(color: AppColors.sequencerBorder, width: 0.5),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(color: AppColors.sequencerBorder, width: 0.5),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(color: AppColors.sequencerAccent, width: 1),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                          onSubmitted: (_) => _handleSubmit(),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.sequencerText,
                                  side: BorderSide(color: AppColors.sequencerBorder, width: 0.5),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  minimumSize: const Size(0, 48),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _isSubmitting ? null : _handleSubmit,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.sequencerAccent,
                                  foregroundColor: AppColors.sequencerText,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  minimumSize: const Size(0, 48),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  elevation: 0,
                                ),
                                child: _isSubmitting
                                    ? SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          color: AppColors.sequencerText,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Add', style: TextStyle(fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleSubmit() async {
    final trackName = _trackNameController.text.trim();
    if (trackName.isEmpty) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      // Get user ID
      final userState = context.read<UserState>();
      final userId = userState.currentUser?.id;
      
      if (userId == null) {
        if (mounted) {
          setState(() {
            _isSubmitting = false;
          });
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please log in to add to library'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }
      
      Log.d('Track: $trackName', 'LIBRARY');
      Log.d('Render ID: "${widget.render.id}"', 'LIBRARY');
      Log.d('Render URL: ${widget.render.url}', 'LIBRARY');
      
      // Check for empty ID issue
      if (widget.render.id.isEmpty) {
        Log.w('Render has EMPTY ID! Cannot add to library properly. This will cause all tracks to be highlighted when playing.', 'LIBRARY');
      }
      
      // Add to library using LibraryState
      final libraryState = context.read<LibraryState>();
      final success = await libraryState.addToPlaylist(
        userId: userId,
        render: widget.render,
        customName: trackName,
      );
      
      if (!mounted) return;
      
      Navigator.of(context).pop();
      
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Track "$trackName" added to library'),
            backgroundColor: AppColors.sequencerAccent,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to add to library'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      Log.e('Error adding to library', 'LIBRARY', e);
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to add to library'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }
}

// Helper widget for pulsing recording indicator
class _RecordingIndicatorDot extends StatefulWidget {
  final Color? color;
  const _RecordingIndicatorDot({this.color});
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
            color: (widget.color ?? AppColors.sequencerAccent).withOpacity(_animation.value),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}

