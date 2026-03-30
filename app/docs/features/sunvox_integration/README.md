# SunVox Integration Guide

BUILD:
`rehorsed/app/native/sunvox_lib/sunvox_lib/make && chmod +x MAKE_IOS && ./MAKE_IOS`

---

## 1. Overview

This documentation provides a complete guide to the integration of the SunVox audio engine into the Rehorsed sequencer application. The integration includes several critical custom modifications to the SunVox library to support the app's unique sequencing and playback requirements.

The key features of this integration are:
- ✅ **No-Clone Sequencing:** A sample-accurate pattern looping system that avoids memory-intensive pattern clones.
- ✅ **Seamless Playback:** Jitter-free playback, including seamless pattern looping and seamless mode switching between "Song" and "Loop" modes.
- ✅ **Real-Time Pitch Shifting:** Instant, real-time pitch adjustments for samples.
- ✅ **Real-Time Recording:** Ability to record the sequencer's output to a WAV file with live monitoring.

---

## 2. Documentation Index

For detailed information on specific features, please refer to the following documents:

### 📚 Architecture & Overview
- **[SUNVOX_LIBRARY_ARCHITECTURE.md](./SUNVOX_LIBRARY_ARCHITECTURE.md)**: Complete SunVox library architecture guide (general, not Rehorsed-specific). Read this first to understand how SunVox works.
- **[sunvox_rehorsed_tweaks.md](./sunvox_rehorsed_tweaks.md)**: Rehorsed-specific modifications, integrations, control capabilities, and future plans. **Read this for Rehorsed-specific information.**

### 🚀 Core Implementation
- **[no_clone.md](./no_clone.md)**: A comprehensive guide to the sample-accurate, no-clone pattern sequencing implementation. **This is the core of the sequencer logic.**
- **[seamless_playback.md](./seamless_playback.md)**: Explains the engine modifications that enable seamless pattern looping and mode switching.
- **[seamless_step_resize.md](./seamless_step_resize.md)**: Documents the seamless add/remove steps feature (no playback interruption).
- **[pitch.md](./pitch.md)**: Details the real-time pitch shifting system in SunVox (Sampler / note-based pitching).
- **[recording.md](./recording.md)**: Describes the architecture for real-time audio recording to a WAV file.

### 🎛️ Effects System (Future)
- **[effects_implementation_guide.md](./effects_implementation_guide.md)**: Comprehensive guide covering effect architectures (column-based chains vs presets), implementation details, and recommendations

### 🛠️ Technical Details
- **[../../native/sunvox_lib/MODIFICATIONS.md](../../native/sunvox_lib/MODIFICATIONS.md)**: A line-by-line list of all changes made to the original SunVox library source code. Use this for reapplying patches when updating the SunVox version.

---

## 3. Architecture

The integration follows a layered architecture:

```
Flutter/Dart Layer (UI)
    ↓
Native FFI (playback.h)
    ↓
Playback Engine (playback_sunvox.mm)
    ↓
SunVox Wrapper (sunvox_wrapper.mm)
    ↓
Modified SunVox Library (libsunvox.a)
```

- **`playback_sunvox.mm`**: The main native engine that interfaces with the Dart layer and manages the audio device (via miniaudio).
- **`sunvox_wrapper.mm`**: A high-level C++ wrapper that simplifies interaction with the SunVox C API and contains most of the app-specific logic.
- **`sunvox_lib/`**: Our local copy of the SunVox library source, including all custom modifications.

---

## 4. Building and Maintenance

### Building
To apply any changes to the custom SunVox engine, you must rebuild the static library from the source.

```bash
# Navigate to the make directory
cd app/native/sunvox_lib/sunvox_lib/make

# Build for iOS (creates a universal binary)
bash MAKE_IOS

# Build for Android (creates binaries for all architectures)
bash MAKE_ANDROID
```
After rebuilding, perform a `flutter clean` before running the app to ensure the new library is linked.

### Updating SunVox
1. Download the new SunVox library source.
2. Replace the contents of `app/native/sunvox_lib/`.
3. Carefully re-apply the modifications listed in `app/native/sunvox_lib/MODIFICATIONS.md`.
4. Rebuild the library and test thoroughly.

---

## 5. Troubleshooting

- **Playback restarts or audio cuts on mode switch:** Ensure you are using the modified library. This is likely caused by using an older version that doesn't have the seamless `sv_set_position` logic.
- **Samples cut off at loop points:** Verify that the `NO_NOTES_OFF` flag is being set correctly on patterns and that Supertracks mode is enabled. See `seamless_playback.md` for details.
- **"Undefined symbol" errors during build:** This means the native library was not built correctly or is out of sync. Re-run the appropriate `MAKE_` script and then `flutter clean`.
- **Recording file is silent or empty:** Check that SunVox is initialized in `USER_AUDIO_CALLBACK` mode and that the audio buffer is being correctly passed to both the playback device and the WAV writer. See `recording.md` for the correct architecture.
