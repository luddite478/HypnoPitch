# Audio Click Elimination: Exponential Volume Smoothing

## 🔍 **The Problem: Audio Clicks**

When switching between audio samples instantly, you get **clicks** or **pops**. This happens because:

```
Sample A playing at volume 1.0 ────┐
                                    │ ← INSTANT JUMP = CLICK! 
Sample B starts at volume 1.0 ──────┘
```

The instant volume jump creates a sharp discontinuity in the audio waveform, which our ears hear as an unpleasant "click" or "pop".

## 🎯 **Our Solution: Exponential Volume Smoothing**

Instead of instant volume changes, we **gradually transition** the volume using exponential curves:

```
Sample A: 1.0 → 0.8 → 0.6 → 0.4 → 0.2 → 0.0  (smooth fade-out)
Sample B: 0.0 → 0.2 → 0.4 → 0.6 → 0.8 → 1.0  (smooth fade-in)
```

This creates **natural-sounding transitions** that eliminate clicks completely.

## 🧮 **How Exponential Smoothing Works**

### Basic Formula
```cpp
new_volume = current_volume + α × (target_volume - current_volume)
```

Where:
- **α (alpha)** = smoothing coefficient (0.0 to 1.0)
- **current_volume** = where we are now
- **target_volume** = where we want to go
- **new_volume** = where we'll be next update

### Alpha Values
- **α = 0.0**: No change (stuck at current volume)
- **α = 0.5**: Move halfway to target each update
- **α = 1.0**: Jump instantly to target (no smoothing)

### Time-Based Alpha Calculation
```cpp
α = 1 - exp(-dt / time_constant)
```

Where:
- **dt** = time between updates (~10.7ms for 512-frame audio buffers)
- **time_constant** = desired transition time (6ms rise, 12ms fall)

---

## 🛠️ **Our Implementation**

### Configuration
```cpp
#define VOLUME_RISE_TIME_MS 6.0f      // 6ms fade-in time
#define VOLUME_FALL_TIME_MS 12.0f     // 12ms fade-out time  
#define VOLUME_THRESHOLD 0.0001f      // Convergence threshold
```

### Core Functions
```cpp
// Calculate alpha coefficient for exponential smoothing
static float calculate_smoothing_alpha(float time_ms) {
    float callback_dt = 512.0f / 48000.0f;  // ~10.7ms at 48kHz
    float time_sec = time_ms / 1000.0f;
    return 1.0f - expf(-callback_dt / time_sec);
}

// Apply exponential smoothing step
static float apply_exponential_smoothing(float current, float target, float alpha) {
    return current + alpha * (target - current);
}

// Set target volume with exponential smoothing
static void set_target_volume(cell_node_t* cell, float new_target_volume) {
    if (volume_has_converged(cell->current_volume, new_target_volume)) {
        cell->current_volume = new_target_volume;
        cell->is_volume_smoothing = 0;
        return;
    }
    
    cell->target_volume = new_target_volume;
    cell->is_volume_smoothing = 1;
    cell->volume_rise_coeff = calculate_smoothing_alpha(VOLUME_RISE_TIME_MS);
    cell->volume_fall_coeff = calculate_smoothing_alpha(VOLUME_FALL_TIME_MS);
}

// Update volume smoothing for all active nodes (called every audio callback)
static void update_volume_smoothing(void) {
    for (each active node) {
        if (volume_has_converged(current, target)) {
            current = target;
            stop_smoothing();
        } else {
            float alpha = (current < target) ? rise_coeff : fall_coeff;
            current = apply_exponential_smoothing(current, target, alpha);
        }
        
        ma_node_set_output_bus_volume(&node, 0, current);
    }
}
```

---

## 📊 **Example Transition**

Starting volume: `0.0`, Target volume: `1.0`, Rise time: `6ms`

