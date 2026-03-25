import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../services/tutorial_service.dart';

export '../services/tutorial_service.dart' show TutorialStep;

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
  int get tutorialStepDisplayIndex => _tutorialService.tutorialStepDisplayIndex;

  GlobalKey get firstCellTutorialKey => _tutorialService.firstCellTutorialKey;
  GlobalKey get selectSampleTutorialKey =>
      _tutorialService.selectSampleTutorialKey;
  GlobalKey get copyButtonTutorialKey => _tutorialService.copyButtonTutorialKey;
  GlobalKey get pasteButtonTutorialKey =>
      _tutorialService.pasteButtonTutorialKey;
  GlobalKey get deleteButtonTutorialKey =>
      _tutorialService.deleteButtonTutorialKey;
  GlobalKey get jumpButtonTutorialKey => _tutorialService.jumpButtonTutorialKey;
  GlobalKey get playButtonTutorialKey => _tutorialService.playButtonTutorialKey;
  GlobalKey get recordButtonTutorialKey =>
      _tutorialService.recordButtonTutorialKey;
  GlobalKey get layersRowTutorialKey => _tutorialService.layersRowTutorialKey;
  GlobalKey get selectModeButtonTutorialKey =>
      _tutorialService.selectModeButtonTutorialKey;
  GlobalKey get sampleGridTutorialKey => _tutorialService.sampleGridTutorialKey;
  GlobalKey get sectionMenuButtonTutorialKey =>
      _tutorialService.sectionMenuButtonTutorialKey;

  Future<void> initialize() => _tutorialService.initialize();
  void dismissTutorialPromptForSession() =>
      _tutorialService.dismissTutorialPromptForSession();
  void startProjectsQuickTutorial() => _tutorialService.startProjectsQuickTutorial();
  void advanceTutorialFromProjectsPlus() =>
      _tutorialService.advanceTutorialFromProjectsPlus();
  void advanceTutorialToSelectSample() =>
      _tutorialService.advanceTutorialToSelectSample();
  void completeSampleSelectionStep() =>
      _tutorialService.completeSampleSelectionStep();
  void markCopyAction() => _tutorialService.markCopyAction();
  void markPasteAction() => _tutorialService.markPasteAction();
  void verifyDeletionStep() => _tutorialService.verifyDeletionStep();
  void markJumpAction() => _tutorialService.markJumpAction();
  void markJumpValueSetToTwo() => _tutorialService.markJumpValueSetToTwo();
  void markJumpValueCopyAction() => _tutorialService.markJumpValueCopyAction();
  void markJumpValuePasteAction() => _tutorialService.markJumpValuePasteAction();
  void markPlayAction() => _tutorialService.markPlayAction();
  void markStopAction() => _tutorialService.markStopAction();
  void completeLayersInfoStep() => _tutorialService.completeLayersInfoStep();
  void completeSelectModeInfoStep() =>
      _tutorialService.completeSelectModeInfoStep();
  void verifyMultiSelectStep() => _tutorialService.verifyMultiSelectStep();
  void verifyDisableSelectModeStep() =>
      _tutorialService.verifyDisableSelectModeStep();
  void verifySecondSectionCreated() =>
      _tutorialService.verifySecondSectionCreated();
  void completePlaybackModesInfoStep() =>
      _tutorialService.completePlaybackModesInfoStep();
  void advanceTutorialManually() => _tutorialService.advanceTutorialManually();
  void goBackTutorialManually() => _tutorialService.goBackTutorialManually();
  void stopTutorial() => _tutorialService.stopTutorial();

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