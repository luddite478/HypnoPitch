import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../state/sequencer/edit.dart';
import '../../../state/app_state.dart';
import '../../../utils/app_colors.dart';
import 'wheel_select_widget.dart';

class StepInsertSettingsWidget extends StatefulWidget {
  const StepInsertSettingsWidget({super.key});

  @override
  State<StepInsertSettingsWidget> createState() => _StepInsertSettingsWidgetState();
}

class _StepInsertSettingsWidgetState extends State<StepInsertSettingsWidget> {
  // Simple variables for main layout areas (same as sound settings template)
  double _headerButtonsHeight = 0.45;     // 45% for header buttons area
  double _sliderTileHeightPercent = 0.50; // 50% for slider tile area
  double _spacingHeight = 0.02;           // 2% for spacing between areas

  @override
  Widget build(BuildContext context) {
    return Consumer2<EditState, AppState>(
      builder: (context, editState, appState, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            // Calculate responsive sizes based on available space - INHERIT from parent
            final panelHeight = constraints.maxHeight;
            
            // Padding & ratios
            final padding = panelHeight * 0.03;

            final innerHeight = panelHeight - padding * 2;
            final borderThickness = 1.0;
            final innerHeightAdj = innerHeight - borderThickness * 2;

            // Use the simple variables for layout calculations
            final headerHeight = innerHeightAdj * _headerButtonsHeight;
            final contentHeight = innerHeightAdj * _sliderTileHeightPercent;

            final labelFontSize = (headerHeight * 0.25).clamp(8.0, 11.0);
            
            return Container(
              padding: EdgeInsets.all(padding),
              decoration: BoxDecoration(
                color: AppColors.sequencerSurfaceBase,
                borderRadius: BorderRadius.circular(2), // Sharp corners
                border: Border.all(
                  color: AppColors.sequencerBorder,
                  width: 1,
                ),
                boxShadow: [
                  // Protruding effect
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
                children: [
                  // Header buttons area - controllable via _headerButtonsHeight
                  Expanded(
                    flex: (_headerButtonsHeight * 100).round(),
                    child: LayoutBuilder(
                      builder: (context, headerConstraints) {
                        return _buildScrollableHeader(headerHeight, labelFontSize, headerConstraints.maxWidth, editState);
                      },
                    ),
                  ),
                  
                  // Top spacer - controllable via _spacingHeight
                  Spacer(flex: (_spacingHeight * 100).round()),
                  
                  // Control tile area - controllable via _sliderTileHeightPercent
                  Expanded(
                    flex: (_sliderTileHeightPercent * 100).round(),
                    child: _buildJumpControl(
                      editState,
                      appState,
                      contentHeight,
                      padding,
                      labelFontSize,
                    ),
                  ),
                  
                  // Bottom spacer - controllable via _spacingHeight
                  Spacer(flex: (_spacingHeight * 100).round()),
                  
                  // Remaining space (auto-adjusts based on other areas)
                  Spacer(flex: ((1.0 - _headerButtonsHeight - _spacingHeight - _sliderTileHeightPercent - _spacingHeight) * 100).round().clamp(0, 100)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _getContextLabel() {
    return 'JUMP PASTE';
  }

  Widget _buildScrollableHeader(double headerHeight, double labelFontSize, double availableWidth, EditState editState) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(right: availableWidth * 0.02),
        child: Container(
          width: availableWidth * 0.30, // 30% of available width
          height: headerHeight * 0.7,
          padding: EdgeInsets.symmetric(
            horizontal: availableWidth * 0.03,
            vertical: headerHeight * 0.02,
          ),
          decoration: BoxDecoration(
            color: AppColors.sequencerSurfaceBase,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: AppColors.sequencerBorder, width: 1),
          ),
          child: Center(
            child: Text(
              _getContextLabel(),
              style: TextStyle(
                color: AppColors.sequencerLightText,
                fontSize: labelFontSize,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildJumpControl(
    EditState editState,
    AppState appState,
    double height,
    double padding,
    double fontSize,
  ) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: padding * 0.3, vertical: padding * 0.15),
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceRaised,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: AppColors.sequencerBorder,
          width: 1,
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
      child: Center(
        child: WheelSelectWidget(
          value: editState.stepInsertSize,
          minValue: 0,
          maxValue: 16,
          onValueChanged: (value) {
            editState.setStepInsertSize(value);
          },
          tutorialHighlightValue: appState.activeTutorialStep ==
                  TutorialStep.sequencerJumpValueTwoHint
              ? 2
              : null,
          tutorialItemKey: appState.activeTutorialStep ==
                  TutorialStep.sequencerJumpValueTwoHint
              ? appState.jumpValueTwoDisplayTutorialKey
              : null,
        ),
      ),
    );
  }
}
