import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../utils/app_colors.dart';
import '../../../state/sequencer/edit.dart';
import '../../../state/sequencer/multitask_panel.dart';
import '../../../state/sequencer/table.dart';
import '../../../state/sequencer/sample_bank.dart';
import '../../../state/sequencer/ui_selection.dart';
import '../../../state/app_state.dart';
import '../../../ffi/table_bindings.dart' show CellData;

class EditButtonsWidget extends StatelessWidget {
  const EditButtonsWidget({super.key});

  // Percent-based sizing configuration for layouts
  static const double _v1ButtonSizePercent = 0.6; // of container height
  static const double _v1HorizontalPaddingPercent = 0.1; // of container height

  // V2 percent-based configuration
  static const double _v2ButtonHeightPercent = 0.7; // of container height
  static const double _v2RightPaddingPercent = 0.03; // of container width
  static const double _v2ButtonHorizontalPaddingPercent =
      0.035; // of container height
  static const double _v2ButtonSpacingPercent = 0.015; // of container width
  static const double _v2TextFontScale = 0.23; // of button height
  static const double _v2PerButtonWidthPercent = 0.162; // of container width

  @override
  Widget build(BuildContext context) {
    return Consumer4<TableState, EditState, SampleBankState, UiSelectionState>(
      builder: (context, tableState, editState, sampleBankState, uiSelection,
          child) {
        final appState = context.watch<AppState>();
        if (appState.activeTutorialStep == TutorialStep.sequencerSelectModeHint &&
            editState.selectedCells.length > 1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            context.read<AppState>().verifyMultiSelectStep();
          });
        }
        if (appState.activeTutorialStep ==
                TutorialStep.sequencerJumpPasteHint &&
            editState.stepInsertSize == 2) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            context.read<AppState>().markJumpValueSetToTwo();
          });
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final panelHeight = constraints.maxHeight;
            final panelWidth = constraints.maxWidth;

            if (tableState.uiEditButtonsLayoutMode ==
                EditButtonsLayoutMode.v2) {
              // V2: Text buttons, equal size via percents, right-aligned, with small inactive left chevron
              final buttonHeight =
                  (panelHeight * _v2ButtonHeightPercent).clamp(20.0, 64.0);
              final textFontSize =
                  (buttonHeight * _v2TextFontScale).clamp(10.0, 22.0);
              final buttonHPad =
                  (panelHeight * _v2ButtonHorizontalPaddingPercent)
                      .clamp(6.0, 18.0);
              final spacing =
                  (panelWidth * _v2ButtonSpacingPercent).clamp(4.0, 16.0);
              final buttonWidth = panelWidth * _v2PerButtonWidthPercent;

              return Container(
                padding:
                    EdgeInsets.only(right: panelWidth * _v2RightPaddingPercent),
                decoration: BoxDecoration(
                  color: AppColors.sequencerSurfaceBase,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(
                    color: AppColors.sequencerBorder,
                    width: 0.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.sequencerShadow,
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Spacer(),
                    SizedBox(
                      width: buttonWidth,
                      child: _buildTextActionButton(
                        key: appState.selectModeButtonTutorialKey,
                        label: 'SELECT',
                        height: buttonHeight,
                        fontSize: textFontSize,
                        enabled: true,
                        onPressed: () {
                          final wasInSelectionMode = editState.isInSelectionMode;
                          final multitaskPanel =
                              Provider.of<MultitaskPanelState>(context,
                                  listen: false);
                          if (editState.isInSelectionMode) {
                            // Toggle off when SELECT is already active.
                            editState.toggleSelectionMode();
                            multitaskPanel.showPlaceholder();
                          } else {
                            // Keep custom rectangle select as default behavior,
                            // and open the Select settings panel.
                            editState.toggleSelectionMode();
                            multitaskPanel.showSelectSettings();
                          }
                          appState.completeSelectModeInfoStep();
                          if (wasInSelectionMode &&
                              !editState.isInSelectionMode) {
                            appState.verifyDisableSelectModeStep();
                          }
                        },
                        isActive: editState.isInSelectionMode,
                        horizontalPadding: buttonHPad,
                      ),
                    ),
                    SizedBox(width: spacing),
                    SizedBox(
                      width: buttonWidth,
                      child: _JumpButtonWithFeedback(
                        key: appState.jumpButtonTutorialKey,
                        label: 'JUMP ${editState.stepInsertSize}',
                        height: buttonHeight,
                        fontSize: textFontSize,
                        horizontalPadding: buttonHPad,
                        onPressed: () {
                          editState.toggleStepInsertMode();
                          Provider.of<MultitaskPanelState>(context,
                                  listen: false)
                              .showStepInsertSettings();
                          appState.markJumpAction();
                        },
                      ),
                    ),
                    SizedBox(width: spacing),
                    SizedBox(
                      width: buttonWidth,
                      child: _buildTextActionButton(
                        key: appState.deleteButtonTutorialKey,
                        label: 'DEL',
                        height: buttonHeight,
                        fontSize: textFontSize,
                        enabled: editState.hasSelection ||
                            uiSelection.isSampleBank ||
                            uiSelection.isSection,
                        onPressed: (editState.hasSelection ||
                                uiSelection.isSampleBank ||
                                uiSelection.isSection)
                            ? () {
                                if (uiSelection.isSampleBank) {
                                  final slot = uiSelection.selectedSampleSlot ??
                                      sampleBankState.activeSlot;
                                  sampleBankState.unloadSample(slot);
                                  uiSelection.clear();
                                } else if (uiSelection.isSection) {
                                  _deleteSectionWithConfirmation(
                                      context, tableState, uiSelection);
                                } else {
                                  final selectedCellsAbs =
                                      editState.getSelectedAbsoluteCells();
                                  final hadSample = _absoluteCellsContainSamples(
                                    tableState,
                                    selectedCellsAbs,
                                  );
                                  editState.deleteCells();
                                  final isDeleted = _absoluteCellsAreEmpty(
                                    tableState,
                                    selectedCellsAbs,
                                  );
                                  if (hadSample && isDeleted) {
                                    appState.verifyDeletionStep();
                                  }
                                }
                              }
                            : null,
                        isActive: false,
                        horizontalPadding: buttonHPad,
                      ),
                    ),
                    SizedBox(width: spacing),
                    SizedBox(
                      width: buttonWidth,
                      child: _buildTextActionButton(
                        key: appState.copyButtonTutorialKey,
                        label: 'COPY',
                        height: buttonHeight,
                        fontSize: textFontSize,
                        enabled:
                            editState.hasSelection || uiSelection.isSection,
                        onPressed:
                            (editState.hasSelection || uiSelection.isSection)
                                ? () {
                                    if (uiSelection.isSection) {
                                      tableState.copySectionToClipboard(
                                          uiSelection.selectedSection!);
                                    } else {
                                      editState.copyCells();
                                    }
                                    appState.markCopyAction();
                                    appState.markJumpValueCopyAction();
                                  }
                                : null,
                        isActive: false,
                        horizontalPadding: buttonHPad,
                      ),
                    ),
                    SizedBox(width: spacing),
                    SizedBox(
                      width: buttonWidth,
                      child: _buildTextActionButton(
                        key: appState.pasteButtonTutorialKey,
                        label: 'PASTE',
                        height: buttonHeight,
                        fontSize: textFontSize,
                        enabled: (editState.hasClipboardData &&
                                editState.hasSelection) ||
                            (tableState.hasCopiedSection &&
                                uiSelection.isSection),
                        onPressed: ((editState.hasClipboardData &&
                                    editState.hasSelection) ||
                                (tableState.hasCopiedSection &&
                                    uiSelection.isSection))
                            ? () {
                                if (uiSelection.isSection &&
                                    tableState.hasCopiedSection) {
                                  // Paste section contents INTO selected section (replace)
                                  tableState.pasteSection(
                                      uiSelection.selectedSection!);
                                } else {
                                  editState.pasteCells();
                                }
                                appState.markPasteAction();
                                appState.markJumpValuePasteAction();
                              }
                            : null,
                        isActive: false,
                        horizontalPadding: buttonHPad,
                      ),
                    ),
                  ],
                ),
              );
            }

            // V1: Keep as-is (icon buttons, evenly spaced)
            final buttonSize =
                (panelHeight * _v1ButtonSizePercent).clamp(20.0, 48.0);
            final iconSize = (buttonSize * 0.6).clamp(16.0, 32.0);

            return Container(
              padding: EdgeInsets.symmetric(
                  horizontal: panelHeight * _v1HorizontalPaddingPercent),
              decoration: BoxDecoration(
                color: AppColors.sequencerSurfaceBase,
                borderRadius: BorderRadius.circular(2), // Sharp corners
                border: Border.all(
                  color: AppColors.sequencerBorder,
                  width: 0.5,
                ),
                boxShadow: [
                  // Protruding effect
                  BoxShadow(
                    color: AppColors.sequencerShadow,
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildEditButton(
                    size: buttonSize,
                    iconSize: iconSize,
                    icon: editState.isInSelectionMode
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    color: editState.isInSelectionMode
                        ? AppColors.sequencerAccent
                        : AppColors.sequencerLightText,
                    onPressed: () => editState.toggleSelectionMode(),
                    tooltip: editState.isInSelectionMode
                        ? 'Exit Selection Mode'
                        : 'Enter Selection Mode',
                  ),
                  _buildStepInsertToggleButton(
                    size: buttonSize,
                    iconSize: iconSize,
                    editState: editState,
                    context: context,
                  ),
                  _buildEditButton(
                    size: buttonSize,
                    iconSize: iconSize,
                    icon: Icons.delete,
                    color: (editState.hasSelection ||
                            context.read<UiSelectionState>().isSampleBank)
                        ? AppColors.sequencerAccent.withOpacity(0.8)
                        : AppColors.sequencerLightText,
                    onPressed: (editState.hasSelection ||
                            context.read<UiSelectionState>().isSampleBank)
                        ? () {
                            final uiSel = context.read<UiSelectionState>();
                            final sb = context.read<SampleBankState>();
                            if (uiSel.isSampleBank) {
                              final slot =
                                  uiSel.selectedSampleSlot ?? sb.activeSlot;
                              sb.unloadSample(slot);
                              uiSel.clear();
                            } else {
                              editState.deleteCells();
                            }
                          }
                        : null,
                    tooltip: 'Delete Selected',
                  ),
                  _buildEditButton(
                    size: buttonSize,
                    iconSize: iconSize,
                    icon: Icons.copy,
                    color: editState.hasSelection
                        ? AppColors.sequencerAccent
                        : AppColors.sequencerLightText,
                    onPressed: editState.hasSelection
                        ? () => editState.copyCells()
                        : null,
                    tooltip: 'Copy Selected Cells',
                  ),
                  _buildEditButton(
                    size: buttonSize,
                    iconSize: iconSize,
                    icon: Icons.paste,
                    color: editState.hasClipboardData && editState.hasSelection
                        ? AppColors.sequencerAccent
                        : AppColors.sequencerLightText,
                    onPressed:
                        editState.hasClipboardData && editState.hasSelection
                            ? () => editState.pasteCells()
                            : null,
                    tooltip: 'Paste to Selected Cells',
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEditButton({
    required double size,
    required double iconSize,
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
    required String tooltip,
  }) {
    final isEnabled = onPressed != null;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isEnabled
            ? AppColors.sequencerSurfaceRaised
            : AppColors.sequencerSurfacePressed,
        borderRadius: BorderRadius.circular(2), // Sharp corners
        border: Border.all(
          color: AppColors.sequencerBorder,
          width: 0.5,
        ),
        boxShadow: isEnabled
            ? [
                // Protruding effect for enabled buttons
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
              ]
            : [
                // Recessed effect for disabled buttons
                BoxShadow(
                  color: AppColors.sequencerShadow,
                  blurRadius: 1,
                  offset: const Offset(0, 0.5),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(2),
          child: Container(
            padding: EdgeInsets.zero,
            child: Icon(
              icon,
              color: color,
              size: iconSize,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepInsertToggleButton({
    required double size,
    required double iconSize,
    required EditState editState,
    required BuildContext context,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceRaised,
        borderRadius: BorderRadius.circular(2), // Sharp corners
        border: Border.all(
          color: editState.isStepInsertMode
              ? AppColors.sequencerAccent
              : AppColors.sequencerBorder,
          width: editState.isStepInsertMode ? 1.0 : 0.5,
        ),
        boxShadow: [
          // Protruding effect
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            editState.toggleStepInsertMode();
            // Open jump insert settings when toggled
            Provider.of<MultitaskPanelState>(context, listen: false)
                .showStepInsertSettings();
          },
          borderRadius: BorderRadius.circular(2),
          child: Container(
            padding: EdgeInsets.zero,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.only(
                        top: 2), // Add 4 pixels top margin
                    child: Text(
                      '${editState.stepInsertSize}',
                      style: TextStyle(
                        color: editState.isStepInsertMode
                            ? AppColors.sequencerAccent
                            : AppColors.sequencerLightText,
                        fontSize: iconSize * 0.8,
                        fontWeight: FontWeight.w600,
                        height: 0.7,
                      ),
                    ),
                  ),
                  Transform.translate(
                    offset: const Offset(0, -2), // Move arrow up by 2 pixels
                    child: Icon(
                      Icons.keyboard_double_arrow_down,
                      color: editState.isStepInsertMode
                          ? AppColors.sequencerAccent
                          : AppColors.sequencerLightText,
                      size: iconSize * 0.8,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextActionButton({
    Key? key,
    required String label,
    required double height,
    required double fontSize,
    required bool enabled,
    required VoidCallback? onPressed,
    required bool isActive,
    required double horizontalPadding,
  }) {
    final backgroundColor = !enabled
        ? AppColors.sequencerSurfacePressed
        : isActive
            ? Colors.white.withOpacity(0.22)
            : AppColors.sequencerSurfaceRaised;
    final textColor = isActive
        ? const Color(0xFFF5F5F5)
        : (enabled ? AppColors.sequencerText : AppColors.sequencerLightText);
    return Container(
      key: key,
      height: height,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: isActive
              ? Colors.white.withOpacity(0.75)
              : AppColors.sequencerBorder,
          width: isActive ? 1.0 : 0.5,
        ),
        boxShadow: enabled
            ? [
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
                if (isActive)
                  BoxShadow(
                    color: Colors.white.withOpacity(0.22),
                    blurRadius: 6,
                    offset: const Offset(0, 0),
                  ),
              ]
            : [
                BoxShadow(
                  color: AppColors.sequencerShadow,
                  blurRadius: 1,
                  offset: const Offset(0, 0.5),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(3),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Stateful JUMP button with click feedback (no active state)
class _JumpButtonWithFeedback extends StatefulWidget {
  final String label;
  final double height;
  final double fontSize;
  final double horizontalPadding;
  final VoidCallback onPressed;

  const _JumpButtonWithFeedback({
    super.key,
    required this.label,
    required this.height,
    required this.fontSize,
    required this.horizontalPadding,
    required this.onPressed,
  });

  @override
  State<_JumpButtonWithFeedback> createState() =>
      _JumpButtonWithFeedbackState();
}

bool _absoluteCellsContainSamples(
  TableState tableState,
  List<({int step, int col})> selectedCellsAbs,
) {
  if (selectedCellsAbs.isEmpty) return false;
  for (final cell in selectedCellsAbs) {
    final ptr = tableState.getCellPointer(cell.step, cell.col);
    if (ptr.address == 0) continue;
    final cellData = CellData.fromPointer(ptr);
    if (cellData.isNotEmpty && cellData.sampleSlot >= 0) return true;
  }
  return false;
}

bool _absoluteCellsAreEmpty(
  TableState tableState,
  List<({int step, int col})> selectedCellsAbs,
) {
  if (selectedCellsAbs.isEmpty) return false;
  for (final cell in selectedCellsAbs) {
    final ptr = tableState.getCellPointer(cell.step, cell.col);
    if (ptr.address == 0) continue;
    final cellData = CellData.fromPointer(ptr);
    if (cellData.isNotEmpty && cellData.sampleSlot >= 0) return false;
  }
  return true;
}

class _JumpButtonWithFeedbackState extends State<_JumpButtonWithFeedback> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _isPressed = true);
      },
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onPressed();
      },
      onTapCancel: () {
        setState(() => _isPressed = false);
      },
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: _isPressed
              ? AppColors.sequencerAccent
              : AppColors.sequencerSurfaceRaised,
          borderRadius: BorderRadius.circular(3),
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
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: widget.horizontalPadding),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                widget.label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
                style: TextStyle(
                  fontSize: widget.fontSize,
                  fontWeight: FontWeight.w700,
                  color: _isPressed
                      ? AppColors.sequencerPageBackground
                      : AppColors.sequencerText,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Helper function for section deletion
void _deleteSectionWithConfirmation(
  BuildContext context,
  TableState tableState,
  UiSelectionState uiSelection,
) {
  final selectedSection = uiSelection.selectedSection;
  if (selectedSection == null) return;

  if (tableState.sectionsCount <= 1) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Cannot delete the last section'),
        backgroundColor: AppColors.sequencerAccent,
        duration: const Duration(seconds: 2),
      ),
    );
    return;
  }

  showDialog(
    context: context,
    barrierDismissible: true,
    barrierColor: AppColors.sequencerPageBackground.withOpacity(0.8),
    builder: (dialogContext) => _DeleteSectionDialog(
      sectionNumber: selectedSection + 1,
      onConfirm: () {
        tableState.deleteSection(selectedSection, undoRecord: true);

        // Adjust selection if needed
        if (selectedSection >= tableState.sectionsCount) {
          uiSelection.selectSection(tableState.sectionsCount - 1);
          tableState.setUiSelectedSection(tableState.sectionsCount - 1);
        } else {
          uiSelection.selectSection(selectedSection);
          tableState.setUiSelectedSection(selectedSection);
        }
      },
    ),
  );
}

// Delete confirmation dialog styled like share menu
class _DeleteSectionDialog extends StatelessWidget {
  final int sectionNumber;
  final VoidCallback onConfirm;

  const _DeleteSectionDialog({
    required this.sectionNumber,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final dialogWidth = (size.width * 0.8).clamp(280.0, size.width);
    final dialogHeight = (size.height * 0.35).clamp(220.0, size.height);

    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: ConstrainedBox(
          constraints:
              BoxConstraints.tightFor(width: dialogWidth, height: dialogHeight),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.sequencerSurfaceRaised,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.sequencerBorder, width: 0.5),
            ),
            clipBehavior: Clip.hardEdge,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Delete Section $sectionNumber?',
                          style: TextStyle(
                            color: AppColors.sequencerText,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: Icon(Icons.close,
                              color: AppColors.sequencerLightText, size: 24),
                          splashRadius: 20,
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 36, minHeight: 36),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'This action cannot be undone.',
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        color: AppColors.sequencerLightText,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.sequencerText,
                              side: BorderSide(
                                  color: AppColors.sequencerBorder, width: 0.5),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              minimumSize: const Size(0, 48),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              onConfirm();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              minimumSize: const Size(0, 48),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              elevation: 0,
                            ),
                            child: const Text('Delete',
                                style: TextStyle(fontWeight: FontWeight.w600)),
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
      ),
    );
  }
}
