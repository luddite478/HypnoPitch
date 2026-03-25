import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import 'package:google_fonts/google_fonts.dart';

class SectionsChainSquares extends StatelessWidget {
  final List<int> loopsPerSection;
  final List<int> layersPerSection;
  final List<int>? stepsPerSection;
  final double? squareSize;
  final double? connectorWidth;
  
  // Percent-based sizing controls (relative to parent height or square size)
  // Increase square size vs message bar while keeping look consistent
  static const double squareSizePercentOfHeight = 0.75; // ~75% of container height
  static const double squareBorderRadiusPx = 2; // match message_bar look
  static const double squareBorderWidthPx = 1; // match message_bar look
  static const double squareHorizontalMarginPercent = 0.08; // 8% of square side on each side
  
  static const double connectorWidthPercentOfSquare = 0.35; // 35% of square side (shorter dash)
  static const double connectorHeightPercentOfSquare = 0.16; // 16% of square side
  static const double connectorHorizontalMarginPercent = 0.06; // 6% of square side on each side
  
  // Layer stack visuals (per-square section representation)
  static const int maxVisualLayers = 8; // hard cap to keep UI readable
  static const double stackShadeDelta = 0.08; // opacity change per depth
  static const double stackHorizontalOffsetPercentOfSquare = 0.07; // horizontal offset per layer (as % of square side)
  static const double stackVerticalOffsetPercentOfSquare = 0.04; // vertical rise per layer (as % of square side)

  const SectionsChainSquares({
    super.key,
    required this.loopsPerSection,
    required this.layersPerSection,
    this.stepsPerSection,
    this.squareSize,
    this.connectorWidth,
  });

  @override
  Widget build(BuildContext context) {
    final count = loopsPerSection.length;
    if (count == 0) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight <= 0 ? 24.0 : constraints.maxHeight;
        // final w = constraints.maxWidth;
        // Normalize percent: if >1, treat as 0-100%
        final rawPercent = squareSizePercentOfHeight;
        final normalizedPercent = rawPercent > 1.0
            ? (rawPercent > 100.0 ? 1.0 : rawPercent / 100.0)
            : rawPercent;
        double s = squareSize ?? (h * normalizedPercent).clamp(12.0, h);
        final connPercent = connectorWidthPercentOfSquare > 1.0
            ? (connectorWidthPercentOfSquare > 100.0 ? 1.0 : connectorWidthPercentOfSquare / 100.0)
            : connectorWidthPercentOfSquare;
        
        // Do not auto-fit to width; rely on horizontal scrolling

        final c = connectorWidth ?? (s * connPercent);

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(count * 2 - 1, (i) {
              if (i.isEven) {
                final idx = i ~/ 2;
                final loops = loopsPerSection[idx];
                final layers = idx < layersPerSection.length ? layersPerSection[idx] : 0;
                final steps = stepsPerSection != null && idx < (stepsPerSection!.length)
                    ? stepsPerSection![idx]
                    : null;
                return _buildSquare(context, loops, layers, s, steps: steps);
              } else {
                return _buildConnector(c, s);
              }
            }),
          ),
        );
      },
    );
  }

  Widget _buildSquare(BuildContext context, int loops, int layers, double s, {int? steps}) {
    final int layerCount = (layers <= 0 ? 1 : layers).clamp(1, maxVisualLayers);
    final double stepX = (s * stackHorizontalOffsetPercentOfSquare).clamp(1.0, s * 0.25);
    final double stepY = (s * stackVerticalOffsetPercentOfSquare).clamp(1.0, s * 0.25);

    final double containerWidth = s + (layerCount - 1) * stepX;
    return Container(
      width: containerWidth,
      height: s,
      margin: EdgeInsets.symmetric(horizontal: (s + (layerCount - 1) * stepX) * squareHorizontalMarginPercent),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Draw back-to-front so the front card is on top
          for (int i = layerCount - 1; i >= 0; i--)
            Positioned(
              left: i * stepX,
              top: (layerCount - 1 - i) * stepY,
              child: Container(
                width: s,
                height: s,
                decoration: BoxDecoration(
                  color: const Color(0xFF7A8288).withOpacity((1.0 - i * stackShadeDelta).clamp(0.5, 1.0)),
                  borderRadius: BorderRadius.circular(squareBorderRadiusPx),
                  border: Border.all(
                    color: AppColors.sequencerBorder,
                    width: squareBorderWidthPx,
                  ),
                ),
              ),
            ),
          // Text (steps above loops) centered on the front (first) card
          Positioned(
            left: 0,
            top: (layerCount - 1) * stepY,
            child: SizedBox(
              width: s,
              height: s,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (steps != null) Text(
                      'steps: $steps',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: (s * 0.22).clamp(6, 10),
                        fontWeight: FontWeight.w600,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      'loops: $loops',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: (s * 0.22).clamp(6, 10),
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildConnector(double c, double s) {
    return Container(
      width: c,
      height: (s * connectorHeightPercentOfSquare).clamp(2.0, 6.0),
      margin: EdgeInsets.symmetric(horizontal: s * connectorHorizontalMarginPercent),
      decoration: BoxDecoration(
        color: AppColors.sequencerLightText,
        borderRadius: BorderRadius.circular((s * 0.08).clamp(1.0, 3.0)),
      ),
    );
  }
}


