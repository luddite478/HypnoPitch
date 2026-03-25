import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../widgets/sequencer/v2/edit_buttons_widget.dart' as v2;
import '../widgets/sequencer/v2/top_multitask_panel_widget.dart' as v2;
import '../widgets/sequencer/v2/sequencer_body.dart';
import '../widgets/sequencer/v2/value_control_overlay.dart';
import '../widgets/pattern_recordings_overlay.dart';
import '../state/patterns_state.dart';
import '../state/audio_player_state.dart';
import '../utils/app_colors.dart';
import '../utils/log.dart';
// Sequencer state imports
import '../state/sequencer/table.dart';
import '../state/sequencer/playback.dart';
import '../state/sequencer/sample_bank.dart';
import '../state/sequencer/sample_browser.dart';
import '../state/sequencer/timer.dart';
import '../state/sequencer/multitask_panel.dart';
import '../state/sequencer/sound_settings.dart';
import '../state/sequencer/recording.dart';
import '../state/sequencer/microphone.dart';
import '../state/sequencer/edit.dart';
import '../state/sequencer/section_settings.dart';
import '../state/sequencer/slider_overlay.dart';
import '../state/sequencer/undo_redo.dart';
import '../state/sequencer/ui_selection.dart';
import '../state/sequencer/recording_waveform.dart';
import 'sequencer_settings_screen.dart';
import '../services/snapshot/snapshot_service.dart';
import '../services/cache/working_state_cache_service.dart';
import '../state/app_state.dart';

class SequencerScreenV2 extends StatefulWidget {
  final Map<String, dynamic>? initialSnapshot;

  const SequencerScreenV2({super.key, this.initialSnapshot});

  @override
  State<SequencerScreenV2> createState() => _SequencerScreenV2State();
}

class _SequencerScreenV2State extends State<SequencerScreenV2> with TickerProviderStateMixin, WidgetsBindingObserver {
  static const double _floatingPlaybackBarHeight = 66.0;
  // Layout flexes:
  // - Edit buttons and multitask panel are each reduced by 10%
  // - Freed space is reassigned to the sequencer body above
  static const int _sequencerBodyFlex = 523; // 500 + (8*0.1 + 15*0.1)*10
  static const int _editButtonsFlex = 72; // 8 * 0.9 * 10
  static const int _multitaskPanelFlex = 135; // 15 * 0.9 * 10
  static const int _contentFlexTotal = _sequencerBodyFlex + _editButtonsFlex + _multitaskPanelFlex;

  // Sequencer state instances
  late final TableState _tableState;
  late final PlaybackState _playbackState;
  late final SampleBankState _sampleBankState;
  late final SampleBrowserState _sampleBrowserState;
  late final TimerState _timerState;
  late final MultitaskPanelState _multitaskPanelState;
  late final SoundSettingsState _soundSettingsState;
  late final RecordingState _recordingState;
  late final MicrophoneState _microphoneState;
  late final RecordingWaveformState _recordingWaveformState;
  late final EditState _editState;
  late final UiSelectionState _uiSelectionState;
  late final SectionSettingsState _sectionSettingsState;
  late final SliderOverlayState _sliderOverlayState;
  late final UndoRedoState _undoRedoState;
  
  bool _isInitialLoading = false;
  bool _isFinalizingTake = false;
  
  // Auto-save
  Timer? _autoSaveTimer;
  static const _autoSaveDelay = Duration(seconds: 5);
  PatternsState? _patternsStateRef; // Cache reference for dispose
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Initialize sequencer state system (reuse Provider-managed states)
    Log.d('Initializing sequencer state system', 'SEQUENCER_V2');
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
    // Wire up dependencies for auto-loading recorded audio as samples
    _recordingState.setDependencies(
      playbackState: _playbackState,
      tableState: _tableState,
      sampleBankState: _sampleBankState,
    );
    _microphoneState = MicrophoneState();
    _recordingWaveformState = RecordingWaveformState();
    _editState = EditState(_tableState, _uiSelectionState);
    _sectionSettingsState = SectionSettingsState();
    _sliderOverlayState = SliderOverlayState();
    
    // Listen to recording state changes for waveform visualization
    _recordingState.addListener(_onRecordingStateChanged);
    
    // Listen to playback state changes to stop recording when playback stops
    _playbackState.isPlayingNotifier.addListener(_onPlaybackStateChanged);
    
    // Listen to playback loop changes for armed recording boundary detection
    _playbackState.currentSectionLoopNotifier.addListener(_onLoopBoundaryCheck);
    _playbackState.currentStepNotifier.addListener(_onLoopBoundaryCheck);
    
