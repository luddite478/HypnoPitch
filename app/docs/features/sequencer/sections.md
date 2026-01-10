# Sections Implementation

## Overview
**Sections** are different parts of a song that can be looped independently or chained together in song mode. Each section contains its own set of sound grid layers and supports two distinct playback modes: **Loop Mode** (repeat current section) and **Song Mode** (play through all sections sequentially).

## Playback Modes

### Loop Mode (Default)
- **Behavior**: Current section repeats infinitely  
- **Native Logic (updated)**: Playback wraps within the native playback region `[start, end)` (end exclusive). Flutter sets this region to the visible section window: `[sectionStart, sectionStart + gridRows)`
- **Use Case**: Practice, live performance, jamming on specific sections
- **Visual**: Loop button highlighted in accent color
- **End Condition**: Never stops automatically (manual stop only)

### Song Mode  
- **Behavior**: Sections play sequentially according to their loop counts, then advance to next section
- **Native Logic (updated)**: Continuous playback across the full playback region; Flutter sets the region to `[0, stepsLen)`. Native stops when `g_current_step >= region.end`.
- **Use Case**: Full song playback, recording complete arrangements  
- **Visual**: Loop button dimmed
- **End Condition**: Stops automatically after last section completes
- **UI Updates**: Section display advances automatically during playback

## UI Components

### Section Button (Left Side Control)
- **Display**: Shows "S" over current section number (e.g., "S" over "1" for Section 1)
- **Function**: Opens section control overlay when tapped
- **Visual State**: Highlights when overlay is open
- **Song Mode**: Updates automatically to show currently playing section

### Loop Mode Button (Left Side Control) 
- **Icon**: `Icons.repeat`
- **Active State**: Bright accent color when in loop mode
- **Inactive State**: Dimmed color when in song mode
- **Function**: Toggles between loop and song playback modes
- **Effect**: Changes native sequencer behavior immediately

### Navigation Arrows (Side Controls)
- **Left Arrow**: Navigate to previous section (disabled if only 1 section)
- **Right Arrow**: 
  - Navigate to next section (if not on last section)
  - Open section creation overlay (if on last section)

## Section Control Overlay
- **Purpose**: Configure existing sections
- **Features**:
  - View all sections with current section highlighted
  - Adjust loop count per section (1-16 loops)
  - Display current playback mode (Loop/Song)
- **Access**: Tap section button (S1, S2, etc.)

## Section Creation Overlay
- **Purpose**: Create new sections
- **Options**:
  - **Create Blank**: Empty section with default settings
  - **Create From**: Copy existing section's content and settings
- **Access**: Right arrow when on last section

## Native Implementation (updated)

### Data Structure
```cpp
static int g_song_mode = 0;                  // 0 = loop mode, 1 = song mode
static int g_steps_len = 16;                 // Current logical steps length (table height)
static playback_region_t g_playback_region;  // [start, end) window for playback

// UI metadata retained for compatibility but not used for playback logic
static int g_current_section = 0;
static int g_total_sections = 1;
static int g_steps_per_section = 16;
static int g_section_start_step = 0;
```

### Continuous Playback Architecture

**KEY CHANGE**: Native sequencer operates on **absolute steps** and uses a **playback region** to define loop/stop boundaries:

- **Section Layout**: Sections are vertical stacks in a continuous table
  - Section 1: Steps 0-15 (16 steps)
  - Section 2: Steps 16-31 (16 steps) 
  - Section 3: Steps 32-47 (16 steps)

- **Playback Logic**: No native section boundaries. Region-driven behavior:
  ```cpp
  if (g_current_step >= g_playback_region.end) {
      if (g_song_mode) {
          g_sequencer_playing = 0;               // Song mode: stop at end
      } else {
          g_current_step = g_playback_region.start; // Loop mode: wrap
      }
  }
  ```

### Native API Functions
- `start_sequencer(bpm, steps, startStep)`: Start with absolute step position; `steps` sets current logical length
- `set_song_mode(isSongMode)`: Set playback mode (0=loop, 1=song)
- `set_playback_region_bounds(start, end)`: Set native playback window `[start, end)`
- `set_steps_len(steps)` / `get_steps_len()`: Explicit control of logical steps length
- `set_current_section(section)`: UI metadata only (no effect on playback)

### Section Metadata vs Playback

**IMPORTANT DISTINCTION**: Section functions are **UI metadata only**. Playback is controlled by the native playback region:

```cpp
void set_current_section(int section) {
    // Update metadata only; playback is driven by g_playback_region
    g_current_section = section;
    g_section_start_step = g_current_section * g_steps_per_section;
    
    // NO PLAYBACK INTERRUPTION - audio continues smoothly
    prnt("ℹ️ [SECTION] Meta set current section to %d. Playback unaffected.", section);
}
```

