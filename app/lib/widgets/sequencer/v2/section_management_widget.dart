import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../state/sequencer/playback.dart';
import '../../../state/sequencer/table.dart';
import '../../../state/sequencer/ui_selection.dart';
import '../../../utils/app_colors.dart';

class SectionManagementWidget extends StatelessWidget {
  const SectionManagementWidget({super.key});

  static const Color _filmBase = Color(0xFF1E1E1C);
  static const Color _filmFrameAperture = Color(0xFF2A2A27);

  // Responsive sizing percentages
  static const double _paddingPercent = 0.025;
  static const double _innerPaddingPercent = 0.02;
  static const double _sectionWidthPercent = 0.28;
  static const double _gapWidthPercent = 0.065;
  static const double _sectionHeightPercent = 0.84;
  static const double _minSectionWidth = 56.0;
  static const double _maxSectionWidth = 84.0;
  static const double _minGapWidth = 24.0;
  static const double _maxGapWidth = 40.0;
  static const double _maxSectionHeight = 64.0;

  @override
  Widget build(BuildContext context) {
    return Consumer3<TableState, PlaybackState, UiSelectionState>(
      builder: (context, tableState, playbackState, uiSelection, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final panelHeight = constraints.maxHeight;
            final panelWidth = constraints.maxWidth;

            final padding = panelHeight * _paddingPercent;
            final innerHeight = panelHeight - (padding * 2);
            final innerHeightAdj = innerHeight - 2;
            final sectionTapeHeight =
                (innerHeightAdj * _sectionHeightPercent).clamp(0.0, _maxSectionHeight);
            final sectionNumberFontSize = (sectionTapeHeight * 0.36).clamp(15.0, 24.0);

            return Container(
              padding: EdgeInsets.all(padding),
              decoration: BoxDecoration(
                color: AppColors.sequencerSurfaceBase,
                borderRadius: BorderRadius.circular(2),
                border: Border.all(color: AppColors.sequencerBorder, width: 1),
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
              child: _buildSectionTape(
                tableState,
                playbackState,
                uiSelection,
                panelWidth,
                sectionTapeHeight,
                sectionNumberFontSize,
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSectionTape(
    TableState tableState,
    PlaybackState playbackState,
    UiSelectionState uiSelection,
    double panelWidth,
    double sectionHeight,
    double fontSize,
  ) {
    final sectionWidth = (panelWidth * _sectionWidthPercent).clamp(_minSectionWidth, _maxSectionWidth);
    final gapWidth = (panelWidth * _gapWidthPercent).clamp(_minGapWidth, _maxGapWidth);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: panelWidth * _innerPaddingPercent,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceRaised,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.sequencerBorder, width: 1),
      ),
      child: LayoutBuilder(
        builder: (context, tapeConstraints) {
          final maxHeight = tapeConstraints.maxHeight.isFinite
              ? tapeConstraints.maxHeight
              : sectionHeight;
          final minSafeHeight = maxHeight < 28 ? maxHeight : 28.0;
          final safeSectionHeight =
              (sectionHeight > 0 ? sectionHeight : maxHeight).clamp(minSafeHeight, maxHeight);

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              height: safeSectionHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: _buildSectionElements(
                  tableState,
                  playbackState,
                  uiSelection,
                  sectionWidth,
                  gapWidth,
                  safeSectionHeight,
                  fontSize,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildSectionElements(
    TableState tableState,
    PlaybackState playbackState,
    UiSelectionState uiSelection,
    double sectionWidth,
    double gapWidth,
    double sectionHeight,
    double fontSize,
  ) {
    final sectionsCount = tableState.sectionsCount;
    final isPlaying = playbackState.isPlaying;
    final currentPlayingSection = playbackState.currentSection;
    final selectedSection = uiSelection.selectedSection;
    final uiSelectedSection = tableState.uiSelectedSection;

    final elements = <Widget>[];

    for (int i = 0; i < sectionsCount; i++) {
      elements.add(
        _buildGap(
          i - 1,
          gapWidth,
          sectionHeight,
          tableState,
          uiSelection,
          playbackState,
        ),
      );

      elements.add(
        _buildSectionCard(
          sectionIndex: i,
          isPlaying: isPlaying && i == currentPlayingSection,
          isSelected: selectedSection == i,
          isUiSelected: uiSelectedSection == i,
          width: sectionWidth,
          height: sectionHeight,
          fontSize: fontSize,
          onTap: () => _onSectionTap(i, tableState, playbackState, uiSelection),
        ),
      );
    }

    elements.add(
      _buildGap(
        sectionsCount - 1,
        gapWidth,
        sectionHeight,
        tableState,
        uiSelection,
        playbackState,
      ),
    );

    return elements;
  }

  Widget _buildSectionCard({
    required int sectionIndex,
    required bool isPlaying,
    required bool isSelected,
    required bool isUiSelected,
    required double width,
    required double height,
    required double fontSize,
    required VoidCallback onTap,
  }) {
    final apertureColor = isUiSelected
        ? AppColors.sequencerLightText.withOpacity(0.92)
        : _filmFrameAperture;
    final numberColor = isPlaying
        ? AppColors.sequencerAccent
        : (isUiSelected ? AppColors.sequencerText : AppColors.sequencerLightText);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: _filmBase,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: AppColors.sequencerBorder.withOpacity(0.55),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            color: apertureColor,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: isSelected
                  ? AppColors.sequencerSelectionBorder
                  : AppColors.sequencerBorder.withOpacity(0.7),
              width: isSelected ? 2.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 0,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${sectionIndex + 1}',
                style: TextStyle(
                  color: numberColor,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGap(
    int gapIndex,
    double width,
    double height,
    TableState tableState,
    UiSelectionState uiSelection,
    PlaybackState playbackState,
  ) {
    return GestureDetector(
      onTap: () => _onGapTap(gapIndex, tableState, uiSelection, playbackState),
      child: Container(
        width: width,
        height: height,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: _filmBase,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: AppColors.sequencerBorder.withOpacity(0.45),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Icon(
              Icons.add_rounded,
              color: AppColors.sequencerLightText.withOpacity(0.72),
              size: (height * 0.34).clamp(14.0, 24.0),
            ),
          ),
        ),
      ),
    );
  }

  void _onSectionTap(
    int index,
    TableState tableState,
    PlaybackState playbackState,
    UiSelectionState uiSelection,
  ) {
    uiSelection.selectSection(index);
    tableState.setUiSelectedSection(index);
    playbackState.switchToSection(index);
  }

  void _onGapTap(
    int gapIndex,
    TableState tableState,
    UiSelectionState uiSelection,
    PlaybackState playbackState,
  ) {
    tableState.addSectionAfter(gapIndex);
    final newIndex = gapIndex + 1;
    uiSelection.selectSection(newIndex);
    playbackState.switchToSection(newIndex);
  }
}
