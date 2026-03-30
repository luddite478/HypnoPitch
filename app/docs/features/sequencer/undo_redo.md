## Undo/Redo (Current Implementation)

### Overview

Undo/redo is still snapshot-based, but now includes batched table-edit transactions for multi-cell actions.

- History: `UNDO_REDO_MAX_HISTORY = 100` entries (oldest dropped when full).
- Snapshot type: `SequencerSnapshot` with pointers to copied module states:
  - `TableState*`
  - `PlaybackState*`
  - `SampleBankState*`
- Snapshots are captured post-mutation by `UndoRedoManager_record()`.
- Undo/redo applies module states in fixed order, then reconciles SunVox pattern content.


### Native state and FFI surface

- Public read model for Flutter is the prefix of native `UndoRedoState`:
  - `version`, `count`, `cursor`, `can_undo`, `can_redo`
  - Exposed by `UndoRedoManager_get_state_ptr()`
- Flutter maps that prefix via `NativePublicUndoRedoState` in `app/lib/ffi/undo_redo_bindings.dart`.
- `UndoRedoState.syncFromNative()` (Dart) uses seqlock-style version checks.


### Recording model

#### Single-action recording

Most mutators still record immediately:

- Table (`app/native/table.mm`):
  - `table_set_cell`
  - `table_clear_cell`
  - `table_set_cell_settings`
  - `table_set_cell_sample_slot`
  - step/section/layer mutations (`insert/delete step`, `set section step count`, `append/delete/reorder section`, `set section`, `set_layer_len`)
- Playback (`app/native/playback_sunvox.mm`):
  - `playback_set_bpm`
  - `playback_set_region`
  - `playback_set_mode`
  - `playback_set_section_loops_num`

`switch_to_section` is treated as navigation and does not record undo.
- Sample bank (`app/native/sample_bank.mm`):
  - `sample_bank_load`
  - `sample_bank_unload`
  - `sample_bank_set_sample_volume`
  - `sample_bank_set_sample_pitch`
  - `sample_bank_set_sample_settings`

#### Batched multi-cell recording

New table transaction APIs in `app/native/table.h` / `table.mm`:

- `table_begin_edit_transaction()`
- `table_mark_step_touched(int step)`
- `table_end_edit_transaction(int record_undo)`

Behavior during transaction:

- Per-cell `sunvox_wrapper_sync_cell()` is suppressed.
- Per-cell `UndoRedoManager_record()` is suppressed.
- Touched sections are tracked.
- On transaction end:
  - touched sections are synced once via `sunvox_wrapper_sync_section(section)`;
  - one undo record is written when `record_undo=1`.

Dart wrappers in `TableState`:

- `beginCellBatchEdit()`
- `endCellBatchEdit()`
- `runCellBatchEdit(...)`

Current migrated multi-cell actions in `EditState`:

- `deleteCells()` runs in one batch transaction.
- Multi-cell branch of `pasteCells()` runs in one batch transaction.
- Assigning a sample to multiple selected cells (cell sound settings / sample browser in SELECT mode) uses `TableState.runCellBatchEdit()` in `sample_selection_widget.dart` so one undo restores all cells.


### Undo/Redo apply flow

Native apply order in `app/native/undo_redo.mm`:

1. `table_apply_state(...)`
2. `playback_apply_state(...)`
3. `sample_bank_apply_state(...)` (with apply mode enabled)
4. SunVox reconciliation: sync all current sections with `sunvox_wrapper_sync_section(...)`

This final sync guarantees audible pattern events match restored table/sample state.


### Sample bank apply-mode optimization

`sample_bank_set_apply_mode(int enabled)` was added to avoid expensive work during snapshot restore.

When apply mode is enabled:

- sample-bank setters skip table-wide rescan + `sunvox_wrapper_sync_cell(...)` loops.
- sample-bank setters skip `UndoRedoManager_record()` calls.

Undo/redo toggles apply mode around `sample_bank_apply_state(...)`.


### Consistency and guardrails

- Redo tail is dropped when recording after undo (standard linear history model).
- Duplicate consecutive snapshots are deduplicated.
- `is_applying` guard prevents undo history pollution during apply.
- Seqlock protects Flutter reads of undo availability fields.


### Non-undo flows

Some bulk/import flows intentionally pass `undoRecord: false` from Dart (e.g. snapshot import and certain recording cleanup operations), so they do not create history entries.


### Debug checklist

- Verify one undo step for a multi-cell delete/paste action.
- Verify undo/redo in playback mode updates both UI and audible output.
- Verify no extra history entries are created during undo/redo apply.
- If buttons lag, inspect timer cadence in `TimerState`/`SyncFrequencyPolicy` (UI polling), not snapshot correctness.


