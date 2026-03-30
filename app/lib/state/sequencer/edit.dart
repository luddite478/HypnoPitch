import 'package:flutter/foundation.dart';
import 'table.dart';
import 'ui_selection.dart';
import '../../ffi/table_bindings.dart' show CellData;

/// State management for edit operations (copy, paste, select, jump insert)
/// Handles table editing functionality
class EditState extends ChangeNotifier {
  final TableState _tableState;
  final UiSelectionState _uiSelection;
  final Set<int> _selectedCells = <int>{};
  // Capture grid width at selection time to decode indices consistently
  int _selectionTableCols = 0;

  // Selection state
  bool _isInSelectionMode = false;
  int? _lastSelectedCell;

  // Clipboard state
  bool _hasClipboardData = false;
  List<CellClipboardData> _clipboardData = [];

  // Jump insert state
  bool _isStepInsertMode = false;
  int _stepInsertSize = 0;

  // Cached result of getSelectedCellsWithSameSample — invalidated when selection changes
  ({
    int sampleSlot,
    int selectedStep,
    int selectedCol,
    List<({int step, int col})> cells
  })? _sameSampleCache;
  bool _sameSampleCacheDirty = true;

  // Value notifiers for UI binding
  final ValueNotifier<bool> isInSelectionModeNotifier =
      ValueNotifier<bool>(false);
  final ValueNotifier<Set<int>> selectedCellsNotifier =
      ValueNotifier<Set<int>>(<int>{});
  final ValueNotifier<bool> hasClipboardDataNotifier =
      ValueNotifier<bool>(false);
  final ValueNotifier<bool> isStepInsertModeNotifier =
      ValueNotifier<bool>(false);
  final ValueNotifier<int> stepInsertSizeNotifier = ValueNotifier<int>(0);

  EditState(this._tableState, this._uiSelection) {
    // When unified selection switches to sample bank or section, clear cell selection without resetting UI selection
    _uiSelection.kindNotifier.addListener(() {
      if ((_uiSelection.isSampleBank || _uiSelection.isSection) &&
          _selectedCells.isNotEmpty) {
        _clearSelectionInternal(preserveUiSelection: true);
      }
    });
  }

  // Getters
  bool get isInSelectionMode => _isInSelectionMode;
  Set<int> get selectedCells => Set.unmodifiable(_selectedCells);
  bool get hasClipboardData => _hasClipboardData;
  bool get isStepInsertMode => _isStepInsertMode;
  int get stepInsertSize => _stepInsertSize;
  bool get hasSelection => _selectedCells.isNotEmpty;

  // Selection methods
  Set<int> _rectSelection(int anchor, int current, int tableCols) {
    final startRow = anchor ~/ tableCols;
    final startCol = anchor % tableCols;
    final endRow = current ~/ tableCols;
    final endCol = current % tableCols;
    final minRow = startRow < endRow ? startRow : endRow;
    final maxRow = startRow > endRow ? startRow : endRow;
    final minCol = startCol < endCol ? startCol : endCol;
    final maxCol = startCol > endCol ? startCol : endCol;
    final Set<int> next = <int>{};
    for (int r = minRow; r <= maxRow; r++) {
      for (int c = minCol; c <= maxCol; c++) {
        next.add(r * tableCols + c);
      }
    }
    return next;
  }

  void _applySelection(Set<int> next, {int? anchor}) {
    _applySelectionInternal(next, anchor: anchor, preserveUiSelection: false);
  }

  void _applySelectionInternal(Set<int> next,
      {int? anchor, bool preserveUiSelection = false}) {
    _selectedCells
      ..clear()
      ..addAll(next);
    _sameSampleCacheDirty = true;
    if (anchor != null) {
      _lastSelectedCell = anchor;
    }
    // Record the grid width used during this selection change
    _selectionTableCols = _tableState.getVisibleCols().length;
    selectedCellsNotifier.value = Set.from(_selectedCells);
    // Update unified UI selection kind
    if (!preserveUiSelection) {
      if (_selectedCells.isNotEmpty) {
        _uiSelection.selectCells();
      } else {
        _uiSelection.clear();
      }
    }
    notifyListeners();
  }

