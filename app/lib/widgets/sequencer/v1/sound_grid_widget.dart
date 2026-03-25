import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import 'dart:math' as math;
import '../../../state/sequencer/table.dart';
import '../../../state/sequencer/sample_bank.dart';
import '../../../state/sequencer/playback.dart';
import '../../../state/sequencer/edit.dart';
import '../../../state/sequencer/multitask_panel.dart';
import '../../../ffi/table_bindings.dart';
import '../../../utils/app_colors.dart';
import '../../stacked_cards_widget.dart';
import '../../../state/sequencer/ui_selection.dart';

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

enum GestureMode { undetermined, scrolling, selecting }

class _SampleGridWidgetState extends State<SampleGridWidget> {
  final ScrollController _scrollController = ScrollController();
  Timer? _autoScrollTimer;
  static const double _autoScrollSpeed = 8.0;
  static const Duration _autoScrollInterval = Duration(milliseconds: 12);
  static const double _edgeThreshold = 50.0;
  
  Offset? _gestureStartPosition;
  Offset? _currentPanPosition;
  GestureMode _gestureMode = GestureMode.undetermined;
  static const double _gestureThreshold = 15.0;

  // CONFIGURABLE GRID DIMENSIONS - Easy to control cell sizing
  static const double cellWidthPercent = 98.0; // Cell width as % of available column space (reduced to make room for row numbers)
  static const double cellHeightPercent = 60.0; // Cell height as % of available row space  
  static const double cellSpacingPercent = 0.0; // Spacing between cells as % of available space
  static const double rowSpacingPercent = 0.0; // Spacing between rows as % of available space
  static const double rowNumberColumnWidthPercent = 6.0; // Row number column width as % of total width
  static const Color rowNumberColumnColor = Color.fromARGB(121, 40, 46, 39); // Color for row number column
  
  // CONFIGURABLE CONTENT SIZING - Control text and element sizes
  static const double sampleLetterFontSize = 14.0; // Font size for sample letters (A, B, C, etc.)
  static const double effectsFontSize = 8.0; // Font size for effects text (V45, K-4, etc.)
  static const double cellPaddingPercent = 0.0; // Internal padding as % of cell size
  
  // CONFIGURATION EXAMPLES - Uncomment and modify as needed:
  // 
  // COMPACT GRID (smaller cells, more spacing):
  // static const double cellWidthPercent = 85.0;
  // static const double cellHeightPercent = 30.0;
  // static const double cellSpacingPercent = 15.0;
  // static const double rowSpacingPercent = 10.0;
  // static const double sampleLetterFontSize = 12.0;
  // static const double effectsFontSize = 7.0;
  //
  // LARGE GRID (bigger cells, less spacing):
  // static const double cellWidthPercent = 98.0;
  // static const double cellHeightPercent = 60.0;
  // static const double cellSpacingPercent = 2.0;
  // static const double rowSpacingPercent = 2.0;
  // static const double sampleLetterFontSize = 16.0;
  // static const double effectsFontSize = 9.0;
  //
  // RECTANGULAR CELLS (wider than tall):
  // static const double cellAspectRatio = 1.5; // 1.5:1 ratio (wider cells)
  // static const double cellAspectRatio = 0.75; // 3:4 ratio (taller cells)

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _scrollController.dispose();
    _stopAllActions(); // Clean up button press timer
    super.dispose();
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
        final renderBox = context.findRenderObject() as RenderBox?;
        final width = renderBox?.size.width ?? MediaQuery.of(context).size.width;
        final cellIndex = _positionToCellIndex(positionToUse, width);
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
    
    if (_gestureMode == GestureMode.undetermined && _gestureStartPosition != null) {
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
    final rb2 = context.findRenderObject() as RenderBox?;
    final width = rb2?.size.width ?? MediaQuery.of(context).size.width;
    final cellIndex = _positionToCellIndex(localPosition, width);
    
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final containerHeight = renderBox.size.height;
      final yPosition = localPosition.dy;
      
      if (yPosition < _edgeThreshold && _scrollController.hasClients && _scrollController.offset > 0) {
        _startAutoScroll(-1.0, localPosition);
        if (cellIndex != null) {
          context.read<UiSelectionState>().selectCells();
          context.read<EditState>().selectCell(cellIndex, extend: true);
        }
        return;
      } else if (yPosition > containerHeight - _edgeThreshold && _scrollController.hasClients && _scrollController.offset < _scrollController.position.maxScrollExtent) {
        _startAutoScroll(1.0, localPosition);
        if (cellIndex != null) {
          context.read<UiSelectionState>().selectCells();
          context.read<EditState>().selectCell(cellIndex, extend: true);
        }
        return;
      } else {
        _stopAutoScroll();
      }
    }
    
