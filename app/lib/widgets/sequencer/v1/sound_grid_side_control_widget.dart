import 'package:flutter/material.dart';
// duplicate import removed
import 'package:provider/provider.dart';
import '../../../state/app_state.dart';
import '../../../state/sequencer/section_settings.dart';
import '../../../state/sequencer/multitask_panel.dart';
import '../../../state/sequencer/undo_redo.dart';
import '../../../state/sequencer/table.dart';
import '../../../state/sequencer/playback.dart';
import '../../../utils/app_colors.dart';

enum SideControlSide { left, right }

class SoundGridSideControlWidget extends StatelessWidget {
  final SideControlSide side;
  final VoidCallback? onBack;
  final VoidCallback? onSettings;
  final VoidCallback? onRecordings;

  const SoundGridSideControlWidget({
    super.key,
    this.side = SideControlSide.left,
    this.onBack,
    this.onSettings,
    this.onRecordings,
  });

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final sectionSettings = context.watch<SectionSettingsState>();
    final multitaskPanel = context.watch<MultitaskPanelState>();
    final playbackState = context.watch<PlaybackState>();
    // final editState = context.watch<EditState>(); // reserved for future selection-mode awareness
    final undoRedo = context.watch<UndoRedoState>();
    final tableState = context.watch<TableState>();
    return Builder(
      builder: (context) {
        return LayoutBuilder(
          builder: (context, constraints) {
            // Calculate responsive button size based on available space
            final availableHeight = constraints.maxHeight;
            final availableWidth = constraints.maxWidth;
            
            final bool hideButtons = sectionSettings.isSectionCreationOpen || tableState.sectionsCount == 0;

            // Use 90% of available height for buttons, leaving small margins
            final buttonsAreaHeight = availableHeight * 0.9;
            // Right side: 3 buttons divided evenly
            final int buttonCount = 3;

            // Button width should use most of available width
            final buttonWidth = availableWidth * 0.8;

            // Right side only: divide height evenly
            final buttonSpacing = buttonsAreaHeight * 0.05;
            final buttonHeight = (buttonsAreaHeight - ((buttonCount - 1) * buttonSpacing)) / buttonCount;

            // Icon size: for right side based on buttonHeight, for left side based on buttonWidth (square)
            final iconSize = side == SideControlSide.left
                ? (buttonWidth * 0.5).clamp(12.0, 24.0)
                : (buttonHeight * 0.5).clamp(14.0, 28.0);
            
            return Container(
              width: availableWidth,
              height: availableHeight,
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
              child: hideButtons
                  ? const SizedBox.shrink()
                  : side == SideControlSide.left
                  // ── Left side: Expanded layout — no overflow possible ─────────
                  ? Column(
                      children: [
                        // Nav: menu / settings / takes
                        Expanded(
                          child: _buildSquareButton(
                            key: appState.activeTutorialStep ==
                                        TutorialStep.sequencerBackToPatternHint
                                ? appState.patternMenuButtonTutorialKey
                                : null,
                            size: buttonWidth,
                            icon: Icons.menu,
                            color: AppColors.sequencerLightText,
                            onPressed: (appState.isTutorialRunning &&
                                    appState.activeTutorialStep !=
                                        TutorialStep.sequencerBackToPatternHint)
                                ? null
                                : () {
                                    if (!appState.canInteractWithTutorialTarget(
                                      TutorialInteractionTarget.patternMenuButton,
                                    )) {
                                      return;
                                    }
                                    onBack?.call();
                                  },
                          ),
                        ),
                        const SizedBox(height: 3),
                        Expanded(
                          child: _buildSquareButton(
                            size: buttonWidth,
                            icon: Icons.graphic_eq,
                            color: AppColors.sequencerAccent,
                            onPressed: appState.canInteractWithTutorialTarget(
                              TutorialInteractionTarget.recordingsButton,
                            )
                                ? onRecordings
                                : null,
                          ),
                        ),
                        const SizedBox(height: 3),
                        // Sequencer: section / loop / redo / undo
                        Expanded(child: _SectionControlButton(
                          key: appState.activeTutorialStep ==
                                      TutorialStep.sequencerSectionLoopsHint
                              ? appState.sectionSettingsButtonTutorialKey
                              : null,
                          size: buttonWidth,
                          sectionNumber: tableState.uiSelectedSection + 1,
                          onPressed: () {
                            if (!appState.canInteractWithTutorialTarget(
                                TutorialInteractionTarget.sectionSettingsButton)) {
                              return;
                            }
                            if (multitaskPanel.currentMode == MultitaskPanelMode.sectionSettings) {
                              multitaskPanel.showPlaceholder();
                            } else {
                              multitaskPanel.showSectionSettings();
                            }
                          },
                        )),
                        const SizedBox(height: 3),
                        Expanded(child: _buildSquareButton(
                          key: appState.activeTutorialStep ==
                                      TutorialStep.sequencerSongModeHint
                              ? appState.songModeButtonTutorialKey
                              : null,
                          size: buttonWidth,
                          icon: Icons.repeat,
                          color: playbackState.songModeNotifier.value == false ? Colors.white : AppColors.sequencerLightText,
                          backgroundColor: playbackState.songModeNotifier.value == false ? AppColors.sequencerPrimaryButton : null,
                          onPressed: appState.canInteractWithTutorialTarget(
                            TutorialInteractionTarget.songModeButton,
                          )
                              ? () => playbackState
                                  .setSongMode(!playbackState.songModeNotifier.value)
                              : null,
                        )),
                        const SizedBox(height: 3),
                        Expanded(child: _buildSquareButton(
                          key: appState.activeTutorialStep ==
                                      TutorialStep.sequencerUndoRedoHint
                              ? appState.redoButtonTutorialKey
                              : null,
                          size: buttonWidth,
                          icon: Icons.redo,
                          color: undoRedo.canRedo ? AppColors.sequencerAccent : AppColors.sequencerLightText,
                          onPressed: undoRedo.canRedo
                              ? () {
                                  if (!appState.canInteractWithTutorialTarget(
                                      TutorialInteractionTarget.redoButton)) {
                                    return;
                                  }
                                  undoRedo.redo();
                                  appState.markRedoAction();
                                }
                              : null,
                        )),
                        const SizedBox(height: 3),
                        Expanded(child: _buildSquareButton(
                          key: appState.activeTutorialStep ==
                                      TutorialStep.sequencerUndoRedoHint
                              ? appState.undoButtonTutorialKey
                              : null,
                          size: buttonWidth,
                          icon: Icons.undo,
                          color: undoRedo.canUndo ? AppColors.sequencerAccent : AppColors.sequencerLightText,
                          onPressed: undoRedo.canUndo
                              ? () {
                                  if (!appState.canInteractWithTutorialTarget(
                                      TutorialInteractionTarget.undoButton)) {
                                    return;
                                  }
                                  undoRedo.undo();
                                  appState.markUndoAction();
                                }
                              : null,
                        )),
                      ],
                    )
                  // ── Right side: original fixed-height layout ──────────────────
                  : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Right Side: Previous, Next, Redo
                  _buildSideControlButton(
                    width: buttonWidth,
                    height: buttonHeight,
                    iconSize: iconSize,
                    icon: Icons.chevron_left,
                    color: tableState.sectionsCount > 1 
                        ? AppColors.sequencerLightText 
                        : AppColors.sequencerLightText.withOpacity(0.5),
                    onPressed: tableState.sectionsCount > 1 
                        ? (appState.isTutorialRunning
                            ? null
                            : () => tableState.setUiSelectedSection((tableState.uiSelectedSection - 1).clamp(0, tableState.sectionsCount - 1)))
                        : null,
                    tooltip: tableState.sectionsCount > 1 
                        ? 'Previous Section (${tableState.uiSelectedSection + 1}/${tableState.sectionsCount})'
                        : 'Only 1 Section',
                  ),
                  SizedBox(height: buttonSpacing),
                  _buildSideControlButton(
                    width: buttonWidth,
                    height: buttonHeight,
                    iconSize: iconSize,
                    icon: Icons.chevron_right,
                    color: AppColors.sequencerLightText,
                    onPressed: appState.isTutorialRunning
                        ? null
                        : () {
                            if (tableState.uiSelectedSection == tableState.sectionsCount - 1) {
                              sectionSettings.openSectionCreationOverlay();
                            } else {
                              tableState.setUiSelectedSection((tableState.uiSelectedSection + 1).clamp(0, tableState.sectionsCount - 1));
                            }
                          },
                    tooltip: tableState.uiSelectedSection == tableState.sectionsCount - 1 
                        ? 'New Section'
                        : 'Next Section (${tableState.uiSelectedSection + 2}/${tableState.sectionsCount})',
                  ),
                  SizedBox(height: buttonSpacing),
                  _buildSideControlButton(
                    width: buttonWidth,
                    height: buttonHeight,
                    iconSize: iconSize,
                    icon: Icons.redo,
                    color: undoRedo.canRedo ? AppColors.sequencerAccent : AppColors.sequencerLightText,
                    onPressed: undoRedo.canRedo &&
                            appState.canInteractWithTutorialTarget(
                              TutorialInteractionTarget.redoButton,
                            )
                        ? () => undoRedo.redo()
                        : null,
                    tooltip: undoRedo.canRedo ? 'Redo' : 'Nothing to Redo',
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSideControlButton({
    required double width,
    required double height,
    required double iconSize,
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
    required String tooltip,
    Color? backgroundColor,
  }) {
    final isEnabled = onPressed != null;
    
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: backgroundColor ?? (isEnabled 
            ? AppColors.sequencerSurfaceRaised 
            : AppColors.sequencerSurfacePressed),
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
            child: Center(
              child: Icon(
                icon,
                color: color,
                size: iconSize,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Left-side panel button: fixed width, fills available height via Expanded
  Widget _buildSquareButton({
    Key? key,
    required double size,
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
    Color? backgroundColor,
  }) {
    final isEnabled = onPressed != null;
    final iconSize = (size * 0.5).clamp(12.0, 22.0);
    return GestureDetector(
      key: key,
      onTap: onPressed,
      child: Container(
        width: size,
        height: double.infinity, // fills the Expanded slot height
        decoration: BoxDecoration(
          color: backgroundColor ?? (isEnabled
              ? AppColors.sequencerSurfaceRaised
              : AppColors.sequencerSurfacePressed),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: AppColors.sequencerBorder, width: 0.5),
          boxShadow: isEnabled
              ? [
                  BoxShadow(color: AppColors.sequencerShadow, blurRadius: 1.5, offset: const Offset(0, 1)),
                  BoxShadow(color: AppColors.sequencerSurfaceRaised, blurRadius: 0.5, offset: const Offset(0, -0.5)),
                ]
              : [BoxShadow(color: AppColors.sequencerShadow, blurRadius: 1, offset: const Offset(0, 0.5))],
        ),
        child: Center(child: Icon(icon, color: color, size: iconSize)),
      ),
    );
  }

}

// Stateful section control button with click feedback
class _SectionControlButton extends StatefulWidget {
  final double size; // square size
  final int sectionNumber;
  final VoidCallback onPressed;

  const _SectionControlButton({
    super.key,
    required this.size,
    required this.sectionNumber,
    required this.onPressed,
  });

  @override
  State<_SectionControlButton> createState() => _SectionControlButtonState();
}

class _SectionControlButtonState extends State<_SectionControlButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final playbackState = context.watch<PlaybackState>();
    
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
        width: widget.size,
        height: double.infinity, // fills the Expanded slot height
        decoration: BoxDecoration(
          color: _isPressed
              ? AppColors.sequencerPrimaryButton
              : AppColors.sequencerSurfaceRaised,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: AppColors.sequencerBorder, width: 0.5),
          boxShadow: [
            BoxShadow(color: AppColors.sequencerShadow, blurRadius: 1.5, offset: const Offset(0, 1)),
            BoxShadow(color: AppColors.sequencerSurfaceRaised, blurRadius: 0.5, offset: const Offset(0, -0.5)),
          ],
        ),
        // FittedBox prevents any text overflow by scaling content to fit the square
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
              Text(
                '${widget.sectionNumber}',
                style: TextStyle(
                  color: _isPressed
                      ? Colors.white
                      : AppColors.sequencerLightText,
                  fontSize: widget.size * 0.55,
                  fontWeight: FontWeight.w700,
                  height: 0.9,
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: playbackState.songModeNotifier,
                builder: (context, isSongMode, __) {
                  if (!isSongMode) {
                    // Loop mode: show infinity symbol
                    final color = Color.lerp(AppColors.menuErrorColor, AppColors.sequencerLightText, 0.5)!;
                    return Text(
                          '∞',
                          style: TextStyle(
                            color: color,
                            fontSize: widget.size * 0.55,
                            fontWeight: FontWeight.w600,
                            height: 1.0,
                          ),
                        );
                  } else {
                    // Song mode: show loop counter
                    return ValueListenableBuilder<int>(
                      valueListenable: playbackState.currentSectionLoopNotifier,
                      builder: (context, currentLoopZeroBased, __) {
                        return ValueListenableBuilder<int>(
                          valueListenable: playbackState.currentSectionLoopsNumNotifier,
                          builder: (context, totalLoops, ___) {
                            final displayCurrent = (currentLoopZeroBased + 1).clamp(1, totalLoops);
                            final label = '$displayCurrent/$totalLoops';
                            final color = Color.lerp(AppColors.menuErrorColor, AppColors.sequencerLightText, 0.5)!;
                            return Text(
                                  label,
                                  style: TextStyle(
                                    color: color,
                                    fontSize: widget.size * 0.35,
                                    fontWeight: FontWeight.w600,
                                    height: 1.0,
                                    letterSpacing: 0.2,
                                  ),
                            );
                          },
                        );
                      },
                    );
                  }
                },
              ),
            ],
          ),   // Column
        ),     // Padding
      ),       // FittedBox
    ),         // Container
  );           // GestureDetector
  }
} 