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
  sequencerJumpHint,
  sequencerJumpValuePasteHint,
  sequencerPlayHint,
  sequencerStopHint,
  sequencerLayersHint,
  sequencerSelectModeHint,
  sequencerSelectMultipleHint,
  sequencerDisableSelectModeHint,
  sequencerSwipeSectionHint,
  sequencerPlaybackModesHint,
  sequencerRecordHint,
}

/// Dedicated service that owns first-launch tutorial state machine.
class TutorialService extends ChangeNotifier {
  /// Internal feature switch for tutorial runtime.
  /// Keep disabled until flow/content is finalized.
  static const bool isEnabled = false;
  static const String hasLaunchedBeforeKey = 'app_has_launched_before';
  static const int tutorialTotalSteps = 16;

  bool _isInitialized = false;
  bool _isFirstLaunchSession = false;
  bool _showTutorialPromptThisSession = false;
  TutorialStep _activeTutorialStep = TutorialStep.none;
  bool _copyActionDone = false;
  bool _jumpValueSetToTwo = false;
  bool _jumpValueCopyDone = false;
  int _jumpValuePasteCount = 0;

  final GlobalKey firstCellTutorialKey = GlobalKey();
  final GlobalKey selectSampleTutorialKey = GlobalKey();
  final GlobalKey copyButtonTutorialKey = GlobalKey();
  final GlobalKey pasteButtonTutorialKey = GlobalKey();
  final GlobalKey deleteButtonTutorialKey = GlobalKey();
  final GlobalKey jumpButtonTutorialKey = GlobalKey();
  final GlobalKey playButtonTutorialKey = GlobalKey();
  final GlobalKey recordButtonTutorialKey = GlobalKey();
  final GlobalKey layersRowTutorialKey = GlobalKey();
  final GlobalKey selectModeButtonTutorialKey = GlobalKey();
  final GlobalKey sampleGridTutorialKey = GlobalKey();
  final GlobalKey sectionMenuButtonTutorialKey = GlobalKey();

  bool get isInitialized => _isInitialized;
  bool get isFirstLaunchSession => _isFirstLaunchSession;
  bool get showTutorialPromptThisSession => _showTutorialPromptThisSession;
  TutorialStep get activeTutorialStep => _activeTutorialStep;
  bool get isTutorialRunning => _activeTutorialStep != TutorialStep.none;