  void toggleSelectionMode() {
    _isInSelectionMode = !_isInSelectionMode;
    if (!_isInSelectionMode && _selectedCells.isNotEmpty) {
      clearSelection();
    }

    isInSelectionModeNotifier.value = _isInSelectionMode;
    notifyListeners();
    debugPrint('✂️ [EDIT] Selection mode: $_isInSelectionMode');
  }

  void selectCell(int cellIndex, {bool extend = false}) {
    if (!_isInSelectionMode) return;

    if (extend) {
      final anchor = _lastSelectedCell ?? cellIndex;
      final tableCols = _tableState.getVisibleCols().length;
      final rect = _rectSelection(anchor, cellIndex, tableCols);
      _applySelection(rect, anchor: anchor);
    } else {
      // Single selection replaces previous, set anchor
      _applySelection({cellIndex}, anchor: cellIndex);
    }
    debugPrint('✂️ [EDIT] Selected cells: ${_selectedCells.length}');
  }

  // Select exactly one cell regardless of selection mode
  void selectSingleCell(int cellIndex) {
    _applySelection({cellIndex}, anchor: cellIndex);
    debugPrint('✂️ [EDIT] Selected single cell: $cellIndex');
  }

  /// In SELECT mode: tap adds the cell; tap again on a selected cell removes it.
  void toggleCellInSelectionMode(int cellIndex) {
    if (!_isInSelectionMode) return;

    if (!_selectedCells.contains(cellIndex)) {
      final next = Set<int>.from(_selectedCells)..add(cellIndex);
      _applySelection(next, anchor: cellIndex);
      debugPrint(
          '✂️ [EDIT] Added cell $cellIndex → ${_selectedCells.length} cells');
      return;
    }

    final next = Set<int>.from(_selectedCells)..remove(cellIndex);
    if (next.isEmpty) {
      _clearSelectionInternal();
    } else {
      _applySelection(next, anchor: next.first);
    }
    debugPrint(
        '✂️ [EDIT] Removed cell $cellIndex → ${_selectedCells.length} cells');
  }

  // Begin a new drag-based rectangular selection starting at this cell
  void beginDragSelectionAt(int cellIndex) {
    _applySelection({cellIndex}, anchor: cellIndex);
    debugPrint('✂️ [EDIT] Begin drag selection at: $cellIndex');
  }

  void clearSelection({bool preserveUiSelection = false}) {
    _clearSelectionInternal(preserveUiSelection: preserveUiSelection);
  }

  void _clearSelectionInternal({bool preserveUiSelection = false}) {
    _lastSelectedCell = null;
    _selectionTableCols = 0;
    _applySelectionInternal({}, preserveUiSelection: preserveUiSelection);
    debugPrint('✂️ [EDIT] Cleared selection');
  }

  void selectAll() {
    if (!_isInSelectionMode) return;

    final tableCols = _tableState.getVisibleCols().length;
    final tableRows =
        _tableState.getSectionStepCount(_tableState.uiSelectedSection);
    _applySelection(
        List<int>.generate(tableRows * tableCols, (i) => i).toSet());
    debugPrint('✂️ [EDIT] Selected all cells: ${_selectedCells.length}');
  }

  /// Ensure rectangular selection mode is enabled.
  void ensureSelectionMode() {
    if (_isInSelectionMode) return;
    _isInSelectionMode = true;
    isInSelectionModeNotifier.value = true;
    notifyListeners();
  }

