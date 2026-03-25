import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'reliable_storage.dart';

enum TutorialStep {
  none,
  projectsPlusButtonHint,
  sequencerFirstCellHint,
  sequencerSelectSampleHint,
  sequencerCopyPasteHint,
  sequencerDeleteHint,
  sequencerUndoRedoHint,
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
}

/// Dedicated service that owns first-launch tutorial state machine.
class TutorialService extends ChangeNotifier {
  /// Internal feature switch for tutorial runtime.
  /// Keep disabled until flow/content is finalized.
  static const bool isEnabled = true;
  static const String hasLaunchedBeforeKey = 'app_has_launched_before';
  static const int tutorialTotalSteps = 20;

  bool _isInitialized = false;
  bool _isFirstLaunchSession = false;
  bool _showTutorialPromptThisSession = false;
  TutorialStep _activeTutorialStep = TutorialStep.none;
  bool _copyActionDone = false;
  bool _jumpValueSetToTwo = false;
  int _jumpValuePasteCount = 0;
  bool _playbackStarted = false;
  bool _selectModeEntered = false;
  bool _multiSelectDone = false;
  bool _recordingPressed = false;
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

  final GlobalKey firstCellTutorialKey = GlobalKey();
  final GlobalKey selectSampleTutorialKey = GlobalKey();
  final GlobalKey copyButtonTutorialKey = GlobalKey();
  final GlobalKey pasteButtonTutorialKey = GlobalKey();
  final GlobalKey deleteButtonTutorialKey = GlobalKey();
  final GlobalKey undoButtonTutorialKey = GlobalKey();
  final GlobalKey redoButtonTutorialKey = GlobalKey();
  final GlobalKey jumpButtonTutorialKey = GlobalKey();
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

  bool get isInitialized => _isInitialized;
  bool get isFirstLaunchSession => _isFirstLaunchSession;
  bool get showTutorialPromptThisSession => _showTutorialPromptThisSession;
  TutorialStep get activeTutorialStep => _activeTutorialStep;
  bool get isTutorialRunning => _activeTutorialStep != TutorialStep.none;
  String get tutorialStepLabel {
    switch (_activeTutorialStep) {
      case TutorialStep.projectsPlusButtonHint:
        return 'Create pattern';
      case TutorialStep.sequencerFirstCellHint:
      case TutorialStep.sequencerSelectSampleHint:
        return 'Select sample';
      case TutorialStep.sequencerCopyPasteHint:
        return 'Copy paste';
      case TutorialStep.sequencerDeleteHint:
        return 'Delete';
      case TutorialStep.sequencerUndoRedoHint:
        return 'Undo redo';
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
      case TutorialStep.none:
        return 'Tutorial';
    }
  }

  int get tutorialStepDisplayIndex {
    switch (_activeTutorialStep) {
      case TutorialStep.projectsPlusButtonHint:
        return 1;
      case TutorialStep.sequencerFirstCellHint:
        return 2;
      case TutorialStep.sequencerSelectSampleHint:
        return 2;
      case TutorialStep.sequencerCopyPasteHint:
        return 3;
      case TutorialStep.sequencerDeleteHint:
        return 4;
      case TutorialStep.sequencerUndoRedoHint:
        return 5;
      case TutorialStep.sequencerJumpPasteHint:
        return 6;
      case TutorialStep.sequencerPlaybackHint:
        return 7;
      case TutorialStep.sequencerSelectModeHint:
        return 8;
      case TutorialStep.sequencerRecordingHint:
        return 9;
      case TutorialStep.sequencerTakesHint:
        return 10;
      case TutorialStep.sequencerLayersHint:
        return 11;
      case TutorialStep.sequencerSectionsSwipeHint:
        return 12;
      case TutorialStep.sequencerSectionTwoStepsHint:
        return 13;
      case TutorialStep.sequencerSectionTwoSamplesHint:
        return 14;
      case TutorialStep.sequencerSectionsNavigateHint:
        return 15;
      case TutorialStep.sequencerSectionsMenuHint:
        return 16;
      case TutorialStep.sequencerSongModeHint:
        return 17;
      case TutorialStep.sequencerSectionLoopsHint:
        return 18;
      case TutorialStep.sequencerSongRecordingHint:
        return 19;
      case TutorialStep.sequencerSecondTakeAddHint:
        return 20;
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

  void startProjectsQuickTutorial() {
    if (!isEnabled) return;
    _showTutorialPromptThisSession = false;
    _setActiveStep(TutorialStep.projectsPlusButtonHint);
  }

  void advanceTutorialFromProjectsPlus() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.projectsPlusButtonHint) return;
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
    _setActiveStep(TutorialStep.sequencerCopyPasteHint);
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
    _setActiveStep(TutorialStep.sequencerJumpPasteHint);
  }

