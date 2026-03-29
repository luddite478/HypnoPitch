import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../services/tutorial_service.dart';

export '../services/tutorial_service.dart'
    show TutorialInteractionTarget, TutorialStep, TutorialTextInsets;

class AppState extends ChangeNotifier {
  static const int tutorialTotalSteps = TutorialService.tutorialTotalSteps;

  final TutorialService _tutorialService = TutorialService();

  AppState() {
    _tutorialService.addListener(_onTutorialChanged);
  }

  bool get isInitialized => _tutorialService.isInitialized;
  bool get isFirstLaunchSession => _tutorialService.isFirstLaunchSession;
  bool get showTutorialPromptThisSession =>
      _tutorialService.showTutorialPromptThisSession;
  TutorialStep get activeTutorialStep => _tutorialService.activeTutorialStep;
  bool get isTutorialRunning => _tutorialService.isTutorialRunning;
  bool get showCellParamsVolumePointer =>
      _tutorialService.showCellParamsVolumePointer;
  bool get showCellParamsKeyPointer => _tutorialService.showCellParamsKeyPointer;
  bool get showCopyPointer => _tutorialService.showCopyPointer;
  bool get showPastePointer => _tutorialService.showPastePointer;
  bool get showJumpValueTwoPointer =>
      _tutorialService.showJumpValueTwoPointer;
  bool get showJumpCopyPointer => _tutorialService.showJumpCopyPointer;
  bool get showJumpPastePointer => _tutorialService.showJumpPastePointer;
  bool get showJumpPasteTargetCellPointer =>
      _tutorialService.showJumpPasteTargetCellPointer;
  bool get showJumpPasteButtonOnlyPointer =>
      _tutorialService.showJumpPasteButtonOnlyPointer;
  bool get showRecordingRecordPointer => _tutorialService.showRecordingRecordPointer;
  bool get showRecordingPlayPointer => _tutorialService.showRecordingPlayPointer;
  bool get showSongRecordingRecordPointer =>
      _tutorialService.showSongRecordingRecordPointer;
  bool get showSelectModeButtonPointer => _tutorialService.showSelectModeButtonPointer;
  bool get showSelectModeVolumePointer => _tutorialService.showSelectModeVolumePointer;
  String get selectModeStepInstruction => _tutorialService.selectModeStepInstruction;
  int get tutorialStepDisplayIndex => _tutorialService.tutorialStepDisplayIndex;
  String get tutorialStepLabel => _tutorialService.tutorialStepLabel;

  GlobalKey get firstCellTutorialKey => _tutorialService.firstCellTutorialKey;
  GlobalKey get selectSampleTutorialKey =>
      _tutorialService.selectSampleTutorialKey;
  GlobalKey get multitaskPanelTutorialKey =>
      _tutorialService.multitaskPanelTutorialKey;
  GlobalKey get cellParamsVolumeButtonTutorialKey =>
      _tutorialService.cellParamsVolumeButtonTutorialKey;
  GlobalKey get cellParamsKeyButtonTutorialKey =>
      _tutorialService.cellParamsKeyButtonTutorialKey;
  GlobalKey get copyButtonTutorialKey => _tutorialService.copyButtonTutorialKey;
  GlobalKey get pasteButtonTutorialKey =>
      _tutorialService.pasteButtonTutorialKey;
  GlobalKey get copyPasteTargetCellTutorialKey =>
      _tutorialService.copyPasteTargetCellTutorialKey;
  GlobalKey get deleteButtonTutorialKey =>
      _tutorialService.deleteButtonTutorialKey;
  GlobalKey get undoButtonTutorialKey => _tutorialService.undoButtonTutorialKey;
  GlobalKey get redoButtonTutorialKey => _tutorialService.redoButtonTutorialKey;
  GlobalKey get jumpButtonTutorialKey => _tutorialService.jumpButtonTutorialKey;
  GlobalKey get jumpValueTwoDisplayTutorialKey =>
      _tutorialService.jumpValueTwoDisplayTutorialKey;
  GlobalKey get jumpPasteSourceCellTutorialKey =>
      _tutorialService.jumpPasteSourceCellTutorialKey;
  GlobalKey get jumpPasteTargetCellTutorialKey =>
      _tutorialService.jumpPasteTargetCellTutorialKey;
  GlobalKey get playButtonTutorialKey => _tutorialService.playButtonTutorialKey;
  GlobalKey get recordButtonTutorialKey =>
      _tutorialService.recordButtonTutorialKey;
  GlobalKey get takesPlayButtonTutorialKey =>
      _tutorialService.takesPlayButtonTutorialKey;
  GlobalKey get takesAddButtonTutorialKey =>
      _tutorialService.takesAddButtonTutorialKey;
  GlobalKey get takesCloseButtonTutorialKey =>
      _tutorialService.takesCloseButtonTutorialKey;
  GlobalKey get layerTabTutorialKey => _tutorialService.layerTabTutorialKey;
  GlobalKey get layerMuteButtonTutorialKey =>
      _tutorialService.layerMuteButtonTutorialKey;
  GlobalKey get layersRowTutorialKey => _tutorialService.layersRowTutorialKey;
  GlobalKey get selectModeButtonTutorialKey =>
      _tutorialService.selectModeButtonTutorialKey;
  GlobalKey get sampleGridTutorialKey => _tutorialService.sampleGridTutorialKey;
  GlobalKey get sectionCreatePrimaryButtonTutorialKey =>
      _tutorialService.sectionCreatePrimaryButtonTutorialKey;
  GlobalKey get sectionMenuButtonTutorialKey =>
      _tutorialService.sectionMenuButtonTutorialKey;
  GlobalKey get songModeButtonTutorialKey =>
      _tutorialService.songModeButtonTutorialKey;
  GlobalKey get sectionSettingsButtonTutorialKey =>
      _tutorialService.sectionSettingsButtonTutorialKey;
  GlobalKey get sectionStepsDecreaseTutorialKey =>
      _tutorialService.sectionStepsDecreaseTutorialKey;
  GlobalKey get sectionStepsIncreaseTutorialKey =>
      _tutorialService.sectionStepsIncreaseTutorialKey;
  GlobalKey get patternMenuButtonTutorialKey =>
      _tutorialService.patternMenuButtonTutorialKey;
  GlobalKey get projectsLibraryFolderTutorialKey =>
      _tutorialService.projectsLibraryFolderTutorialKey;
  GlobalKey get libraryLatestRecordingTutorialKey =>
      _tutorialService.libraryLatestRecordingTutorialKey;
  GlobalKey get libraryLatestRecordingShareTutorialKey =>
      _tutorialService.libraryLatestRecordingShareTutorialKey;

