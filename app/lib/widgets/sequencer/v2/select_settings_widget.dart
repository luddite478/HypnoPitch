import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../state/sequencer/edit.dart';
import '../../../state/sequencer/multitask_panel.dart';
import '../../../state/sequencer/sample_bank.dart';
import '../../../state/sequencer/ui_selection.dart';
import '../../../utils/app_colors.dart';

enum _SelectActionMode {
  custom,
  selectAll,
  sample,
}

class SelectSettingsWidget extends StatefulWidget {
  const SelectSettingsWidget({super.key});

  @override
  State<SelectSettingsWidget> createState() => _SelectSettingsWidgetState();
}

class _SelectSettingsWidgetState extends State<SelectSettingsWidget> {
  _SelectActionMode _activeMode = _SelectActionMode.custom;
  int? _activeSampleSlot;

  @override
  Widget build(BuildContext context) {
    return Consumer3<EditState, SampleBankState, UiSelectionState>(
      builder: (context, editState, sampleBankState, uiSelection, child) {
        final sampleSlots = editState.getSampleSlotsUsedInVisibleGrid();
        return LayoutBuilder(
          builder: (context, constraints) {
            return Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.sequencerSurfaceBase,
                borderRadius: BorderRadius.circular(2),
                border: Border.all(
                  color: AppColors.sequencerBorder,
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.sequencerShadow,
                    blurRadius: 3,
                    offset: const Offset(0, 2),
                  ),
                  BoxShadow(
                    color: AppColors.sequencerSurfaceRaised,
                    blurRadius: 1,
                    offset: const Offset(0, -1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildActionButton(
                          label: 'CUSTOM SELECT',
                          isActive: _activeMode == _SelectActionMode.custom,
                          onTap: () {
                            editState.ensureSelectionMode();
                            uiSelection.selectCells();
                            if (_activeMode == _SelectActionMode.selectAll) {
                              // Leaving SELECT ALL mode clears full-grid selection.
                              editState.clearSelection();
                            }
                            setState(() {
                              _activeMode = _SelectActionMode.custom;
                              _activeSampleSlot = null;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _buildActionButton(
                          label: 'SELECT ALL',
                          isActive: _activeMode == _SelectActionMode.selectAll,
                          onTap: () {
                            editState.ensureSelectionMode();
                            if (_activeMode != _SelectActionMode.selectAll) {
                              editState.selectAll();
                              setState(() {
                                _activeMode = _SelectActionMode.selectAll;
                                _activeSampleSlot = null;
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.sequencerSurfaceRaised,
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(
                          color: AppColors.sequencerBorder,
                          width: 0.5,
                        ),
                      ),
                      child: sampleSlots.isEmpty
                          ? const SizedBox.shrink()
                          : GridView.builder(
                              padding: EdgeInsets.zero,
                              itemCount: sampleSlots.length,
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 84,
                                mainAxisExtent: 30,
                                crossAxisSpacing: 6,
                                mainAxisSpacing: 6,
                              ),
                              itemBuilder: (context, idx) {
                                final slot = sampleSlots[idx];
                                final color = (slot >= 0 &&
                                        slot <
                                            sampleBankState.uiBankColors.length)
                                    ? sampleBankState.uiBankColors[slot]
                                    : AppColors.sequencerAccent;
                                final letter =
                                    sampleBankState.getSlotLetter(slot);
                                return _buildSampleButton(
                                  label: letter,
                                  color: color,
                                  isActive:
                                      _activeMode == _SelectActionMode.sample &&
                                          _activeSampleSlot == slot,
                                  onTap: () {
                                    editState.ensureSelectionMode();
                                    editState
                                        .selectCellsBySampleSlotInVisibleGrid(
                                            slot);
                                    context
                                        .read<MultitaskPanelState>()
                                        .showCellSettings();
                                    setState(() {
                                      _activeMode = _SelectActionMode.sample;
                                      _activeSampleSlot = slot;
                                    });
                                  },
                                );
                              },
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildActionButton({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 30,
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.sequencerAccent
              : AppColors.sequencerSurfaceRaised,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: AppColors.sequencerBorder,
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.sequencerShadow,
              blurRadius: 1.5,
              offset: const Offset(0, 1),
            ),
            BoxShadow(
              color: AppColors.sequencerSurfaceRaised,
              blurRadius: 0.5,
              offset: const Offset(0, -0.5),
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isActive
                  ? AppColors.sequencerPageBackground
                  : AppColors.sequencerText,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSampleButton({
    required String label,
    required Color color,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.sequencerSurfaceBase,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: isActive
                ? AppColors.sequencerAccent
                : AppColors.sequencerBorder,
            width: isActive ? 1.0 : 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: AppColors.sequencerText,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