  /// Returns distinct sample slots used in current section + current layer.
  List<int> getSampleSlotsUsedInVisibleGrid() {
    final sectionStart =
        _tableState.getSectionStartStep(_tableState.uiSelectedSection);
    final rows = _tableState.getSectionStepCount(_tableState.uiSelectedSection);
    final visibleCols = _tableState.getVisibleCols();
    final used = <int>{};

    for (int row = 0; row < rows; row++) {
      final step = sectionStart + row;
      for (final col in visibleCols) {
        final cellPtr = _tableState.getCellPointer(step, col);
        if (cellPtr.address == 0) continue;
        final cellData = CellData.fromPointer(cellPtr);
        if (cellData.isNotEmpty && cellData.sampleSlot >= 0) {
          used.add(cellData.sampleSlot);
        }
      }
    }

    final result = used.toList()..sort();
    return result;
  }

  /// Select all cells in current section + current layer that use [sampleSlot].
  void selectCellsBySampleSlotInVisibleGrid(int sampleSlot) {
    if (!_isInSelectionMode) return;
    if (sampleSlot < 0) {
      _applySelection(<int>{});
      return;
    }

    final sectionStart =
        _tableState.getSectionStartStep(_tableState.uiSelectedSection);
    final rows = _tableState.getSectionStepCount(_tableState.uiSelectedSection);
    final visibleCols = _tableState.getVisibleCols();
    final tableCols = visibleCols.length;
    final next = <int>{};

    for (int row = 0; row < rows; row++) {
      final step = sectionStart + row;
      for (int colInSlice = 0; colInSlice < tableCols; colInSlice++) {
        final absCol = visibleCols[colInSlice];
        final cellPtr = _tableState.getCellPointer(step, absCol);
        if (cellPtr.address == 0) continue;
        final cellData = CellData.fromPointer(cellPtr);
        if (cellData.isNotEmpty && cellData.sampleSlot == sampleSlot) {
          next.add(row * tableCols + colInSlice);
        }
      }
    }

    _applySelection(next);
    debugPrint(
        '✂️ [EDIT] Selected by sample slot $sampleSlot: ${_selectedCells.length}');
  }

  /// Returns selected cells as absolute (step, col) positions for the
  /// current section + current layer selection slice.
  List<({int step, int col})> getSelectedAbsoluteCells() {
    if (_selectedCells.isEmpty) return const [];

    final sectionStart =
        _tableState.getSectionStartStep(_tableState.uiSelectedSection);
    final layerStart = _tableState.getLayerStartCol(_tableState.uiSelectedLayer);
    final tableCols = _selectionTableCols > 0
        ? _selectionTableCols
        : _tableState.getVisibleCols().length;

    final result = <({int step, int col})>[];
    for (final cellIndex in _selectedCells) {
      final row = cellIndex ~/ tableCols;
      final colInSlice = cellIndex % tableCols;
      result.add((step: sectionStart + row, col: layerStart + colInSlice));
    }
    return result;
  }

  /// Returns current selected batch for cell-settings bulk editing.
  /// If all selected cells share one sample slot, [sampleSlot] is that slot,
  /// otherwise it is null.
  ({
    int? sampleSlot,
    int selectedStep,
    int selectedCol,
    List<({int step, int col})> cells
  })? getSelectedBatchForSettings() {
    if (_selectedCells.isEmpty) return null;

    final tableCols = _selectionTableCols > 0
        ? _selectionTableCols
        : _tableState.getVisibleCols().length;
    final sectionStart =
        _tableState.getSectionStartStep(_tableState.uiSelectedSection);
    final layerStart = _tableState.getLayerStartCol(_tableState.uiSelectedLayer);

    final anchor = _lastSelectedCell ?? _selectedCells.first;
    final selectedStep = sectionStart + (anchor ~/ tableCols);
    final selectedCol = layerStart + (anchor % tableCols);

    final cells = getSelectedAbsoluteCells();
    if (cells.isEmpty) return null;

    int? commonSlot;
    bool mixedSlots = false;
    for (final cell in cells) {
      final ptr = _tableState.getCellPointer(cell.step, cell.col);
      if (ptr.address == 0) {
        mixedSlots = true;
        break;
      }
      final cd = CellData.fromPointer(ptr);
      final slot = (cd.isNotEmpty && cd.sampleSlot >= 0) ? cd.sampleSlot : null;
      if (commonSlot == null) {
        commonSlot = slot;
      } else if (commonSlot != slot) {
        mixedSlots = true;
        break;
      }
    }

    return (
      sampleSlot: mixedSlots ? null : commonSlot,
      selectedStep: selectedStep,
      selectedCol: selectedCol,
      cells: cells,
    );
  }