**Benefits**:
- No audio artifacts at section boundaries
- Smooth continuous playback across all sections
- Section UI updates don't interrupt audio flow

## Flutter State Management

### Terminology
- We call vertical layers in the UI "sound grids" (a.k.a. layers). Each section contains one or more sound grids. Each sound grid is a 2D grid (rows × columns) flattened into a `List<int?>`.

### Single Source of Truth
```dart
// Authoritative per-section store: section → list of sound grids → flattened cells
Map<int, List<List<int?>>> _sectionGridData;

// View binding: reference to the current section's sound grids (no copying)
List<List<int?>> _soundGridSamples; // points to _sectionGridData[_currentSectionIndex]

// Section settings
int _currentSectionIndex = 0;
List<int> _sectionLoopCounts = [1];
SectionPlaybackMode _sectionPlaybackMode = SectionPlaybackMode.loop;
```

Key idea: `_sectionGridData` is the only owner of section grid data. `_soundGridSamples` is just a reference to the current section's lists for convenience. No cloning on section changes.

### Section Switching Process (UI-only)
1. **Update**: set `_currentSectionIndex`
2. **Rebind**: set `_soundGridSamples = _sectionGridData[_currentSectionIndex]`
3. **Interface**: notify UI to redraw

Notes:
- No save/load or data copying during switches
- No native calls on switch while playing; audio is independent

### Song Mode UI Tracking (Flutter)

UI computes current section from native absolute step. In loop mode, Flutter also updates the native playback region whenever the visible section or `gridRows` changes:

```dart
// During playback polling:
final absoluteStep = sequencerLibrary.currentStep;

if (sectionPlaybackMode == SectionPlaybackMode.song) {
    // Compute current section from absolute step
    final currentSectionFromAbsoluteStep = absoluteStep ~/ gridRows;
    
    // Update UI if section changed
    if (currentSectionFromAbsoluteStep != currentSectionIndex) {
        currentSectionIndex = currentSectionFromAbsoluteStep;
        notifyListeners(); // Update section display
    }
}
```

**Benefits**:
- Section display always matches actual playback position
- No timing-dependent wrap-around detection
- Immediate UI updates during song mode progression
- Simpler, more reliable logic

### Sample Placement
- Edits update the backing store directly: `_sectionGridData[_currentSectionIndex][gridIndex][row*cols + col]`
- Native mapping uses absolute indices:
  - `absoluteStep = (sectionIndex * gridRows) + row`
  - `absoluteColumn = (gridIndex * gridColumns) + col`
- Full sync sends all sections to native as one continuous table
- Individual cell changes send immediate absolute updates

## Key Behaviors

### Section Navigation
- **Manual Navigation**: Left/Right arrows navigate between sections (UI only)
- **Automatic Navigation**: In song mode, UI follows playback automatically
- **During Playback**: Manual navigation changes UI view but doesn't interrupt audio
- **Auto-save**: Grid changes saved automatically per section

### Section Creation
- **Trigger**: Right arrow on last section opens creation overlay
- **Blank sections**: Start with empty grid, default 1 loop
- **Copied sections**: Inherit loop count, independent grid data
- **Auto-switch**: Automatically switch to newly created section
- **Native Update**: Total section count updated for song length calculation

### Playback Integration

- **Loop Mode**
  - **Flutter**: Sets region to `[sectionStart, sectionStart + gridRows)` and updates it when section/grid size changes
  - **Native**: Wraps to `region.start` when reaching `region.end`
  - **UI**: Section display remains static; navigation changes view only

- **Song Mode**
  - **Flutter**: Sets steps length to `numSections * gridRows` and region to `[0, stepsLen)`
  - **Native**: Stops automatically at `region.end`
  - **UI**: Section display advances automatically with playback

## Error Handling
- **Bounds checking**: UI validates section indices; native clamps playback region and steps length
- **Playback isolation**: UI navigation errors don't affect audio playback
- **Fallback behavior**: Empty grid returned if section data missing

## Performance and Consistency

### Improvements
1. **Single Source of Truth**: No more save/load churn on switches, fewer bugs
2. **Continuous Audio**: Seamless playback across sections
3. **Responsive UI**: UI follows playback via absolute step computation
4. **Simplified Logic**: UI-only switches; native independent from UI

### Current Limitations and Next Steps
- Rows per section are currently global (`gridRows`). To support truly independent per-section sizes, introduce per-section row counts in Flutter and per-section step lengths natively.

This architecture provides professional-quality song mode playback while maintaining the flexibility of individual section editing and preview. 