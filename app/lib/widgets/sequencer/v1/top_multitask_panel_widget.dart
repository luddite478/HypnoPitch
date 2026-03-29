import 'package:flutter/material.dart';
// duplicate import removed
import 'package:provider/provider.dart';
import '../../../state/sequencer/multitask_panel.dart';
import '../../../state/sequencer/recording.dart';
import '../../../state/sequencer/edit.dart';
import '../../../state/sequencer/sample_bank.dart';
import '../../../state/sequencer/ui_selection.dart';
import 'sample_selection_widget.dart';
import 'share_widget.dart';
import 'sound_settings.dart';
import 'step_insert_settings_widget.dart';
import 'section_settings_widget.dart';
import 'section_management_widget.dart';
import 'layer_settings_widget.dart';
import 'select_settings_widget.dart';
import '../../../utils/app_colors.dart';

class MultitaskPanelWidget extends StatelessWidget {
  const MultitaskPanelWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer3<MultitaskPanelState, RecordingState, UiSelectionState>(
      builder: (context, panelState, recordingState, uiSelection, child) {
        // Also watch states that determine whether data exists for sound settings
        final editState = context.watch<EditState>();
        final sampleBankState = context.watch<SampleBankState>();
        switch (panelState.currentMode) {
          case MultitaskPanelMode.sampleSelection:
            return const SampleSelectionWidget();

          case MultitaskPanelMode.cellSettings:
            // Show cell settings whenever any cell is selected, including empty cells.
            final bool hasSelectedCell = editState.selectedCells.isNotEmpty;
            if (!hasSelectedCell) {
              return _buildPlaceholder();
            }
            final cellSettings = SoundSettingsWidget.forCell();
            return SoundSettingsWidget(
              type: cellSettings.type,
              title: cellSettings.title,
              headerButtons: cellSettings.headerButtons,
              closeAction: () =>
                  context.read<MultitaskPanelState>().showPlaceholder(),
              noDataMessage: cellSettings.noDataMessage,
              noDataIcon: cellSettings.noDataIcon,
              showDeleteButton: false,
              showCloseButton: cellSettings.showCloseButton,
            );

          case MultitaskPanelMode.sampleSettings:
            // If active sample slot is empty, show placeholder
            final bool hasSampleData = _hasActiveSampleData(sampleBankState);
            if (!hasSampleData) {
              return _buildPlaceholder();
            }
            final sampleSettings = SoundSettingsWidget.forSample();
            return SoundSettingsWidget(
              type: sampleSettings.type,
              title: sampleSettings.title,
              headerButtons: sampleSettings.headerButtons,
              closeAction: () =>
                  context.read<MultitaskPanelState>().showPlaceholder(),
              noDataMessage: sampleSettings.noDataMessage,
              noDataIcon: sampleSettings.noDataIcon,
              showDeleteButton: false,
              showCloseButton: sampleSettings.showCloseButton,
            );

          case MultitaskPanelMode.masterSettings:
            final masterSettings = SoundSettingsWidget.forMaster();
            return SoundSettingsWidget(
              type: masterSettings.type,
              title: masterSettings.title,
              headerButtons: masterSettings.headerButtons,
              closeAction: () =>
                  context.read<MultitaskPanelState>().showPlaceholder(),
              noDataMessage: masterSettings.noDataMessage,
              noDataIcon: masterSettings.noDataIcon,
              showDeleteButton: masterSettings.showDeleteButton,
              showCloseButton: masterSettings.showCloseButton,
            );

          case MultitaskPanelMode.stepInsertSettings:
            return const StepInsertSettingsWidget();

          case MultitaskPanelMode.shareWidget:
            return const ShareWidget();

          case MultitaskPanelMode.sectionSettings:
            return SectionSettingsWidget(
              closeAction: () =>
                  context.read<MultitaskPanelState>().showPlaceholder(),
              showCloseButton: false,
            );

          case MultitaskPanelMode.sectionManagement:
            return const SectionManagementWidget();

          case MultitaskPanelMode.layerSettings:
            return const LayerSettingsWidget();

          case MultitaskPanelMode.selectSettings:
            return const SelectSettingsWidget();

          case MultitaskPanelMode.recordingWidget:
            // Recording widget removed - recordings now auto-save as messages
            return _buildPlaceholder();

          case MultitaskPanelMode.placeholder:
            return _buildPlaceholder();
        }
      },
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceRaised,
        borderRadius: BorderRadius.circular(2), // Sharp corners
        border: Border.all(
          color: AppColors.sequencerBorder,
          width: 0.5,
        ),
        boxShadow: [
          // Protruding effect with multiple shadows
          BoxShadow(
            color: AppColors.sequencerShadow,
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: AppColors.sequencerSurfaceBase,
            blurRadius: 1,
            offset: const Offset(0, -1),
          ),
        ],
      ),
    );
  }

  bool _hasActiveSampleData(SampleBankState sampleBankState) {
    final idx = sampleBankState.activeSlot;
    return sampleBankState.isSlotLoaded(idx) ||
        sampleBankState.getSlotName(idx) != null;
  }
}