  int get tutorialStepDisplayIndex {
    switch (_activeTutorialStep) {
      case TutorialStep.projectsPlusButtonHint:
        return 1;
      case TutorialStep.sequencerFirstCellHint:
        return 2;
      case TutorialStep.sequencerSelectSampleHint:
        return 3;
      case TutorialStep.sequencerCopyPasteHint:
        return 4;
      case TutorialStep.sequencerDeleteHint:
        return 5;
      case TutorialStep.sequencerJumpHint:
        return 6;
      case TutorialStep.sequencerJumpValuePasteHint:
        return 7;
      case TutorialStep.sequencerPlayHint:
        return 8;
      case TutorialStep.sequencerStopHint:
        return 9;
      case TutorialStep.sequencerSelectModeHint:
        return 10;
      case TutorialStep.sequencerSelectMultipleHint:
        return 11;
      case TutorialStep.sequencerDisableSelectModeHint:
        return 12;
      case TutorialStep.sequencerLayersHint:
        return 13;
      case TutorialStep.sequencerSwipeSectionHint:
        return 14;
      case TutorialStep.sequencerPlaybackModesHint:
        return 15;
      case TutorialStep.sequencerRecordHint:
        return 16;
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
    _setActiveStep(TutorialStep.sequencerJumpHint);
  }

  void markJumpAction() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerJumpHint) return;
    _setActiveStep(TutorialStep.sequencerJumpValuePasteHint);
  }

  void markJumpValueSetToTwo() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerJumpValuePasteHint) return;
    if (_jumpValueSetToTwo) return;
    _jumpValueSetToTwo = true;
    _tryCompleteJumpValuePasteStep();
  }

  void markJumpValueCopyAction() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerJumpValuePasteHint) return;
    if (_jumpValueCopyDone) return;
    _jumpValueCopyDone = true;
    _tryCompleteJumpValuePasteStep();
  }

  void markJumpValuePasteAction() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerJumpValuePasteHint) return;
    _jumpValuePasteCount += 1;
    _tryCompleteJumpValuePasteStep();
  }

  void _tryCompleteJumpValuePasteStep() {
    if (_activeTutorialStep != TutorialStep.sequencerJumpValuePasteHint) return;
    if (_jumpValueSetToTwo && _jumpValueCopyDone && _jumpValuePasteCount >= 2) {
      _setActiveStep(TutorialStep.sequencerPlayHint);
    } else {
      notifyListeners();
    }
  }

  void markPlayAction() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerPlayHint) return;
    _setActiveStep(TutorialStep.sequencerStopHint);
  }

  void markStopAction() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerStopHint) return;
    _setActiveStep(TutorialStep.sequencerSelectModeHint);
  }

  void completeLayersInfoStep() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerLayersHint) return;
    _setActiveStep(TutorialStep.sequencerSwipeSectionHint);
  }

  void completeSelectModeInfoStep() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerSelectModeHint) return;
    _setActiveStep(TutorialStep.sequencerSelectMultipleHint);
  }

  void verifyMultiSelectStep() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerSelectMultipleHint) return;
    _setActiveStep(TutorialStep.sequencerDisableSelectModeHint);
  }

  void verifyDisableSelectModeStep() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerDisableSelectModeHint) return;
    _setActiveStep(TutorialStep.sequencerLayersHint);
  }

  void verifySecondSectionCreated() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerSwipeSectionHint) return;
    _setActiveStep(TutorialStep.sequencerPlaybackModesHint);
  }

  void completePlaybackModesInfoStep() {
    if (!isEnabled) return;
    if (_activeTutorialStep != TutorialStep.sequencerPlaybackModesHint) return;
    _setActiveStep(TutorialStep.sequencerRecordHint);
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
        _setActiveStep(TutorialStep.sequencerJumpHint);
        break;
      case TutorialStep.sequencerJumpHint:
        _setActiveStep(TutorialStep.sequencerJumpValuePasteHint);
        break;
      case TutorialStep.sequencerJumpValuePasteHint:
        _setActiveStep(TutorialStep.sequencerPlayHint);
        break;
      case TutorialStep.sequencerPlayHint:
        _setActiveStep(TutorialStep.sequencerStopHint);
        break;
      case TutorialStep.sequencerStopHint:
        _setActiveStep(TutorialStep.sequencerSelectModeHint);
        break;
      case TutorialStep.sequencerSelectModeHint:
        _setActiveStep(TutorialStep.sequencerSelectMultipleHint);
        break;
      case TutorialStep.sequencerSelectMultipleHint:
        _setActiveStep(TutorialStep.sequencerDisableSelectModeHint);
        break;
      case TutorialStep.sequencerDisableSelectModeHint:
        _setActiveStep(TutorialStep.sequencerLayersHint);
        break;
      case TutorialStep.sequencerLayersHint:
        _setActiveStep(TutorialStep.sequencerSwipeSectionHint);
        break;
      case TutorialStep.sequencerSwipeSectionHint:
        _setActiveStep(TutorialStep.sequencerPlaybackModesHint);
        break;
      case TutorialStep.sequencerPlaybackModesHint:
        _setActiveStep(TutorialStep.sequencerRecordHint);
        break;
      case TutorialStep.sequencerRecordHint:
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
      case TutorialStep.sequencerJumpHint:
        _setActiveStep(TutorialStep.sequencerDeleteHint);
        break;
      case TutorialStep.sequencerJumpValuePasteHint:
        _setActiveStep(TutorialStep.sequencerJumpHint);
        break;
      case TutorialStep.sequencerPlayHint:
        _setActiveStep(TutorialStep.sequencerJumpValuePasteHint);
        break;
      case TutorialStep.sequencerStopHint:
        _setActiveStep(TutorialStep.sequencerPlayHint);
        break;
      case TutorialStep.sequencerSelectModeHint:
        _setActiveStep(TutorialStep.sequencerStopHint);
        break;
      case TutorialStep.sequencerSelectMultipleHint:
        _setActiveStep(TutorialStep.sequencerSelectModeHint);
        break;
      case TutorialStep.sequencerDisableSelectModeHint:
        _setActiveStep(TutorialStep.sequencerSelectMultipleHint);
        break;
      case TutorialStep.sequencerLayersHint:
        _setActiveStep(TutorialStep.sequencerDisableSelectModeHint);
        break;
      case TutorialStep.sequencerSwipeSectionHint:
        _setActiveStep(TutorialStep.sequencerSelectModeHint);
        break;
      case TutorialStep.sequencerPlaybackModesHint:
        _setActiveStep(TutorialStep.sequencerSwipeSectionHint);
        break;
      case TutorialStep.sequencerRecordHint:
        _setActiveStep(TutorialStep.sequencerPlaybackModesHint);
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
    _jumpValueCopyDone = false;
    _jumpValuePasteCount = 0;
    notifyListeners();
  }
}
