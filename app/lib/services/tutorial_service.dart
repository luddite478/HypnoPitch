import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'reliable_storage.dart';

enum TutorialStep {
  none,
  sequencerFirstCellHint,
  sequencerSelectSampleHint,
  sequencerCellParamsHint,
  sequencerCopyPasteHint,
  sequencerDeleteHint,
  sequencerUndoRedoHint,
  sequencerJumpValueTwoHint,
  sequencerJumpPasteHint,
  sequencerPlaybackHint,
  sequencerRecordingHint,
  sequencerTakesHint,
  sequencerLayersHint,
  sequencerSelectModeHint,
  sequencerSectionsSwipeHint,
  sequencerSectionTwoStepsHint,
  sequencerSectionTwoSamplesHint,
  sequencerSectionsNavigateHint,
  sequencerSectionsMenuHint,
  sequencerSongModeHint,
  sequencerSectionLoopsHint,
  sequencerSongRecordingHint,
  sequencerSecondTakeAddHint,
  sequencerSecondTakeCloseHint,
  sequencerBackToPatternHint,
  sequencerProjectsLibraryHint,
  sequencerLibraryLatestRecordingHint,
}

/// Percent-based padding/inset configuration for the tutorial text card.
///
/// Values are percentages of the overlay viewport:
/// - `left/right` are percentages of viewport width
/// - `top/bottom` are percentages of viewport height
class TutorialTextInsets {
  final double left;
  final double right;
  final double top;
  final double bottom;

  const TutorialTextInsets({
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
  });
}

enum TutorialInteractionTarget {
  firstGridCell,
  sampleGrid,
  selectSampleButton,
  copyButton,
  pasteButton,
  deleteButton,
  undoButton,
  redoButton,
  jumpButton,
  playButton,
  recordButton,
  layerTab,
  layerMuteButton,
  selectModeButton,
  sectionMenuButton,
  songModeButton,
  sectionSettingsButton,
  sectionStepsDecrease,
  sectionStepsIncrease,
  sectionLoopsControl,
  takesPlayButton,
  takesAddButton,
  takesCloseButton,
  recordingsButton,
  patternMenuButton,
  projectsLibraryFolderButton,
  libraryLatestRecordingButton,
  libraryLatestRecordingShareButton,
}

/// Dedicated service that owns first-launch tutorial state machine.
class TutorialService extends ChangeNotifier {
  /// Internal feature switch for tutorial runtime.
  /// Keep disabled until flow/content is finalized.
  static const bool isEnabled = true;
  static const String hasLaunchedBeforeKey = 'app_has_launched_before';
  static const int tutorialTotalSteps = 24;
  static const int minRecordingSecondsForTutorialAdvance = 4;
  static const Duration recordingStepStopPromptDelay = Duration(seconds: 3);
  static const double selectModeVolumeDeltaThreshold = 0.10;
  static const double tutorialCellTargetVolume = 0.8;
  static const int tutorialCellTargetPitchClassDSharp = 3;
  static const Duration tutorialCellParamsAdvanceDelay =
      Duration(seconds: 1);
  static const Duration tutorialJumpValueTwoToPasteDelay =
      Duration(seconds: 1);

  bool _isInitialized = false;
  bool _isFirstLaunchSession = false;
  bool _showTutorialPromptThisSession = false;
  TutorialStep _activeTutorialStep = TutorialStep.none;
  bool _copyActionDone = false;
  bool _cellVolumeAdjusted = false;
  bool _cellPitchAdjusted = false;
  Timer? _cellParamsAdvanceTimer;
  Timer? _jumpValueTwoAdvanceTimer;
  bool _jumpValueSetToTwo = false;
  bool _jumpValueCopyDone = false;
  int _jumpValuePasteCount = 0;
  bool _playbackStarted = false;
  bool _selectModeEntered = false;
  bool _multiSelectDone = false;
  bool _selectModeVolumeAdjusted = false;
  double? _selectModeVolumeBaseline;
  Timer? _recordingReadyToStopTimer;
  bool _recordingPressed = false;
  bool _recordingPlayStarted = false;
  bool _recordingReadyToStop = false;
  bool _recordingStoppedAfterFourSec = false;
  bool _takesPlayDone = false;
  bool _takesAddDone = false;
  bool _layersTabPressed = false;
  bool _layersMutePressed = false;
  bool _layersUnmutePressed = false;
  bool _undoPressed = false;
  bool _redoPressed = false;
  bool _songRecordingPressed = false;
  bool _songRecordingPlayStarted = false;
  bool _songRecordingStopped = false;
  bool _secondTakeAddDone = false;
  bool _secondTakeCloseDone = false;
  bool _libraryLatestRecordingOpened = false;
  bool _libraryLatestRecordingShared = false;

  // Default inset config (matches the previously hardcoded values in
  // sequencer_screen_v2.dart).
  static const double _defaultLeftInsetPercent = 0.2;
  static const double _defaultRightInsetPercent = 0.03;
  static const double _defaultTopInsetPercent = 0.02;
  static const double _defaultBottomInsetPercent = 0.02;
  static const TutorialTextInsets _defaultTextInsets = TutorialTextInsets(
    left: _defaultLeftInsetPercent,
    right: _defaultRightInsetPercent,
    top: _defaultTopInsetPercent,
    bottom: _defaultBottomInsetPercent,
  );

