#ifndef SAMPLE_BANK_H
#define SAMPLE_BANK_H

#ifdef __cplusplus
extern "C" {
#endif

// Constants
#define MAX_SAMPLE_SLOTS 101  // 100 user slots + 1 preview slot
#define SAMPLE_MAX_PATH 512
#define SAMPLE_MAX_NAME 128
#define SAMPLE_MAX_ID   128

// Forward declarations
struct ma_decoder;

// Sample audio settings
typedef struct {
    float volume;                       // 0.0 to 1.0 (default: 1.0)
    float pitch;                        // 0.25 to 4.0 (default: 1.0, 2 octaves down/up)
} SampleSettings;

// Core sample data structure (POD - no heap pointers)
typedef struct {
    int loaded;                         // 0 = empty, 1 = loaded
    SampleSettings settings;            // audio settings
    int is_processing;                  // 1 while preprocessing job(s) active for this sample
    char sample_id[SAMPLE_MAX_ID];      // Stable ID for the sample (optional)
    char file_path[SAMPLE_MAX_PATH];    // Path to sample file (empty string if none)
    char display_name[SAMPLE_MAX_NAME]; // Display name for UI (empty string if none)
    int offset_frames;                  // Sample offset in frames (for precise positioning)
} Sample;

// Single live sample bank state (authoritative)
typedef struct {
    // FFI-visible prefix (read directly by Dart)
    unsigned int version;       // even=stable, odd=write in progress
    int max_slots;              // number of available sample slots
    int loaded_count;           // number of slots currently loaded
    Sample* samples_ptr;        // direct pointer to samples array (&samples[0])

    // Canonical storage
    Sample samples[MAX_SAMPLE_SLOTS];
} SampleBankState;

// Sample management
__attribute__((visibility("default"))) __attribute__((used))
void sample_bank_init(void);
__attribute__((visibility("default"))) __attribute__((used))
void sample_bank_cleanup(void);
__attribute__((visibility("default"))) __attribute__((used))
int sample_bank_load(int slot, const char* file_path);
__attribute__((visibility("default"))) __attribute__((used))
int sample_bank_load_with_id(int slot, const char* file_path, const char* sample_id);
__attribute__((visibility("default"))) __attribute__((used))
void sample_bank_unload(int slot);
__attribute__((visibility("default"))) __attribute__((used))
int sample_bank_play(int slot);
__attribute__((visibility("default"))) __attribute__((used))
void sample_bank_stop(int slot);
__attribute__((visibility("default"))) __attribute__((used))
int sample_bank_is_loaded(int slot);
__attribute__((visibility("default"))) __attribute__((used))
const char* sample_bank_get_file_path(int slot);
__attribute__((visibility("default"))) __attribute__((used))
struct ma_decoder* sample_bank_get_decoder(int slot);

// Direct sample access 
__attribute__((visibility("default"))) __attribute__((used))
Sample* sample_bank_get_sample(int slot);
__attribute__((visibility("default"))) __attribute__((used))
void sample_bank_set_sample_volume(int slot, float volume);
__attribute__((visibility("default"))) __attribute__((used))
void sample_bank_set_sample_pitch(int slot, float pitch);

// New unified settings setter
__attribute__((visibility("default"))) __attribute__((used))
void sample_bank_set_sample_settings(int slot, float volume, float pitch);

// For FFI
__attribute__((visibility("default"))) __attribute__((used))
int sample_bank_get_max_slots(void);

// Expose pointer to sample bank state (prefix-mapped by Dart)
__attribute__((visibility("default"))) __attribute__((used))
const SampleBankState* sample_bank_get_state_ptr(void);

// Accessor mirroring table_state_get_ptr/playback_state_get_ptr
__attribute__((visibility("default"))) __attribute__((used))
const SampleBankState* sample_bank_state_get_ptr(void);

// Unified naming to mirror table_apply_state
__attribute__((visibility("default"))) __attribute__((used))
void sample_bank_apply_state(const SampleBankState* state);

// Internal apply mode hook:
// when enabled, setters avoid expensive table-wide rescan/sync and undo recording.
__attribute__((visibility("default"))) __attribute__((used))
void sample_bank_set_apply_mode(int enabled);

// Processing state hooks used by pitch module
__attribute__((visibility("default"))) __attribute__((used))
void sample_bank_set_processing(int slot, int processing);


#ifdef __cplusplus
}
#endif

#endif // SAMPLE_BANK_H
