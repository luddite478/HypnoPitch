import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../../utils/log.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:math' as math;
import '../../../state/sequencer/table.dart';
import '../../../state/sequencer/sample_bank.dart';
import '../../../state/sequencer/playback.dart';
import '../../../state/sequencer/recording.dart';
import '../../../state/sequencer/recording_waveform.dart';
import '../../../state/sequencer/microphone.dart';
import '../../../state/sequencer/edit.dart';
import '../../../state/sequencer/multitask_panel.dart';
import '../../../ffi/table_bindings.dart';
import '../../../utils/app_colors.dart';
import '../../stacked_cards_widget.dart';
import '../../../state/sequencer/ui_selection.dart';
import '../../../state/app_state.dart';
import '../../../config/debug_flags.dart';
import 'line_mic_waveform_widget.dart';
import '../../tutorial_pulse_widget.dart';
import 'sequencer_layer_label.dart';

// Custom ScrollPhysics to retain position when content changes
class PositionRetainedScrollPhysics extends ScrollPhysics {
  final bool shouldRetain;
  const PositionRetainedScrollPhysics({super.parent, this.shouldRetain = true});

  @override
  PositionRetainedScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return PositionRetainedScrollPhysics(
      parent: buildParent(ancestor),
      shouldRetain: shouldRetain,
    );
  }

  @override
  double adjustPositionForNewDimensions({
    required ScrollMetrics oldPosition,
    required ScrollMetrics newPosition,
    required bool isScrolling,
    required double velocity,
  }) {
    final position = super.adjustPositionForNewDimensions(
      oldPosition: oldPosition,
      newPosition: newPosition,
      isScrolling: isScrolling,
      velocity: velocity,
    );

    final diff = newPosition.maxScrollExtent - oldPosition.maxScrollExtent;

    // Always retain position when content is added (diff > 0), regardless of scroll position
    if (diff > 0 && shouldRetain) {
      return position + diff;
    } else {
      return position;
    }
  }
}

class SampleGridWidget extends StatefulWidget {
  final int? sectionIndexOverride;
  const SampleGridWidget({super.key, this.sectionIndexOverride});

  @override
  State<SampleGridWidget> createState() => _SampleGridWidgetState();
}

/// Payload for moving a placed sample from one grid cell to another (long-press drag).
class GridCellDragData {
  final int sourceAbsoluteStep;
  final int sourceAbsoluteCol;
  final int sampleSlot;
  final double volume;
  final double pitch;

  const GridCellDragData({
    required this.sourceAbsoluteStep,
    required this.sourceAbsoluteCol,
    required this.sampleSlot,
    required this.volume,
    required this.pitch,
  });
}

enum GestureMode { undetermined, scrolling, selecting }

/// Row/cell geometry shared by [_SampleGridWidgetState._buildGridRow] and
/// [_SampleGridWidgetState._positionToCellIndex]. Uses the grid viewport width
/// from [LayoutBuilder] constraints only — not screen [MediaQuery] — and rounds
/// down per `docs/dart_ui_guide/flutter_overflow_prevention_guide.md`.
class _SoundGridRowLayoutMetrics {
  const _SoundGridRowLayoutMetrics({
    required this.actualRowHeight,
    required this.actualRowSpacing,
    required this.rowBlock,
    required this.actualRowNumberColumnWidth,
    required this.actualCellSpacing,
    required this.actualCellWidth,
    required this.cellBlock,
  });

  final double actualRowHeight;
  final double actualRowSpacing;
  final double rowBlock;
  final double actualRowNumberColumnWidth;
  final double actualCellSpacing;
  final double actualCellWidth;
  final double cellBlock;

  /// [viewportWidth] must be [LayoutBuilder.constraints.maxWidth] for this grid.
  static _SoundGridRowLayoutMetrics fromViewportWidth(
    double viewportWidth,
    int gridCols, {
    required double cellWidthPercent,
    required double cellHeightPercent,
    required double cellSpacingPercent,
    required double rowSpacingPercent,
    required double rowNumberColumnWidthPercent,
  }) {
    const baseRowHeight = 50.0;
    final actualRowHeight = baseRowHeight * (cellHeightPercent / 100.0);
    final actualRowSpacing = baseRowHeight * (rowSpacingPercent / 100.0);
    final rowBlock = actualRowHeight + actualRowSpacing;
    if (rowBlock <= 0 || viewportWidth <= 0) {
      return _SoundGridRowLayoutMetrics(
        actualRowHeight: actualRowHeight,
        actualRowSpacing: actualRowSpacing,
        rowBlock: rowBlock,
        actualRowNumberColumnWidth: 0,
        actualCellSpacing: 0,
        actualCellWidth: 0,
        cellBlock: 0,
      );
    }

    final w = viewportWidth;
    // Round down (guide: avoid float overflow in Rows).
    final actualRowNumberColumnWidth =
        (w * (rowNumberColumnWidthPercent / 100.0)).floorToDouble();
    final actualCellSpacing =
        (w * (cellSpacingPercent / 100.0)).floorToDouble();
    final availableWidthForGrid =
        (w - actualRowNumberColumnWidth).clamp(0.0, w).floorToDouble();
    final totalHorizontalSpacing = actualCellSpacing * (gridCols - 1);
    var availableWidthForCells = availableWidthForGrid - totalHorizontalSpacing;
    if (availableWidthForCells < 0) availableWidthForCells = 0;
    final fullCellWidth = gridCols > 0
        ? (availableWidthForCells / gridCols).floorToDouble()
        : 0.0;
    var actualCellWidth =
        (fullCellWidth * (cellWidthPercent / 100.0)).floorToDouble();
    if (gridCols > 0) {
      var rowSum = gridCols * actualCellWidth + totalHorizontalSpacing;
      if (rowSum > availableWidthForGrid) {
        final over = rowSum - availableWidthForGrid;
        actualCellWidth = ((gridCols * actualCellWidth - over) / gridCols)
            .floorToDouble()
            .clamp(0.0, double.infinity);
      }
    }
    final cellBlock = actualCellWidth + actualCellSpacing;

    assert(() {
      if (gridCols <= 0) return true;
      final rowSum = gridCols * actualCellWidth + totalHorizontalSpacing;
      return rowSum <= availableWidthForGrid + 1.0;
    }());

    return _SoundGridRowLayoutMetrics(
      actualRowHeight: actualRowHeight,
      actualRowSpacing: actualRowSpacing,
      rowBlock: rowBlock,
      actualRowNumberColumnWidth: actualRowNumberColumnWidth,
      actualCellSpacing: actualCellSpacing,
      actualCellWidth: actualCellWidth,
      cellBlock: cellBlock,
    );
  }
}

class _SampleGridWidgetState extends State<SampleGridWidget> {
  final ScrollController _scrollController = ScrollController();
  Timer? _autoScrollTimer;
  final Set<String> _pendingMovedSourceCells = <String>{};
  final Map<String, Timer> _pendingMovedSourceTimers = <String, Timer>{};
  static const double _autoScrollSpeed = 8.0;
  static const Duration _autoScrollInterval = Duration(milliseconds: 12);
  static const double _edgeThreshold = 50.0;

  Offset? _gestureStartPosition;
  Offset? _currentPanPosition;
  GestureMode _gestureMode = GestureMode.undetermined;
  static const double _gestureThreshold = 15.0;
  int _gridBuildCount = 0;

  /// Last laid-out grid viewport from [LayoutBuilder.constraints] (same coordinate space as pan
  /// [localPosition]). Cached for timers/updates between builds; do not use [MediaQuery] size
  /// for grid math — see `docs/dart_ui_guide/flutter_overflow_prevention_guide.md`.
  double? _gridViewportWidth;
  double? _gridViewportHeight;

  // CONFIGURABLE GRID DIMENSIONS - Easy to control cell sizing
  static const double cellWidthPercent =
      98.0; // Cell width as % of available column space (reduced to make room for row numbers)
  static const double cellHeightPercent =
      60.0; // Cell height as % of available row space
  static const double cellSpacingPercent =
      0.0; // Spacing between cells as % of available space
  static const double rowSpacingPercent =
      0.0; // Spacing between rows as % of available space
  static const double rowNumberColumnWidthPercent =
      6.0; // Row number column width as % of total width
  static const Color rowNumberColumnColor =
      Color.fromARGB(121, 40, 46, 39); // Color for row number column
  static const Color gridBackgroundColor = AppColors
      .sequencerCellEmptyAlternate; // Gray background behind grid and buttons
  static const Color cellBorderColor =
      Color.fromARGB(255, 77, 77, 77); // Border color for cells
  static const double cellBorderWidth = 1.0; // Border width for cells

  // CONFIGURABLE CONTENT SIZING - Control text and element sizes
  static const double effectsFontSize =
      12.0; // Font size for effects text (V45, K-4, etc.) — single-row layout
  static const double cellPaddingPercent =
      0.0; // Internal padding as % of cell size

