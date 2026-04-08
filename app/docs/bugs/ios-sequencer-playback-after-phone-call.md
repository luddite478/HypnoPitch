# iOS: sequencer playback broken after phone call

## Summary

After placing samples on the grid and playing successfully, an **incoming phone call** (or similar system interruption) can leave **play/stop ineffective** or **inaudible** when the user returns to the app. The issue is most plausibly **iOS audio session and Core Audio output recovery**, not SunVox pattern logic itself.

## Symptoms

- Playback worked before the call.
- After the call ends and the user is back in the app, **transport controls appear to fail** or **there is no audible output** (exact UX may vary).

## Architecture (for debugging)

- SunVox runs in **`USER_AUDIO_CALLBACK`** mode; **miniaudio** drives a playback device whose callback invokes SunVox’s audio callback (`playback_sunvox.mm`).
- **`AVAudioSession`** is configured in native code during **`playback_init()`** (e.g. PlayAndRecord, MixWithOthers, DefaultToSpeaker). Miniaudio is built with **`MA_NO_AVFOUNDATION`** (`miniaudio_impl.mm`), so session lifecycle is **app-owned**, not handled inside miniaudio.

## Likely cause

1. **iOS audio interruption**: A call triggers `AVAudioSession` interruption; the session may be **deactivated** or I/O **suspended**. Other apps are expected to **reactivate** the session and often **restart** audio I/O when interruption ends.
2. **No recovery path wired**: `SequencerScreenV2.didChangeAppLifecycleState` on **`resumed`** currently only logs intent to reconfigure the session; it does **not** call native code to reactivate the session or restart the miniaudio device.
3. **SunVox’s role**: In callback mode, SunVox only fills buffers supplied by the host. If Core Audio stops pulling buffers or the session is inactive, **play/stop may still run in software** while **no sound** reaches the speaker.

## Related code locations

- `app/native/playback_sunvox.mm` — `playback_init()`, audio callback, miniaudio device start.
- `app/native/miniaudio_impl.mm` — miniaudio backend flags (`MA_NO_AVFOUNDATION`).
- `app/lib/screens/sequencer_screen_v2.dart` — `didChangeAppLifecycleState` (resume branch).
- `app/lib/state/sequencer/playback.dart` — `PlaybackBindings` (`playback_init` / `playback_start` / `playback_stop`).

## Suggested direction for a fix

- Handle **`AVAudioSessionInterruptionNotification`** (and/or the Dart **`audio_session`** interruption stream) and on **interruption ended** with resume: reactivate the session, then **restart or reinitialize** the miniaudio output if needed.
- Do not rely on **`AppLifecycleState.resumed`** alone; it is not equivalent to audio interruption callbacks for all cases.
- Optionally expose a small native API (e.g. “recover audio output”) callable from Flutter on resume/interruption end, and verify with logs that the audio callback runs after recovery.

## Status

**Open** — documented for investigation; no fix applied in this note.
