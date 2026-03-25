#include "sample_bank.h"
#include "sunvox_wrapper.h"  // For SunVox integration
#include "table.h"
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

// Platform-specific logging
#ifdef __APPLE__
    #include "log.h"
    #undef LOG_TAG
    #define LOG_TAG "SAMPLE_BANK"
#elif defined(__ANDROID__)
    #include "log.h"
    #undef LOG_TAG
    #define LOG_TAG "SAMPLE_BANK"
#else
    #include "log.h"
    #undef LOG_TAG
    #define LOG_TAG "SAMPLE_BANK"
#endif

// Only include miniaudio as a header here (implementation lives elsewhere)
#include "miniaudio/miniaudio.h"
#include "undo_redo.h"

// Unified state (authoritative) and decoders
static SampleBankState g_sample_bank_state;   // single source of truth
static ma_decoder g_sample_decoders[MAX_SAMPLE_SLOTS];
// During snapshot-apply we suppress expensive rescan/sync in setters.
static int g_sample_bank_apply_mode = 0;

static inline void state_write_begin() { g_sample_bank_state.version++; }
static inline void state_write_end()   { g_sample_bank_state.version++; }
static inline void state_recompute_prefix() {
    g_sample_bank_state.max_slots = MAX_SAMPLE_SLOTS;
    g_sample_bank_state.samples_ptr = &g_sample_bank_state.samples[0];
    int loadedCount = 0;
    for (int i = 0; i < MAX_SAMPLE_SLOTS; i++) {
        if (g_sample_bank_state.samples[i].loaded) loadedCount++;
    }
    g_sample_bank_state.loaded_count = loadedCount;
}

