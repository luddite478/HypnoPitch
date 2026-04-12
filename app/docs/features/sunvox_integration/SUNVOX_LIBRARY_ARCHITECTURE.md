# SunVox Library - Complete Architecture Guide

**A Comprehensive Manual for Understanding the SunVox Audio Engine**

Version: 2.1.2b  
Based on: `/app/native/sunvox_lib/`  
Official Documentation: https://warmplace.ru/soft/sunvox/sunvox_lib.php

> **Note:** This document covers **general SunVox architecture**. For **Rehorsed-specific modifications, integrations, and control capabilities**, see `sunvox_rehorsed_tweaks.md`.

---

## Table of Contents

1. [Introduction](#chapter-1-introduction)
2. [High-Level Architecture](#chapter-2-high-level-architecture)
3. [Core Concepts](#chapter-3-core-concepts)
4. [Directory Structure](#chapter-4-directory-structure)
5. [Data Structures](#chapter-5-data-structures)
6. [Data Flow and Audio Pipeline](#chapter-6-data-flow-and-audio-pipeline)
7. [Module System (PSynth)](#chapter-7-module-system-psynth)
8. [Pattern System and Sequencing](#chapter-8-pattern-system-and-sequencing)
9. [Audio Callback and Real-Time Processing](#chapter-9-audio-callback-and-real-time-processing)
10. [File I/O and Project Management](#chapter-10-file-io-and-project-management)
11. [Integration and API Usage](#chapter-11-integration-and-api-usage)
12. [Advanced Topics](#chapter-12-advanced-topics)

---

## Chapter 1: Introduction

### What is SunVox Library?

SunVox Library is the core audio engine of SunVox, provided as a standalone library without a graphical interface. It enables developers to integrate powerful modular synthesis and pattern-based sequencing capabilities into their own applications.

### Key Capabilities

- **Modular Synthesis**: Connect synthesizers, samplers, and effects in complex audio processing networks
- **Pattern-Based Sequencing**: Tracker-style composition with precise timing control
- **Real-Time Audio**: Sample-accurate audio processing suitable for interactive applications
- **Multi-Format Support**: Load `.sunvox`, `.sunsynth`, WAV, AIFF, XI, OGG, MP3, FLAC
- **Cross-Platform**: Works on iOS, Android, macOS, Windows, Linux, and web (WebAssembly)
- **Multiple Slots**: Run multiple independent SunVox projects simultaneously

### Use Cases

- Music players and DAW applications
- Game audio engines with dynamic/interactive music
- Live performance tools
- Generative music systems
- Educational music software

---

## Chapter 2: High-Level Architecture

### Architectural Overview

The SunVox Library follows a layered architecture:

```
┌─────────────────────────────────────────────────────┐
│          Application Layer (Your Code)              │
│         (Uses Public API from sunvox.h)             │
└─────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────┐
│            SunVox Engine Layer                      │
│    (sunvox_engine.h/cpp - Timeline & Playback)      │
│  • Pattern Sequencer                                │
│  • Timeline Management                              │
│  • Event Distribution                               │
│  • Recording                                        │
└─────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────┐
│          PSynth Network Layer                       │
│      (psynth_net.h - Module System)                 │
│  • Module Graph Management                          │
│  • Event Routing                                    │
│  • Audio Mixing                                     │
└─────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────┐
│        Individual Modules (PSynth Modules)          │
│  • Generators (Synths, Samplers)                    │
│  • Effects (Reverb, Delay, Filters)                 │
│  • Controllers (LFO, ADSR, Glide)                   │
└─────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────┐
│           SunDog Platform Layer                     │
│      (lib_sundog - Cross-platform utilities)        │
│  • Audio I/O                                        │
│  • File System                                      │
│  • Threading & Memory                               │
│  • MIDI Support                                     │
└─────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────┐
│        Auxiliary Libraries                          │
│  • DSP (lib_dsp - Signal processing)                │
│  • FLAC (lib_flac - Audio codec)                    │
│  • MP3 (lib_mp3 - Audio codec)                      │
│  • Vorbis (lib_vorbis - Audio codec)                │
└─────────────────────────────────────────────────────┘
```

### Core Components

1. **SunVox Engine** (`lib_sunvox/sunvox_engine.*`)
   - Project management
   - Timeline and pattern playback
   - Event scheduling
   - Recording system

2. **PSynth Network** (`lib_sunvox/psynth/psynth_net.*`)
   - Module graph
   - Audio routing
   - Event distribution to modules

3. **PSynth Modules** (`lib_sunvox/psynth/psynths_*`)
   - Individual synthesizers and effects
   - Each module is self-contained

4. **SunDog Platform** (`lib_sundog/`)
   - Cross-platform abstractions
   - Audio I/O, file system, threading

5. **Public API** (`sunvox_lib/headers/sunvox.h`)
   - C-style interface for external applications

---

## Chapter 3: Core Concepts

### 3.1 Slots

**Slots** are independent instances of the SunVox engine. Each slot can load and play a separate project.

- Maximum slots: typically up to 4-8 (configurable)
- Slot numbering: 0, 1, 2, ...
- Each slot has its own:
  - Pattern timeline
  - Module network
  - Playback state
  - BPM and speed settings

**Usage:**
```c
sv_open_slot(0);  // Open slot 0
sv_load(0, "song.sunvox");  // Load project into slot 0
sv_play(0);  // Start playback on slot 0
```

### 3.2 Modules

**Modules** are the building blocks of sound in SunVox. Each module is a unit that generates or processes audio.

**Module Types:**

1. **Generators** (Sound Sources)
   - Synthesizers (FM, Generator, MultiSynth)
   - Samplers
   - Drum machines
   - Input module (audio input)

2. **Effects** (Sound Processors)
   - Reverb, Delay, Echo
   - Filters, EQ
   - Distortion, Compressor
   - Flanger, Vibrato

3. **Controllers** (Modulation)
   - LFO (Low Frequency Oscillator)
   - ADSR (Envelope)
   - Glide
   - MultiCtl

**Module Connections:**
- Modules are connected in a directed graph
- Audio flows from source to destination
- Special "Output" module is the final destination

### 3.3 Patterns

**Patterns** are sequences of musical events (notes, controller changes, effects) arranged in a tracker-style grid.

**Pattern Structure:**
- **Lines** (vertical): Timeline positions (like rows in a spreadsheet)
- **Tracks** (horizontal): Independent note channels
- **Events**: Each cell contains a note event with:
  - Note number (C0-B9, note off, etc.)
  - Velocity
  - Target module
  - Controller/effect command
  - Controller value

**Pattern Timeline:**
- Patterns are placed on a timeline at specific X positions (line numbers)
- Multiple patterns can play simultaneously (up to 64)
- Patterns can be cloned (instances share data) or copied (independent data)

### 3.4 Events

**Events** are the atomic units of musical information in SunVox.

**Event Types:**

1. **Note Events**
   - Note On (1-127 = note number + 1)
   - Note Off (128)
   - All Notes Off (129)
   - Clean Synths (130)
   - Control commands (Play, Stop, etc.)

2. **Controller Events**
   - Module parameter changes (volume, pitch, filter cutoff, etc.)
   - MIDI CC messages

3. **Effects**
   - Pattern effects (arpeggio, portamento, vibrato, etc.)
   - Timeline effects (jump, speed change)

### 3.5 Timeline and Playback

**Timeline** is the horizontal axis where patterns are arranged.

- Measured in **lines** (absolute positions)
- Each line is subdivided into **ticks**
- **BPM** (Beats Per Minute): Tempo
- **TPL** (Ticks Per Line): Speed of playback
- **LPB** (Lines Per Beat): Grid resolution

**Playback Modes:**

1. **Timeline Mode**: Play through all patterns sequentially
2. **Pattern Loop Mode**: Loop a single pattern (added by Rehorsed modifications)
3. **Autostop**: Stop at end of project vs. loop forever

### 3.6 Audio Callback

The **audio callback** is the real-time function that generates audio output.

**Flow:**
1. Application/OS requests audio frames (e.g., 512 frames)
2. SunVox audio callback is invoked
3. Engine processes timeline, reads pattern events
4. Events are sent to modules
5. Modules generate/process audio
6. Audio is mixed and returned to application/OS

**Threading:**
- Audio callback runs on a high-priority audio thread
- UI operations must use `sv_lock_slot()` / `sv_unlock_slot()`

---

## Chapter 4: Directory Structure

### 4.1 Top-Level Structure

```
sunvox_lib/
├── lib_dsp/           # Digital signal processing utilities
├── lib_flac/          # FLAC audio codec
├── lib_mp3/           # MP3 audio codec (dr_mp3)
├── lib_vorbis/        # Vorbis/Ogg audio codec
├── lib_sundog/        # Cross-platform framework
├── lib_sunvox/        # SunVox engine implementation
└── sunvox_lib/        # Public API, examples, binaries
```

### 4.2 lib_dsp/ - Digital Signal Processing

**Purpose:** Low-level DSP functions used by audio modules

**Key Files:**
- `dsp.h`: DSP function declarations
- `dsp_functions.cpp`: Implementations (filters, oscillators, etc.)
- `dsp_tables.cpp`: Lookup tables for fast computation

**Functions:**
- Interpolation
- Fast trigonometric functions
- Filter coefficient calculations

### 4.3 lib_flac/, lib_mp3/, lib_vorbis/ - Audio Codecs

**Purpose:** Support for loading and saving audio files

- **lib_flac/**: FLAC lossless compression
- **lib_mp3/**: MP3 decompression (dr_mp3 header-only library)
- **lib_vorbis/**: Ogg Vorbis compression/decompression

**Integration:**
- Used when loading samples into Sampler modules
- Used in export functions

### 4.4 lib_sundog/ - Platform Abstraction Layer

**Purpose:** Cross-platform utilities that SunVox depends on

**Subdirectories:**

1. **file/** - File system operations
   - `file.h`, `file.cpp`: Cross-platform file I/O
   - `file_format.cpp`: File format detection and conversion
   - `file_apple.mm`: macOS/iOS specific file handling

2. **log/** - Logging system
   - `log.h`, `log.cpp`: Debug and error logging

3. **main/** - Platform entry points
   - `main.cpp`: Main application entry
   - Platform-specific subdirectories (android/, ios/, macos/)

4. **memory/** - Memory management
   - `memory.h`, `memory.cpp`: Memory allocation utilities

5. **misc/** - Miscellaneous utilities
   - `misc.h`, `misc.cpp`: String operations, utilities

6. **net/** - Networking
   - `net.h`, `net.cpp`: Network operations (not heavily used in lib)

7. **sound/** - Audio I/O
   - `sound.h`, `sound.cpp`: Audio stream management
   - `sound_ios.mm`, `sound_macos.hpp`: Platform audio backends
   - `sound_common_jack.hpp`: JACK audio support

8. **thread/** - Threading
   - `thread.h`, `thread.cpp`: Thread and mutex abstractions

9. **time/** - Time functions
   - `time.h`, `time.cpp`: High-resolution timers

10. **video/** - Video/display (minimal in library)
    - `video.h`, `video.cpp`: Display information

11. **wm/** - Window manager (GUI framework, minimal in library version)
    - GUI components (not used in SUNVOX_LIB builds)

**Key Files:**
- `sundog.h`: Main header, platform detection, configuration

### 4.5 lib_sunvox/ - SunVox Engine Core

**Purpose:** The heart of SunVox - engine, modules, patterns, sequencing

**Top-Level Files:**

- `sunvox_engine.h`: Main engine structure and API declarations
- `sunvox_engine.cpp`: Engine initialization and management
- `sunvox_engine_audio_callback.cpp`: Real-time audio processing
- `sunvox_engine_patterns.cpp`: Pattern management
- `sunvox_engine_load_proj.cpp`: Project loading
- `sunvox_engine_save_proj.cpp`: Project saving
- `sunvox_engine_load_module.cpp`: Module loading
- `sunvox_engine_save_module.cpp`: Module saving
- `sunvox_engine_export.cpp`: Export to WAV/MIDI
- `sunvox_engine_record.cpp`: Recording system
- `sunvox_engine_action_handler.cpp`: Undo/redo actions
- `sunvox_engine_helper.h`: Helper macros

**Subdirectories:**

1. **psynth/** - Module system (detailed in section 4.6)
2. **midi_file/** - MIDI file support
   - `midi_file.h`, `midi_file.cpp`: MIDI import/export
3. **xm/** - XM (FastTracker II) module support
   - `xm.h`, `xm_*.cpp`: XM file loader

### 4.6 lib_sunvox/psynth/ - Module System

**Purpose:** PSynth (PixiSynth) is the modular audio synthesis framework

**Core Files:**

- `psynth.h`: Module handler interface, event structures
- `psynth_net.h`: Module network (graph) management
- `psynth_net.cpp`: Network implementation
- `psynth_net_midi_in.cpp`: MIDI input handling
- `psynth_dsp.h`, `psynth_dsp.cpp`: DSP utilities for modules
- `psynth_strings.h`, `psynth_strings.cpp`: String resources
- `psynth_gui_utils.h`, `psynth_gui_utils.cpp`: GUI helpers (for full app)

**Module Implementation Files:**

Each module type has its own implementation file:

**Generators:**
- `psynths_generator.cpp`: Simple waveform generator
- `psynths_generator2.cpp`: Advanced generator
- `psynths_drumsynth.cpp`: Drum synthesizer
- `psynths_fm.cpp`, `psynths_fm2.cpp`: FM synthesizers
- `psynths_kicker.cpp`: Kick drum synthesizer
- `psynths_sampler.cpp`: Sample player
- `psynths_spectravoice.cpp`: Spectral synthesizer
- `psynths_vorbis_player.cpp`: Vorbis file player
- `psynths_multisynth.cpp`: Multi-voice synthesizer
- `psynths_input.cpp`: Audio input module

**Effects:**
- `psynths_amplifier.cpp`: Volume control
- `psynths_compressor.cpp`: Dynamic range compression
- `psynths_delay.cpp`: Delay effect
- `psynths_echo.cpp`: Echo effect
- `psynths_reverb.cpp`: Reverb effect
- `psynths_distortion.cpp`: Distortion/overdrive
- `psynths_filter.cpp`, `psynths_filter2.cpp`: Filters
- `psynths_eq.cpp`: Equalizer
- `psynths_vocal_filter.cpp`: Formant filter
- `psynths_flanger.cpp`: Flanger effect
- `psynths_vibrato.cpp`: Vibrato effect
- `psynths_waveshaper.cpp`: Waveshaping
- `psynths_pitch_shifter.cpp`: Pitch shift
- `psynths_dc_blocker.cpp`: DC offset removal
- `psynths_loop.cpp`: Loop module
- `psynths_fft.cpp`: FFT analyzer

**Controllers:**
- `psynths_lfo.cpp`: Low frequency oscillator
- `psynths_adsr.cpp`: Envelope generator
- `psynths_glide.cpp`: Pitch glide
- `psynths_modulator.cpp`: Ring modulator
- `psynths_smooth.cpp`: Smoothing/slew limiter
- `psynths_multictl.cpp`: Multi-controller
- `psynths_ctl2note.cpp`: Controller to note converter
- `psynths_pitch2ctl.cpp`: Pitch to controller converter
- `psynths_sound2ctl.cpp`: Audio to controller converter
- `psynths_velocity2ctl.cpp`: Velocity to controller converter
- `psynths_pitch_detector.cpp`: Pitch detection
- `psynths_gpio.cpp`: GPIO control (hardware)
- `psynths_feedback.cpp`: Feedback router

**Special:**
- `psynths_metamodule.cpp`: Nested SunVox project module
- `psynths_sampler.h`: Sampler module header
- `psynths_sampler_gui*.h`: GUI components for sampler

### 4.7 sunvox_lib/ - Public API and Distribution

**Purpose:** Public interface, examples, and precompiled binaries

**Structure:**

```
sunvox_lib/
├── headers/
│   └── sunvox.h              # Public API (C interface)
├── docs/
│   ├── readme.txt            # Usage instructions
│   ├── changelog.txt         # Version history
│   ├── support.txt           # Support information
│   └── license/              # License files
├── examples/
│   ├── c/                    # C examples
│   ├── c (static lib)/       # Static linking examples
│   └── pixilang/             # PixiLang examples
├── android/                  # Android library + sample project
├── ios/                      # iOS library + sample project
├── js/                       # JavaScript/WebAssembly library
├── linux/                    # Linux library (lib_x86, lib_x86_64, lib_arm*)
├── macos/                    # macOS library
├── windows/                  # Windows library (DLL)
├── main/                     # Library main file
│   └── sunvox_lib.cpp        # Public API implementation
└── make/                     # Build scripts
    ├── MAKE_IOS              # iOS build script
    ├── MAKE_ANDROID          # Android build script
    └── ...                   # Other platform build scripts
```

**Key File:**
- `headers/sunvox.h`: Complete public API documentation

---

## Chapter 5: Data Structures

### 5.1 sunvox_engine

**Definition:** `lib_sunvox/sunvox_engine.h`

The main SunVox engine structure that contains the entire state of a project.

```c
struct sunvox_engine {
    // Initialization
    volatile int initialized;
    uint32_t flags;              // SUNVOX_FLAG_*
    int freq;                    // Sample rate
    
    // Project info
    uint base_version;           // SunVox version
    char* proj_name;             // Project name
    uint16_t bpm;                // Beats per minute
    uint8_t speed;               // Ticks per line (TPL)
    uint8_t tgrid, tgrid2;       // Grid settings
    
    // Playback state
    volatile int playing;        // 0 = stopped, 1 = playing
    volatile int recording;      // Recording active
    int line_counter;            // Current line position
    uint tick_counter;           // Tick counter (fixed point)
    int single_pattern_play;     // Pattern loop mode (-1 = off)
    int restart_pos;             // Project restart position
    bool stop_at_the_end_of_proj; // Autostop flag
    
    // Pattern loop counting (Rehorsed modifications)
    int pattern_loop_counts[256];      // Loop count per pattern
    int pattern_current_loop[256];     // Current loop iteration
    int pattern_sequence[64];          // Pattern playback order
    int pattern_sequence_count;        // Sequence length
    
    // Timeline
    int* sorted_pats;            // Sorted pattern table
    int sorted_pats_num;         // Number of sorted patterns
    int cur_playing_pats[64];    // Currently active patterns
    int proj_lines;              // Project length in lines
    uint proj_len;               // Project length in frames
    
    // Patterns
    sunvox_pattern** pats;       // Pattern array
    sunvox_pattern_info* pats_info; // Pattern metadata
    int pats_num;                // Number of pattern slots
    sunvox_pattern_state* pat_state; // Pattern playback states
    int pat_state_size;          // Pattern state capacity
    
    // Modules (PSynth network)
    psynth_net* net;             // Module network
    int selected_module;         // Currently selected module
    
    // MIDI
    sunvox_midi* midi;           // MIDI input/output
    
    // Events
    sunvox_kbd_events* kbd;      // Keyboard events
    sring_buf* user_commands;    // User command buffer
    sring_buf* out_ui_events;    // Output events for UI
    
    // Visualization
    uint8_t f_volume_l[...];     // Volume visualization
    uint8_t f_volume_r[...];     // Volume visualization
    int f_line[...];             // Line position visualization
    
    // ...many more fields...
};
```

**Key Fields Explained:**

- **flags**: Control engine behavior (supertracks, one-thread mode, etc.)
- **line_counter**: Current playback position (line number)
- **tick_counter**: Sub-line position (for smooth playback)
- **pats**: Array of pointers to patterns (can have holes/NULL entries)
- **net**: The module network (PSynth graph)
- **kbd**: Keyboard event handling for live input

### 5.2 sunvox_pattern

**Definition:** `lib_sunvox/sunvox_engine.h`

A pattern contains musical events arranged in a grid.

```c
struct sunvox_pattern {
    sunvox_note* data;       // Event data (2D array: lines × tracks)
    int data_xsize;          // Allocated track count
    int data_ysize;          // Allocated line count
    
    uint32_t id;             // Unique pattern ID
    
    int channels;            // Visible track count
    int lines;               // Visible line count
    int ysize;               // (unused)
    
    uint32_t flags;          // SUNVOX_PATTERN_FLAG_*
    
    char* name;              // Pattern name
    
    uint16_t icon[16];       // 16x16 icon pixels
    uint8_t fg[3];           // Foreground color (RGB)
    uint8_t bg[3];           // Background color (RGB)
    int icon_num;            // Icon number in icon map
};
```

**Pattern Flags:**
- `SUNVOX_PATTERN_FLAG_NO_ICON`: Don't show icon
- `SUNVOX_PATTERN_FLAG_NO_NOTES_OFF`: Seamless looping (Rehorsed mod)

**Data Layout:**
- `data` is a flat array: `data[line * data_xsize + track]`
- `data_xsize` may be larger than `channels` (over-allocation)
- `data_ysize` may be larger than `lines` (over-allocation)

### 5.3 sunvox_pattern_info

**Definition:** `lib_sunvox/sunvox_engine.h`

Metadata and playback state for each pattern.

```c
struct sunvox_pattern_info {
    uint32_t flags;              // Info flags (clone, selected, mute, solo)
    int parent_num;              // Parent pattern (if clone)
    int x, y;                    // Timeline position
    int start_x, start_y;        // Drag start position (UI)
    int state_ptr;               // Index into pat_state array
    sv_pat_track_bits track_status; // Active tracks bitmask
};
```

**Info Flags:**
- `SUNVOX_PATTERN_INFO_FLAG_CLONE`: This is a clone of another pattern
- `SUNVOX_PATTERN_INFO_FLAG_SELECTED`: Selected in UI
- `SUNVOX_PATTERN_INFO_FLAG_MUTE`: Muted
- `SUNVOX_PATTERN_INFO_FLAG_SOLO`: Solo mode

**Position:**
- `x`: Horizontal position on timeline (line number)
- `y`: Vertical position (supertrack number / 32)

### 5.4 sunvox_note (Event)

**Definition:** `lib_sunvox/sunvox_engine.h`

A single musical event (note, controller change, effect).

```c
struct sunvox_note {
    uint8_t note;        // NN: 0=empty, 1-127=note+1, 128=note off, 129+=commands
    uint8_t vel;         // VV: Velocity 1-129, 0=default
    uint16_t mod;        // MM: 0=empty, 1-65535=module number+1
    uint16_t ctl;        // 0xCCEE: CC=controller+1, EE=effect
    uint16_t ctl_val;    // 0xXXYY: Controller value or effect parameter
};
```

**Fields:**

1. **note**: Note number or command
   - 0: Empty
   - 1-127: MIDI note number + 1 (1 = C0)
   - 128: Note off
   - 129: All notes off
   - 130: Clean synths
   - 131: Stop
   - 132: Play
   - 133: Set pitch

2. **vel**: Velocity
   - 0: Use default velocity
   - 1-129: Velocity value

3. **mod**: Target module
   - 0: No module specified
   - 1-65535: Module number + 1

4. **ctl**: Controller/Effect
   - Upper byte (CC): Controller number + 1 (1-127)
   - Lower byte (EE): Effect number

5. **ctl_val**: Value
   - 0xXXYY format
   - Interpretation depends on controller/effect

### 5.5 psynth_net

**Definition:** `lib_sunvox/psynth/psynth_net.h`

The module network (audio graph).

```c
struct psynth_net {
    psynth_module** mods;        // Module array
    uint mods_num;               // Number of module slots
    
    int base_host_version;       // SunVox version
    
    smutex mutex;                // Thread synchronization
    
    // Audio buffers
    PS_STYPE** output_buffers;   // Output audio buffers
    PS_STYPE** input_buffers;    // Input audio buffers
    int output_channels;         // Output channel count
    
    // Rendering
    int render_counter;          // Frame counter
    
    // MIDI
    psynth_midi_port* midi_in_ports;  // MIDI input ports
    int midi_in_ports_num;
    
    // Global state
    int bpm;                     // Beats per minute
    int speed;                   // Ticks per line
    int global_volume;           // Master volume
    
    // ...more fields...
};
```

**Key Concepts:**
- `mods`: Array of all modules (can have NULL entries)
- Modules are numbered 0, 1, 2, ... (0 is typically "Output")
- Each module has input/output connections

### 5.6 psynth_module

**Definition:** `lib_sunvox/psynth/psynth.h`

A single module (synth, effect, or controller).

```c
struct psynth_module {
    PS_RETTYPE (*handler)(PSYNTH_MODULE_HANDLER_PARAMETERS); // Module function
    
    uint32_t flags;              // Module flags (exists, generator, effect, etc.)
    uint32_t flags2;             // Additional flags
    
    char* name;                  // Module name
    int x, y, z;                 // Position in module graph
    int scale;                   // Scale (for UI)
    uint32_t color;              // Color (for UI)
    
    int finetune;                // Finetune value
    int relative_note;           // Relative note
    
    int* input_links;            // Input connections
    uint input_links_num;        // Number of inputs
    int* output_links;           // Output connections
    uint output_links_num;       // Number of outputs
    
    void* data_ptr;              // Module-specific data
    uint data_size;              // Size of module data
    
    psynth_ctl* ctls;            // Controller array
    int ctls_num;                // Number of controllers
    
    int finetune;                // Pitch adjustment
    int relative_note;           // Note transposition
    
    // Runtime state
    int draw_request;            // GUI redraw needed
    int full_redraw_request;     // Full GUI redraw
    
    // ...more fields...
};
```

**Module Types (via flags):**
- `SV_MODULE_FLAG_EXISTS`: Module slot is occupied
- `SV_MODULE_FLAG_GENERATOR`: Generates sound (has note input)
- `SV_MODULE_FLAG_EFFECT`: Processes sound (has audio input/output)
- `SV_MODULE_FLAG_MUTE`: Muted
- `SV_MODULE_FLAG_SOLO`: Solo mode
- `SV_MODULE_FLAG_BYPASS`: Bypassed

### 5.7 psynth_event

**Definition:** `lib_sunvox/psynth/psynth.h`

An event sent to a module.

```c
struct psynth_event {
    uint16_t command;            // PS_CMD_*
    uint id;                     // Event ID (for note off matching)
    uint offset;                 // Sample offset within buffer
    
    union {
        psynth_event_note note;      // Note data
        psynth_event_ctl ctl;        // Controller data
    };
};

struct psynth_event_note {
    uint8_t pitch;               // MIDI pitch (0-127)
    uint8_t velocity;            // Velocity (1-256)
};

struct psynth_event_ctl {
    uint16_t ctl_num;            // Controller number
    int32_t ctl_val;             // Controller value
};
```

**Event Commands:**
- `PS_CMD_NOTE_ON`: Start a note
- `PS_CMD_NOTE_OFF`: Stop a note
- `PS_CMD_SET_VELOCITY`: Change velocity
- `PS_CMD_SET_FREQ`: Set frequency
- `PS_CMD_CLEAN`: Clean/reset module
- `PS_CMD_SET_GLOBAL_CONTROLLER`: Global parameter change
- `PS_CMD_SET_LOCAL_CONTROLLER`: Module-specific parameter change

### 5.8 sunvox_pattern_state

**Definition:** `lib_sunvox/sunvox_engine.h`

Runtime state of a pattern during playback (tracks effects, note states).

```c
struct sunvox_pattern_state {
    sunvox_track_eff effects[MAX_PATTERN_TRACKS]; // Per-track effects
    sv_pat_track_bits track_status;  // Active tracks bitmask
    int16_t track_module[MAX_PATTERN_TRACKS]; // Module for each track
    bool busy;                       // State is in use
    uint8_t mutable_tracks;          // Number of mutable tracks
};

struct sunvox_track_eff {
    int evt_pitch0;              // Original pitch
    int evt_pitch;               // Current pitch
    int cur_pitch;               // Pitch after effects
    int target_pitch;            // Portamento target
    uint16_t porta_speed;        // Portamento speed
    uint16_t flags;              // Effect flags
    int16_t cur_vel;             // Current velocity
    int16_t vel_speed;           // Velocity slide speed
    uint16_t arpeggio;           // Arpeggio pattern
    uint8_t vib_amp;             // Vibrato amplitude
    uint8_t vib_freq;            // Vibrato frequency
    int vib_phase;               // Vibrato phase
    uint8_t timer;               // Effect timer
    uint8_t timer_init;          // Initial timer value
};
```

**Purpose:**
- Tracks which notes are currently playing
- Stores effect state (portamento, vibrato, arpeggio)
- Allows per-track effect memory

---

## Chapter 6: Data Flow and Audio Pipeline

### 6.1 Overall Data Flow

```
User Input (UI Thread)
    ↓
sv_* API calls (e.g., sv_play, sv_send_event)
    ↓
User Command Buffer (ring buffer)
    ↓
Audio Callback (Audio Thread)
    ↓
┌─────────────────────────────────────┐
│  Timeline Processing                │
│  • Advance line_counter             │
│  • Read pattern events at current   │
│    position from active patterns    │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│  Event Distribution                 │
│  • Process pattern events           │
│  • Convert to psynth_events         │
│  • Send to target modules           │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│  Module Processing                  │
│  • Each module handles events       │
│  • Modules render audio             │
│  • Audio is written to buffers      │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│  Mixing & Output                    │
│  • Module outputs are mixed         │
│  • Global volume applied            │
│  • Final audio sent to output       │
└─────────────────────────────────────┘
    ↓
Audio Hardware / Application
```

### 6.2 Audio Callback Flow

**Function:** `sunvox_render_piece_of_sound()` in `sunvox_engine_audio_callback.cpp`

**Steps:**

1. **Handle User Commands**
   - Process commands from user_commands ring buffer
   - Play, Stop, BPM change, controller changes, etc.

2. **Timeline Advancement**
   - Increment `tick_counter` by number of frames
   - When tick_counter crosses tick boundary:
     - Process next tick
     - When tick reaches TPL (ticks per line):
       - Advance `line_counter`
       - Process next line

3. **Pattern Selection**
   - `sunvox_select_current_playing_patterns()`:
     - Find all patterns that intersect current line
     - Up to 64 patterns can be active simultaneously
     - Store active patterns in `cur_playing_pats`

4. **Event Reading**
   - For each active pattern:
     - Calculate local line within pattern
     - If on first tick of line:
       - Read events from pattern at current line
       - For each track with an event:
         - Process the event

5. **Event Processing**
   - Convert sunvox_note to psynth_event
   - Handle effects (arpeggio, portamento, vibrato, etc.)
   - Update pattern_state

6. **Event Sending**
   - Send psynth_events to target modules
   - Events are queued in module's event buffer

7. **Audio Rendering**
   - For each frame in the audio callback buffer:
     - For each module in dependency order:
       - Call module's handler with PS_CMD_RENDER
       - Module processes queued events
       - Module generates audio samples
       - Module writes to its output buffers
     - Mix module outputs according to connections
     - Apply global volume
     - Write to output buffer

8. **Cleanup**
   - Update visualization data
   - Handle pattern boundaries (loop, advance to next pattern)

### 6.3 Module Rendering Order

Modules must be rendered in **dependency order** (topological sort):

- Modules with no inputs are rendered first
- Modules are rendered only after all their input modules

**Example:**
```
Generator → Filter → Reverb → Output
```

**Rendering Order:**
1. Generator (no inputs)
2. Filter (depends on Generator)
3. Reverb (depends on Filter)
4. Output (depends on Reverb)

**Implementation:**
- PSynth network maintains a sorted list of modules
- Each module has a `rendering_order` field

### 6.4 Event Timing

**Tick-Based Timing:**

- 1 line = TPL ticks (Ticks Per Line, typically 6)
- 1 tick = (sample_rate / bpm) * (60.0 / 24.0) frames
- Example at 120 BPM, 44100 Hz:
  - 1 tick = 44100 / 120 * 60 / 24 = 920 frames
  - 1 line = 6 ticks = 5520 frames ≈ 125 ms

**Sub-Tick Precision:**

- Events have an `offset` field (sample offset within buffer)
- Allows sample-accurate event timing
- Important for tight synchronization

---

## Chapter 7: Module System (PSynth)

### 7.1 PSynth Overview

**PSynth** (PixiSynth) is the modular synthesis framework that powers SunVox.

**Key Features:**
- Modular architecture: each module is independent
- Signal routing: modules can be connected in any configuration
- Real-time processing: designed for low-latency audio
- Extensible: new modules can be added

### 7.2 Module Handler Function

Each module implements a **handler function** with this signature:

```c
PS_RETTYPE psynth_module_handler(
    PSYNTH_MODULE_HANDLER_PARAMETERS
);
```

**Expanded:**
```c
PS_RETTYPE module_handler(
    psynth_event* event,           // Event to handle (or NULL for rendering)
    psynth_module* mod,            // The module itself
    psynth_net* pnet               // The PSynth network
);
```

**Commands:**

1. **PS_CMD_NOTE_ON**: Start playing a note
2. **PS_CMD_NOTE_OFF**: Stop playing a note
3. **PS_CMD_SET_FREQ**: Change frequency
4. **PS_CMD_SET_VELOCITY**: Change velocity
5. **PS_CMD_SET_GLOBAL_CONTROLLER**: Set global parameter
6. **PS_CMD_SET_LOCAL_CONTROLLER**: Set module parameter
7. **PS_CMD_CLEAN**: Clean/reset module state
8. **PS_CMD_RENDER_REPLACE**: Render audio (replace buffer)
9. **PS_CMD_INIT**: Initialize module
10. **PS_CMD_CLOSE**: Clean up module
11. **PS_CMD_SET_SAMPLE_RATE**: Notify of sample rate change
12. **PS_CMD_SPEED_CHANGED**: Notify of BPM/TPL change

### 7.3 Module Categories

#### 7.3.1 Generators (Sound Sources)

**Generator Module** (`psynths_generator.cpp`)
- Simple waveform generator (sine, saw, square, noise)
- Supports drawing custom waveforms

**Generator 2** (`psynths_generator2.cpp`)
- Advanced generator with more waveforms
- Multiple wave shaping options

**FM Synthesizer** (`psynths_fm.cpp`, `psynths_fm2.cpp`)
- Frequency modulation synthesis
- Multiple operators with configurable algorithms

**DrumSynth** (`psynths_drumsynth.cpp`)
- Drum sound synthesizer
- Kick, snare, hihat presets

**Kicker** (`psynths_kicker.cpp`)
- Bass drum synthesizer
- Optimized for kick drum sounds

**Sampler** (`psynths_sampler.cpp`)
- Plays audio samples
- Multi-sample support with velocity/note mapping
- Loop modes, envelopes

**SpectraVoice** (`psynths_spectravoice.cpp`)
- Spectral synthesis
- Harmonic controls

**Vorbis Player** (`psynths_vorbis_player.cpp`)
- Plays Ogg Vorbis files directly

**MultiSynth** (`psynths_multisynth.cpp`)
- Polyphonic synthesizer with multiple oscillators
- Built-in effects

**Input** (`psynths_input.cpp`)
- Audio input from microphone/line-in

#### 7.3.2 Effects (Sound Processors)

**Amplifier** (`psynths_amplifier.cpp`)
- Volume control with panning

**Compressor** (`psynths_compressor.cpp`)
- Dynamic range compression

**DC Blocker** (`psynths_dc_blocker.cpp`)
- Remove DC offset

**Delay** (`psynths_delay.cpp`)
- Multi-tap delay with feedback

**Distortion** (`psynths_distortion.cpp`)
- Overdrive, distortion, bit crushing

**Echo** (`psynths_echo.cpp`)
- Stereo echo with filtering

**EQ** (`psynths_eq.cpp`)
- Multi-band equalizer

**Filter** (`psynths_filter.cpp`, `psynths_filter2.cpp`)
- Resonant filters (LP, HP, BP, Notch)

**Vocal Filter** (`psynths_vocal_filter.cpp`)
- Formant filter for vocal effects

**Flanger** (`psynths_flanger.cpp`)
- Flanging effect

**Reverb** (`psynths_reverb.cpp`)
- Reverb with room size control

**Pitch Shifter** (`psynths_pitch_shifter.cpp`)
- Real-time pitch shifting

**WaveShaper** (`psynths_waveshaper.cpp`)
- Waveshaping with custom curves

**Vibrato** (`psynths_vibrato.cpp`)
- Pitch vibrato effect

**Loop** (`psynths_loop.cpp`)
- Sample-accurate looper

**FFT** (`psynths_fft.cpp`)
- FFT analysis and processing

#### 7.3.3 Controllers (Modulators)

**LFO** (`psynths_lfo.cpp`)
- Low frequency oscillator
- Modulates other module parameters

**ADSR** (`psynths_adsr.cpp`)
- Envelope generator (Attack, Decay, Sustain, Release)

**Glide** (`psynths_glide.cpp`)
- Portamento (pitch glide)

**Modulator** (`psynths_modulator.cpp`)
- Ring modulation

**Smooth** (`psynths_smooth.cpp`)
- Parameter smoothing/interpolation

**MultiCtl** (`psynths_multictl.cpp`)
- Multi-controller with response curve

**Ctl2Note** (`psynths_ctl2note.cpp`)
- Convert controller values to notes

**Pitch2Ctl** (`psynths_pitch2ctl.cpp`)
- Convert pitch to controller value

**Sound2Ctl** (`psynths_sound2ctl.cpp`)
- Convert audio level to controller value (envelope follower)

**Velocity2Ctl** (`psynths_velocity2ctl.cpp`)
- Convert note velocity to controller

**Pitch Detector** (`psynths_pitch_detector.cpp`)
- Detect pitch from audio input

**Feedback** (`psynths_feedback.cpp`)
- Feedback routing

**GPIO** (`psynths_gpio.cpp`)
- Hardware GPIO control

#### 7.3.4 Special Modules

**MetaModule** (`psynths_metamodule.cpp`)
- Embeds an entire SunVox project as a module
- Allows nested projects

**Output** (special, always module 0)
- Final output destination
- Stereo mix

### 7.4 Module Data Storage

Each module can have **module-specific data**:

```c
struct psynth_module {
    void* data_ptr;          // Pointer to module data
    uint data_size;          // Size of data
};
```

**Example (from psynths_generator.cpp):**
```c
struct generator_data {
    int waveform;            // Selected waveform
    int volume;              // Volume level
    int phase;               // Oscillator phase
    int freq;                // Frequency
    // ...more fields...
};
```

**Lifecycle:**
1. **PS_CMD_INIT**: Allocate `data_ptr`, initialize
2. **PS_CMD_RENDER**: Use `data_ptr` for processing
3. **PS_CMD_CLOSE**: Free `data_ptr`

### 7.5 Module Controllers

Each module has **controllers** (parameters):

```c
struct psynth_ctl {
    char* name;              // Controller name
    int type;                // Controller type (0=slider, 1=enum)
    int min, max;            // Value range
    int val;                 // Current value
    int show_offset;         // Display offset
    // ...
};
```

**Example Controllers:**
- Volume: 0-256 (256 = 100%)
- Frequency: 0-44100 (Hz)
- Filter Cutoff: 0-16384
- Waveform: 0-7 (enum: sine, saw, square, etc.)

**Accessing Controllers:**
```c
// From API
sv_set_module_ctl_value(slot, mod_num, ctl_num, value, scaled);
int value = sv_get_module_ctl_value(slot, mod_num, ctl_num, scaled);

// From pattern events
// ctl field in sunvox_note: (ctl_num+1) << 8 | effect
```

Important integration note for host code: controller indices are module-specific and defined by each module's `psynth_register_ctl(...)` order in source (for example `psynths_reverb.cpp`). Do not assume a shared semantic layout across modules, and keep wrapper constants synchronized with the module's registration order.

### 7.6 Module Connections

Modules are connected via **links**:

```c
struct psynth_module {
    int* input_links;        // Array of input module numbers
    uint input_links_num;    // Number of inputs
    int* output_links;       // Array of output module numbers
    uint output_links_num;   // Number of outputs
};
```

**Connection Rules:**
- Generators: typically no inputs, one or more outputs
- Effects: one or more inputs, one or more outputs
- Controllers: outputs only (modulate other modules)
- Output: inputs only (final destination)

**Creating Connections:**
```c
sv_connect_module(slot, source_mod, dest_mod);
```

**Audio Mixing:**
- When a module has multiple inputs, they are **summed** (mixed)
- When a module has multiple outputs, the same audio is sent to all

---

## Chapter 8: Pattern System and Sequencing

### 8.1 Pattern Structure

**Pattern = 2D Grid:**
- **Vertical (Lines)**: Time progression (like rows in a spreadsheet)
- **Horizontal (Tracks)**: Independent voices/channels

**Example Pattern:**
```
Line | Track 0     | Track 1     | Track 2     | Track 3
-----|-------------|-------------|-------------|-------------
  0  | C5 80 01 .. | .. .. .. .. | E5 64 02 .. | .. .. .. ..
  1  | .. .. .. .. | G5 70 01 .. | .. .. .. .. | .. .. .. ..
  2  | D5 80 01 .. | .. .. .. .. | F5 64 02 .. | .. .. .. ..
  3  | .. .. .. .. | A5 70 01 .. | .. .. .. .. | .. .. .. ..
```

**Reading:**
- Line 0, Track 0: Note C5, velocity 80, module 1
- Line 0, Track 2: Note E5, velocity 64, module 2
- Line 1, Track 1: Note G5, velocity 70, module 1

### 8.2 Pattern Timeline

**Timeline Arrangement:**

Patterns are placed on a horizontal timeline at specific **X positions** (line numbers):

```
Timeline:
|-----|-----|-----|-----|-----|-----|-----|-----|-----|
0    16    32    48    64    80    96   112   128   144

Pattern 0: x=0,  lines=16  [0  - 15 ]
Pattern 1: x=16, lines=32  [16 - 47 ]
Pattern 2: x=48, lines=16  [48 - 63 ]
Pattern 3: x=64, lines=32  [64 - 95 ]
```

**Playback:**
- `line_counter` advances: 0, 1, 2, 3, ...
- Patterns are activated when `line_counter` is within their range
- Multiple patterns can be active simultaneously (vertical stacking)

### 8.3 Supertracks (SunVox 2.0+)

**Supertracks** are a fundamental feature introduced in SunVox 2.0 that revolutionizes how patterns are organized and played back.

#### 8.3.1 What Are Supertracks?

Supertracks allow **vertical layering** of patterns on the timeline, enabling multiple patterns to play simultaneously at the same horizontal position.

**Key Concept:** Think of supertracks as "lanes" or "layers" on the timeline:

```
Timeline (vertical view):
╔═══════════════════════════════════════════════════════════╗
║ Supertrack 0: [Pattern A: Drums    ]──────────────────── ║ y=0
║ Supertrack 1: [Pattern B: Bass     ]──────────────────── ║ y=1
║ Supertrack 2: [Pattern C: Lead     ]──────────────────── ║ y=2
║ Supertrack 3: [Pattern D: Pads     ]──────────────────── ║ y=3
╚═══════════════════════════════════════════════════════════╝
             x=0                    x=16              x=32
```

All four patterns start at x=0 and play **simultaneously**, but on different vertical layers.

#### 8.3.2 Classic Mode vs. Supertracks Mode

**Without Supertracks (Classic Mode):**
```
Timeline:
[Pattern A]────[Pattern B]────[Pattern C]────
x=0           x=16          x=32

Only ONE pattern per X position!
```

- Only one pattern can occupy any given X position
- Patterns are arranged horizontally in sequence
- Simpler mental model, but less flexible
- Used in SunVox versions before 2.0

**With Supertracks (Modern Mode):**
```
Timeline (3D view):
       y=0: [Pattern A]────[Pattern D]────
       y=1: [Pattern B]────[Pattern E]────
       y=2: [Pattern C]────[Pattern F]────
            x=0           x=16          x=32

Multiple patterns per X position! (on different Y layers)
```

- Up to 64 patterns can play simultaneously (MAX_PLAYING_PATS = 64)
- Patterns are arranged in a 2D grid (X = time, Y = layer/supertrack)
- More complex but vastly more powerful
- Essential for modern SunVox features

#### 8.3.3 Technical Implementation

**Engine Flag:**
```c
#define SUNVOX_FLAG_SUPERTRACKS  (1 << 15)

// In sunvox_engine struct:
uint32_t flags;  // Contains SUNVOX_FLAG_SUPERTRACKS when enabled
```

**Pattern Position:**
```c
struct sunvox_pattern_info {
    int x;  // Horizontal position (line number on timeline)
    int y;  // Vertical position (supertrack number / 32)
    // ...
};
```

**Pattern State Allocation:**

In supertracks mode, the engine maintains up to 64 `sunvox_pattern_state` structures:

```c
struct sunvox_engine {
    sunvox_pattern_state* pat_state;    // Array of state structures
    int pat_state_size;                 // Capacity (64 in supertracks mode)
    int cur_playing_pats[64];           // Currently active pattern indices
    // ...
};
```

Each active pattern gets its own state slot to track:
- Active notes per track (`track_status` bitmask)
- Effect state (vibrato, portamento, etc.)
- Target modules per track

**Enabling:**
```c
sv_enable_supertracks(slot, 1);
```

**Supertrack Muting:**

Supertracks mode enables per-supertrack muting:

```c
struct sunvox_engine {
    uint32_t supertrack_mute[SUPERTRACK_BITARRAY_SIZE];  // Bitmask
    // ...
};
```

**Multi-Layer Composition Example:**

```cpp
// Create a full arrangement with simultaneous patterns
sv_enable_supertracks(slot, 1);

// Layer 0: Drums (loops every 16 lines)
int drums = sv_new_pattern(slot, -1, 0, 0, 4, 16, 0, "Drums");

// Layer 1: Bass (loops every 16 lines)
int bass = sv_new_pattern(slot, -1, 0, 1, 2, 16, 0, "Bass");

// Layer 2: Chords (loops every 32 lines)  
int chords = sv_new_pattern(slot, -1, 0, 2, 8, 32, 0, "Chords");

// Layer 3: Lead (starts at line 32)
int lead = sv_new_pattern(slot, -1, 32, 3, 4, 16, 0, "Lead");

// Result: Drums, bass, and chords play from start
//         Lead joins in at line 32
//         All play simultaneously on different layers
```

**Key Benefits:**

- Independent pattern state management
- Per-pattern behavior control via flags
- Advanced timeline arrangements
- Better scalability for complex projects

> **Note:** For Rehorsed-specific usage of supertracks, see `sunvox_rehorsed_tweaks.md`

### 8.4 Pattern Clones

**Clone** = Instance of a pattern that shares the same data.

**Purpose:**
- Repeat a pattern multiple times without duplicating data
- Save memory

**Creating Clones:**
```c
int clone_pat = sv_new_pattern(slot, parent_pat, x, y, tracks, lines, 0, NULL);
```

**Characteristics:**
- Clone and parent share the same `sunvox_note* data` pointer
- Editing clone edits parent (and vice versa)
- Clones can be **detached** to become independent

**Detaching:**
```c
sunvox_detach_clone(pat_num, s);
```

### 8.5 Pattern Playback State

During playback, each active pattern has a `sunvox_pattern_state`:

**Purpose:**
- Track which notes are currently playing
- Store effect state (portamento, vibrato, etc.)

**Allocation:**
- `pat_state` array in `sunvox_engine`
- Size = maximum number of simultaneously playing patterns
- Patterns share state slots dynamically

**State Fields:**
- `busy`: Is this state in use?
- `track_status`: Bitmask of active tracks (1 = note on)
- `track_module[track]`: Which module is playing on this track
- `effects[track]`: Per-track effect state

### 8.6 Pattern Events and Effects

**Event Types:**

1. **Note Events**
   - Note On: Start a note
   - Note Off: Stop a note

2. **Module Selection**
   - `mod` field: Target module for the note

3. **Effects**
   - Encoded in `ctl` and `ctl_val` fields
   - Examples:
     - 01: Arpeggio
     - 02: Pitch up
     - 03: Pitch down
     - 04: Tone portamento
     - 05: Vibrato
     - 06: Volume slide
     - 07: Tremolo
     - 08: Set panning
     - 09: Set sample offset
     - 0C: Set volume
     - 0F: Set speed
     - ... many more

**Effect Processing:**
- Some effects are **instant** (executed once)
- Some effects are **continuous** (executed every tick)

### 8.7 Pattern Loop Modes

**Normal Timeline Mode:**
- Play through all patterns from start to end
- Controlled by `single_pattern_play = -1`
- When autostop is enabled, stops at end
- When autostop is disabled, loops from beginning

**Single Pattern Loop Mode:**
- Loop a specific pattern indefinitely
- Controlled by `single_pattern_play = pattern_num`
- Only the specified pattern plays, rest of timeline ignored
- Useful for live looping, pattern editing, rehearsal

**Autostop Control:**
```c
// Loop entire project
sv_set_autostop(slot, 0);  // 0 = loop forever

// Stop at end of project
sv_set_autostop(slot, 1);  // 1 = stop at end
```

> **Note:** Rehorsed has added extended pattern loop features including loop counting and automatic pattern advancement. See `sunvox_rehorsed_tweaks.md` for details.

---

## Chapter 9: Audio Callback and Real-Time Processing

### 9.1 Audio Callback Entry Point

**Function:** `sunvox_render_piece_of_sound()`  
**Location:** `lib_sunvox/sunvox_engine_audio_callback.cpp`

**Called By:**
- Platform audio thread (iOS, Android, macOS, etc.)
- OR user application (in offline mode with `SV_INIT_FLAG_USER_AUDIO_CALLBACK`)

**Signature:**
```c
bool sunvox_render_piece_of_sound(
    sunvox_render_data* rdata,
    sunvox_engine* s
);
```

**Parameters:**
- `rdata->buffer`: Output buffer to fill
- `rdata->frames`: Number of frames to render
- `rdata->channels`: Number of channels (typically 2 for stereo)
- `rdata->out_time`: Output timestamp

**Return:**
- `true`: Audio was rendered
- `false`: Silence (no audio)

### 9.2 Main Processing Loop

**Outer Loop:** Iterate through requested frames

```c
for (int frame = 0; frame < rdata->frames; frame++) {
    // 1. Handle user commands
    // 2. Advance timeline
    // 3. Process events
    // 4. Render modules
    // 5. Mix and output
}
```

### 9.3 Timeline Processing

**Step 1: Tick Counter Advancement**

```c
s->tick_counter += (256 << 8);  // Fixed-point increment
```

**Step 2: Check Tick Boundary**

```c
if (s->tick_counter >= s->tick_size << 8) {
    s->tick_counter -= s->tick_size << 8;
    // Process tick
}
```

**Step 3: Line Advancement**

```c
s->speed_counter++;
if (s->speed_counter >= s->speed) {  // speed = TPL
    s->speed_counter = 0;
    s->line_counter++;
    // Process new line
}
```

### 9.4 Pattern Event Processing

**Step 1: Select Active Patterns**

```c
sunvox_select_current_playing_patterns(first_sorted_pat, s);
```

- Finds all patterns that overlap `line_counter`
- Stores in `s->cur_playing_pats[]`

**Step 2: Read Events from Active Patterns**

For each active pattern:

```c
sunvox_pattern* pat = s->pats[pat_num];
int local_line = s->line_counter - s->pats_info[pat_num].x;

if (local_line >= 0 && local_line < pat->lines) {
    for (int track = 0; track < pat->channels; track++) {
        sunvox_note* evt = &pat->data[local_line * pat->data_xsize + track];
        if (evt->note != 0 || evt->vel != 0 || ...) {
            // Process event
        }
    }
}
```

**Step 3: Convert to PSynth Events**

```c
psynth_event module_evt;
module_evt.command = PS_CMD_NOTE_ON;
module_evt.note.pitch = evt->note - 1;  // Convert to MIDI pitch
module_evt.note.velocity = evt->vel ? evt->vel : default_vel;
module_evt.id = (state_ptr << 16) | track;  // Unique ID for note off
module_evt.offset = frame;  // Sample-accurate timing

psynth_add_event(mod_num, &module_evt, s->net);
```

### 9.5 Module Rendering

**PSynth Rendering:** `psynth_render()`  
**Location:** `lib_sunvox/psynth/psynth_net.cpp`

**Process:**

1. **For each module in rendering order:**

```c
for (int i = 0; i < pnet->mods_num; i++) {
    psynth_module* mod = pnet->mods[i];
    if (!mod || !(mod->flags & SV_MODULE_FLAG_EXISTS))
        continue;
    
    // Render this module
    psynth_render_module(mod, offset, frames, pnet);
}
```

2. **Render Individual Module:**

```c
// Mix inputs
psynth_mix_inputs(mod, pnet);

// Handle events
while (event = get_next_event(mod)) {
    mod->handler(event, mod, pnet);
}

// Render audio
psynth_event render_evt;
render_evt.command = PS_CMD_RENDER_REPLACE;
render_evt.offset = offset;
mod->handler(&render_evt, mod, pnet);

// Send output to connected modules
psynth_send_output(mod, pnet);
```

### 9.6 Audio Mixing

**Input Mixing:**

When a module has multiple inputs:

```c
// For each input link
for (int i = 0; i < mod->input_links_num; i++) {
    int input_mod = mod->input_links[i];
    // Sum input audio
    for (int ch = 0; ch < channels; ch++) {
        for (int frame = 0; frame < frames; frame++) {
            mod->input_buffers[ch][frame] += 
                pnet->mods[input_mod]->output_buffers[ch][frame];
        }
    }
}
```

**Output Mixing:**

Output module (module 0) receives audio from all connected modules:

```c
// Output module collects final mix
for (int frame = 0; frame < frames; frame++) {
    float left = output_mod->input_buffers[0][frame];
    float right = output_mod->input_buffers[1][frame];
    
    // Apply global volume
    left *= s->net->global_volume / 256.0f;
    right *= s->net->global_volume / 256.0f;
    
    // Write to output buffer
    rdata->buffer[frame * 2 + 0] = left;
    rdata->buffer[frame * 2 + 1] = right;
}
```

### 9.7 Thread Safety

**Two Threads:**

1. **Audio Thread** (high priority, real-time)
   - Runs `sunvox_render_piece_of_sound()`
   - Must not block or allocate memory

2. **UI Thread** (normal priority)
   - Calls API functions (`sv_*`)
   - Can allocate, block, etc.

**Synchronization:**

```c
// UI Thread
sv_lock_slot(slot);
sv_set_pattern_size(slot, pat_num, new_tracks, new_lines);
sv_unlock_slot(slot);
```

**Internally:**
- `sv_lock_slot()` acquires `pnet->mutex`
- Audio thread also acquires this mutex during rendering
- Prevents data races

**User Command Buffer:**

- UI thread writes commands to `s->user_commands` ring buffer
- Audio thread reads and processes commands
- Lock-free ring buffer for low latency

---

## Chapter 10: File I/O and Project Management

### 10.1 SunVox File Format

**File Extension:** `.sunvox`

**Structure:**

```
┌─────────────────────┐
│ File Header         │
│ "SVOX"              │
└─────────────────────┘
│ Version Block       │
│ (VERS)              │
└─────────────────────┘
│ Project Metadata    │
│ (BPM, SPED, NAME)   │
└─────────────────────┘
│ Patterns            │
│ (PATN ... PEND)     │
│ ...                 │
└─────────────────────┘
│ Modules             │
│ (SNAM, STYP, ...)   │
│ (SEND)              │
│ ...                 │
└─────────────────────┘
│ Connections         │
│ (SLNK)              │
└─────────────────────┘
│ End of File         │
└─────────────────────┘
```

**Block Format:**

Each block has:
- **4-byte ID** (ASCII, e.g., "BPM ", "PATN")
- **4-byte size** (little-endian)
- **Data** (size bytes)

### 10.2 Block Types

**Global Blocks:**

- `BVER`: Base version (SunVox version when project was created)
- `VERS`: Current version
- `SFGS`: Flags (supertracks, etc.)
- `BPM `: Beats per minute
- `SPED`: Speed (ticks per line)
- `TGRD`, `TGD2`: Grid settings
- `NAME`: Project name
- `GVOL`: Global volume
- `MSCL`, `MZOO`, `MXOF`, `MYOF`: Module view settings
- `LMSK`: Layer mask
- `CURL`: Current layer
- `TIME`: Restart position
- `REPS`: Restart position (alternate)
- `SELS`: Selected module

**Pattern Blocks:**

- `PATN`: Pattern number
- `PATT`: Pattern tracks
- `PATL`: Pattern lines
- `PDTA`: Pattern data (events)
- `PNME`: Pattern name
- `PCHN`: Pattern channels
- `PLIN`: Pattern lines (alternate)
- `PYSZ`: Pattern Y size
- `PICO`: Pattern icon
- `PFLG`: Pattern flags
- `PXXX`, `PYYY`: Pattern position
- `PFGC`, `PBGC`: Pattern colors
- `PEND`: Pattern end marker

**Module Blocks:**

- `SFFF`: Module flags
- `SNAM`: Module name
- `STYP`: Module type
- `SFIN`: Module finetune
- `SREL`: Module relative note
- `SXXX`, `SYYY`, `SZZZ`: Module position
- `SSCL`: Module scale
- `SCOL`: Module color
- `SMII`: MIDI input flags
- `SLNK`, `SLnK`, `SLnk`: Module connections (various formats)
- `CVAL`: Controller value
- `CMID`: Controller MIDI
- `CHNK`, `CHNM`, `CHDT`, `CHFF`, `CHFR`: Module chunks (module-specific data)
- `SEND`: Module end marker

### 10.3 Loading a Project

**API:**
```c
int sv_load(int slot, const char* name);
int sv_load_from_memory(int slot, void* data, uint32_t data_size);
```

**Implementation:** `sunvox_load_proj_from_fd()` in `sunvox_engine_load_proj.cpp`

**Process:**

1. **Open File**
   ```c
   sfs_file f = sfs_open(name, "rb");
   ```

2. **Check Signature**
   ```c
   uint8_t sign[4];
   sfs_read(sign, 1, 4, f);
   if (memcmp(sign, "SVOX", 4) != 0) return -1;  // Not a SunVox file
   ```

3. **Create Load State**
   ```c
   sunvox_load_state* state = sunvox_new_load_state(s, f);
   ```

4. **Load Blocks in Loop**
   ```c
   while (load_block(state) == 0) {
       // Process block based on block_id
       switch (state->block_id) {
           case BID_BVER:
               s->base_version = state->block_data_int;
               break;
           case BID_BPM:
               s->bpm = state->block_data_int;
               break;
           case BID_PATN:
               current_pat = state->block_data_int;
               break;
           case BID_PDTA:
               // Load pattern data
               sunvox_load_pattern_data(current_pat, state);
               break;
           // ... many more cases
       }
   }
   ```

5. **Post-Processing**
   - Sort patterns
   - Build module connections
   - Initialize visualization

6. **Cleanup**
   ```c
   sunvox_remove_load_state(state);
   sfs_close(f);
   ```

### 10.4 Saving a Project

**API:**
```c
int sv_save(int slot, const char* name);
void* sv_save_to_memory(int slot, size_t* size);
```

**Implementation:** `sunvox_save_proj_to_fd()` in `sunvox_engine_save_proj.cpp`

**Process:**

1. **Open File**
   ```c
   sfs_file f = sfs_open(name, "wb");
   ```

2. **Write Signature**
   ```c
   sfs_write("SVOX", 1, 4, f);
   ```

3. **Create Save State**
   ```c
   sunvox_save_state* state = sunvox_new_save_state(s, f);
   ```

4. **Write Global Blocks**
   ```c
   save_block(BID_BVER, sizeof(uint32_t), &s->base_version, state);
   save_block(BID_BPM, sizeof(uint16_t), &s->bpm, state);
   save_block(BID_SPED, sizeof(uint8_t), &s->speed, state);
   // ...
   ```

5. **Write Patterns**
   ```c
   for (int i = 0; i < s->pats_num; i++) {
       if (!s->pats[i]) continue;
       sunvox_save_pattern(i, state);
   }
   ```

6. **Write Modules**
   ```c
   for (int i = 0; i < s->net->mods_num; i++) {
       if (!s->net->mods[i]) continue;
       sunvox_save_module_to_fd(i, f, 0, s, state);
   }
   ```

7. **Cleanup**
   ```c
   sunvox_remove_save_state(state);
   sfs_close(f);
   ```

### 10.5 Loading Modules

**Module File Formats:**

- `.sunsynth`: SunVox module
- `.xi`: Extended Instrument (FastTracker II)
- `.wav`, `.aiff`: Audio samples (loaded into Sampler)
- `.ogg`, `.mp3`, `.flac`: Compressed audio

**API:**
```c
int sv_load_module(int slot, const char* file_name, int x, int y, int z);
int sv_load_module_from_memory(int slot, void* data, uint32_t data_size, int x, int y, int z);
```

**Process:**

1. **Detect Format**
   ```c
   sfs_file_fmt fmt = sfs_get_file_format(file_name);
   ```

2. **Load Based on Format**
   - `.sunsynth`: Load module structure and data
   - Audio files: Create Sampler module, load sample

3. **Add to Network**
   ```c
   int mod_num = psynth_add_module(mod_type, x, y, z, s->net);
   ```

### 10.6 Export to WAV

**API:**
```c
int sunvox_export_to_wav(
    const char* name,
    sound_buffer_type buf_type,
    sfs_file_fmt file_format,
    int q,
    int mode,
    int mode_par,
    void (*status_handler)(void*, int),
    void* status_data,
    sunvox_engine* s
);
```

**Process:**

1. **Setup**
   - Determine project length
   - Create output file
   - Set rendering mode

2. **Offline Rendering Loop**
   ```c
   while (!finished) {
       sunvox_render_data rdata;
       rdata.buffer = temp_buffer;
       rdata.frames = buffer_size;
       sunvox_render_piece_of_sound(&rdata, s);
       
       // Write to file
       write_audio_samples(file, rdata.buffer, rdata.frames);
       
       // Update progress
       if (status_handler) {
           status_handler(status_data, current_frame * 100 / total_frames);
       }
   }
   ```

3. **Finalize**
   - Close file
   - Restore playback mode

---

## Chapter 11: Integration and API Usage

### 11.1 Basic Integration

**Step 1: Initialize Library**

```c
#include "sunvox.h"

int result = sv_init(
    NULL,           // config (NULL = auto)
    44100,          // sample rate
    2,              // channels (stereo)
    0               // flags
);

if (result != 0) {
    // Error handling
}
```

**Step 2: Open Slot**

```c
int slot = 0;
sv_open_slot(slot);
```

**Step 3: Load Project**

```c
sv_load(slot, "song.sunvox");
```

**Step 4: Start Playback**

```c
sv_play_from_beginning(slot);
```

**Step 5: Audio Callback (Offline Mode)**

If using `SV_INIT_FLAG_USER_AUDIO_CALLBACK`:

```c
void audio_callback(float* buffer, int frames) {
    sv_audio_callback(
        buffer,
        frames,
        0,              // latency
        sv_get_ticks()  // output time
    );
}
```

**Step 6: Cleanup**

```c
sv_stop(slot);
sv_close_slot(slot);
sv_deinit();
```

### 11.2 Creating a Project Programmatically

**Create Modules:**

```c
// Create Generator
int gen_mod = sv_new_module(slot, "Generator", "Gen1", 256, 256, 0);
sv_connect_module(slot, gen_mod, 0);  // Connect to Output

// Create Filter
int flt_mod = sv_new_module(slot, "Filter", "Filter1", 512, 256, 0);
sv_connect_module(slot, gen_mod, flt_mod);  // Gen → Filter
sv_connect_module(slot, flt_mod, 0);        // Filter → Output

// Set module parameters
sv_set_module_ctl_value(slot, gen_mod, 0, 128, 0);  // Volume = 128
sv_set_module_ctl_value(slot, flt_mod, 0, 8192, 0); // Cutoff = 8192
```

**Create Pattern:**

```c
int pat = sv_new_pattern(
    slot,
    -1,     // clone (-1 = new pattern)
    0,      // x position
    0,      // y position
    4,      // tracks
    16,     // lines
    0,      // icon seed (0 = generate)
    "Main"  // name
);
```

**Add Events:**

```c
// Line 0, Track 0: C5, velocity 80, module 1
sv_set_pattern_event(
    slot,
    pat,
    0,      // track
    0,      // line
    60,     // note (C5 = MIDI 60)
    80,     // velocity
    gen_mod + 1,  // module (add 1)
    -1,     // ctl (none)
    -1      // ctl_val (none)
);

// Line 4, Track 0: E5
sv_set_pattern_event(slot, pat, 0, 4, 64, 80, gen_mod + 1, -1, -1);

// Line 8, Track 0: G5
sv_set_pattern_event(slot, pat, 0, 8, 67, 80, gen_mod + 1, -1, -1);
```

**Play:**

```c
sv_play_from_beginning(slot);
```

### 11.3 Real-Time Control

**Send Events:**

```c
// Send Note On
sv_send_event(
    slot,
    0,          // track
    60,         // note (C5)
    80,         // velocity
    gen_mod + 1, // module
    0,          // ctl
    0           // ctl_val
);

// Send Note Off
sv_send_event(slot, 0, 128, 0, gen_mod + 1, 0, 0);
```

**Change Parameters:**

```c
// Set filter cutoff (controller 0)
sv_set_module_ctl_value(slot, flt_mod, 0, 4096, 0);
```

**BPM and Speed:**

```c
// Change BPM
sv_send_event(slot, 0, 132, 0, 0, 0, 140);  // Play command with BPM=140

// Change Speed (TPL)
sv_send_event(slot, 0, 132, 0, 0, 0xF00, 8);  // Effect 0F (speed), value 8
```

### 11.4 Multiple Slots

**Use Case:** Play multiple songs simultaneously

```c
// Initialize
sv_init(NULL, 44100, 2, 0);

// Open slots
sv_open_slot(0);
sv_open_slot(1);

// Load projects
sv_load(0, "background_music.sunvox");
sv_load(1, "sound_effects.sunvox");

// Play both
sv_play(0);
sv_play(1);

// Audio callback mixes both slots automatically
sv_audio_callback(buffer, frames, 0, sv_get_ticks());
```

### 11.5 Custom Extensions and Modifications

The SunVox library can be extended with custom features. The Rehorsed project has added several modifications for seamless pattern looping, loop counting, and automatic pattern advancement.

> **For Rehorsed-specific pattern loop features, see:** `sunvox_rehorsed_tweaks.md`  
> **For source code modifications, see:** `/app/native/sunvox_lib/MODIFICATIONS.md`

### 11.6 Thread Safety Tips

**UI Thread:**

```c
// Always use lock/unlock for modifications
sv_lock_slot(slot);

// Modify pattern
sunvox_note* data = sv_get_pattern_data(slot, pat);
data[line * tracks + track].note = 60;

sv_unlock_slot(slot);
```

**Lock-Free Operations:**

These don't require locking:
- `sv_play()`, `sv_stop()`, `sv_pause()`, `sv_resume()`
- `sv_send_event()`
- `sv_get_current_line()` (reading playback state)
- `sv_get_module_flags()`, `sv_get_pattern_lines()` (reading metadata)

**Lock-Required Operations:**

These require locking:
- `sv_new_pattern()`, `sv_remove_pattern()`
- `sv_new_module()`, `sv_remove_module()`
- `sv_set_pattern_size()`, `sv_set_pattern_xy()`
- `sv_connect_module()`, `sv_disconnect_module()`
- Direct manipulation of pattern data

---

## Chapter 12: Advanced Topics

### 12.1 Library Extensions and Modifications

The SunVox library source code can be modified to add custom features. Applications can extend functionality by:

- Adding new APIs to `sunvox.h`
- Modifying engine behavior in `sunvox_engine_audio_callback.cpp`
- Extending data structures in `sunvox_engine.h`

**Example: Custom Pattern Features**

The Rehorsed project has added several modifications including:
- Seamless pattern looping (NO_NOTES_OFF flag)
- Pattern loop counting with automatic advancement
- Seamless position changes without audio interruption

> **See:** `sunvox_rehorsed_tweaks.md` for complete details on Rehorsed's modifications  
> **See:** `/app/native/sunvox_lib/MODIFICATIONS.md` for technical implementation

### 12.2 Custom Module Development

**Not Officially Supported in Library Version**

To add a custom module:

1. **Create Module File**
   - Example: `psynths_mymodule.cpp`

2. **Implement Handler Function**
   ```c
   PS_RETTYPE psynth_mymodule(PSYNTH_MODULE_HANDLER_PARAMETERS) {
       psynth_module* mod = (psynth_module*)pnet->mods[mod_num];
       mymodule_data* data = (mymodule_data*)mod->data_ptr;
       
       switch(event->command) {
           case PS_CMD_INIT:
               // Initialize module
               break;
           case PS_CMD_NOTE_ON:
               // Handle note on
               break;
           case PS_CMD_RENDER_REPLACE:
               // Render audio
               break;
           case PS_CMD_CLOSE:
               // Cleanup
               break;
       }
       
       return 0;
   }
   ```

3. **Register Module**
   - Add to `g_psynths` array in `sunvox_engine.cpp`

4. **Rebuild Library**
   - Use build scripts in `sunvox_lib/make/`

### 12.3 MetaModule (Nested Projects)

**MetaModule** allows embedding a SunVox project as a module.

**Use Cases:**
- Create reusable instruments
- Build complex effects chains
- Organize large projects

**Creating:**

```c
int meta_mod = sv_new_module(slot, "MetaModule", "Sub", 256, 256, 0);
sv_metamodule_load(slot, meta_mod, "sub_project.sunvox");
```

**How It Works:**
- MetaModule contains its own `sunvox_engine` instance
- Renders audio internally
- Outputs to parent project

### 12.4 MIDI Integration

**MIDI Input:**

SunVox can receive MIDI from external keyboards/controllers.

**Configuration:**
- MIDI ports configured via platform audio system
- Up to 5 MIDI input ports

**MIDI to Module:**

```c
// Enable MIDI input for a module
// (Set via module flags in UI, not directly via API)
```

**MIDI Events:**
- Note On/Off → Note events to selected module
- CC (Controller Change) → Module parameter changes
- Pitch Bend → Pitch modulation
- Program Change → (not typically used)

**MIDI Output:**

```c
// Export project to MIDI file
sunvox_export_to_midi("output.mid", s);
```

### 12.5 Performance Optimization

**Tips:**

1. **Reduce Module Count**
   - Fewer modules = less processing
   - Combine simple modules where possible

2. **Optimize Pattern Complexity**
   - Fewer tracks = less event processing
   - Avoid excessive pattern cloning (use references)

3. **Buffer Size**
   - Larger buffer = more latency but less CPU usage
   - Smaller buffer = less latency but higher CPU usage

4. **Sample Rate**
   - Lower sample rate (e.g., 44100 vs 48000) = less processing

5. **Module-Specific:**
   - Reverb: Reduce size/quality
   - FFT: Use smaller FFT size
   - Filters: Use simpler filter types

6. **Threading:**
   - Use `SV_INIT_FLAG_ONE_THREAD` if not needed

### 12.6 Debugging

**Logging:**

```c
// Enable logging (if not compiled with NOLOG)
// Logs go to system log (iOS: Console, Android: Logcat)
```

**Query Playback State:**

```c
int line = sv_get_current_line(slot);
int line_fp = sv_get_current_line2(slot);  // Fixed-point (27.5)
int playing = sv_end_of_song(slot);        // 0 = playing, 1 = stopped
int bpm = sv_get_song_bpm(slot);
int tpl = sv_get_song_tpl(slot);
```

**Audio Analysis:**

```c
// Get output level
int left = sv_get_current_signal_level(slot, 0);
int right = sv_get_current_signal_level(slot, 1);
// 0-255
```

**Module Scope:**

```c
// Get module output waveform
int16_t buffer[1024];
int received = sv_get_module_scope2(slot, mod_num, 0, buffer, 1024);
// buffer[0..received-1] contains samples
```

### 12.7 Cross-Platform Considerations

**Platform-Specific Code:**

SunDog layer handles platform differences:
- **iOS**: Core Audio backend
- **Android**: OpenSL ES / AAudio
- **macOS**: Core Audio
- **Windows**: WASAPI / DirectSound
- **Linux**: ALSA / JACK

**File Paths:**

- Use forward slashes: `"songs/song.sunvox"`
- Absolute paths work on all platforms
- iOS: Use app sandbox paths
- Android: Use external storage paths

**Threading:**

- Audio callback runs on OS-provided audio thread
- Priority varies by platform (iOS = very high, Android = high)

**Permissions:**

- **iOS**: No special permissions needed
- **Android**: WRITE_EXTERNAL_STORAGE (if accessing files)

### 12.8 Further Reading

**Official Resources:**
- SunVox Library Documentation: https://warmplace.ru/soft/sunvox/sunvox_lib.php
- SunVox User Manual: https://warmplace.ru/soft/sunvox/
- SunVox Forum: https://warmplace.ru/forum/

**Code Examples:**
- `sunvox_lib/examples/c/` - C examples
- `sunvox_lib/examples/pixilang/` - PixiLang examples

**Related Projects:**
- Radiant Voices: Python library for SunVox file manipulation
- SunVox Mobile: Full SunVox app for iOS/Android

**Rehorsed-Specific Documentation:**
- `sunvox_rehorsed_tweaks.md` - Rehorsed's modifications, integrations, and control capabilities
- `/app/native/sunvox_lib/MODIFICATIONS.md` - Technical details of source code modifications
- `/app/docs/features/sunvox_integration/` - Complete integration documentation

---

## Glossary

**BPM**: Beats Per Minute - tempo of the project

**Clone**: A pattern instance that shares data with its parent

**DSP**: Digital Signal Processing

**Event**: A note, controller change, or effect command in a pattern

**Line**: A horizontal row in a pattern; one step in the timeline

**MetaModule**: A module that contains an entire SunVox project

**Module**: A unit of sound generation or processing (synth, effect, controller)

**Pattern**: A grid of musical events (notes, effects) arranged in tracks and lines

**PSynth**: PixiSynth - the modular synthesis framework

**Slot**: An independent instance of the SunVox engine

**Supertrack**: Vertical layer for stacking patterns

**Tick**: Sub-division of a line for timing precision

**Timeline**: The horizontal arrangement of patterns

**TPL**: Ticks Per Line - speed of playback

**Track**: A vertical column in a pattern; independent voice

---

## Appendix: File Structure Reference

```
sunvox_lib/
├── lib_dsp/                      # DSP utilities
│   ├── dsp.h
│   ├── dsp_functions.cpp
│   └── dsp_tables.cpp
├── lib_flac/                     # FLAC codec
├── lib_mp3/                      # MP3 codec
├── lib_vorbis/                   # Vorbis codec
├── lib_sundog/                   # Platform abstraction
│   ├── sundog.h                  # Platform config
│   ├── file/                     # File I/O
│   ├── log/                      # Logging
│   ├── memory/                   # Memory
│   ├── sound/                    # Audio I/O
│   ├── thread/                   # Threading
│   └── time/                     # Time functions
├── lib_sunvox/                   # SunVox engine
│   ├── sunvox_engine.h           # Engine structure
│   ├── sunvox_engine.cpp         # Engine init
│   ├── sunvox_engine_audio_callback.cpp  # Audio processing
│   ├── sunvox_engine_patterns.cpp        # Pattern management
│   ├── sunvox_engine_load_proj.cpp       # Project loading
│   ├── sunvox_engine_save_proj.cpp       # Project saving
│   ├── sunvox_engine_load_module.cpp     # Module loading
│   ├── sunvox_engine_save_module.cpp     # Module saving
│   ├── sunvox_engine_export.cpp          # WAV/MIDI export
│   ├── sunvox_engine_record.cpp          # Recording
│   ├── psynth/                   # Module system
│   │   ├── psynth.h              # Module interface
│   │   ├── psynth_net.h          # Module network
│   │   ├── psynth_net.cpp
│   │   ├── psynths_*.cpp         # Individual modules
│   │   └── ...
│   ├── midi_file/                # MIDI import/export
│   └── xm/                       # XM module support
└── sunvox_lib/                   # Public API
    ├── headers/
    │   └── sunvox.h              # Public API (C)
    ├── docs/
    ├── examples/
    ├── android/                  # Android library
    ├── ios/                      # iOS library
    ├── js/                       # JavaScript/WASM library
    ├── linux/                    # Linux library
    ├── macos/                    # macOS library
    ├── windows/                  # Windows library
    ├── main/
    │   └── sunvox_lib.cpp        # API implementation
    └── make/                     # Build scripts
```

---

## Index of Key Functions

**Initialization:**
- `sv_init()` - Initialize library
- `sv_deinit()` - Shut down library
- `sv_open_slot()` - Open a slot
- `sv_close_slot()` - Close a slot

**Project Management:**
- `sv_load()` - Load project from file
- `sv_save()` - Save project to file
- `sv_load_from_memory()` - Load from memory
- `sv_save_to_memory()` - Save to memory

**Playback Control:**
- `sv_play()` - Start playback
- `sv_play_from_beginning()` - Play from start
- `sv_stop()` - Stop playback
- `sv_pause()` - Pause playback
- `sv_resume()` - Resume playback
- `sv_rewind()` - Rewind to position
- `sv_set_position()` - Seamless position change (Rehorsed mod)

**Pattern Operations:**
- `sv_new_pattern()` - Create pattern
- `sv_remove_pattern()` - Delete pattern
- `sv_get_pattern_data()` - Get pattern event data
- `sv_set_pattern_event()` - Set single event
- `sv_get_pattern_lines()` - Get pattern length
- `sv_set_pattern_size()` - Resize pattern
- `sv_pattern_mute()` - Mute/unmute pattern

**Module Operations:**
- `sv_new_module()` - Create module
- `sv_remove_module()` - Delete module
- `sv_connect_module()` - Connect modules
- `sv_disconnect_module()` - Disconnect modules
- `sv_load_module()` - Load module from file
- `sv_get_module_ctl_value()` - Get parameter value
- `sv_set_module_ctl_value()` - Set parameter value

**Events:**
- `sv_send_event()` - Send real-time event

**Pattern Looping (Rehorsed Mods):**
- `sv_set_pattern_loop()` - Enable pattern loop mode
- `sv_set_pattern_loop_count()` - Set loop count
- `sv_set_pattern_sequence()` - Set pattern order
- `sv_get_pattern_current_loop()` - Get current loop iteration
- `sv_pattern_set_flags()` - Set pattern flags
- `sv_enable_supertracks()` - Enable supertracks mode

**Audio Callback:**
- `sv_audio_callback()` - Get audio output

**Thread Safety:**
- `sv_lock_slot()` - Lock slot for modifications
- `sv_unlock_slot()` - Unlock slot

---

**End of Document**

This comprehensive guide should provide you with a deep understanding of the SunVox Library architecture, from high-level concepts down to implementation details. For specific code examples and usage patterns, refer to the official examples in `sunvox_lib/examples/` and the API documentation in `sunvox_lib/headers/sunvox.h`.

