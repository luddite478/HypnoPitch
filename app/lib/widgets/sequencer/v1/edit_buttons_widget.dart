import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../utils/app_colors.dart';
import '../../../state/sequencer/edit.dart';
import '../../../state/sequencer/multitask_panel.dart';
import '../../../state/sequencer/table.dart';
import '../../../state/sequencer/sample_bank.dart';
import '../../../state/sequencer/ui_selection.dart';

class EditButtonsWidget extends StatelessWidget {
  const EditButtonsWidget({super.key});

  // Percent-based sizing configuration for layouts
  static const double _v1ButtonSizePercent = 0.6; // of container height
  static const double _v1HorizontalPaddingPercent = 0.1; // of container height

  // V2 percent-based configuration
  static const double _v2ButtonHeightPercent = 0.7; // of container height
  static const double _v2RightPaddingPercent = 0.03; // of container width
  static const double _v2ButtonHorizontalPaddingPercent = 0.035; // of container height
  static const double _v2ButtonSpacingPercent = 0.015; // of container width
  static const double _v2TextFontScale = 0.23; // of button height
  static const double _v2PerButtonWidthPercent = 0.162; // of container width

  @override
  Widget build(BuildContext context) {
    return Consumer4<TableState, EditState, SampleBankState, UiSelectionState>(
      builder: (context, tableState, editState, sampleBankState, uiSelection, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final panelHeight = constraints.maxHeight;
            final panelWidth = constraints.maxWidth;

            if (tableState.uiEditButtonsLayoutMode == EditButtonsLayoutMode.v2) {
              // V2: Text buttons, equal size via percents, right-aligned, with small inactive left chevron
              final buttonHeight = (panelHeight * _v2ButtonHeightPercent).clamp(20.0, 64.0);
              final textFontSize = (buttonHeight * _v2TextFontScale).clamp(10.0, 22.0);
              final buttonHPad = (panelHeight * _v2ButtonHorizontalPaddingPercent).clamp(6.0, 18.0);
              final spacing = (panelWidth * _v2ButtonSpacingPercent).clamp(4.0, 16.0);
              final buttonWidth = panelWidth * _v2PerButtonWidthPercent;

              return Container(
                padding: EdgeInsets.only(right: panelWidth * _v2RightPaddingPercent),
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
                        label: 'SELECT',
                        height: buttonHeight,
                        fontSize: textFontSize,
                        enabled: true,
                        onPressed: () => editState.toggleSelectionMode(),
                        isActive: editState.isInSelectionMode,
                        horizontalPadding: buttonHPad,
                      ),
                    ),
                    SizedBox(width: spacing),
                    SizedBox(
                      width: buttonWidth,
                      child: _buildTextActionButton(
                        label: 'JUMP ${editState.stepInsertSize}',
                        height: buttonHeight,
                        fontSize: textFontSize,
                        enabled: true,
                        onPressed: () {
                          editState.toggleStepInsertMode();
                          Provider.of<MultitaskPanelState>(context, listen: false).showStepInsertSettings();
                        },
                        isActive: editState.isStepInsertMode,
                        horizontalPadding: buttonHPad,
                      ),
                    ),
                    SizedBox(width: spacing),
                    SizedBox(
                      width: buttonWidth,
                      child: _buildTextActionButton(
                        label: 'DEL',
                        height: buttonHeight,
                        fontSize: textFontSize,
                        enabled: editState.hasSelection || uiSelection.isSampleBank,
                        onPressed: (editState.hasSelection || uiSelection.isSampleBank)
                            ? () {
                                if (uiSelection.isSampleBank) {
                                  final slot = uiSelection.selectedSampleSlot ?? sampleBankState.activeSlot;
                                  sampleBankState.unloadSample(slot);
                                  uiSelection.clear();
                                } else {
                                  editState.deleteCells();
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
                        label: 'COPY',
                        height: buttonHeight,
                        fontSize: textFontSize,
                        enabled: editState.hasSelection,
                        onPressed: editState.hasSelection ? () => editState.copyCells() : null,
                        isActive: false,
                        horizontalPadding: buttonHPad,
                      ),
                    ),
                    SizedBox(width: spacing),
                    SizedBox(
                      width: buttonWidth,
                      child: _buildTextActionButton(
                        label: 'PASTE',
                        height: buttonHeight,
                        fontSize: textFontSize,
                        enabled: editState.hasClipboardData && editState.hasSelection,
                        onPressed: (editState.hasClipboardData && editState.hasSelection)
                            ? () => editState.pasteCells()
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
            final buttonSize = (panelHeight * _v1ButtonSizePercent).clamp(20.0, 48.0);
            final iconSize = (buttonSize * 0.6).clamp(16.0, 32.0);

            return Container(
              padding: EdgeInsets.symmetric(horizontal: panelHeight * _v1HorizontalPaddingPercent),
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
                    icon: editState.isInSelectionMode ? Icons.check_box : Icons.check_box_outline_blank,
                    color: editState.isInSelectionMode ? AppColors.sequencerAccent : AppColors.sequencerLightText,
                    onPressed: () => editState.toggleSelectionMode(),
                    tooltip: editState.isInSelectionMode ? 'Exit Selection Mode' : 'Enter Selection Mode',
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
                    color: (editState.hasSelection || context.read<UiSelectionState>().isSampleBank)
                        ? AppColors.sequencerAccent.withOpacity(0.8)
                        : AppColors.sequencerLightText,
                    onPressed: (editState.hasSelection || context.read<UiSelectionState>().isSampleBank)
                        ? () {
                            final uiSel = context.read<UiSelectionState>();
                            final sb = context.read<SampleBankState>();
                            if (uiSel.isSampleBank) {
                              final slot = uiSel.selectedSampleSlot ?? sb.activeSlot;
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
                    onPressed: editState.hasClipboardData && editState.hasSelection
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
          color: editState.isStepInsertMode ? AppColors.sequencerAccent : AppColors.sequencerBorder,
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
            Provider.of<MultitaskPanelState>(context, listen: false).showStepInsertSettings();
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
                    margin: const EdgeInsets.only(top: 2), // Add 4 pixels top margin
                    child: Text(
                      '${editState.stepInsertSize}',
                      style: TextStyle(
                        color: editState.isStepInsertMode ? AppColors.sequencerAccent : AppColors.sequencerLightText,
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
                      color: editState.isStepInsertMode ? AppColors.sequencerAccent : AppColors.sequencerLightText,
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
    required String label,
    required double height,
    required double fontSize,
    required bool enabled,
    required VoidCallback? onPressed,
    required bool isActive,
    required double horizontalPadding,
  }) {
    final backgroundColor = enabled
        ? AppColors.sequencerSurfaceRaised
        : AppColors.sequencerSurfacePressed;
    final textColor = isActive
        ? AppColors.sequencerAccent
        : (enabled ? AppColors.sequencerText : AppColors.sequencerLightText);
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: isActive ? AppColors.sequencerAccent : AppColors.sequencerBorder,
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