  /// Returns (sampleSlot, selectedStep, selectedCol, list of (step, col)) for all cells
  /// in the entire song that share the sample of the selected cell. Returns null if
  /// selection is empty or selected cell has no sample. Result is cached until selection changes.
  ({
    int sampleSlot,
    int selectedStep,
    int selectedCol,
    List<({int step, int col})> cells
  })? getSelectedCellsWithSameSample() {
    if (_selectedCells.isEmpty) return null;

    if (!_sameSampleCacheDirty && _sameSampleCache != null) {
      return _sameSampleCache;
    }
    _sameSampleCacheDirty = false;

    final tableCols = _selectionTableCols > 0
        ? _selectionTableCols
        : _tableState.getVisibleCols().length;
    final sectionStart =
        _tableState.getSectionStartStep(_tableState.uiSelectedSection);
    final layerStart =
        _tableState.getLayerStartCol(_tableState.uiSelectedLayer);

    // Get the selected cell's absolute position and sample slot
    final cellIndex = _selectedCells.first;
    final row = cellIndex ~/ tableCols;
    final col = cellIndex % tableCols;
    final selectedStep = sectionStart + row;
    final selectedCol = layerStart + col;
    final cellPtr = _tableState.getCellPointer(selectedStep, selectedCol);
    if (cellPtr.address == 0) {
      _sameSampleCache = null;
      return null;
    }
    final cellData = CellData.fromPointer(cellPtr);
    if (!cellData.isNotEmpty || cellData.sampleSlot < 0) {
      _sameSampleCache = null;
      return null;
    }
    final targetSlot = cellData.sampleSlot;

    // Scan the entire song for cells with the same sample
    final maxSteps = _tableState.maxSteps;
    final maxCols = _tableState.maxCols;
    final List<({int step, int col})> cells = [];
    for (var s = 0; s < maxSteps; s++) {
      for (var c = 0; c < maxCols; c++) {
        final cellP = _tableState.getCellPointer(s, c);
        if (cellP.address == 0) continue;
        final cd = CellData.fromPointer(cellP);
        if (cd.isNotEmpty && cd.sampleSlot == targetSlot) {
          cells.add((step: s, col: c));
        }
      }
    }
    if (cells.isEmpty) {
      _sameSampleCache = null;
      return null;
    }
    _sameSampleCache = (
      sampleSlot: targetSlot,
      selectedStep: selectedStep,
      selectedCol: selectedCol,
      cells: cells
    );
    return _sameSampleCache;
  }

  // Clipboard methods
  void copyCells() {
    if (_selectedCells.isEmpty) return;

    _clipboardData.clear();
    final sectionStart =
        _tableState.getSectionStartStep(_tableState.uiSelectedSection);
    final layerStart =
        _tableState.getLayerStartCol(_tableState.uiSelectedLayer);
    final tableCols = _selectionTableCols > 0
        ? _selectionTableCols
        : _tableState.getVisibleCols().length;
    // Normalize copied coordinates to the top-left of the current selection
    final minRow = _selectedCells
        .map((i) => i ~/ tableCols)
        .reduce((a, b) => a < b ? a : b);
    final minCol = _selectedCells
        .map((i) => i % tableCols)
        .reduce((a, b) => a < b ? a : b);

    for (final cellIndex in _selectedCells) {
      final row = cellIndex ~/ tableCols;
      final colInSlice = cellIndex % tableCols;
      final step = sectionStart + row;
      final col = layerStart + colInSlice;

      final cellPtr = _tableState.getCellPointer(step, col);
      if (cellPtr.address != 0) {
        final cellData = CellData.fromPointer(cellPtr);
        _clipboardData.add(CellClipboardData(
          relativeRow: row - minRow,
          relativeCol: colInSlice - minCol,
          sampleSlot: cellData.isNotEmpty ? cellData.sampleSlot : null,
          volume: cellData.volume,
          pitch: cellData.pitch,
        ));
      }
    }

    _hasClipboardData = _clipboardData.isNotEmpty;
    hasClipboardDataNotifier.value = _hasClipboardData;
    notifyListeners();
    debugPrint('📋 [EDIT] Copied ${_clipboardData.length} cells');
  }

