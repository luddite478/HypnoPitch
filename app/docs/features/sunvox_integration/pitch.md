# SunVox Pitch Implementation

**Date:** October 15, 2025  
**Status:** ✅ Implemented & Verified

---

## 1. Overview

This document outlines the real-time pitch shifting implementation using the SunVox library. It replaces an older file-based offline preprocessing approach.

The primary goal was to leverage SunVox's real-time capabilities to simplify the codebase, improve performance, and provide instant pitch changes for a better user experience.

---

## 2. The Problem with the Old System

The legacy system had several drawbacks:

- **Slow & Resource-Intensive:** It required generating and saving a new audio file to disk for every unique pitch value, which was slow and consumed significant storage.
- **Delayed Feedback:** Users had to wait for audio files to be processed before hearing their changes.
- **Complex Code:** It involved a complex system for managing asynchronous file generation, caching, and cleanup, spread across multiple files (`pitch.h`, `pitch.mm`, `sample_bank.mm`).
- **File Clutter:** It created numerous pitched sample files (e.g., `sample_p0.840.wav`), which cluttered the project's sample directories.

---

## 3. The SunVox Solution: Real-Time Pitching

The new implementation leverages SunVox's **Sampler** module, which can play samples at different musical notes, effectively changing their pitch in real-time.

### How It Works

The core of the solution is to translate the pitch ratio from the UI into a MIDI note that SunVox can play.

1.  **Pitch as a Ratio:** The UI and the sequencer state store pitch as a *ratio* (e.g., `1.0` for original pitch, `2.0` for one octave up, `0.5` for one octave down).
2.  **Ratio to Semitone Conversion:** This ratio is converted into a semitone offset using the logarithmic formula:
    \[ \text{semitones} = 12 \times \log_2(\text{ratio}) \]
3.  **Final MIDI Note:** The calculated semitone offset is added to a base note (C4, MIDI note 60) to determine the final MIDI note that the SunVox Sampler should play.
    \[ \text{final\_note} = \text{BASE\_NOTE} + \text{semitones} \]

This calculation is performed instantly whenever a note is triggered or a cell is updated in the sequencer grid.

### Technical Implementation

The entire logic is now contained within `app/native/sunvox_wrapper.mm`.

#### Key Code Snippet

This code snippet from `sunvox_wrapper_sync_cell` shows the conversion logic:

```cpp
// Resolve pitch from cell or sample settings
float pitch = cell->settings.pitch;
if (pitch == DEFAULT_CELL_PITCH) {
    Sample* s = sample_bank_get_sample(cell->sample_slot);
    pitch = (s && s->loaded) ? s->settings.pitch : 1.0f;
}

// Guard against non-positive pitch values for log2f
if (pitch <= 0.0f) {
    pitch = 1.0f;
}

// Convert pitch ratio to semitones
float semitones = 12.0f * log2f(pitch);
int final_note = SUNVOX_BASE_NOTE + (int)roundf(semitones);
if (final_note < 0) final_note = 0;
if (final_note > 127) final_note = 127;

// This final_note is then used in sv_set_pattern_event()
int result = sv_set_pattern_event(
    SUNVOX_SLOT,
    pat_id,
    col,
    local_line,
    final_note, // The calculated note
    velocity,
    mod_id + 1,
    0,
    0
);
```

This logic is applied consistently across all functions that handle note events:
- `sunvox_wrapper_sync_cell()`
- `sunvox_wrapper_sync_section()`
- `sunvox_wrapper_trigger_step()`

---

## 4. Benefits of the New System

- **Instantaneous Pitch Changes:** No more waiting. Pitch adjustments are reflected in the audio immediately.
- **Simplified Codebase:** The removal of the entire pre-processing system (`pitch.h`, `pitch.mm`, and related logic) makes the code much cleaner and easier to maintain.
- **Improved Performance:** Eliminates disk I/O and CPU-intensive file generation, resulting in lower resource consumption.
- **No File Management Overhead:** The project is no longer cluttered with pre-rendered audio files.

---

## 5. What Was Removed

The following components of the legacy pitch system have been completely removed from the project:

- **Native Files:** `app/native/pitch.h` and `app/native/pitch.mm`.
- **FFI Bindings:** `app/lib/ffi/pitch_bindings.dart`.
- **UI Settings:** The "Pitch Quality" section in the Sequencer Settings screen, which is no longer relevant.
- **Snapshot Logic:** The step in the snapshot import process that generated pitched files has been removed.



