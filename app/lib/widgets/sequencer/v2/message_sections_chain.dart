import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../utils/app_colors.dart';

/// Custom sections chain widget for message tiles
/// Shows sections as rectangles with layer divisions in the header
/// and steps/loops counters in the bottom
/// Horizontally scrollable like the old chain
class MessageSectionsChain extends StatelessWidget {
  final int sectionsCount;
  final List<int> stepsPerSection;
  final List<int> loopsPerSection;
  final List<int> layersPerSection;
  final double? verticalPadding; // Optional vertical padding to control space inside container
  final Color? dividerColor; // Optional divider color
  final double? dividerWidth; // Optional divider width
  final bool showDividers; // Whether to show dividers
  final int? dividerSpacingLayers; // Number of layers to use for calculating divider spacing
  
  // Sizing constants similar to old widget
  static const double rectangleSizePercentOfHeight = 0.75; // ~75% of container height (reduced for smaller rectangles)
  static const double rectangleHorizontalMarginPercent = 0.0; // No margin - tape effect (was 0.06)
  static const double rectangleMinWidth = 40.0; // Minimum width for rectangle (increased)
  static const double layerColumnMinWidth = 14.0; // Minimum width per layer column (increased)
  static const int defaultLayersForSpacing = 4; // Default number of layers to use for divider spacing

  const MessageSectionsChain({
    super.key,
    required this.sectionsCount,
    required this.stepsPerSection,
    required this.loopsPerSection,
    required this.layersPerSection,
    this.verticalPadding,
    this.dividerColor,
    this.dividerWidth,
    this.showDividers = false,
    this.dividerSpacingLayers,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight <= 0 ? 24.0 : constraints.maxHeight;
        
        // Calculate available height after accounting for vertical padding
        final double availableHeight = verticalPadding != null
            ? (h - (verticalPadding! * 2)).clamp(0.0, h)
            : h;
        
        // Use full available height if padding is specified, otherwise use percentage
        final double baseHeight = verticalPadding != null
            ? availableHeight.clamp(12.0, h)
            : (h * rectangleSizePercentOfHeight).clamp(12.0, h);

        // Calculate width of a section with specified layers (for divider spacing)
        final int spacingLayers = (dividerSpacingLayers ?? defaultLayersForSpacing).clamp(1, 12);
        final double defaultMinLayerWidth = layerColumnMinWidth;
        final double defaultBaseWidth = (spacingLayers * defaultMinLayerWidth).clamp(rectangleMinWidth, double.infinity);
        final double defaultHorizontalMargin = defaultBaseWidth * rectangleHorizontalMarginPercent;
        final double defaultSectionWidth = defaultBaseWidth + (defaultHorizontalMargin * 2);
        final double dividerW = dividerWidth ?? 1.0;
        
        // Calculate how many dividers to show to fill the visible area + one additional divider
        // Each divider unit (divider + spacing) = defaultSectionWidth
        final double containerWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : 400.0; // Fallback if infinite
        // Number of dividers that fit in visible width
        final int dividersForWidth = (containerWidth / defaultSectionWidth).ceil();
        // Show dividers that fill visible area + exactly 1 additional divider beyond
        final int dividerCount = dividersForWidth + 1;
        
        return Padding(
          padding: EdgeInsets.symmetric(
            vertical: verticalPadding ?? 0.0,
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Stack(
              children: [
                // Background: Full-height dividers spanning entire container height
                if (showDividers)
                  SizedBox(
                    height: h, // Full container height
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Divider at the start
                        Container(
                          width: dividerW,
                          color: dividerColor ?? const Color.fromARGB(255, 180, 180, 180),
                        ),
                        // Dividers evenly spaced - fill the entire line
                        ...List.generate(dividerCount, (dividerIndex) {
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(width: defaultSectionWidth - dividerW),
                              // Divider after each spacing
                              Container(
                                width: dividerW,
                                color: dividerColor ?? const Color.fromARGB(255, 180, 180, 180),
                              ),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                // Foreground: Sections (only if sections exist)
                if (sectionsCount > 0)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(sectionsCount, (sectionIndex) {
                      final layers = layersPerSection[sectionIndex];
                      final steps = stepsPerSection[sectionIndex];
                      final loops = loopsPerSection[sectionIndex];

                      return _buildSectionRectangle(
                        context,
                        layersCount: layers,
                        stepsCount: steps,
                        loopsCount: loops,
                        baseHeight: baseHeight,
                      );
                    }),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionRectangle(
    BuildContext context, {
    required int layersCount,
    required int stepsCount,
    required int loopsCount,
    required double baseHeight,
  }) {
    final int clampedLayers = layersCount.clamp(1, 12);
    
    // Width grows with number of layers
    final double minLayerWidth = layerColumnMinWidth;
    final double baseWidth = (clampedLayers * minLayerWidth).clamp(rectangleMinWidth, double.infinity);
    final double horizontalMargin = baseWidth * rectangleHorizontalMarginPercent;

    return Container(
      width: baseWidth,
      height: baseHeight,
      margin: EdgeInsets.symmetric(horizontal: horizontalMargin),
      child: _SectionRectangle(
        height: baseHeight,
        layersCount: clampedLayers,
        stepsCount: stepsCount,
        loopsCount: loopsCount,
      ),
    );
  }
}

class _SectionRectangle extends StatelessWidget {
  final double height;
  final int layersCount;
  final int stepsCount;
  final int loopsCount;

  const _SectionRectangle({
    required this.height,
    required this.layersCount,
    required this.stepsCount,
    required this.loopsCount,
  });

  @override
  Widget build(BuildContext context) {
    // Split height: 50% for layers header, 50% for counters (via Expanded)
    final double headerHeight = height * 0.50;

    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: const Color.fromARGB(255, 102, 102, 102),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: AppColors.sequencerBorder,
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            // Top part: Layers header with indices (1, 2, 3, 4...)
            Container(
              height: headerHeight,
              clipBehavior: Clip.hardEdge,
              decoration: const BoxDecoration(),
              child: Row(
                mainAxisSize: MainAxisSize.max,
                children: List.generate(layersCount, (layerIndex) {
                  return Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          right: layerIndex < layersCount - 1
                              ? BorderSide(
                                  color: AppColors.sequencerBorder,
                                  width: 0.5,
                                )
                              : BorderSide.none,
                        ),
                      ),
                      clipBehavior: Clip.hardEdge,
                      alignment: Alignment.center,
                      padding: EdgeInsets.zero,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${layerIndex + 1}',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            height: 1.0,
                            letterSpacing: 0,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          softWrap: false,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
            // Bottom part: Loops and steps aligned left and right
            Expanded(
              child: Container(
                clipBehavior: Clip.hardEdge,
                decoration: const BoxDecoration(),
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Loops on the left
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '$loopsCount',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          height: 1.0,
                          letterSpacing: 0,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        softWrap: false,
                      ),
                    ),
                    // Steps on the right
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '$stepsCount',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          height: 1.0,
                          letterSpacing: 0,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        softWrap: false,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