  void markJumpAction() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerJumpPasteHint) return;
    notifyListeners();
  }

  void markJumpValueSetToTwo() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerJumpPasteHint) return;
    if (_jumpValueSetToTwo) return;
    _jumpValueSetToTwo = true;
    _tryCompleteJumpValuePasteStep();
  }

  void markJumpValueCopyAction() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerJumpPasteHint) return;
    notifyListeners();
  }

  void markJumpValuePasteAction() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerJumpPasteHint) return;
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
    notifyListeners();
  }

  void markRecordingPlayAction() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerRecordingHint) return;
    notifyListeners();
  }

  void markRecordingStopAction({required Duration recordingDuration}) {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerRecordingHint) return;
    if (!_recordingPressed) return;
    if (_recordingStoppedAfterFourSec) return;
    if (recordingDuration.inSeconds < 4) {
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
      if (!_songRecordingPressed ||
          !_songRecordingPlayStarted ||
          !_songRecordingStopped) {
        return;
      }
      _setActiveStep(TutorialStep.sequencerSecondTakeAddHint);
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
      _activeTutorialStep == TutorialStep.sequencerSecondTakeAddHint &&
      !_secondTakeAddDone;
  String get secondTakeStepInstruction =>
      'You created second take. Add it to your library too.';

  void verifyTakesCloseStep() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerTakesHint) return;
    if (!_takesPlayDone || !_takesAddDone) return;
    _setActiveStep(TutorialStep.sequencerLayersHint);
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

  void verifyDisableSelectModeStep() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerSelectModeHint) return;
    if (!_selectModeEntered || !_multiSelectDone) return;
    _setActiveStep(TutorialStep.sequencerRecordingHint);
  }

  /// Second section exists (swipe / create verified via [TableState.sectionsCount]).
  void verifySecondSectionCreated() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerSectionsSwipeHint) return;
    _setActiveStep(TutorialStep.sequencerSectionTwoStepsHint);
  }

  void verifySectionTwoStepsSetToEightStep() {
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
    _setActiveStep(TutorialStep.sequencerSectionsNavigateHint);
  }

  void verifyNavigatedToPreviousSectionStep() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerSectionsNavigateHint) {
      return;
    }
    _setActiveStep(TutorialStep.sequencerSectionsMenuHint);
  }

  void completeSectionMenuTutorialStep() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerSectionsMenuHint) return;
    _setActiveStep(TutorialStep.sequencerSongModeHint);
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
    if (_activeTutorialStep != TutorialStep.sequencerSecondTakeAddHint) return;
    if (_secondTakeAddDone) return;
    _secondTakeAddDone = true;
    stopTutorial();
  }

  void advanceTutorialManually() {
    if (!isEnabled) return;
    switch (_activeTutorialStep) {
      case TutorialStep.projectsPlusButtonHint:
        _setActiveStep(TutorialStep.sequencerFirstCellHint);
        break;
      case TutorialStep.sequencerFirstCellHint:
        _setActiveStep(TutorialStep.sequencerSelectSampleHint);
        break;
      case TutorialStep.sequencerSelectSampleHint:
        _setActiveStep(TutorialStep.sequencerCopyPasteHint);
        break;
      case TutorialStep.sequencerCopyPasteHint:
        _setActiveStep(TutorialStep.sequencerDeleteHint);
        break;
      case TutorialStep.sequencerDeleteHint:
        _setActiveStep(TutorialStep.sequencerUndoRedoHint);
        break;
      case TutorialStep.sequencerUndoRedoHint:
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
        _setActiveStep(TutorialStep.sequencerSectionsNavigateHint);
        break;
      case TutorialStep.sequencerSectionsNavigateHint:
        _setActiveStep(TutorialStep.sequencerSectionsMenuHint);
        break;
      case TutorialStep.sequencerSectionsMenuHint:
        _setActiveStep(TutorialStep.sequencerSongModeHint);
        break;
      case TutorialStep.sequencerSongModeHint:
        _setActiveStep(TutorialStep.sequencerSectionLoopsHint);
        break;
      case TutorialStep.sequencerSectionLoopsHint:
        _setActiveStep(TutorialStep.sequencerSongRecordingHint);
        break;
      case TutorialStep.sequencerSongRecordingHint:
        _setActiveStep(TutorialStep.sequencerSecondTakeAddHint);
        break;
      case TutorialStep.sequencerSecondTakeAddHint:
        stopTutorial();
        break;
      case TutorialStep.none:
        break;
    }
  }

  void goBackTutorialManually() {
    if (!isEnabled) return;
    switch (_activeTutorialStep) {
      case TutorialStep.projectsPlusButtonHint:
        _activeTutorialStep = TutorialStep.none;
        _showTutorialPromptThisSession = true;
        notifyListeners();
        break;
      case TutorialStep.sequencerFirstCellHint:
        _setActiveStep(TutorialStep.projectsPlusButtonHint);
        break;
      case TutorialStep.sequencerSelectSampleHint:
        _setActiveStep(TutorialStep.sequencerFirstCellHint);
        break;
      case TutorialStep.sequencerCopyPasteHint:
        _setActiveStep(TutorialStep.sequencerSelectSampleHint);
        break;
      case TutorialStep.sequencerDeleteHint:
        _setActiveStep(TutorialStep.sequencerCopyPasteHint);
        break;
      case TutorialStep.sequencerJumpPasteHint:
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
        _setActiveStep(TutorialStep.sequencerSectionTwoSamplesHint);
        break;
      case TutorialStep.sequencerSectionsMenuHint:
        _setActiveStep(TutorialStep.sequencerSectionsNavigateHint);
        break;
      case TutorialStep.sequencerSongModeHint:
        _setActiveStep(TutorialStep.sequencerSectionsMenuHint);
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
      case TutorialStep.none:
        break;
    }
  }

  void stopTutorial() {
    if (!isEnabled) return;
    if (_activeTutorialStep == TutorialStep.none) return;
    _setActiveStep(TutorialStep.none);
  }

  void _setActiveStep(TutorialStep step) {
    _activeTutorialStep = step;
    _copyActionDone = false;
    _jumpValueSetToTwo = false;
    _jumpValuePasteCount = 0;
    _playbackStarted = false;
    _selectModeEntered = false;
    _multiSelectDone = false;
    _recordingPressed = false;
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
    notifyListeners();
  }
}
