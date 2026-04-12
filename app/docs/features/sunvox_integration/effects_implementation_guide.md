# Effects Implementation Guide

This document has two parts:

- **[Part I: Theory and design options](#part-i-theory-and-design-options)** — How SunVox separates pattern effects vs module controllers, trade-offs (presets vs column chains), and recommendations. Written as product-agnostic design material; examples refer to the original “Rehorsed” planning name where the text predates the current app.
- **[Part II: Current implementation in HypnoPitch](#part-ii-current-implementation-in-hypnopitch)** — What HypnoPitch implements today: master-bus EQ, **per-layer send/return reverb** (dual A/B banks for section handover), master “reverb” as a send-level shim, native wiring, FFI, Dart state, and UI entry points.

---

## Table of Contents

### Part I: Theory and design options

1. [User Requirements](#user-requirements)
2. [Understanding SunVox Effect Systems](#understanding-sunvox-effect-systems)
3. [Pattern Effects Implementation (Vibrato, Slide, etc.)](#pattern-effects-implementation)
4. [Module Controllers for Reverb/Delay/Filter](#module-controllers-for-reverbdelayfilter)
5. [The Combinatorial Explosion Problem](#the-combinatorial-explosion-problem)
6. [THE SOLUTION: Column-Based Effect Chains](#the-solution-column-based-effect-chains)
7. [Alternative Solutions (Preset-Based)](#alternative-solutions-preset-based)
8. [Implementation Details](#implementation-details)
9. [Final Recommendations](#final-recommendations)
10. [HypnoPitch scaling and reverb tails: investigation notes](#hypnopitch-scaling-and-reverb-tails-investigation-notes)

### Part II: Current implementation in HypnoPitch

1. [What is implemented vs not](#what-is-implemented-vs-not)
2. [Master + per-layer signal chain (summary)](#master-per-layer-signal-chain-summary)
3. [Per-layer reverb: data model and native API](#per-layer-reverb-data-model-and-native-api)
4. [Per-layer EQ: data model and native API](#per-layer-eq-data-model-and-native-api)
5. [Per-layer EQ: graph wiring and implementation notes](#per-layer-eq-graph-wiring-and-implementation-notes)
6. [Native layer (HypnoPitch) — key symbols](#native-layer-hypnopitch-key-symbols)
7. [Playback bridge (C API)](#playback-bridge-c-api)
8. [Dart: FFI and PlaybackState](#dart-ffi-and-playbackstate)
9. [UI (master vs layer)](#ui-master-vs-layer)
10. [Mapping notes (EQ dB vs SunVox)](#mapping-notes-eq-db-vs-sunvox)
11. [Relation to Part I](#relation-to-part-i)

---

## Part I: Theory and design options

## User Requirements

### What You Want

**Per-cell control with gradual sliders (0-100) for:**
- Reverb amount
- Delay amount
- Filter cutoff/type
- Multiple effects simultaneously per cell
- Works with column canceling behavior (notes in same column cancel previous notes)

**Like existing volume/pitch controls:**
- Sample-level defaults
- Cell-level overrides
- Gradual control via sliders

---

## Understanding SunVox Effect Systems

**SunVox has TWO completely different effect systems:**

### Type 1: Pattern Effects (Per-Cell in Pattern Data)

**What they are:**
- Effects stored IN each pattern event
- ONE effect per cell (hard limit in SunVox data structure)
- Independent per-cell
- Works perfectly with column canceling

**Available pattern effects:**
- ✅ Vibrato (0x04)
- ✅ Pitch Slide Up/Down (0x01/0x02)
- ✅ Portamento (0x03)
- ✅ Arpeggio (0x11)
- ✅ Volume Slide (0x07)
- ✅ Panning (0x08)
- ✅ Sample Offset (0x09)
- ✅ Retrigger (0x19)
- ❌ **NOT** Reverb
- ❌ **NOT** Delay
- ❌ **NOT** Filter

**SunVox pattern data structure:**
```c
typedef struct {
    uint8_t note;       // MIDI note
    uint8_t vel;        // Velocity
    uint16_t module;    // Target module
    uint16_t ctl;       // Effect code (ONLY ONE!)
    uint16_t ctl_val;   // Effect parameter (ONLY ONE!)
} sunvox_note;  // 8 bytes total
```

**Limitation:** Only ONE effect per cell! Must choose vibrato OR slide OR arpeggio (not multiple).

---

### Type 2: Module Controllers (Per-Module/Sample Global)

**What they are:**
- Parameters/knobs on modules
- Apply to ALL notes from that module
- Can set UNLIMITED controllers simultaneously
- Don't work per-cell (global to module)

**Available on Sampler module:**
- ✅ Reverb (Controller 8)
- ✅ Filter Type (Controller 9)
- ✅ Filter Cutoff (Controller 10)
- ✅ Filter Resonance (Controller 11)
- ✅ Envelope Attack (Controller 3)
- ✅ Envelope Release (Controller 4)
- ✅ Panning (Controller 1)
- ✅ Volume (Controller 0)
- ❌ **NOT** Delay (Sampler doesn't have delay built-in)

**Problem with per-cell control:**
```
Module controllers affect ALL notes from that module!

Line 0: Kick plays, set reverb=50%
Line 4: Snare plays, set reverb=80%
        ❌ Line 0's kick (still playing) ALSO changes to 80%!

Can't have different settings per cell if notes overlap!
```

---

## Pattern Effects Implementation

### When to Use

**Use pattern effects for:**
- Vibrato, pitch slide, arpeggio, volume slide, panning
- Effects that need to vary per-note
- When you need independent per-cell control

### Implementation (Already Documented)

**This follows the EXACT pattern as volume/pitch:**

```c
// Data structures
typedef struct {
    float volume;               // ✅ Already implemented
    float pitch;                // ✅ Already implemented
    uint16_t effect_code;       // 📋 Add this
    uint16_t effect_param;      // 📋 Add this
} CellSettings;

typedef struct {
    float volume;               // ✅ Already implemented
    float pitch;                // ✅ Already implemented
    uint16_t effect_code;       // 📋 Add this (sample default)
    uint16_t effect_param;      // 📋 Add this
} SampleSettings;

// Resolution (same as volume/pitch)
void resolve_effect(Cell* cell, uint16_t* out_code, uint16_t* out_param) {
    if (cell->settings.effect_code == 0) {
        // Inherit from sample
        Sample* s = sample_bank_get_sample(cell->sample_slot);
        *out_code = s ? s->settings.effect_code : 0;
        *out_param = s ? s->settings.effect_param : 0;
        } else {
        // Use cell override
        *out_code = cell->settings.effect_code;
        *out_param = cell->settings.effect_param;
    }
}

// Apply in sync
sv_set_pattern_event(slot, pat, track, line,
    note, velocity, module,
    effect_code,    // ← Add this
    effect_param    // ← Add this
);
```

**Effort:** ~170 lines, 1-2 weeks

**Result:**
- ✅ Per-cell vibrato, slide, arpeggio control
- ✅ Gradual control (0-255 range)
- ✅ Works with column canceling
- ❌ Still only ONE effect per cell
- ❌ Doesn't include reverb/delay/filter

---

## Module Controllers for Reverb/Delay/Filter

### The Challenge

**You want reverb/delay/filter per-cell with 0-100 gradual control.**

**Problem:** These are NOT pattern effects! They're module controllers!

**This means you need multiple modules (presets) with different settings.**

### Simple Example: One Effect

**Reverb with 11 levels (0%, 10%, 20%, ..., 100%):**

```
Kick sample with reverb presets:
├─ Module 1:  Kick 0% reverb   (dry)
├─ Module 2:  Kick 10% reverb
├─ Module 3:  Kick 20% reverb
├─ Module 4:  Kick 30% reverb
... up to
└─ Module 11: Kick 100% reverb

11 modules per sample
20 samples × 11 = 220 modules
Memory: ~660 KB ✅ Totally fine!
```

**This works!** ✅

---

## The Combinatorial Explosion Problem

### What Happens with Multiple Effects

**Your requirement: Reverb + Delay + Filter, each with 100 levels (0-100 slider):**

```
Combinations per sample:
100 reverb × 100 delay × 100 filter = 1,000,000 presets! 😱

Memory per sample: 1,000,000 × 3 KB = 3 GB
For 20 samples: 60 GB ❌ IMPOSSIBLE!
```

**Even with fewer levels:**

```
100 × 100 × 100 = 1,000,000 ❌ Impossible
50 × 50 × 50   = 125,000   ⚠️ Too many (375 MB per 20 samples)
20 × 20 × 20   = 8,000     ⚠️ Pushing it (24 MB per 20 samples, 480 MB total)
10 × 10 × 10   = 1,000     ✅ Manageable (60 MB total)
```

### Why This Matters

**Module creation at init is fine.**  
**Creating 1000+ or 100,000+ modules is NOT.**

**Memory constraints:**
- Mobile devices: 2-4 GB RAM
- 100,000+ modules = 300+ MB just for module structures
- Audio data adds another 10-20 MB
- Leaves little room for app/OS

**CPU constraints:**
- Even though only active modules use CPU
- More modules = more memory overhead
- Slower init times
- More complex management

---

## THE SOLUTION: Column-Based Effect Chains

**This is the OPTIMAL architecture for Rehorsed!** 🎯

### Core Concept

Instead of creating thousands of preset modules, create **one effect chain per column** and leverage **column canceling** to allow per-cell effect control.

### Key Insight

**Rehorsed has column canceling behavior:**
- Only ONE note plays per column at a time
- New note in same column CANCELS previous note
- This means we can safely change effect settings between notes!

### Architecture

```
32 Columns, each with:
├─ 25 Sampler modules (one per sample)
└─ 1 Effect chain (shared by all samplers in column)
   ├─ Reverb module
   ├─ Delay module
   ├─ Filter module
   └─ Compressor module

Module count:
├─ Samplers: 32 columns × 25 samples = 800 modules
├─ Effects: 32 columns × 4 effects = 128 modules
└─ Total: 928 modules = ~3 MB ✅
```

### Visual Example

```
Column 0:
├─ Sampler: Col0_Kick ───┐
├─ Sampler: Col0_Snare ──┤
├─ Sampler: Col0_HiHat ──┼→ [Reverb] → [Delay] → [Filter] → [Compressor] → Output
└─ Sampler: Col0_Piano ──┘
    ↑ All route through shared effect chain

Column 1:
├─ Sampler: Col1_Kick ───┐
├─ Sampler: Col1_Snare ──┤
├─ Sampler: Col1_HiHat ──┼→ [Reverb] → [Delay] → [Filter] → [Compressor] → Output
└─ Sampler: Col1_Piano ──┘
    ↑ Independent effect chain

... (30 more columns)
```

### How It Works

**1. Initialization (once at startup):**

```cpp
void init_column_effect_chains() {
    for (int col = 0; col < NUM_COLUMNS; col++) {
        // Create samplers for this column
        for (int sample_idx = 0; sample_idx < NUM_SAMPLES; sample_idx++) {
            Sample* sample = get_sample(sample_idx);
            int module_id = col * NUM_SAMPLES + sample_idx;
            
            // Create sampler module
            char name[64];
            snprintf(name, 64, "Col%d_%s", col, sample->name);
            int sampler = sv_new_module(SUNVOX_SLOT, "Sampler", name, x, y, 0);
            g_samplers[module_id] = sampler;
            
            // Load sample (audio data shared automatically!)
            sv_sampler_load(SUNVOX_SLOT, sampler, sample->path, -1);
        }
        
        // Create effect chain for this column
        int reverb = sv_new_module(SUNVOX_SLOT, "Reverb", "Col_Reverb", x, y, 0);
        int delay = sv_new_module(SUNVOX_SLOT, "Delay", "Col_Delay", x, y, 0);
        int filter = sv_new_module(SUNVOX_SLOT, "Filter Pro", "Col_Filter", x, y, 0);
        int comp = sv_new_module(SUNVOX_SLOT, "Compressor", "Col_Comp", x, y, 0);
        
        g_column_effects[col].reverb = reverb;
        g_column_effects[col].delay = delay;
        g_column_effects[col].filter = filter;
        g_column_effects[col].compressor = comp;
        
        // Route: Samplers → Reverb → Delay → Filter → Compressor → Output
        for (int s = 0; s < NUM_SAMPLES; s++) {
            int sampler = g_samplers[col * NUM_SAMPLES + s];
            sv_connect_module(SUNVOX_SLOT, sampler, reverb);
        }
        sv_connect_module(SUNVOX_SLOT, reverb, delay);
        sv_connect_module(SUNVOX_SLOT, delay, filter);
        sv_connect_module(SUNVOX_SLOT, filter, comp);
        sv_connect_module(SUNVOX_SLOT, comp, 0);  // 0 = output
    }
}
```

**2. Playing a cell (with per-cell effect control):**

```cpp
void play_cell(int step, int col) {
    Cell* cell = get_cell(step, col);
    if (!cell || cell->sample_id < 0) return;
    
    // Get sampler module for (column, sample)
    int sampler_module = col * NUM_SAMPLES + cell->sample_id;
    
    // Get effect modules for this column
    ColumnEffects* fx = &g_column_effects[col];
    
    // ✅ Column canceling stops previous note BEFORE we change effects!
    // ✅ Safe to change effect settings for new note!
    
    // Configure Reverb
    if (cell->use_reverb) {
        // Controller 0: Wet (0-256)
        sv_set_module_ctl_value(SUNVOX_SLOT, fx->reverb, 0, 
                                cell->reverb_wet, 0);
        // Controller 1: Room size (0-256)
        sv_set_module_ctl_value(SUNVOX_SLOT, fx->reverb, 1, 
                                cell->reverb_room_size, 0);
    } else {
        // Disable: Set wet to 0
        sv_set_module_ctl_value(SUNVOX_SLOT, fx->reverb, 0, 0, 0);
    }
    
    // Configure Delay
    if (cell->use_delay) {
        // Controller 0: Delay time (0-256)
        sv_set_module_ctl_value(SUNVOX_SLOT, fx->delay, 0, 
                                cell->delay_time, 0);
        // Controller 1: Feedback (0-256)
        sv_set_module_ctl_value(SUNVOX_SLOT, fx->delay, 1, 
                                cell->delay_feedback, 0);
        // Controller 2: Wet (0-256)
        sv_set_module_ctl_value(SUNVOX_SLOT, fx->delay, 2, 
                                cell->delay_wet, 0);
    } else {
        // Disable: Set wet to 0
        sv_set_module_ctl_value(SUNVOX_SLOT, fx->delay, 2, 0, 0);
    }
    
    // Configure Filter
    if (cell->use_filter) {
        // Controller 0: Cutoff (0-16384)
        sv_set_module_ctl_value(SUNVOX_SLOT, fx->filter, 0, 
                                cell->filter_cutoff, 0);
        // Controller 1: Resonance (0-1530)
        sv_set_module_ctl_value(SUNVOX_SLOT, fx->filter, 1, 
                                cell->filter_resonance, 0);
    } else {
        // Disable: Set cutoff to max (bypass)
        sv_set_module_ctl_value(SUNVOX_SLOT, fx->filter, 0, 16384, 0);
    }
    
    // Configure Compressor
    if (cell->use_compressor) {
        // Controller 0: Threshold (0-512)
        sv_set_module_ctl_value(SUNVOX_SLOT, fx->compressor, 0, 
                                cell->comp_threshold, 0);
        // Controller 1: Ratio (0-256)
        sv_set_module_ctl_value(SUNVOX_SLOT, fx->compressor, 1, 
                                cell->comp_ratio, 0);
    } else {
        // Disable: Set threshold to max (bypass)
        sv_set_module_ctl_value(SUNVOX_SLOT, fx->compressor, 0, 512, 0);
    }
    
    // Play note (goes through configured effect chain)
    int note = calculate_note(cell);
    int velocity = calculate_velocity(cell);
    sv_send_event(SUNVOX_SLOT, col, note, velocity, 
                  sampler_module + 1, 0, 0);
}
```

### Per-Cell Effect Control ✅

**Example timeline for Column 1:**

```
Line 1: Kick (20% reverb, no other effects)
└─ Set: reverb_wet=51 (20%), delay_wet=0, filter bypass, comp bypass
└─ Play: Kick with 20% reverb only

Line 5: Snare (30% reverb, 60% delay, LP filter)
└─ Previous kick CANCELLED (column canceling)
└─ Set: reverb_wet=77 (30%), delay_wet=154 (60%), filter_cutoff=6000
└─ Play: Snare with reverb + delay + filter

Line 10: HiHat (no effects)
└─ Previous snare CANCELLED
└─ Set: All effects to 0/bypass
└─ Play: HiHat dry (no effects)
```

**Each cell has independent effect settings!** ✅

### Cross-Column Independence

```
Same time (Line 5):

Column 0: Kick (20% reverb)
└─ Uses Column 0's effect chain → Set to 20% reverb

Column 1: Kick (40% reverb)  
└─ Uses Column 1's effect chain → Set to 40% reverb

Column 2: Snare (80% reverb, delay, filter)
└─ Uses Column 2's effect chain → Set to 80% reverb + delay + filter

✅ All play simultaneously with DIFFERENT effects!
✅ Each column has independent effect chain!
```

### Cell Data Structure

```c
typedef struct {
    int sample_id;              // Which sample to play (0-24)
    
    // Reverb
    bool use_reverb;
    uint8_t reverb_wet;         // 0-255 (0-100%)
    uint8_t reverb_room_size;   // 0-255
    
    // Delay
    bool use_delay;
    uint8_t delay_time;         // 0-255
    uint8_t delay_feedback;     // 0-255
    uint8_t delay_wet;          // 0-255 (0-100%)
    
    // Filter
    bool use_filter;
    uint16_t filter_cutoff;     // 0-16384 (Hz)
    uint8_t filter_resonance;   // 0-255
    
    // Compressor
    bool use_compressor;
    uint16_t comp_threshold;    // 0-512 (dB)
    uint8_t comp_ratio;         // 0-255
    
    // Pattern effect (ONE additional)
    uint16_t effect_code;       // Vibrato, slide, etc.
    uint16_t effect_param;      // 0-255
} Cell;
```

### Effect Combinations

**Any combination per cell (2^4 = 16 combinations):**

```
Cell A: R--- (reverb only)
Cell B: -D-- (delay only)
Cell C: --F- (filter only)
Cell D: ---C (compressor only)
Cell E: RD-- (reverb + delay)
Cell F: RDF- (reverb + delay + filter)
Cell G: RDFC (all 4 effects!)
Cell H: ---- (no effects, dry)

✅ All 16 combinations possible per cell!
✅ 0-255 gradual control for EACH effect parameter!
```

### Sample Defaults + Cell Overrides

```c
// Sample defaults
Sample kick = {
    .default_reverb_wet = 51,        // 20% default
    .default_delay_wet = 0,          // No delay by default
    .default_filter_cutoff = 16384,  // Filter bypassed
};

// Cell resolution (like volume/pitch)
int final_reverb = (cell->reverb_wet >= 0) 
    ? cell->reverb_wet 
    : kick.default_reverb_wet;
```

### Performance Optimization

**Cache previous effect values to avoid redundant controller changes:**

```cpp
static uint8_t g_column_last_reverb[32];
static uint8_t g_column_last_delay[32];

void play_cell(int step, int col) {
    // ... get cell and effects ...
    
    // Only update if changed
    if (cell->reverb_wet != g_column_last_reverb[col]) {
        sv_set_module_ctl_value(SUNVOX_SLOT, fx->reverb, 0, 
                                cell->reverb_wet, 0);
        g_column_last_reverb[col] = cell->reverb_wet;
    }
    
    // Same for other effects...
}
```

### Resource Summary

**For 32 columns, 25 samples, 4 effects per column:**

```
Samplers: 32 × 25 = 800 modules (~2.4 MB)
Effects: 32 × 4 = 128 modules (~384 KB)
Total: 928 modules (~2.8 MB) ✅

Audio data: 25 samples × 500 KB = 12.5 MB (shared)
Total memory: ~15.3 MB ✅ Excellent!

CPU: ~20-30 active modules = 10-15% ✅
Init time: ~2-3 seconds (one-time) ✅
```

### Why This Works Perfectly

1. ✅ **Column canceling**: Only one note per column, so only one set of effects needed
2. ✅ **Minimal modules**: 928 modules vs 4,000+ with presets
3. ✅ **True continuous control**: 0-255 for every effect parameter
4. ✅ **Any combination**: Enable/disable any effects per cell
5. ✅ **Column independence**: Each column has its own effect chain
6. ✅ **Audio data sharing**: Same .wav loaded 32 times shares memory
7. ✅ **Fast playback**: Simple module lookup, configure effects, play
8. ✅ **Sample defaults**: Can implement inheritance like volume/pitch

### Advantages Over Preset Approach

| Feature | Column Chains | Presets |
|---------|--------------|---------|
| **Modules** | 928 | 4,000+ |
| **Memory** | ~3 MB | ~12 MB |
| **Control** | 0-255 continuous | Discrete levels |
| **Combinations** | Any (2^4 = 16) | Pre-defined only |
| **Flexibility** | Add effects easily | Must recreate all presets |
| **Complexity** | Medium | Low |

### Pattern Effects (Bonus)

**Add ONE additional pattern effect per cell:**

```cpp
// After configuring module effects:
sv_send_event(SUNVOX_SLOT, col, note, velocity, 
              sampler_module + 1,
              cell->effect_code,    // Vibrato, slide, etc.
              cell->effect_param);  // 0-255

// Result: 4 module effects + 1 pattern effect = 5 effects per cell!
```

---

## Alternative Solutions (Preset-Based)

### Solution A: Use 10-20 Levels (RECOMMENDED) ✅

**Best balance of control vs. feasibility:**

```
Configuration:
├─ Reverb: 20 levels (0, 5, 10, 15, ..., 95, 100) ← 5% increments
├─ Filter: 20 levels (0, 5, 10, ..., 100)
└─ Combinations: 20 × 20 = 400 per sample

Total: 20 samples × 400 = 8,000 modules
Memory: 8,000 × 3 KB = 24 MB ✅ Excellent!
CPU: 5-10% average ✅
```

**UI Implementation:**

```dart
// Slider APPEARS 0-100 but snaps to 20 levels
Slider(
  value: reverbValue,
  min: 0, max: 100,
  divisions: 20,  // Snaps to 0, 5, 10, 15, ..., 100
  label: '${reverbValue.round()}%',
  onChanged: (val) {
    int reverbLevel = (val / 5).round();    // 0-20
    int filterLevel = (filterVal / 5).round(); // 0-20
    
    // Map to preset module
    int presetIndex = reverbLevel * 20 + filterLevel;
    cell.sample_slot = baseSampleSlot + presetIndex;
    
    resync();
  }
)
```

**What user sees:**
- ✅ Smooth 0-100 sliders
- ✅ Appears continuous
- ✅ Actually 21 discrete levels (5% steps)
- ✅ Difference is imperceptible!

**Result:**
- ✅ 2 effects per cell (reverb + filter)
- ✅ Gradual control (20 levels each)
- ✅ 24 MB memory (negligible)
- ✅ 5-10% CPU (excellent)
- ✅ Works with column canceling
- ✅ Implementation: 2-3 weeks

---

### Solution B: Prioritize Key Effects

**Not all effects need same granularity:**

```
Configuration:
├─ Reverb: 20 levels (most important)
├─ Filter: 10 levels (less critical)
├─ Combinations: 20 × 10 = 200 per sample

Total: 20 samples × 200 = 4,000 modules
Memory: 4,000 × 3 KB = 12 MB ✅
```

**Or even simpler:**

```
Configuration:
├─ Reverb: 10 levels (0%, 10%, 20%, ..., 90%, 100%)
├─ Filter: 10 levels
├─ Combinations: 10 × 10 = 100 per sample

Total: 20 samples × 100 = 2,000 modules
Memory: 2,000 × 3 KB = 6 MB ✅ Very light!
```

---

### Solution C: Hybrid Approach (Module + Pattern)

**Combine both effect systems:**

```
Module Controllers (Reverb + Filter):
├─ 20 × 20 = 400 presets per sample
├─ Coarse control via sample slot selection
└─ 8,000 modules total = 24 MB

Pattern Effects (ONE additional):
└─ Fine control: Vibrato OR Slide OR Arpeggio
    Range: 0-255 for that ONE effect

Result: 3 effects per cell total!
(2 from module + 1 from pattern)
```

**Example:**

```dart
Cell {
  sample_slot: 45,      // Preset with reverb=50%, filter=LP 8kHz
  effect_code: 0x04,    // + Vibrato
  effect_param: 0x60    // Depth = 96
}

// This cell has:
// - Reverb: 50% (from module)
// - Filter: LP 8kHz (from module)
// - Vibrato: depth=96 (from pattern)
// = 3 effects! ✅
```

---

### Solution D: Accept Coarser Steps

**If 10-20 levels feels too granular:**

```
Simple presets (5-7 per effect):
├─ Reverb: Dry, Light, Medium, Heavy, Wet (5 levels)
├─ Filter: Off, Slight, Medium, Dark, Bright (5 levels)
├─ Combinations: 5 × 5 = 25 per sample

Total: 20 samples × 25 = 500 modules
Memory: 500 × 3 KB = 1.5 MB ✅ Extremely light!
```

**Still gives musical control!**

---

## Comparison Table

| Approach | Effects/Cell | Levels Each | Modules/Sample | Total Modules | Memory | Feasible? |
|----------|--------------|-------------|----------------|---------------|--------|-----------|
| **100 levels × 3 effects** | 3 | 100 | 1,000,000 | 20,000,000 | 60 GB | ❌ NO |
| **20 levels × 3 effects** | 3 | 20 | 8,000 | 160,000 | 480 MB | ⚠️ Pushing it |
| **20 levels × 2 effects** | 2 | 20 | 400 | 8,000 | 24 MB | ✅ **RECOMMENDED** |
| **10 levels × 3 effects** | 3 | 10 | 1,000 | 20,000 | 60 MB | ✅ Good |
| **10 levels × 2 effects** | 2 | 10 | 100 | 2,000 | 6 MB | ✅ Very light |
| **5 levels × 2 effects** | 2 | 5 | 25 | 500 | 1.5 MB | ✅ Extremely light |

---

## Implementation Details

### Module Setup at Initialization

```cpp
// Create all reverb/filter presets at startup
void setup_effects_presets() {
    int slot = 0;
    
    for (int sample_idx = 0; sample_idx < 20; sample_idx++) {
        const char* path = get_sample_path(sample_idx);
        
        // Create 400 presets (20 reverb × 20 filter)
        for (int reverb_level = 0; reverb_level < 20; reverb_level++) {
            for (int filter_level = 0; filter_level < 20; filter_level++) {
                // Load sample
                sunvox_wrapper_load_sample(slot, path);
                
                // Set effects
                int mod_id = g_sampler_modules[slot];
                int reverb = reverb_level * 13;    // 0-247 (0-100%)
                int filter_cutoff = 16384 - (filter_level * 820); // 16384 down to 0
                
                sv_set_module_ctl_value(SUNVOX_SLOT, mod_id, 8, reverb, 0);
                sv_set_module_ctl_value(SUNVOX_SLOT, mod_id, 10, filter_cutoff, 0);
                
                slot++;
            }
        }
    }
    
    // Total: 8,000 modules created
    // Time: < 2 seconds
    // Memory: ~24 MB
}
```

### Data Model

```dart
class Sample {
  String name;
  String filePath;
  int baseSampleSlot;  // Starting slot (e.g., 0 for kick, 400 for snare)
  int presetsPerSample = 400;  // 20 × 20
}

class EffectPresetMapper {
  // Map reverb/filter levels to sample slot
  static int getSampleSlot(
    int baseSampleSlot,
    int reverbLevel,   // 0-20
    int filterLevel    // 0-20
  ) {
    return baseSampleSlot + (reverbLevel * 20) + filterLevel;
  }
  
  // Reverse: Get levels from sample slot
  static (int, int) getLevelsFromSlot(int sampleSlot, int baseSampleSlot) {
    int offset = sampleSlot - baseSampleSlot;
    int reverbLevel = offset ~/ 20;
    int filterLevel = offset % 20;
    return (reverbLevel, filterLevel);
  }
}
```

### UI Implementation

```dart
class CellEffectsControl extends StatefulWidget {
  final Cell cell;
  
  @override
  Widget build(BuildContext context) {
    Sample baseSample = getBaseSampleForCell(cell);
    
    // Extract current levels from sample slot
    var (reverbLevel, filterLevel) = EffectPresetMapper.getLevelsFromSlot(
      cell.sample_slot,
      baseSample.baseSampleSlot
    );
    
    return Column([
      // Reverb slider (appears 0-100, actually 20 levels)
      Text('Reverb: ${reverbLevel * 5}%'),
      Slider(
        value: (reverbLevel * 5).toDouble(),
        min: 0, max: 100,
        divisions: 20,
        onChanged: (val) {
          int newLevel = (val / 5).round();
          
          // Calculate new sample slot
          int newSlot = EffectPresetMapper.getSampleSlot(
            baseSample.baseSampleSlot,
            newLevel,
            filterLevel
          );
          
          setState(() {
            cell.sample_slot = newSlot;
          });
          
          sunvoxResyncCell(cell);
        },
      ),
      
      // Filter slider (appears 0-100, actually 20 levels)
      Text('Filter: ${filterLevel * 5}%'),
      Slider(
        value: (filterLevel * 5).toDouble(),
        min: 0, max: 100,
        divisions: 20,
        onChanged: (val) {
          int newLevel = (val / 5).round();
          
          int newSlot = EffectPresetMapper.getSampleSlot(
            baseSample.baseSampleSlot,
            reverbLevel,
            newLevel
          );
          
          setState(() {
            cell.sample_slot = newSlot;
          });
          
          sunvoxResyncCell(cell);
        },
      ),
    ]);
  }
}
```

### Memory Optimization

**Audio data is shared automatically:**

```cpp
// Loading same file multiple times shares audio data
sunvox_wrapper_load_sample(0, "kick.wav");  // Loads audio data once
sunvox_wrapper_load_sample(1, "kick.wav");  // References SAME audio data!
sunvox_wrapper_load_sample(2, "kick.wav");  // Not duplicated!

// Only module settings differ (3 KB per module)
// Audio data: 500 KB (shared across all 400 kick presets)
// Total: 500 KB + (400 × 3 KB) = 1.7 MB per sample ✅
```

---

## Final Recommendations

### PRIMARY RECOMMENDATION: Column-Based Effect Chains ✅ 🎯

**This is the optimal architecture for Rehorsed!**

```
Architecture:
├─ 800 Sampler modules (32 columns × 25 samples)
├─ 128 Effect modules (32 columns × 4 effects)
└─ Total: 928 modules

Memory: ~15 MB total (~3 MB modules + ~12 MB audio)
CPU: 10-15% average
Implementation: 3-4 weeks

Effects per cell:
├─ Reverb: 0-255 continuous (any value!)
├─ Delay: 0-255 continuous
├─ Filter: 0-16384 continuous
├─ Compressor: 0-512 continuous
├─ Any combination (enable/disable independently)
└─ Pattern effect: ONE additional (vibrato/slide/etc.)

= Up to 5 effects per cell with TRUE continuous control! ✅
```

**Why this is the BEST approach:**
- ✅ **True continuous control**: 0-255 for every parameter (not discrete levels!)
- ✅ **Any combination**: Enable/disable any effects per cell (16 combinations)
- ✅ **Minimal modules**: 928 vs 4,000+ with presets
- ✅ **Reasonable memory**: ~15 MB total (excellent!)
- ✅ **Column independence**: Each column has its own effect chain
- ✅ **Leverages column canceling**: Previous note stops before effects change
- ✅ **Sample defaults**: Can implement inheritance like volume/pitch
- ✅ **Future-proof**: Easy to add more effects to chain
- ✅ **Professional quality**: Uses dedicated effect modules (better than Sampler built-ins)

### Implementation Phases

**Phase 1: Column Effect Chain Setup (1-2 weeks)**
- Create samplers per column (800 modules)
- Create effect chains per column (128 modules)
- Route samplers → effects → output
- Test basic playback

**Phase 2: Per-Cell Effect Control (1-2 weeks)**
- Extend Cell data structure with effect settings
- Add effect resolution logic (sample defaults + cell overrides)
- Update play_cell() to configure effects before playing
- Add caching to optimize redundant controller changes

**Phase 3: UI & Polish (1 week)**
- Add effect control sliders (0-255 range)
- Add enable/disable toggles per effect
- Visual feedback for active effects
- Documentation

**Total: 3-4 weeks** for complete system ✅

---

### ALTERNATIVE: Preset-Based Approach

**If you prefer simpler implementation (discrete levels):**

```
Architecture:
├─ 8,000 modules (20 samples × 20 reverb × 20 filter)
└─ Total: 8,000 modules

Memory: ~24 MB
CPU: 5-10% average
Implementation: 2-3 weeks

Effects per cell:
├─ Reverb: 0-100% (20 discrete levels, 5% increments)
├─ Filter: 0-100% (20 discrete levels)
└─ Pattern effect: ONE additional

= 3 effects per cell with discrete control
```

**Pros:**
- ✅ Simpler implementation (no controller changes)
- ✅ Faster playback (just module selection)
- ✅ Still covers most use cases (5% increments imperceptible)

**Cons:**
- ⚠️ Discrete levels only (not continuous)
- ⚠️ More modules (8,000 vs 928)
- ⚠️ More memory (24 MB vs 15 MB)
- ⚠️ Fixed combinations (can't easily add more effects)

---

### Comparison Table

| Feature | Column Chains | Presets |
|---------|--------------|---------|
| **Modules** | 928 | 8,000 |
| **Memory** | ~15 MB | ~24 MB |
| **Control** | 0-255 continuous | 20 discrete levels |
| **Effects per cell** | 4-5 | 2-3 |
| **Combinations** | Any (2^4 = 16) | Pre-defined only |
| **Flexibility** | Add effects easily | Must recreate all presets |
| **Implementation** | 3-4 weeks | 2-3 weeks |
| **Complexity** | Medium | Low |
| **Result** | ⭐⭐⭐⭐⭐ EXCELLENT | ⭐⭐⭐⭐ Very Good |

---

### Don't Try These

❌ **100 × 100 × 100 preset variations** - Impossible (60 GB, 1M modules)  
❌ **Dynamic module creation during playback** - Slow, buggy, dangerous  
❌ **Changing module controllers without column canceling** - Affects all playing notes  
❌ **Single effect chain for all columns** - Can't have different effects per column

---

## Summary

### What You Want
- Per-cell effects (reverb, delay, filter, compressor)
- Gradual control (0-100 sliders)
- Multiple effects simultaneously per cell
- Works with column canceling

### What You GET with Column Chains ✅
- ✅ **Reverb + Delay + Filter + Compressor:** 0-255 continuous control each
- ✅ **Pattern effects:** ONE additional (vibrato/slide/arpeggio) per cell
- ✅ **Total:** Up to 5 effects per cell
- ✅ **Any combination:** Enable/disable effects independently
- ✅ **True continuous control:** Not discrete levels!
- ✅ **Minimal resources:** 928 modules, ~15 MB, 10-15% CPU

### Recommended Implementation

**🎯 PRIMARY: Column-Based Effect Chains**
- 928 modules
- ~15 MB memory
- 3-4 weeks implementation
- TRUE continuous control (0-255)
- Up to 5 effects per cell
- **BEST overall solution!** ✅

**Alternative: Preset-Based**
- 8,000 modules
- ~24 MB memory
- 2-3 weeks implementation
- Discrete levels (20 each)
- 3 effects per cell
- Simpler but less flexible

**This column-based architecture is the best balance of control, performance, and flexibility!** 🎯

---

## HypnoPitch scaling and reverb tails: investigation notes

This section records **design-time conclusions** (not a shipping spec): how **sections / layers / columns** combine with Part I, and what the **bundled SunVox Reverb** actually does regarding **tails**. Source for DSP behavior: [`app/native/sunvox_lib/lib_sunvox/psynth/psynths_reverb.cpp`](../../../native/sunvox_lib/lib_sunvox/psynth/psynths_reverb.cpp).

### Problem: what actually explodes vs what multiplies

| Pitfall | Why |
|--------|-----|
| **Preset explosion** | One module per *combination* of discrete FX levels (e.g. reverb × delay × filter steps) scales as a **product** — see [The Combinatorial Explosion Problem](#the-combinatorial-explosion-problem). Unrelated to “max sections = 100” in the project data. |
| **Parallel module paths** | Module-based FX (reverb/delay/filter as **controllers** on real modules) needs **one independently routable path** per **simultaneously sounding** voice group. That scales with **concurrency**, not with how many section indices exist in the song. |
| **Sections in time** | Stored section count (e.g. 100) is mostly **data** (automation/presets). **Runtime** usually **reuses** a fixed graph and loads the **active** section’s parameters — unless multiple sections must be **audible at once**. |
| **Section boundaries + tails** | Changing **global** insert FX on a **single** shared reverb can **reshape** everything currently passing through it; a separate issue from “notes not cut” between patterns. |

### HypnoPitch-oriented layout (reference)

Product shape discussed for HypnoPitch: **composition split into sections in time**; each section has **5 layers** × **4 columns**; **layers play concurrently**.

- **Per-column** module FX ⇒ up to **layers × columns** parallel chains (e.g. 5×4 = 20), if every layer-column pair needs **different** insert FX at the same time — same idea as [column chains](#the-solution-column-based-effect-chains), but replicated per layer.
- **Per-layer only** (no per-column FX) ⇒ sum each layer’s columns into a **layer bus**, then **one effect chain per layer** ⇒ **five** parallel FX paths (plus sampler count), fewer modules than a full grid.
- **Column canceling** (one active note per column **within a layer**) still matters for **safe** controller updates **inside** that layer’s routing; **layers** stack, so canceling does **not** apply across layers.

### SunVox “Reverb” module — verified behavior (tails)

From `psynths_reverb.cpp` render path:

- Output is built as **wet × (comb/allpass processing)** plus **dry × input** (`ctl_wet` scales the processed path; `ctl_dry` adds the direct input after processing).
- Setting **`ctl_wet` to 0** multiplies the **entire** processed (reverb) component by zero → **audible tail from that path stops**, even if energy still circulates internally. So **wet is the wrong control** for “stop sending new material but keep decay.”
- **Buffer clears** that actually **wipe** tail state happen in **`clean_filters()`**, used from **`PS_CMD_CLEAN`** and setup — not from every knob tweak.
- **Any** controller change sets `filters_reinit_request` (reinit/recalc/realloc on next render); that is **not** the same as clearing buffers, but **room size / mode / seed**-style changes can resize buffers — treat **big** parameter jumps at section boundaries as a **risk** for continuity unless tested.

### Non–tail-cutting direction (routing)

For **audible** tails across section or mix changes:

1. Prefer **send / return** style wiring: **gain (e.g. Amplifier) before the Reverb** = **send**; keep Reverb **wet** in a range where the return is still **audible** while decaying; use **dry path + mixer** for direct sound.
2. **Do not** use **Reverb wet → 0** as the primary “mute FX for the next section” — it **mutes the return** and kills the tail.
3. If you need **two** independent decaying spaces (e.g. old vs new section color), plan **two** reverb instances or an explicit **crossfade/overlap** — one Reverb has **one** internal state.

HypnoPitch **Part II** now implements **per-layer send/return reverb** (see below): each layer has its own **dual A/B reverb banks** with **Amplifier** send and return stages, summed into **master EQ → output**. The earlier “single shared insert Reverb after EQ” layout is **no longer** the shipping graph; the investigation notes above still apply to **wet vs send** and **tail preservation**.

---

## Part II: Current implementation in HypnoPitch

This section describes the **live codebase** (paths relative to the app package: `app/`).

### What is implemented vs not

| Area | Status in HypnoPitch |
|------|----------------------|
| **Master volume** | Implemented: SunVox slot volume via `sv_volume` (0…256). |
| **Master bus EQ** | Implemented: SunVox **EQ** module, three bands (Low / Mid / High), gain 0…512 per band. EQ is the **only** module in `g_master_effect_modules[]`; it connects **directly** to SunVox output module `0`. |
| **Master “reverb” (UI: Master RVB)** | Implemented as a **compatibility shim**: `sunvox_wrapper_set_master_reverb(wet01)` does **not** drive a dedicated master Reverb module. It sets **Amplifier volume (send)** on each layer’s **currently active** A/B bank to **0…256** (mapped from UI 0…1). This scales **how much** of each layer’s signal feeds that layer’s active reverb path. |
| **Per-layer reverb** | Implemented: For each of `MAX_LAYERS_PER_SECTION` (5) layers: **two** parallel chains **Send amp → Reverb → Return amp → master EQ**, with **A/B banks** so section switches can crossfade **sends** while old tails decay in the inactive bank. Per-**section**, per-**layer** parameters (**send**, **room**, **damp** as 0…255) live in `TableState` (`section_layer_reverb` in [`app/native/table.h`](../../../native/table.h)). |
| **Per-layer EQ** | Implemented: **One** SunVox **EQ** module per layer (`g_layer_eq_mod[]`), inserted **after** layer samplers and **before** the per-layer volume amp, master EQ, and reverb sends. Per-**section**, per-**layer** three-band dB values (**−12…+6**, same range as master EQ UI) live in `TableState` (`section_layer_eq` in [`app/native/table.h`](../../../native/table.h)). No A/B banks (no tail). Applied on section switch via `sunvox_wrapper_apply_section_layer_eq`. |
| **Per-layer volume** | Implemented: **One** SunVox **Amplifier** per layer (`g_layer_post_eq_amp[]`) **after** layer EQ, **before** master EQ and both reverb sends—scales dry and wet together. Per-**section**, per-**layer** level **0…255** in `TableState` (`section_layer_volume` in [`app/native/table.h`](../../../native/table.h)); UI/Dart **0…1**. Applied via `sunvox_wrapper_apply_section_layer_volume` alongside layer EQ on section switch and when editing the current section. |
| **Sampler routing** | Implemented: **One Sampler module per (layer, sample slot)** — `g_sampler_modules[layer][slot]`. Pattern events target the sampler for the cell’s **layer** (`table_get_layer_for_col`). This allows the same sample slot to sound with different layer FX. |
| **Section switch (song mode, tails)** | Implemented: `switch_to_section_seamless_song_mode` + `sunvox_wrapper_on_section_switch` ramp send levels between banks; automatic section changes in song mode also trigger handover from the playback poll path. Hard stop path remains `switch_to_section_immediate`. |
| **Per-cell pattern effects** (vibrato, slide, one effect per cell in pattern data) | Not implemented in the product flow described here; Part I still applies if we add them. |
| **Per-column** separate FX chains | Not implemented; reverb is **per layer**, not per column. |
| **Column-based effect chains** (Part I full “one chain per column”) | Not implemented; see per-layer reverb above instead. |

### Master + per-layer signal chain (summary)

Conceptually, for **each layer** \(L\):

- **Dry**: each layer’s samplers → **Layer EQ** → **Layer volume** (Amplifier) → **Master EQ** → **Output** (via the master EQ module).
- **Wet (per layer)**: same **Layer volume** output → **Send** (Amplifier) → **Reverb** → **Return** (Amplifier) → **same Master EQ** → **Output**.

Each layer has **two** such wet paths (**bank A** and **bank B**). Only one bank is “active” for new send at a time; section handover ramps sends between banks while the previous bank’s reverb can still decay. Wiring is built in `connect_master_effect_chain()` (master EQ only) and `connect_layer_reverb_graph()` in [`app/native/sunvox_wrapper.mm`](../../../native/sunvox_wrapper.mm).

```
Per layer L (repeated for L = 0..4):

  [L Sampler slot 0] ──► [ Layer EQ L ] ──► [ Layer Vol L ] ──┬──► [ Master EQ ] ──► [ Output 0 ]
  [L Sampler slot …] ──► [ Layer EQ L ] ──► [ Layer Vol L ] ──┤         ▲
                                                             │         │
                    ┌────────────────────────────────────────┴─────────┘
                    ├──► [Send L_A] ─►[Rev L_A]─►[Ret L_A]──┘
                    └──► [Send L_B] ─►[Rev L_B]─►[Ret L_B]──┘
```

- Reverb modules run as a **wet-only return** in the shipping graph: Reverb **Dry=0**, **Wet=256**; direct signal remains on the dry path (`layer EQ → layer volume → master EQ`). **Send** level is the primary per-layer “amount” control (aligned with **Non–tail-cutting direction (routing)** above: prefer send/return, not muting reverb wet to silence).
- Return Amplifier uses a small fixed trim (`SV_REVERB_RETURN_TRIM=240`) to keep high-send reverb from reading as an abrupt loudness lift while preserving tail character.
- Controller mapping in [`sunvox_wrapper.mm`](../../../native/sunvox_wrapper.mm) follows `psynths_reverb.cpp` `psynth_register_ctl` order: **Dry=0**, **Wet=1**, **Feedback=2**, **Damp=3**, **Room size=8**. This avoids accidental writes to the wrong parameter.
- `SectionLayerReverb.room` is stored as `0..255` in table state and mapped to SunVox Reverb room-size range `0..128` before applying; `damp` stays in `0..255`.

### Per-layer reverb: data model and native API

- **Storage**: `SectionLayerReverb` in [`app/native/table.h`](../../../native/table.h) — `send`, `room`, `damp` (uint8 0…255) per `[section][layer]`.
- **Setters**: `table_set_section_layer_reverb(...)`, getters `table_get_section_layer_reverb_send/room/damp(...)`.
- **Playback**: `playback_set_section_layer_reverb(section, layer, send01, room01, damp01)` and getters `playback_get_section_layer_reverb_send/room/damp(section, layer)` in [`app/native/playback.h`](../../../native/playback.h) / [`app/native/playback_sunvox.mm`](../../../native/playback_sunvox.mm).
- **Engine**: `sunvox_wrapper_apply_section_layer_reverb(section_index, force_reseed)` and `sunvox_wrapper_on_section_switch(prev, next)` in [`app/native/sunvox_wrapper.h`](../../../native/sunvox_wrapper.h).

### Per-layer EQ: data model and native API

- **Storage**: `SectionLayerEq` in [`app/native/table.h`](../../../native/table.h) — `low_db`, `mid_db`, `high_db` (int8, **−12…+6**) per `[section][layer]`.
- **Setters**: `table_set_section_layer_eq(...)`, `table_set_section_layer_eq_band(...)`, getter `table_get_section_layer_eq_band_db(...)`.
- **Playback**: `playback_set_section_layer_eq_band(section, layer, band, db)` and `playback_get_section_layer_eq_band_db(...)` in [`app/native/playback.h`](../../../native/playback.h) / [`app/native/playback_sunvox.mm`](../../../native/playback_sunvox.mm).
- **Engine**: `sunvox_wrapper_apply_section_layer_eq(section_index)` — sets SunVox EQ ctl 0…2 from table (dB → gain 0…512, same mapping as master). Called at end of `sunvox_wrapper_on_section_switch` (next section) and alongside `sunvox_wrapper_apply_section_layer_reverb` where playback mode / stopped seamless switch applies FX.

### Per-layer volume: data model and native API

- **Storage**: `section_layer_volume[section][layer]` (uint8 **0…255**, default **255**) in [`app/native/table.h`](../../../native/table.h).
- **Setters**: `table_set_section_layer_volume(...)`, getter `table_get_section_layer_volume(...)`.
- **Playback**: `playback_set_section_layer_volume(section, layer, volume01)` and `playback_get_section_layer_volume` in [`app/native/playback.h`](../../../native/playback.h) / [`app/native/playback_sunvox.mm`](../../../native/playback_sunvox.mm).
- **Engine**: `sunvox_wrapper_apply_section_layer_volume(section_index)` — sets **Amplifier** `SV_AMP_CTL_VOL` on `g_layer_post_eq_amp[layer]`. Called next to `sunvox_wrapper_apply_section_layer_eq` wherever section-scoped layer FX are applied.

### Per-layer EQ: graph wiring and implementation notes

Built in [`connect_layer_reverb_graph()`](../../../native/sunvox_wrapper.mm) after [`connect_master_effect_chain()`](../../../native/sunvox_wrapper.mm) (master EQ must exist first).

1. **Create** one SunVox `"EQ"` per layer → `g_layer_eq_mod[layer]`; set bands to **256** (unity), matching master EQ init.
2. **Create** one SunVox `"Amplifier"` per layer → `g_layer_post_eq_amp[layer]` (per-layer volume); initial **volume** ctl **255** (unity).
3. **Create** per-layer A/B reverb chains (unchanged): Send → Reverb → Return → **master EQ**.
4. **Per layer**, **per sample slot**: `sv_connect_module(sampler, layer_eq)` only. Each sampler is a **distinct** source, so this link is unique (26 links into one layer EQ, analogous to 26 samplers feeding the master bus before layer EQ existed).
5. **Per layer**, **after** the sampler loop: connect **`layer_eq → layer_vol_amp`**, then **`layer_vol_amp → master_eq`** and **`layer_vol_amp → send_amp[0]`**, **`layer_vol_amp → send_amp[1]`** exactly **once**.

**Why step 5 must not run inside the slot loop:** `sv_connect_module` maps to `psynth_make_link`. If the same source→destination pair is already linked, SunVox **removes** that link and **does not** re-add it (toggle behavior). Repeating `layer_vol_amp → master_eq` for every slot would disconnect the bus after the first sampler, resulting in **silence**. Only **unique** `(source, destination)` pairs may be connected repeatedly without toggling off.

**Section-scoped tone:** Table state holds EQ per `[section][layer]`. Editing calls `playback_set_section_layer_eq_band` when the section is current; on song-mode section advance, `sunvox_wrapper_apply_section_layer_eq(next_section)` runs after the reverb send ramp (`sunvox_wrapper_on_section_switch`).

**UI:** In [`layer_settings_widget.dart`](../../../lib/widgets/sequencer/v1/layer_settings_widget.dart), the layers strip **VOL**, **EQ**, and **RVB** header buttons use the same `_buildMasterStyleHeaderButton` styling as the master row in [`sound_settings.dart`](../../../lib/widgets/sequencer/v1/sound_settings.dart) (`_buildSettingsButton`: fixed width 80, accent fill when selected). The EQ panel reuses the master pattern: **LOW / MID / HIGH** chevrons + [`WheelSelectWidget`](../../../lib/widgets/sequencer/v1/wheel_select_widget.dart) bound to `getSectionLayerEqBandDb` / `setSectionLayerEqBandDb` for `uiSelectedSection` and `uiSelectedLayer`. The **VOL** panel uses [`GenericSlider`](../../../lib/widgets/sequencer/v1/generic_slider.dart) (`SliderType.volume`) bound to `getSectionLayerVolume` / `setSectionLayerVolume`.

**Persistence:** Included in native `TableState` and undo snapshots (`memcpy` of full state). JSON snapshot export/import persists per-layer FX in snapshot `schema_version: 3` (and still reads v1/v2):

- `source.table.layer_fx.<section>.<layer>.volume01` (optional on import; default 1.0)
- `source.table.layer_fx.<section>.<layer>.reverb.{send01,room01,damp01}`
- `source.table.layer_fx.<section>.<layer>.eq_db.{low,mid,high}`
- `source.playback.master_fx.{volume01,reverb_wet01,eq_db}`
- `source.table.mute_solo.{layer_muted,layer_soloed,layer_column_muted,layer_column_soloed}`

Legacy top-level mute/solo keys remain accepted by importer for compatibility.

### Native layer (HypnoPitch) — key symbols

| Symbol / area | Role |
|-----------------|------|
| `g_master_effect_modules[]`, `MASTER_FX_EQ` | Master **EQ** only (index 0). Connects to output module `0`. |
| `g_sampler_modules[layer][slot]` | Sampler module ids per layer and sample slot. |
| `g_layer_eq_mod[]` | Per-layer **EQ** module (insert between samplers and layer volume / master EQ / reverb sends). |
| `g_layer_post_eq_amp[]` | Per-layer **Amplifier** after layer EQ (dry + wet gain). |
| `g_layer_send_amp`, `g_layer_reverb_mod`, `g_layer_return_amp`, `g_layer_active_bank` | Per-layer A/B send/reverb/return modules and which bank is active after a handover. |
| `connect_master_effect_chain()` | Creates master EQ, connects EQ → output, sets unity EQ bands. |
| `connect_layer_reverb_graph()` | Creates per-layer EQ + per-layer volume amp + A/B reverb chains; connects samplers → layer EQ → layer volume → master EQ (dry) and layer volume → both sends (wet). |
| `sunvox_wrapper_set_master_eq_band(band, gain_0_512)` | EQ bands 0…2 on the master EQ module. |
| `sunvox_wrapper_set_master_reverb(wet01)` | **Shim**: sets **send Amplifier** ctl (volume) on each layer’s **active** bank to 0…256. |
| `sunvox_wrapper_apply_section_layer_reverb` / `sunvox_wrapper_on_section_switch` | Apply table params and perform A/B send crossfade on section change. |
| `sunvox_wrapper_apply_section_layer_eq` | Apply per-layer EQ from table for a section (no ramp). |
| `sunvox_wrapper_apply_section_layer_volume` | Apply per-layer output volume (Amplifier after layer EQ) from table for a section. |

Declared for other translation units in [`app/native/sunvox_wrapper.h`](../../../native/sunvox_wrapper.h).

### Playback bridge (C API)

[`app/native/playback.h`](../../../native/playback.h) exposes:

- `playback_set_master_volume(float volume01)` — forwards to `sv_volume` on the SunVox slot (0…256).
- `playback_set_master_reverb(float wet01)` — calls `sunvox_wrapper_set_master_reverb` (**layer send shim**, see above).
- `playback_set_master_eq_band(int band, int gain_0_512)` — calls `sunvox_wrapper_set_master_eq_band`.
- `playback_set_section_layer_reverb(int section, int layer, float send01, float room01, float damp01)` — updates table + applies to engine for current section when relevant.
- `playback_get_section_layer_reverb_send/room/damp(int section, int layer)` — normalized reverb params for UI/snapshots.
- `playback_set_section_layer_eq_band(int section, int layer, int band, int db)` / `playback_get_section_layer_eq_band_db(...)` — per-layer EQ band in dB.
- `playback_set_section_layer_volume(int section, int layer, float volume01)` / `playback_get_section_layer_volume(...)` — per-layer output level (0.0…1.0).
- `switch_to_section_immediate` / `switch_to_section_seamless_song_mode` — explicit section navigation; `switch_to_section` delegates (song mode + playing uses seamless path).

Implementations: [`app/native/playback_sunvox.mm`](../../../native/playback_sunvox.mm).

### Dart: FFI and PlaybackState

[`app/lib/ffi/playback_bindings.dart`](../../../lib/ffi/playback_bindings.dart) loads the native symbols (`playback_set_master_volume`, `playback_set_master_reverb`, `playback_set_master_eq_band`, `playback_set_section_layer_reverb`, `playback_get_section_layer_reverb_send/room/damp`, `playback_set_section_layer_eq_band`, `playback_get_section_layer_eq_band_db`, `playback_set_section_layer_volume`, `playback_get_section_layer_volume`, and section switch variants).

[`app/lib/state/sequencer/playback.dart`](../../../lib/state/sequencer/playback.dart) — `PlaybackState`:

- **Master volume**: `ValueNotifier<double>` `masterVolumeNotifier`, `setMasterVolume`.
- **Master reverb (shim)**: `masterReverbWetNotifier`, `setMasterReverbWet` (0.0…1.0) — drives **per-layer active send** levels via native shim.
- **Master EQ**: three notifiers `masterEqLowDbNotifier`, `masterEqMidDbNotifier`, `masterEqHighDbNotifier`, integer **dB** in **`[masterEqMinDb, masterEqMaxDb]` = [-12, +6]**.
- **Per-layer reverb**: `setSectionLayerReverb(...)`, getters `getSectionLayerReverbSend/Room/Damp(section, layer)`.
- **Per-layer EQ**: `setSectionLayerEqBandDb(...)`, `getSectionLayerEqBandDb(section, layer, band)` (dB range matches master EQ).
- **Per-layer volume**: `setSectionLayerVolume(...)`, `getSectionLayerVolume(section, layer)` (0.0…1.0).
- `setMasterEqBandDb(band, db)` updates the notifier and calls FFI with **`_dbToSunvoxGain512(db)`**: treats SunVox EQ as linear gain = ctl/256, maps dB → amplitude with \(10^{dB/20}\), then `round(256 * gain)` clamped to **0…512**.
- On successful `playbackInit()`, initial master volume, reverb, and all three EQ bands are pushed to native once.

### UI (master vs layer)

[`app/lib/widgets/sequencer/v1/sound_settings.dart`](../../../lib/widgets/sequencer/v1/sound_settings.dart) (master panel):

- Master header includes **VOL**, **RVB**, **EQ**, **BPM** (and related wiring).
- **RVB**: slider bound to `masterReverbWetNotifier` / `setMasterReverbWet` (global **send-level** shim on each layer’s active bank).
- EQ: band label **LOW / MID / HIGH** with chevrons to cycle band; [`WheelSelectWidget`](../../../lib/widgets/sequencer/v1/wheel_select_widget.dart) shows dB for the active band and calls `setMasterEqBandDb`.

[`app/lib/widgets/sequencer/v1/layer_settings_widget.dart`](../../../lib/widgets/sequencer/v1/layer_settings_widget.dart) (layers panel):

- **EQ** / **RVB** header toggles use `_buildMasterStyleHeaderButton` (same visual language as master **EQ** / **RVB** in `SoundSettingsWidget`).
- **EQ** tab: per-**section** / per-**layer** three-band editor (same LOW/MID/HIGH + wheel pattern as master EQ) via `getSectionLayerEqBandDb` / `setSectionLayerEqBandDb`.
- **REVERB** tab: per-**section** / per-**layer** **send** slider for the current `uiSelectedSection` and `uiSelectedLayer`, via `getSectionLayerReverbSend` / `setSectionLayerReverb` (room/damp are stored in native table state; expose in UI if needed later).

### Mapping notes (EQ dB vs SunVox)

- UI exposes asymmetric **−12…+6 dB** to match practical boost/cut in one control range.
- Native stores **per-band gain 0…512**; **256 ≈ 0 dB** (unity linear gain in the SunVox EQ convention used here).
- Further bands or different curves would adjust `_dbToSunvoxGain512` and/or native clamps.

### Relation to Part I

- **Part I** explains why per-note “studio” FX often need **either** pattern events **or** separate modules / routing; it argues for **column chains** or **preset** strategies when you need **different** reverb/delay/filter per cell.
- **[HypnoPitch scaling and reverb tails: investigation notes](#hypnopitch-scaling-and-reverb-tails-investigation-notes)** summarizes **section/layer/column** scaling, **verified** SunVox Reverb tail behavior from `psynths_reverb.cpp`, and **send/return** vs **wet** as a mute.
- **Part II (current)** ships **master EQ**, **per-layer EQ** (one insert EQ per layer before master bus and reverb sends; section-scoped dB in table state), **per-layer send/return reverb** (A/B banks, section-scoped params in table state), and a **master RVB** control that scales **active send** per layer (shim). **Per-column** distinct FX chains are still **not** implemented; adding them should follow Part I constraints (pattern effect slot limit, module controller bleed-over) and extend routing explicitly in `sunvox_wrapper` / playback.
