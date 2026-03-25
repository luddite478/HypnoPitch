# UI Performance Optimizations 250426

## Scope
This document summarizes recent visual/performance optimizations across Flutter UI and native table sync, focused on sequencer responsiveness.

## What Was Optimized

- Reduced high-frequency rebuild fan-out in sequencer UI (especially grid + playback controls).
- Introduced adaptive sync cadence in timer-driven state polling.
- Added fast-path checks in sync layers (`playback`, `sample_bank`, `table`) to skip unnecessary work.
- Added native table `content_epoch` dirty marker and Dart-side gating to avoid rescanning visible cells when unchanged.

## Seqlock Version vs Content Epoch

- `version` (seqlock):
  - Purpose: snapshot consistency.
  - Reader retries when writer is active or version changes mid-read.
  - Ensures Dart sees a coherent state.

- `content_epoch` (dirty marker):
  - Purpose: cheap "did content change?" signal.
  - Not a consistency primitive.
  - Lets Dart skip expensive visible-cell refresh when value is unchanged.

Together they solve different problems:
- `version` = correctness of snapshot read.
- `content_epoch` = performance gating for UI refresh.

## Expected Impact

- Lower CPU cost during idle/steady playback.
- Fewer redundant widget rebuilds in dense grid views.
- More predictable frame-time under continuous playback + interaction.

## Follow-up Simplifications

Implemented:

1. **Sync profiling helpers**
   - Added shared `SyncProfiler` helper in `app/lib/state/sequencer/sync_profiling_helpers.dart`.
   - `TableState`, `PlaybackState`, and `SampleBankState` now use this helper instead of duplicated stopwatch/aggregation code.

2. **Adaptive cadence policy**
   - Added centralized `SyncFrequencyPolicy` in `app/lib/state/sequencer/sync_frequency_policy.dart`.
   - `TimerState` now reads cadence values from `SyncFrequencyPolicy.forPlaybackState(...)` instead of hardcoded inline rules.

Still open for future generalization:

3. **Dirty-gated refresh pattern**
   - Epoch/last-seen gating is currently table-specific.
   - Could be abstracted as a generic `DirtyEpochGate` used by other native-backed states.

4. **Selector/Listenable composition**
   - Some screen/widget trees still have manual subscription patterns.
   - Can standardize a small set of patterns/helpers for `Selector`/`ValueListenableBuilder` composition in hot paths.

5. **Native dirty API shape**
   - `content_epoch` is currently scalar.
   - Future extension: optional dirty-region API for section/layer/cell ranges to reduce refresh scope further.

## Validation Checklist

- Run sequencer in three modes:
  - idle view,
  - active playback,
  - drag selection + edit actions.
- Verify no regressions in:
  - playhead progression,
  - section navigation,
  - selection behavior,
  - recording overlay interactions.
- Compare logs for average sync cost and rebuild counters.