  Future<void> initialize() => _tutorialService.initialize();
  void dismissTutorialPromptForSession() =>
      _tutorialService.dismissTutorialPromptForSession();
  void startSequencerQuickTutorial() =>
      _tutorialService.startSequencerQuickTutorial();
  void advanceTutorialToSelectSample() =>
      _tutorialService.advanceTutorialToSelectSample();
  void completeSampleSelectionStep() =>
      _tutorialService.completeSampleSelectionStep();
  void markCellVolumeAdjusted(double value) =>
      _tutorialService.markCellVolumeAdjusted(value);
  void markCellPitchAdjusted(num semitones) =>
      _tutorialService.markCellPitchAdjusted(semitones);
  void markCopyAction() => _tutorialService.markCopyAction();
  void markPasteAction() => _tutorialService.markPasteAction();
  void verifyDeletionStep() => _tutorialService.verifyDeletionStep();
  bool get isUndoDone => _tutorialService.isUndoDone;
  bool get isRedoDone => _tutorialService.isRedoDone;
  void markUndoAction() => _tutorialService.markUndoAction();
  void markRedoAction() => _tutorialService.markRedoAction();
  void markJumpAction() => _tutorialService.markJumpAction();
  void markJumpValueSetToTwo() => _tutorialService.markJumpValueSetToTwo();
  void markJumpValueCopyAction() => _tutorialService.markJumpValueCopyAction();
  void markJumpValuePasteAction() => _tutorialService.markJumpValuePasteAction();
  void markPlayAction() => _tutorialService.markPlayAction();
  void markStopAction() => _tutorialService.markStopAction();
  void markRecordingAction() => _tutorialService.markRecordingAction();
  void markRecordingPlayAction() => _tutorialService.markRecordingPlayAction();
  void markRecordingStopAction({required Duration recordingDuration}) =>
      _tutorialService.markRecordingStopAction(
        recordingDuration: recordingDuration,
      );
  void completeRecordingStepAfterTakeSaved() =>
      _tutorialService.completeRecordingStepAfterTakeSaved();
  void markTakesPlayAction({required Duration listenedDuration}) =>
      _tutorialService.markTakesPlayAction(
        listenedDuration: listenedDuration,
      );
  void markTakesAddToLibraryAction() =>
      _tutorialService.markTakesAddToLibraryAction();
  int get takesStepPartIndex => _tutorialService.takesStepPartIndex;
  String get takesStepInstruction => _tutorialService.takesStepInstruction;
  bool get showTakesPlayPointer => _tutorialService.showTakesPlayPointer;
  bool get showTakesAddPointer => _tutorialService.showTakesAddPointer;
  bool get showTakesClosePointer => _tutorialService.showTakesClosePointer;
  bool get canCloseTakesTutorialStep => _tutorialService.canCloseTakesTutorialStep;
  bool get showSecondTakeAddPointer => _tutorialService.showSecondTakeAddPointer;
  bool get showSecondTakeClosePointer =>
      _tutorialService.showSecondTakeClosePointer;
  String get secondTakeStepInstruction =>
      _tutorialService.secondTakeStepInstruction;
  bool get showLibraryLatestRecordingPointer =>
      _tutorialService.showLibraryLatestRecordingPointer;
  bool get showLibraryLatestRecordingSharePointer =>
      _tutorialService.showLibraryLatestRecordingSharePointer;
  String get libraryLatestRecordingStepInstruction =>
      _tutorialService.libraryLatestRecordingStepInstruction;
  void verifyTakesCloseStep() => _tutorialService.verifyTakesCloseStep();
  bool get isLayersTabDone => _tutorialService.isLayersTabDone;
  bool get isLayersMuteDone => _tutorialService.isLayersMuteDone;
  bool get isLayersUnmuteDone => _tutorialService.isLayersUnmuteDone;
  void markLayersTabAction() => _tutorialService.markLayersTabAction();
  void markLayersMuteToggleAction({required bool isMutedAfterToggle}) =>
      _tutorialService.markLayersMuteToggleAction(
        isMutedAfterToggle: isMutedAfterToggle,
      );
  void completeLayersInfoStep() => _tutorialService.completeLayersInfoStep();
  void completeSelectModeInfoStep() =>
      _tutorialService.completeSelectModeInfoStep();
  void verifyMultiSelectStep() => _tutorialService.verifyMultiSelectStep();
  void markSelectModeVolumeChanged(double value) =>
      _tutorialService.markSelectModeVolumeChanged(value);
  void verifyDisableSelectModeStep() =>
      _tutorialService.verifyDisableSelectModeStep();
  void verifySecondSectionCreated() =>
      _tutorialService.verifySecondSectionCreated();
  void verifySectionTwoStepsSetToThirtyTwoStep() =>
      _tutorialService.verifySectionTwoStepsSetToThirtyTwoStep();
  void verifySectionTwoFiveSamplesStep() =>
      _tutorialService.verifySectionTwoFiveSamplesStep();
  void verifyNavigatedToPreviousSectionStep() =>
      _tutorialService.verifyNavigatedToPreviousSectionStep();
  void completeSectionMenuTutorialStep() =>
      _tutorialService.completeSectionMenuTutorialStep();
  void verifySongModeEnabledStep() =>
      _tutorialService.verifySongModeEnabledStep();
  void verifyAnySectionLoopSetToTwoStep() =>
      _tutorialService.verifyAnySectionLoopSetToTwoStep();
  void markSongRecordingAction() => _tutorialService.markSongRecordingAction();
  void markSongRecordingPlayAction() =>
      _tutorialService.markSongRecordingPlayAction();
  void markSongRecordingStopAction({
    required Duration recordingDuration,
    required int sectionsCount,
    required bool isSongMode,
  }) =>
      _tutorialService.markSongRecordingStopAction(
        recordingDuration: recordingDuration,
        sectionsCount: sectionsCount,
        isSongMode: isSongMode,
      );
  void markSecondTakeAddToLibraryAction() =>
      _tutorialService.markSecondTakeAddToLibraryAction();
  void markSecondTakeCloseAction() => _tutorialService.markSecondTakeCloseAction();
  void markPatternMenuBackAction() => _tutorialService.markPatternMenuBackAction();
  void markProjectsLibraryFolderOpenAction() =>
      _tutorialService.markProjectsLibraryFolderOpenAction();
  void markLibraryLatestRecordingOpenAction() =>
      _tutorialService.markLibraryLatestRecordingOpenAction();
  void markLibraryLatestRecordingShareAction() =>
      _tutorialService.markLibraryLatestRecordingShareAction();
  void advanceTutorialManually() => _tutorialService.advanceTutorialManually();
  void goBackTutorialManually() => _tutorialService.goBackTutorialManually();
  void stopTutorial() => _tutorialService.stopTutorial();
  bool canInteractWithTutorialTarget(TutorialInteractionTarget target) =>
      _tutorialService.canInteractWithTutorialTarget(target);

  TutorialTextInsets get activeTutorialTextInsets =>
      _tutorialService.activeTutorialTextInsets;

  void _onTutorialChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    _tutorialService.removeListener(_onTutorialChanged);
    _tutorialService.dispose();
    super.dispose();
  }
}