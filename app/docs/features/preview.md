## Preview System

This document describes the audio preview system used to play standalone samples and to preview configured cells/samples from the UI without affecting sequencer playback state.

### Goals

- Trigger quick, low-latency previews without disturbing sequencer playback state
- Use the same SunVox-based preview path as the rest of the engine (pitch via `sunvox_preview_*`)
- Keep the audio callback predictable; preview work is routed through the SunVox wrapper

### Architecture Overview

- Native module: `app/native/preview.h` and `app/native/preview.mm`
  - Preview is implemented on top of the SunVox engine (`sunvox_wrapper.h`): slot/cell previews call into `sunvox_preview_slot` / `sunvox_preview_cell` with pitch and volume.
  - File-path preview (`preview_sample_path`) is a minimal stub for API compatibility (volume `0` stops preview; otherwise no separate file-path graph).

- Lifecycle:
  - `preview_init()` / `preview_cleanup()` are no-ops; sequencing hooks call them from playback init/teardown for API symmetry.
  - Stopping preview delegates to `sunvox_preview_stop()`.

### Native API (C)

- Initialization and teardown:
  - `int preview_init(void);`
  - `void preview_cleanup(void);`

- Preview actions:
  - `int preview_sample_path(const char* file_path, float pitch, float volume);`
    - Plays an on-disk audio file at the specified pitch/volume
  - `int preview_slot(int slot, float pitch, float volume);`
    - Plays a loaded sample-bank slot at the specified pitch/volume
  - `int preview_cell(int step, int column, float pitch, float volume);`
    - Plays a cell’s sample using absolute step/column indices; pitch/volume passed-in are applied directly
  - `void preview_stop_sample(void);`
  - `void preview_stop_cell(void);`

Return value is `0` on success; negative on error (e.g., decoder init failure).

### Flutter FFI Bindings

Bindings are exposed in `app/lib/ffi/playback_bindings.dart`:

- `int Function(Pointer<Utf8>, double, double) previewSamplePath`
- `int Function(int, double, double) previewSlot`
- `int Function(int, int, double, double) previewCell`
- `void Function() previewStopSample`
- `void Function() previewStopCell`

### UI Integration

1) Sample Browser (preview via dedicated slot)

- File entries in `app/lib/widgets/sequencer/v2/sample_selection_widget.dart` have play buttons for preview.
- Preview implementation:
  - Samples are temporarily loaded into slot 25 (Z), which serves as a dedicated preview slot
  - `SampleBrowserState.previewSample()` loads the sample via manifest ID using `SampleBankState.loadSample()`
  - Once loaded, `PlaybackState.previewSampleSlot()` is called to play the preview
  - The preview slot is reused if the same sample is already loaded, avoiding unnecessary reloads
  - This approach ensures compatibility with SunVox since samples are loaded into a real slot before previewing
- Integration: Uses `PlaybackState` from Provider, same as sound settings preview

2) Sound Settings (preview current configuration)

- `app/lib/widgets/sequencer/v2/sound_settings.dart` provides live preview during slider interaction.
- Sample settings: calls `PlaybackState.previewSampleSlot(activeSlot, pitch, volume)` using the current sample-bank settings with debounced updates.
- Cell settings: computes absolute `step`/`col` from the selected UI cell; resolves effective pitch/volume (cell override or inherited from sample) and calls `PlaybackState.previewCell(step, col, effPitch, effVol)`.

### Pitch/Volume Semantics

- Sample preview (`preview_slot`) uses the provided pitch/volume directly (UI supplies current values from notifiers)
- Cell preview (`preview_cell`) resolves overrides first:
  - If cell volume is default, it inherits sample-bank volume
  - If cell pitch is default, it inherits sample-bank pitch

### Simplified Approach

- **Sample Browser Preview**: Instead of using `preview_sample_path()` with temporary files, samples are loaded into slot 25 (the dedicated preview slot) and then previewed using `preview_slot()`.
- **Benefits**: 
  - Consistent with sound settings preview behavior
  - Reuses existing sample loading infrastructure
  - Ensures samples are properly loaded into SunVox modules before preview
  - Avoids temporary file management overhead
- **Implementation**: `SampleBrowserState.previewSample()` handles the loading and preview coordination

### Error Handling & Troubleshooting

- Sample loading failed:
  - Check that the sample manifest ID exists in `samples_manifest.json`
  - Verify the asset path in the manifest is correct
  - Ensure slot 25 (preview slot) is available (it may be overwritten during preview, which is acceptable)

- No audio heard:
  - Confirm device is initialized (`playback_init` was successful)
  - Confirm the sample-bank slot is loaded (required for `preview_slot`/`preview_cell`)
  - Verify volume is non-zero and the node graph is running
  - Check that `PlaybackState` is properly initialized before calling preview methods

### Performance Notes

- Preview uses the same node graph and mixes alongside sequencer nodes
- No smoothing is applied for preview; volume is applied immediately on the output bus
- Pitch method selection and preprocessing/cache are reused via `pitch_ds_create(...)`

### Example Calls

Native (C):

```
// Play a file from disk at unity pitch/volume
preview_sample_path("/tmp/snare.wav", 1.0f, 1.0f);

// Play loaded sample slot C (index 2) one octave up at 50% volume
preview_slot(2, 2.0f, 0.5f);

// Play cell at absolute step 10, column 3 with explicit pitch/volume
preview_cell(10, 3, 0.5f, 0.8f);
```

Dart (High-level API via PlaybackState):

```dart
// Sample browser preview (via SampleBrowserState)
final browserState = context.read<SampleBrowserState>();
final playbackState = context.read<PlaybackState>();
final sampleBankState = context.read<SampleBankState>();
await browserState.previewSample(item, sampleBankState, playbackState);

// Sound settings preview (direct PlaybackState usage)
playbackState.previewSampleSlot(activeSlot, pitchRatio: 1.0, volume01: 1.0);
playbackState.previewCell(step: step, colAbs: colAbs, pitchRatio: effPitch, volume01: effVol);

// Stop preview
playbackState.stopPreview();
```

Dart (Low-level FFI - for direct control):

```dart
final bindings = PlaybackBindings();

// Preview loaded slot (preferred method)
bindings.previewSlot(slot, pitch, volume);

// Preview cell with resolved settings
bindings.previewCell(step, colAbs, effPitch, effVol);

// Stop preview
bindings.previewStopSample();
```

### Future Extensions

- Optional smoothing for preview fades
- Pause/seek within preview (e.g., scrubbing)
- Unified preview manager for multiple concurrent previews (currently one per context)


