# Sample Bank Slot Usage

## Architecture: 26 Total Slots

### Breakdown
- **Slots 0-24** (A-Y): **25 user-accessible slots** → 5 bars × 5 samples in UI
- **Slot 25** (Z): **Reserved for preview functionality** (hidden from UI)

## Preview Slot Purpose

**Location**: `app/lib/state/sequencer/sample_browser.dart`

```dart
// Preview slot constant - use slot 25 (Z) as dedicated preview slot
static const int _previewSlot = 25;

/// Preview a sample by loading it temporarily into preview slot and playing it
/// Similar to how sound settings preview works
Future<void> previewSample(SampleItem item, SampleBankState sampleBankState, PlaybackState playbackState) async {
  // Stop any existing preview first
  playbackState.stopPreview();
  
  // If same sample is already loaded in preview slot, just play it
  if (_previewSampleId == item.sampleId && sampleBankState.isSlotLoaded(_previewSlot)) {
    playbackState.previewSampleSlot(_previewSlot, pitchRatio: 1.0, volume01: 1.0);
    return;
  }
  
  // Load sample into preview slot
  final success = await sampleBankState.loadSample(_previewSlot, item.sampleId!);
  
  if (success) {
    _previewSampleId = item.sampleId;
    await Future.delayed(const Duration(milliseconds: 50));
    playbackState.previewSampleSlot(_previewSlot, pitchRatio: 1.0, volume01: 1.0);
  }
}
```

## Why Preview Needs a Dedicated Slot

When users browse samples in the sample browser, they can:
1. **Tap a sample** to preview it before loading
2. The preview slot (Z) temporarily loads the sample
3. The sample plays so the user can hear it
4. User can then decide to load it into a real slot (A-Y) or skip it

This way:
- User slots (A-Y) remain unchanged during preview
- Multiple samples can be previewed without losing user's work
- Preview slot is automatically reused for each new preview

## Current UI Layout

### Sequencer V2 Sample Bank Widget
**Location**: `app/lib/widgets/sequencer/v2/sample_banks_widget.dart`

The UI shows **scrollable sample slots** with left/right arrows:
- Typically shows 5-7 slots at a time (responsive, depending on screen width)
- User can scroll through all 25 slots (A-Y) using arrow buttons
- Slot Z (25) is never shown in the UI (internal use only for preview)
- **Layout**: 5 visual bars × 5 samples = 25 accessible slots

### Projects Screen Preview
**Location**: `app/lib/screens/projects_screen.dart`

Shows mini sample bank preview:
- Currently configured to show all loaded slots
- Uses `max_slots` from snapshot data (26)
- Displays only the first 16-25 slots in practice

## Changes Made

### Before
- UI showed only **16 slots** (A-P)
- This limited users to roughly 3 bars × 5 samples

### After  
- UI now shows **25 slots** (A-Y)
- Users can access 5 bars × 5 samples as desired
- Scrollable with arrow buttons for smaller screens

### Files Modified
1. **`app/lib/widgets/sequencer/v2/sample_banks_widget.dart`**
   - Changed `clamp(1, 16)` to `clamp(1, 25)` on line 51
   - Changed max index from 16 to 25 on lines 57-59
   - Added comments explaining A-Y vs Z slot usage

## Keep 26 Slots in Native/Schema

**DO NOT** reduce to 25 slots in native code or schemas because:
1. ✅ Slot 25 (Z) is **actively used** for sample preview functionality
2. ✅ Native layer (`sample_bank.h`): `MAX_SAMPLE_SLOTS = 26`
3. ✅ Schema (`sample_bank.json`): `max_slots: 26`, `samples: minItems/maxItems: 26`
4. ✅ Flutter state (`sample_bank.dart`): `maxSampleSlots = 26`
5. ⚠️ Removing slot Z would **break** sample browser preview

## Summary

Your desired layout is now implemented:
- **User-visible slots**: 25 (A-Y) = 5 bars × 5 samples ✅
- **Hidden preview slot**: 1 (Z) for sample browser (unchanged)
- **Total capacity**: 26 slots (unchanged)
- **UI change**: Now displays 25 slots instead of 16 ✅