  void pasteCells() {
    if (!_hasClipboardData || _clipboardData.isEmpty) return;

    final sectionStart =
        _tableState.getSectionStartStep(_tableState.uiSelectedSection);
    final layerStart =
        _tableState.getLayerStartCol(_tableState.uiSelectedLayer);
    final tableColsSel = _selectionTableCols > 0
        ? _selectionTableCols
        : _tableState.getVisibleCols().length;

    // Find the top-left corner of the selection or use first selected cell
    int baseRow = 0;
    int baseCol = 0;
    if (_selectedCells.isNotEmpty) {
      if (_clipboardData.length == 1 && _lastSelectedCell != null) {
        // For single-cell paste, target exactly the anchor (visually selected cell)
        baseRow = _lastSelectedCell! ~/ tableColsSel;
        baseCol = _lastSelectedCell! % tableColsSel;
      } else {
        // For multi-cell paste, use top-left of the rectangle
        final rows = _selectedCells.map((i) => i ~/ tableColsSel);
        final cols = _selectedCells.map((i) => i % tableColsSel);
        baseRow = rows.reduce((a, b) => a < b ? a : b);
        baseCol = cols.reduce((a, b) => a < b ? a : b);
      }
    }

    if (_clipboardData.length > 1) {
      // Group clipboard items by absolute target row and bulk update per row
      final int maxCols = _tableState.maxCols;
      final Map<int, Map<int, CellData>> rowColToCell =
          <int, Map<int, CellData>>{};
      for (final clipData in _clipboardData) {
        final targetRow = baseRow + clipData.relativeRow;
        final targetCol = baseCol + clipData.relativeCol;
        final rowAbs = sectionStart + targetRow;
        final colAbs = layerStart + targetCol;
        if (rowAbs >= _tableState.maxSteps || colAbs >= maxCols) continue;
        final cell = (clipData.sampleSlot != null)
            ? CellData(
                sampleSlot: clipData.sampleSlot!,
                volume: clipData.volume,
                pitch: clipData.pitch,
                isProcessing: false)
            : const CellData(
                sampleSlot: -1, volume: 1.0, pitch: 1.0, isProcessing: false);
        rowColToCell.putIfAbsent(rowAbs, () => <int, CellData>{})[colAbs] =
            cell;
      }
      _tableState.runCellBatchEdit(() {
        for (final rowAbs in rowColToCell.keys.toList()..sort()) {
          // Start from current row baseline
          final List<CellData> rowFlat = List<CellData>.generate(
            maxCols,
            (col) => CellData.fromPointer(_tableState.getCellPointer(rowAbs, col)),
          );
          // Overlay pasted cells for this row
          final overrides = rowColToCell[rowAbs]!;
          overrides.forEach((col, cell) {
            rowFlat[col] = cell;
          });
          _tableState.updateManyCells(rowAbs, rowFlat);
        }
      });
    } else {
      for (final clipData in _clipboardData) {
        final targetRow = baseRow + clipData.relativeRow;
        final targetCol = baseCol + clipData.relativeCol;
        final step = sectionStart + targetRow;
        final col = layerStart + targetCol;

        if (step < _tableState.maxSteps && col < _tableState.maxCols) {
          if (clipData.sampleSlot != null) {
            _tableState.setCell(step, col, clipData.sampleSlot!,
                clipData.volume, clipData.pitch);
          } else {
            _tableState.clearCell(step, col);
          }
        }
      }
    }

    notifyListeners();
    debugPrint('📋 [EDIT] Pasted ${_clipboardData.length} cells');

    // Jump insert: after pasting, move selection down by configured cells.
    // Wrap to the first step of the next cycle when exceeding section bounds
    // (e.g. 16 steps + jump 2: at step 14, next is step 0, not step 15).
    if (_isStepInsertMode) {
      final tableColsAfter = _tableState.getVisibleCols().length;
      final maxRows =
          _tableState.getSectionStepCount(_tableState.uiSelectedSection);
      final nextBaseRow = (baseRow + _stepInsertSize) % maxRows;
      final nextIndex = nextBaseRow * tableColsAfter + baseCol;
      selectSingleCell(nextIndex);
      debugPrint(
          '🔗 [EDIT] Jumped selection by $_stepInsertSize cells to row $nextBaseRow');
    }
  }