| Callback | Current Volume | Calculation | 
|----------|----------------|-------------|
| 1 | 0.000 | `0.000 + 0.3 × (1.0 - 0.000) = 0.300` |
| 2 | 0.300 | `0.300 + 0.3 × (1.0 - 0.300) = 0.510` |
| 3 | 0.510 | `0.510 + 0.3 × (1.0 - 0.510) = 0.657` |
| 4 | 0.657 | `0.657 + 0.3 × (1.0 - 0.657) = 0.760` |
| 5 | 0.760 | `0.760 + 0.3 × (1.0 - 0.760) = 0.832` |

Result: **Smooth exponential curve** from 0.0 to 1.0 over ~6ms

---

## 🎵 **A/B Node Switching Flow**

When switching from Sample A to Sample B in the same column using A/B nodes:

1. **Current Node (A)**: `set_target_volume(current_node, 0.0)`
   - Starts fading out with 12ms fall time
   - Uses fall coefficient (slower decay)

2. **Alternate Node (B)**: `set_target_volume(alternate_node, 1.0)` 
   - Loads new sample and starts fading in with 6ms rise time
   - Uses rise coefficient (faster attack)

3. **Both A/B nodes** play simultaneously during transition
   - Current node gets quieter exponentially
   - Alternate node gets louder exponentially
   - **Total result**: Smooth crossfade with no clicks, then roles switch

---

## ⚠️ **Known Limitations**

- **Clicks still occur** for some harmonically rich synth samples
- **Most noticeable** when few other sounds are playing in parallel
- **Less audible** when many sounds are mixed together (masking effect)
- **Requires longer fade times** for complex waveforms (current: 6ms/12ms)

---

## 🎚️ **Tuning Parameters**

### Rise Time (Fade-in)
- **Current**: 6ms (fast attack for responsive feel)
- **Faster** (3ms): More responsive, risk of micro-clicks
- **Slower** (10ms): More gradual, may sound sluggish

### Fall Time (Fade-out)  
- **Current**: 12ms (natural decay for complex content)
- **Faster** (6ms): Quicker cutoff, less natural
- **Slower** (20ms): More natural tail, longer overlap

### Threshold
- **Current**: 0.0001 (snap when within 0.01% of target)
- **Tighter**: More precise but longer transitions
- **Looser**: Faster convergence but less precise

---

## 🎯 **Integration in Our Code**

### Files
- **Main**: `native/sequencer.mm`
- **Functions**: `update_volume_smoothing()`, `set_target_volume()`, `calculate_smoothing_alpha()`

### Usage Points
1. **Sample start**: Fade from 0.0 to target volume on A or B node
2. **A/B switch**: Crossfade between current and alternate column nodes
3. **Sample stop**: Fade from current to 0.0

---

## 📚 **Alternative Smoothing Approaches**

During development, we analyzed three professional approaches to audio click elimination:

### 🎛️ **Audacity: Kernel-Based Smoothing**
- **Technique**: Convolution with triangular smoothing kernels
- **Pros**: Highly effective for complex patterns, preserves audio quality
- **Cons**: CPU intensive, complex implementation
- **Result**: Not adopted - too complex for real-time use

### ⚡ **Surge Synthesizer: Linear Volume Ramping**  
- **Technique**: Linear interpolation over fixed time (4ms)
- **Pros**: Simple implementation, CPU efficient, predictable timing
- **Cons**: Linear curves less natural than exponential
- **Result**: Initially adopted, later improved with exponential curves

### 🚀 **SunVox: Exponential Smoothing** (Our Final Choice)
- **Technique**: Exponential smoothing with separate rise/fall coefficients
- **Pros**: Natural curves, separate timing control, CPU efficient, industry proven
- **Cons**: Slightly more complex than linear ramping
- **Result**: Final adoption with modifications for our use case

### Comparison Summary

| Approach | Complexity | CPU Cost | Audio Quality | Real-time Suitable |
|----------|------------|----------|---------------|-------------------|
| **Audacity** | High | High | Excellent | ❌ No |
| **Surge** | Low | Low | Good | ✅ Yes |
| **SunVox** | Low | Low | Excellent | ✅ Yes |

Our implementation is **inspired by SunVox's exponential approach** but adapted for our specific sequencer architecture and optimized for harmonically rich content.

---