  // CONFIGURATION EXAMPLES - Uncomment and modify as needed:
  //
  // COMPACT GRID (smaller cells, more spacing):
  // static const double cellWidthPercent = 85.0;
  // static const double cellHeightPercent = 30.0;
  // static const double cellSpacingPercent = 15.0;
  // static const double rowSpacingPercent = 10.0;
  // static const double effectsFontSize = 7.0;
  //
  // LARGE GRID (bigger cells, less spacing):
  // static const double cellWidthPercent = 98.0;
  // static const double cellHeightPercent = 60.0;
  // static const double cellSpacingPercent = 2.0;
  // static const double rowSpacingPercent = 2.0;
  // static const double effectsFontSize = 9.0;
  //
  // RECTANGULAR CELLS (wider than tall):
  // static const double cellAspectRatio = 1.5; // 1.5:1 ratio (wider cells)
  // static const double cellAspectRatio = 0.75; // 3:4 ratio (taller cells)

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    for (final timer in _pendingMovedSourceTimers.values) {
      timer.cancel();
    }
    _pendingMovedSourceTimers.clear();
    _scrollController.dispose();
    _stopAllActions(); // Clean up button press timer
    super.dispose();
  }

  String _cellKey(int absoluteStep, int absoluteCol) {
    return '$absoluteStep:$absoluteCol';
  }

  void _hideMovedSourceCellTemporarily(int absoluteStep, int absoluteCol) {
    final key = _cellKey(absoluteStep, absoluteCol);
    _pendingMovedSourceTimers.remove(key)?.cancel();
    if (!_pendingMovedSourceCells.contains(key) && mounted) {
      setState(() => _pendingMovedSourceCells.add(key));
    } else {
      _pendingMovedSourceCells.add(key);
    }

    _pendingMovedSourceTimers[key] = Timer(
      const Duration(milliseconds: 180),
      () {
        if (!mounted) return;
        if (_pendingMovedSourceCells.remove(key)) {
          setState(() {});
        }
        _pendingMovedSourceTimers.remove(key);
      },
    );
  }

  void _resolvePendingSourceCellIfCleared(
      int absoluteStep, int absoluteCol, bool hasPlacedSample) {
    if (hasPlacedSample) return;
    final key = _cellKey(absoluteStep, absoluteCol);
    if (!_pendingMovedSourceCells.contains(key)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final removed = _pendingMovedSourceCells.remove(key);
      _pendingMovedSourceTimers.remove(key)?.cancel();
      if (removed) {
        setState(() {});
      }
    });
  }

  void _startAutoScroll(double direction, Offset initialPosition) {
    if (_autoScrollTimer != null) {
      return;
    }

    _autoScrollTimer = Timer.periodic(_autoScrollInterval, (timer) {
      if (!mounted) {
        timer.cancel();
        _autoScrollTimer = null;
        return;
      }

      final currentOffset = _scrollController.offset;
      final maxOffset = _scrollController.position.maxScrollExtent;
      final newOffset = currentOffset + (direction * _autoScrollSpeed);
      final clampedOffset = newOffset.clamp(0.0, maxOffset);

      if (clampedOffset != currentOffset) {
        _scrollController.jumpTo(clampedOffset);

        final positionToUse = _currentPanPosition ?? initialPosition;
        final cellIndex = _positionToCellIndex(positionToUse, _gridViewportWidth);
        if (cellIndex != null) {
          context.read<EditState>().selectCell(cellIndex, extend: true);
        }
      } else {
        timer.cancel();
        _autoScrollTimer = null;
      }
    });
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    final localPosition = details.localPosition;
    _currentPanPosition = localPosition;

    if (_gestureMode == GestureMode.undetermined &&
        _gestureStartPosition != null) {
      final delta = localPosition - _gestureStartPosition!;

      if (delta.distance > _gestureThreshold) {
        final isVertical = delta.dy.abs() > delta.dx.abs();

        if (context.read<EditState>().isInSelectionMode) {
          _gestureMode = GestureMode.selecting;
        } else if (isVertical) {
          _gestureMode = GestureMode.scrolling;
        } else {
          _gestureMode = GestureMode.selecting;
        }
      }
    }

    if (_gestureMode == GestureMode.selecting) {
      _handleSelectionGesture(localPosition);
    }
  }

  void _handleSelectionGesture(Offset localPosition) {
    final cellIndex = _positionToCellIndex(localPosition, _gridViewportWidth);

    final viewportH = _gridViewportHeight;
    final yPosition = localPosition.dy;

    if (viewportH != null &&
        viewportH > 0 &&
        yPosition < _edgeThreshold &&
        _scrollController.hasClients &&
        _scrollController.offset > 0) {
      _startAutoScroll(-1.0, localPosition);
      if (cellIndex != null) {
        context.read<UiSelectionState>().selectCells();
        context.read<EditState>().selectCell(cellIndex, extend: true);
        context.read<MultitaskPanelState>().showCellSettings();
      }
      return;
    }
    if (viewportH != null &&
        viewportH > 0 &&
        yPosition > viewportH - _edgeThreshold &&
        _scrollController.hasClients &&
        _scrollController.offset < _scrollController.position.maxScrollExtent) {
      _startAutoScroll(1.0, localPosition);
      if (cellIndex != null) {
        context.read<UiSelectionState>().selectCells();
        context.read<EditState>().selectCell(cellIndex, extend: true);
        context.read<MultitaskPanelState>().showCellSettings();
      }
      return;
    }
    _stopAutoScroll();

    if (cellIndex != null) {
      context.read<UiSelectionState>().selectCells();
      context.read<EditState>().selectCell(cellIndex, extend: true);
      context.read<MultitaskPanelState>().showCellSettings();
    }
  }

  /// [viewportWidth] must be the grid [LayoutBuilder] width (see [_gridViewportWidth]).
  int? _positionToCellIndex(Offset localPosition, double? viewportWidth) {
    if (viewportWidth == null || viewportWidth <= 0) return null;

    final gridCols = context.read<TableState>().getVisibleCols().length;
    final m = _SoundGridRowLayoutMetrics.fromViewportWidth(
      viewportWidth,
      gridCols,
      cellWidthPercent: cellWidthPercent,
      cellHeightPercent: cellHeightPercent,
      cellSpacingPercent: cellSpacingPercent,
      rowSpacingPercent: rowSpacingPercent,
      rowNumberColumnWidthPercent: rowNumberColumnWidthPercent,
    );
    if (m.rowBlock <= 0 || m.cellBlock <= 0) return null;

    final scrollOffset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;
    final rowIndex = ((scrollOffset + localPosition.dy) / m.rowBlock).floor();
    if (rowIndex < 0) return null;

    final xInGrid = localPosition.dx - m.actualRowNumberColumnWidth;
    if (xInGrid < 0) return null;
    // Align hit testing with symmetric margins used in layout (s/2 on both sides)
    final xAdjusted = xInGrid - (m.actualCellSpacing / 2);
    int colIndex = (xAdjusted / m.cellBlock).floor();
    if (colIndex < 0) return null;
    if (colIndex >= gridCols) colIndex = gridCols - 1;
    return rowIndex * gridCols + colIndex;
  }

  Color _getSampleColorForGrid(int sampleSlot, BuildContext context) {
    // Get sample bank colors - these are the authoritative colors for samples
    final sampleBankState =
        Provider.of<SampleBankState>(context, listen: false);

    // Use sample bank colors directly, with slight darkening for grid cells
    if (sampleSlot >= 0 && sampleSlot < sampleBankState.uiBankColors.length) {
      final originalColor = sampleBankState.uiBankColors[sampleSlot];
      return Color.lerp(originalColor, AppColors.sequencerCellFilled, 0.3) ??
          AppColors.sequencerCellFilled;
    }

    // Fallback color for invalid sample slots
    return AppColors.sequencerCellFilled;
  }

  /// Flat index of the cell to highlight for Jump paste "copy" step: 0:0 if it has
  /// a sample, else first row-major cell with a sample, else 0.
  int? _jumpPasteSourceFlatIndex(
    TableState tableState,
    AppState appState,
    TutorialStep tutorialStep,
  ) {
    if (tutorialStep != TutorialStep.sequencerJumpPasteHint ||
        !appState.showJumpCopyPointer) {
      return null;
    }
    final sectionIndex =
        widget.sectionIndexOverride ?? tableState.uiSelectedSection;
    final gridCols = tableState.getVisibleCols().length;
    final sectionStart = tableState.getSectionStartStep(sectionIndex);
    final layerStart = tableState.getLayerStartCol();
    final sectionStepCount = tableState.getSectionStepCount(sectionIndex);

    bool hasSampleAt(int r, int c) {
      final step = sectionStart + r;
      final colAbs = layerStart + c;
      return tableState.getCellNotifier(step, colAbs).value.sampleSlot >= 0;
    }

    if (hasSampleAt(0, 0)) return 0;
    for (int r = 0; r < sectionStepCount; r++) {
      for (int c = 0; c < gridCols; c++) {
        if (r == 0 && c == 0) continue;
        if (hasSampleAt(r, c)) return r * gridCols + c;
      }
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    _gridBuildCount++;
    if (kShouldLogSequencerProfiling && (_gridBuildCount % 240 == 0)) {
      Log.d('[SAMPLE_GRID_PROFILE] build_count=$_gridBuildCount', 'SOUND_GRID');
    }
    // Include layer sub-step flags: they change without activeTutorialStep changing.
    final tutorialDeps = context.select((AppState s) => (
          s.activeTutorialStep,
          s.isLayersTabDone,
          s.isLayersMuteDone,
          s.isLayersUnmuteDone,
          s.showJumpValueTwoPointer,
          s.showJumpCopyPointer,
          s.showJumpPasteTargetCellPointer,
          s.showJumpPasteButtonOnlyPointer,
        ));
    final tutorialStep = tutorialDeps.$1;
    final appState = context.read<AppState>();
    return Consumer<TableState>(
      builder: (context, tableState, child) {
        final int numSoundGrids =
            tableState.totalLayers; // Derive from table state

        // Initialize sound grids if not already done or if number changed
        if (tableState.uiSoundGridOrder.length != numSoundGrids) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            tableState.uiInitializeSoundGrids(numSoundGrids);
          });
          return const Center(child: CircularProgressIndicator());
        }

        // Get TableState for reading cell data from the new table system (already provided)

        final bool isFlat =
            tableState.uiSoundGridViewMode == SoundGridViewMode.flat;
        return Container(
          margin: const EdgeInsets.only(
              top: 0, bottom: 0), // Move entire sound grid structure
          decoration: BoxDecoration(
            border: Border.all(
              color: AppColors.sequencerBorder,
              width: 0,
            ),
            borderRadius: BorderRadius.circular(2), // Sharp corners
            boxShadow: [
              // Protruding effect
              BoxShadow(
                color: AppColors.sequencerShadow,
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: isFlat
              ? _buildFlatTabs(
                  tableState,
                  tutorialStep: tutorialStep,
                  appState: appState,
                )
              : StackedCardsWidget(
                  numCards: numSoundGrids,
                  cardWidthFactor: 0.98,
                  cardHeightFactor: 0.98,
                  offsetPerDepth: const Offset(0, -8),
                  scaleFactorPerDepth: 0.02,
                  borderRadius: 2.0, // Sharp corners
                  cardColors: [
                    AppColors.sequencerSurfaceBase,
                    AppColors.sequencerSurfaceRaised,
                  ],
                  activeCardIndex: tableState.uiCurrentSoundGridIndex,
                  cardBuilder: (index, width, height, depth) {
                    // INVERSION LOGIC: Stack index 0 = back card, but we want L1 to be front
                    // So we need to invert: front card (highest stack index) = L1 (first grid)
                    final invertedIndex = numSoundGrids - 1 - index;
                    final actualSoundGridId =
                        tableState.uiSoundGridOrder[invertedIndex];

                    // Define subtle colors for each card ID (non-vibrant, more professional)
                    final availableColors = [
                      const Color(0xFF4B5563), // Gray-600
                      const Color(0xFF6B7280), // Gray-500
                      const Color(0xFF374151), // Gray-700
                      const Color(0xFF9CA3AF), // Gray-400
                      const Color(0xFF1F2937), // Gray-800
                      const Color(0xFF111827), // Gray-900
                      const Color(0xFFD1D5DB), // Gray-300
                      const Color(0xFFF3F4F6), // Gray-100
                      const Color(
                          0xFF6B7280), // Gray-500 (repeat for more grids)
                      const Color(
                          0xFF374151), // Gray-700 (repeat for more grids)
                    ];
                    final cardColor = availableColors[
                        actualSoundGridId % availableColors.length];

                    // The front card is the one that matches the current sound grid index
                    final isFrontCard =
                        actualSoundGridId == tableState.uiCurrentSoundGridIndex;

                    // Wrap everything in a container with minimal extra space for the label tab
                    return SizedBox(
                      width: width,
                      height:
                          height + 100, // More space for tabs positioned lower
                      child: Stack(
                        clipBehavior: Clip
                            .none, // Allow tabs to be positioned outside bounds if needed
                        children: [
                          // Main card positioned to leave space for tab at top
                          Positioned(
                            top: 37, // More space for tab positioned lower
                            left: 0,
                            child: _buildMainCard(
                              width: width,
                              height: height,
                              cardColor: cardColor,
                              isFrontCard: isFrontCard,
                              depth: depth,
                              actualSoundGridId: actualSoundGridId,
                              index: index,
                              tableState: tableState,
                              tutorialStep: tutorialStep,
                              appState: appState,
                            ),
                          ),
                          // Clickable tab label positioned above the card
                          // Use actualSoundGridId for positioning to maintain fixed horizontal positions
                          Positioned(
                            top:
                                15, // Positioned lower to stay within container bounds
                            left: _calculateTabPosition(
                                actualSoundGridId, width, numSoundGrids),
                            child: _buildClickableTabLabel(
                              gridIndex: actualSoundGridId,
                              cardColor: cardColor,
                              isFrontCard: isFrontCard,
                              depth: depth,
                              tabWidth:
                                  _calculateTabWidth(width, numSoundGrids),
                              tableState: tableState,
                              tutorialStep: tutorialStep,
                              appState: appState,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  /// Multi-select outline: strong left & bottom edges, softer top & right (light from upper-right).
  /// When two selected cells touch, shared edges use a thin seam so the block does not look doubled.
  Border _selectionBorderForCell({
    required int index,
    required int gridCols,
    required int row,
    required int col,
    required Set<int> selectedSet,
  }) {
    final hasLeft = col > 0 && selectedSet.contains(index - 1);
    final hasRight = col < gridCols - 1 && selectedSet.contains(index + 1);
    final hasTop = row > 0 && selectedSet.contains(index - gridCols);
    final hasBottom = selectedSet.contains(index + gridCols);

    const double heavyW = 2.75;
    const double lightW = 1.15;
    const double seamW = 1.0;
    final Color strongEdgeC =
        AppColors.sequencerSelectionBorder.withValues(alpha: 0.72);
    final Color litC =
        AppColors.sequencerSelectionBorder.withValues(alpha: 0.52);
    final Color seamC =
        AppColors.sequencerSelectionBorder.withValues(alpha: 0.30);

    return Border(
      left: BorderSide(
        width: hasLeft ? seamW : heavyW,
        color: hasLeft ? seamC : strongEdgeC,
      ),
      right: BorderSide(
        width: hasRight ? seamW : lightW,
        color: hasRight ? seamC : litC,
      ),
      top: BorderSide(
        width: hasTop ? seamW : lightW,
        color: hasTop ? seamC : litC,
      ),
      bottom: BorderSide(
        width: hasBottom ? seamW : heavyW,
        color: hasBottom ? seamC : strongEdgeC,
      ),
    );
  }

  // 🎯 PERFORMANCE: Cell that only rebuilds when current step changes or cell data changes
  Widget _buildEnhancedGridCell(
    BuildContext context,
    TableState tableState,
    int index, {
    required int currentStep,
    required Set<int> selectedSet,
    required TutorialStep tutorialStep,
    required AppState appState,
  }) {
    final gridCols = tableState.getVisibleCols().length;
    final row = index ~/ gridCols;
    final col = index % gridCols;
    final currentLayer = tableState.uiSelectedLayer;
    final isLayerMuted = tableState.isLayerMuted(currentLayer);
    final isColumnMuted = tableState.isLayerColumnMuted(currentLayer, col);
    final isLayerSoloed = tableState.isLayerSoloed(currentLayer);
    final isColumnSoloed = tableState.isLayerColumnSoloed(currentLayer, col);
    final mutedVisual = isLayerMuted || isColumnMuted;
    // Layer mute suppresses solo highlight; no simultaneous mute + solo for the layer.
    final soloVisual = !isLayerMuted && (isLayerSoloed || isColumnSoloed);

    // Calculate absolute step and column for TableState (respect section override)
    final sectionIndex =
        widget.sectionIndexOverride ?? tableState.uiSelectedSection;
    final absoluteStep = tableState.getSectionStartStep(sectionIndex) + row;
    final layerStartCol = tableState.getLayerStartCol();
    final absoluteCol = layerStartCol + col;

    final bool isFirstTutorialCell = widget.sectionIndexOverride == null &&
        row == 0 &&
        col == 0;
    final bool isCopyPasteTutorialAnchorCell =
        widget.sectionIndexOverride == null &&
            tutorialStep == TutorialStep.sequencerCopyPasteHint &&
            ((row == 0 &&
                    col == 0 &&
                    appState.showCopyPasteSourceCellHighlight) ||
                (row == 2 && col == 2 && appState.showPastePointer));
    final int? jumpPasteSourceFlatIndex =
        _jumpPasteSourceFlatIndex(tableState, appState, tutorialStep);
    final bool isJumpPasteSourceCell = widget.sectionIndexOverride == null &&
        tutorialStep == TutorialStep.sequencerJumpPasteHint &&
        appState.showJumpCopyPointer &&
        jumpPasteSourceFlatIndex != null &&
        index == jumpPasteSourceFlatIndex;
    final bool isJumpPasteTargetCell = widget.sectionIndexOverride == null &&
        row == 2 &&
        col == 0 &&
        tutorialStep == TutorialStep.sequencerJumpPasteHint &&
        appState.showJumpPasteTargetCellPointer;
    final bool pulseCopyPasteTutorialCell = isCopyPasteTutorialAnchorCell;
    final bool pulseJumpPasteCell = isJumpPasteSourceCell ||
        isJumpPasteTargetCell ||
        pulseCopyPasteTutorialCell;
    final bool isTutorialCell = isFirstTutorialCell &&
        tutorialStep == TutorialStep.sequencerFirstCellHint;
    final Key? cellTutorialKey = isTutorialCell
        ? appState.firstCellTutorialKey
        : (isCopyPasteTutorialAnchorCell
            ? appState.copyPasteTargetCellTutorialKey
            : (isJumpPasteSourceCell
                ? appState.jumpPasteSourceCellTutorialKey
                : (isJumpPasteTargetCell
                    ? appState.jumpPasteTargetCellTutorialKey
                    : null)));
    final bool shouldBlinkTutorialCell = isFirstTutorialCell &&
        (tutorialStep == TutorialStep.sequencerFirstCellHint ||
            tutorialStep == TutorialStep.sequencerSelectSampleHint);

    return ValueListenableBuilder<CellData>(
      valueListenable: tableState.getCellNotifier(absoluteStep, absoluteCol),
      builder: (context, cellData, child) {
        final isInSelectionMode =
            context.select((EditState e) => e.isInSelectionMode);
        final isActivePad =
            false; // UI-only highlight not yet wired in TableState
        final isCurrentStep = widget.sectionIndexOverride == null &&
            currentStep >= 0 &&
            currentStep == absoluteStep;
        final placedSample =
            cellData.sampleSlot >= 0 ? cellData.sampleSlot : null;
        final hasPlacedSample = placedSample != null;
        final sourceCellKey = _cellKey(absoluteStep, absoluteCol);
        final isPendingMovedSource =
            _pendingMovedSourceCells.contains(sourceCellKey);
        final hasPlacedSampleForDisplay =
            hasPlacedSample && !isPendingMovedSource;
        _resolvePendingSourceCellIfCleared(
            absoluteStep, absoluteCol, hasPlacedSample);

        // 🎯 PERFORMANCE: Light bulb-bluish-white highlight for current step
        Color cellColor;
        // ignore: dead_code
        if (isActivePad) {
          cellColor = AppColors.sequencerAccent.withOpacity(0.6);
        } else if (isCurrentStep) {
          // Light bulb-bluish-white highlight for current step
          cellColor = hasPlacedSampleForDisplay
              ? _getSampleColorForGrid(placedSample, context).withOpacity(0.9)
              : const Color(0xFF87CEEB)
                  .withOpacity(0.4); // Light blue highlight
        } else if (hasPlacedSampleForDisplay) {
          cellColor = _getSampleColorForGrid(placedSample, context);
        } else {
          // Alternate cell color for every 4th row (1, 5, 9, etc. in 1-indexed terms)
          final isAlternateRow = row % 4 == 0;
          cellColor = isAlternateRow
              ? AppColors.sequencerCellEmptyAlternate
              : AppColors.sequencerCellEmpty;
        }

        return DragTarget<Object>(
          onWillAcceptWithDetails: (DragTargetDetails<Object?> details) {
            final data = details.data;
            return data is int || data is GridCellDragData;
          },
          onAcceptWithDetails: (DragTargetDetails<Object?> details) {
            final data = details.data;
            if (data == null) return;
            if (!appState.canInteractWithTutorialTarget(
                TutorialInteractionTarget.sampleGrid)) {
              return;
            }
            final ts = Provider.of<TableState>(context, listen: false);
            final gridCols = ts.getVisibleCols().length;
            final row = index ~/ gridCols;
            final col = index % gridCols;
            final sectionIndex =
                widget.sectionIndexOverride ?? ts.uiSelectedSection;
            final targetStep = ts.getSectionStartStep(sectionIndex) + row;
            final layerStartCol = ts.getLayerStartCol();
            final targetCol = layerStartCol + col;

            if (data is int) {
              ts.setCell(targetStep, targetCol, data, -1.0, -1.0);
              Log.d(
                  ' [DRAG] Set cell [$targetStep, $targetCol] = sample $data');
            } else if (data is GridCellDragData) {
              if (data.sourceAbsoluteStep == targetStep &&
                  data.sourceAbsoluteCol == targetCol) {
                return;
              }
              _hideMovedSourceCellTemporarily(
                  data.sourceAbsoluteStep, data.sourceAbsoluteCol);
              ts.setCell(targetStep, targetCol, data.sampleSlot, data.volume,
                  data.pitch);
              ts.clearCell(data.sourceAbsoluteStep, data.sourceAbsoluteCol);
              Log.d(
                  ' [DRAG] Move cell [${data.sourceAbsoluteStep},${data.sourceAbsoluteCol}] → [$targetStep,$targetCol]');
            }
          },
          builder: (context, candidateData, rejectedData) {
            final bool isDragHovering = candidateData.isNotEmpty;
            final bool isSelected = selectedSet.contains(index);

            final Widget surface = Container(
              key: cellTutorialKey,
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                color: isDragHovering
                    ? AppColors.sequencerAccent.withOpacity(0.8)
                    : cellColor,
                borderRadius: BorderRadius.zero,
                border: isSelected
                    ? _selectionBorderForCell(
                        index: index,
                        gridCols: gridCols,
                        row: row,
                        col: col,
                        selectedSet: selectedSet,
                      )
                    : isCurrentStep
                        ? Border.all(
                            color: const Color(0xFF87CEEB),
                            width: 1.5,
                          )
                        : isDragHovering
                            ? Border.all(
                                color: AppColors.sequencerAccent,
                                width: 0.75,
                              )
                            : Border.all(
                                color: cellBorderColor,
                                width: cellBorderWidth,
                              ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.24),
                          offset: const Offset(1.2, 2.0),
                          blurRadius: 3,
                        ),
                      ]
                    : isCurrentStep
                        ? [
                            BoxShadow(
                              color:
                                  const Color(0xFF87CEEB).withOpacity(0.3),
                              blurRadius: 4,
                              spreadRadius: 1,
                              offset: const Offset(0, 0),
                            ),
                            BoxShadow(
                              color: AppColors.sequencerShadow,
                              blurRadius: 1,
                              offset: const Offset(0, 0.5),
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final basePadding =
                      math.min(constraints.maxWidth, constraints.maxHeight) *
                          (cellPaddingPercent / 100.0);
                  final actualPadding = basePadding + 1.0;
                  return Stack(
                    children: [
                      Padding(
                        padding: EdgeInsets.all(actualPadding),
                        child: hasPlacedSampleForDisplay
                            ? _buildSampleCellContent(
                                context,
                                tableState,
                                index,
                                placedSample,
                                isActivePad,
                                isCurrentStep,
                                isDragHovering,
                              )
                            : _buildEmptyCellContent(),
                      ),
                      if (mutedVisual)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Container(
                              color: Colors.black.withOpacity(0.26),
                            ),
                          ),
                        ),
                      if (!mutedVisual && soloVisual)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Container(
                              color: const Color(0xFFF4D35E)
                                  .withOpacity(0.18),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            );

            final Widget tutorialWrapped = shouldBlinkTutorialCell
                ? _TutorialBlinkCell(child: surface)
                : surface;

            Widget gestureChild = GestureDetector(
              onTap: () {
                final canTapAnyGridCell =
                    appState.canInteractWithTutorialTarget(
                  TutorialInteractionTarget.sampleGrid,
                );
                final canTapFirstTutorialCell = isTutorialCell &&
                    appState.canInteractWithTutorialTarget(
                      TutorialInteractionTarget.firstGridCell,
                    );
                if (!canTapAnyGridCell && !canTapFirstTutorialCell) {
                  return;
                }
                context.read<UiSelectionState>().selectCells();
                final edit = Provider.of<EditState>(context, listen: false);
                if (edit.isInSelectionMode) {
                  edit.toggleCellInSelectionMode(index);
                } else {
                  edit.selectSingleCell(index);
                }
                tableState.uiHandlePadPress(index);

                Provider.of<MultitaskPanelState>(context, listen: false)
                    .showCellSettings();
                if (isTutorialCell) {
                  context.read<AppState>().advanceTutorialToSelectSample();
                }
              },
              child: TutorialPulseWidget(
                enabled: pulseJumpPasteCell,
                borderRadius: BorderRadius.zero,
                child: tutorialWrapped,
              ),
            );

            final bool canDrag = hasPlacedSample &&
                !isPendingMovedSource &&
                !cellData.isProcessing &&
                !isInSelectionMode &&
                appState.canInteractWithTutorialTarget(
                    TutorialInteractionTarget.sampleGrid);

            if (canDrag) {
              final slot = placedSample;
              final dragData = GridCellDragData(
                sourceAbsoluteStep: absoluteStep,
                sourceAbsoluteCol: absoluteCol,
                sampleSlot: slot,
                volume: cellData.volume,
                pitch: cellData.pitch,
              );
              final Color feedbackColor =
                  _getSampleColorForGrid(slot, context);
              gestureChild = LongPressDraggable<GridCellDragData>(
                data: dragData,
                feedback: _DragPulseShell(
                  child: Material(
                    color: feedbackColor,
                    elevation: 4,
                    shadowColor: Colors.black45,
                    borderRadius: BorderRadius.circular(2),
                    child: Container(
                      width: 76,
                      height: 42,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(
                          color: AppColors.sequencerBorder,
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: _buildCellDragFeedbackContent(
                            context,
                            slot,
                            cellData.volume,
                            cellData.pitch,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                childWhenDragging: Container(
                  width: double.infinity,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: row % 4 == 0
                        ? AppColors.sequencerCellEmptyAlternate
                        : AppColors.sequencerCellEmpty,
                    border: Border.all(
                      color: cellBorderColor,
                      width: cellBorderWidth,
                    ),
                  ),
                ),
                child: gestureChild,
              );
            }

            return gestureChild;
          },
        );
      },
    );
  }

  Widget _buildFlatTabs(
    TableState tableState, {
    required TutorialStep tutorialStep,
    required AppState appState,
  }) {
    final int numSoundGrids = tableState.totalLayers;
    return Column(
      children: [
        SizedBox(
          key: tutorialStep == TutorialStep.sequencerLayersHint
              ? appState.layersRowTutorialKey
              : null,
          height: 42,
          child: ValueListenableBuilder<int>(
            valueListenable: tableState.uiSelectedLayerNotifier,
            builder: (context, selectedLayer, _) {
              return ValueListenableBuilder<LayerMode>(
                valueListenable: tableState.layerModeNotifier,
                builder: (context, viewMode, __) {
                  return Row(
                    children: List.generate(numSoundGrids, (i) {
                      final isActive = selectedLayer == i;
                      final layerLabel = sequencerLayerLabelForIndex(i);
                      // Check THIS layer's mode, not the global mode
                      final layerMode = tableState.getLayerMode(i);
                      return Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          key: tutorialStep == TutorialStep.sequencerLayersHint &&
                                  !appState.isLayersTabDone &&
                                  i == 0
                              ? appState.layerTabTutorialKey
                              : null,
                          onTap: () {
                            if (!appState.canInteractWithTutorialTarget(
                                TutorialInteractionTarget.layerTab)) {
                              return;
                            }
                            debugPrint(
                                '🎨 [SOUND_GRID] Layer tab $layerLabel tapped, current layer: $selectedLayer');
                            tableState.setUiSelectedLayer(i);
                            tableState.uiBringGridToFront(i);
                            context
                                .read<MultitaskPanelState>()
                                .showLayerSettings();
                            if (tutorialStep == TutorialStep.sequencerLayersHint &&
                                i == 0) {
                              context.read<AppState>().markLayersTabAction();
                            }
                            debugPrint(
                                '🎨 [SOUND_GRID] After tap, layer should be: $i');
                          },
                          child: TutorialPulseWidget(
                            enabled: tutorialStep ==
                                    TutorialStep.sequencerLayersHint &&
                                !appState.isLayersTabDone,
                            borderRadius: BorderRadius.circular(2),
                            child: _LayerTabLabel(
                              label: layerLabel,
                              isActive: isActive,
                              showLevel: layerMode == LayerMode.rec,
                              isMuted: tableState.isLayerMuted(i),
                              isSoloed: tableState.isLayerSoloed(i),
                            ),
                          ),
                        ),
                      );
                    }),
                  );
                },
              );
            },
          ),
        ),
        Expanded(
          child: ValueListenableBuilder<int>(
            valueListenable: tableState.uiSelectedLayerNotifier,
            builder: (context, selectedLayer, _) {
              return ValueListenableBuilder<LayerMode>(
                valueListenable: tableState.layerModeNotifier,
                builder: (context, viewMode, __) {
                  if (viewMode == LayerMode.rec) {
                    return _buildLineMicContent(tableState);
                  }
                  // Do not key by layer: same ScrollController must stay attached so
                  // vertical position is preserved when switching layers in a section.
                  return _buildGridContent(
                    tableState,
                    tutorialStep: tutorialStep,
                    appState: appState,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSampleCellContent(
      BuildContext context,
      TableState tableState,
      int index,
      int sampleSlot,
      bool isActivePad,
      bool isCurrentStep,
      bool isDragHovering) {
    // Get volume and pitch values from states
    final sectionStart = tableState.getSectionStartStep(
        widget.sectionIndexOverride ?? tableState.uiSelectedSection);
    final gridCols = tableState.getVisibleCols().length;
    final row = index ~/ gridCols;
    final colInSlice = index % gridCols;
    final step = sectionStart + row;
    final col = tableState.getLayerStartCol() + colInSlice;
    final cellData = tableState.getCellNotifier(step, col).value;
    final cellVolume = cellData.volume;
    final cellPitch = cellData.pitch;

    // Listen to sample bank defaults so UI updates when sample defaults change
    final sampleBankState = context.read<SampleBankState>();
    final volNotifier = sampleBankState.getSampleVolumeNotifier(sampleSlot);
    final pitchNotifier = sampleBankState.getSamplePitchNotifier(sampleSlot);

    return ValueListenableBuilder<double>(
      valueListenable: volNotifier,
      builder: (context, sampleVolume, _) {
        return ValueListenableBuilder<double>(
          valueListenable: pitchNotifier,
          builder: (context, samplePitch, __) {
            // Treat sentinel values (-1.0) as "inherit from sample bank"
            final bool usesDefaultVolume = cellVolume < 0.0;
            final bool usesDefaultPitch = cellPitch < 0.0;

            final effectiveVolume =
                usesDefaultVolume ? sampleVolume : cellVolume;
            final effectivePitch = usesDefaultPitch ? samplePitch : cellPitch;

            // Check if values are non-default (cell overrides)
            final hasVolumeOverride =
                !usesDefaultVolume && (cellVolume - sampleVolume).abs() > 0.001;
            final hasPitchOverride =
                !usesDefaultPitch && (cellPitch - samplePitch).abs() > 0.001;

            // Only show table if there are non-default values
            final showEffectsTable = hasVolumeOverride || hasPitchOverride;

            if (!showEffectsTable) {
              return const SizedBox.shrink();
            }

            final Color effectsColor = (isActivePad || isDragHovering)
                ? AppColors.sequencerPageBackground
                : isCurrentStep
                    ? Colors.white.withOpacity(0.9)
                    : AppColors.sequencerLightText;
            final TextStyle effectsStyle = TextStyle(
              color: effectsColor,
              fontSize: effectsFontSize,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.15,
              height: 1.0,
            );

            Widget chip(String text, {required bool alignStart}) {
              return Container(
                padding: alignStart
                    ? const EdgeInsets.only(left: 0, right: 4, top: 2, bottom: 2)
                    : const EdgeInsets.only(left: 4, right: 0, top: 2, bottom: 2),
                decoration: BoxDecoration(
                  color: AppColors.sequencerPageBackground.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(1),
                ),
                child: Text(text, style: effectsStyle),
              );
            }

            // Pitch (K…) on the left, volume (V…) on the right; vertically centered in cell.
            return SizedBox.expand(
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (hasPitchOverride)
                      chip(_formatPitchDisplay(effectivePitch), alignStart: true),
                    if (hasPitchOverride && hasVolumeOverride) const Spacer(),
                    if (hasVolumeOverride) ...[
                      if (!hasPitchOverride) const Spacer(),
                      chip('V${(effectiveVolume * 100).round()}',
                          alignStart: false),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyCellContent() {
    // Return a simple container to maintain consistent cell size
    return const SizedBox.shrink();
  }

  /// Compact K + V line for drag feedback (opaque; uses effective pitch/volume).
  Widget _buildCellDragFeedbackContent(
    BuildContext context,
    int sampleSlot,
    double cellVolume,
    double cellPitch,
  ) {
    final sampleBankState = context.read<SampleBankState>();
    final volNotifier = sampleBankState.getSampleVolumeNotifier(sampleSlot);
    final pitchNotifier = sampleBankState.getSamplePitchNotifier(sampleSlot);
    return ValueListenableBuilder<double>(
      valueListenable: volNotifier,
      builder: (context, sampleVolume, _) {
        return ValueListenableBuilder<double>(
          valueListenable: pitchNotifier,
          builder: (context, samplePitch, __) {
            final usesDefaultVolume = cellVolume < 0.0;
            final usesDefaultPitch = cellPitch < 0.0;
            final effectiveVolume =
                usesDefaultVolume ? sampleVolume : cellVolume;
            final effectivePitch =
                usesDefaultPitch ? samplePitch : cellPitch;

            // Match _buildSampleCellContent: only show non-default overrides.
            final hasVolumeOverride =
                !usesDefaultVolume && (cellVolume - sampleVolume).abs() > 0.001;
            final hasPitchOverride =
                !usesDefaultPitch && (cellPitch - samplePitch).abs() > 0.001;
            if (!hasVolumeOverride && !hasPitchOverride) {
              return const SizedBox.shrink();
            }

            final style = TextStyle(
              color: AppColors.sequencerLightText,
              fontSize: effectsFontSize * 0.82,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.12,
              height: 1.0,
            );
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasPitchOverride)
                  Text(_formatPitchDisplay(effectivePitch), style: style),
                if (hasPitchOverride && hasVolumeOverride) Text('  ', style: style),
                if (hasVolumeOverride)
                  Text('V${(effectiveVolume * 100).round()}', style: style),
              ],
            );
          },
        );
      },
    );
  }

  String _formatPitchDisplay(double pitchRatio) {
    // Convert pitch ratio to semitones from center (1.0 = 0 semitones)
    final semitones = 12.0 * (math.log(pitchRatio) / math.ln2);
    final semitonesRounded = semitones.round();

    if (semitonesRounded == 0) {
      return 'K0';
    } else if (semitonesRounded > 0) {
      return 'K+$semitonesRounded';
    } else {
      return 'K$semitonesRounded'; // Negative sign is included in the number
    }
  }

  Widget _buildGridCell(
    BuildContext context,
    TableState tableState,
    int index, {
    required int currentStep,
    required Set<int> selectedSet,
    required TutorialStep tutorialStep,
    required AppState appState,
  }) {
    return _buildEnhancedGridCell(
      context,
      tableState,
      index,
      currentStep: currentStep,
      selectedSet: selectedSet,
      tutorialStep: tutorialStep,
      appState: appState,
    );
  }

  Widget _buildGridRow(
    BuildContext context,
    TableState tableState,
    int rowIndex, {
    required int currentStep,
    required Set<int> selectedSet,
    required TutorialStep tutorialStep,
    required AppState appState,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final gridCols = tableState.getVisibleCols().length;
        final m = _SoundGridRowLayoutMetrics.fromViewportWidth(
          availableWidth,
          gridCols,
          cellWidthPercent: cellWidthPercent,
          cellHeightPercent: cellHeightPercent,
          cellSpacingPercent: cellSpacingPercent,
          rowSpacingPercent: rowSpacingPercent,
          rowNumberColumnWidthPercent: rowNumberColumnWidthPercent,
        );

        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: 0,
            vertical: m.actualRowSpacing / 2, // Use calculated row spacing
          ),
          child: Row(
            children: [
              // Row number column on the left
              Container(
                width: m.actualRowNumberColumnWidth,
                height: m.actualRowHeight,
                decoration: BoxDecoration(
                  color: rowNumberColumnColor,
                  borderRadius: BorderRadius.zero, // Sharp corners
                ),
                child: Center(
                  child: Text(
                    '${rowIndex + 1}',
                    style: TextStyle(
                      color: AppColors.sequencerText,
                      fontSize: 9,
                      // fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
              // Grid cells
              Expanded(
                child: Row(
                  // Use explicit margins for spacing; avoid additional distribution that breaks hit-testing math
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: List.generate(gridCols, (colIndex) {
                    final cellIndex = rowIndex * gridCols + colIndex;
                    return Container(
                      width: m.actualCellWidth,
                      height: m.actualRowHeight,
                      margin: EdgeInsets.symmetric(
                        horizontal: m.actualCellSpacing /
                            2, // Use calculated cell spacing
                      ),
                      child: _buildGridCell(
                        context,
                        tableState,
                        cellIndex,
                        currentStep: currentStep,
                        selectedSet: selectedSet,
                        tutorialStep: tutorialStep,
                        appState: appState,
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildClickableTabLabel({
    required int gridIndex,
    required Color cardColor,
    required bool isFrontCard,
    required int depth,
    required double tabWidth,
    required TableState tableState,
    required TutorialStep tutorialStep,
    required AppState appState,
  }) {
    return ValueListenableBuilder<int>(
      valueListenable: tableState.uiSelectedLayerNotifier,
      builder: (context, selectedLayer, _) {
        final bool isActive = selectedLayer == gridIndex;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          key: tutorialStep == TutorialStep.sequencerLayersHint &&
                  !appState.isLayersTabDone &&
                  gridIndex == 0
              ? appState.layerTabTutorialKey
              : null,
          onTap: () {
            if (!appState.canInteractWithTutorialTarget(
                TutorialInteractionTarget.layerTab)) {
              return;
            }
            // Bring this grid to front and switch UI-visible layer
            tableState.uiBringGridToFront(gridIndex);
            tableState.setUiSelectedLayer(gridIndex);
            context.read<MultitaskPanelState>().showLayerSettings();
            if (tutorialStep == TutorialStep.sequencerLayersHint &&
                gridIndex == 0) {
              context.read<AppState>().markLayersTabAction();
            }
          },
          child: TutorialPulseWidget(
            enabled: tutorialStep == TutorialStep.sequencerLayersHint &&
                !appState.isLayersTabDone,
            borderRadius: BorderRadius.circular(2),
            child: Container(
              width: tabWidth,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              decoration: BoxDecoration(
                color: isActive
                    ? AppColors.sequencerAccent
                    : AppColors.sequencerSurfaceBase, // Inactive tabs recessed
                borderRadius: BorderRadius.circular(2), // Sharp corners
                border: Border.all(
                  color: AppColors.sequencerBorder,
                  width: 0.5,
                ),
                boxShadow: isActive
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
              child: Center(
                child: Text(
                  sequencerLayerLabelForIndex(gridIndex),
                  style: TextStyle(
                    color: isActive
                        ? AppColors.sequencerPageBackground
                        : AppColors.sequencerLightText,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // Unused helper retained for reference - can be deleted if not needed
  // ignore: unused_element
  Widget _buildTabLabel({
    required int gridIndex,
    required Color cardColor,
    required bool isFrontCard,
    required int depth,
    required double tabWidth,
  }) {
    return Container(
      width: tabWidth,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: cardColor.withOpacity(0.8),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Center(
        child: Text(
          sequencerLayerLabelForIndex(gridIndex),
          style: TextStyle(
            color: cardColor,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
            fontFamily: 'monospace',
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildMainCard({
    required double width,
    required double height,
    required Color cardColor,
    required bool isFrontCard,
    required int depth,
    required int actualSoundGridId,
    required int index,
    required TableState tableState,
    required TutorialStep tutorialStep,
    required AppState appState,
  }) {
    // Non-front cards are grayed out but still visible
    if (!isFrontCard) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.sequencerSurfaceBase, // Full opacity background
          borderRadius: BorderRadius.circular(2), // Sharp corners
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
        child: Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.sequencerSurfacePressed,
            borderRadius: BorderRadius.circular(2), // Sharp corners
            border: Border.all(
              color: AppColors.sequencerBorder,
              width: 0.5,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.music_note,
                  color: AppColors.sequencerLightText,
                  size: 40,
                ),
                const SizedBox(height: 8),
                Text(
                  'Layer ${actualSoundGridId + 1}',
                  style: TextStyle(
                    color: AppColors.sequencerLightText,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Front card - clearly highlighted as selected
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceRaised, // Gray-beige surface
        borderRadius: BorderRadius.circular(2), // Sharp corners
        border: Border.all(
          color: context.read<EditState>().isInSelectionMode
              ? AppColors.sequencerAccent
              : AppColors.sequencerBorder, // Brown accent or subtle border
          width: context.read<EditState>().isInSelectionMode
              ? 2
              : 1, // Thicker border when in selection mode
        ),
        boxShadow: [
          // Strong protruding effect for front card
          BoxShadow(
            color: AppColors.sequencerShadow,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: AppColors.sequencerSurfaceRaised,
            blurRadius: 2,
            offset: const Offset(0, -1),
          ),
          // Additional highlight for selection mode
          if (context.read<EditState>().isInSelectionMode)
            BoxShadow(
              color: AppColors.sequencerAccent.withOpacity(0.3),
              blurRadius: 6,
              offset: const Offset(0, 0),
            ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(2), // Reduced padding
        child: Column(
          children: [
            // Minimal space for tab label above
            const SizedBox(height: 8),
            // Sound grid
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: tableState.uiSelectedLayerNotifier,
                builder: (context, selectedLayer, _) {
                  return ValueListenableBuilder<LayerMode>(
                    valueListenable: tableState.layerModeNotifier,
                    builder: (context, viewMode, __) {
                      if (viewMode == LayerMode.rec) {
                        return _buildLineMicContent(tableState);
                      }
                      return _buildGridContent(
                        tableState,
                        tutorialStep: tutorialStep,
                        appState: appState,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridContent(
    TableState tableState, {
    required TutorialStep tutorialStep,
    required AppState appState,
  }) {
    return Container(
      key: tutorialStep == TutorialStep.sequencerFirstCellHint ||
              (tutorialStep == TutorialStep.none &&
                  appState.showTutorialPromptThisSession) ||
              tutorialStep == TutorialStep.sequencerSelectModeHint ||
              tutorialStep == TutorialStep.sequencerSectionsSwipeHint ||
              tutorialStep == TutorialStep.sequencerSectionTwoStepsHint ||
              tutorialStep == TutorialStep.sequencerSectionTwoSamplesHint ||
              tutorialStep == TutorialStep.sequencerSectionsNavigateHint ||
              tutorialStep == TutorialStep.sequencerLayersHint
          ? appState.sampleGridTutorialKey
          : null,
      color: gridBackgroundColor,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportW = constraints.maxWidth;
          final viewportH = constraints.maxHeight;
          _gridViewportWidth = viewportW;
          _gridViewportHeight = viewportH;
          return GestureDetector(
        onPanStart: (details) {
          if (!appState.canInteractWithTutorialTarget(
              TutorialInteractionTarget.sampleGrid)) {
            return;
          }
          _gestureStartPosition = details.localPosition;
          _gestureMode = GestureMode.undetermined;

          if (context.read<EditState>().isInSelectionMode) {
            final cellIndex =
                _positionToCellIndex(details.localPosition, viewportW);
            if (cellIndex != null) {
              context.read<UiSelectionState>().selectCells();
              context.read<EditState>().beginDragSelectionAt(cellIndex);
            }
          }
        },
        onPanUpdate: (details) {
          if (!appState.canInteractWithTutorialTarget(
              TutorialInteractionTarget.sampleGrid)) {
            return;
          }
          _handlePanUpdate(details);
        },
        onPanEnd: (details) {
          _gestureStartPosition = null;
          _currentPanPosition = null;
          _gestureMode = GestureMode.undetermined;
          _stopAutoScroll();

          // No-op for new selection logic: selection is finalized incrementally
        },
        child: ValueListenableBuilder<int>(
          valueListenable: context.read<PlaybackState>().currentStepNotifier,
          builder: (context, currentStep, _) {
            return ValueListenableBuilder<Set<int>>(
              valueListenable: context.read<EditState>().selectedCellsNotifier,
              builder: (context, selectedSet, __) {
                final isInSelectionMode =
                    context.watch<EditState>().isInSelectionMode;
                final sectionStepCount = tableState.getSectionStepCount(
                  widget.sectionIndexOverride ?? tableState.uiSelectedSection,
                );
                return ListView.builder(
                  controller: _scrollController,
                  physics: (isInSelectionMode ||
                          _gestureMode == GestureMode.selecting)
                      ? const NeverScrollableScrollPhysics()
                      : const PositionRetainedScrollPhysics(
                          parent:
                              ClampingScrollPhysics()), // Prevents jumping when rows are added/removed, no bounce at edges
                  itemCount: sectionStepCount +
                      1, // +1 for the control buttons at the bottom
                  itemBuilder: (context, index) {
                    if (index < sectionStepCount) {
                      // Build a row of grid cells
                      return _buildGridRow(
                        context,
                        tableState,
                        index,
                        currentStep: currentStep,
                        selectedSet: selectedSet,
                        tutorialStep: tutorialStep,
                        appState: appState,
                      );
                    } else {
                      // Control buttons at the bottom
                      final int displaySection = widget.sectionIndexOverride ??
                          tableState.uiSelectedSection;
                      final bool isActiveSectionGrid =
                          displaySection == tableState.uiSelectedSection;
                      final bool attachStepControlsTutorialKey =
                          isActiveSectionGrid &&
                              (tutorialStep ==
                                      TutorialStep.sequencerSectionTwoSamplesHint ||
                                  tutorialStep ==
                                      TutorialStep.sequencerSectionTwoStepsHint);
                      return RepaintBoundary(
                        key: attachStepControlsTutorialKey
                            ? appState.gridStepRowControlsTutorialKey
                            : null,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8, top: 4),
                          child: _buildGridRowControls(
                            tableState,
                            tutorialStep: tutorialStep,
                            appState: appState,
                          ),
                        ),
                      );
                    }
                  },
                );
              },
            );
          },
        ),
      );
        },
      ),
    );
  }

  Widget _buildLineMicContent(TableState tableState) {
    final playbackState = context.watch<PlaybackState>();
    final recordingState = context.watch<RecordingState>();
    final waveformState = context.watch<RecordingWaveformState>();
    final micState = context.watch<MicrophoneState>();

    final int displaySection =
        (playbackState.songMode && recordingState.isRecording)
            ? playbackState.currentSection
            : tableState.uiSelectedSection;
    final lines =
        waveformState.getLines(tableState.uiSelectedLayer, displaySection);
    final loopsNum = playbackState.getSectionLoopsNum(displaySection);
    final isRecording = recordingState.isRecording &&
        waveformState.activeLayer == tableState.uiSelectedLayer;
    final shouldCapture = micState.isMicEnabled;
    final isSongMode = playbackState.songMode;

    waveformState.ensureCapture(
      enabled: shouldCapture,
      layer: tableState.uiSelectedLayer,
      section: displaySection,
      playbackState: playbackState,
      tableState: tableState,
      isActuallyRecording:
          recordingState.isRecording, // Pass actual record button state
      levelProvider: micState.getAudioLevel,
    );

    // Calculate line height similar to grid rows (showing ~5 lines in view)
    const double baseRowHeight = 50.0;
    const double lineHeightPercent = 60.0;
    final double actualLineHeight = baseRowHeight * (lineHeightPercent / 100.0);

    // Determine how many lines to show:
    // - Loop mode: Show all recorded lines (unlimited iteration)
    // - Song mode: Show max(recorded lines, loopsNum) to display all data but respect loop limit for playback
    // - No data: Show loopsNum empty lines as placeholder
    final bool hasRecordedData = waveformState.hasRecordedData(
        tableState.uiSelectedLayer, displaySection);
    final int lineCount = hasRecordedData
        ? lines.length // Show all recorded lines
        : loopsNum; // Show placeholder lines if no recording yet

    // Get current step for position indicator (only show if playing)
    final bool isPlaying = playbackState.isPlaying;
    final currentStep = isPlaying ? playbackState.currentStep : null;
    final totalSteps = tableState.getSectionStepCount(displaySection);

    // Calculate which line should be playing based on current step position
    // In loop mode, calculate the loop iteration from step position since engine loop counter is always 0
    final int? currentLoop;
    if (isPlaying && hasRecordedData) {
      if (isSongMode) {
        // Song mode: use engine loop counter
        currentLoop = playbackState.currentSectionLoop;
      } else {
        // Loop mode: calculate loop from step position
        final sectionStartStep = tableState.getSectionStartStep(displaySection);
        final sectionSteps = tableState.getSectionStepCount(displaySection);
        final stepInSection = currentStep! - sectionStartStep;
        currentLoop = stepInSection ~/ sectionSteps; // Integer division
      }

      debugPrint(
          '🔄 [LOOP_COUNTER_DEBUG] UI: currentLoop=$currentLoop, lineCount=$lineCount, isSongMode=$isSongMode, currentStep=$currentStep');
    } else {
      currentLoop = null;
    }

    final int currentLayer = tableState.uiSelectedLayer;

    return Stack(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: gridBackgroundColor,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
              color: AppColors.sequencerBorder,
              width: 0.5,
            ),
          ),
          child: ListView.builder(
            controller: _scrollController,
            physics: const PositionRetainedScrollPhysics(
                parent: ClampingScrollPhysics()),
            itemCount: lineCount,
            itemBuilder: (context, index) {
              final samples = hasRecordedData && index < lines.length
                  ? lines[index]
                  : <int>[];
              final bool isActive = !isSongMode || (index < loopsNum);
              final int? activeLineIndex = currentLoop != null
                  ? (isSongMode
                      ? (currentLoop < loopsNum ? currentLoop : null)
                      : (currentLoop % lineCount))
                  : null;
              final int? stepForThisLine =
                  (activeLineIndex == index) ? currentStep : null;
              return LineMicWaveformWidget(
                samples: samples,
                lineIndex: index + 1,
                loopsNum: loopsNum,
                isRecording: isRecording,
                lineHeight: actualLineHeight,
                currentStep: stepForThisLine,
                totalSteps: totalSteps,
                isSongMode: isSongMode,
                isActive: isActive,
                waveformState: waveformState,
                layer: currentLayer,
                section: displaySection,
              );
            },
          ),
        ),
        Positioned(
          bottom: 12,
          right: 12,
          child: _RecLayerRecordButton(layer: currentLayer),
        ),
      ],
    );
  }

  double _calculateTabPosition(int index, double width, int numSoundGrids) {
    // Calculate tab width with relative spacing
    final tabWidth = _calculateTabWidth(width, numSoundGrids);
    final spacingBetweenTabs = _calculateTabSpacing(width, numSoundGrids);

    // Position from left to right with spacing
    final leftMargin = 8.0; // Small left margin

    // Important: Use only the available card width for positioning
    // The cards may be transformed by StackedCardsWidget but tabs need to align with card boundaries
    return leftMargin + (tabWidth + spacingBetweenTabs) * index;
  }

  double _calculateTabWidth(double width, int numSoundGrids) {
    // Calculate available width for tabs (leaving small margins)
    final leftMargin = 8.0;
    final rightMargin = 8.0;
    final availableWidth = width - leftMargin - rightMargin;

    // Calculate spacing between tabs (relative to number of tabs)
    final spacingBetweenTabs = _calculateTabSpacing(width, numSoundGrids);
    final totalSpacing = spacingBetweenTabs * (numSoundGrids - 1);

    // Calculate tab width with relative spacing
    final tabWidth = (availableWidth - totalSpacing) / numSoundGrids;

    // Ensure minimum tab width
    return tabWidth.clamp(40.0, double.infinity);
  }

  double _calculateTabSpacing(double width, int numSoundGrids) {
    // Relative spacing based on number of tabs and available width
    // More tabs = smaller spacing, fewer tabs = more spacing
    final baseSpacing = width * 0.1; // 2% of card width as base
    final scaleFactor = 1.0 / numSoundGrids; // Reduce spacing as tabs increase

    return (baseSpacing * scaleFactor).clamp(2.0, 12.0); // Min 2px, Max 12px
  }

  // Grid row control buttons - styled like test page buttons
  Timer? _buttonPressTimer;
  bool _isLongPressing = false;
  bool _isDecreasePressed = false;
  bool _isIncreasePressed = false;

  Widget _buildGridRowControls(
    TableState tableState, {
    required TutorialStep tutorialStep,
    required AppState appState,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final actualRowNumberColumnWidth =
            availableWidth * (rowNumberColumnWidthPercent / 100.0);

        final bool twoStepsTutorial =
            tutorialStep == TutorialStep.sequencerSectionTwoStepsHint;
        final GlobalKey? decreaseTutorialKey = twoStepsTutorial &&
                appState.showSectionTwoStepsDecreasePointer
            ? appState.sectionStepsDecreaseTutorialKey
            : null;
        final GlobalKey? increaseTutorialKey = twoStepsTutorial &&
                appState.showSectionTwoStepsIncreasePointer
            ? appState.sectionStepsIncreaseTutorialKey
            : null;

        return Container(
          height: 30, // Reduced height from 40 to 30
          margin: EdgeInsets.zero, // Remove margin to match grid width
          child: Row(
            children: [
              // Row number column spacer (to align with grid)
              Container(
                width: actualRowNumberColumnWidth,
                height: 30,
                decoration: BoxDecoration(
                  color: gridBackgroundColor,
                  borderRadius: BorderRadius.zero, // Sharp corners
                ),
              ),
              // Remove rows button - left half
              Expanded(
                child: _buildControlButton(
                  tutorialKey: decreaseTutorialKey,
                  isEnabled: tableState.getSectionStepCount() > 4,
                  onAction: () => _handleDecreaseRows(tableState),
                  icon: Icons.remove,
                  borderRadius: BorderRadius.zero, // Sharp corners
                  isPressed: _isDecreasePressed,
                  buttonType: 'decrease',
                ),
              ),

              // Add rows button - right half
              Expanded(
                child: _buildControlButton(
                  tutorialKey: increaseTutorialKey,
                  isEnabled:
                      tableState.getSectionStepCount() < tableState.maxSteps,
                  onAction: () => _handleIncreaseRows(tableState),
                  icon: Icons.add,
                  borderRadius: BorderRadius.zero, // Sharp corners
                  isPressed: _isIncreasePressed,
                  buttonType: 'increase',
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildControlButton({
    GlobalKey? tutorialKey,
    required bool isEnabled,
    required VoidCallback onAction,
    required IconData icon,
    required BorderRadius borderRadius,
    required bool isPressed,
    required String buttonType,
  }) {
    return Listener(
      key: tutorialKey,
      onPointerDown: isEnabled
          ? (event) {
              // Update pressed state
              setState(() {
                if (buttonType == 'decrease') {
                  _isDecreasePressed = true;
                } else {
                  _isIncreasePressed = true;
                }
              });

              // Start single action immediately
              onAction();

              // Start long press timer for continuous action
              _buttonPressTimer?.cancel();
              _buttonPressTimer = Timer(const Duration(milliseconds: 300), () {
                if (mounted) {
                  _isLongPressing = true;
                  _startContinuousAction(onAction);
                }
              });
            }
          : null,
      onPointerUp: (event) {
        _stopAllActions();

        // Reset pressed state
        setState(() {
          _isDecreasePressed = false;
          _isIncreasePressed = false;
        });
      },
      onPointerCancel: (event) {
        _stopAllActions();

        // Reset pressed state
        setState(() {
          _isDecreasePressed = false;
          _isIncreasePressed = false;
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: _getButtonColor(isEnabled, isPressed),
          borderRadius: borderRadius,
          border: Border.all(
            color: isPressed
                ? AppColors.sequencerAccent
                : AppColors.sequencerBorder,
            width: isPressed ? 1.5 : 1,
          ),
          boxShadow: isPressed
              ? [
                  // Pressed (inset) shadow effect
                  BoxShadow(
                    color: AppColors.sequencerShadow,
                    blurRadius: 2,
                    offset: const Offset(0, -1),
                  ),
                ]
              : [
                  // Normal (protruding) shadow effect
                  BoxShadow(
                    color: AppColors.sequencerShadow,
                    blurRadius: 1,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: Center(
          child: Icon(
            icon,
            color: isEnabled
                ? (isPressed
                    ? AppColors.sequencerAccent
                    : AppColors.sequencerText)
                : AppColors.sequencerLightText.withOpacity(0.5),
            size: 18, // Slightly smaller icon for reduced button height
          ),
        ),
      ),
    );
  }

  Color _getButtonColor(bool isEnabled, bool isPressed) {
    if (!isEnabled) {
      return gridBackgroundColor.withOpacity(0.3);
    }

    if (isPressed) {
      return gridBackgroundColor.withOpacity(0.5); // Darker when pressed
    }

    return gridBackgroundColor; // Normal state
  }

  void _handleIncreaseRows(TableState tableState) {
    // Check limits - if at limit, stop continuous action
    if (tableState.getSectionStepCount() >= tableState.maxSteps) {
      _isLongPressing = false;
      _stopContinuousAction();
      return;
    }
    tableState.uiAppendStep();

    // Check if we just reached the limit and stop
    if (tableState.getSectionStepCount() >= tableState.maxSteps) {
      _isLongPressing = false;
      _stopContinuousAction();
    }
  }

  void _handleDecreaseRows(TableState tableState) {
    // Check limits - if at limit, stop continuous action
    if (tableState.getSectionStepCount() <= 4) {
      _isLongPressing = false;
      _stopContinuousAction();
      return;
    }
    tableState.uiDeleteLastStep();

    // Check if we just reached the limit and stop
    if (tableState.getSectionStepCount() <= 4) {
      _isLongPressing = false;
      _stopContinuousAction();
    }
  }

  void _startContinuousAction(VoidCallback action) {
    _buttonPressTimer?.cancel();
    _buttonPressTimer = null;

    _buttonPressTimer =
        Timer.periodic(const Duration(milliseconds: 75), (timer) {
      if (!mounted) {
        timer.cancel();
        _buttonPressTimer = null;
        _isLongPressing = false;
        return;
      }

      if (_isLongPressing) {
        action();
      } else {
        timer.cancel();
        _buttonPressTimer = null;
      }
    });
  }

  void _stopContinuousAction() {
    _isLongPressing = false;
    if (_buttonPressTimer != null) {
      _buttonPressTimer!.cancel();
      _buttonPressTimer = null;
    }
  }

  void _stopAllActions() {
    _isLongPressing = false;

    if (_buttonPressTimer != null) {
      _buttonPressTimer!.cancel();
      _buttonPressTimer = null;
    }
  }
}

class _LayerTabLabel extends StatefulWidget {
  final String label;
  final bool isActive;
  final bool showLevel;
  final bool isMuted;
  final bool isSoloed;

  const _LayerTabLabel({
    required this.label,
    required this.isActive,
    required this.showLevel,
    this.isMuted = false,
    this.isSoloed = false,
  });

  @override
  State<_LayerTabLabel> createState() => _LayerTabLabelState();
}

class _LayerTabLabelState extends State<_LayerTabLabel>
    with SingleTickerProviderStateMixin {
  /// Nullable so [dispose] is safe if unmount happens before [initState] finishes
  /// (e.g. hot reload / frame churn).
  AnimationController? _controller;
  double _currentLevel = 0.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 80),
      vsync: this,
    );
    if (widget.showLevel) {
      _startPolling();
    }
  }

  @override
  void didUpdateWidget(covariant _LayerTabLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showLevel && !oldWidget.showLevel) {
      _startPolling();
    } else if (!widget.showLevel && oldWidget.showLevel) {
      _controller?.stop();
      setState(() {
        _currentLevel = 0.0;
      });
    }
  }

  void _startPolling() {
    final c = _controller;
    if (c == null) return;
    c.repeat();
    c.addListener(_pollLevel);
  }

  void _pollLevel() {
    if (!widget.showLevel) return;
    final micState = context.read<MicrophoneState>();
    final level = micState.getAudioLevel();
    setState(() {
      if (micState.isMicEnabled) {
        _currentLevel = level > 0.0 ? level.clamp(0.02, 1.0) : 0.02;
      } else {
        _currentLevel = 0.0;
      }
    });
  }

  @override
  void dispose() {
    final c = _controller;
    if (c != null) {
      c.removeListener(_pollLevel);
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool mutedVisual = widget.isMuted;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      decoration: BoxDecoration(
        color: widget.isActive
            ? AppColors.sequencerAccent
            : AppColors.sequencerSurfaceBase,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: AppColors.sequencerBorder,
          width: 0.5,
        ),
        boxShadow: widget.isActive
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
      child: Stack(
        children: [
          if (widget.showLevel && _currentLevel > 0.0)
            Positioned.fill(
              child: CustomPaint(
                painter: _TabLevelBarPainter(level: _currentLevel),
              ),
            ),
          if (mutedVisual)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.22),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    widget.label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      color: mutedVisual
                          ? (widget.isActive
                              ? AppColors.sequencerPageBackground
                                  .withOpacity(0.55)
                              : AppColors.sequencerLightText.withOpacity(0.65))
                          : (widget.isActive
                              ? AppColors.sequencerPageBackground
                              : AppColors.sequencerLightText),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                  if (widget.isMuted) ...[
                    const SizedBox(width: 2),
                    Text(
                      'M',
                      maxLines: 1,
                      style: TextStyle(
                        color: AppColors.menuErrorColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (widget.isSoloed) ...[
                    const SizedBox(width: 2),
                    Text(
                      'S',
                      maxLines: 1,
                      style: TextStyle(
                        color: const Color(0xFFF4D35E),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabLevelBarPainter extends CustomPainter {
  final double level;
  _TabLevelBarPainter({required this.level});

  @override
  void paint(Canvas canvas, Size size) {
    final levelWidth = size.width * level.clamp(0.0, 1.0);
    final paint = Paint()
      ..color = (level > 0.8
              ? Colors.red
              : (level > 0.5 ? Colors.orange : Colors.green))
          .withOpacity(0.25)
      ..style = PaintingStyle.fill;
    final rect = Rect.fromLTWH(0, 0, levelWidth, size.height);
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)), paint);
  }

  @override
  bool shouldRepaint(covariant _TabLevelBarPainter oldDelegate) =>
      oldDelegate.level != level;
}

/// Pulsing scale + accent border for grid cell drag feedback and placeholder.
class _DragPulseShell extends StatefulWidget {
  final Widget child;

  const _DragPulseShell({required this.child});

  @override
  State<_DragPulseShell> createState() => _DragPulseShellState();
}

class _DragPulseShellState extends State<_DragPulseShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final t = _pulse.value;
        final scale = 1.0 + 0.08 * t;
        return Transform.scale(
          scale: scale,
          alignment: Alignment.center,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: AppColors.sequencerAccent
                    .withOpacity(0.45 + 0.45 * t),
                width: 1.5 + t,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.sequencerAccent.withOpacity(0.12 + 0.2 * t),
                  blurRadius: 6 + 8 * t,
                  spreadRadius: 0.5 * t,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

class _TutorialBlinkCell extends StatefulWidget {
  final Widget child;

  const _TutorialBlinkCell({required this.child});

  @override
  State<_TutorialBlinkCell> createState() => _TutorialBlinkCellState();
}

class _TutorialBlinkCellState extends State<_TutorialBlinkCell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.25, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final borderOpacity = 0.35 + (0.65 * _pulse.value);
        final glowOpacity = 0.18 + (0.30 * _pulse.value);
        return Stack(
          fit: StackFit.expand,
          children: [
            child!,
            IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.tutorialPulseColor.withOpacity(
                    0.06 + (0.10 * _pulse.value),
                  ),
                  border: Border.all(
                    color: AppColors.tutorialPulseColor.withOpacity(borderOpacity),
                    width: 2.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.tutorialPulseColor.withOpacity(glowOpacity),
                      blurRadius: 10 + (6 * _pulse.value),
                      spreadRadius: 0.5 + (1.0 * _pulse.value),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
      child: widget.child,
    );
  }
}

// Full-screen sample browser dialog, styled like the takes menu
class _RecLayerRecordButton extends StatefulWidget {
  final int layer;
  const _RecLayerRecordButton({required this.layer});

  @override
  State<_RecLayerRecordButton> createState() => _RecLayerRecordButtonState();
}

class _RecLayerRecordButtonState extends State<_RecLayerRecordButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Drag-up tracking
  double _dragDy = 0.0;
  bool _dragTriggered = false;
  static const double _dragThreshold = 40.0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startRecording(BuildContext context) async {
    final recordingState = context.read<RecordingState>();
    final micState = context.read<MicrophoneState>();
    final playbackState = context.read<PlaybackState>();

    // Stop output while recording (no feedback like a messenger app)
    if (playbackState.isPlaying) {
      playbackState.stop();
    }

    final micReady = micState.isMicEnabled && micState.checkMicActive();
    if (!micReady) {
      final success = await micState.enableMicrophone();
      if (!success) {
        if (context.mounted && micState.errorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(micState.errorMessage!),
              duration: const Duration(seconds: 3),
              backgroundColor: Colors.red.shade700,
            ),
          );
        }
        return;
      }
    }
    await recordingState.startRecording(layer: widget.layer);
  }

  Future<void> _handleTap(BuildContext context) async {
    final recordingState = context.read<RecordingState>();
    if (recordingState.isRecording) {
      await recordingState.stopRecording();
    } else {
      await _startRecording(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recordingState = context.watch<RecordingState>();
    final isRecording = recordingState.isRecording;

    return GestureDetector(
      onTap: () => _handleTap(context),
      onVerticalDragStart: (_) {
        setState(() {
          _dragDy = 0.0;
          _dragTriggered = false;
        });
      },
      onVerticalDragUpdate: (details) {
        if (isRecording) return;
        setState(() {
          _dragDy =
              (_dragDy + details.delta.dy).clamp(-_dragThreshold * 1.5, 0.0);
        });
        if (!_dragTriggered && _dragDy <= -_dragThreshold) {
          setState(() => _dragTriggered = true);
          _startRecording(context);
        }
      },
      onVerticalDragEnd: (_) {
        setState(() {
          _dragDy = 0.0;
          _dragTriggered = false;
        });
      },
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          final pulseOpacity = isRecording ? _pulseAnimation.value : 1.0;
          final dragProgress = (-_dragDy / _dragThreshold).clamp(0.0, 1.0);

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Static drag indicator (never moves) ──
              if (!isRecording)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: SizedBox(
                    width: 20,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Chevron arrow
                        Icon(
                          Icons.keyboard_arrow_up,
                          size: 13,
                          color: AppColors.sequencerLightText,
                        ),
                        // Track area: thumb travels upward
                        SizedBox(
                          width: 20,
                          height: 32,
                          child: Stack(
                            alignment: Alignment.bottomCenter,
                            children: [
                              // Track line — centered
                              Center(
                                child: Container(
                                  width: 2,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: AppColors.sequencerLightText,
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                ),
                              ),
                              // Thumb — slides upward as you drag
                              Positioned(
                                bottom: (dragProgress * 22).floorToDouble(),
                                child: Container(
                                  width: 3,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: AppColors.sequencerLightText,
                                    borderRadius: BorderRadius.circular(1.5),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ── Round button — moves upward on drag ──
              Opacity(
                opacity: pulseOpacity,
                child: Transform.translate(
                  offset: Offset(0, _dragDy),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isRecording
                          ? AppColors.sequencerPrimaryButton
                          : AppColors.sequencerSurfaceBase,
                      border: Border.all(
                        color: isRecording
                            ? AppColors.sequencerPrimaryButton
                            : AppColors.sequencerBorder,
                        width: 0.5,
                      ),
                    ),
                    child: Center(
                      child: isRecording
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.stop,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ],
                            )
                          : Icon(
                              Icons.mic,
                              size: 22,
                              color: AppColors.sequencerLightText,
                            ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