  void deleteCells() {
    if (_selectedCells.isEmpty) return;

    final sectionStart =
        _tableState.getSectionStartStep(_tableState.uiSelectedSection);
    final layerStart =
        _tableState.getLayerStartCol(_tableState.uiSelectedLayer);
    final tableCols = _selectionTableCols > 0
        ? _selectionTableCols
        : _tableState.getVisibleCols().length;

    _tableState.runCellBatchEdit(() {
      for (final cellIndex in _selectedCells) {
        final row = cellIndex ~/ tableCols;
        final colInSlice = cellIndex % tableCols;
        final step = sectionStart + row;
        final col = layerStart + colInSlice;

        if (step < _tableState.maxSteps && col < _tableState.maxCols) {
          _tableState.clearCell(step, col);
        }
      }
    });

    notifyListeners();
    debugPrint('🗑️ [EDIT] Deleted ${_selectedCells.length} cells');
  }

  // Jump insert methods
  void toggleStepInsertMode() {
    _isStepInsertMode = !_isStepInsertMode;
    isStepInsertModeNotifier.value = _isStepInsertMode;
    notifyListeners();
    debugPrint('🔗 [EDIT] Jump insert mode: $_isStepInsertMode');
  }

  void setStepInsertSize(int size) {
    _stepInsertSize = size.clamp(0, 16);
    stepInsertSizeNotifier.value = _stepInsertSize;
    final shouldEnableJumpMode = _stepInsertSize > 0;
    if (_isStepInsertMode != shouldEnableJumpMode) {
      _isStepInsertMode = shouldEnableJumpMode;
      isStepInsertModeNotifier.value = _isStepInsertMode;
    }
    notifyListeners();
    debugPrint(
        '🔗 [EDIT] Jump insert size: $_stepInsertSize, mode: $_isStepInsertMode');
  }

  void insertStepsAtPosition(int step) {
    _tableState.insertStep(_tableState.uiSelectedSection, step);
    notifyListeners();
    debugPrint('➕ [EDIT] Inserted step at position $step');
  }

  void deleteStepAtPosition(int step) {
    _tableState.deleteStep(_tableState.uiSelectedSection, step);
    notifyListeners();
    debugPrint('➖ [EDIT] Deleted step at position $step');
  }

  @override
  void dispose() {
    isInSelectionModeNotifier.dispose();
    selectedCellsNotifier.dispose();
    hasClipboardDataNotifier.dispose();
    isStepInsertModeNotifier.dispose();
    stepInsertSizeNotifier.dispose();
    super.dispose();
  }
}

/// Data structure for clipboard operations
class CellClipboardData {
  final int relativeRow;
  final int relativeCol;
  final int? sampleSlot;
  final double volume;
  final double pitch;

  const CellClipboardData({
    required this.relativeRow,
    required this.relativeCol,
    required this.sampleSlot,
    required this.volume,
    required this.pitch,
  });
}
