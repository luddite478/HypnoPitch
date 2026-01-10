## Undo/Redo (Snapshot-Based)

### Overview

Undo/Redo uses simple, self-contained snapshots of native module state:

- 100-entry linear history managed by `UndoRedoManager` (oldest entries are dropped when full)
- Each history entry is a composite sequencer snapshot (`SequencerSnapshot`) built via the shared snapshot module:
  - `TableState`
  - `PlaybackState`
  - `SampleBankState`
- Snapshots are recorded after each mutation (post-state), so each entry represents the user-visible state immediately after an action
- Undo/Redo applies module `*_apply_state` functions to restore state
- A small public, seqlock-protected struct exposes Undo/Redo availability to Flutter without calls


### Native data structures

- `PublicUndoRedoState` (read-only, seqlock)
  - `uint32_t version` (even=stable, odd=writer)
  - `int count`, `int cursor`
  - `int can_undo`, `int can_redo`
  - Getter: `const PublicUndoRedoState* UndoRedoManager_get_state_ptr(void)`

- `SequencerSnapshot` (defined in `sequencer_snapshot.h`)
  - `TableState table`
  - `PlaybackState playback`
  - `SampleBankState sample_bank`

- `TableState`
  - Inline `table[MAX_SEQUENCER_STEPS][MAX_SEQUENCER_COLS]`
  - Inline arrays for `sections` and `layers`

- `PlaybackState` (no pointers, no play/transport)
  - `int bpm`
  - `int region_start`, `region_end`
  - `int song_mode`
  - `int current_section`, `current_section_loop`
  - `int sections_loops_num[MAX_SECTIONS]`
  - Excludes `is_playing`/`current_step` to avoid unwanted transport side-effects during undo/redo

- `SampleBankState` (no pointers)
  - `int loaded[MAX_SAMPLE_SLOTS]`
  - `float volume[MAX_SAMPLE_SLOTS]`, `pitch[MAX_SAMPLE_SLOTS]`
  - `char file_path[MAX_SAMPLE_SLOTS][SAMPLE_MAX_PATH]`
  - `char display_name[MAX_SAMPLE_SLOTS][SAMPLE_MAX_NAME]`
  - `char sample_id[MAX_SAMPLE_SLOTS][SAMPLE_MAX_ID]`


### Native APIs

- Manager
  - `void UndoRedoManager_init(void)` / `void UndoRedoManager_clear(void)`
  - `int UndoRedoManager_canUndo(void)` / `int UndoRedoManager_canRedo(void)`
  - `int UndoRedoManager_undo(void)` / `int UndoRedoManager_redo(void)`
  - `const PublicUndoRedoState* UndoRedoManager_get_state_ptr(void)`
  - Recording (post-mutation): `void UndoRedoManager_record(void)`

- Table
  - `const TableState* table_state_get_ptr(void)`
  - `void table_apply_state(const TableState*)`

- Playback
  - `const PlaybackState* playback_state_get_ptr(void)`
  - `void playback_apply_state(const PlaybackState*)`

- Sample bank
  - `const SampleBankState* sample_bank_state_get_ptr(void)`
  - `void sample_bank_apply_state(const SampleBankState*)`

- Snapshot module
  - `void sequencer_capture_snapshot(SequencerSnapshot* out)`
  - `void sequencer_apply_snapshot(const SequencerSnapshot* s)`


### Recording strategy (modules)

Record a snapshot after each user-visible mutation. One Undo reverts exactly one action.

- Table: `table_set_cell`, `table_clear_cell`, `table_insert_step`, `table_delete_step`, `table_set_section_step_count`, `table_append_section`, `table_delete_section`, `table_update_many_(cells|sections|layers)`
- Playback: `playback_set_bpm`, `playback_set_region`, `playback_set_mode`, `switch_to_section`, `playback_set_section_loops_num`
- Sample bank: `sample_bank_load`, `sample_bank_load_with_id` (no extra record beyond load), `sample_bank_unload`, `sample_bank_set_sample_volume`, `sample_bank_set_sample_pitch`

On first init of each module, seed a baseline snapshot to allow Undo of the first change.


### Global consistency per entry

Even when only one module changed, the manager captures a full composite snapshot so Undo/Redo always restores a consistent system-wide state.


### Apply order

When undoing/redoing, the manager applies in order:
1) `table_apply_state`
2) `playback_apply_state`
3) `sample_bank_apply_state`
This order preserves dependencies.


### Flutter integration

- FFI mapping for `PublicUndoRedoState` mirrors native layout.
- A `UndoRedoState.syncFromNative()` method uses seqlock reads to update `canUndo`/`canRedo` ValueNotifiers.
- The frame ticker (`TimerState`) calls `undoRedoState.syncFromNative()` each frame alongside other modules.
- Buttons call native `undo`/`redo` directly; state refresh occurs on the next tick.
- For JSON export of the entire sequencer, use the snapshot module (see `docs/features/snapshot.md`).


### Usage examples

- Add a sample to bank, then place it in the grid:
  - Two snapshots are recorded (sample bank change, table cell change)
  - A single Undo reverts both table and sample bank to the previous consistent state

- Insert/delete steps:
  - Snapshots recorded post-mutation, `table_apply_state` restores `sections` and `layers` and updates public state; UI observes active section `num_steps` change


### Limits and behavior

- History length: 100 entries (oldest dropped)
- Undo after some undos discards redo tail upon new record
- Public state uses seqlock; Flutter reads are lock-free and consistent
- Playback state does not change transport (play/stop) during Undo/Redo


### Implementation notes

- Unified recording API: `UndoRedoManager_record()` calls the snapshot module to build a composite snapshot and appends it.
- Apply guard: recording is suppressed while applying snapshots to prevent polluting history.
- Deduplication: identical consecutive entries are skipped.
- Table snapshot optimization: only the active rows (sum of section lengths) are copied; trailing rows are reset to defaults on apply.


### Debug tips

- Verify module init seeds a baseline snapshot
- Ensure recording is post-mutation (state reflects what user sees)
- Confirm `*_apply_state` updates module public state inside seqlock begin/end
- If UI doesn’t refresh, check the Flutter side’s change detection for that specific property (e.g., active section `num_steps`)


