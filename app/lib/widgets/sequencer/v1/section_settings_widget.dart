import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../utils/app_colors.dart';
import 'package:provider/provider.dart';
import '../../../state/app_state.dart';
import '../../../state/sequencer/table.dart';
import '../../../state/sequencer/playback.dart';
import '../../tutorial_pulse_widget.dart';

class SectionSettingsWidget extends StatefulWidget {
  final VoidCallback closeAction;
  final bool showCloseButton;

  const SectionSettingsWidget({
    super.key,
    required this.closeAction,
    this.showCloseButton = false,
  });

  @override
  State<SectionSettingsWidget> createState() => _SectionSettingsWidgetState();
}

class _SectionSettingsWidgetState extends State<SectionSettingsWidget> {
  String _selectedControl = 'LOOPS'; // Default to LOOPS
  
  // Simple variables for main layout areas (same as sound settings template)
  double _headerButtonsHeight = 0.45;     // 45% for header buttons area
  double _sliderTileHeightPercent = 0.50; // 50% for slider tile area
  double _spacingHeight = 0.02;           // 2% for spacing between areas

  @override
  Widget build(BuildContext context) {
    return Consumer2<TableState, PlaybackState>(
      builder: (context, tableState, playbackState, child) {
        final appState = context.watch<AppState>();
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
            
            // Get current section index
            final int currentSection = tableState.uiSelectedSection;
            
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
                        return _buildScrollableHeader(headerHeight, labelFontSize, headerConstraints.maxWidth, currentSection);
                      },
                    ),
                  ),
                  
                  // Top spacer - controllable via _spacingHeight
                  Spacer(flex: (_spacingHeight * 100).round()),
                  