    // Initialize timer with dependencies
    _timerState = TimerState(
      tableState: _tableState,
      playbackState: _playbackState,
      sampleBankState: _sampleBankState,
      undoRedoState: _undoRedoState,
    );
    
    // Cache PatternsState reference for later use (including dispose)
    _patternsStateRef = Provider.of<PatternsState>(context, listen: false);
    
    // Set up auto-save listeners
    _setupAutoSaveListeners();
    
    // Start sequencer
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrapInitialLoad();
    });
  }

  // Auto-save setup
  void _setupAutoSaveListeners() {
    // Listen to table state changes (cell edits, note changes, etc.)
    _tableState.addListener(_onSequencerStateChanged);
    
    // Listen to playback state changes (BPM, sections, etc.)
    _playbackState.addListener(_onSequencerStateChanged);
    
    // Listen to sample bank changes (sample loads/unloads)
    _sampleBankState.addListener(_onSequencerStateChanged);
  }

  // Triggered when any sequencer state changes
  void _onSequencerStateChanged() {
    _maybeAdvanceTutorialByState();

    // Cancel existing timer and schedule new one (debouncing)
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(_autoSaveDelay, () {
      _performAutoSave();
    });
  }

  void _maybeAdvanceTutorialByState() {
    if (!mounted) return;
    final appState = context.read<AppState>();
    if (appState.activeTutorialStep == TutorialStep.sequencerSwipeSectionHint &&
        _tableState.sectionsCount > 1) {
      appState.verifySecondSectionCreated();
    }
  }

  // Perform the actual auto-save
  Future<void> _performAutoSave() async {
    final patternsState = _patternsStateRef;
    if (patternsState == null) return;
    
    final activePattern = patternsState.activePattern;
    if (activePattern == null) return;
    
    try {
      // Export current sequencer state
      final snapshotService = SnapshotService(
        tableState: _tableState,
        playbackState: _playbackState,
        sampleBankState: _sampleBankState,
      );
      
      final snapshotJson = snapshotService.exportToJson(
        name: activePattern.name,
        id: activePattern.id,
      );
      final snapshot = json.decode(snapshotJson) as Map<String, dynamic>;
      
      // Save working state
      await WorkingStateCacheService.saveWorkingState(
        activePattern.id,
        snapshot,
      );
      
      // Update pattern timestamp so it shows as recently modified
      await patternsState.updatePatternTimestamp();
      
      patternsState.cancelAutoSave(); // Reset unsaved changes flag
      
      Log.d('💾 Auto-saved pattern ${activePattern.name}', 'SEQUENCER_V2');
    } catch (e) {
      Log.e('Auto-save failed', 'SEQUENCER_V2', e);
    }
  }

  // Thread management removed in offline transformation

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

  Future<void> _bootstrapInitialLoad() async {
    if (mounted) {
      setState(() {
        _isInitialLoading = true;
      });
    }
    try {
      _timerState.start();
      _sampleBrowserState.initialize();
      
      // Load working state if available (takes priority over initial snapshot)
      final patternsState = _patternsStateRef;
      final activePattern = patternsState?.activePattern;
      
      if (activePattern != null) {
        final workingState = await WorkingStateCacheService.loadWorkingState(activePattern.id);
        if (workingState != null) {
          // Load working state (most recent auto-saved state)
          final service = SnapshotService(
            tableState: _tableState,
            playbackState: _playbackState,
            sampleBankState: _sampleBankState,
          );
          final importSuccess = await service.importFromJson(json.encode(workingState));
          if (!importSuccess || !_isImportedStateViable()) {
            if (widget.initialSnapshot != null) {
              Log.w(
                'Working state import is invalid; falling back to checkpoint snapshot',
                'SEQUENCER_V2',
              );
              await WorkingStateCacheService.clearWorkingState(activePattern.id);
              await _importInitialSnapshotIfAny();
            } else {
              Log.w(
                'Working state import is invalid and no checkpoint fallback exists',
                'SEQUENCER_V2',
              );
            }
          }
          Log.i('✅ Loaded working state for pattern ${activePattern.name}', 'SEQUENCER_V2');
        } else {
          // No working state, load initial snapshot if provided
          await _importInitialSnapshotIfAny();
        }
      } else {
        // No active pattern, just load initial snapshot if provided
        await _importInitialSnapshotIfAny();
      }
      
      // Sequencer ready
      Log.i('Sequencer initialized successfully', 'SEQUENCER_V2');
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

  bool _isImportedStateViable() {
    final usedSlots = <int>{};
    for (int step = 0; step < _tableState.maxSteps; step++) {
      for (int col = 0; col < _tableState.maxCols; col++) {
        final cell = _tableState.readCell(step, col);
        if (cell.sampleSlot >= 0) {
          usedSlots.add(cell.sampleSlot);
        }
      }
    }
    if (usedSlots.isEmpty) {
      return true;
    }
    for (final slot in usedSlots) {
      if (!_sampleBankState.isSlotLoaded(slot)) {
        return false;
      }
    }
    return true;
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

  // Thread view and message loading removed in offline transformation

  // Recording state change handler for waveform visualization
  void _onRecordingStateChanged() {
    if (_recordingState.isRecording) {
      // Only start capture if not already recording (prevent repeated calls)
      if (!_recordingWaveformState.isRecording) {
        _recordingWaveformState.startCapture(
          layer: _tableState.uiSelectedLayer,
          section: _tableState.uiSelectedSection,
          playbackState: _playbackState,
          tableState: _tableState,
          clearExisting: true, // Always clear when starting new recording
        );
        Log.d('Recording started - line/mic capture enabled', 'SEQUENCER_V2');
      }
    } else if (_recordingState.currentRecordingPath != null) {
      _recordingWaveformState.stopCapture();
      Log.d('Recording stopped - line/mic capture stopped', 'SEQUENCER_V2');
    }
  }
  
  // Playback state changed - stop recording if playback stops
  void _onPlaybackStateChanged() {
    final isPlaying = _playbackState.isPlaying;
    
    // If playback stopped and we're recording, stop the recording
    if (!isPlaying && _recordingState.isRecording) {
      Log.d('Playback stopped - stopping recording', 'SEQUENCER_V2');
      _recordingState.stopRecording();
    }
  }
  
  // Loop boundary detection for armed recording
  // Called when currentSectionLoop or currentStep changes
  void _onLoopBoundaryCheck() {
    // Only check if recording is armed
    if (!_recordingState.isArmed) return;
    
    _recordingState.checkLoopBoundary(
      currentSection: _playbackState.currentSection,
      currentSectionLoop: _playbackState.currentSectionLoop,
      currentStep: _playbackState.currentStep,
    );
  }

  @override
  void dispose() {
    Log.d('Disposing sequencer state system', 'SEQUENCER_V2');
    
    // Cancel auto-save timer and force immediate save
    _autoSaveTimer?.cancel();
    _performAutoSave();
    
    // Remove auto-save listeners
    _tableState.removeListener(_onSequencerStateChanged);
    _playbackState.removeListener(_onSequencerStateChanged);
    _sampleBankState.removeListener(_onSequencerStateChanged);
    
    // Remove recording state listener
    _recordingState.removeListener(_onRecordingStateChanged);
    
    // Remove playback state listener
    _playbackState.isPlayingNotifier.removeListener(_onPlaybackStateChanged);
    
    // Remove loop boundary listeners
    _playbackState.currentSectionLoopNotifier.removeListener(_onLoopBoundaryCheck);
    _playbackState.currentStepNotifier.removeListener(_onLoopBoundaryCheck);
    
    try {
      final audioPlayer = context.read<AudioPlayerState>();
      audioPlayer.stop();
    } catch (_) {}
    
    _timerState.dispose();
    _sampleBrowserState.dispose();
    _multitaskPanelState.dispose();
    _soundSettingsState.dispose();
    _recordingState.dispose();
    _microphoneState.dispose();
    _recordingWaveformState.dispose();
    _editState.dispose();
    _sectionSettingsState.dispose();
    _undoRedoState.dispose();
    
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Log.d('App resumed - reconfiguring Bluetooth audio session', 'SEQUENCER_V2');
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // App going to background or being closed - force immediate save
      Log.d('App paused/inactive - forcing auto-save', 'SEQUENCER_V2');
      _autoSaveTimer?.cancel();
      _performAutoSave();
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _tableState),
        ChangeNotifierProvider.value(value: _playbackState),
        ChangeNotifierProvider.value(value: _sampleBankState),
        ChangeNotifierProvider.value(value: _sampleBrowserState),
        ChangeNotifierProvider.value(value: _multitaskPanelState),
        ChangeNotifierProvider.value(value: _soundSettingsState),
        ChangeNotifierProvider.value(value: _recordingState),
        ChangeNotifierProvider.value(value: _microphoneState),
        ChangeNotifierProvider.value(value: _recordingWaveformState),
        ChangeNotifierProvider.value(value: _editState),
        ChangeNotifierProvider.value(value: _sectionSettingsState),
        ChangeNotifierProvider.value(value: _sliderOverlayState),
        ChangeNotifierProvider.value(value: _undoRedoState),
        ChangeNotifierProvider.value(value: _uiSelectionState),
      ],
      child: Scaffold(
        backgroundColor: AppColors.sequencerPageBackground,
        body: Stack(
          children: [
            // Sequencer view only (thread view removed)
                _buildSequencerView(),
            
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
            if (_isFinalizingTake)
              Positioned.fill(
                child: Container(
                  color: AppColors.sequencerPageBackground.withOpacity(0.65),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: AppColors.sequencerAccent),
                        const SizedBox(height: 12),
                        Text(
                          'Processing take...',
                          style: TextStyle(
                            color: AppColors.sequencerText,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (appState.activeTutorialStep == TutorialStep.sequencerFirstCellHint)
              _SequencerTutorialAnchorOverlay(
                anchorKey: appState.firstCellTutorialKey,
                text: 'Press cell 1/1 in the sample grid',
                centerText: true,
              ),
            if (appState.activeTutorialStep == TutorialStep.sequencerSelectSampleHint)
              _SequencerTutorialAnchorOverlay(
                anchorKey: appState.selectSampleTutorialKey,
                text: 'Select sample for this cell',
              ),
            if (appState.activeTutorialStep == TutorialStep.sequencerCopyPasteHint)
              _SequencerTutorialAnchorOverlay(
                anchorKey: appState.copyButtonTutorialKey,
                text: 'Try to copy and paste the sample cell',
              ),
            if (appState.activeTutorialStep == TutorialStep.sequencerDeleteHint)
              _SequencerTutorialAnchorOverlay(
                anchorKey: appState.deleteButtonTutorialKey,
                text: 'Try to delete the created sample cell',
              ),
            if (appState.activeTutorialStep == TutorialStep.sequencerJumpHint)
              _SequencerTutorialAnchorOverlay(
                anchorKey: appState.jumpButtonTutorialKey,
                text: 'You can set how many cells to jump after pasting a cell.',
              ),
            if (appState.activeTutorialStep == TutorialStep.sequencerJumpValuePasteHint)
              _SequencerTutorialAnchorOverlay(
                anchorKey: appState.jumpButtonTutorialKey,
                text:
                    'Try setting Jump value to 2, copy one cell, then press Paste several times.',
              ),
            if (appState.activeTutorialStep == TutorialStep.sequencerPlayHint)
              _SequencerTutorialAnchorOverlay(
                anchorKey: appState.playButtonTutorialKey,
                text: 'Press play and listen to the sample(s) you loaded.',
              ),
            if (appState.activeTutorialStep == TutorialStep.sequencerStopHint)
              _SequencerTutorialAnchorOverlay(
                anchorKey: appState.playButtonTutorialKey,
                text: 'Playback can be stopped by pressing the stop button.',
              ),
            if (appState.activeTutorialStep == TutorialStep.sequencerLayersHint)
              _SequencerTutorialAnchorOverlay(
                anchorKey: appState.layersRowTutorialKey,
                text:
                    'These are section layers. They all play at the same time. You can arrange samples across them. Selecting a layer opens controls to mute/solo the layer or specific columns.',
                centerInRectKey: appState.sampleGridTutorialKey,
                drawLayerPointers: true,
              ),
            if (appState.activeTutorialStep == TutorialStep.sequencerSelectModeHint)
              _SequencerTutorialAnchorOverlay(
                anchorKey: appState.selectModeButtonTutorialKey,
                text:
                    'Select button allows you to select multiple cells for copy/paste or changing their parameters at once.',
              ),
            if (appState.activeTutorialStep == TutorialStep.sequencerSelectMultipleHint)
              _SequencerTutorialAnchorOverlay(
                anchorKey: appState.sampleGridTutorialKey,
                text: 'Try to select multiple steps.',
                centerText: true,
              ),
            if (appState.activeTutorialStep ==
                TutorialStep.sequencerDisableSelectModeHint)
              _SequencerTutorialAnchorOverlay(
                anchorKey: appState.selectModeButtonTutorialKey,
                text: 'Now disable select mode.',
              ),
            if (appState.activeTutorialStep == TutorialStep.sequencerSwipeSectionHint)
              _SequencerTutorialAnchorOverlay(
                anchorKey: appState.sampleGridTutorialKey,
                text: 'Swipe the sample grid left and create or copy the first section.',
                centerText: true,
              ),
            if (appState.activeTutorialStep == TutorialStep.sequencerPlaybackModesHint)
              _SequencerTutorialAnchorOverlay(
                anchorKey: appState.sectionMenuButtonTutorialKey,
                text:
                    'There are two playback modes: Loop and Song. Use this section control to manage loops and section playback behavior.',
              ),
            if (appState.activeTutorialStep == TutorialStep.sequencerRecordHint)
              _SequencerTutorialAnchorOverlay(
                anchorKey: appState.recordButtonTutorialKey,
                text:
                    'Try adding samples across two sections, then press Record and Play.',
              ),
          ],
        ),
      ),
    );
  }

  
  void _showRecordingsOverlay(BuildContext context, {bool highlightNewest = false}) {
    if (_isFinalizingTake) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Processing take...'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => PatternRecordingsOverlay(highlightNewest: highlightNewest),
    );
  }

  Widget _buildSequencerView() {
    return Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  Expanded(
                flex: _sequencerBodyFlex,
                    child: SequencerBody(
                      onBack: () async {
                        if (_playbackState.isPlaying) _playbackState.stop();
                        try { context.read<AudioPlayerState>().stop(); } catch (_) {}
                        _autoSaveTimer?.cancel();
                        await _performAutoSave();
                        if (context.mounted) Navigator.of(context).pop();
                      },
                      onSettings: () => _navigateToSettings(context),
                      onRecordings: () => _showRecordingsOverlay(context),
                    ),
                  ),
                  Expanded(
                    flex: _editButtonsFlex,
                    child: RepaintBoundary(
                      child: const v2.EditButtonsWidget(),
                    ),
                  ),
                  Expanded(
                flex: _multitaskPanelFlex,
                    child: RepaintBoundary(
                      child: const v2.MultitaskPanelWidget(),
                    ),
                  ),
              const SizedBox(height: _floatingPlaybackBarHeight), // Keep panel stacked above floating playback bar
                ],
              ),
            ),
        // Value overlay
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final h = constraints.maxHeight;
                  const double playbackControl = _floatingPlaybackBarHeight;
                  final double flexRegion = h - playbackControl;
                  final double bottomInset = (flexRegion * (_multitaskPanelFlex / _contentFlexTotal)) + playbackControl;
                  return Padding(
                    padding: EdgeInsets.only(top: 0, bottom: bottomInset),
                    child: const ValueControlOverlay(),
                  );
                },
              ),
            ),
      ],
    );
  }

  // _buildThreadView removed in offline transformation

  Widget _buildFloatingPlaybackBar() {
    return SafeArea(
      top: false,
      child: Container(
        height: _floatingPlaybackBarHeight,
        decoration: BoxDecoration(
          color: AppColors.sequencerSurfaceRaised,
          border: Border(
            top: BorderSide(color: AppColors.sequencerBorder, width: 0.5),
          ),
        ),
        child: Consumer4<TableState, PlaybackState, RecordingState, MultitaskPanelState>(
          builder: (context, tableState, playbackState, recordingState, multitaskPanelState, child) {
            final appState = context.watch<AppState>();
            return LayoutBuilder(
              builder: (context, constraints) {
                final barHeight = constraints.maxHeight;
                final double innerVerticalMargin = 4;
                final double innerHorizontalMargin = 6;
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
                        final double chainFraction = 0.4; // Fixed width (thread view removed)
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
                                                key: appState.activeTutorialStep ==
                                                        TutorialStep.sequencerPlaybackModesHint
                                                    ? appState.sectionMenuButtonTutorialKey
                                                    : null,
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
                                                    allActive: false, // Always false (no thread view)
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
                                  child: ValueListenableBuilder<bool>(
                                          valueListenable: recordingState.isRecordingNotifier,
                                          builder: (context, isRecording, _) {
                                            return ValueListenableBuilder<bool>(
                                              valueListenable: recordingState.isArmedNotifier,
                                              builder: (context, isArmed, __) {
                                                return ValueListenableBuilder<bool>(
                                              valueListenable: playbackState.isPlayingNotifier,
                                              builder: (context, isPlaying, ___) {
                                                // Record button shows active when recording OR armed
                                                final isRecordButtonActive = isRecording || isArmed;
                                                return LayoutBuilder(
                                                  builder: (context, box) {
                                                    final double perButtonWidth = box.maxWidth / 3;
                                                    final double perButtonHeight = box.maxHeight;
                                                    return ToggleButtons(
                                                      isSelected: [
                                                        false, // Never show background selection for master button
                                                        isRecordButtonActive,
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
                                                          if (isRecording || isArmed) {
                                                            await recordingState.stopRecording();
                                                          } else {
                                                            final currentLayer = _tableState.uiSelectedLayer;
                                                            await recordingState.startRecording(layer: currentLayer);
                                                          }
                                                        } else if (index == 2) {
                                                          if (isPlaying) {
                                                            playbackState.stop();
                                                            appState.markStopAction();
                                                          } else {
                                                            playbackState.start();
                                                            appState.markPlayAction();
                                                          }
                                                        }
                                                      },
                                                      borderRadius: BorderRadius.circular(2),
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
                                                            size: 20,
                                                            color: multitaskPanelState.currentMode == MultitaskPanelMode.masterSettings
                                                                ? Colors.white // Brighter when active
                                                                : AppColors.sequencerLightText, // Normal color
                                                          ),
                                                        ),
                                                        KeyedSubtree(
                                                          key: appState.activeTutorialStep ==
                                                                  TutorialStep.sequencerRecordHint
                                                              ? appState.recordButtonTutorialKey
                                                              : null,
                                                          child: const Icon(Icons.circle, size: 14),
                                                        ),
                                                        KeyedSubtree(
                                                          key: appState.activeTutorialStep ==
                                                                  TutorialStep.sequencerPlayHint
                                                              ? appState.playButtonTutorialKey
                                                              : null,
                                                          child: Icon(
                                                            isPlaying ? Icons.stop : Icons.play_arrow,
                                                            size: 20,
                                                          ),
                                                        ),
                                                      ],
                                                    );
                                                  },
                                                );
                                              },
                                            );
                                              },
                                            );
                                          },
                                        ),
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

  

  Future<void> _onRecordingComplete() async {
    Log.i('Recording complete, saving and showing recordings overlay...', 'SEQUENCER_V2');
    
    // Stop pattern playback automatically when a take is recorded.
    if (_playbackState.isPlaying) {
      _playbackState.stop();
    }
    
    // Get recording info from recording state
    final wavPath = _recordingState.currentRecordingPath;
    final duration = _recordingState.recordingDuration;
    
    if (wavPath == null) {
      Log.e('Recording complete but no file path', 'SEQUENCER_V2');
      return;
    }
    
    if (mounted) {
      setState(() {
        _isFinalizingTake = true;
      });
    }

    try {
      // Wait for MP3 conversion to complete (it happens automatically in background)
      // Get the MP3 path (will convert if not already done)
      final mp3Path = await _recordingState.ensureMp3Ready(bitrateKbps: 320);
      
      if (mp3Path == null) {
        Log.e('Failed to get MP3 path after recording', 'SEQUENCER_V2');
        return;
      }
      
      // Verify MP3 file is actually written and readable (retry up to 10 times with 100ms delay)
      bool fileReady = false;
      for (int attempt = 0; attempt < 10; attempt++) {
        final mp3File = File(mp3Path);
        if (await mp3File.exists()) {
          try {
            // Try to read file size to ensure it's not corrupt/still being written
            final size = await mp3File.length();
            if (size > 0) {
              fileReady = true;
              Log.d('MP3 file ready (${size} bytes) after ${attempt + 1} attempts', 'SEQUENCER_V2');
              break;
            }
          } catch (e) {
            Log.d('MP3 file not readable yet (attempt ${attempt + 1})', 'SEQUENCER_V2');
          }
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }
      
      if (!fileReady) {
        Log.e('MP3 file not ready after waiting', 'SEQUENCER_V2');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Recording saved but audio file not ready. Please wait a moment.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }
      
      // Export current sequencer state
      final snapshotService = SnapshotService(
        tableState: _tableState,
        playbackState: _playbackState,
        sampleBankState: _sampleBankState,
      );
      
      final patternsState = _patternsStateRef;
      if (patternsState == null) {
        Log.e('Patterns state unavailable for checkpoint save', 'SEQUENCER_V2');
        return;
      }
      final activePattern = patternsState.activePattern;

      if (activePattern == null) {
        Log.e('No active pattern available for checkpoint save', 'SEQUENCER_V2');
        return;
      }

      final snapshotJson = snapshotService.exportToJson(
        name: activePattern.name,
        id: activePattern.id,
      );
      final snapshot = json.decode(snapshotJson) as Map<String, dynamic>;

      // Save checkpoint with audio (use MP3 path)
      final checkpoint = await patternsState.saveCheckpoint(
        snapshot: snapshot,
        snapshotMetadata: {'source': 'recording'},
        audioFilePath: mp3Path,  // Use MP3 path instead of WAV
        audioDuration: duration.inMilliseconds / 1000.0,
      );

      if (checkpoint == null) {
        Log.e('Checkpoint save returned null', 'SEQUENCER_V2');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to save take. Please try again.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      Log.d('Checkpoint saved successfully with audio: $mp3Path', 'SEQUENCER_V2');

      // Show recordings overlay with highlight for new recording
      if (mounted) {
        setState(() {
          _isFinalizingTake = false;
        });
        _showRecordingsOverlay(context, highlightNewest: true);
      }
    } catch (e) {
      Log.e('Failed to save recording checkpoint', 'SEQUENCER_V2', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save recording: $e'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isFinalizingTake = false;
        });
      }
    }
  }

  void _navigateToSettings(BuildContext context) {
    // Pass existing providers to settings screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChangeNotifierProvider.value(
          value: _microphoneState,
          child: const SequencerSettingsScreen(),
        ),
      ),
    );
  }

  // Thread-related methods and collaboration dialogs removed in offline transformation
}