    if (cellIndex != null) {
      context.read<UiSelectionState>().selectCells();
      context.read<EditState>().selectCell(cellIndex, extend: true);
    }
  }

  int? _positionToCellIndex(Offset localPosition, double width) {
    final baseRowHeight = 50.0;
    final actualRowHeight = baseRowHeight * (cellHeightPercent / 100.0);
    final actualRowSpacing = baseRowHeight * (rowSpacingPercent / 100.0);
    final rowBlock = actualRowHeight + actualRowSpacing;
    if (rowBlock <= 0) return null;
    // Account for vertical scroll offset so row index corresponds to absolute row
    final scrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;
    final rowIndex = ((scrollOffset + localPosition.dy) / rowBlock).floor();
    if (rowIndex < 0) return null;
    
    final gridCols = context.read<TableState>().getVisibleCols().length;
    final actualRowNumberColumnWidth = width * (rowNumberColumnWidthPercent / 100.0);
    final xInGrid = localPosition.dx - actualRowNumberColumnWidth;
    if (xInGrid < 0) return null;
    final actualCellSpacing = width * (cellSpacingPercent / 100.0);
    final availableWidthForGrid = width - actualRowNumberColumnWidth;
    final totalHorizontalSpacing = actualCellSpacing * (gridCols - 1);
    final availableWidthForCells = availableWidthForGrid - totalHorizontalSpacing;
    final fullCellWidth = availableWidthForCells / gridCols;
    final actualCellWidth = fullCellWidth * (cellWidthPercent / 100.0);
    final cellBlock = actualCellWidth + actualCellSpacing;
    if (cellBlock <= 0) return null;
    // Align hit testing with symmetric margins used in layout (s/2 on both sides)
    final xAdjusted = xInGrid - (actualCellSpacing / 2);
    int colIndex = (xAdjusted / cellBlock).floor();
    if (colIndex < 0) return null;
    if (colIndex >= gridCols) colIndex = gridCols - 1;
    return rowIndex * gridCols + colIndex;
  }

  Color _getSampleColorForGrid(int sampleSlot, BuildContext context) {
    // Get sample bank colors - these are the authoritative colors for samples
    final sampleBankState = Provider.of<SampleBankState>(context, listen: false);
    
    // Use sample bank colors directly, with slight darkening for grid cells
    if (sampleSlot >= 0 && sampleSlot < sampleBankState.uiBankColors.length) {
      final originalColor = sampleBankState.uiBankColors[sampleSlot];
      return Color.lerp(originalColor, AppColors.sequencerCellFilled, 0.3) ?? AppColors.sequencerCellFilled;
    }
    
    // Fallback color for invalid sample slots
    return AppColors.sequencerCellFilled;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TableState>(
      builder: (context, tableState, child) {
        final int numSoundGrids = tableState.totalLayers; // Derive from table state
        
        // Initialize sound grids if not already done or if number changed
        if (tableState.uiSoundGridOrder.length != numSoundGrids) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            tableState.uiInitializeSoundGrids(numSoundGrids);
          });
          return const Center(child: CircularProgressIndicator());
        }
        
        // Get TableState for reading cell data from the new table system (already provided)
        
        final bool isFlat = tableState.uiSoundGridViewMode == SoundGridViewMode.flat;
        return Container(
          margin: const EdgeInsets.only(top: 0, bottom: 0), // Move entire sound grid structure
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
              ? _buildFlatTabs(tableState)
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
              final actualSoundGridId = tableState.uiSoundGridOrder[invertedIndex];
              
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
                const Color(0xFF6B7280), // Gray-500 (repeat for more grids)
                const Color(0xFF374151), // Gray-700 (repeat for more grids)
              ];
              final cardColor = availableColors[actualSoundGridId % availableColors.length];
              
              // The front card is the one that matches the current sound grid index
              final isFrontCard = actualSoundGridId == tableState.uiCurrentSoundGridIndex;
              
              // Wrap everything in a container with minimal extra space for the label tab
              return SizedBox(
                width: width,
                height: height + 100, // More space for tabs positioned lower
                child: Stack(
                  clipBehavior: Clip.none, // Allow tabs to be positioned outside bounds if needed
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
                      ),
                    ),
                    // Clickable tab label positioned above the card
                    // Use actualSoundGridId for positioning to maintain fixed horizontal positions
                    Positioned(
                      top: 15, // Positioned lower to stay within container bounds
                      left: _calculateTabPosition(actualSoundGridId, width, numSoundGrids),
                      child: _buildClickableTabLabel(
                        gridIndex: actualSoundGridId,
                        cardColor: cardColor,
                        isFrontCard: isFrontCard,
                        depth: depth,
                        tabWidth: _calculateTabWidth(width, numSoundGrids),
                        tableState: tableState,
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

  // 🎯 PERFORMANCE: Cell that only rebuilds when current step changes or cell data changes
  Widget _buildEnhancedGridCell(BuildContext context, TableState tableState, int index) {
    final gridCols = tableState.getVisibleCols().length;
    final row = index ~/ gridCols;
    final col = index % gridCols;
    
    // Calculate absolute step and column for TableState (respect section override)
    final sectionIndex = widget.sectionIndexOverride ?? tableState.uiSelectedSection;
    final absoluteStep = tableState.getSectionStartStep(sectionIndex) + row;
    final layerStartCol = tableState.getLayerStartCol();
    final absoluteCol = layerStartCol + col;
    
    return ValueListenableBuilder<int>(
      valueListenable: context.read<PlaybackState>().currentStepNotifier,
      builder: (context, currentStep, child) {
        return ValueListenableBuilder<CellData>(
          valueListenable: tableState.getCellNotifier(absoluteStep, absoluteCol),
          builder: (context, cellData, child) {
            final isActivePad = false; // UI-only highlight not yet wired in TableState
            final isCurrentStep = widget.sectionIndexOverride == null && currentStep >= 0 && currentStep == absoluteStep;
            final placedSample = cellData.sampleSlot >= 0 ? cellData.sampleSlot : null;
            final hasPlacedSample = placedSample != null;
        
        // 🎯 PERFORMANCE: Light bulb-bluish-white highlight for current step
        Color cellColor;
        // ignore: dead_code
        if (isActivePad) {
          cellColor = AppColors.sequencerAccent.withOpacity(0.6);
        } else if (isCurrentStep) {
           // Light bulb-bluish-white highlight for current step
           cellColor = hasPlacedSample 
               ? _getSampleColorForGrid(placedSample, context).withOpacity(0.9)
               : const Color(0xFF87CEEB).withOpacity(0.4); // Light blue highlight
         } else if (hasPlacedSample) {
           cellColor = _getSampleColorForGrid(placedSample, context);
        } else {
          // Alternate cell color for every 4th row (1, 5, 9, etc. in 1-indexed terms)
          final isAlternateRow = row % 4 == 0;
          cellColor = isAlternateRow 
              ? AppColors.sequencerCellEmptyAlternate 
              : AppColors.sequencerCellEmpty;
        }
        
        return DragTarget<int>(
          onAccept: (int sampleSlot) {
            // Use TableState instead of legacy SequencerState for drag operations
            final tableState = Provider.of<TableState>(context, listen: false);
            final gridCols = tableState.getVisibleCols().length;
            final row = index ~/ gridCols;
            final col = index % gridCols;
            
            // Calculate absolute step and column based on current (or overridden) section and layer
            final sectionIndex = widget.sectionIndexOverride ?? tableState.uiSelectedSection;
            final absoluteStep = tableState.getSectionStartStep(sectionIndex) + row;
            final layerStartCol = tableState.getLayerStartCol();
            final absoluteCol = layerStartCol + col;
            
            // Use the new table system with inheritance sentinels
            tableState.setCell(absoluteStep, absoluteCol, sampleSlot, -1.0, -1.0);
            debugPrint('🎵 [DRAG] Set cell [$absoluteStep, $absoluteCol] = sample $sampleSlot');
          },
          builder: (context, candidateData, rejectedData) {
            final bool isDragHovering = candidateData.isNotEmpty;
            
            return GestureDetector(
              onTap: () {
                context.read<UiSelectionState>().selectCells();
                final edit = Provider.of<EditState>(context, listen: false);
                if (edit.isInSelectionMode) {
                  if (edit.selectedCells.contains(index)) {
                    // Tap inside selected area → select single tapped cell
                    edit.selectSingleCell(index);
                  } else {
                    // Tap outside selected area → clear then select single
                    edit.clearSelection();
                    edit.selectSingleCell(index);
                  }
                } else {
                  // Not in selection mode → select single cell
                  edit.selectSingleCell(index);
                }
                tableState.uiHandlePadPress(index);

                // Open cell settings only if the tapped cell has a placed sample (always open for filled)
                final gridColsLocal = tableState.getVisibleCols().length;
                final rowLocal = index ~/ gridColsLocal;
                final colLocal = index % gridColsLocal;
                final sectionIndexLocal = widget.sectionIndexOverride ?? tableState.uiSelectedSection;
                final absoluteStepLocal = tableState.getSectionStartStep(sectionIndexLocal) + rowLocal;
                final absoluteColLocal = tableState.getLayerStartCol() + colLocal;
                final cellDataLocal = tableState.getCellNotifier(absoluteStepLocal, absoluteColLocal).value;
                if (cellDataLocal.sampleSlot >= 0) {
                  Provider.of<MultitaskPanelState>(context, listen: false).showCellSettings();
                }
              },
              child: ValueListenableBuilder<Set<int>>( 
                valueListenable: context.read<EditState>().selectedCellsNotifier,
                builder: (context, selectedSet, _) {
                  final bool isSelected = selectedSet.contains(index);
                  return Container(
                width: double.infinity, // Fill available width
                height: double.infinity, // Fill available height
                decoration: BoxDecoration(
                  color: isDragHovering 
                      ? AppColors.sequencerAccent.withOpacity(0.8)
                      : cellColor,
                  borderRadius: BorderRadius.circular(2),
                  border: isSelected 
                      ? Border.all(color: AppColors.sequencerSelectionBorder, width: 2)
                      : isCurrentStep 
                          ? Border.all(color: const Color(0xFF87CEEB), width: 1.5) // Light blue border for current step
                          : isDragHovering
                              ? Border.all(color: AppColors.sequencerAccent, width: 0.75)
                              : Border.all(color: cellColor, width: 0.5),
                  boxShadow: isSelected
                      ? null
                      : isCurrentStep
                          ? [
                              // Extra glow for current step - light bulb effect
                              BoxShadow(
                                color: const Color(0xFF87CEEB).withOpacity(0.3),
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
                    // Increase inner padding slightly to create space for thin selection border
                    final basePadding = math.min(constraints.maxWidth, constraints.maxHeight) * (cellPaddingPercent / 100.0);
                    final actualPadding = basePadding + 1.0;
                    return Padding(
                      padding: EdgeInsets.all(actualPadding), // Use percentage-based padding relative to cell size
                      child: hasPlacedSample ? _buildSampleCellContent(context, tableState, index, placedSample, isActivePad, isCurrentStep, isDragHovering) : _buildEmptyCellContent(),
                    );
                  },
                ),
                  );
                },
              ),
            );
          },
        );
          },
        );
      },
    );
  }

  Widget _buildFlatTabs(TableState tableState) {
    final int numSoundGrids = tableState.totalLayers;
    return Column(
      children: [
        SizedBox(
          height: 34,
          child: Row(
            children: List.generate(numSoundGrids, (i) {
              final isActive = tableState.uiSelectedLayer == i;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    tableState.setUiSelectedLayer(i);
                    tableState.uiBringGridToFront(i);
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    decoration: BoxDecoration(
                      color: isActive ? AppColors.sequencerSurfaceRaised : AppColors.sequencerSurfaceBase,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                        color: isActive ? AppColors.sequencerAccent : AppColors.sequencerBorder,
                        width: isActive ? 1.0 : 0.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.sequencerShadow,
                          blurRadius: isActive ? 2 : 1,
                          offset: Offset(0, isActive ? 1 : 0.5),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        'L${i + 1}',
                        style: TextStyle(
                          color: isActive ? AppColors.sequencerText : AppColors.sequencerLightText,
                          fontSize: 12,
                          fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        Expanded(
          child: _buildGridContent(tableState),
        ),
      ],
    );
  }

  Widget _buildSampleCellContent(BuildContext context, TableState tableState, int index, int sampleSlot, bool isActivePad, bool isCurrentStep, bool isDragHovering) {
    // Get volume and pitch values from states
    final sectionStart = tableState.getSectionStartStep(widget.sectionIndexOverride ?? tableState.uiSelectedSection);
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

            final effectiveVolume = usesDefaultVolume ? sampleVolume : cellVolume;
            final effectivePitch = usesDefaultPitch ? samplePitch : cellPitch;
    
    // Check if values are non-default (cell overrides)
            final hasVolumeOverride = !usesDefaultVolume && (cellVolume - sampleVolume).abs() > 0.001;
            final hasPitchOverride = !usesDefaultPitch && (cellPitch - samplePitch).abs() > 0.001;
    
    // Only show table if there are non-default values
    final showEffectsTable = hasVolumeOverride || hasPitchOverride;
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Sample letter (always shown on the left)
        Text(
          String.fromCharCode(65 + sampleSlot),
          style: TextStyle(
            color: (isActivePad || isDragHovering) 
                ? AppColors.sequencerPageBackground 
                : isCurrentStep
                    ? Colors.white // Bright white text for current step
                    : AppColors.sequencerText,
            fontWeight: isCurrentStep ? FontWeight.bold : FontWeight.w600,
            fontSize: sampleLetterFontSize,
            letterSpacing: 0.5,
          ),
        ),
        
        // Effects table (only shown if there are non-default values, positioned on the right)
        if (showEffectsTable) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.sequencerPageBackground.withOpacity(0.3),
              borderRadius: BorderRadius.circular(1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (hasVolumeOverride) ...[
                  Text(
                    'V${(effectiveVolume * 100).round()}',
                    style: TextStyle(
                      color: (isActivePad || isDragHovering)
                          ? AppColors.sequencerPageBackground
                          : isCurrentStep
                              ? Colors.white.withOpacity(0.9)
                              : AppColors.sequencerLightText,
                      fontSize: effectsFontSize,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
                if (hasPitchOverride) ...[
                  Text(
                    _formatPitchDisplay(effectivePitch),
                    style: TextStyle(
                      color: (isActivePad || isDragHovering)
                          ? AppColors.sequencerPageBackground
                          : isCurrentStep
                              ? Colors.white.withOpacity(0.9)
                              : AppColors.sequencerLightText,
                      fontSize: effectsFontSize,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
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


  Widget _buildGridCell(BuildContext context, TableState tableState, int index) {
    // 🎯 PERFORMANCE: Use enhanced cell that listens to currentStepNotifier
    return _buildEnhancedGridCell(context, tableState, index);
  }



  Widget _buildGridRow(BuildContext context, TableState tableState, int rowIndex) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate dimensions based on percentages
        final availableWidth = constraints.maxWidth;
        final baseRowHeight = 50.0; // Base height for percentage calculation
        final actualRowHeight = baseRowHeight * (cellHeightPercent / 100.0);
        final actualCellSpacing = availableWidth * (cellSpacingPercent / 100.0);
        final actualRowSpacing = baseRowHeight * (rowSpacingPercent / 100.0);
        
        // Calculate row number column width and grid area
        final actualRowNumberColumnWidth = availableWidth * (rowNumberColumnWidthPercent / 100.0);
        final availableWidthForGrid = availableWidth - actualRowNumberColumnWidth;
        final gridCols = tableState.getVisibleCols().length;
        final totalHorizontalSpacing = actualCellSpacing * (gridCols - 1);
        final availableWidthForCells = availableWidthForGrid - totalHorizontalSpacing;
        final fullCellWidth = availableWidthForCells / gridCols;
        final actualCellWidth = fullCellWidth * (cellWidthPercent / 100.0);
        
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: 0, 
            vertical: actualRowSpacing / 2, // Use calculated row spacing
          ),
          child: Row(
            children: [
              // Row number column on the left
              Container(
                width: actualRowNumberColumnWidth,
                height: actualRowHeight,
                decoration: BoxDecoration(
                  color: rowNumberColumnColor,
                  borderRadius: BorderRadius.circular(2),
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
                      width: actualCellWidth,
                      height: actualRowHeight,
                      margin: EdgeInsets.symmetric(
                        horizontal: actualCellSpacing / 2, // Use calculated cell spacing
                      ),
                      child: _buildGridCell(context, tableState, cellIndex),
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
  }) {
    return GestureDetector(
      onTap: () {
        // Bring this grid to front and switch UI-visible layer
        tableState.uiBringGridToFront(gridIndex);
        tableState.setUiSelectedLayer(gridIndex);
      },
      child: Container(
        width: tabWidth,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: isFrontCard 
              ? AppColors.sequencerSurfaceRaised // Active tab protruding
              : AppColors.sequencerSurfaceBase, // Inactive tabs recessed
          borderRadius: BorderRadius.circular(2), // Sharp corners
          border: Border.all(
            color: isFrontCard 
                ? AppColors.sequencerAccent // Brown accent for active
                : AppColors.sequencerBorder, // Subtle border for inactive
            width: isFrontCard ? 1.0 : 0.5,
          ),
          boxShadow: isFrontCard 
              ? [
                  BoxShadow(
                    color: AppColors.sequencerShadow,
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                  // Extra highlight for protruding effect
                  BoxShadow(
                    color: AppColors.sequencerSurfaceRaised,
                    blurRadius: 1,
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
            'L${gridIndex + 1}',
            style: TextStyle(
              color: isFrontCard 
                  ? AppColors.sequencerText // Light text for active tab
                  : AppColors.sequencerLightText, // Muted text for inactive tab
              fontSize: 12,
              fontWeight: isFrontCard ? FontWeight.bold : FontWeight.w600,
              letterSpacing: 1,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
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
          'L${gridIndex + 1}',
          style: TextStyle(
            color: cardColor,
            fontSize: 12,
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
          width: context.read<EditState>().isInSelectionMode ? 2 : 1, // Thicker border when in selection mode
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
              child: _buildGridContent(tableState),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridContent(TableState tableState) {
    return GestureDetector(
      onPanStart: (details) {
        _gestureStartPosition = details.localPosition;
        _gestureMode = GestureMode.undetermined;
        
        if (context.read<EditState>().isInSelectionMode) {
          final rb = context.findRenderObject() as RenderBox?;
          final width = rb?.size.width ?? MediaQuery.of(context).size.width;
          final cellIndex = _positionToCellIndex(details.localPosition, width);
          if (cellIndex != null) {
            context.read<UiSelectionState>().selectCells();
            context.read<EditState>().beginDragSelectionAt(cellIndex);
          }
        }
      },
      onPanUpdate: (details) {
        _handlePanUpdate(details);
      },
      onPanEnd: (details) {
        _gestureStartPosition = null;
        _currentPanPosition = null;
        _gestureMode = GestureMode.undetermined;
        _stopAutoScroll();
        
        // No-op for new selection logic: selection is finalized incrementally
      },
      child: ListView.builder(
        controller: _scrollController,
        physics: (context.watch<EditState>().isInSelectionMode || _gestureMode == GestureMode.selecting)
            ? const NeverScrollableScrollPhysics()
            : const PositionRetainedScrollPhysics(), // Prevents jumping when rows are added/removed
        itemCount: tableState.getSectionStepCount(widget.sectionIndexOverride ?? tableState.uiSelectedSection) + 1, // +1 for the control buttons at the bottom
        itemBuilder: (context, index) {
          if (index < tableState.getSectionStepCount(widget.sectionIndexOverride ?? tableState.uiSelectedSection)) {
            // Build a row of grid cells
            return _buildGridRow(context, tableState, index);
          } else {
            // Control buttons at the bottom
            return RepaintBoundary(
              child: Container(
                margin: const EdgeInsets.only(left: 16, right: 16, bottom: 60, top: 4),
                child: _buildGridRowControls(tableState),
              ),
            );
          }
        },
      ),
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
  
  Widget _buildGridRowControls(TableState tableState) {
    return Container(
      height: 30, // Reduced height from 40 to 30
      margin: EdgeInsets.zero, // Remove margin to match grid width
      child: Row(
        children: [
          // Remove rows button - left half
          Expanded(
            child: _buildControlButton(
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
              isEnabled: tableState.getSectionStepCount() < tableState.maxSteps,
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
  }

  Widget _buildControlButton({
    required bool isEnabled,
    required VoidCallback onAction,
    required IconData icon,
    required BorderRadius borderRadius,
    required bool isPressed,
    required String buttonType,
  }) {
    return Listener(
      onPointerDown: isEnabled ? (event) {
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
      } : null,
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
                ? (isPressed ? AppColors.sequencerAccent : AppColors.sequencerText)
                : AppColors.sequencerLightText.withOpacity(0.5),
            size: 18, // Slightly smaller icon for reduced button height
          ),
        ),
      ),
    );
  }

  Color _getButtonColor(bool isEnabled, bool isPressed) {
    if (!isEnabled) {
      return AppColors.sequencerCellEmpty.withOpacity(0.3);
    }
    
    if (isPressed) {
      return AppColors.sequencerSurfacePressed; // Darker when pressed
    }
    
    return AppColors.sequencerCellEmpty; // Normal state
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
    
    _buttonPressTimer = Timer.periodic(const Duration(milliseconds: 75), (timer) {
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