  static const TutorialTextInsets _firstCellTextInsets = _defaultTextInsets;
  static const TutorialTextInsets _selectSampleTextInsets = _defaultTextInsets;
  static const TutorialTextInsets _cellParamsTextInsets = _defaultTextInsets;
  static const TutorialTextInsets _copyPasteTextInsets = _defaultTextInsets;
  static const TutorialTextInsets _deleteTextInsets = _defaultTextInsets;
  static const TutorialTextInsets _undoRedoTextInsets = _defaultTextInsets;
  static const TutorialTextInsets _jumpPasteTextInsets = _defaultTextInsets;
  static const TutorialTextInsets _playbackTextInsets = _defaultTextInsets;
  static const TutorialTextInsets _selectModeTextInsets = _defaultTextInsets;
  static const TutorialTextInsets _recordingTextInsets = _defaultTextInsets;
  static const TutorialTextInsets _takesTextInsets = _defaultTextInsets;
  static const TutorialTextInsets _layersTextInsets = _defaultTextInsets;
  static const TutorialTextInsets _sectionsSwipeTextInsets = _defaultTextInsets;
  static const TutorialTextInsets _sectionTwoStepsTextInsets = _defaultTextInsets;
  static const TutorialTextInsets _sectionTwoSamplesTextInsets = _defaultTextInsets;
  static const TutorialTextInsets _sectionsNavigateTextInsets = _defaultTextInsets;
  static const TutorialTextInsets _sectionsMenuTextInsets = _defaultTextInsets;
  static const TutorialTextInsets _songModeTextInsets = _defaultTextInsets;
  static const TutorialTextInsets _sectionLoopsTextInsets = _defaultTextInsets;
  static const TutorialTextInsets _songRecordingTextInsets = _defaultTextInsets;
  static const TutorialTextInsets _secondTakeAddTextInsets = _defaultTextInsets;
  static const TutorialTextInsets _secondTakeCloseTextInsets = _defaultTextInsets;
  static const TutorialTextInsets _backToPatternTextInsets = _defaultTextInsets;
  static const TutorialTextInsets _projectsLibraryTextInsets = _defaultTextInsets;
  static const TutorialTextInsets _libraryLatestRecordingTextInsets =
      _defaultTextInsets;

  TutorialTextInsets textInsetsForStep(TutorialStep step) {
    switch (step) {
      case TutorialStep.sequencerFirstCellHint:
        return _firstCellTextInsets;
      case TutorialStep.sequencerSelectSampleHint:
        return _selectSampleTextInsets;
      case TutorialStep.sequencerCellParamsHint:
        return _cellParamsTextInsets;
      case TutorialStep.sequencerCopyPasteHint:
        return _copyPasteTextInsets;
      case TutorialStep.sequencerDeleteHint:
        return _deleteTextInsets;
      case TutorialStep.sequencerUndoRedoHint:
        return _undoRedoTextInsets;
      case TutorialStep.sequencerJumpValueTwoHint:
        return _jumpPasteTextInsets;
      case TutorialStep.sequencerJumpPasteHint:
        return _jumpPasteTextInsets;
      case TutorialStep.sequencerPlaybackHint:
        return _playbackTextInsets;
      case TutorialStep.sequencerSelectModeHint:
        return _selectModeTextInsets;
      case TutorialStep.sequencerRecordingHint:
        return _recordingTextInsets;
      case TutorialStep.sequencerTakesHint:
        return _takesTextInsets;
      case TutorialStep.sequencerLayersHint:
        return _layersTextInsets;
      case TutorialStep.sequencerSectionsSwipeHint:
        return _sectionsSwipeTextInsets;
      case TutorialStep.sequencerSectionTwoStepsHint:
        return _sectionTwoStepsTextInsets;
      case TutorialStep.sequencerSectionTwoSamplesHint:
        return _sectionTwoSamplesTextInsets;
      case TutorialStep.sequencerSectionsNavigateHint:
        return _sectionsNavigateTextInsets;
      case TutorialStep.sequencerSectionsMenuHint:
        return _sectionsMenuTextInsets;
      case TutorialStep.sequencerSongModeHint:
        return _songModeTextInsets;
      case TutorialStep.sequencerSectionLoopsHint:
        return _sectionLoopsTextInsets;
      case TutorialStep.sequencerSongRecordingHint:
        return _songRecordingTextInsets;
      case TutorialStep.sequencerSecondTakeAddHint:
        return _secondTakeAddTextInsets;
      case TutorialStep.sequencerSecondTakeCloseHint:
        return _secondTakeCloseTextInsets;
      case TutorialStep.sequencerBackToPatternHint:
        return _backToPatternTextInsets;
      case TutorialStep.sequencerProjectsLibraryHint:
        return _projectsLibraryTextInsets;
      case TutorialStep.sequencerLibraryLatestRecordingHint:
        return _libraryLatestRecordingTextInsets;
      case TutorialStep.none:
        return _defaultTextInsets;
    }
  }

  TutorialTextInsets get activeTutorialTextInsets =>
      textInsetsForStep(_activeTutorialStep);

  final GlobalKey firstCellTutorialKey = GlobalKey();
  final GlobalKey selectSampleTutorialKey = GlobalKey();
  final GlobalKey multitaskPanelTutorialKey = GlobalKey();
  final GlobalKey cellParamsVolumeButtonTutorialKey = GlobalKey();
  final GlobalKey cellParamsKeyButtonTutorialKey = GlobalKey();
  final GlobalKey copyButtonTutorialKey = GlobalKey();
  final GlobalKey pasteButtonTutorialKey = GlobalKey();
  final GlobalKey copyPasteTargetCellTutorialKey = GlobalKey();
  final GlobalKey deleteButtonTutorialKey = GlobalKey();
  final GlobalKey undoButtonTutorialKey = GlobalKey();
  final GlobalKey redoButtonTutorialKey = GlobalKey();
  final GlobalKey jumpButtonTutorialKey = GlobalKey();
  /// The numeric Jump value on the JUMP button (e.g. "2") for tutorial anchoring.
  final GlobalKey jumpValueTwoDisplayTutorialKey = GlobalKey();
  /// Cell to copy from: prefers 0:0 if it has a sample, else first occupied cell.
  final GlobalKey jumpPasteSourceCellTutorialKey = GlobalKey();
  /// Paste destination for first paste after copy (row 3, col 0).
  final GlobalKey jumpPasteTargetCellTutorialKey = GlobalKey();
  final GlobalKey playButtonTutorialKey = GlobalKey();
  final GlobalKey recordButtonTutorialKey = GlobalKey();
  final GlobalKey takesPlayButtonTutorialKey = GlobalKey();
  final GlobalKey takesAddButtonTutorialKey = GlobalKey();
  final GlobalKey takesCloseButtonTutorialKey = GlobalKey();
  final GlobalKey layerTabTutorialKey = GlobalKey();
  final GlobalKey layerMuteButtonTutorialKey = GlobalKey();
  final GlobalKey layersRowTutorialKey = GlobalKey();
  final GlobalKey selectModeButtonTutorialKey = GlobalKey();
  final GlobalKey sampleGridTutorialKey = GlobalKey();
  final GlobalKey sectionMenuButtonTutorialKey = GlobalKey();
  final GlobalKey songModeButtonTutorialKey = GlobalKey();
  final GlobalKey sectionSettingsButtonTutorialKey = GlobalKey();
  final GlobalKey sectionStepsDecreaseTutorialKey = GlobalKey();
  final GlobalKey sectionStepsIncreaseTutorialKey = GlobalKey();
  final GlobalKey patternMenuButtonTutorialKey = GlobalKey();
  final GlobalKey projectsLibraryFolderTutorialKey = GlobalKey();
  final GlobalKey libraryLatestRecordingTutorialKey = GlobalKey();
  final GlobalKey libraryLatestRecordingShareTutorialKey = GlobalKey();

