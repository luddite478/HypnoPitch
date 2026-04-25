import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import '../widgets/sequencer/v1/edit_buttons_widget.dart' as v1;
import '../widgets/sequencer/v1/top_multitask_panel_widget.dart' as v1;
import '../widgets/sequencer/v1/sequencer_body.dart';
import '../widgets/sequencer/v1/value_control_overlay.dart';
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
import '../state/library_samples_state.dart';
import 'library_screen.dart';
import 'sequencer_settings_screen.dart';
import '../services/snapshot/snapshot_service.dart';
import '../services/snapshot/snapshot_table_validator.dart';
import '../services/cache/working_state_cache_service.dart';
import '../state/app_state.dart';
import '../config/debug_flags.dart';

class SequencerScreenV2 extends StatefulWidget {
  final Map<String, dynamic>? initialSnapshot;

  const SequencerScreenV2({super.key, this.initialSnapshot});

  @override
  State<SequencerScreenV2> createState() => _SequencerScreenV2State();
}

enum _SequencerSaveReason {
  debounce,
  back,
  lifecycle,
  patternSwitch,
  dispose,
  retry,
}

class _SequencerScreenV2State extends State<SequencerScreenV2>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const double _floatingPlaybackBarHeight = 52.8;
  // Layout flexes:
  // - Edit buttons and multitask panel are each reduced by 10%
  // - Freed space is reassigned to the sequencer body above
  static const int _sequencerBodyFlex = 523; // 500 + (8*0.1 + 15*0.1)*10
  static const int _editButtonsFlex = 72; // 8 * 0.9 * 10
  static const int _multitaskPanelFlex = 135; // 15 * 0.9 * 10
  static const int _contentFlexTotal =
      _sequencerBodyFlex + _editButtonsFlex + _multitaskPanelFlex;
  static const double _navDrawerCornerRadius = 6;
  static const double _navDrawerSideActionIconSize = 24;
  /// Fixed slot so Patterns / Library labels share one vertical text start line.
  static const double _navDrawerBottomIconSlotWidth = 40;

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

  // Start covered to avoid one-frame flicker before bootstrap begins.
  bool _isInitialLoading = true;
  bool _isFinalizingTake = false;

  // Auto-save
  Timer? _autoSaveTimer;
  Timer? _saveRetryTimer;
  static const _autoSaveDelay = Duration(seconds: 5);
  static const _saveRetryDelay = Duration(milliseconds: 700);
  static const _maxSaveRetryAttempts = 3;
  static const _leaveSaveSoftTimeout = Duration(milliseconds: 350);
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  PatternsState? _patternsStateRef; // Cache reference for dispose

  /// Draft is always saved under this id for this screen instance (see [_performAutoSave]).
  String? _loadedPatternId;
  bool _bootstrapComplete = false;

  /// After [PatternsState.setActivePattern] flushes this screen's draft, shared table may belong to another pattern.
  bool _suppressAutoSave = false;
  bool _hasPendingChanges = false;
  DateTime? _lastDirtyAt;
  DateTime? _lastSuccessfulSaveAt;
  Future<void> _saveQueue = Future<void>.value();

  int _playbackBarBuildCount = 0;
  List<MissingSampleIssue> _pendingMissingSamples = const [];

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
    _sampleBrowserState = SampleBrowserState(
      librarySamplesState:
          Provider.of<LibrarySamplesState>(context, listen: false),
    );
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
    _patternsStateRef!
        .addBeforeActivePatternSwitchListener(_onBeforeActivePatternSwitch);

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
    _hasPendingChanges = true;
    _lastDirtyAt = DateTime.now();

    // Cancel existing timer and schedule new one (debouncing)
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(_autoSaveDelay, () {
      _requestSave(
        reason: _SequencerSaveReason.debounce,
      );
    });
  }

  void _maybeAdvanceTutorialByState() {
    if (!mounted) return;
    final appState = context.read<AppState>();
    switch (appState.activeTutorialStep) {
      case TutorialStep.sequencerSectionsSwipeHint:
        if (_tableState.sectionsCount > 1) {
          appState.verifySecondSectionCreated();
        }
        break;
      case TutorialStep.sequencerSectionTwoSamplesHint:
        if (_tableState.sectionsCount > 1 &&
            _tableState.countCellsWithSamplesInSection(1) >= 5) {
          appState.verifySectionTwoFiveSamplesStep();
        }
        break;
      case TutorialStep.sequencerSectionTwoStepsHint:
        if (_tableState.sectionsCount > 1) {
          appState.syncSectionTwoStepsHint(
            sectionIndex: 1,
            stepCount: _tableState.getSectionStepCount(1),
            sectionsCount: _tableState.sectionsCount,
          );
        }
        break;
      case TutorialStep.sequencerSectionsNavigateHint:
        if (_tableState.uiSelectedSection == 0) {
          appState.verifyNavigatedToPreviousSectionStep();
        }
        break;
      case TutorialStep.sequencerSongModeHint:
        if (_playbackState.songMode) {
          appState.verifySongModeEnabledStep();
        }
        break;
      case TutorialStep.sequencerSectionLoopsHint:
        final loops = _playbackState.getSectionsLoopsNum();
        if (loops.any((value) => value == 2)) {
          appState.verifyAnySectionLoopSetToTwoStep();
        }
        break;
      default:
        break;
    }
  }

  /// Persists the current shared sequencer state to working storage for [patternId].
  Future<bool> _saveWorkingStateForPatternId(String patternId) async {
    final patternsState = _patternsStateRef;
    if (patternsState == null) return false;

    var patternName = 'Pattern';
    for (final p in patternsState.patterns) {
      if (p.id == patternId) {
        patternName = p.name;
        break;
      }
    }

    final snapshotService = SnapshotService(
      tableState: _tableState,
      playbackState: _playbackState,
      sampleBankState: _sampleBankState,
    );

    final snapshotJson = snapshotService.exportToJson(
      name: patternName,
      id: patternId,
    );
    final snapshot = json.decode(snapshotJson) as Map<String, dynamic>;

    final saved =
        await WorkingStateCacheService.saveWorkingState(patternId, snapshot);
    if (!saved) {
      return false;
    }
    await patternsState.updatePatternTimestampForId(patternId);
    return true;
  }

  Future<void> _onBeforeActivePatternSwitch() async {
    if (!_bootstrapComplete || _loadedPatternId == null || _suppressAutoSave) {
      return;
    }
    final patternsState = _patternsStateRef;
    if (patternsState == null) return;
    if (patternsState.activePattern?.id != _loadedPatternId) return;

    _autoSaveTimer?.cancel();
    try {
      final ok = await _requestSave(
        reason: _SequencerSaveReason.patternSwitch,
        force: true,
        allowBackgroundRetry: true,
      );
      if (ok) {
        Log.d(
          '💾 Flushed draft before pattern switch (${_loadedPatternId!})',
          'SEQUENCER_V2',
        );
      } else {
        Log.w(
          'Pattern switch flush did not complete, retry scheduled',
          'SEQUENCER_V2',
        );
      }
      _suppressAutoSave = true;
    } catch (e) {
      Log.e('Pre-switch flush failed', 'SEQUENCER_V2', e);
    }
  }

  bool _shouldSkipSave({required bool force}) {
    final patternsState = _patternsStateRef;
    if (patternsState == null ||
        _suppressAutoSave ||
        !_bootstrapComplete ||
        _loadedPatternId == null) {
      return true;
    }

    // If global active pattern no longer matches this session, do not write shared
    // table into the wrong pattern file (handled by pre-switch flush + suppress).
    if (patternsState.activePattern?.id != _loadedPatternId) {
      return true;
    }
    if (force) return false;
    if (!_hasPendingChanges) return true;
    final dirtyAt = _lastDirtyAt;
    final savedAt = _lastSuccessfulSaveAt;
    if (dirtyAt != null && savedAt != null && !dirtyAt.isAfter(savedAt)) {
      return true;
    }
    return false;
  }

  String _saveReasonLabel(_SequencerSaveReason reason) {
    switch (reason) {
      case _SequencerSaveReason.debounce:
        return 'debounce';
      case _SequencerSaveReason.back:
        return 'back';
      case _SequencerSaveReason.lifecycle:
        return 'lifecycle';
      case _SequencerSaveReason.patternSwitch:
        return 'pattern_switch';
      case _SequencerSaveReason.dispose:
        return 'dispose';
      case _SequencerSaveReason.retry:
        return 'retry';
    }
  }

  void _scheduleBackgroundSaveRetry({
    required _SequencerSaveReason sourceReason,
    required int attempt,
  }) {
    if (attempt > _maxSaveRetryAttempts) return;
    _saveRetryTimer?.cancel();
    _saveRetryTimer = Timer(_saveRetryDelay, () {
      _requestSave(
        reason: _SequencerSaveReason.retry,
        force: true,
        allowBackgroundRetry: true,
        retryAttempt: attempt,
        retrySourceReason: sourceReason,
      );
    });
  }

  Future<bool> _requestSave({
    required _SequencerSaveReason reason,
    bool force = false,
    bool allowBackgroundRetry = false,
    int retryAttempt = 0,
    _SequencerSaveReason? retrySourceReason,
  }) async {
    final completer = Completer<bool>();
    _saveQueue = _saveQueue.then((_) async {
      if (_shouldSkipSave(force: force)) {
        completer.complete(true);
        return;
      }

      try {
        final ok = await _saveWorkingStateForPatternId(_loadedPatternId!);
        if (ok) {
          _hasPendingChanges = false;
          _lastSuccessfulSaveAt = DateTime.now();
          Log.d(
            '💾 Saved pattern $_loadedPatternId (${_saveReasonLabel(reason)})',
            'SEQUENCER_V2',
          );
          completer.complete(true);
          return;
        }

        final source = retrySourceReason ?? reason;
        if (allowBackgroundRetry && retryAttempt < _maxSaveRetryAttempts) {
          _scheduleBackgroundSaveRetry(
            sourceReason: source,
            attempt: retryAttempt + 1,
          );
        }
        Log.w(
          'Save did not complete (${_saveReasonLabel(reason)}), attempt=$retryAttempt',
          'SEQUENCER_V2',
        );
        completer.complete(false);
      } catch (e) {
        final source = retrySourceReason ?? reason;
        if (allowBackgroundRetry && retryAttempt < _maxSaveRetryAttempts) {
          _scheduleBackgroundSaveRetry(
            sourceReason: source,
            attempt: retryAttempt + 1,
          );
        }
        Log.e('Save failed (${_saveReasonLabel(reason)})', 'SEQUENCER_V2', e);
        completer.complete(false);
      }
    }).catchError((Object e, StackTrace st) {
      Log.e('Save queue failure', 'SEQUENCER_V2', '$e\n$st');
    });

    return completer.future;
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
      final success = await service.importFromJson(json.encode(snapshot));
      if (success) {
        _pendingMissingSamples = service.lastImportReport.missingSamples;
        Log.i('Imported initial snapshot into Sequencer V2', 'SEQUENCER_V2');
      }
    } catch (e) {
      Log.e('Failed to import initial snapshot', 'SEQUENCER_V2', e);
    }
  }

  /// Loads a single latest-state source for [patternId].
  ///
  /// Optional [widget.initialSnapshot] is only used as an explicit snapshot input
  /// (e.g. opening a specific take/revision), not as general checkpoint fallback.
  Future<void> _loadLatestStateForActivePattern({
    required String patternId,
    required String patternName,
  }) async {
    final maxSteps = _tableState.maxSteps;
    final maxCols = _tableState.maxCols;

    final service = SnapshotService(
      tableState: _tableState,
      playbackState: _playbackState,
      sampleBankState: _sampleBankState,
    );

    final envelope =
        await WorkingStateCacheService.loadWorkingStateEnvelope(patternId);
    if (envelope != null) {
      final latestSnapshot = envelope.snapshot;
      if (!SnapshotTableValidator.isValidSnapshotSource(
        latestSnapshot,
        maxSteps: maxSteps,
        maxCols: maxCols,
      )) {
        Log.w(
          'Latest state failed structural validation; clearing file',
          'SEQUENCER_V2',
        );
        await WorkingStateCacheService.clearWorkingState(patternId);
      } else {
        final importSuccess =
            await service.importFromJson(json.encode(latestSnapshot));
        if (importSuccess) {
          _pendingMissingSamples = service.lastImportReport.missingSamples;
          Log.i(
            'Loaded pattern $patternName from latest state',
            'SEQUENCER_V2',
          );
          return;
        }
      }
    }

    final explicitSnapshot = widget.initialSnapshot;
    if (explicitSnapshot != null &&
        SnapshotTableValidator.isValidSnapshotSource(
          explicitSnapshot,
          maxSteps: maxSteps,
          maxCols: maxCols,
        )) {
      final importSuccess =
          await service.importFromJson(json.encode(explicitSnapshot));
      if (importSuccess) {
        _pendingMissingSamples = service.lastImportReport.missingSamples;
        Log.i(
          'Loaded pattern $patternName from explicit snapshot input',
          'SEQUENCER_V2',
        );
        return;
      }
    }

    Log.w(
      'No valid latest state could be imported for $patternName',
      'SEQUENCER_V2',
    );
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

      final patternsState = _patternsStateRef;
      final activePattern = patternsState?.activePattern;

      if (activePattern != null) {
        await _loadLatestStateForActivePattern(
          patternId: activePattern.id,
          patternName: activePattern.name,
        );
      } else {
        await _importInitialSnapshotIfAny();
      }
      // Always enter at section 1 grid (index 0) and keep section-creation closed.
      _tableState.setUiSelectedSection(0);
      _sectionSettingsState.closeSectionCreationOverlay();

      // Sequencer ready
      Log.i('Sequencer initialized successfully', 'SEQUENCER_V2');
    } catch (e) {
      Log.e('Initial sequencer bootstrap failed', 'SEQUENCER_V2', e);
    } finally {
      final ps = _patternsStateRef;
      final active = ps?.activePattern;
      _loadedPatternId = active?.id;
      _bootstrapComplete = true;
      if (mounted) {
        setState(() {
          _isInitialLoading = false;
        });
        if (_pendingMissingSamples.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _showMissingSamplesDialog(_pendingMissingSamples);
          });
        }
      }
    }
  }

  Future<void> _showMissingSamplesDialog(
      List<MissingSampleIssue> initial) async {
    final issues = List<MissingSampleIssue>.from(initial);
    if (issues.isEmpty || !mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> resolveByLocate(MissingSampleIssue issue) async {
              final picked = await FilePicker.platform.pickFiles(
                allowMultiple: false,
                type: FileType.custom,
                allowedExtensions: const [
                  'wav',
                  'mp3',
                  'm4a',
                  'aif',
                  'aiff',
                  'flac',
                  'ogg'
                ],
              );
              final sourcePath = picked?.files.first.path;
              if (sourcePath == null || sourcePath.isEmpty) return;
              if (!mounted) return;
              if (!context.mounted) return;

              try {
                final samples = context.read<LibrarySamplesState>();
                final registration =
                    await samples.registerRecoveredCustomSample(
                  sourcePath: sourcePath,
                );
                if (!mounted) return;
                if (!context.mounted) return;
                if (!registration.success || registration.sampleId == null) {
                  return;
                }
                final loadResult = await _sampleBankState.loadSampleReference(
                  issue.slot,
                  sampleId: registration.sampleId,
                  filePathHint: registration.filePath,
                  displayName: issue.displayName,
                );
                if (loadResult.success) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!dialogContext.mounted) return;
                    setDialogState(() => issues.remove(issue));
                  });
                }
              } catch (_) {}
            }

            void resolveByReplaceFromLibrary(MissingSampleIssue issue) {
              Navigator.of(dialogContext).pop();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _sampleBrowserState.showForSlot(issue.slot);
              });
            }

            if (issues.isEmpty) {
              return AlertDialog(
                backgroundColor: AppColors.sequencerSurfaceRaised,
                title: Text(
                  'Missing Samples Resolved',
                  style: TextStyle(
                    color: AppColors.sequencerText,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: Text(
                      'Done',
                      style: TextStyle(color: AppColors.sequencerAccent),
                    ),
                  ),
                ],
              );
            }

            return AlertDialog(
              backgroundColor: AppColors.sequencerSurfaceRaised,
              title: Text(
                'Missing Samples',
                style: TextStyle(
                  color: AppColors.sequencerText,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: issues.map((issue) {
                      final clampedSlot = issue.slot
                          .clamp(0, SampleBankState.maxSampleSlots - 1);
                      final slotLabel = clampedSlot < 26
                          ? String.fromCharCode(65 + clampedSlot)
                          : '${clampedSlot + 1}';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.sequencerBorder),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Slot $slotLabel',
                              style: TextStyle(
                                color: AppColors.sequencerText,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            if (issue.displayName != null &&
                                issue.displayName!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  issue.displayName!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppColors.sequencerLightText,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.only(top: 6, bottom: 8),
                              child: Text(
                                _missingReasonLabel(issue.reason),
                                style: TextStyle(
                                  color: AppColors.sequencerLightText,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            // Do not use LayoutBuilder here: AlertDialog uses
                            // IntrinsicWidth and will query intrinsic dimensions,
                            // which LayoutBuilder cannot provide (Flutter assert).
                            Wrap(
                              spacing: 4,
                              runSpacing: 8,
                              alignment: WrapAlignment.start,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                TextButton(
                                  onPressed: () => resolveByLocate(issue),
                                  child: const Text('Locate file'),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      resolveByReplaceFromLibrary(issue),
                                  child: const Text('Replace from library'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                      if (!dialogContext.mounted) return;
                                      setDialogState(
                                          () => issues.remove(issue));
                                    });
                                  },
                                  child: const Text('Skip'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(
                    'Continue',
                    style: TextStyle(color: AppColors.sequencerAccent),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    _pendingMissingSamples = const [];
  }

  String _missingReasonLabel(MissingSampleReason reason) {
    switch (reason) {
      case MissingSampleReason.missingSampleId:
        return 'Sample id is missing in this snapshot.';
      case MissingSampleReason.unknownSampleId:
        return 'Sample id is not found in the current built-in/custom index.';
      case MissingSampleReason.missingAssetPath:
        return 'Built-in sample exists but has no valid asset path.';
      case MissingSampleReason.fileNotFound:
        return 'Audio file could not be found on device storage.';
      case MissingSampleReason.loadFailed:
        return 'Sample failed to load in audio engine.';
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

    _patternsStateRef
        ?.removeBeforeActivePatternSwitchListener(_onBeforeActivePatternSwitch);

    // Cancel auto-save timer and force immediate save
    _autoSaveTimer?.cancel();
    _saveRetryTimer?.cancel();
    if (!_suppressAutoSave &&
        _bootstrapComplete &&
        _loadedPatternId != null &&
        _patternsStateRef?.activePattern?.id == _loadedPatternId) {
      _requestSave(
        reason: _SequencerSaveReason.dispose,
        force: true,
        allowBackgroundRetry: true,
      );
    }

    // Remove auto-save listeners
    _tableState.removeListener(_onSequencerStateChanged);
    _playbackState.removeListener(_onSequencerStateChanged);
    _sampleBankState.removeListener(_onSequencerStateChanged);

    // Remove recording state listener
    _recordingState.removeListener(_onRecordingStateChanged);

    // Remove playback state listener
    _playbackState.isPlayingNotifier.removeListener(_onPlaybackStateChanged);

    // Remove loop boundary listeners
    _playbackState.currentSectionLoopNotifier
        .removeListener(_onLoopBoundaryCheck);
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
      Log.d('App resumed - reconfiguring Bluetooth audio session',
          'SEQUENCER_V2');
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      // App going to background or being closed - force immediate save
      Log.d('App leaving foreground - forcing auto-save', 'SEQUENCER_V2');
      _autoSaveTimer?.cancel();
      _requestSave(
        reason: _SequencerSaveReason.lifecycle,
        force: true,
        allowBackgroundRetry: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Must watch AppState, not only activeTutorialStep: sub-steps (e.g. layer tab
    // done, mute/unmute) update via notifyListeners without changing the step enum.
    final appState = context.watch<AppState>();
    final tutorialStep = appState.activeTutorialStep;
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
        key: _scaffoldKey,
        backgroundColor: AppColors.sequencerPageBackground,
        endDrawer: _buildSequencerNavDrawer(),
        endDrawerEnableOpenDragGesture: false,
        body: Stack(
          children: [
            // Sequencer view only (thread view removed)
            _buildSequencerView(),
            // After bootstrap so grid anchors exist and Yes does not race load.
            if (appState.showTutorialPromptThisSession &&
                tutorialStep == TutorialStep.none &&
                !_isInitialLoading)
              Positioned.fill(
                child: _buildTutorialEntryDialog(appState),
              ),

            // Floating playback bar
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildFloatingPlaybackBar(
                tutorialStep: tutorialStep,
                appState: appState,
              ),
            ),

            // Value slider dim over playback bar (must be above bar in z-order;
            // top dim lives inside [_buildSequencerView]). [Positioned] must be a
            // direct [Stack] child; [ValueListenableBuilder] sits inside it.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ValueListenableBuilder<bool>(
                valueListenable: _sliderOverlayState.isInteractingNotifier,
                builder: (context, isInteracting, _) {
                  if (!isInteracting) return const SizedBox.shrink();
                  final padding = MediaQuery.paddingOf(context);
                  return SizedBox(
                    height: padding.bottom + _floatingPlaybackBarHeight,
                    width: double.infinity,
                    child: ColoredBox(
                      color: Colors.black.withOpacity(0.6),
                    ),
                  );
                },
              ),
            ),

            if (_isInitialLoading)
              Positioned.fill(
                child: Container(
                  color: AppColors.sequencerPageBackground.withOpacity(0.8),
                  child: Center(
                    child: CircularProgressIndicator(
                        color: AppColors.sequencerAccent),
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
                        CircularProgressIndicator(
                            color: AppColors.sequencerAccent),
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
            if (tutorialStep == TutorialStep.sequencerFirstCellHint)
              _SequencerTutorialAnchorOverlay(
                anchorKey: appState.firstCellTutorialKey,
                label: appState.tutorialStepLabel,
                text: 'Tap on this cell in the sample grid',
                centerText: true,
              ),
            if (tutorialStep == TutorialStep.sequencerSelectSampleHint)
              _SequencerTutorialAnchorOverlay(
                anchorKey: appState.selectSampleTutorialKey,
                label: appState.tutorialStepLabel,
                text:
                    'Select sample for this cell. Choose any sample from the library.',
              ),
            if (tutorialStep == TutorialStep.sequencerCellParamsHint)
              _SequencerTutorialAnchorOverlay(
                anchorKey: appState.showCellParamsVolumePointer
                    ? appState.cellParamsVolumeButtonTutorialKey
                    : appState.cellParamsKeyButtonTutorialKey,
                label: appState.tutorialStepLabel,
                text:
                    'Set Volume (Vol) to 80% and scroll Key control to D# for created sample cell.',
                centerText: true,
                centerInRectKey: appState.sampleGridTutorialKey,
              ),
            if (tutorialStep == TutorialStep.sequencerCopyPasteHint)
              _SequencerTutorialAnchorOverlay(
                anchorKey: appState.showCopyPointer
                    ? appState.copyButtonTutorialKey
                    : appState.copyPasteTargetCellTutorialKey,
                secondaryAnchorKey: appState.showCopyPasteSourceCellHighlight
                    ? appState.copyPasteTargetCellTutorialKey
                    : null,
                label: appState.tutorialStepLabel,
                text:
                    'Select this cell again, then press Copy, then select another cell and press Paste.',
              ),
            if (tutorialStep == TutorialStep.sequencerDeleteHint)
              _SequencerTutorialAnchorOverlay(
                anchorKey: appState.deleteButtonTutorialKey,
                label: appState.tutorialStepLabel,
                text: 'Try to delete the created sample cell',
              ),
            if (tutorialStep == TutorialStep.sequencerUndoRedoHint)
              _SequencerTutorialAnchorOverlay(
                anchorKey: appState.undoButtonTutorialKey,
                secondaryAnchorKey: appState.redoButtonTutorialKey,
                label: appState.tutorialStepLabel,
                text:
                    'Press Undo to restore the deleted sample and then press Redo to delete it again.',
              ),
            if (tutorialStep == TutorialStep.sequencerJumpValueTwoHint)
              _SequencerTutorialAnchorOverlay(
                anchorKey: appState.jumpValueTwoDisplayTutorialKey,
                label: appState.tutorialStepLabel,
                text:
                    'Set Jump to 2. Tap JUMP to open the wheel, then scroll to 2.',
              ),
            if (tutorialStep == TutorialStep.sequencerJumpPasteHint)
              _SequencerTutorialAnchorOverlay(
                anchorKey: appState.showJumpCopyPointer
                    ? appState.copyButtonTutorialKey
                    : (appState.showJumpPasteTargetCellPointer
                        ? appState.jumpPasteTargetCellTutorialKey
                        : appState.pasteButtonTutorialKey),
                secondaryAnchorKey: appState.showJumpCopyPointer
                    ? appState.jumpPasteSourceCellTutorialKey
                    : (appState.showJumpPasteTargetCellPointer
                        ? appState.pasteButtonTutorialKey
                        : null),
                label: appState.tutorialStepLabel,
                text:
                    'Select and Copy a sample, then select cell below and press Paste three times (Jump spacing is 2).',
              ),
            if (tutorialStep == TutorialStep.sequencerPlaybackHint)
              _SequencerTutorialAnchorOverlay(
                anchorKey: appState.playButtonTutorialKey,
                label: appState.tutorialStepLabel,
                text: 'Press Play, then press Stop.',
              ),
            if (tutorialStep == TutorialStep.sequencerRecordingHint)
              _SequencerTutorialAnchorOverlay(
                anchorKey: appState.showRecordingPlayPointer
                    ? appState.playButtonTutorialKey
                    : appState.recordButtonTutorialKey,
                label: appState.tutorialStepLabel,
                text: appState.recordingStepInstruction,
              ),
            if (tutorialStep == TutorialStep.sequencerLayersHint)
              _SequencerTutorialAnchorOverlay(
                anchorKey: appState.isLayersTabDone
                    ? appState.layerMuteButtonTutorialKey
                    : appState.layersRowTutorialKey,
                label: appState.tutorialStepLabel,
                text: !appState.isLayersTabDone
                    ? 'These are section layers.\n\nAll of them play simultaneously. Arrange samples across them however you want.\n\nNow select layer A tab.'
                    : (!appState.isLayersMuteDone
                        ? 'Now press Mute layer button.'
                        : 'Unmute the layer by pressing Mute again.'),
                centerInRectKey: appState.sampleGridTutorialKey,
                drawLayerPointers: !appState.isLayersTabDone,
                layerPointersCount: _tableState.totalLayers,
              ),
            if (tutorialStep == TutorialStep.sequencerSelectModeHint)
              _SequencerTutorialAnchorOverlay(
                anchorKey: appState.showSelectModeVolumePointer
                    ? appState.multitaskPanelTutorialKey
                    : appState.selectModeButtonTutorialKey,
                label: appState.tutorialStepLabel,
                text: appState.selectModeStepInstruction,
              ),
            if (tutorialStep == TutorialStep.sequencerSectionsSwipeHint)
              _SequencerTutorialAnchorOverlay(
                anchorKey: appState.sampleGridTutorialKey,
                label: appState.tutorialStepLabel,
                text: 'Swipe the sound grid left and create a second section.',
                centerText: true,
                centerInRectKey: appState.sampleGridTutorialKey,
                drawCurvedSwipeHint: true,
              ),
            if (tutorialStep == TutorialStep.sequencerSectionTwoStepsHint)
              _SequencerTutorialAnchorOverlay(
                anchorKey: appState.showSectionTwoStepsIncreasePointer
                    ? appState.sectionStepsIncreaseTutorialKey
                    : appState.sectionStepsDecreaseTutorialKey,
                label: appState.tutorialStepLabel,
                text: appState.sectionTwoStepsHintInstruction,
                centerText: false,
                centerInRectKey: appState.sampleGridTutorialKey,
                textPosition: _TutorialTextPosition.belowGrid,
                drawVerticalScrollDownHint:
                    appState.showSectionTwoStepsIncreasePointer,
                drawCoachArrow: true,
              ),
            if (tutorialStep == TutorialStep.sequencerSectionTwoSamplesHint)
              _SequencerTutorialAnchorOverlay(
                anchorKey: appState.sampleGridTutorialKey,
                label: appState.tutorialStepLabel,
                text:
                    'Place at least 5 samples in 5 different cells in this section.',
                centerText: false,
                textPosition: _TutorialTextPosition.stepControlsGap,
                centerInRectKey: appState.sampleGridTutorialKey,
                drawCoachArrow: false,
              ),
            if (tutorialStep == TutorialStep.sequencerSectionsNavigateHint)
              _SequencerTutorialAnchorOverlay(
                anchorKey: appState.sampleGridTutorialKey,
                label: appState.tutorialStepLabel,
                text:
                    'Swipe right to go back to section 1 or select section 1 in section management menu.',
                centerText: true,
                centerInRectKey: appState.sampleGridTutorialKey,
                drawCoachArrow: false,
              ),
            if (tutorialStep == TutorialStep.sequencerSectionsMenuHint)
              _SequencerTutorialAnchorOverlay(
                anchorKey: appState.sectionMenuButtonTutorialKey,
                label: appState.tutorialStepLabel,
                text:
                    'This is the section menu: you can navigate, add, or insert sections here too.',
              ),
            if (tutorialStep == TutorialStep.sequencerSongModeHint)
              _SequencerTutorialAnchorOverlay(
                anchorKey: appState.songModeButtonTutorialKey,
                label: appState.tutorialStepLabel,
                textPosition: _TutorialTextPosition.center,
                text:
                    'Sequencer could be in loop and song modes.\n\nIn loop mode section plays indefinitely, in song mode sections are iterated.\n\nPress this button to enter song mode.',
              ),
            if (tutorialStep == TutorialStep.sequencerSectionLoopsHint)
              _SequencerTutorialAnchorOverlay(
                anchorKey: appState.sectionSettingsButtonTutorialKey,
                label: appState.tutorialStepLabel,
                text:
                    'Press sections settings button. You can control number of loops here for song mode.\nSet loops count to 2 for any section.',
              ),
            if (tutorialStep == TutorialStep.sequencerSongRecordingHint)
              _SequencerTutorialAnchorOverlay(
                anchorKey: appState.showSongRecordingRecordPointer
                    ? appState.recordButtonTutorialKey
                    : appState.playButtonTutorialKey,
                label: appState.tutorialStepLabel,
                text:
                    'Press Record and Play to record the song made from 2 sections.\nWhen playback finishes, you will be taken to Takes automatically.',
              ),
            if (tutorialStep == TutorialStep.sequencerBackToPatternHint)
              _SequencerTutorialAnchorOverlay(
                anchorKey: appState.patternMenuButtonTutorialKey,
                label: appState.tutorialStepLabel,
                text:
                    'Open the menu, then tap Patterns to return to the patterns page.',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTutorialEntryDialog(AppState appState) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        final gridRect = _tutorialResolveAnchorRect(
            appState.sampleGridTutorialKey, viewport);
        final dialogCenter =
            gridRect?.center ?? Offset(viewport.width / 2, viewport.height / 2);
        final dialogWidth = min(290.0, max(220.0, viewport.width - 24));
        const dialogHeightEstimate = 126.0;
        final left = (dialogCenter.dx - dialogWidth / 2)
            .clamp(12.0, max(12.0, viewport.width - dialogWidth - 12.0))
            .toDouble();
        final top = (dialogCenter.dy - dialogHeightEstimate / 2)
            .clamp(
              MediaQuery.paddingOf(context).top + 10,
              max(
                MediaQuery.paddingOf(context).top + 10,
                viewport.height - dialogHeightEstimate - 12.0,
              ),
            )
            .toDouble();

        return Container(
          color: Colors.black.withOpacity(0.18),
          child: Stack(
            children: [
              Positioned(
                left: left,
                top: top,
                width: dialogWidth,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  decoration: BoxDecoration(
                    color: AppColors.sequencerSurfaceRaised.withOpacity(0.96),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppColors.sequencerBorder, width: 0.8),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        appState.tutorialEntryPromptIsResume
                            ? 'Proceed with tutorial?'
                            : 'Run quick tutorial?',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.sequencerText,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton(
                            onPressed: appState.tutorialEntryPromptIsResume
                                ? appState.resumeSequencerQuickTutorial
                                : appState.startSequencerQuickTutorial,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.sequencerAccent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 18, vertical: 9),
                              minimumSize: const Size(0, 0),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              appState.tutorialEntryPromptIsResume
                                  ? 'Proceed'
                                  : 'Yes',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: appState.dismissTutorialPromptForSession,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.sequencerSurfaceBase,
                              foregroundColor: AppColors.sequencerText,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 18, vertical: 9),
                              minimumSize: const Size(0, 0),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              'No',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _navigateBackToPatterns() async {
    if (_playbackState.isPlaying) _playbackState.stop();
    context.read<AppState>().markPatternMenuBackAction();
    try {
      context.read<AudioPlayerState>().stop();
    } catch (_) {}
    _autoSaveTimer?.cancel();
    final saveFinished = await _requestSave(
      reason: _SequencerSaveReason.back,
      force: true,
      allowBackgroundRetry: true,
    ).timeout(
      _leaveSaveSoftTimeout,
      onTimeout: () => false,
    );
    if (!saveFinished) {
      Log.w(
        'Back navigation continued before save confirmation',
        'SEQUENCER_V2',
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _openLibraryFromNavMenu(BuildContext menuContext) {
    Navigator.of(menuContext).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AppState>().markProjectsLibraryFolderOpenAction();
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => const LibraryScreen(),
        ),
      );
    });
  }

  String _suggestedProjectArchiveFileName() {
    final activePatternName = _patternsStateRef?.activePattern?.name.trim();
    final safeBaseName =
        (activePatternName == null || activePatternName.isEmpty)
            ? 'hypnopitch_project'
            : activePatternName
                .replaceAll(RegExp(r'[^\w\-\s]'), '')
                .replaceAll(RegExp(r'\s+'), '_')
                .toLowerCase();
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    return '${safeBaseName}_$y$m${d}_$hh$mm$ss.$snapshotArchiveFileExtension';
  }

  String _fileNameFromPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final slash = normalized.lastIndexOf('/');
    if (slash >= 0 && slash + 1 < normalized.length) {
      return normalized.substring(slash + 1);
    }
    return normalized;
  }

  SnapshotService _buildSnapshotService() {
    return SnapshotService(
      tableState: _tableState,
      playbackState: _playbackState,
      sampleBankState: _sampleBankState,
      librarySamplesState:
          Provider.of<LibrarySamplesState>(context, listen: false),
    );
  }

  Future<void> _exportSnapshotFromNavMenu(BuildContext menuContext) async {
    Navigator.of(menuContext).pop();
    try {
      final patternName = _patternsStateRef?.activePattern?.name ?? 'Project';
      final archiveBytes = await _buildSnapshotService().exportToArchiveBytes(
        name: patternName,
        description: 'Manual project export from sequencer drawer',
      );
      if (!mounted) return;

      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.save_alt_outlined),
                  title: const Text('Save to file'),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    if (!mounted) return;
                    await _saveProjectArchiveBytes(archiveBytes);
                  },
                ),
                Builder(
                  builder: (tileContext) {
                    return ListTile(
                      leading: const Icon(Icons.share_outlined),
                      title: const Text('Share'),
                      onTap: () async {
                        final box = tileContext.findRenderObject() as RenderBox?;
                        final sharePositionOrigin = box == null
                            ? const Rect.fromLTWH(0, 0, 100, 100)
                            : box.localToGlobal(Offset.zero) & box.size;
                        Navigator.of(sheetContext).pop();
                        if (!mounted) return;
                        await _shareProjectArchiveBytes(
                          archiveBytes,
                          sharePositionOrigin: sharePositionOrigin,
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to export project archive: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _saveProjectArchiveBytes(Uint8List bytes) async {
    try {
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Export portable project archive',
        fileName: _suggestedProjectArchiveFileName(),
        type: FileType.custom,
        allowedExtensions: const [snapshotArchiveFileExtension],
        bytes: bytes,
      );
      if (!mounted || savePath == null || savePath.isEmpty) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Project exported: ${_fileNameFromPath(savePath)}'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save project: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _shareProjectArchiveBytes(
    Uint8List bytes, {
    required Rect sharePositionOrigin,
  }) async {
    final fileName = _suggestedProjectArchiveFileName();
    final tempPath =
        '${Directory.systemTemp.path}${Platform.pathSeparator}$fileName';
    final file = File(tempPath);
    try {
      await file.writeAsBytes(bytes);
      await Share.shareXFiles(
        [
          XFile(
            tempPath,
            name: fileName,
            mimeType: 'application/zip',
          ),
        ],
        subject: 'HypnoPitch project',
        text: 'HypnoPitch project',
        sharePositionOrigin: sharePositionOrigin,
      );
      // Share can return before the OS finishes copying the file (Android).
      Future<void>.delayed(const Duration(seconds: 3), () async {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to share project: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  Future<void> _importSnapshotFromNavMenu(BuildContext menuContext) async {
    Navigator.of(menuContext).pop();
    try {
      // Use FileType.any: custom extensions like `hypnopattern` are not registered
      // with the OS (iOS UTI / Android MimeTypeMap), so FileType.custom drops them
      // and .hypnopattern files never appear in the filtered picker.
      final picked = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
        type: FileType.any,
        dialogTitle: 'Select project file (.hypnopattern, .json, or .zip)',
      );
      final file = picked?.files.first;
      final path = file?.path;
      final fileName = file?.name ?? '';
      if (!mounted || file == null) return;

      final fileBytes = file.bytes ??
          (path != null && path.isNotEmpty
              ? await File(path).readAsBytes()
              : null);
      if (!mounted || fileBytes == null || fileBytes.isEmpty) return;

      if (!mounted) return;

      final snapshotService = _buildSnapshotService();
      var restoredEmbeddedSamples = 0;
      bool success;
      if (snapshotService.validateArchiveBytes(fileBytes)) {
        final archiveResult =
            await snapshotService.importFromArchiveBytes(fileBytes);
        success = archiveResult.success;
        restoredEmbeddedSamples = archiveResult.restoredEmbeddedSampleCount;
      } else {
        String? jsonString;
        try {
          jsonString = utf8.decode(fileBytes);
        } catch (_) {
          jsonString = null;
        }
        if (jsonString == null || !snapshotService.validateJson(jsonString)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unsupported project archive format.'),
              duration: Duration(seconds: 3),
            ),
          );
          return;
        }
        success = await snapshotService.importFromJson(jsonString);
      }

      if (!mounted) return;
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to import project snapshot.'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      final missing = snapshotService.lastImportReport.missingSamples;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            restoredEmbeddedSamples > 0
                ? 'Project imported: ${_fileNameFromPath(path ?? fileName)} ($restoredEmbeddedSamples embedded samples restored)'
                : 'Project imported: ${_fileNameFromPath(path ?? fileName)}',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      if (missing.isNotEmpty) {
        _pendingMissingSamples = missing;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showMissingSamplesDialog(missing);
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to import project archive: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Widget _buildSequencerNavDrawer() {
    final takesTitleStyle = TextStyle(
      color: AppColors.sequencerText,
      fontSize: 17,
      fontWeight: FontWeight.w600,
    );
    return Builder(
      builder: (drawerContext) {
        final width = MediaQuery.sizeOf(drawerContext).width * 0.75;
        return Drawer(
          width: width,
          backgroundColor: AppColors.sequencerSurfaceRaised,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(_navDrawerCornerRadius),
              bottomLeft: Radius.circular(_navDrawerCornerRadius),
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SizedBox(
                  height: constraints.maxHeight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 16, 20, 8),
                                child: Text(
                                  'Menu',
                                  style: TextStyle(
                                    color: AppColors.sequencerLightText,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.3,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              ListTile(
                                leading: Icon(
                                  Icons.graphic_eq,
                                  color: AppColors.sequencerAccent,
                                ),
                                title: Text(
                                  'Takes',
                                  style: takesTitleStyle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  Navigator.of(drawerContext).pop();
                                  WidgetsBinding.instance
                                      .addPostFrameCallback((_) {
                                    if (mounted) {
                                      _showRecordingsOverlay(context);
                                    }
                                  });
                                },
                              ),
                              ListTile(
                                leading: Icon(
                                  Icons.upload_file_rounded,
                                  color: AppColors.sequencerAccent,
                                ),
                                title: Text(
                                  'Export',
                                  style: takesTitleStyle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  _exportSnapshotFromNavMenu(drawerContext);
                                },
                              ),
                              ListTile(
                                leading: Icon(
                                  Icons.download_rounded,
                                  color: AppColors.sequencerAccent,
                                ),
                                title: Text(
                                  'Import',
                                  style: takesTitleStyle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  _importSnapshotFromNavMenu(drawerContext);
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Divider(
                          height: 1,
                          thickness: 1,
                          color: const Color(0xFF9A9A96),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 16, 16),
                        child: Align(
                          alignment: Alignment.bottomRight,
                          child: Builder(
                            builder: (_) {
                              // Outer padding 12+16; InkWell inner padding 8+8; icon column + gap.
                              final textMaxW = max(
                                0.0,
                                constraints.maxWidth -
                                    28 -
                                    16 -
                                    _navDrawerBottomIconSlotWidth -
                                    14,
                              );
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () {
                                        HapticFeedback.lightImpact();
                                        Navigator.of(drawerContext).pop();
                                        WidgetsBinding.instance
                                            .addPostFrameCallback((_) {
                                          if (mounted) {
                                            unawaited(
                                                _navigateBackToPatterns());
                                          }
                                        });
                                      },
                                      borderRadius: BorderRadius.circular(8),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 10,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            SizedBox(
                                              width:
                                                  _navDrawerBottomIconSlotWidth,
                                              child: Align(
                                                alignment: Alignment.centerLeft,
                                                child: Icon(
                                                  Icons.grid_view_rounded,
                                                  size:
                                                      _navDrawerSideActionIconSize,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 14),
                                            ConstrainedBox(
                                              constraints: BoxConstraints(
                                                maxWidth: textMaxW,
                                              ),
                                              child: Text(
                                                'Patterns',
                                                style: TextStyle(
                                                  color:
                                                      AppColors.sequencerText,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () {
                                        HapticFeedback.lightImpact();
                                        _openLibraryFromNavMenu(
                                            drawerContext);
                                      },
                                      borderRadius: BorderRadius.circular(8),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 10,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            SizedBox(
                                              width:
                                                  _navDrawerBottomIconSlotWidth,
                                              child: Align(
                                                alignment: Alignment.centerLeft,
                                                child: Icon(
                                                  Icons.folder_outlined,
                                                  size:
                                                      _navDrawerSideActionIconSize,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 14),
                                            ConstrainedBox(
                                              constraints: BoxConstraints(
                                                maxWidth: textMaxW,
                                              ),
                                              child: Text(
                                                'Library',
                                                style: TextStyle(
                                                  color:
                                                      AppColors.sequencerText,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                              ),
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
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showRecordingsOverlay(BuildContext context,
      {bool highlightNewest = false}) {
    if (_isFinalizingTake) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Processing take...'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final appState = context.read<AppState>();
    final tutorialStep = appState.activeTutorialStep;
    final isTakesTutorialStep =
        tutorialStep == TutorialStep.sequencerTakesHint ||
            appState.showSecondTakeAddPointer ||
            appState.showSecondTakeClosePointer;
    showDialog(
      context: context,
      barrierDismissible: !isTakesTutorialStep,
      builder: (context) =>
          PatternRecordingsOverlay(highlightNewest: highlightNewest),
    );
  }

  Widget _buildSequencerView() {
    final appState = context.watch<AppState>();
    final tutorialStep = appState.activeTutorialStep;
    return Stack(
      children: [
        SafeArea(
          child: Column(
            children: [
              Expanded(
                flex: _sequencerBodyFlex,
                child: SequencerBody(
                  onOpenNavMenu: () =>
                      _scaffoldKey.currentState?.openEndDrawer(),
                  onSettings: () => _navigateToSettings(context),
                ),
              ),
              Expanded(
                flex: _editButtonsFlex,
                child: RepaintBoundary(
                  child: const v1.EditButtonsWidget(),
                ),
              ),
              Expanded(
                flex: _multitaskPanelFlex,
                child: RepaintBoundary(
                  key: tutorialStep == TutorialStep.sequencerCellParamsHint
                      ? appState.multitaskPanelTutorialKey
                      : null,
                  child: const v1.MultitaskPanelWidget(),
                ),
              ),
              const SizedBox(
                  height:
                      _floatingPlaybackBarHeight), // Keep panel stacked above floating playback bar
            ],
          ),
        ),
        // Value overlay (inset matches SafeArea Column: three Expanded share
        // h - top - bottom - spacer; see body Stack for bottom dim over playback bar).
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final h = constraints.maxHeight;
              final padding = MediaQuery.paddingOf(context);
              const double playbackControl = _floatingPlaybackBarHeight;
              final double flexRegion = max(
                0.0,
                h - padding.top - padding.bottom - playbackControl,
              );
              final double bottomInset = padding.bottom +
                  playbackControl +
                  flexRegion * (_multitaskPanelFlex / _contentFlexTotal);
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

  Widget _buildFloatingPlaybackBar({
    required TutorialStep tutorialStep,
    required AppState appState,
  }) {
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
        child: Consumer4<TableState, PlaybackState, RecordingState,
            MultitaskPanelState>(
          builder: (context, tableState, playbackState, recordingState,
              multitaskPanelState, child) {
            _playbackBarBuildCount++;
            if (kShouldLogSequencerProfiling &&
                (_playbackBarBuildCount % 180 == 0)) {
              Log.d(
                '[PLAYBACK_BAR_PROFILE] build_count=$_playbackBarBuildCount',
                'SEQUENCER_V2',
              );
            }
            return LayoutBuilder(
              builder: (context, constraints) {
                final barHeight = constraints.maxHeight;
                final double innerVerticalMargin = 4;
                final double innerHorizontalMargin = 6;
                final double innerHeight = (barHeight - innerVerticalMargin * 2)
                    .clamp(0, double.infinity);

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
                      border: Border.all(
                          color: AppColors.sequencerBorder, width: 0.5),
                    ),
                    child: LayoutBuilder(
                      builder: (context, rowConstraints) {
                        final totalWidth = rowConstraints.maxWidth;
                        const gap = 8.0;
                        final double chainFraction =
                            0.4; // Fixed width (thread view removed)
                        final double buttonsFraction = 1 - chainFraction;
                        final double chainWidth =
                            (totalWidth - gap) * chainFraction;
                        final double buttonsWidth =
                            (totalWidth - gap) * buttonsFraction;
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
                                      valueListenable:
                                          recordingState.isRecordingNotifier,
                                      builder: (context, isRecording, _) {
                                        return Stack(
                                          children: [
                                            // Section chain: tap toggles section management; neutral chrome +
                                            // opacity blink on tap (no persistent active styling).
                                            Container(
                                              key: appState
                                                  .sectionMenuButtonTutorialKey,
                                              clipBehavior: Clip.antiAlias,
                                              decoration: BoxDecoration(
                                                color: AppColors
                                                    .sequencerSurfaceBase,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                border: Border.all(
                                                  color: AppColors
                                                      .sequencerBorder,
                                                  width: 0.5,
                                                ),
                                              ),
                                              child: _SequencerTapBlinkChild(
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                onTap: isRecording
                                                    ? null
                                                    : () {
                                                        if (!appState
                                                            .canInteractWithTutorialTarget(
                                                          TutorialInteractionTarget
                                                              .sectionMenuButton,
                                                        )) {
                                                          return;
                                                        }
                                                        if (multitaskPanelState
                                                                .currentMode ==
                                                            MultitaskPanelMode
                                                                .sectionManagement) {
                                                          multitaskPanelState
                                                              .showPlaceholder();
                                                        } else {
                                                          multitaskPanelState
                                                              .showSectionManagement();
                                                        }
                                                        if (appState
                                                                .activeTutorialStep ==
                                                            TutorialStep
                                                                .sequencerSectionsMenuHint) {
                                                          appState
                                                              .completeSectionMenuTutorialStep();
                                                        }
                                                      },
                                                child: Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8),
                                                  child: Center(
                                                    child: _buildSectionChain(
                                                      tableState
                                                          .sectionsCount,
                                                      playbackState,
                                                      allActive: false,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            // Dark overlay when recording
                                            if (isRecording)
                                              Positioned.fill(
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    color: AppColors
                                                        .sequencerSurfaceBase
                                                        .withOpacity(0.9),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            4),
                                                  ),
                                                ),
                                              ),
                                            // Recording timer on top
                                            if (isRecording)
                                              Positioned.fill(
                                                child: Center(
                                                  child: Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 6,
                                                        vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: Colors.transparent,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                      border: Border.all(
                                                          color: AppColors
                                                              .sequencerLightText,
                                                          width: 1),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        _RecordingIndicatorDot(
                                                            color: AppColors
                                                                .sequencerLightText),
                                                        const SizedBox(
                                                            width: 4),
                                                        ValueListenableBuilder<
                                                            Duration>(
                                                          valueListenable:
                                                              recordingState
                                                                  .recordingDurationNotifier,
                                                          builder: (context,
                                                              duration, __) {
                                                            final minutes =
                                                                duration
                                                                    .inMinutes;
                                                            final seconds =
                                                                duration.inSeconds %
                                                                    60;
                                                            final text =
                                                                '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
                                                            return Text(
                                                              text,
                                                              style: TextStyle(
                                                                color: const Color
                                                                    .fromARGB(
                                                                    255,
                                                                    231,
                                                                    229,
                                                                    226),
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                fontFamily:
                                                                    'monospace',
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
                                    valueListenable:
                                        recordingState.isRecordingNotifier,
                                    builder: (context, isRecording, _) {
                                      return ValueListenableBuilder<bool>(
                                        valueListenable:
                                            recordingState.isArmedNotifier,
                                        builder: (context, isArmed, __) {
                                          return ValueListenableBuilder<bool>(
                                            valueListenable:
                                                playbackState.isPlayingNotifier,
                                            builder: (context, isPlaying, ___) {
                                              // Record button shows active when recording OR armed
                                              final isRecordButtonActive =
                                                  isRecording || isArmed;
                                              return LayoutBuilder(
                                                builder: (context, box) {
                                                  final double perButtonWidth =
                                                      box.maxWidth / 3;
                                                  final double perButtonHeight =
                                                      box.maxHeight;
                                                  return Row(
                                                    children: [
                                                      SizedBox(
                                                        width: perButtonWidth,
                                                        height:
                                                            perButtonHeight,
                                                        child:
                                                            _SequencerTapBlinkChild(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      2),
                                                          onTap: appState
                                                                  .isTutorialRunning
                                                              ? null
                                                              : () {
                                                                  Log.d(
                                                                    'Master settings button pressed',
                                                                    'SEQUENCER_V2',
                                                                  );
                                                                  if (multitaskPanelState
                                                                          .currentMode ==
                                                                      MultitaskPanelMode
                                                                          .masterSettings) {
                                                                    multitaskPanelState
                                                                        .showPlaceholder();
                                                                  } else {
                                                                    multitaskPanelState
                                                                        .showMasterSettings();
                                                                  }
                                                                },
                                                          child: Center(
                                                            child:
                                                                Transform
                                                                    .rotate(
                                                              angle: 1.5708,
                                                              child: Icon(
                                                                Icons.tune,
                                                                size: 20,
                                                                color: AppColors
                                                                    .sequencerLightText,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        width: perButtonWidth,
                                                        height:
                                                            perButtonHeight,
                                                        child: Material(
                                                          color: Colors
                                                              .transparent,
                                                          child: InkWell(
                                                            onTap: () async {
                                                              if (!appState
                                                                  .canInteractWithTutorialTarget(
                                                                TutorialInteractionTarget
                                                                    .recordButton,
                                                              )) {
                                                                return;
                                                              }
                                                              HapticFeedback.lightImpact();
                                                              if (isRecording ||
                                                                  isArmed) {
                                                                appState
                                                                    .markRecordingStopAction(
                                                                  recordingDuration:
                                                                      recordingState
                                                                          .recordingDuration,
                                                                );
                                                                appState
                                                                    .markSongRecordingStopAction(
                                                                  recordingDuration:
                                                                      recordingState
                                                                          .recordingDuration,
                                                                  sectionsCount:
                                                                      tableState
                                                                          .sectionsCount,
                                                                  isSongMode:
                                                                      playbackState
                                                                          .songMode,
                                                                );
                                                                await recordingState
                                                                    .stopRecording();
                                                              } else {
                                                                appState
                                                                    .markRecordingAction();
                                                                appState
                                                                    .markSongRecordingAction();
                                                                final currentLayer =
                                                                    _tableState
                                                                        .uiSelectedLayer;
                                                                await recordingState
                                                                    .startRecording(
                                                                        layer:
                                                                            currentLayer);
                                                              }
                                                            },
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        2),
                                                            splashColor: Colors
                                                                .transparent,
                                                            highlightColor:
                                                                Colors
                                                                    .transparent,
                                                            child: Container(
                                                              width:
                                                                  perButtonWidth,
                                                              height:
                                                                  perButtonHeight,
                                                              alignment:
                                                                  Alignment
                                                                      .center,
                                                              color:
                                                                  isRecordButtonActive
                                                                      ? AppColors
                                                                          .sequencerPrimaryButton
                                                                      : Colors
                                                                          .transparent,
                                                              child:
                                                                  KeyedSubtree(
                                                                key: appState
                                                                    .recordButtonTutorialKey,
                                                                child: Icon(
                                                                  Icons.circle,
                                                                  size: 14,
                                                                  color:
                                                                      isRecordButtonActive
                                                                          ? Colors
                                                                              .white
                                                                          : AppColors
                                                                              .sequencerLightText,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        width: perButtonWidth,
                                                        height:
                                                            perButtonHeight,
                                                        child: Material(
                                                          color: Colors
                                                              .transparent,
                                                          child: InkWell(
                                                            onTap: () {
                                                              if (!appState
                                                                  .canInteractWithTutorialTarget(
                                                                TutorialInteractionTarget
                                                                    .playButton,
                                                              )) {
                                                                return;
                                                              }
                                                              HapticFeedback.lightImpact();
                                                              if (isPlaying) {
                                                                playbackState
                                                                    .stop();
                                                                appState
                                                                    .markStopAction();
                                                              } else {
                                                                playbackState
                                                                    .start();
                                                                appState
                                                                    .markPlayAction();
                                                                appState
                                                                    .markRecordingPlayAction();
                                                                appState
                                                                    .markSongRecordingPlayAction();
                                                              }
                                                            },
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        2),
                                                            splashColor: Colors
                                                                .transparent,
                                                            highlightColor:
                                                                Colors
                                                                    .transparent,
                                                            child: Container(
                                                              width:
                                                                  perButtonWidth,
                                                              height:
                                                                  perButtonHeight,
                                                              alignment:
                                                                  Alignment
                                                                      .center,
                                                              color: isPlaying
                                                                  ? AppColors
                                                                      .sequencerPrimaryButton
                                                                  : Colors
                                                                      .transparent,
                                                              child:
                                                                  KeyedSubtree(
                                                                key: appState
                                                                    .playButtonTutorialKey,
                                                                child: Icon(
                                                                  isPlaying
                                                                      ? Icons
                                                                          .stop
                                                                      : Icons
                                                                          .play_arrow,
                                                                  size: 20,
                                                                  color:
                                                                      isPlaying
                                                                          ? Colors
                                                                              .white
                                                                          : AppColors
                                                                              .sequencerLightText,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
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

  Widget _buildSectionChain(int numSections, PlaybackState playbackState,
      {bool allActive = false}) {
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
                  final bool isCurrentSection =
                      allActive || actualIndex == currentSection;
                  return Container(
                    width: squareWidth,
                    height: 15,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: isCurrentSection
                          ? AppColors
                              .sequencerLightText // match buttons icon color
                          : const Color.fromARGB(255, 114, 114,
                              110), // match inactive section settings button bg
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
    Log.i('Recording complete, saving and showing recordings overlay...',
        'SEQUENCER_V2');

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
              Log.d(
                  'MP3 file ready (${size} bytes) after ${attempt + 1} attempts',
                  'SEQUENCER_V2');
              break;
            }
          } catch (e) {
            Log.d('MP3 file not readable yet (attempt ${attempt + 1})',
                'SEQUENCER_V2');
          }
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }

      if (!fileReady) {
        Log.e('MP3 file not ready after waiting', 'SEQUENCER_V2');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Recording saved but audio file not ready. Please wait a moment.'),
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
        Log.e(
            'No active pattern available for checkpoint save', 'SEQUENCER_V2');
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
        audioFilePath: mp3Path, // Use MP3 path instead of WAV
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

      Log.d(
          'Checkpoint saved successfully with audio: $mp3Path', 'SEQUENCER_V2');

      // Show recordings overlay with highlight for new recording
      if (mounted) {
        context.read<AppState>().completeRecordingStepAfterTakeSaved();
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
  final GlobalKey? secondaryAnchorKey;
  final String label;
  final String text;
  final _TutorialTextPosition textPosition;
  final bool centerText;
  final GlobalKey? centerInRectKey;
  final bool drawLayerPointers;
  final int layerPointersCount;

  /// Cubic swipe arrow on the sound grid (no straight coach-mark arrow).
  final bool drawCurvedSwipeHint;

  /// Vertical scroll-down hint on [centerInRectKey] (e.g. sound grid).
  final bool drawVerticalScrollDownHint;

  /// Draw default straight arrow from text card to target.
  final bool drawCoachArrow;

  const _SequencerTutorialAnchorOverlay({
    required this.anchorKey,
    this.secondaryAnchorKey,
    required this.label,
    required this.text,
    this.textPosition = _TutorialTextPosition.center,
    this.centerText = false,
    this.centerInRectKey,
    this.drawLayerPointers = false,
    this.layerPointersCount = 5,
    this.drawCurvedSwipeHint = false,
    this.drawVerticalScrollDownHint = false,
    this.drawCoachArrow = true,
  });

  @override
  State<_SequencerTutorialAnchorOverlay> createState() =>
      _SequencerTutorialAnchorOverlayState();
}

class _SequencerTutorialAnchorOverlayState
    extends State<_SequencerTutorialAnchorOverlay>
    with SingleTickerProviderStateMixin {
  int _layoutTick = 0;
  static const int _maxLayoutWaits = 48;

  /// Largest [sampleGridTutorialKey] rect seen while "Sections swipe" is shown;
  /// keeps the text card fixed when the grid is temporarily smaller (e.g. creation sheet).
  Rect? _lockedSwipeTutorialTextRect;
  late final AnimationController _pulseController;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )
      ..addListener(_onPulseTick)
      ..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut);
  }

  void _onPulseTick() {
    // Keep anchor-driven arrow/spotlight aligned with moving targets
    // (e.g. scrollable VOL/KEY header buttons) while tutorial overlay is visible.
    if (!mounted) return;
    if (!widget.drawCoachArrow) return;
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant _SequencerTutorialAnchorOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.anchorKey != widget.anchorKey ||
        oldWidget.secondaryAnchorKey != widget.secondaryAnchorKey) {
      _layoutTick = 0;
    }
    if (oldWidget.drawCurvedSwipeHint && !widget.drawCurvedSwipeHint) {
      _lockedSwipeTutorialTextRect = null;
    }
    if (oldWidget.drawVerticalScrollDownHint !=
        widget.drawVerticalScrollDownHint) {
      _layoutTick = 0;
    }
  }

  @override
  void dispose() {
    _pulseController.removeListener(_onPulseTick);
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final sectionsCount = context.select((TableState t) => t.sectionsCount);
    final sectionCreationOpen =
        context.select((SectionSettingsState s) => s.isSectionCreationOpen);
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = Size(constraints.maxWidth, constraints.maxHeight);
          final anchorRect =
              _tutorialResolveAnchorRect(widget.anchorKey, viewport);
          final secondaryAnchorRect = widget.secondaryAnchorKey == null
              ? null
              : _tutorialResolveAnchorRect(
                  widget.secondaryAnchorKey!, viewport);
          final rawCenterRect = _tutorialResolveAnchorRect(
            widget.centerInRectKey ?? appState.sampleGridTutorialKey,
            viewport,
          );
          final centerRect = rawCenterRect ??
              Rect.fromCenter(
                center: Offset(viewport.width / 2, viewport.height / 2),
                width: viewport.width,
                height: viewport.height,
              );
          if (widget.drawCurvedSwipeHint && rawCenterRect != null) {
            final area = rawCenterRect.width * rawCenterRect.height;
            final prev = _lockedSwipeTutorialTextRect;
            if (prev == null || area > prev.width * prev.height) {
              _lockedSwipeTutorialTextRect = rawCenterRect;
            }
          }
          final textLayoutRect =
              widget.drawCurvedSwipeHint && _lockedSwipeTutorialTextRect != null
                  ? _lockedSwipeTutorialTextRect!
                  : centerRect;
          final anchorsReady = anchorRect != null &&
              (widget.secondaryAnchorKey == null ||
                  secondaryAnchorRect != null);
          if (!anchorsReady) {
            if (_layoutTick < _maxLayoutWaits) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                setState(() => _layoutTick++);
              });
            }
          }

          final safeTop = MediaQuery.of(context).padding.top + 10;
          final safeBottom = MediaQuery.of(context).padding.bottom;
          final resolvedAnchorRect = anchorRect ?? centerRect;
          final resolvedSecondaryAnchorRect =
              anchorsReady ? secondaryAnchorRect : null;
          final ti = appState.activeTutorialTextInsets;
          // Percent-based edge insets with safety buffer to prevent edge overflow.
          final leftInset =
              max(8.0, (viewport.width * ti.left).floorToDouble());
          final rightInset =
              max(8.0, (viewport.width * ti.right).floorToDouble());
          final topInset = max(0.0, (viewport.height * ti.top).floorToDouble());
          final bottomInset =
              max(0.0, (viewport.height * ti.bottom).floorToDouble());
          final spaceBelowGrid = max(
            0.0,
            viewport.height -
                textLayoutRect.bottom -
                8 -
                bottomInset -
                safeBottom -
                8,
          );
          final availableForCard =
              max(0.0, viewport.width - leftInset - rightInset);
          final textWidth =
              min(272.0, availableForCard * 0.995).floorToDouble();
          final maxCardBodyHeight = max(
            120.0,
            min(
              viewport.height * ti.maxCardHeightFraction,
              viewport.height - safeTop - safeBottom - 16,
            ),
          );
          final position = widget.centerText
              ? _TutorialTextPosition.center
              : widget.textPosition;
          const cardHeightEstimate = 126.0;
          // Step 15 (two samples): tall scrollable card; cap height when using belowGrid
          // or stepControlsGap so the card does not cover edit buttons / stays in the gap.
          final useStep15SamplesLayout = appState.activeTutorialStep ==
                  TutorialStep.sequencerSectionTwoSamplesHint &&
              (position == _TutorialTextPosition.bottom ||
                  position == _TutorialTextPosition.belowGrid ||
                  position == _TutorialTextPosition.stepControlsGap);
          const tutorialCardChromeExcludingBody = 94.0;
          final rawStep15SamplesCardHeight = min(
            viewport.height * 0.92,
            max(
              cardHeightEstimate,
              ti.cardPaddingVertical * 2 +
                  tutorialCardChromeExcludingBody +
                  maxCardBodyHeight,
            ),
          );
          final stepControlsRectForLayout =
              position == _TutorialTextPosition.stepControlsGap
                  ? _tutorialResolveAnchorRect(
                      appState.gridStepRowControlsTutorialKey, viewport)
                  : null;
          final gapHeightCapForStepControls = stepControlsRectForLayout != null
              ? max(
                  100.0,
                  textLayoutRect.bottom -
                      stepControlsRectForLayout.bottom +
                      10.0,
                )
              : null;
          final layoutCardHeight = useStep15SamplesLayout
              ? (position == _TutorialTextPosition.belowGrid
                  ? min(spaceBelowGrid, rawStep15SamplesCardHeight)
                  : position == _TutorialTextPosition.stepControlsGap
                      ? min(
                          gapHeightCapForStepControls ??
                              rawStep15SamplesCardHeight,
                          rawStep15SamplesCardHeight,
                        )
                      : rawStep15SamplesCardHeight)
              : cardHeightEstimate;
          final minL = leftInset;
          final maxL = max(minL, viewport.width - textWidth - rightInset);
          // Absolute top/bottom bounds that account for safe area + percent inset.
          final absoluteMinTop = max(safeTop, safeTop + topInset);
          final absoluteMaxTop = useStep15SamplesLayout
              ? max(
                  absoluteMinTop,
                  viewport.height -
                      layoutCardHeight -
                      bottomInset -
                      safeBottom -
                      8,
                )
              : max(
                  absoluteMinTop,
                  viewport.height - cardHeightEstimate - bottomInset - 8,
                );
          double desiredLeft;
          double desiredTop;
          switch (position) {
            case _TutorialTextPosition.top:
              desiredLeft = textLayoutRect.center.dx - textWidth / 2;
              desiredTop = absoluteMinTop + 6;
              break;
            case _TutorialTextPosition.right:
              desiredLeft = resolvedAnchorRect.right + 12;
              desiredTop =
                  resolvedAnchorRect.center.dy - (layoutCardHeight / 2);
              break;
            case _TutorialTextPosition.center:
              desiredLeft = textLayoutRect.center.dx - textWidth / 2;
              desiredTop = textLayoutRect.center.dy - (layoutCardHeight / 2);
              break;
            case _TutorialTextPosition.bottom:
              desiredLeft = textLayoutRect.center.dx - textWidth / 2;
              desiredTop = viewport.height -
                  layoutCardHeight -
                  bottomInset -
                  safeBottom -
                  8;
              break;
            case _TutorialTextPosition.belowGrid:
              // Sit under the sound grid (sampleGridTutorialKey rect) so +/- row stays tappable.
              desiredLeft = textLayoutRect.center.dx - textWidth / 2;
              desiredTop = textLayoutRect.bottom + 8;
              break;
            case _TutorialTextPosition.stepControlsGap:
              // Between +/- row and bottom of grid container (above edit buttons).
              final gridRect = textLayoutRect;
              final controlsRect = _tutorialResolveAnchorRect(
                  appState.gridStepRowControlsTutorialKey, viewport);
              desiredLeft = gridRect.center.dx - textWidth / 2;
              if (controlsRect != null) {
                const double overlapIntoStepRow = 8.0;
                const double marginAboveGridBottom = 2.0;
                final double maxCardBottom =
                    gridRect.bottom - marginAboveGridBottom;
                var top = controlsRect.bottom - overlapIntoStepRow;
                if (top + layoutCardHeight > maxCardBottom) {
                  top = maxCardBottom - layoutCardHeight;
                }
                final minTop = gridRect.top + 8.0;
                if (top < minTop) {
                  top = minTop;
                }
                desiredTop = top;
              } else {
                desiredTop = gridRect.bottom + 8;
              }
              break;
          }

          final textLeft = (() {
            if (position == _TutorialTextPosition.center) {
              final minAllowedLeft = max(minL, textLayoutRect.left + 8);
              final maxAllowedLeft = max(
                minAllowedLeft,
                min(maxL, textLayoutRect.right - textWidth - 8),
              );
              return desiredLeft
                  .clamp(minAllowedLeft, maxAllowedLeft)
                  .toDouble();
            }
            return desiredLeft.clamp(minL, maxL).toDouble();
          })();

          final textTop = (() {
            if (position == _TutorialTextPosition.center) {
              final minTop = max(absoluteMinTop, textLayoutRect.top + 8);
              final maxTop = min(
                absoluteMaxTop,
                textLayoutRect.bottom - layoutCardHeight - 8,
              );
              return desiredTop.clamp(minTop, max(minTop, maxTop)).toDouble();
            }
            if (position == _TutorialTextPosition.belowGrid) {
              final minTop = max(absoluteMinTop, textLayoutRect.bottom + 8);
              final maxTop = viewport.height -
                  layoutCardHeight -
                  bottomInset -
                  safeBottom -
                  8;
              if (minTop > maxTop) {
                return max(absoluteMinTop, maxTop);
              }
              return desiredTop.clamp(minTop, maxTop).toDouble();
            }
            if (position == _TutorialTextPosition.stepControlsGap) {
              final maxTop = viewport.height -
                  layoutCardHeight -
                  bottomInset -
                  safeBottom -
                  8;
              return desiredTop.clamp(absoluteMinTop, maxTop).toDouble();
            }
            return desiredTop.clamp(absoluteMinTop, absoluteMaxTop).toDouble();
          })();
          final textCenter = Offset(
              textLeft + (textWidth / 2), textTop + (layoutCardHeight / 2));
          final swipeHintTopUpper =
              max(resolvedAnchorRect.top, resolvedAnchorRect.bottom - 12.0);
          final swipeHintTop = (textTop + layoutCardHeight + 8.0)
              .clamp(resolvedAnchorRect.top, swipeHintTopUpper)
              .toDouble();
          final swipeHintRect = Rect.fromLTRB(
              resolvedAnchorRect.left,
              swipeHintTop,
              resolvedAnchorRect.right,
              resolvedAnchorRect.bottom);
          final arrowEnd = _tutorialResolveArrowTarget(
            from: textCenter,
            targetRect: resolvedAnchorRect,
            edgePadding: 4,
          );
          final spotlightRects =
              appState.activeTutorialStep == TutorialStep.sequencerFirstCellHint
                  ? <Rect>[centerRect]
                  : <Rect>[
                      resolvedAnchorRect,
                      if (resolvedSecondaryAnchorRect != null)
                        resolvedSecondaryAnchorRect,
                    ];
          final pulseRects = <Rect>[
            if (_shouldPulseTargetRect(resolvedAnchorRect, viewport))
              resolvedAnchorRect,
            if (resolvedSecondaryAnchorRect != null &&
                _shouldPulseTargetRect(resolvedSecondaryAnchorRect, viewport))
              resolvedSecondaryAnchorRect,
          ];
          final sectionCreateBtnRect = _tutorialResolveAnchorRect(
            appState.sectionCreatePrimaryButtonTutorialKey,
            viewport,
          );
          final swipeSectionCreatePulseRects = <Rect>[
            if (widget.drawCurvedSwipeHint &&
                sectionCreationOpen &&
                sectionCreateBtnRect != null &&
                _shouldPulseSectionCreateTutorialButton(
                    sectionCreateBtnRect, viewport))
              sectionCreateBtnRect,
          ];

          return Stack(
            children: [
              IgnorePointer(
                child: CustomPaint(
                  size: viewport,
                  painter: _TutorialSpotlightPainter(
                    targetRects: spotlightRects,
                    scrimColor: Colors.transparent,
                  ),
                ),
              ),
              if (widget.drawVerticalScrollDownHint &&
                  rawCenterRect != null &&
                  rawCenterRect.width >= 8 &&
                  rawCenterRect.height >= 8)
                IgnorePointer(
                  child: CustomPaint(
                    size: viewport,
                    painter: _VerticalScrollDownHintPainter(
                      targetRect: rawCenterRect,
                      color: AppColors.tutorialArrowColor,
                    ),
                  ),
                ),
              if (widget.drawCoachArrow &&
                  !widget.drawLayerPointers &&
                  !widget.drawCurvedSwipeHint &&
                  anchorsReady)
                IgnorePointer(
                  child: CustomPaint(
                    size: viewport,
                    painter: _TutorialOverlayArrowsPainter(
                      start: textCenter,
                      ends: [
                        arrowEnd,
                        if (resolvedSecondaryAnchorRect != null)
                          _tutorialResolveArrowTarget(
                            from: textCenter,
                            targetRect: resolvedSecondaryAnchorRect,
                            edgePadding: 4,
                          ),
                      ],
                      color: AppColors.tutorialArrowColor,
                    ),
                  ),
                ),
              if (widget.drawCoachArrow &&
                  !widget.drawLayerPointers &&
                  !widget.drawCurvedSwipeHint &&
                  anchorsReady &&
                  pulseRects.isNotEmpty)
                IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, _) {
                      return CustomPaint(
                        size: viewport,
                        painter: _TutorialTargetPulsePainter(
                          targetRects: pulseRects,
                          color: AppColors.tutorialPulseColor,
                          intensity: _pulse.value,
                        ),
                      );
                    },
                  ),
                ),
              if (widget.drawCurvedSwipeHint)
                IgnorePointer(
                  child: CustomPaint(
                    size: viewport,
                    painter: _CurvedSwipeHintPainter(
                      targetRect: swipeHintRect,
                      color: anchorsReady && sectionsCount < 2
                          ? AppColors.tutorialArrowColor
                          : Colors.transparent,
                      leftToRight: true,
                    ),
                  ),
                ),
              if (widget.drawCurvedSwipeHint &&
                  anchorsReady &&
                  swipeSectionCreatePulseRects.isNotEmpty)
                IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, _) {
                      return CustomPaint(
                        size: viewport,
                        painter: _TutorialTargetPulsePainter(
                          targetRects: swipeSectionCreatePulseRects,
                          color: AppColors.tutorialPulseColor,
                          intensity: _pulse.value,
                        ),
                      );
                    },
                  ),
                ),
              if (widget.drawLayerPointers && anchorsReady)
                IgnorePointer(
                  child: CustomPaint(
                    size: viewport,
                    painter: _LayerPointersPainter(
                      targetRect: resolvedAnchorRect,
                      color: AppColors.tutorialArrowColor,
                      count: widget.layerPointersCount,
                    ),
                  ),
                ),
              Positioned(
                left: textLeft,
                top: textTop,
                width: textWidth,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ti.cardPaddingHorizontal,
                    vertical: ti.cardPaddingVertical,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.tutorialTextOverlayColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.sequencerBorder, width: 0.8),
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: maxCardBodyHeight,
                    ),
                    child: SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Text(
                                  widget.label,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: true,
                                  style: const TextStyle(
                                    color: AppColors.sequencerText,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${appState.tutorialStepDisplayIndex}/${AppState.tutorialTotalSteps}',
                                style: const TextStyle(
                                  color: AppColors.sequencerText,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.text,
                            softWrap: true,
                            style: const TextStyle(
                              color: AppColors.sequencerText,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              ElevatedButton(
                                onPressed: appState.goBackTutorialManually,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      AppColors.sequencerSurfaceBase,
                                  foregroundColor: AppColors.sequencerText,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 6),
                                  minimumSize: const Size(0, 0),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(7),
                                  ),
                                ),
                                child: const Text(
                                  'Back',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12),
                                ),
                              ),
                              const SizedBox(width: 6),
                              ElevatedButton(
                                onPressed: appState.stopTutorial,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      AppColors.sequencerSurfaceBase,
                                  foregroundColor: AppColors.sequencerText,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 6),
                                  minimumSize: const Size(0, 0),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(7),
                                  ),
                                ),
                                child: const Text(
                                  'Quit tutorial',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12),
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
            ],
          );
        },
      ),
    );
  }

  bool _shouldPulseTargetRect(Rect rect, Size viewport) {
    final maxW = viewport.width * 0.72;
    final maxH = viewport.height * 0.28;
    return rect.width <= maxW && rect.height <= maxH;
  }
}

/// Full-width primary CTA on section creation page; allow pulse despite wide rect.
bool _shouldPulseSectionCreateTutorialButton(Rect rect, Size viewport) {
  if (rect.width < 8 || rect.height < 8) return false;
  return rect.height <= viewport.height * 0.35;
}

enum _TutorialTextPosition {
  center,
  top,
  right,
  bottom,

  /// Card top sits at [centerInRectKey].bottom + padding (under sound grid).
  belowGrid,

  /// Card in the gap between +/- row and bottom of grid (above edit buttons).
  /// Uses [AppState.gridStepRowControlsTutorialKey] and [centerInRectKey].
  stepControlsGap,
}

Rect? _tutorialResolveAnchorRect(GlobalKey key, Size viewport) {
  final ctx = key.currentContext;
  if (ctx == null) return null;
  try {
    final box = ctx.findRenderObject();
    if (box is! RenderBox) return null;
    if (!box.hasSize || !box.attached) return null;
    final topLeft = box.localToGlobal(Offset.zero);
    return topLeft & box.size;
  } catch (_) {
    // Anchor can briefly be invalid during rebuilds (e.g. sliver children not
    // laid out yet). localToGlobal may throw TypeError, not only FlutterError.
    return null;
  }
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

class _TutorialOverlayArrowsPainter extends CustomPainter {
  final Offset start;
  final List<Offset> ends;
  final Color color;

  _TutorialOverlayArrowsPainter({
    required this.start,
    required this.ends,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    for (final end in ends) {
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
  }

  @override
  bool shouldRepaint(covariant _TutorialOverlayArrowsPainter oldDelegate) {
    return oldDelegate.start != start ||
        oldDelegate.ends != ends ||
        oldDelegate.color != color;
  }
}

class _TutorialSpotlightPainter extends CustomPainter {
  final List<Rect> targetRects;
  final Color scrimColor;

  _TutorialSpotlightPainter({
    required this.targetRects,
    required this.scrimColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPath = Path()..addRect(Offset.zero & size);
    for (final rect in targetRects) {
      final expanded = rect.inflate(6.0);
      overlayPath.addRRect(
        RRect.fromRectAndRadius(expanded, const Radius.circular(8)),
      );
    }
    overlayPath.fillType = PathFillType.evenOdd;

    final paint = Paint()
      ..color = scrimColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(overlayPath, paint);
  }

  @override
  bool shouldRepaint(covariant _TutorialSpotlightPainter oldDelegate) {
    return oldDelegate.targetRects != targetRects ||
        oldDelegate.scrimColor != scrimColor;
  }
}

class _TutorialTargetPulsePainter extends CustomPainter {
  final List<Rect> targetRects;
  final Color color;
  final double intensity;

  _TutorialTargetPulsePainter({
    required this.targetRects,
    required this.color,
    required this.intensity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final t = intensity.clamp(0.0, 1.0);
    for (final rect in targetRects) {
      final expanded = rect.inflate(2.0 + (2.0 * t));
      final rrect = RRect.fromRectAndRadius(expanded, const Radius.circular(7));
      final fill = Paint()
        ..style = PaintingStyle.fill
        ..color = color.withOpacity(0.08 + (0.14 * t));
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = color.withOpacity(0.35 + (0.45 * t));
      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0 + (2.0 * t)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5)
        ..color = color.withOpacity(0.16 + (0.12 * t));

      canvas.drawRRect(rrect, glow);
      canvas.drawRRect(rrect, fill);
      canvas.drawRRect(rrect, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _TutorialTargetPulsePainter oldDelegate) {
    return oldDelegate.targetRects != targetRects ||
        oldDelegate.color != color ||
        oldDelegate.intensity != intensity;
  }
}

/// Curved swipe hint across the sound grid (direction of the page swipe).
class _CurvedSwipeHintPainter extends CustomPainter {
  final Rect targetRect;
  final Color color;
  final bool leftToRight;

  _CurvedSwipeHintPainter({
    required this.targetRect,
    required this.color,
    required this.leftToRight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (targetRect.width < 8 || targetRect.height < 8) return;

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round;

    final w = targetRect.width;
    final h = targetRect.height;
    final midY = targetRect.center.dy;
    final bulge = (h * 0.18).clamp(10.0, 48.0);

    late Offset p0, p1, p2, p3;
    if (leftToRight) {
      p0 = Offset(targetRect.left + w * 0.06, midY);
      p3 = Offset(targetRect.right - w * 0.10, midY);
      p1 = Offset(targetRect.left + w * 0.38, midY - bulge);
      p2 = Offset(targetRect.right - w * 0.38, midY - bulge);
    } else {
      p0 = Offset(targetRect.right - w * 0.06, midY);
      p3 = Offset(targetRect.left + w * 0.10, midY);
      p1 = Offset(targetRect.right - w * 0.38, midY - bulge);
      p2 = Offset(targetRect.left + w * 0.38, midY - bulge);
    }

    final path = Path()
      ..moveTo(p0.dx, p0.dy)
      ..cubicTo(p1.dx, p1.dy, p2.dx, p2.dy, p3.dx, p3.dy);
    canvas.drawPath(path, linePaint);

    final tangent = (p3 - p2) * 3.0;
    final len = tangent.distance;
    final dir =
        len > 0.001 ? tangent / len : Offset(leftToRight ? 1.0 : -1.0, 0.0);
    final angle = dir.direction;
    const arrowLength = 11.0;
    const arrowSpread = 0.55;
    final arrowPath = Path()
      ..moveTo(p3.dx, p3.dy)
      ..lineTo(
        p3.dx - arrowLength * cos(angle - arrowSpread),
        p3.dy - arrowLength * sin(angle - arrowSpread),
      )
      ..moveTo(p3.dx, p3.dy)
      ..lineTo(
        p3.dx - arrowLength * cos(angle + arrowSpread),
        p3.dy - arrowLength * sin(angle + arrowSpread),
      );
    canvas.drawPath(arrowPath, linePaint);
  }

  @override
  bool shouldRepaint(covariant _CurvedSwipeHintPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect ||
        oldDelegate.color != color ||
        oldDelegate.leftToRight != leftToRight;
  }
}

/// Straight vertical scroll-down hint on the sound grid (scroll to reach step +/- row).
class _VerticalScrollDownHintPainter extends CustomPainter {
  final Rect targetRect;
  final Color color;

  _VerticalScrollDownHintPainter({
    required this.targetRect,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (targetRect.width < 8 || targetRect.height < 8) return;

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round;

    final h = targetRect.height;
    final midX = targetRect.center.dx;

    final pTop = Offset(midX, targetRect.top + h * 0.10);
    final pBottom = Offset(midX, targetRect.bottom - h * 0.14);
    canvas.drawLine(pTop, pBottom, linePaint);

    // Arrowhead pointing down (line direction +y).
    const arrowLength = 11.0;
    const arrowSpread = 0.55;
    const angle = pi / 2;
    final arrowPath = Path()
      ..moveTo(pBottom.dx, pBottom.dy)
      ..lineTo(
        pBottom.dx - arrowLength * cos(angle - arrowSpread),
        pBottom.dy - arrowLength * sin(angle - arrowSpread),
      )
      ..moveTo(pBottom.dx, pBottom.dy)
      ..lineTo(
        pBottom.dx - arrowLength * cos(angle + arrowSpread),
        pBottom.dy - arrowLength * sin(angle + arrowSpread),
      );
    canvas.drawPath(arrowPath, linePaint);
  }

  @override
  bool shouldRepaint(covariant _VerticalScrollDownHintPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect || oldDelegate.color != color;
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
      final angle = -pi / 2;
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

/// Tap feedback: [InkWell] + short opacity blink (matches JUMP / section chain).
/// No persistent “selected” fill — use for controls that toggle a multitask panel.
class _SequencerTapBlinkChild extends StatefulWidget {
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final Widget child;

  const _SequencerTapBlinkChild({
    required this.onTap,
    required this.borderRadius,
    required this.child,
  });

  @override
  State<_SequencerTapBlinkChild> createState() =>
      _SequencerTapBlinkChildState();
}

class _SequencerTapBlinkChildState extends State<_SequencerTapBlinkChild>
    with SingleTickerProviderStateMixin {
  late final AnimationController _tapBlinkController;
  late final Animation<double> _tapBlinkOpacity;

  @override
  void initState() {
    super.initState();
    _tapBlinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _tapBlinkOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.38), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.38, end: 1.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.48), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.48, end: 1.0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _tapBlinkController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _tapBlinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: widget.onTap == null
            ? null
            : () {
                HapticFeedback.lightImpact();
                widget.onTap!();
                _tapBlinkController.forward(from: 0);
              },
        borderRadius: widget.borderRadius,
        child: AnimatedBuilder(
          animation: _tapBlinkController,
          builder: (context, __) {
            return Opacity(
              opacity: _tapBlinkOpacity.value,
              child: widget.child,
            );
          },
        ),
      ),
    );
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
            color: (widget.color ?? AppColors.sequencerAccent)
                .withOpacity(_animation.value),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}
