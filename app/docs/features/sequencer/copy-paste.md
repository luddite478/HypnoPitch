### Copy & Paste in the Sequencer Grid

This document explains how copy/paste works in the sequencer grid: selection rules, coordinate mapping, single vs multi-cell paste, and edge cases.

### Selection model
- **Selection space**: The UI grid uses a flat index (`row * visibleCols + col`) over the currently visible layer slice and active section.
- **Anchor cell**: The last explicitly selected cell is stored as the selection “anchor.”
- **Stable grid width**: When selection changes, we capture the grid width (`visibleCols`) at that moment to decode indices consistently, even if layers/visible columns change before paste.

Relevant signals in `EditState`:
- `_selectedCells: Set<int>`: Flat indices in the current grid view
- `_lastSelectedCell: int?`: Anchor cell
- `_selectionTableCols: int`: Grid width at selection time

### Coordinate mapping (UI → native)
For any selected flat index `i`:
- `row = i ~/ tableCols`
- `colInSlice = i % tableCols`
- `step = sectionStart + row`
- `col = layerStart + colInSlice`

Where:
- `sectionStart = TableState.getSectionStartStep(uiSelectedSection)`
- `layerStart = TableState.getLayerStartCol(uiSelectedLayer)`
- `tableCols` is the grid width at selection time (`_selectionTableCols`, fallback to current `visibleCols`).

### Copy algorithm
When copying, selected cells are normalized so the clipboard is relative to the selection’s top-left corner.

Steps:
1. Determine `minRow`, `minCol` across `_selectedCells` using `tableCols` captured at selection time.
2. For each cell in selection:
   - Read native cell via `TableState.getCellPointer(step, col)` and convert to `CellData`.
   - Store `CellClipboardData` with `relativeRow = row - minRow`, `relativeCol = colInSlice - minCol`, and the cell payload.
3. Set flags: `hasClipboardData = clipboard.isNotEmpty`.

Important:
- Empty cells are represented with `sampleSlot = -1`. `CellData.isEmpty`/`isNotEmpty` derive from that.

### Paste algorithm
Compute the base target in the current view, then place each clipboard item at `base + relative`.

Base target (`baseRow`, `baseCol`):
- **Single-cell paste** (`clipboard.length == 1`) and there is an anchor: use the anchor cell exactly (not the top-left of a rectangle). This ensures the paste lands in the visibly selected cell.
- **Multi-cell paste**: use the top-left of the current selection rectangle.

Placement:
- For each clipboard item:
  - `targetRow = baseRow + relativeRow`
  - `targetCol = baseCol + relativeCol`
  - Map to native: `step = sectionStart + targetRow`, `col = layerStart + targetCol`
  - Bounds check against `maxSteps` and `maxCols`.
  - If sample present: `TableState.setCell(step, col, sampleSlot, volume, pitch)`
  - Else: `TableState.clearCell(step, col)`

Batching (multi-cell optimization):
- Clipboard items are grouped per absolute row and overlaid onto a snapshot row array, then `TableState.updateManyCells(rowAbs, rowFlat)` is called once per row to minimize undo records and FFI calls.

### Volume/Pitch semantics
- A cell can store “inherit” sentinels: `volume = -1.0`, `pitch = -1.0` to defer to sample bank defaults.
- Copy/paste preserves these values exactly. UI renders effective values by combining cell value with sample bank defaults.

### Jump insert (optional post-paste)
- If jump-insert mode is enabled, after pasting, selection moves down by `stepInsertSize` rows within the current grid, anchored at the same column.

### Edge cases & safeguards
- **Bounds**: Paste ignores targets beyond native limits (`maxSteps`, `maxCols`).
- **Grid width changes**: Decoding uses `_selectionTableCols` to avoid drift if layer layout changes between selection and paste.
- **Single vs multi**: Single-cell paste uses anchor to match the exact visually selected cell; multi-cell uses selection’s top-left.

### APIs involved
- Selection: `EditState.selectCell`, `selectSingleCell`, `beginDragSelectionAt`, `clearSelection`
- Clipboard: `EditState.copyCells`, `pasteCells`, `deleteCells`
- Mapping helpers (via `TableState`): `getSectionStartStep`, `getLayerStartCol`, `getVisibleCols`, `setCell`, `clearCell`, `updateManyCells`

### Notes on UI hit-testing
- Grid hit-testing accounts for vertical scroll and horizontal spacing to ensure that the cell computed from pointer position aligns with the rendered grid, keeping selection and paste targets in sync.




