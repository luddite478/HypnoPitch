# Simple WAV Writer Integration

## What Was Added

A **zero-dependency WAV file writer** to replace miniaudio's `ma_encoder` for recording.

### Files Created

1. **`simple_wav_writer.h`** - Header with 3 simple functions
2. **`simple_wav_writer.mm`** - Implementation (107 lines, just stdio.h)

### Build System Updates

✅ **Xcode Project** (`project.pbxproj`):
- Added `simple_wav_writer.mm` to PBXBuildFile section
- Added `simple_wav_writer.mm` to PBXFileReference section
- Added `simple_wav_writer.h` to PBXFileReference section
- Added both files to PBXGroup (Native Files)
- Added `simple_wav_writer.mm` to PBXSourcesBuildPhase (will be compiled)

✅ **CMake** (`CMakeLists.txt`):
- Added `simple_wav_writer.mm` to `SEQUENCER_SOURCES`

## API Overview

```objective-c
// 1. Open a WAV file for writing
simple_wav_writer writer;
int result = simple_wav_open(&writer, "/path/to/output.wav", 48000, 2);
if (result != 0) {
    // Error opening file
}

// 2. Write float32 PCM frames (interleaved stereo)
float buffer[1024 * 2];  // 1024 frames, 2 channels
sv_audio_callback(buffer, 1024, 0, sv_get_ticks());
simple_wav_write_frames(&writer, buffer, 1024);

// 3. Close and finalize (updates WAV header with correct sizes)
simple_wav_close(&writer);
```

## Features

- ✅ **Zero dependencies** - only uses `stdio.h`
- ✅ **IEEE float32 PCM** - matches SunVox output format perfectly
- ✅ **Stereo/Mono** - configurable channels
- ✅ **Auto-header update** - file sizes calculated on close
- ✅ **Simple API** - 3 functions: open, write, close
- ✅ **Cross-platform** - pure C (well, .mm but no Objective-C)

## Why Not miniaudio's ma_encoder?

1. **Overkill** - We only need WAV output, not MP3/FLAC/etc
2. **Dependencies** - Pulls in entire miniaudio header (13K+ lines)
3. **Complexity** - More moving parts = more things to go wrong
4. **Compatibility concerns** - Eliminates any SunVox/miniaudio interaction issues

## WAV Format Specification

The writer creates standard WAV files with:
- **RIFF header** (12 bytes)
- **fmt chunk** (24 bytes) 
  - Audio format: 3 (IEEE float)
  - Channels: 2 (stereo)
  - Sample rate: 48000 Hz
  - Bit depth: 32-bit float
- **data chunk** (8 bytes + audio data)

Total header size: **44 bytes**

## Integration with Recording System

The current `recording.mm` uses `ma_encoder`. To switch to `simple_wav_writer`:

```objective-c
// Replace ma_encoder with simple_wav_writer
// OLD:
ma_encoder g_output_encoder;
ma_encoder_config config = ma_encoder_config_init(...);
ma_encoder_init_file(path, &config, &g_output_encoder);
ma_encoder_write_pcm_frames(&g_output_encoder, buffer, frames, NULL);
ma_encoder_uninit(&g_output_encoder);

// NEW:
simple_wav_writer g_output_writer;
simple_wav_open(&g_output_writer, path, 48000, 2);
simple_wav_write_frames(&g_output_writer, buffer, frames);
simple_wav_close(&g_output_writer);
```

## Next Steps

1. **Test build** - Verify Xcode compiles successfully
2. **Update recording.mm** - Replace ma_encoder with simple_wav_writer
3. **Test recording** - Create test WAV file
4. **Verify output** - Open in audio editor, check format

## File Locations

- Header: `/Users/romansmirnov/projects/fortuned/app/native/simple_wav_writer.h`
- Implementation: `/Users/romansmirnov/projects/fortuned/app/native/simple_wav_writer.mm`
- Build configs updated: `project.pbxproj`, `CMakeLists.txt`

## Status

✅ Files created  
✅ Xcode project updated  
✅ CMake updated  
⏳ Ready to use (not yet integrated in recording.mm)  








