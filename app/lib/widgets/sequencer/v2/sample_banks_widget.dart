import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../utils/app_colors.dart';
import '../../../state/sequencer/sample_bank.dart';
import '../../../state/sequencer/sample_browser.dart';
import '../../../state/sequencer/playback.dart';
import '../../../state/sequencer/table.dart';
import '../../../state/sequencer/multitask_panel.dart';
import '../../../state/sequencer/ui_selection.dart';

class SampleBanksWidget extends StatefulWidget {
  const SampleBanksWidget({super.key});

  @override
  State<SampleBanksWidget> createState() => _SampleBanksWidgetState();
}

class _SampleBanksWidgetState extends State<SampleBanksWidget> {
  int _startIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Consumer5<SampleBankState, PlaybackState, SampleBrowserState, TableState, UiSelectionState>(
      builder: (context, sampleBankState, playbackState, sampleBrowserState, tableState, uiSelection, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final panelHeight = constraints.maxHeight;
            final panelWidth = constraints.maxWidth;

            final padding = panelHeight * 0.05;
            final baseButtonsWidth = panelWidth; // container has zero padding
            final preferredButtonWidth = baseButtonsWidth / 7.5; // baseline
            final buttonHeight = panelHeight * 0.8;
            final letterSize = (buttonHeight * 0.35).clamp(10.0, double.infinity);
            const borderRadius = 2.0;

            final arrowWidth = preferredButtonWidth * 0.8;
            final arrowHeight = buttonHeight * 0.8;
            final sampleMarginH = padding * 0.3;
            // Zero inner margin between arrows and tiles
            final leftArrowMarginLeft = 0.0;
            final leftArrowMarginRight = 0.0;
            final rightArrowMarginLeft = 0.0;
            final rightArrowMarginRight = 0.0;

            final totalArrowMargins = leftArrowMarginLeft + leftArrowMarginRight + rightArrowMarginLeft + rightArrowMarginRight;
            final availableRowWidth = baseButtonsWidth - (arrowWidth * 2) - totalArrowMargins;
            final preferredTileWithMargins = preferredButtonWidth + 2 * sampleMarginH;
            // Changed from 16 to 25: Show all user-accessible slots (A-Y)
            // Slot 25 (Z) is reserved for preview and not shown in UI
            int visibleCount = availableRowWidth > 0
                ? (availableRowWidth / preferredTileWithMargins).floor().clamp(1, 25)
                : 1;
            if (visibleCount < 1) visibleCount = 1;
            final totalInterTileMargins = (visibleCount - 1) * (2 * sampleMarginH);
            final buttonWidth = ((availableRowWidth - totalInterTileMargins) / visibleCount).floorToDouble();

            // Update max index to 25 (A-Y are user slots, Z is preview slot)
            final maxStart = (25 - visibleCount).clamp(0, 25);
            final startIndex = _startIndex.clamp(0, maxStart);
            final endIndex = (startIndex + visibleCount).clamp(0, 25);
            final effectiveCount = (endIndex - startIndex).clamp(0, visibleCount);

            void goLeft() {
              if (startIndex > 0) {
                setState(() {
                  _startIndex = (startIndex - visibleCount).clamp(0, maxStart);
                });
              }
            }

            void goRight() {
              if (startIndex < maxStart) {
                setState(() {
                  _startIndex = (startIndex + visibleCount).clamp(0, maxStart);
                });
              }
            }

            return Container(
              padding: EdgeInsets.zero,
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
              child: SizedBox(
                width: double.infinity,
                height: panelHeight,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _ArrowTile(
                      enabled: startIndex > 0,
                      onTap: goLeft,
                      icon: Icons.chevron_left,
                      width: arrowWidth,
                      height: arrowHeight,
                      marginLeft: leftArrowMarginLeft,
                      marginRight: leftArrowMarginRight,
                      borderRadius: borderRadius,
                    ),
                    Expanded(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (int i = 0; i < effectiveCount; i++)
                            _buildBankButton(
                              context: context,
                              sampleBankState: sampleBankState,
                              playbackState: playbackState,
                              sampleBrowserState: sampleBrowserState,
                              tableState: tableState,
                              bank: startIndex + i,
                              buttonHeight: buttonHeight,
                              buttonWidth: buttonWidth,
                              leftMargin: i == 0 ? 0.0 : sampleMarginH,
                              rightMargin: i == effectiveCount - 1 ? 0.0 : sampleMarginH,
                              borderRadius: borderRadius,
                              letterSize: letterSize,
                            ),
                        ],
                      ),
                    ),
                    _ArrowTile(
                      enabled: startIndex < maxStart,
                      onTap: goRight,
                      icon: Icons.chevron_right,
                      width: arrowWidth,
                      height: arrowHeight,
                      marginLeft: rightArrowMarginLeft,
                      marginRight: rightArrowMarginRight,
                      borderRadius: borderRadius,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBankButton({
    required BuildContext context,
    required SampleBankState sampleBankState,
    required PlaybackState playbackState,
    required SampleBrowserState sampleBrowserState,
    required TableState tableState,
    required int bank,
    required double buttonHeight,
    required double buttonWidth,
    required double leftMargin,
    required double rightMargin,
    required double borderRadius,
    required double letterSize,
  }) {
    final isActive = sampleBankState.activeSlot == bank;
    final isSelected = context.read<UiSelectionState>().isSampleBank && sampleBankState.activeSlot == bank;
    final hasFile = sampleBankState.isSlotLoaded(bank);

    Widget sampleButton = Container(
      height: buttonHeight,
      width: buttonWidth,
      margin: EdgeInsets.only(left: leftMargin, right: rightMargin),
      decoration: BoxDecoration(
        color: _getButtonColor(isSelected, isActive, hasFile, bank, sampleBankState),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: isSelected
              ? AppColors.sequencerSelectionBorder
              : _getButtonColor(isSelected, isActive, hasFile, bank, sampleBankState),
          width: isSelected ? 2 : 0.5,
        ),
        boxShadow: _getBoxShadow(isSelected, isActive),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              String.fromCharCode(65 + bank),
              style: TextStyle(
                color: _getTextColor(isSelected, isActive, hasFile),
                fontWeight: FontWeight.w600,
                fontSize: letterSize,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );

    return hasFile
        ? Draggable<int>(
            data: bank,
            feedback: Container(
              width: buttonWidth * 0.9,
              height: buttonHeight,
              decoration: BoxDecoration(
                color: _getButtonColorForBank(bank, sampleBankState).withOpacity(0.9),
                borderRadius: BorderRadius.circular(borderRadius),
                border: Border.all(color: AppColors.sequencerAccent, width: 2),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      String.fromCharCode(65 + bank),
                      style: TextStyle(
                        color: AppColors.sequencerText,
                        fontWeight: FontWeight.w600,
                        fontSize: letterSize,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            childWhenDragging: Container(
              height: buttonHeight,
              width: buttonWidth,
              margin: EdgeInsets.only(left: leftMargin, right: rightMargin),
              decoration: BoxDecoration(
                color: AppColors.sequencerSurfacePressed,
                borderRadius: BorderRadius.circular(borderRadius),
                border: Border.all(
                  color: AppColors.sequencerBorder,
                  width: 1,
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      String.fromCharCode(65 + bank),
                      style: TextStyle(
                        color: AppColors.sequencerLightText,
                        fontWeight: FontWeight.w600,
                        fontSize: letterSize,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            child: GestureDetector(
              onTap: () {
                sampleBankState.uiHandleBankChange(bank);
                context.read<UiSelectionState>().selectSampleBank(bank);
                // Open sample settings for filled slot
                Provider.of<MultitaskPanelState>(context, listen: false).showSampleSettings();
              },
              onLongPress: () => sampleBankState.uiPickFileForSlot(bank),
              child: sampleButton,
            ),
          )
        : GestureDetector(
            onTap: () {
              sampleBankState.uiHandleBankChange(bank);
              context.read<UiSelectionState>().selectSampleBank(bank);
              // If the slot is empty, open sample browser
              if (!sampleBankState.isSlotLoaded(bank)) {
                sampleBrowserState.showForSlot(bank);
              }
            },
            onLongPress: () => sampleBankState.uiPickFileForSlot(bank),
            child: sampleButton,
          );
  }

  Color _getButtonColor(bool isSelected, bool isActive, bool hasFile, int bank, SampleBankState sampleBankState) {
    if (hasFile) {
      return _getButtonColorForBank(bank, sampleBankState);
    } else {
      return AppColors.sequencerSurfacePressed;
    }
  }

  Color _getButtonColorForBank(int bank, SampleBankState sampleBankState) {
    final colors = sampleBankState.uiBankColors;
    final originalColor = bank < colors.length ? colors[bank] : colors[0];
    return Color.lerp(originalColor, AppColors.sequencerCellFilled, 0.3) ?? AppColors.sequencerCellFilled;
  }

  List<BoxShadow>? _getBoxShadow(bool isSelected, bool isActive) {
    if (isSelected) {
      return null;
    } else {
      return [
        BoxShadow(
          color: AppColors.sequencerShadow,
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
        BoxShadow(
          color: AppColors.sequencerSurfaceRaised,
          blurRadius: 1,
          offset: const Offset(0, -0.5),
        ),
      ];
    }
  }

  Color _getTextColor(bool isSelected, bool isActive, bool hasFile) {
    return AppColors.sequencerText;
  }
}

class _ArrowTile extends StatelessWidget {
  final bool enabled;
  final VoidCallback? onTap;
  final IconData icon;
  final double width;
  final double height;
  final double marginLeft;
  final double marginRight;
  final double borderRadius;

  const _ArrowTile({
    required this.enabled,
    required this.onTap,
    required this.icon,
    required this.width,
    required this.height,
    required this.marginLeft,
    required this.marginRight,
    required this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: EdgeInsets.only(left: marginLeft, right: marginRight),
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfacePressed,
        borderRadius: BorderRadius.circular(borderRadius),
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
          BoxShadow(
            color: AppColors.sequencerSurfaceRaised,
            blurRadius: 1,
            offset: const Offset(0, -0.5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(borderRadius),
          child: Center(
            child: Icon(
              icon,
              size: height * 0.5,
              color: enabled ? AppColors.sequencerText : AppColors.sequencerLightText,
            ),
          ),
        ),
      ),
    );
  }
}
