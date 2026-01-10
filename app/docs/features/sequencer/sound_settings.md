## Sound Settings: Samples vs Cells

This document describes how sound settings (volume and pitch) are handled at the sample level (defaults) and at the cell level (overrides), how values are resolved for playback, and what the UI shows.

### Concepts

- **Sample-level settings (defaults)**
  - Stored per sample slot in the sample bank.
  - Apply to every grid cell that references the sample, unless that cell has an explicit override.
  - When changed, inheriting cells update immediately (no labels shown on cells).

- **Cell-level settings (overrides)**
  - Stored per cell in the sequencer table.
  - Take precedence over sample defaults from the moment they’re set.
  - Cells with overrides display small labels in the grid (e.g., `V…` for volume, `K…` for pitch).

### Sentinel values (inherit)

Cells use sentinel values to mean “inherit from sample bank”:

- `DEFAULT_CELL_VOLUME = -1.0`
- `DEFAULT_CELL_PITCH = -1.0`

When a cell field holds a sentinel, the effective value is taken from the referenced sample’s defaults.

### Value resolution (effective values)

- Volume: `effectiveVolume = (cell.volume == -1.0) ? sample.volume : cell.volume`
- Pitch: `effectivePitch = (cell.pitch == -1.0) ? sample.pitch : cell.pitch`

UI sliders for cells display these effective values for convenience. Changing a slider writes an explicit value (i.e., it becomes an override), and the cell starts showing a label.

### UI behavior summary

- Drag/placement into the grid creates cells with inheritance by default (both volume and pitch set to `-1.0`).
- **Labels** appear only for cells that have explicit (non-sentinel) values.
- The overlay displays context (e.g., `Sample A` or `Cell 3:5`) so it’s clear what you are editing.

### Processing status and UI spinner

- Native exposes processing status via `is_processing` fields:
  - `Sample.is_processing` in `sample_bank.h` (actively used by UI)
  - `Cell.is_processing` in `table.h` (present for parity; preprocessing is currently keyed by sample)
- The pitch module toggles `Sample.is_processing`:
  - Set to `1` when async SoundTouch preprocessing starts
  - Set to `0` when preprocessing finishes or when a cache hit is detected (no job started)
- Flutter binds the overlay spinner directly to the native processing notifier (no mirroring in Overlay state):
  - Spinner shows while `is_processing == true`
  - The overlay itself is visible only while the finger is pressed on a slider; spinner can appear/disappear under it
  - Spinner area has a fixed size to avoid layout shifts; the value tile is transparent
- The dark overlay dims only the sequencer body and edit buttons area; the multitask panel and header are not dimmed.

### Preprocessing / caching (pitch)

- Default pitch method is SoundTouch preprocessing (high quality, cached in RAM).
- **Sample-level pitch change** triggers asynchronous preprocessing for that sample and pitch, warming the cache so subsequent triggers use the preprocessed audio immediately.
- **Cell-level pitch change** triggers preprocessing only when:
  - method is preprocessing, and
  - the cell pitch is explicit (not sentinel) and meaningfully different from `1.0`.
- Playback resolves sentinels to sample defaults; if no cache exists yet, playback starts unpitched and uses the cache on subsequent triggers.

Implementation notes:
- Processing flags are centralized in the pitch module; async worker calls `sample_bank_set_processing(slot, 1/0)`.
- On cache hit, the pitch module ensures `is_processing` is cleared immediately.

### Lifecycle

- On playback initialization, the pitch preprocessing cache is cleared to avoid stale data across app restarts.

### Debouncing policy

- Sliders react instantly visually; only native updates are debounced.
- Pitch changes (both sample and cell): 250 ms debounce before sending to native.
- Volume changes:
  - Sample volume: 200 ms debounce
  - Cell volume: 150 ms debounce
- While changing volume, pitch-related cache log lines may appear due to harmless cache checks; no preprocessing is started for volume-only changes.

### Implementation touchpoints

- Table (cells):
  - Structs and sentinels: `app/native/table.h`
  - CRUD and defaults: `app/native/table.mm`
  - Flutter table state (set/override/preserve sentinel): `app/lib/state/sequencer/table.dart`

- Sample bank (defaults):
  - State and setters: `app/native/sample_bank.mm`
  - Processing flag: `is_processing` on `Sample` and `sample_bank_set_processing()`
  - Flutter sample state: `app/lib/state/sequencer/sample_bank.dart`

- Playback resolution:
  - Resolves cell defaults vs overrides per step: `app/native/playback.mm`
  - Pitch data source and preprocessing: `app/native/pitch.mm`

- UI overlay and processing binding:
  - Overlay widget: `app/lib/widgets/sequencer/v2/value_control_overlay.dart`
  - Overlay state: `app/lib/state/sequencer/slider_overlay.dart` (binds external processing source)
  - Sliders wire processing notifier: `app/lib/widgets/sequencer/v2/sound_settings.dart` and `generic_slider.dart`

### Removed/changed APIs

- Removed `pitch_is_preprocessed` polling API; UI now observes `is_processing` from native.

### Notes and edge cases

- Existing cells saved with explicit values (e.g., `1.0`) behave as overrides and won’t inherit defaults unless you reset them to sentinel `-1.0`.
- UI shows effective values for inheriting cells, but writes explicit values when you adjust a slider.


