import 'package:flutter/foundation.dart';

/// State management for multitask panel
/// Controls which panel is currently active and provides navigation between different panels
class MultitaskPanelState extends ChangeNotifier {
  MultitaskPanelMode _currentMode = MultitaskPanelMode.placeholder;

  MultitaskPanelMode get currentMode => _currentMode;

  void setMode(MultitaskPanelMode mode) {
    _currentMode = mode;
    notifyListeners();
    debugPrint('🎛️ [MULTITASK_PANEL] Set mode to $mode');
  }

  void showSampleSelection() => setMode(MultitaskPanelMode.sampleSelection);
  void showCellSettings() => setMode(MultitaskPanelMode.cellSettings);
  void showSampleSettings() => setMode(MultitaskPanelMode.sampleSettings);
  void showMasterSettings() => setMode(MultitaskPanelMode.masterSettings);
  void showStepInsertSettings() =>
      setMode(MultitaskPanelMode.stepInsertSettings);
  void showShareWidget() => setMode(MultitaskPanelMode.shareWidget);
  void showSectionSettings() => setMode(MultitaskPanelMode.sectionSettings);
  void showSectionManagement() => setMode(MultitaskPanelMode.sectionManagement);
  void showLayerSettings() => setMode(MultitaskPanelMode.layerSettings);
  void showSelectSettings() => setMode(MultitaskPanelMode.selectSettings);
  void showPlaceholder() => setMode(MultitaskPanelMode.placeholder);
}

enum MultitaskPanelMode {
  placeholder,
  sampleSelection,
  cellSettings,
  sampleSettings,
  masterSettings,
  stepInsertSettings,
  shareWidget,
  sectionSettings,
  sectionManagement,
  layerSettings,
  selectSettings,
  @Deprecated('Recording widget removed - recordings now auto-save as messages')
  recordingWidget,
}