  bool get isInitialized => _isInitialized;
  bool get isFirstLaunchSession => _isFirstLaunchSession;
  bool get showTutorialPromptThisSession => _showTutorialPromptThisSession;
  TutorialStep get activeTutorialStep => _activeTutorialStep;
  bool get isTutorialRunning => _activeTutorialStep != TutorialStep.none;
  bool get showCellParamsVolumePointer =>
      _activeTutorialStep == TutorialStep.sequencerCellParamsHint &&
      !_cellVolumeAdjusted;
  bool get showCellParamsKeyPointer =>
      _activeTutorialStep == TutorialStep.sequencerCellParamsHint &&
      _cellVolumeAdjusted &&
      !_cellPitchAdjusted;
  bool get showCopyPointer =>
      _activeTutorialStep == TutorialStep.sequencerCopyPasteHint &&
      !_copyActionDone;
  bool get showPastePointer =>
      _activeTutorialStep == TutorialStep.sequencerCopyPasteHint &&
      _copyActionDone;
  bool get showJumpValueTwoPointer =>
      _activeTutorialStep == TutorialStep.sequencerJumpValueTwoHint;
  bool get showJumpCopyPointer =>
      _activeTutorialStep == TutorialStep.sequencerJumpPasteHint &&
      _jumpValueSetToTwo &&
      !_jumpValueCopyDone;
  bool get showJumpPastePointer =>
      _activeTutorialStep == TutorialStep.sequencerJumpPasteHint &&
      _jumpValueSetToTwo &&
      _jumpValueCopyDone &&
      _jumpValuePasteCount < 3;
  /// First paste after copy: highlight cell 3:0 and Paste.
  bool get showJumpPasteTargetCellPointer =>
      _activeTutorialStep == TutorialStep.sequencerJumpPasteHint &&
      _jumpValueSetToTwo &&
      _jumpValueCopyDone &&
      _jumpValuePasteCount == 0;
  /// Pastes 2–3: highlight Paste only.
  bool get showJumpPasteButtonOnlyPointer =>
      _activeTutorialStep == TutorialStep.sequencerJumpPasteHint &&
      _jumpValueSetToTwo &&
      _jumpValueCopyDone &&
      _jumpValuePasteCount >= 1 &&
      _jumpValuePasteCount < 3;
  bool get showRecordingRecordPointer =>
      _activeTutorialStep == TutorialStep.sequencerRecordingHint &&
      (!_recordingPressed || _recordingReadyToStop);
  bool get showRecordingPlayPointer =>
      _activeTutorialStep == TutorialStep.sequencerRecordingHint &&
      _recordingPressed &&
      !_recordingReadyToStop;
  /// Song-mode recording: point at Record only until Record is pressed; then Play/Stop.
  bool get showSongRecordingRecordPointer =>
      _activeTutorialStep == TutorialStep.sequencerSongRecordingHint &&
      !_songRecordingPressed;
  bool get showSelectModeButtonPointer =>
      _activeTutorialStep == TutorialStep.sequencerSelectModeHint &&
      (!_selectModeEntered || _selectModeVolumeAdjusted);
  bool get showSelectModeVolumePointer =>
      _activeTutorialStep == TutorialStep.sequencerSelectModeHint &&
      _selectModeEntered &&
      _multiSelectDone &&
      !_selectModeVolumeAdjusted;
  String get tutorialStepLabel {
    switch (_activeTutorialStep) {
      case TutorialStep.sequencerFirstCellHint:
      case TutorialStep.sequencerSelectSampleHint:
        return 'Select sample';
      case TutorialStep.sequencerCellParamsHint:
        return 'Cell params';
      case TutorialStep.sequencerCopyPasteHint:
        return 'Copy paste';
      case TutorialStep.sequencerDeleteHint:
        return 'Delete';
      case TutorialStep.sequencerUndoRedoHint:
        return 'Undo redo';
      case TutorialStep.sequencerJumpValueTwoHint:
        return 'Jump value';
      case TutorialStep.sequencerJumpPasteHint:
        return 'Jump paste';
      case TutorialStep.sequencerPlaybackHint:
        return 'Playback';
      case TutorialStep.sequencerSelectModeHint:
        return 'Select mode';
      case TutorialStep.sequencerRecordingHint:
        return 'Recording';
      case TutorialStep.sequencerTakesHint:
        return 'Takes';
      case TutorialStep.sequencerLayersHint:
        return 'Layers';
      case TutorialStep.sequencerSectionsSwipeHint:
        return 'Sections swipe';
      case TutorialStep.sequencerSectionTwoStepsHint:
        return 'Section 2 steps';
      case TutorialStep.sequencerSectionTwoSamplesHint:
        return 'Section 2 samples';
      case TutorialStep.sequencerSectionsNavigateHint:
        return 'Navigate sections';
      case TutorialStep.sequencerSectionsMenuHint:
        return 'Section menu';
      case TutorialStep.sequencerSongModeHint:
        return 'Song mode';
      case TutorialStep.sequencerSectionLoopsHint:
        return 'Section loops';
      case TutorialStep.sequencerSongRecordingHint:
        return 'Song recording';
      case TutorialStep.sequencerSecondTakeAddHint:
        return 'Second take';
      case TutorialStep.sequencerSecondTakeCloseHint:
        return 'Second take';
      case TutorialStep.sequencerBackToPatternHint:
        return 'Pattern menu';
      case TutorialStep.sequencerProjectsLibraryHint:
        return 'Library folder';
      case TutorialStep.sequencerLibraryLatestRecordingHint:
        return 'Library overview';
      case TutorialStep.none:
        return 'Tutorial';
    }
  }

