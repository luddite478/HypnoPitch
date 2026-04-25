# Autostop And Stop Fade (SunVox)

## Overview

This document describes recent transport-stop behavior changes in the SunVox playback path, with focus on autostop state transitions and click-safe stopping.

## What Changed

### 1) End-of-chain output gain stage

A dedicated final amplifier was added at the end of the SunVox master chain:

- Previous chain (master tail): `MasterEQ -> Output`
- New chain (master tail): `MasterEQ -> MasterFinalOut -> Output`

Implementation:

- `app/native/sunvox_wrapper.mm`
  - `connect_master_effect_chain()` now creates `MasterFinalOut` (Amplifier)
  - New wrapper API: `sunvox_wrapper_set_final_output_gain(float gain01)`
- `app/native/sunvox_wrapper.h`
  - Declares `sunvox_wrapper_set_final_output_gain()`

Purpose:

- Provide a graph-level gain control at the very end of SunVox processing.
- Enable clean stop fades without touching per-layer/sample routing.

### 2) Stop fade on transport stop request

`playback_stop()` no longer performs an immediate hard stop. It now:

1. sets playback state to stopped for UI (`is_playing=0`, `current_step=-1`)
2. starts an 80 ms gain ramp on `MasterFinalOut`
3. calls `sunvox_wrapper_stop()` when fade reaches zero

Implementation:

- `app/native/playback_sunvox.mm`
  - added stop-fade runtime state and worker thread
  - constants:
    - `STOP_FADE_MS = 80`
    - `STOP_FADE_STEP_MS = 8`
  - helper flow:
    - `request_stop_with_fade()`
    - `stop_fade_thread_func()`
    - `stop_fade_cancel_and_restore_unity()`

Important behavior detail:

- After fade completion + hard stop, final output gain stays at zero.
- Gain is restored to unity on next `playback_start()`.
- This avoids a stop-edge transient from re-opening the master gain too early.

## Autostop Behavior

Autostop detection remains based on SunVox engine state:

- `sunvox_is_actually_playing()` checks:
  - `sv_end_of_song(0)`
  - in song mode, `sv_get_autostop()` + current line vs song length
- Polling thread (`poll_thread_func`) debounces stop detection (3 consecutive checks).

Current result:

- Engine-driven autostop still updates native playback state and UI as before.
- The new fade path is wired to explicit transport stop requests (`playback_stop()`).
- End-of-song autostop state logic itself is unchanged.

## Teardown Semantics

For deterministic cleanup:

- `playback_cleanup()` requests stop, then force-cancels any in-flight fade and executes immediate hard stop before device uninit.
- This keeps shutdown predictable and avoids dangling fade workers.

## Files Touched

- `app/native/sunvox_wrapper.h`
- `app/native/sunvox_wrapper.mm`
- `app/native/playback_sunvox.mm`