/// Coach-mark overlay that waits until [anchorKey] is laid out (grid may build after first frame).
class _SequencerTutorialAnchorOverlay extends StatefulWidget {
  final GlobalKey anchorKey;
  final String text;
  final bool centerText;
  final GlobalKey? centerInRectKey;
  final bool drawLayerPointers;

  const _SequencerTutorialAnchorOverlay({
    required this.anchorKey,
    required this.text,
    this.centerText = false,
    this.centerInRectKey,
    this.drawLayerPointers = false,
  });

  @override
  State<_SequencerTutorialAnchorOverlay> createState() =>
      _SequencerTutorialAnchorOverlayState();
}

class _SequencerTutorialAnchorOverlayState
    extends State<_SequencerTutorialAnchorOverlay> {
  int _layoutTick = 0;
  static const int _maxLayoutWaits = 48;

  @override
  void didUpdateWidget(covariant _SequencerTutorialAnchorOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.anchorKey != widget.anchorKey) {
      _layoutTick = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = Size(constraints.maxWidth, constraints.maxHeight);
          final anchorRect = _tutorialResolveAnchorRect(widget.anchorKey, viewport);
          if (anchorRect == null) {
            if (_layoutTick < _maxLayoutWaits) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                setState(() => _layoutTick++);
              });
            }
            return IgnorePointer(
              child: Container(color: Colors.black.withOpacity(0.06)),
            );
          }

          final safeTop = MediaQuery.of(context).padding.top + 10;
          final centerRect = _tutorialResolveAnchorRect(
                widget.centerInRectKey ?? appState.sampleGridTutorialKey,
                viewport,
              ) ??
              Rect.fromCenter(
                center: Offset(viewport.width / 2, viewport.height / 2),
                width: viewport.width,
                height: viewport.height,
              );
          final textWidth =
              (viewport.width * 0.56).clamp(180.0, 300.0).toDouble();
          final desiredLeft = centerRect.center.dx - textWidth / 2;
          final textLeft =
              desiredLeft.clamp(12.0, viewport.width - textWidth - 12.0).toDouble();
          const cardHeightEstimate = 126.0;
          final desiredTop = centerRect.center.dy - (cardHeightEstimate / 2);
          final textTop = desiredTop
              .clamp(safeTop, viewport.height - 120.0)
              .toDouble();
          final textCenter = Offset(textLeft + (textWidth / 2), textTop + (cardHeightEstimate / 2));
          final arrowEnd = _tutorialResolveArrowTarget(
            from: textCenter,
            targetRect: anchorRect,
            edgePadding: 4,
          );

          return Stack(
            children: [
              IgnorePointer(
                child: Container(color: Colors.black.withOpacity(0.1)),
              ),
              if (!widget.drawLayerPointers)
                IgnorePointer(
                  child: CustomPaint(
                    size: viewport,
                    painter: _TutorialOverlayArrowPainter(
                      start: textCenter,
                      end: arrowEnd,
                      color: AppColors.sequencerAccent,
                    ),
                  ),
                ),
              if (widget.drawLayerPointers)
                IgnorePointer(
                  child: CustomPaint(
                    size: viewport,
                    painter: _LayerPointersPainter(
                      targetRect: anchorRect,
                      color: AppColors.sequencerAccent,
                      count: 5,
                    ),
                  ),
                ),
              Positioned(
                left: textLeft,
                top: textTop,
                width: textWidth,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.sequencerSurfaceBase.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.sequencerBorder, width: 0.8),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${appState.tutorialStepDisplayIndex}/${AppState.tutorialTotalSteps}',
                            style: const TextStyle(
                              color: AppColors.sequencerText,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: appState.goBackTutorialManually,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.sequencerSurfaceBase,
                              foregroundColor: AppColors.sequencerText,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                              minimumSize: const Size(0, 0),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(7),
                              ),
                            ),
                            child: const Text(
                              'Back',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                            ),
                          ),
                          const SizedBox(width: 6),
                          ElevatedButton(
                            onPressed: appState.advanceTutorialManually,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.sequencerAccent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                              minimumSize: const Size(0, 0),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(7),
                              ),
                            ),
                            child: const Text(
                              'Next',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.text,
                        style: const TextStyle(
                          color: AppColors.sequencerText,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
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
}

Rect? _tutorialResolveAnchorRect(GlobalKey key, Size viewport) {
  final ctx = key.currentContext;
  if (ctx == null) return null;
  final box = ctx.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  final topLeft = box.localToGlobal(Offset.zero);
  return topLeft & box.size;
}

Offset _tutorialResolveArrowTarget({
  required Offset from,
  required Rect targetRect,
  required double edgePadding,
}) {
  final center = targetRect.center;
  final towardsText = from - center;
  if (towardsText.distanceSquared < 0.0001) return center;

  final halfW = targetRect.width / 2;
  final halfH = targetRect.height / 2;
  final scaleX = towardsText.dx.abs() < 0.0001
      ? double.infinity
      : halfW / towardsText.dx.abs();
  final scaleY = towardsText.dy.abs() < 0.0001
      ? double.infinity
      : halfH / towardsText.dy.abs();
  final scale = scaleX < scaleY ? scaleX : scaleY;
  final edgePoint = Offset(
    center.dx + towardsText.dx * scale,
    center.dy + towardsText.dy * scale,
  );
  final toCenter = center - edgePoint;
  final len = toCenter.distance;
  if (len < 0.0001) return edgePoint;
  final inset = edgePadding.clamp(0.0, 12.0).toDouble();
  return Offset(
    edgePoint.dx + (toCenter.dx / len) * inset,
    edgePoint.dy + (toCenter.dy / len) * inset,
  );
}

class _TutorialOverlayArrowPainter extends CustomPainter {
  final Offset start;
  final Offset end;
  final Color color;

  _TutorialOverlayArrowPainter({
    required this.start,
    required this.end,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(start, end, linePaint);

    final direction = (end - start);
    final angle = direction.direction;
    const arrowLength = 10.0;
    const arrowSpread = 0.6;
    final arrowPath = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(
        end.dx - arrowLength * cos(angle - arrowSpread),
        end.dy - arrowLength * sin(angle - arrowSpread),
      )
      ..moveTo(end.dx, end.dy)
      ..lineTo(
        end.dx - arrowLength * cos(angle + arrowSpread),
        end.dy - arrowLength * sin(angle + arrowSpread),
      );
    canvas.drawPath(arrowPath, linePaint);
  }

  @override
  bool shouldRepaint(covariant _TutorialOverlayArrowPainter oldDelegate) {
    return oldDelegate.start != start ||
        oldDelegate.end != end ||
        oldDelegate.color != color;
  }
}

class _LayerPointersPainter extends CustomPainter {
  final Rect targetRect;
  final Color color;
  final int count;

  _LayerPointersPainter({
    required this.targetRect,
    required this.color,
    required this.count,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (count <= 0 || targetRect.width <= 0) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final segmentWidth = targetRect.width / count;
    for (int i = 0; i < count; i++) {
      final x = targetRect.left + segmentWidth * (i + 0.5);
      final start = Offset(x, targetRect.bottom + 18);
      final end = Offset(x, targetRect.bottom + 4);
      canvas.drawLine(start, end, paint);

      const arrowLen = 5.0;
      const spread = 0.6;
      final angle = -pi / 2; // upward
      final arrowPath = Path()
        ..moveTo(end.dx, end.dy)
        ..lineTo(
          end.dx - arrowLen * cos(angle - spread),
          end.dy - arrowLen * sin(angle - spread),
        )
        ..moveTo(end.dx, end.dy)
        ..lineTo(
          end.dx - arrowLen * cos(angle + spread),
          end.dy - arrowLen * sin(angle + spread),
        );
      canvas.drawPath(arrowPath, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LayerPointersPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect ||
        oldDelegate.color != color ||
        oldDelegate.count != count;
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