  int get tutorialStepDisplayIndex {
    switch (_activeTutorialStep) {
      case TutorialStep.sequencerFirstCellHint:
        return 1;
      case TutorialStep.sequencerSelectSampleHint:
        return 1;
      case TutorialStep.sequencerCellParamsHint:
        return 2;
      case TutorialStep.sequencerCopyPasteHint:
        return 3;
      case TutorialStep.sequencerDeleteHint:
        return 4;
      case TutorialStep.sequencerUndoRedoHint:
        return 5;
      case TutorialStep.sequencerJumpValueTwoHint:
        return 6;
      case TutorialStep.sequencerJumpPasteHint:
        return 7;
      case TutorialStep.sequencerPlaybackHint:
        return 8;
      case TutorialStep.sequencerSelectModeHint:
        return 9;
      case TutorialStep.sequencerRecordingHint:
        return 10;
      case TutorialStep.sequencerTakesHint:
        return 11;
      case TutorialStep.sequencerLayersHint:
        return 12;
      case TutorialStep.sequencerSectionsSwipeHint:
        return 13;
      case TutorialStep.sequencerSectionTwoStepsHint:
        return 14;
      case TutorialStep.sequencerSectionTwoSamplesHint:
        return 15;
      case TutorialStep.sequencerSectionsNavigateHint:
        return 17;
      case TutorialStep.sequencerSectionsMenuHint:
        return 16;
      case TutorialStep.sequencerSongModeHint:
        return 18;
      case TutorialStep.sequencerSectionLoopsHint:
        return 19;
      case TutorialStep.sequencerSongRecordingHint:
        return 20;
      case TutorialStep.sequencerSecondTakeAddHint:
        return 21;
      case TutorialStep.sequencerSecondTakeCloseHint:
        return 21;
      case TutorialStep.sequencerBackToPatternHint:
        return 22;
      case TutorialStep.sequencerProjectsLibraryHint:
        return 23;
      case TutorialStep.sequencerLibraryLatestRecordingHint:
        return 24;
      case TutorialStep.none:
        return 0;
    }
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    if (!isEnabled) {
      _isFirstLaunchSession = false;
      _showTutorialPromptThisSession = false;
      _activeTutorialStep = TutorialStep.none;
      _isInitialized = true;
      notifyListeners();
      return;
    }

    final hasLaunchedBefore = await ReliableStorage.getBool(
      hasLaunchedBeforeKey,
      defaultValue: false,
    );

    _isFirstLaunchSession = !hasLaunchedBefore;
    _showTutorialPromptThisSession = !hasLaunchedBefore;

    if (!hasLaunchedBefore) {
      await ReliableStorage.setBool(hasLaunchedBeforeKey, true);
    }

    _isInitialized = true;
    notifyListeners();
  }

  void dismissTutorialPromptForSession() {
    if (!isEnabled) return;
    if (!_showTutorialPromptThisSession) return;
    _showTutorialPromptThisSession = false;
    notifyListeners();
  }

  void startSequencerQuickTutorial() {
    if (!isEnabled) return;
    _showTutorialPromptThisSession = false;
    _setActiveStep(TutorialStep.sequencerFirstCellHint);
  }

