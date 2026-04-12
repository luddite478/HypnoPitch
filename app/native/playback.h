#ifndef PLAYBACK_H
#define PLAYBACK_H

#include <stdint.h>
#include "table.h"

#ifdef __cplusplus
extern "C" {
#endif

// Constants for playback
#define SAMPLE_RATE 48000
#define CHANNELS 2
#define DEFAULT_VOLUME_RISE_TIME_MS 6.0f      // Default 6ms fade-in time
#define DEFAULT_VOLUME_FALL_TIME_MS 12.0f     // Default 12ms fade-out time  
#define MIN_VOLUME_SMOOTHING_MS 1.0f          // Min 1ms
#define MAX_VOLUME_SMOOTHING_MS 100.0f        // Max 100ms
#define VOLUME_THRESHOLD 0.0001f              // Convergence threshold
#define DEFAULT_SECTION_LOOPS 4
#define MIN_SECTION_LOOPS 1
#define MAX_SECTION_LOOPS 1024
#define MA_NODES_PER_COLUMN 2
#define MIN_BPM 1
#define MAX_BPM 300

// RAM preloading configuration
#define PRELOAD_HEAD_SIZE_SEC 1.5f                     // Load 1.5s head (or full sample if shorter)
#define PRELOAD_MIN_HEAD_FRAMES (SAMPLE_RATE / 4)      // Minimum 250ms (12000 frames @ 48kHz)
#define PRELOAD_MAX_TOTAL_MEMORY (100 * 1024 * 1024)   // 100 MB safety limit

// A/B Node structure for smooth switching
typedef struct {
    int column;
    int index;                      // 0=A, 1=B
    int node_initialized;           // 1 when miniaudio node is created
    int sample_slot;                // Which sample this node plays (-1 = none)
    
    // RAM-based resources (NEW)
    float* pcm_buffer;              // Decoded PCM frames (owned, transferred from preloader)
    uint64_t buffer_frame_count;    // Number of frames in pcm_buffer
    void* audio_buffer;             // ma_audio_buffer* (RAM-backed data source)
    int audio_buffer_initialized;   // 1 when using RAM buffer
    
    // Legacy file-based resources (fallback path)
    void* decoder;                  // ma_decoder* (cast to void* for C compatibility)
    void* node;                     // ma_data_source_node* (cast to void* for C compatibility)
    void* pitch_ds;                 // ma_pitch_data_source* (cast to void*)
    int pitch_ds_initialized;       // 1 when pitch data source is initialized
    float pitch;                    // Current pitch ratio
    
    // Volume smoothing
    float user_volume;              // User volume setting (from cell)
    float current_volume;           // Real actual volume (for smoothing)
    float target_volume;            // Target volume we're smoothing towards
    float volume_rise_coeff;        // Smoothing coefficient for fade-in
    float volume_fall_coeff;        // Smoothing coefficient for fade-out
    
    uint64_t id;                    // Unique identifier
} AudioColumnNode;

// A/B node switching for smooth playback (used on audio thread)
typedef struct {
    AudioColumnNode nodes[2];       // A and B nodes
    int active_node;                // 0=A, 1=B, -1=none
    int next_node;                  // Which node to use next
} ColumnPlayback;

// Preloader state for preparing next step resources (used on preloader thread)
typedef struct {
    int target_step;                // step index of prepared resources
    int ready;                      // 0/1 prepared and ready for transfer
    int consuming;                  // 0/1 audio thread is consuming resources (don't cleanup)
    int sample_slot;                // prepared sample slot
    float volume;                   // prepared volume
    float pitch;                    // prepared pitch
    
    // RAM-based resources (NEW)
    float* pcm_buffer;              // Decoded PCM frames (owned by preloader until transfer)
    uint64_t buffer_frame_count;    // Number of frames in pcm_buffer
    void* audio_buffer;             // ma_audio_buffer* (RAM-backed data source)
    int audio_buffer_initialized;   // 1 when audio_buffer is ready
    
    // Legacy file-based resources (fallback path - kept for compatibility)
    void* decoder;                  // ma_decoder*
    void* pitch_ds;                 // ma_pitch_data_source*
    int   pitch_ds_initialized;     // 0/1
} ColumnPreloader;

// Complete column controller combining playback and preloading
typedef struct {
    ColumnPlayback* playback;       // reference to A/B playback nodes
    ColumnPreloader preloader;      // preloaded resources for next step
} AudioColumn;

// Playback region
// typedef struct {
//     int start;
//     int end;                        // exclusive
// } PlaybackRegion;

// Single live playback state (authoritative)
typedef struct {
    // FFI-visible prefix (read directly by Dart)
    uint32_t version;               // even=stable, odd=writer in progress
    int is_playing;                 // 0/1
    int current_step;               // current sequencer step
    int bpm;                        // current BPM
    int region_start;               // inclusive start of playback region
    int region_end;                 // exclusive end of playback region
    int song_mode;                  // 0=loop, 1=song
    int* sections_loops_num;        // &sections_loops_num_storage[0]
    int current_section;            // current section being played
    int current_section_loop;       // current loop within section (0-based)

    // Canonical storage
    int sections_loops_num_storage[MAX_SECTIONS];
} PlaybackState;

// Playback initialization and cleanup
__attribute__((visibility("default"))) __attribute__((used))
int playback_init(void);

__attribute__((visibility("default"))) __attribute__((used))
void playback_cleanup(void);

// Playback control
__attribute__((visibility("default"))) __attribute__((used))
int playback_start(int bpm, int start_step);

__attribute__((visibility("default"))) __attribute__((used))
void playback_stop(void);

// Playback settings
__attribute__((visibility("default"))) __attribute__((used))
void playback_set_bpm(int bpm);

__attribute__((visibility("default"))) __attribute__((used))
void playback_set_region(int start, int end);

__attribute__((visibility("default"))) __attribute__((used))
void playback_set_mode(int song_mode);

// Section loops management
__attribute__((visibility("default"))) __attribute__((used))
void playback_set_section_loops_num(int section, int loops);

// Section switching helper (stops and restarts playback at section start if needed)
__attribute__((visibility("default"))) __attribute__((used))
void switch_to_section(int section_index);

// Explicit switch modes
__attribute__((visibility("default"))) __attribute__((used))
void switch_to_section_immediate(int section_index);

__attribute__((visibility("default"))) __attribute__((used))
void switch_to_section_seamless_song_mode(int section_index);

// Per-section, per-layer reverb controls (0.0..1.0 normalized).
__attribute__((visibility("default"))) __attribute__((used))
void playback_set_section_layer_reverb(int section, int layer, float send01, float room01, float damp01);

__attribute__((visibility("default"))) __attribute__((used))
float playback_get_section_layer_reverb_send(int section, int layer);

__attribute__((visibility("default"))) __attribute__((used))
float playback_get_section_layer_reverb_room(int section, int layer);

__attribute__((visibility("default"))) __attribute__((used))
float playback_get_section_layer_reverb_damp(int section, int layer);

// Per-section, per-layer EQ: band 0=Low, 1=Mid, 2=High; db in [-12, +6] (same range as master EQ UI).
__attribute__((visibility("default"))) __attribute__((used))
void playback_set_section_layer_eq_band(int section, int layer, int band, int db);

__attribute__((visibility("default"))) __attribute__((used))
int playback_get_section_layer_eq_band_db(int section, int layer, int band);

// Per-section, per-layer output volume (0.0..1.0), after layer EQ.
__attribute__((visibility("default"))) __attribute__((used))
void playback_set_section_layer_volume(int section, int layer, float volume01);

__attribute__((visibility("default"))) __attribute__((used))
float playback_get_section_layer_volume(int section, int layer);

// Master volume control (0.0 .. 1.0)
__attribute__((visibility("default"))) __attribute__((used))
void playback_set_master_volume(float volume01);

// Master bus reverb wet (0.0 .. 1.0)
__attribute__((visibility("default"))) __attribute__((used))
void playback_set_master_reverb(float wet01);

// Master EQ: band 0..2, gain 0..512 (256 = unity)
__attribute__((visibility("default"))) __attribute__((used))
void playback_set_master_eq_band(int band, int gain_0_512);

// Enhanced playback logging (for debugging)
__attribute__((visibility("default"))) __attribute__((used))
void playback_set_enhanced_logging(int enabled);

// NOTE: sv_audio_callback2 bypass functions removed - mic bypasses SunVox entirely now

// Volume smoothing configuration
__attribute__((visibility("default"))) __attribute__((used))
void playback_set_smoothing_rise_time(float ms);

__attribute__((visibility("default"))) __attribute__((used))
void playback_set_smoothing_fall_time(float ms);

__attribute__((visibility("default"))) __attribute__((used))
float playback_get_smoothing_rise_time(void);

__attribute__((visibility("default"))) __attribute__((used))
float playback_get_smoothing_fall_time(void);

// Return a stable pointer to the native PlaybackState struct (prefix-mapped)
__attribute__((visibility("default"))) __attribute__((used))
const PlaybackState* playback_get_state_ptr(void);

// Accessor for full live playback state (snapshot-friendly)
__attribute__((visibility("default"))) __attribute__((used))
const PlaybackState* playback_state_get_ptr(void);

// Unified state API
__attribute__((visibility("default"))) __attribute__((used))
void playback_apply_state(const PlaybackState* state);

// Accessor to global node graph for auxiliary modules (e.g., preview)
__attribute__((visibility("default"))) __attribute__((used))
struct ma_node_graph* playback_get_node_graph(void);

// Components-based apply removed in favor of unified state snapshot

// Sample bank functions (forward declarations)
__attribute__((visibility("default"))) __attribute__((used))
int sample_bank_load(int slot, const char* file_path);

__attribute__((visibility("default"))) __attribute__((used))
void sample_bank_unload(int slot);

__attribute__((visibility("default"))) __attribute__((used))
int sample_bank_is_loaded(int slot);

__attribute__((visibility("default"))) __attribute__((used))
const char* sample_bank_get_file_path(int slot);

// Forward declarations for pitched file management (implemented in pitch.mm)
const char* pitch_get_file_path(int sample_slot, float pitch);
int pitch_generate_file(int sample_slot, float pitch, const char* output_path);
void pitch_delete_file(int sample_slot, float pitch);
void pitch_delete_all_files_for_sample(int sample_slot);

// Output recording (WAV) control
__attribute__((visibility("default"))) __attribute__((used))
int recording_start(const char* file_path);

__attribute__((visibility("default"))) __attribute__((used))
void recording_stop(void);

__attribute__((visibility("default"))) __attribute__((used))
int recording_is_active(void);

// NOTE: Mic-only recording functions removed - mic recording now writes raw mic directly to WAV
// See docs/features/microphone_dual_output_architecture.md for archived approach

#ifdef __cplusplus
}
#endif

#endif // PLAYBACK_H
