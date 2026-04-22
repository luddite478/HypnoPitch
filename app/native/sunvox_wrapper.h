#ifndef SUNVOX_WRAPPER_H
#define SUNVOX_WRAPPER_H

// Simple wrapper around SunVox library for our playback engine
// Maps our table-based sequencer to SunVox patterns and modules

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Initialize SunVox engine (called from playback_init)
// Returns 0 on success, negative on error
int sunvox_wrapper_init(void);

// Cleanup SunVox engine (called from playback_cleanup)
void sunvox_wrapper_cleanup(void);

// Load a sample into a SunVox sampler module
// sample_slot: 0..MAX_SAMPLE_SLOTS-1
// file_path: path to audio file
// Returns 0 on success, negative on error
int sunvox_wrapper_load_sample(int sample_slot, const char* file_path);

// Unload a sample from a SunVox sampler module
void sunvox_wrapper_unload_sample(int sample_slot);

// Create a pattern for a section
// Returns 0 on success, negative on error
int sunvox_wrapper_create_section_pattern(int section_index, int section_length);

// Remove a pattern for a section
void sunvox_wrapper_remove_section_pattern(int section_index);

// Reset ALL SunVox patterns (used before import to ensure clean state)
__attribute__((visibility("default"))) __attribute__((used))
void sunvox_wrapper_reset_all_patterns(void);

// Sync entire section to its SunVox patter
__attribute__((visibility("default"))) __attribute__((used))
void sunvox_wrapper_sync_section(int section_index);

// Sync single cell to SunVox pattern
// Called when a single cell changes
void sunvox_wrapper_sync_cell(int step, int col);

// Set playback mode (updates timeline accordingly)
// current_loop: which loop to use in loop mode (0 = first loop, 1 = second, etc.)
void sunvox_wrapper_set_playback_mode(int song_mode, int current_section, int current_loop);

// Update the timeline/playback order of sections (uses internally stored mode)
void sunvox_wrapper_update_timeline(void);

// Seamless timeline update for pattern size changes (add/remove steps)
// This updates pattern X positions WITHOUT stopping playback
// section_index: which section was resized (for loop mode refresh)
__attribute__((visibility("default"))) __attribute__((used))
void sunvox_wrapper_update_timeline_seamless(int section_index);

// Seamless section reordering (called after table_reorder_section)
// Updates timeline and preserves playback position
__attribute__((visibility("default"))) __attribute__((used))
void sunvox_wrapper_reorder_section(int from_index, int to_index);

// Start playback
// Returns 0 on success, negative on error
int sunvox_wrapper_play(void);

// Stop playback
void sunvox_wrapper_stop(void);

// Set BPM
void sunvox_wrapper_set_bpm(int bpm);

// Set playback region (loop range)
// start: inclusive start step
// end: exclusive end step
void sunvox_wrapper_set_region(int start, int end);

// Get current playback line/step
// Returns current line number or -1 if not playing
int sunvox_wrapper_get_current_line(void);

// Get pattern X position for a section (for calculating local position in loop mode)
// Returns X position in timeline or 0 if pattern doesn't exist
int sunvox_wrapper_get_section_pattern_x(int section_index);

// Trigger notes at a specific step (used when starting playback mid-song)
// This manually triggers all notes at the given step
void sunvox_wrapper_trigger_step(int step);

// Render audio frames (called from audio callback)
// buf: output buffer (stereo float32 interleaved)
// frames: number of frames to render
// Returns 1 if audio rendered, 0 if silence
int sunvox_wrapper_render(float* buf, int frames);

// Check if SunVox is initialized
int sunvox_wrapper_is_initialized(void);

// Master bus reverb wet (0..1). No-op if engine not ready.
void sunvox_wrapper_set_master_reverb(float wet01);

// Apply section-layer reverb params (room/damp) and set send level from the
// table. Used for stopped/initial state changes; section switches during
// playback should go through sunvox_wrapper_on_section_switch instead so the
// send + layer volume are crossfaded from their real current values.
void sunvox_wrapper_apply_section_layer_reverb(int section_index);
void sunvox_wrapper_apply_section_layer_eq(int section_index);
void sunvox_wrapper_apply_section_layer_volume(int section_index);
void sunvox_wrapper_on_section_switch(int prev_section, int next_section);

// Playback bridge (Dart FFI): per-section layer output volume (0.0..1.0). Implemented in playback_sunvox.mm.
__attribute__((visibility("default"))) __attribute__((used))
void playback_set_section_layer_volume(int section, int layer, float volume01);

__attribute__((visibility("default"))) __attribute__((used))
float playback_get_section_layer_volume(int section, int layer);

// Master 3-band EQ: band 0=Low, 1=Mid, 2=High; gain 0..512 (256 = unity).
void sunvox_wrapper_set_master_eq_band(int band, int gain_0_512);

// Debug: Dump all pattern information
void sunvox_wrapper_debug_dump_patterns(const char* context);

int sunvox_wrapper_get_pattern_current_loop(int section_index);

// Live preview (SunVox-based)
// Play/stop preview for a sample slot or specific cell without altering patterns
int sunvox_preview_slot(int slot, float pitch, float volume);
int sunvox_preview_cell(int step, int column, float pitch, float volume);
void sunvox_preview_stop(void);

// NOTE: Microphone Input module functions removed - mic recording now bypasses SunVox entirely
// Mic audio is captured directly to WAV file without going through SunVox
// See docs/features/microphone_dual_output_architecture.md for archived approach

// Wrapper for SunVox sv_get_module_scope2 (for waveform visualization)
// Get audio scope data from a specific module
// Returns: number of samples returned
__attribute__((visibility("default"))) __attribute__((used))
uint32_t sunvox_wrapper_get_module_scope2(int slot, int mod_num, int channel, int16_t* dest_buf, uint32_t samples_to_read);

// Set pattern event with sample offset (for precise positioning)
// Uses SunVox 09xx (coarse) and 07xx (fine) offset effects for sub-step precision
// Note: sample_slot parameter (not module ID) - looks up module internally
__attribute__((visibility("default"))) __attribute__((used))
void sunvox_wrapper_set_pattern_event_with_offset(
    int pat_id, int track, int line, int note, int velocity, 
    int sample_slot, int offset_frames
);

#ifdef __cplusplus
}
#endif

#endif // SUNVOX_WRAPPER_H