                  // Control tile area - controllable via _sliderTileHeightPercent
                  Expanded(
                    flex: (_sliderTileHeightPercent * 100).round(),
                    child: (_selectedControl == 'STEPS' ||
                            appState.activeTutorialStep ==
                                TutorialStep.sequencerSectionTwoStepsHint)
                        ? _buildStepsControl(tableState, currentSection,
                            contentHeight, padding, appState)
                        : _buildLoopsControl(playbackState, currentSection,
                            contentHeight, padding, labelFontSize, appState),
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

  String _getContextLabel(int currentSection) {
    return 'Section ${currentSection + 1}';
  }

  Widget _buildScrollableHeader(double headerHeight, double labelFontSize, double availableWidth, int currentSection) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Context label tile showing which section is opened
            Padding(
              padding: EdgeInsets.only(right: availableWidth * 0.02),
              child: Container(
                width: availableWidth * 0.25, // 25% of available width
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
                    _getContextLabel(currentSection),
                    style: TextStyle(
                      color: AppColors.sequencerLightText,
                      fontSize: labelFontSize,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
            // LOOPS button
            Padding(
              padding: EdgeInsets.only(right: availableWidth * 0.02),
              child: SizedBox(
                width: availableWidth * 0.20, // 20% of available width
                child: _buildSettingsButton(
                  'LOOPS', 
                  _selectedControl == 'LOOPS', 
                  headerHeight * 0.7, 
                  labelFontSize, 
                  () {
                    setState(() {
                      _selectedControl = 'LOOPS';
                    });
                  }
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(right: availableWidth * 0.02),
              child: SizedBox(
                width: availableWidth * 0.20, // 20% of available width
                child: _buildSettingsButton(
                    'STEPS',
                    _selectedControl == 'STEPS',
                    headerHeight * 0.7,
                    labelFontSize, () {
                  setState(() {
                    _selectedControl = 'STEPS';
                  });
                }),
              ),
            ),
            
            // Optional spacing before action buttons
            if (widget.showCloseButton)
              SizedBox(width: availableWidth * 0.04),
            
            // Close button (if enabled)
            if (widget.showCloseButton)
              SizedBox(
                width: availableWidth * 0.15, // 15% of available width
                child: GestureDetector(
                  onTap: widget.closeAction,
                  child: Container(
                    height: headerHeight * 0.7,
                    decoration: BoxDecoration(
                      color: AppColors.sequencerSurfacePressed,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                        color: AppColors.sequencerBorder,
                        width: 0.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.sequencerShadow,
                          blurRadius: 1,
                          offset: const Offset(0, 0.5),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(
                        Icons.close,
                        color: AppColors.sequencerLightText,
                        size: headerHeight * 0.35,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsButton(String label, bool isSelected, double height, double fontSize, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: isSelected 
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
              color: isSelected 
                  ? AppColors.sequencerPageBackground 
                  : AppColors.sequencerText,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoopsControl(
    PlaybackState playbackState,
    int currentSection,
    double height,
    double padding,
    double fontSize,
    AppState appState,
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
      child: Builder(
        builder: (context) {
          // Get loops for the UI selected section (not necessarily the playing section)
          // Watch both currentSectionNotifier and currentSectionLoopsNumNotifier to update when section changes or loops change
          return ValueListenableBuilder<int>(
            valueListenable: playbackState.currentSectionNotifier,
            builder: (context, _, __) {
              return ValueListenableBuilder<int>(
                valueListenable: playbackState.currentSectionLoopsNumNotifier,
                builder: (context, __, ___) {
                  final loopCount = playbackState.getSectionLoopsNum(currentSection);
                  // Calculate responsive sizes for controls using percentages of available space
                  // Available height after vertical padding
                  final availableHeight = height - (padding * 0.3); // Subtract vertical padding
                  final buttonSize = availableHeight * 0.75; // 60% of available height
                  final counterWidth = availableHeight * 0.80; // 70% of available height for width
                  final counterHeight = availableHeight * 0.75; // 60% of available height
                  final spacing = availableHeight * 0.3; // 8% spacing between elements
                  
                  return Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Left arrow button
                        _buildArrowButton(
                          context,
                          icon: Icons.chevron_left,
                          onTap: () {
                            if (!appState.canInteractWithTutorialTarget(
                                TutorialInteractionTarget.sectionLoopsControl)) {
                              return;
                            }
                            if (loopCount > PlaybackState.minLoopsPerSection) {
                              playbackState.setSectionLoopsNum(currentSection, loopCount - 1);
                              HapticFeedback.selectionClick();
                            }
                          },
                          enabled: loopCount > PlaybackState.minLoopsPerSection,
                          size: buttonSize,
                        ),
                        
                        SizedBox(width: spacing),
                        
                        // Current loop count
                        Container(
                          width: counterWidth,
                          height: counterHeight,
                          decoration: BoxDecoration(
                            color: AppColors.sequencerSurfacePressed,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Center(
                            child: Text(
                              '$loopCount',
                              style: TextStyle(
                                color: AppColors.sequencerAccent,
                                fontSize: counterHeight * 0.75, // 65% of counter height for bigger digit
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        
                        SizedBox(width: spacing),
                        
                        // Right arrow button
                        _buildArrowButton(
                          context,
                          icon: Icons.chevron_right,
                          onTap: () {
                            if (!appState.canInteractWithTutorialTarget(
                                TutorialInteractionTarget.sectionLoopsControl)) {
                              return;
                            }
                            if (loopCount < PlaybackState.maxLoopsPerSection) {
                              playbackState.setSectionLoopsNum(currentSection, loopCount + 1);
                              HapticFeedback.selectionClick();
                            }
                          },
                          enabled: loopCount < PlaybackState.maxLoopsPerSection,
                          size: buttonSize,
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildArrowButton(BuildContext context, {
    Key? key,
    required IconData icon,
    required VoidCallback onTap,
    required bool enabled,
    required double size,
    bool pulseHighlight = false,
  }) {
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: TutorialPulseWidget(
        enabled: pulseHighlight,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: enabled 
                ? AppColors.sequencerSurfaceRaised
                : AppColors.sequencerSurfacePressed,
            borderRadius: BorderRadius.circular(4),
            boxShadow: enabled ? [
              BoxShadow(
                color: AppColors.sequencerShadow,
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ] : null,
          ),
          child: Center(
            child: Icon(
              icon,
              color: enabled 
                  ? AppColors.sequencerAccent
                  : AppColors.sequencerBorder,
              size: size * 0.70, // 70% of button size for bigger arrows
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepsControl(
    TableState tableState,
    int currentSection,
    double height,
    double padding,
    AppState appState,
  ) {
    return Container(
      padding:
          EdgeInsets.symmetric(horizontal: padding * 0.3, vertical: padding * 0.15),
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
      child: Builder(
        builder: (context) {
          final stepCount = tableState.getSectionStepCount(currentSection);
          final availableHeight = height - (padding * 0.3);
          final buttonSize = availableHeight * 0.75;
          final counterWidth = availableHeight * 1.05;
          final counterHeight = availableHeight * 0.75;
          final spacing = availableHeight * 0.3;

          return Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildArrowButton(
                  context,
                  key: appState.activeTutorialStep ==
                          TutorialStep.sequencerSectionTwoStepsHint
                      ? appState.sectionStepsDecreaseTutorialKey
                      : null,
                  icon: Icons.chevron_left,
                  onTap: () {
                    if (!appState.canInteractWithTutorialTarget(
                        TutorialInteractionTarget.sectionStepsDecrease)) {
                      return;
                    }
                    if (stepCount > 1) {
                      tableState.setSectionStepCount(currentSection, stepCount - 1);
                      HapticFeedback.selectionClick();
                    }
                  },
                  enabled: stepCount > 1,
                  size: buttonSize,
                ),
                SizedBox(width: spacing),
                Container(
                  width: counterWidth,
                  height: counterHeight,
                  decoration: BoxDecoration(
                    color: AppColors.sequencerSurfacePressed,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Center(
                    child: Text(
                      '$stepCount',
                      style: TextStyle(
                        color: AppColors.sequencerAccent,
                        fontSize: counterHeight * 0.6,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: spacing),
                _buildArrowButton(
                  context,
                  key: appState.activeTutorialStep ==
                          TutorialStep.sequencerSectionTwoStepsHint
                      ? appState.sectionStepsIncreaseTutorialKey
                      : null,
                  pulseHighlight: appState.activeTutorialStep ==
                      TutorialStep.sequencerSectionTwoStepsHint,
                  icon: Icons.chevron_right,
                  onTap: () {
                    if (!appState.canInteractWithTutorialTarget(
                        TutorialInteractionTarget.sectionStepsIncrease)) {
                      return;
                    }
                    if (stepCount < tableState.maxSteps) {
                      tableState.setSectionStepCount(currentSection, stepCount + 1);
                      HapticFeedback.selectionClick();
                    }
                  },
                  enabled: stepCount < tableState.maxSteps,
                  size: buttonSize,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