#ifdef __cplusplus
extern "C" {
#endif

void sample_bank_init(void) {
    sample_bank_cleanup();
    
    for (int i = 0; i < MAX_SAMPLE_SLOTS; i++) {
        g_sample_bank_state.samples[i].loaded = 0;
        g_sample_bank_state.samples[i].settings.volume = 1.0f;
        g_sample_bank_state.samples[i].settings.pitch = 1.0f;
        g_sample_bank_state.samples[i].is_processing = 0;
        g_sample_bank_state.samples[i].file_path[0] = '\0';
        g_sample_bank_state.samples[i].display_name[0] = '\0';
        g_sample_bank_state.samples[i].sample_id[0] = '\0';
        g_sample_bank_state.samples[i].offset_frames = 0;
        memset(&g_sample_decoders[i], 0, sizeof(ma_decoder));
    }
    prnt("✅ [SAMPLE_BANK] Initialized with %d slots", MAX_SAMPLE_SLOTS);

    // Initialize FFI-visible prefix
    g_sample_bank_state.version = 0;
    state_write_begin();
    state_recompute_prefix();
    state_write_end();
    // Do not seed undo/redo baseline here; a single baseline is recorded after all modules init
}

void sample_bank_cleanup(void) {
    for (int i = 0; i < MAX_SAMPLE_SLOTS; i++) {
        if (g_sample_bank_state.samples[i].loaded) {
            sample_bank_unload(i);
        }
    }
    prnt("🧹 [SAMPLE_BANK] Cleanup complete");
}

int sample_bank_load(int slot, const char* file_path) {
    if (slot < 0 || slot >= MAX_SAMPLE_SLOTS) {
        prnt_err("❌ [SAMPLE_BANK] Invalid slot: %d", slot);
        return -1;
    }

    if (!file_path) {
        prnt_err("❌ [SAMPLE_BANK] Null file path for slot %d", slot);
        return -1;
    }

    prnt_debug("📂 [SAMPLE_BANK] Loading sample into slot %d: %s", slot, file_path);

    // Unload existing sample if any
    if (g_sample_bank_state.samples[slot].loaded) {
        sample_bank_unload(slot);
    }

    // Initialize decoder for this sample
    ma_result result = ma_decoder_init_file(file_path, NULL, &g_sample_decoders[slot]);
    if (result != MA_SUCCESS) {
        prnt_err("❌ [SAMPLE_BANK] Failed to initialize decoder for %s: %d", file_path, result);
        return -1;
    }

    // Store the file path and extract display name
    strncpy(g_sample_bank_state.samples[slot].file_path, file_path, SAMPLE_MAX_PATH - 1);
    g_sample_bank_state.samples[slot].file_path[SAMPLE_MAX_PATH - 1] = '\0';

    const char* filename = strrchr(file_path, '/');
    filename = filename ? filename + 1 : file_path;
    strncpy(g_sample_bank_state.samples[slot].display_name, filename, SAMPLE_MAX_NAME - 1);
    g_sample_bank_state.samples[slot].display_name[SAMPLE_MAX_NAME - 1] = '\0';

    // Update state
    g_sample_bank_state.samples[slot].loaded = 1;
    g_sample_bank_state.samples[slot].settings.volume = 1.0f;
    g_sample_bank_state.samples[slot].settings.pitch = 1.0f;
    g_sample_bank_state.samples[slot].is_processing = 0;

    prnt("✅ [SAMPLE_BANK] Sample loaded in slot %d: %s", slot, file_path);

    // Load into SunVox sampler module
    if (sunvox_wrapper_is_initialized()) {
        sunvox_wrapper_load_sample(slot, file_path);
    }

    // Update FFI-visible prefix
    state_write_begin();
    state_recompute_prefix();
    state_write_end();
    if (!g_sample_bank_apply_mode) {
        UndoRedoManager_record();
    }
    return 0;
}

int sample_bank_load_with_id(int slot, const char* file_path, const char* sample_id) {
    int result = sample_bank_load(slot, file_path);
    if (result != 0) {
        return result;
    }

    if (sample_id && sample_id[0] != '\0') {
        strncpy(g_sample_bank_state.samples[slot].sample_id, sample_id, SAMPLE_MAX_ID - 1);
        g_sample_bank_state.samples[slot].sample_id[SAMPLE_MAX_ID - 1] = '\0';
    }

    state_write_begin();
    state_recompute_prefix();
    state_write_end();
    // Intentionally do NOT record again to avoid duplicate undo step
    return 0;
}

void sample_bank_unload(int slot) {
    if (slot < 0 || slot >= MAX_SAMPLE_SLOTS) {
        prnt_err("❌ [SAMPLE_BANK] Invalid slot: %d", slot);
        return;
    }

    if (!g_sample_bank_state.samples[slot].loaded) {
        return; // Already unloaded
    }

    prnt_debug("🗑️ [SAMPLE_BANK] Unloading sample from slot %d", slot);

    // Unload from SunVox sampler module
    if (sunvox_wrapper_is_initialized()) {
        sunvox_wrapper_unload_sample(slot);
    }

    // Uninitialize decoder
    ma_decoder_uninit(&g_sample_decoders[slot]);

    // Clear state
    g_sample_bank_state.samples[slot].loaded = 0;
    g_sample_bank_state.samples[slot].settings.volume = 1.0f;
    g_sample_bank_state.samples[slot].settings.pitch = 1.0f;
    g_sample_bank_state.samples[slot].is_processing = 0;
    g_sample_bank_state.samples[slot].file_path[0] = '\0';
    g_sample_bank_state.samples[slot].display_name[0] = '\0';
    g_sample_bank_state.samples[slot].sample_id[0] = '\0';
    g_sample_bank_state.samples[slot].offset_frames = 0;

    prnt("✅ [SAMPLE_BANK] Sample unloaded from slot %d", slot);

    // Update FFI-visible prefix
    state_write_begin();
    state_recompute_prefix();
    state_write_end();
    if (!g_sample_bank_apply_mode) {
        UndoRedoManager_record();
    }
}

int sample_bank_play(int slot) {
    if (slot < 0 || slot >= MAX_SAMPLE_SLOTS) {
        prnt_err("❌ [SAMPLE_BANK] Invalid slot: %d", slot);
        return -1;
    }

    if (!g_sample_bank_state.samples[slot].loaded) {
        prnt_err("❌ [SAMPLE_BANK] No sample loaded in slot %d", slot);
        return -1;
    }

    prnt("▶️ [SAMPLE_BANK] Playing sample from slot %d", slot);

    // For preview - separate preview playback system can be implemented later
    return 0;
}

void sample_bank_stop(int slot) {
    if (slot < 0 || slot >= MAX_SAMPLE_SLOTS) {
        prnt_err("❌ [SAMPLE_BANK] Invalid slot: %d", slot);
        return;
    }

    prnt_debug("⏹️ [SAMPLE_BANK] Stopping sample preview for slot %d", slot);
}

int sample_bank_is_loaded(int slot) {
    if (slot < 0 || slot >= MAX_SAMPLE_SLOTS) {
        return 0;
    }

    return g_sample_bank_state.samples[slot].loaded;
}

const char* sample_bank_get_file_path(int slot) {
    if (slot < 0 || slot >= MAX_SAMPLE_SLOTS || !g_sample_bank_state.samples[slot].loaded) {
        return NULL;
    }

    return g_sample_bank_state.samples[slot].file_path;
}

struct ma_decoder* sample_bank_get_decoder(int slot) {
    if (slot < 0 || slot >= MAX_SAMPLE_SLOTS || !g_sample_bank_state.samples[slot].loaded) {
        return NULL;
    }

    return &g_sample_decoders[slot];
}

int sample_bank_get_max_slots(void) {
    return MAX_SAMPLE_SLOTS;
}

Sample* sample_bank_get_sample(int slot) {
    if (slot < 0 || slot >= MAX_SAMPLE_SLOTS) {
        return NULL;
    }

    return &g_sample_bank_state.samples[slot];
}

void sample_bank_set_sample_volume(int slot, float volume) {
    if (slot < 0 || slot >= MAX_SAMPLE_SLOTS || !g_sample_bank_state.samples[slot].loaded) {
        return;
    }
    
    if (volume < 0.0f) volume = 0.0f;
    if (volume > 1.0f) volume = 1.0f;
    
    state_write_begin();
    g_sample_bank_state.samples[slot].settings.volume = volume;
    state_write_end();

    if (!g_sample_bank_apply_mode) {
        // Re-sync all cells using this sample with default volume
        for (int i = 0; i < table_get_max_steps(); i++) {
            for (int j = 0; j < table_get_max_cols(); j++) {
                Cell* cell = table_get_cell(i, j);
                if (cell && cell->sample_slot == slot && cell->settings.volume == DEFAULT_CELL_VOLUME) {
                    sunvox_wrapper_sync_cell(i, j);
                }
            }
        }
        UndoRedoManager_record();
    }
}

void sample_bank_set_sample_pitch(int slot, float pitch) {
    if (slot < 0 || slot >= MAX_SAMPLE_SLOTS || !g_sample_bank_state.samples[slot].loaded) {
        return;
    }
    
    if (pitch < 0.25f) pitch = 0.25f;
    if (pitch > 4.0f) pitch = 4.0f;
    
    state_write_begin();
    g_sample_bank_state.samples[slot].settings.pitch = pitch;
    state_write_end();

    if (!g_sample_bank_apply_mode) {
        // Re-sync all cells using this sample with default pitch
        for (int i = 0; i < table_get_max_steps(); i++) {
            for (int j = 0; j < table_get_max_cols(); j++) {
                Cell* cell = table_get_cell(i, j);
                if (cell && cell->sample_slot == slot && cell->settings.pitch == DEFAULT_CELL_PITCH) {
                    sunvox_wrapper_sync_cell(i, j);
                }
            }
        }
        UndoRedoManager_record();
    }
}

const SampleBankState* sample_bank_get_state_ptr(void) { return &g_sample_bank_state; }

void sample_bank_apply_state(const SampleBankState* s) {
    if (s == NULL) return;
    const int prev_apply_mode = g_sample_bank_apply_mode;
    g_sample_bank_apply_mode = 1;
    // Apply by loading/unloading files and setting params
    for (int i = 0; i < MAX_SAMPLE_SLOTS; i++) {
        int wantLoaded = s->samples[i].loaded;
        const char* path = s->samples[i].file_path;
        int isLoaded = g_sample_bank_state.samples[i].loaded;
        if (wantLoaded && !isLoaded) {
            if (path && path[0] != '\0') {
                sample_bank_load(i, path);
            }
        } else if (!wantLoaded && isLoaded) {
            sample_bank_unload(i);
        }
        if (wantLoaded) {
            sample_bank_set_sample_volume(i, s->samples[i].settings.volume);
            sample_bank_set_sample_pitch(i, s->samples[i].settings.pitch);
        }
    }
    g_sample_bank_apply_mode = prev_apply_mode;
}

void sample_bank_set_sample_settings(int slot, float volume, float pitch) {
    if (slot < 0 || slot >= MAX_SAMPLE_SLOTS || !g_sample_bank_state.samples[slot].loaded) {
        return;
    }

    if (volume < 0.0f) volume = 0.0f;
    if (volume > 1.0f) volume = 1.0f;
    if (pitch < 0.25f) pitch = 0.25f;
    if (pitch > 4.0f) pitch = 4.0f;

    state_write_begin();
    g_sample_bank_state.samples[slot].settings.volume = volume;
    g_sample_bank_state.samples[slot].settings.pitch = pitch;
    state_write_end();

    if (!g_sample_bank_apply_mode) {
        // Re-sync all cells using this sample with default pitch or volume
        for (int i = 0; i < table_get_max_steps(); i++) {
            for (int j = 0; j < table_get_max_cols(); j++) {
                Cell* cell = table_get_cell(i, j);
                if (cell && cell->sample_slot == slot && (cell->settings.pitch == DEFAULT_CELL_PITCH || cell->settings.volume == DEFAULT_CELL_VOLUME)) {
                    sunvox_wrapper_sync_cell(i, j);
                }
            }
        }
        UndoRedoManager_record();
    }
}

const SampleBankState* sample_bank_state_get_ptr(void) {
    return &g_sample_bank_state;
}

void sample_bank_set_apply_mode(int enabled) {
    g_sample_bank_apply_mode = enabled ? 1 : 0;
}

#ifdef __cplusplus
} // extern "C"
#endif

extern "C" void sample_bank_set_processing(int slot, int processing) {
    if (slot < 0 || slot >= MAX_SAMPLE_SLOTS) return;
    g_sample_bank_state.samples[slot].is_processing = processing ? 1 : 0;
}