  void advanceTutorialToSelectSample() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerFirstCellHint) return;
    _setActiveStep(TutorialStep.sequencerSelectSampleHint);
  }

  void completeSampleSelectionStep() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerSelectSampleHint) return;
    _setActiveStep(TutorialStep.sequencerCellParamsHint);
  }

  void markCellVolumeAdjusted(double value) {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerCellParamsHint) return;
    final reached = (value - tutorialCellTargetVolume).abs() <= 0.02;
    if (_cellVolumeAdjusted == reached) return;
    _cellVolumeAdjusted = reached;
    _tryCompleteCellParamsStep();
  }

  void markCellPitchAdjusted(num semitones) {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerCellParamsHint) return;
    final rounded = semitones.round();
    final pitchClass = ((rounded % 12) + 12) % 12;
    final reached = pitchClass == tutorialCellTargetPitchClassDSharp;
    if (_cellPitchAdjusted == reached) return;
    _cellPitchAdjusted = reached;
    _tryCompleteCellParamsStep();
  }

  void _tryCompleteCellParamsStep() {
    if (_activeTutorialStep != TutorialStep.sequencerCellParamsHint) return;
    if (_cellVolumeAdjusted && _cellPitchAdjusted) {
      _cellParamsAdvanceTimer?.cancel();
      _cellParamsAdvanceTimer = Timer(tutorialCellParamsAdvanceDelay, () {
        if (_activeTutorialStep != TutorialStep.sequencerCellParamsHint) return;
        if (!_cellVolumeAdjusted || !_cellPitchAdjusted) return;
        _setActiveStep(TutorialStep.sequencerCopyPasteHint);
      });
    } else {
      _cellParamsAdvanceTimer?.cancel();
      notifyListeners();
    }
  }

  void markCopyAction() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerCopyPasteHint) return;
    if (_copyActionDone) return;
    _copyActionDone = true;
    notifyListeners();
  }

  void markPasteAction() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerCopyPasteHint) return;
    if (!_copyActionDone) return;
    _setActiveStep(TutorialStep.sequencerDeleteHint);
  }

  void verifyDeletionStep() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerDeleteHint) return;
    _setActiveStep(TutorialStep.sequencerUndoRedoHint);
  }

  bool get isUndoDone => _undoPressed;
  bool get isRedoDone => _redoPressed;

  void markUndoAction() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerUndoRedoHint) return;
    if (_undoPressed) return;
    _undoPressed = true;
    notifyListeners();
  }

  void markRedoAction() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerUndoRedoHint) return;
    if (!_undoPressed) return;
    if (_redoPressed) return;
    _redoPressed = true;
    _setActiveStep(TutorialStep.sequencerJumpValueTwoHint);
  }

  void markJumpAction() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerJumpPasteHint &&
        _activeTutorialStep != TutorialStep.sequencerJumpValueTwoHint) {
      return;
    }
    notifyListeners();
  }

  void markJumpValueSetToTwo() {
    if (!isEnabled) return;
    if (_activeTutorialStep == TutorialStep.sequencerJumpValueTwoHint) {
      if (_jumpValueTwoAdvanceTimer?.isActive ?? false) {
        return;
      }
      _jumpValueTwoAdvanceTimer?.cancel();
      _jumpValueTwoAdvanceTimer =
          Timer(tutorialJumpValueTwoToPasteDelay, () {
        _jumpValueTwoAdvanceTimer = null;
        if (_activeTutorialStep != TutorialStep.sequencerJumpValueTwoHint) {
          return;
        }
        _setActiveStep(
          TutorialStep.sequencerJumpPasteHint,
          enterJumpPasteWithJumpAtTwo: true,
        );
      });
      return;
    }
    if (_activeTutorialStep != TutorialStep.sequencerJumpPasteHint) return;
    if (_jumpValueSetToTwo) return;
    _jumpValueSetToTwo = true;
    _tryCompleteJumpValuePasteStep();
  }

  void markJumpValueCopyAction() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerJumpPasteHint) return;
    if (!_jumpValueSetToTwo) return;
    if (_jumpValueCopyDone) return;
    _jumpValueCopyDone = true;
    notifyListeners();
  }

  void markJumpValuePasteAction() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerJumpPasteHint) return;
    if (!_jumpValueSetToTwo || !_jumpValueCopyDone) return;
    _jumpValuePasteCount += 1;
    _tryCompleteJumpValuePasteStep();
  }

  void _tryCompleteJumpValuePasteStep() {
    if (_activeTutorialStep != TutorialStep.sequencerJumpPasteHint) return;
    if (_jumpValueSetToTwo && _jumpValuePasteCount >= 3) {
      _setActiveStep(TutorialStep.sequencerPlaybackHint);
    } else {
      notifyListeners();
    }
  }

  void markPlayAction() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerPlaybackHint) return;
    if (_playbackStarted) return;
    _playbackStarted = true;
    notifyListeners();
  }

  void markStopAction() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerPlaybackHint) return;
    if (!_playbackStarted) return;
    _setActiveStep(TutorialStep.sequencerSelectModeHint);
  }

  void completeLayersInfoStep() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerLayersHint) return;
    if (!_layersTabPressed || !_layersMutePressed || !_layersUnmutePressed) {
      return;
    }
    _setActiveStep(TutorialStep.sequencerSectionsSwipeHint);
  }

  bool get isLayersTabDone => _layersTabPressed;
  bool get isLayersMuteDone => _layersMutePressed;
  bool get isLayersUnmuteDone => _layersUnmutePressed;

  void markLayersTabAction() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerLayersHint) return;
    if (_layersTabPressed) return;
    _layersTabPressed = true;
    notifyListeners();
  }

  void markLayersMuteToggleAction({required bool isMutedAfterToggle}) {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerLayersHint) return;
    if (!_layersTabPressed) return;
    if (isMutedAfterToggle && !_layersMutePressed) {
      _layersMutePressed = true;
      notifyListeners();
      return;
    }
    if (!isMutedAfterToggle && _layersMutePressed && !_layersUnmutePressed) {
      _layersUnmutePressed = true;
      completeLayersInfoStep();
      return;
    }
    notifyListeners();
  }

  void markRecordingAction() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerRecordingHint) return;
    if (_recordingPressed) return;
    _recordingPressed = true;
    _recordingPlayStarted = false;
    _recordingReadyToStop = false;
    _recordingReadyToStopTimer?.cancel();
    notifyListeners();
  }

  void markRecordingPlayAction() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerRecordingHint) return;
    if (!_recordingPressed) return;
    if (_recordingPlayStarted) return;
    _recordingPlayStarted = true;
    _recordingReadyToStop = false;
    _recordingReadyToStopTimer?.cancel();
    _recordingReadyToStopTimer = Timer(recordingStepStopPromptDelay, () {
      if (_activeTutorialStep != TutorialStep.sequencerRecordingHint) return;
      if (!_recordingPressed) return;
      _recordingReadyToStop = true;
      notifyListeners();
    });
    notifyListeners();
  }

  void markRecordingStopAction({required Duration recordingDuration}) {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerRecordingHint) return;
    if (!_recordingPressed) return;
    if (_recordingStoppedAfterFourSec) return;
    if (recordingDuration.inSeconds < minRecordingSecondsForTutorialAdvance) {
      // Keep user on this step until a sufficiently long recording is finished.
      notifyListeners();
      return;
    }
    _recordingStoppedAfterFourSec = true;
    notifyListeners();
  }

  void completeRecordingStepAfterTakeSaved() {
    if (!isEnabled) return;
    if (_activeTutorialStep == TutorialStep.sequencerRecordingHint) {
      if (!_recordingPressed || !_recordingStoppedAfterFourSec) return;
      _setActiveStep(TutorialStep.sequencerTakesHint);
      return;
    }
    if (_activeTutorialStep == TutorialStep.sequencerSongRecordingHint) {
      if (!_songRecordingPressed || !_songRecordingPlayStarted) {
        return;
      }
      // In song mode recording can stop automatically when playback finishes.
      // Treat the saved take as a completed stop and continue with takes instructions.
      if (!_songRecordingStopped) {
        _songRecordingStopped = true;
      }
      // Keep the same step and continue with in-step subparts:
      // 1) add newly recorded song take to library
      // 2) close takes menu
      notifyListeners();
    }
  }

  void markTakesPlayAction({required Duration listenedDuration}) {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerTakesHint) return;
    if (_takesPlayDone) return;
    if (listenedDuration.inMilliseconds < 2000) {
      notifyListeners();
      return;
    }
    _takesPlayDone = true;
    notifyListeners();
  }

  void markTakesAddToLibraryAction() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerTakesHint) return;
    if (!_takesPlayDone) return;
    if (_takesAddDone) return;
    _takesAddDone = true;
    notifyListeners();
  }

  int get takesStepPartIndex {
    if (_activeTutorialStep != TutorialStep.sequencerTakesHint) return 0;
    if (!_takesPlayDone) return 1;
    if (!_takesAddDone) return 2;
    return 3;
  }

  String get takesStepInstruction {
    if (_activeTutorialStep != TutorialStep.sequencerTakesHint) {
      return 'Takes';
    }
    switch (takesStepPartIndex) {
      case 1:
        return 'After recording you are always navigated to takes menu.Press Play and listen to the take.';
      case 2:
        return 'Now add this take to your library.';
      case 3:
        return 'Now close the Takes menu.';
      default:
        return 'Takes';
    }
  }

  bool get showTakesPlayPointer =>
      _activeTutorialStep == TutorialStep.sequencerTakesHint && !_takesPlayDone;
  bool get showTakesAddPointer =>
      _activeTutorialStep == TutorialStep.sequencerTakesHint &&
      _takesPlayDone &&
      !_takesAddDone;
  bool get showTakesClosePointer =>
      _activeTutorialStep == TutorialStep.sequencerTakesHint &&
      _takesPlayDone &&
      _takesAddDone;

  bool get canCloseTakesTutorialStep => _takesPlayDone && _takesAddDone;
  bool get showSecondTakeAddPointer =>
      _activeTutorialStep == TutorialStep.sequencerSongRecordingHint &&
      _songRecordingStopped &&
      !_secondTakeAddDone;
  bool get showSecondTakeClosePointer =>
      _activeTutorialStep == TutorialStep.sequencerSongRecordingHint &&
      _songRecordingStopped &&
      _secondTakeAddDone &&
      !_secondTakeCloseDone;
  bool get canCloseSecondTakeTutorialStep =>
      _songRecordingStopped && _secondTakeAddDone;
  String get secondTakeStepInstruction {
    if (_activeTutorialStep == TutorialStep.sequencerSongRecordingHint &&
        _songRecordingStopped &&
        !_secondTakeAddDone) {
      return 'Now you have a new take made from 2 sections. Add it to your library too.';
    }
    if (_activeTutorialStep == TutorialStep.sequencerSongRecordingHint &&
        _songRecordingStopped &&
        _secondTakeAddDone &&
        !_secondTakeCloseDone) {
      return 'Now close the Takes menu again.';
    }
    return 'Second take';
  }

  bool get showLibraryLatestRecordingPointer =>
      _activeTutorialStep == TutorialStep.sequencerLibraryLatestRecordingHint &&
      !_libraryLatestRecordingOpened;
  bool get showLibraryLatestRecordingSharePointer =>
      _activeTutorialStep == TutorialStep.sequencerLibraryLatestRecordingHint &&
      _libraryLatestRecordingOpened &&
      !_libraryLatestRecordingShared;

  String get libraryLatestRecordingStepInstruction {
    if (_activeTutorialStep != TutorialStep.sequencerLibraryLatestRecordingHint) {
      return 'Library overview';
    }
    if (!_libraryLatestRecordingOpened) {
      return "Library overview\nIn the library, you can access takes you've added before in the Recordings tab, and browse or add your own samples.\nNavigate to the Recordings tab now.";
    }
    if (!_libraryLatestRecordingShared) {
      return 'Now you can share/save your song.';
    }
    return 'Thank you for downloading the app. Feel free to experiment more. Our tutorial ends here.';
  }

  void verifyTakesCloseStep() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerTakesHint) return;
    if (!_takesPlayDone || !_takesAddDone) return;
    _setActiveStep(TutorialStep.sequencerLayersHint);
  }

  String get selectModeStepInstruction {
    if (_activeTutorialStep != TutorialStep.sequencerSelectModeHint) {
      return 'Press Select, choose multiple cells, change selected cells volume by at least 10%, then disable Select mode.';
    }
    if (!_selectModeEntered) {
      return 'Press Select.';
    }
    if (!_multiSelectDone) {
      return 'Select multiple sample cells by dragging your finger.';
    }
    if (!_selectModeVolumeAdjusted) {
      return 'Change volume of selected cells by at least 10%.';
    }
    return 'Now disable Select mode by pressing Select again.';
  }

  void completeSelectModeInfoStep() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerSelectModeHint) return;
    if (_selectModeEntered) return;
    _selectModeEntered = true;
    notifyListeners();
  }

  void verifyMultiSelectStep() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerSelectModeHint) return;
    if (_multiSelectDone) return;
    _multiSelectDone = true;
    notifyListeners();
  }

  void markSelectModeVolumeChanged(double value) {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerSelectModeHint) return;
    if (!_selectModeEntered || !_multiSelectDone) return;

    _selectModeVolumeBaseline ??= value;
    if (_selectModeVolumeAdjusted) return;

    final baseline = _selectModeVolumeBaseline ?? value;
    final delta = (value - baseline).abs();
    if (delta >= selectModeVolumeDeltaThreshold) {
      _selectModeVolumeAdjusted = true;
    }
    notifyListeners();
  }

  void verifyDisableSelectModeStep() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerSelectModeHint) return;
    if (!_selectModeEntered || !_multiSelectDone || !_selectModeVolumeAdjusted) {
      return;
    }
    _setActiveStep(TutorialStep.sequencerRecordingHint);
  }

  /// Second section exists (swipe / create verified via [TableState.sectionsCount]).
  void verifySecondSectionCreated() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerSectionsSwipeHint) return;
    _setActiveStep(TutorialStep.sequencerSectionTwoStepsHint);
  }

  void verifySectionTwoStepsSetToThirtyTwoStep() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerSectionTwoStepsHint) {
      return;
    }
    _setActiveStep(TutorialStep.sequencerSectionTwoSamplesHint);
  }

  void verifySectionTwoFiveSamplesStep() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerSectionTwoSamplesHint) {
      return;
    }
    _setActiveStep(TutorialStep.sequencerSectionsMenuHint);
  }

  void verifyNavigatedToPreviousSectionStep() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerSectionsNavigateHint) {
      return;
    }
    _setActiveStep(TutorialStep.sequencerSongModeHint);
  }

  void completeSectionMenuTutorialStep() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerSectionsMenuHint) return;
    _setActiveStep(TutorialStep.sequencerSectionsNavigateHint);
  }

  void verifySongModeEnabledStep() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerSongModeHint) return;
    _setActiveStep(TutorialStep.sequencerSectionLoopsHint);
  }

  void verifyAnySectionLoopSetToFiveStep() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerSectionLoopsHint) return;
    _setActiveStep(TutorialStep.sequencerSongRecordingHint);
  }

  void markSongRecordingAction() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerSongRecordingHint) return;
    if (_songRecordingPressed) return;
    _songRecordingPressed = true;
    notifyListeners();
  }

  void markSongRecordingPlayAction() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerSongRecordingHint) return;
    if (_songRecordingPlayStarted) return;
    _songRecordingPlayStarted = true;
    notifyListeners();
  }

  void markSongRecordingStopAction({
    required Duration recordingDuration,
    required int sectionsCount,
    required bool isSongMode,
  }) {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerSongRecordingHint) return;
    if (!_songRecordingPressed || !_songRecordingPlayStarted) return;
    if (!isSongMode || sectionsCount < 2 || recordingDuration.inSeconds < 4) {
      notifyListeners();
      return;
    }
    _songRecordingStopped = true;
    notifyListeners();
  }

  void markSecondTakeAddToLibraryAction() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerSongRecordingHint) return;
    if (!_songRecordingStopped) return;
    if (_secondTakeAddDone) return;
    _secondTakeAddDone = true;
    notifyListeners();
  }

  void markSecondTakeCloseAction() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerSongRecordingHint) return;
    if (!_songRecordingStopped) return;
    if (!_secondTakeAddDone) return;
    if (_secondTakeCloseDone) return;
    _secondTakeCloseDone = true;
    _setActiveStep(TutorialStep.sequencerBackToPatternHint);
  }

  void markPatternMenuBackAction() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerBackToPatternHint) return;
    _setActiveStep(TutorialStep.sequencerProjectsLibraryHint);
  }

  void markProjectsLibraryFolderOpenAction() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerProjectsLibraryHint) return;
    _setActiveStep(TutorialStep.sequencerLibraryLatestRecordingHint);
  }

  void markLibraryLatestRecordingOpenAction() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerLibraryLatestRecordingHint) {
      return;
    }
    if (_libraryLatestRecordingOpened) return;
    _libraryLatestRecordingOpened = true;
    notifyListeners();
  }

  void markLibraryLatestRecordingShareAction() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerLibraryLatestRecordingHint) {
      return;
    }
    if (!_libraryLatestRecordingOpened || _libraryLatestRecordingShared) return;
    _libraryLatestRecordingShared = true;
    notifyListeners();
  }

  void advanceTutorialManually() {
    if (!isEnabled) return;
    switch (_activeTutorialStep) {
      case TutorialStep.sequencerFirstCellHint:
        _setActiveStep(TutorialStep.sequencerSelectSampleHint);
        break;
      case TutorialStep.sequencerSelectSampleHint:
        _setActiveStep(TutorialStep.sequencerCellParamsHint);
        break;
      case TutorialStep.sequencerCellParamsHint:
        _setActiveStep(TutorialStep.sequencerCopyPasteHint);
        break;
      case TutorialStep.sequencerCopyPasteHint:
        _setActiveStep(TutorialStep.sequencerDeleteHint);
        break;
      case TutorialStep.sequencerDeleteHint:
        _setActiveStep(TutorialStep.sequencerUndoRedoHint);
        break;
      case TutorialStep.sequencerUndoRedoHint:
        _setActiveStep(TutorialStep.sequencerJumpValueTwoHint);
        break;
      case TutorialStep.sequencerJumpValueTwoHint:
        _setActiveStep(TutorialStep.sequencerJumpPasteHint);
        break;
      case TutorialStep.sequencerJumpPasteHint:
        _setActiveStep(TutorialStep.sequencerPlaybackHint);
        break;
      case TutorialStep.sequencerPlaybackHint:
        _setActiveStep(TutorialStep.sequencerSelectModeHint);
        break;
      case TutorialStep.sequencerSelectModeHint:
        _setActiveStep(TutorialStep.sequencerRecordingHint);
        break;
      case TutorialStep.sequencerRecordingHint:
        _setActiveStep(TutorialStep.sequencerTakesHint);
        break;
      case TutorialStep.sequencerTakesHint:
        _setActiveStep(TutorialStep.sequencerLayersHint);
        break;
      case TutorialStep.sequencerLayersHint:
        _setActiveStep(TutorialStep.sequencerSectionsSwipeHint);
        break;
      case TutorialStep.sequencerSectionsSwipeHint:
        _setActiveStep(TutorialStep.sequencerSectionTwoStepsHint);
        break;
      case TutorialStep.sequencerSectionTwoStepsHint:
        _setActiveStep(TutorialStep.sequencerSectionTwoSamplesHint);
        break;
      case TutorialStep.sequencerSectionTwoSamplesHint:
        _setActiveStep(TutorialStep.sequencerSectionsMenuHint);
        break;
      case TutorialStep.sequencerSectionsNavigateHint:
        _setActiveStep(TutorialStep.sequencerSongModeHint);
        break;
      case TutorialStep.sequencerSectionsMenuHint:
        _setActiveStep(TutorialStep.sequencerSectionsNavigateHint);
        break;
      case TutorialStep.sequencerSongModeHint:
        _setActiveStep(TutorialStep.sequencerSectionLoopsHint);
        break;
      case TutorialStep.sequencerSectionLoopsHint:
        _setActiveStep(TutorialStep.sequencerSongRecordingHint);
        break;
      case TutorialStep.sequencerSongRecordingHint:
        _setActiveStep(TutorialStep.sequencerBackToPatternHint);
        break;
      case TutorialStep.sequencerSecondTakeAddHint:
        _setActiveStep(TutorialStep.sequencerSecondTakeCloseHint);
        break;
      case TutorialStep.sequencerSecondTakeCloseHint:
        _setActiveStep(TutorialStep.sequencerBackToPatternHint);
        break;
      case TutorialStep.sequencerBackToPatternHint:
        _setActiveStep(TutorialStep.sequencerProjectsLibraryHint);
        break;
      case TutorialStep.sequencerProjectsLibraryHint:
        _setActiveStep(TutorialStep.sequencerLibraryLatestRecordingHint);
        break;
      case TutorialStep.sequencerLibraryLatestRecordingHint:
        stopTutorial();
        break;
      case TutorialStep.none:
        break;
    }
  }

  void goBackTutorialManually() {
    if (!isEnabled) return;
    switch (_activeTutorialStep) {
      case TutorialStep.sequencerFirstCellHint:
        _activeTutorialStep = TutorialStep.none;
        _showTutorialPromptThisSession = true;
        notifyListeners();
        break;
      case TutorialStep.sequencerSelectSampleHint:
        _setActiveStep(TutorialStep.sequencerFirstCellHint);
        break;
      case TutorialStep.sequencerCellParamsHint:
        _setActiveStep(TutorialStep.sequencerSelectSampleHint);
        break;
      case TutorialStep.sequencerCopyPasteHint:
        _setActiveStep(TutorialStep.sequencerCellParamsHint);
        break;
      case TutorialStep.sequencerDeleteHint:
        _setActiveStep(TutorialStep.sequencerCopyPasteHint);
        break;
      case TutorialStep.sequencerJumpPasteHint:
        _setActiveStep(TutorialStep.sequencerJumpValueTwoHint);
        break;
      case TutorialStep.sequencerJumpValueTwoHint:
        _setActiveStep(TutorialStep.sequencerUndoRedoHint);
        break;
      case TutorialStep.sequencerUndoRedoHint:
        _setActiveStep(TutorialStep.sequencerDeleteHint);
        break;
      case TutorialStep.sequencerPlaybackHint:
        _setActiveStep(TutorialStep.sequencerJumpPasteHint);
        break;
      case TutorialStep.sequencerSelectModeHint:
        _setActiveStep(TutorialStep.sequencerPlaybackHint);
        break;
      case TutorialStep.sequencerRecordingHint:
        _setActiveStep(TutorialStep.sequencerSelectModeHint);
        break;
      case TutorialStep.sequencerTakesHint:
        _setActiveStep(TutorialStep.sequencerRecordingHint);
        break;
      case TutorialStep.sequencerLayersHint:
        _setActiveStep(TutorialStep.sequencerTakesHint);
        break;
      case TutorialStep.sequencerSectionsSwipeHint:
        _setActiveStep(TutorialStep.sequencerLayersHint);
        break;
      case TutorialStep.sequencerSectionTwoStepsHint:
        _setActiveStep(TutorialStep.sequencerSectionsSwipeHint);
        break;
      case TutorialStep.sequencerSectionTwoSamplesHint:
        _setActiveStep(TutorialStep.sequencerSectionTwoStepsHint);
        break;
      case TutorialStep.sequencerSectionsNavigateHint:
        _setActiveStep(TutorialStep.sequencerSectionsMenuHint);
        break;
      case TutorialStep.sequencerSectionsMenuHint:
        _setActiveStep(TutorialStep.sequencerSectionTwoSamplesHint);
        break;
      case TutorialStep.sequencerSongModeHint:
        _setActiveStep(TutorialStep.sequencerSectionsNavigateHint);
        break;
      case TutorialStep.sequencerSectionLoopsHint:
        _setActiveStep(TutorialStep.sequencerSongModeHint);
        break;
      case TutorialStep.sequencerSongRecordingHint:
        _setActiveStep(TutorialStep.sequencerSectionLoopsHint);
        break;
      case TutorialStep.sequencerSecondTakeAddHint:
        _setActiveStep(TutorialStep.sequencerSongRecordingHint);
        break;
      case TutorialStep.sequencerSecondTakeCloseHint:
        _setActiveStep(TutorialStep.sequencerSecondTakeAddHint);
        break;
      case TutorialStep.sequencerBackToPatternHint:
        _setActiveStep(TutorialStep.sequencerSecondTakeCloseHint);
        break;
      case TutorialStep.sequencerProjectsLibraryHint:
        _setActiveStep(TutorialStep.sequencerBackToPatternHint);
        break;
      case TutorialStep.sequencerLibraryLatestRecordingHint:
        if (_libraryLatestRecordingOpened && !_libraryLatestRecordingShared) {
          _libraryLatestRecordingOpened = false;
          notifyListeners();
        } else {
          _setActiveStep(TutorialStep.sequencerProjectsLibraryHint);
        }
        break;
      case TutorialStep.none:
        break;
    }
  }

  void stopTutorial() {
    if (!isEnabled) return;
    if (_activeTutorialStep == TutorialStep.none) return;
    _setActiveStep(TutorialStep.none);
  }

  bool canInteractWithTutorialTarget(TutorialInteractionTarget target) {
    // Temporarily keep all interactions enabled during tutorial steps.
    return true;
  }

  void _setActiveStep(
    TutorialStep step, {
    bool enterJumpPasteWithJumpAtTwo = false,
  }) {
    _cellParamsAdvanceTimer?.cancel();
    _jumpValueTwoAdvanceTimer?.cancel();
    _jumpValueTwoAdvanceTimer = null;
    _recordingReadyToStopTimer?.cancel();
    _activeTutorialStep = step;
    _copyActionDone = false;
    _cellVolumeAdjusted = false;
    _cellPitchAdjusted = false;
    _jumpValueSetToTwo = false;
    _jumpValueCopyDone = false;
    _jumpValuePasteCount = 0;
    if (step == TutorialStep.sequencerJumpPasteHint &&
        enterJumpPasteWithJumpAtTwo) {
      _jumpValueSetToTwo = true;
    }
    _playbackStarted = false;
    _selectModeEntered = false;
    _multiSelectDone = false;
    _selectModeVolumeAdjusted = false;
    _selectModeVolumeBaseline = null;
    _recordingPressed = false;
    _recordingPlayStarted = false;
    _recordingReadyToStop = false;
    _recordingStoppedAfterFourSec = false;
    _takesPlayDone = false;
    _takesAddDone = false;
    _layersTabPressed = false;
    _layersMutePressed = false;
    _layersUnmutePressed = false;
    _undoPressed = false;
    _redoPressed = false;
    _songRecordingPressed = false;
    _songRecordingPlayStarted = false;
    _songRecordingStopped = false;
    _secondTakeAddDone = false;
    _secondTakeCloseDone = false;
    _libraryLatestRecordingOpened = false;
    _libraryLatestRecordingShared = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _cellParamsAdvanceTimer?.cancel();
    _jumpValueTwoAdvanceTimer?.cancel();
    _recordingReadyToStopTimer?.cancel();
    super.dispose();
  }
}
