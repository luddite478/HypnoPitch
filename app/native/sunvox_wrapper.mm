#include "sunvox_wrapper.h"
#include "table.h"
#include "sample_bank.h"
#include "playback.h"  // For PlaybackState and playback_get_state_ptr
#include <math.h>
#include <unistd.h>

// Platform-specific logging
#ifdef __APPLE__
    #import <Foundation/Foundation.h>  // For NSString, NSFileManager, etc.
    #include "log.h"
    #undef LOG_TAG
    #define LOG_TAG "SUNVOX"
#elif defined(__ANDROID__)
    #include "log.h"
    #undef LOG_TAG
    #define LOG_TAG "SUNVOX"
#else
    #include "log.h"
    #undef LOG_TAG
    #define LOG_TAG "SUNVOX"
#endif

// Use static linking with SunVox library
#define SUNVOX_STATIC_LIB
#include "sunvox.h"

// Forward declare our custom SunVox functions (defined in sunvox_lib.cpp)
extern "C" {
    int sv_pattern_set_flags(int slot, int pat_num, uint32_t flags, int set);
    int sv_enable_supertracks(int slot, int enable);
    int sv_set_pattern_loop(int slot, int pattern_num);  // NEW: Pattern loop mode
}

#define SV_PATTERN_FLAG_NO_NOTES_OFF  (1<<1)

// Constants
#define SUNVOX_SLOT 0                    // Use slot 0 for our project
#define SUNVOX_SAMPLE_RATE 48000         // Match our audio engine
#define SUNVOX_CHANNELS 2                // Stereo
#define SUNVOX_OUTPUT_MODULE 0           // Output module is always 0
#define SUNVOX_BASE_NOTE 60              // Middle C (C4)

// Master bus: all layer sums feed this chain; tail connects to SUNVOX_OUTPUT_MODULE.
#define MAX_MASTER_EFFECT_MODULES 8
static int g_master_effect_modules[MAX_MASTER_EFFECT_MODULES];
static int g_master_effect_module_count = 0;
// Indices into g_master_effect_modules[] (creation order = signal order for the chain).
enum { MASTER_FX_EQ = 0 };

// SunVox module controller indices used in this wrapper.
// Reverb ctl order matches psynths_reverb.cpp psynth_register_ctl:
// Dry=0, Wet=1, Feedback=2, Damp=3, ... , RoomSize=8.
#define SV_AMP_CTL_VOL 0
#define SV_REVERB_CTL_DRY 0
#define SV_REVERB_CTL_WET 1
#define SV_REVERB_CTL_DAMP 3
#define SV_REVERB_CTL_ROOM_SIZE 8
// Return-amp trim on the wet-only return path; keeps high-send reverb from
// reading as an abrupt loudness lift while preserving tail character.
#define SV_REVERB_RETURN_TRIM 240
// Mapped from user-unit 128 with (v*128+127)/255; SunVox Reverb room is 0..128.
#define SV_REVERB_ROOM_DEFAULT 64
#define SV_REVERB_DAMP_DEFAULT 128

// State
static int g_sunvox_initialized = 0;
static int g_section_patterns[MAX_SECTIONS]; // Pattern IDs for each section (-1 = not created)
static int g_sampler_modules[MAX_LAYERS_PER_SECTION][MAX_SAMPLE_SLOTS]; // [layer][slot]
// Dedicated dry samplers for slot preview; bypass layer/master FX graph.
static int g_preview_dry_sampler_modules[MAX_SAMPLE_SLOTS]; // [slot]
// Reverb graph: ONE master Reverb shared by all layers, with a per-layer send
// amp so each layer can still have its own section-scoped wet amount.
//
//   layer_vol[L] -> master_eq                                        (dry)
//   layer_vol[L] -> send_amp[L] -> master_reverb -> return_amp -> master_eq (wet)
//
// Section switches only touch per-layer amplifiers (send / volume / EQ).
// The master Reverb's controllers are written once at init and never again:
// any write flags filters_reinit_request, which recomputes comb buffer sizes
// on the next render and changes delay lengths mid-tail — producing an audible
// break if the tail is still ringing.
static int g_layer_send_amp[MAX_LAYERS_PER_SECTION];
static int g_master_reverb_mod = -1;
static int g_master_return_amp = -1;
static int g_layer_eq_mod[MAX_LAYERS_PER_SECTION];
static int g_layer_post_eq_amp[MAX_LAYERS_PER_SECTION];
static int g_song_mode = 0; // 0 = loop mode, 1 = song mode
static int g_current_section = 0; // Current section for loop mode
static int g_updating_timeline = 0; // Recursion guard for update_timeline

static int clamp_0_255(int v) {
    if (v < 0) return 0;
    if (v > 255) return 255;
    return v;
}

// Small helpers that clamp the user-unit level and look up the correct
// Amplifier module for the layer. Callers must hold the slot lock (these are
// wrapped in sv_lock_slot / sv_unlock_slot by higher-level functions).
static void set_layer_send_level(int layer, int level_u8) {
    if (layer < 0 || layer >= MAX_LAYERS_PER_SECTION) return;
    int mod = g_layer_send_amp[layer];
    if (mod >= 0) sv_set_module_ctl_value(SUNVOX_SLOT, mod, SV_AMP_CTL_VOL, clamp_0_255(level_u8), 0);
}

static void set_layer_volume_level(int layer, int level_u8) {
    if (layer < 0 || layer >= MAX_LAYERS_PER_SECTION) return;
    int mod = g_layer_post_eq_amp[layer];
    if (mod >= 0) sv_set_module_ctl_value(SUNVOX_SLOT, mod, SV_AMP_CTL_VOL, clamp_0_255(level_u8), 0);
}

// Match Dart PlaybackState._dbToSunvoxGain512: linear gain = ctl/256, 256 ≈ 0 dB.
static int db_to_sunvox_eq_gain512(int db) {
    if (db < SECTION_LAYER_EQ_MIN_DB) db = SECTION_LAYER_EQ_MIN_DB;
    if (db > SECTION_LAYER_EQ_MAX_DB) db = SECTION_LAYER_EQ_MAX_DB;
    double g = pow(10.0, (double)db / 20.0);
    int out = (int)round(256.0 * g);
    if (out < 0) out = 0;
    if (out > 512) out = 512;
    return out;
}

static int get_sampler_module_for_layer_slot(int layer, int sample_slot) {
    if (sample_slot < 0 || sample_slot >= MAX_SAMPLE_SLOTS) return -1;
    if (layer < 0 || layer >= MAX_LAYERS_PER_SECTION) layer = 0;
    return g_sampler_modules[layer][sample_slot];
}

static int get_preview_dry_sampler_for_slot(int sample_slot) {
    if (sample_slot < 0 || sample_slot >= MAX_SAMPLE_SLOTS) return -1;
    return g_preview_dry_sampler_modules[sample_slot];
}

static int any_layer_solo_active() {
    for (int l = 0; l < MAX_LAYERS_PER_SECTION; l++) {
        if (table_get_layer_solo(l)) return 1;
    }
    return 0;
}

static int any_col_solo_active_for_layer(int layer) {
    if (layer < 0 || layer >= MAX_LAYERS_PER_SECTION) return 0;
    for (int c = 0; c < MAX_COLS_PER_LAYER; c++) {
        if (table_get_layer_col_solo(layer, c)) return 1;
    }
    return 0;
}

// Unified audible rule for layer/column mute+solo.
static int sunvox_wrapper_is_cell_audible(int section, int col) {
    const int layer = table_get_layer_for_col(section, col);
    const int col_in_layer = table_get_col_in_layer(section, col);
    if (layer < 0 || col_in_layer < 0) return 0;

    if (table_get_layer_mute(layer)) return 0;
    if (table_get_layer_col_mute(layer, col_in_layer)) return 0;

    const int any_layer_solo = any_layer_solo_active();
    if (any_layer_solo && !table_get_layer_solo(layer)) return 0;

    const int any_col_solo_for_layer = any_col_solo_active_for_layer(layer);
    if (any_col_solo_for_layer && !table_get_layer_col_solo(layer, col_in_layer)) return 0;

    return 1;
}

// Create master effect modules and wire: per-layer sums -> EQ -> output.
// Call with slot locked. On failure returns -1 (caller should unlock and abort init).
static int connect_master_effect_chain(void) {
    g_master_effect_module_count = 0;

    int eq_mod = sv_new_module(SUNVOX_SLOT, "EQ", "MasterEQ", 40, 50, 0);
    if (eq_mod < 0) {
        prnt_err("❌ [SUNVOX] Failed to create master EQ: %d", eq_mod);
        return -1;
    }
    if (g_master_effect_module_count >= MAX_MASTER_EFFECT_MODULES) {
        prnt_err("❌ [SUNVOX] MAX_MASTER_EFFECT_MODULES too small");
        return -1;
    }
    g_master_effect_modules[g_master_effect_module_count++] = eq_mod;

    int result = sv_connect_module(SUNVOX_SLOT, eq_mod, SUNVOX_OUTPUT_MODULE);
    if (result < 0) {
        prnt_err("❌ [SUNVOX] Failed to connect master EQ %d to output: %d", eq_mod, result);
        return -1;
    }

    // EQ: unity gain per band (psynths_eq.cpp: ctl 0–2, default 256).
    int eq = g_master_effect_modules[MASTER_FX_EQ];
    sv_set_module_ctl_value(SUNVOX_SLOT, eq, 0, 256, 0);
    sv_set_module_ctl_value(SUNVOX_SLOT, eq, 1, 256, 0);
    sv_set_module_ctl_value(SUNVOX_SLOT, eq, 2, 256, 0);
    return 0;
}

// Build the per-layer dry path + per-layer sends feeding a single shared
// master Reverb. No per-layer Reverb modules exist, so section switches never
// write to any Reverb controller and never trigger filters_reinit_request.
static int connect_layer_reverb_graph(void) {
    const int master_eq = g_master_effect_modules[MASTER_FX_EQ];

    // 1) One shared Reverb + one shared return amp, wired into master EQ.
    int master_rev = sv_new_module(SUNVOX_SLOT, "Reverb", "MasterReverb", 380, 50, 0);
    int master_ret = sv_new_module(SUNVOX_SLOT, "Amplifier", "MasterReverbRet", 460, 50, 0);
    if (master_rev < 0 || master_ret < 0) {
        prnt_err("❌ [SUNVOX] Failed to create shared reverb bus (%d %d)", master_rev, master_ret);
        return -1;
    }
    g_master_reverb_mod = master_rev;
    g_master_return_amp = master_ret;

    if (sv_connect_module(SUNVOX_SLOT, master_rev, master_ret) < 0 ||
        sv_connect_module(SUNVOX_SLOT, master_ret, master_eq) < 0) {
        prnt_err("❌ [SUNVOX] Failed to wire shared reverb bus into master EQ");
        return -1;
    }

    // Wet-only return path; dry stays on the direct layer bus to master EQ.
    // Room/damp are set once here and NEVER rewritten (any Reverb ctl write
    // flags filters_reinit_request and reshapes comb buf sizes mid-tail).
    sv_set_module_ctl_value(SUNVOX_SLOT, master_ret, SV_AMP_CTL_VOL, SV_REVERB_RETURN_TRIM, 0);
    sv_set_module_ctl_value(SUNVOX_SLOT, master_rev, SV_REVERB_CTL_DRY, 0, 0);
    sv_set_module_ctl_value(SUNVOX_SLOT, master_rev, SV_REVERB_CTL_WET, 256, 0);
    sv_set_module_ctl_value(SUNVOX_SLOT, master_rev, SV_REVERB_CTL_ROOM_SIZE, SV_REVERB_ROOM_DEFAULT, 0);
    sv_set_module_ctl_value(SUNVOX_SLOT, master_rev, SV_REVERB_CTL_DAMP, SV_REVERB_DAMP_DEFAULT, 0);

    // 2) Per-layer dry bus + per-layer send amp into the shared reverb.
    for (int layer = 0; layer < MAX_LAYERS_PER_SECTION; layer++) {
        char eq_name[24];
        snprintf(eq_name, sizeof(eq_name), "L%dLayerEQ", layer);
        int layer_eq = sv_new_module(SUNVOX_SLOT, "EQ", eq_name, 200, 120 + layer * 140, 0);
        if (layer_eq < 0) {
            prnt_err("❌ [SUNVOX] Failed to create layer EQ L%d: %d", layer, layer_eq);
            return -1;
        }
        g_layer_eq_mod[layer] = layer_eq;
        sv_set_module_ctl_value(SUNVOX_SLOT, layer_eq, 0, 256, 0);
        sv_set_module_ctl_value(SUNVOX_SLOT, layer_eq, 1, 256, 0);
        sv_set_module_ctl_value(SUNVOX_SLOT, layer_eq, 2, 256, 0);

        char vol_name[24];
        snprintf(vol_name, sizeof(vol_name), "L%dLayerVol", layer);
        int layer_vol = sv_new_module(SUNVOX_SLOT, "Amplifier", vol_name, 220, 120 + layer * 140, 0);
        if (layer_vol < 0) {
            prnt_err("❌ [SUNVOX] Failed to create layer volume amp L%d: %d", layer, layer_vol);
            return -1;
        }
        g_layer_post_eq_amp[layer] = layer_vol;
        set_layer_volume_level(layer, 255);

        char send_name[32];
        snprintf(send_name, sizeof(send_name), "L%dSend", layer);
        int send_amp = sv_new_module(SUNVOX_SLOT, "Amplifier", send_name, 300, 120 + layer * 140, 0);
        if (send_amp < 0) {
            prnt_err("❌ [SUNVOX] Failed to create layer send amp L%d: %d", layer, send_amp);
            return -1;
        }
        g_layer_send_amp[layer] = send_amp;

        // Samplers → layer EQ.
        for (int slot = 0; slot < MAX_SAMPLE_SLOTS; slot++) {
            int sampler = g_sampler_modules[layer][slot];
            if (sampler < 0) continue;
            if (sv_connect_module(SUNVOX_SLOT, sampler, layer_eq) < 0) {
                prnt_err("❌ [SUNVOX] Failed to connect sampler L%d slot=%d to layer EQ", layer, slot);
                return -1;
            }
        }

        // Layer EQ → per-layer volume → [master EQ (dry) and send_amp (wet tap)].
        if (sv_connect_module(SUNVOX_SLOT, layer_eq, layer_vol) < 0 ||
            sv_connect_module(SUNVOX_SLOT, layer_vol, master_eq) < 0 ||
            sv_connect_module(SUNVOX_SLOT, layer_vol, send_amp) < 0) {
            prnt_err("❌ [SUNVOX] Failed to wire layer dry/wet taps L%d", layer);
            return -1;
        }

        // send_amp → shared master reverb.
        if (sv_connect_module(SUNVOX_SLOT, send_amp, master_rev) < 0) {
            prnt_err("❌ [SUNVOX] Failed to connect send L%d to master reverb", layer);
            return -1;
        }

        // Start quiet; real send comes from section table on first apply.
        set_layer_send_level(layer, 0);
    }
    return 0;
}

// Initialize SunVox engine
int sunvox_wrapper_init(void) {
    prnt_debug("🎵 [SUNVOX] Initializing SunVox wrapper (NEW LIBRARY - Oct 14 2025)");
    
    // WORKAROUND for crash bug: Pre-create config files before sv_init()
    // SunVox's smisc_global_init() tries to load config files and crashes if they don't exist
    // when using USER_AUDIO_CALLBACK mode
    #ifdef __APPLE__
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docsDir = [paths firstObject];
    NSString *configPath = [docsDir stringByAppendingPathComponent:@"sunvox_dll_config.ini"];
    
    // Create empty config file if it doesn't exist
    if (![[NSFileManager defaultManager] fileExistsAtPath:configPath]) {
        [@"" writeToFile:configPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        prnt_debug("🔧 [SUNVOX] Created empty config file at: %s", [configPath UTF8String]);
    }
    #endif
    
    // Initialize SunVox in OFFLINE mode (USER_AUDIO_CALLBACK)
    // This disables SunVox's built-in audio - we'll manage it ourselves via miniaudio
    // This prevents double audio consumption and enables clean recording
    uint32_t flags = SV_INIT_FLAG_USER_AUDIO_CALLBACK | 
                     SV_INIT_FLAG_AUDIO_FLOAT32 | 
                     SV_INIT_FLAG_ONE_THREAD;
    
    int result = sv_init(NULL, SUNVOX_SAMPLE_RATE, SUNVOX_CHANNELS, flags);
    if (result < 0) {
        prnt_err("❌ [SUNVOX] Failed to initialize SunVox: %d", result);
        return -1;
    }
    
    prnt("✅ [SUNVOX] sv_init succeeded in OFFLINE mode (USER_AUDIO_CALLBACK)");
    
    // Open slot 0 for our project
    result = sv_open_slot(SUNVOX_SLOT);
    if (result < 0) {
        prnt_err("❌ [SUNVOX] Failed to open slot: %d", result);
        sv_deinit();
        return -1;
    }
    
    prnt("✅ [SUNVOX] sv_open_slot succeeded");
    
    // Enable supertracks mode - required for NO_NOTES_OFF flag to work properly
    sv_lock_slot(SUNVOX_SLOT);
    result = sv_enable_supertracks(SUNVOX_SLOT, 1);
    sv_unlock_slot(SUNVOX_SLOT);
    
    if (result == 0) {
        prnt("✅ [SUNVOX] Supertracks mode enabled (required for seamless looping)");
    } else {
        prnt_err("⚠️ [SUNVOX] Failed to enable supertracks mode: %d", result);
        prnt_err("❌ [SUNVOX] Without supertracks, seamless looping will NOT work!");
    }
    
    // Check if SunVox created any default patterns
    int num_pattern_slots = sv_get_number_of_patterns(SUNVOX_SLOT);
    
    int actual_patterns = 0;
    for (int i = 0; i < num_pattern_slots; i++) {
        int lines = sv_get_pattern_lines(SUNVOX_SLOT, i);
        if (lines > 0) {
            actual_patterns++;
            const char* name = sv_get_pattern_name(SUNVOX_SLOT, i);
            int tracks = sv_get_pattern_tracks(SUNVOX_SLOT, i);
            int x = sv_get_pattern_x(SUNVOX_SLOT, i);
            int y = sv_get_pattern_y(SUNVOX_SLOT, i);
            prnt("🔧   Default pattern %d: \"%s\" - %d x %d lines, position (%d, %d)", 
                 i, name ? name : "???", tracks, lines, x, y);
        }
    }
    
    if (actual_patterns > 0) {
        prnt("⚠️ [SUNVOX] WARNING: SunVox created %d default pattern(s)!", actual_patterns);
        prnt_debug("🗑️ [SUNVOX] Deleting default patterns to start clean...");
        
        // Delete all default patterns
        sv_lock_slot(SUNVOX_SLOT);
        for (int i = 0; i < num_pattern_slots; i++) {
            int lines = sv_get_pattern_lines(SUNVOX_SLOT, i);
            if (lines > 0) {
                prnt_debug("🗑️ [SUNVOX] Deleting default pattern %d", i);
                sv_remove_pattern(SUNVOX_SLOT, i);
            }
        }
        sv_unlock_slot(SUNVOX_SLOT);
        
        prnt("✅ [SUNVOX] Deleted all default patterns");
    } else {
        prnt("✅ [SUNVOX] No default patterns, starting clean");
    }
    
    // Initialize arrays
    g_master_reverb_mod = -1;
    g_master_return_amp = -1;
    for (int l = 0; l < MAX_LAYERS_PER_SECTION; l++) {
        g_layer_send_amp[l] = -1;
        g_layer_eq_mod[l] = -1;
        g_layer_post_eq_amp[l] = -1;
        for (int i = 0; i < MAX_SAMPLE_SLOTS; i++) {
            g_sampler_modules[l][i] = -1; // No module yet
        }
    }
    for (int i = 0; i < MAX_SAMPLE_SLOTS; i++) {
        g_preview_dry_sampler_modules[i] = -1;
    }
    for (int i = 0; i < MAX_SECTIONS; i++) {
        g_section_patterns[i] = -1; // No pattern yet
    }
    
    // Create per-layer sampler modules.
    sv_lock_slot(SUNVOX_SLOT);
    
    for (int layer = 0; layer < MAX_LAYERS_PER_SECTION; layer++) {
        for (int i = 0; i < MAX_SAMPLE_SLOTS; i++) {
            int x = 100 + (i % 8) * 100;
            int y = 100 + (i / 8) * 100 + layer * 360;

            char name[40];
            snprintf(name, sizeof(name), "L%dSampler%d", layer, i);

            int mod_id = sv_new_module(SUNVOX_SLOT, "Sampler", name, x, y, 0);
            if (mod_id < 0) {
                prnt_err("❌ [SUNVOX] Failed to create sampler L%d S%d: %d", layer, i, mod_id);
                sv_unlock_slot(SUNVOX_SLOT);
                sunvox_wrapper_cleanup();
                return -1;
            }
            g_sampler_modules[layer][i] = mod_id;
        }
    }

    // Create dedicated dry samplers for slot preview and connect straight to output.
    // These modules are not part of the layer/master FX graph.
    for (int i = 0; i < MAX_SAMPLE_SLOTS; i++) {
        int x = 100 + (i % 8) * 100;
        int y = 100 + (i / 8) * 100 + MAX_LAYERS_PER_SECTION * 360 + 140;
        char name[40];
        snprintf(name, sizeof(name), "PreviewDryS%d", i);

        int mod_id = sv_new_module(SUNVOX_SLOT, "Sampler", name, x, y, 0);
        if (mod_id < 0) {
            prnt_err("❌ [SUNVOX] Failed to create dry preview sampler S%d: %d", i, mod_id);
            sv_unlock_slot(SUNVOX_SLOT);
            sunvox_wrapper_cleanup();
            return -1;
        }
        if (sv_connect_module(SUNVOX_SLOT, mod_id, SUNVOX_OUTPUT_MODULE) < 0) {
            prnt_err("❌ [SUNVOX] Failed to connect dry preview sampler S%d to output", i);
            sv_unlock_slot(SUNVOX_SLOT);
            sunvox_wrapper_cleanup();
            return -1;
        }
        g_preview_dry_sampler_modules[i] = mod_id;
    }

    if (connect_master_effect_chain() != 0) {
        sv_unlock_slot(SUNVOX_SLOT);
        sunvox_wrapper_cleanup();
        return -1;
    }
    if (connect_layer_reverb_graph() != 0) {
        sv_unlock_slot(SUNVOX_SLOT);
        sunvox_wrapper_cleanup();
        return -1;
    }
    
    sv_unlock_slot(SUNVOX_SLOT);
    
    // Patterns will be created on-demand as sections are added
    // (via sunvox_wrapper_create_section_pattern)
    
    // Set autostop off (patterns will loop automatically)
    sv_set_autostop(SUNVOX_SLOT, 0);

    // Get initial BPM (unused but kept for reference)
    int initial_bpm = sv_get_song_bpm(SUNVOX_SLOT);
    (void)initial_bpm;
    
    // NOTE: Input module removed - mic recording now bypasses SunVox entirely
    // See docs/features/microphone_dual_output_architecture.md for the archived approach
    
    g_sunvox_initialized = 1;
    return 0;
}

// Cleanup SunVox engine
void sunvox_wrapper_cleanup(void) {
    if (!g_sunvox_initialized) return;
    
    prnt("🧹 [SUNVOX] Cleaning up");
    
    // Stop playback
    sv_stop(SUNVOX_SLOT);
    
    // Close slot (this automatically removes all modules including Input)
    sv_close_slot(SUNVOX_SLOT);
    
    // Deinit SunVox
    sv_deinit();
    
    g_sunvox_initialized = 0;

    g_master_effect_module_count = 0;
    
    // Clear section patterns array
    for (int i = 0; i < MAX_SECTIONS; i++) {
        g_section_patterns[i] = -1;
    }
    g_master_reverb_mod = -1;
    g_master_return_amp = -1;
    for (int l = 0; l < MAX_LAYERS_PER_SECTION; l++) {
        g_layer_eq_mod[l] = -1;
        g_layer_post_eq_amp[l] = -1;
        g_layer_send_amp[l] = -1;
        for (int s = 0; s < MAX_SAMPLE_SLOTS; s++) {
            g_sampler_modules[l][s] = -1;
        }
    }
    for (int s = 0; s < MAX_SAMPLE_SLOTS; s++) {
        g_preview_dry_sampler_modules[s] = -1;
    }
    
    prnt("✅ [SUNVOX] Cleanup complete");
}

// Master EQ band gain (band 0..2, gain 0..512). See MASTER_FX_EQ.
extern "C" void sunvox_wrapper_set_master_eq_band(int band, int gain_0_512) {
    if (!g_sunvox_initialized) return;
    if (band < 0 || band > 2) return;
    if (g_master_effect_module_count <= MASTER_FX_EQ) return;
    if (gain_0_512 < 0) gain_0_512 = 0;
    if (gain_0_512 > 512) gain_0_512 = 512;
    int eq_mod = g_master_effect_modules[MASTER_FX_EQ];
    sv_lock_slot(SUNVOX_SLOT);
    sv_set_module_ctl_value(SUNVOX_SLOT, eq_mod, band, gain_0_512, 0);
    sv_unlock_slot(SUNVOX_SLOT);
}

// Compatibility shim: maps master reverb control to every layer's send amp.
extern "C" void sunvox_wrapper_set_master_reverb(float wet01) {
    if (!g_sunvox_initialized) return;
    if (wet01 < 0.0f) wet01 = 0.0f;
    if (wet01 > 1.0f) wet01 = 1.0f;
    int wet256 = (int)(wet01 * 256.0f);
    if (wet256 < 0) wet256 = 0;
    if (wet256 > 256) wet256 = 256;
    sv_lock_slot(SUNVOX_SLOT);
    for (int layer = 0; layer < MAX_LAYERS_PER_SECTION; layer++) {
        set_layer_send_level(layer, wet256);
    }
    sv_unlock_slot(SUNVOX_SLOT);
}

// Per-section `room` and `damp` in table state are intentionally ignored at
// runtime: the shared master Reverb is configured once at init (see
// connect_layer_reverb_graph). Only the per-layer send amp is section-scoped.
void sunvox_wrapper_apply_section_layer_reverb(int section_index) {
    if (!g_sunvox_initialized) return;
    sv_lock_slot(SUNVOX_SLOT);
    for (int layer = 0; layer < MAX_LAYERS_PER_SECTION; layer++) {
        int send_target = table_get_section_layer_reverb_send(section_index, layer);
        set_layer_send_level(layer, send_target);
    }
    sv_unlock_slot(SUNVOX_SLOT);
}

void sunvox_wrapper_apply_section_layer_eq(int section_index) {
    if (!g_sunvox_initialized) return;
    if (section_index < 0 || section_index >= MAX_SECTIONS) return;
    sv_lock_slot(SUNVOX_SLOT);
    for (int layer = 0; layer < MAX_LAYERS_PER_SECTION; layer++) {
        int eq = g_layer_eq_mod[layer];
        if (eq < 0) continue;
        int low = table_get_section_layer_eq_band_db(section_index, layer, 0);
        int mid = table_get_section_layer_eq_band_db(section_index, layer, 1);
        int high = table_get_section_layer_eq_band_db(section_index, layer, 2);
        sv_set_module_ctl_value(SUNVOX_SLOT, eq, 0, db_to_sunvox_eq_gain512(low), 0);
        sv_set_module_ctl_value(SUNVOX_SLOT, eq, 1, db_to_sunvox_eq_gain512(mid), 0);
        sv_set_module_ctl_value(SUNVOX_SLOT, eq, 2, db_to_sunvox_eq_gain512(high), 0);
    }
    sv_unlock_slot(SUNVOX_SLOT);
}

void sunvox_wrapper_apply_section_layer_volume(int section_index) {
    if (!g_sunvox_initialized) return;
    if (section_index < 0 || section_index >= MAX_SECTIONS) return;
    sv_lock_slot(SUNVOX_SLOT);
    for (int layer = 0; layer < MAX_LAYERS_PER_SECTION; layer++) {
        int level = table_get_section_layer_volume(section_index, layer);
        set_layer_volume_level(layer, level);
    }
    sv_unlock_slot(SUNVOX_SLOT);
}

// Snap per-layer send / volume / EQ to the next section's table values. The
// shared master Reverb is not touched (see `g_master_reverb_mod` comment), so
// its tail rings through the switch undisturbed. No ramp: the new section's
// first line must start on time — fading layer volume in from 0 is audible as
// the line starting late.
void sunvox_wrapper_on_section_switch(int prev_section, int next_section) {
    if (!g_sunvox_initialized) return;
    (void)prev_section;
    sunvox_wrapper_apply_section_layer_reverb(next_section);
    sunvox_wrapper_apply_section_layer_volume(next_section);
    sunvox_wrapper_apply_section_layer_eq(next_section);
}

// Load a sample into a SunVox sampler module
int sunvox_wrapper_load_sample(int sample_slot, const char* file_path) {
    if (!g_sunvox_initialized) {
        prnt_err("❌ [SUNVOX] Not initialized");
        return -1;
    }
    
    if (sample_slot < 0 || sample_slot >= MAX_SAMPLE_SLOTS) {
        prnt_err("❌ [SUNVOX] Invalid sample slot: %d", sample_slot);
        return -1;
    }
    
    prnt_debug("📂 [SUNVOX] Loading sample %d: %s", sample_slot, file_path);
    
    // Lock slot for sample loading
    sv_lock_slot(SUNVOX_SLOT);

    for (int layer = 0; layer < MAX_LAYERS_PER_SECTION; layer++) {
        int mod_id = get_sampler_module_for_layer_slot(layer, sample_slot);
        if (mod_id < 0) {
            sv_unlock_slot(SUNVOX_SLOT);
            prnt_err("❌ [SUNVOX] No sampler module for layer=%d slot=%d", layer, sample_slot);
            return -1;
        }

        // Load sample into each layer clone (sample_slot -1 means replace entire sampler)
        int result = sv_sampler_load(SUNVOX_SLOT, mod_id, file_path, -1);
        if (result < 0) {
            sv_unlock_slot(SUNVOX_SLOT);
            prnt_err("❌ [SUNVOX] Failed to load sample into sampler L%d S%d: %d", layer, sample_slot, result);
            return -1;
        }

        // Force one-shot playback for imported loops.
        const int kSamplerParLoopType = 2;
        const int kMaxSamplesPerSamplerModule = 128;
        for (int s = 0; s < kMaxSamplesPerSamplerModule; s++) {
            sv_sampler_par(SUNVOX_SLOT, mod_id, s, kSamplerParLoopType, 0, 1);
        }

        sv_set_module_ctl_value(SUNVOX_SLOT, mod_id, 4, 256, 0);
    }

    // Mirror sample into dry preview sampler so slot preview bypasses all FX.
    int dry_mod_id = get_preview_dry_sampler_for_slot(sample_slot);
    if (dry_mod_id < 0) {
        sv_unlock_slot(SUNVOX_SLOT);
        prnt_err("❌ [SUNVOX] No dry preview sampler for slot=%d", sample_slot);
        return -1;
    }
    int dry_result = sv_sampler_load(SUNVOX_SLOT, dry_mod_id, file_path, -1);
    if (dry_result < 0) {
        sv_unlock_slot(SUNVOX_SLOT);
        prnt_err("❌ [SUNVOX] Failed to load sample into dry preview sampler S%d: %d", sample_slot, dry_result);
        return -1;
    }
    const int kSamplerParLoopType = 2;
    const int kMaxSamplesPerSamplerModule = 128;
    for (int s = 0; s < kMaxSamplesPerSamplerModule; s++) {
        sv_sampler_par(SUNVOX_SLOT, dry_mod_id, s, kSamplerParLoopType, 0, 1);
    }
    sv_set_module_ctl_value(SUNVOX_SLOT, dry_mod_id, 4, 256, 0);
    
    sv_unlock_slot(SUNVOX_SLOT);
    
    prnt("✅ [SUNVOX] Loaded sample %d into %d layer samplers", sample_slot, MAX_LAYERS_PER_SECTION);
    return 0;
}

// Unload a sample from a SunVox sampler module
void sunvox_wrapper_unload_sample(int sample_slot) {
    if (!g_sunvox_initialized) return;
    
    if (sample_slot < 0 || sample_slot >= MAX_SAMPLE_SLOTS) {
        return;
    }

    // SunVox public API does not expose sampler sample-count/remove functions.
    // Keep this as a lightweight logical unload; the next load replaces sampler content.
    prnt_debug("🗑️ [SUNVOX] Logical unload for sample %d (content replaced on next load)", sample_slot);
}

// Sync single cell to SunVox pattern
void sunvox_wrapper_sync_cell(int step, int col) {
    if (!g_sunvox_initialized) return;
    
    // Find which section this step belongs to
    int section_index = table_get_section_at_step(step);
    if (section_index < 0 || section_index >= MAX_SECTIONS) {
        prnt_err("❌ [SUNVOX] Invalid section index for step %d", step);
        return;
    }
    
    int pat_id = g_section_patterns[section_index];
    if (pat_id < 0) {
        prnt_err("❌ [SUNVOX] Pattern doesn't exist for section %d (step %d) - was playback_init() called?", 
                 section_index, step);
        return;
    }
    
    // Convert global step to local line within section
    int section_start = table_get_section_start_step(section_index);
    int local_line = step - section_start;
    
    Cell* cell = table_get_cell(step, col);
    if (!cell) return;
    
    sv_lock_slot(SUNVOX_SLOT);
    
    const int should_mute = !sunvox_wrapper_is_cell_audible(section_index, col);
    if (!should_mute && cell->sample_slot >= 0 && cell->sample_slot < MAX_SAMPLE_SLOTS) {
        // Cell has a sample - write note event
        int layer = table_get_layer_for_col(section_index, col);
        int mod_id = get_sampler_module_for_layer_slot(layer, cell->sample_slot);
        if (mod_id >= 0) {
            // Resolve volume from cell or sample settings
            float volume = cell->settings.volume;
            if (volume == DEFAULT_CELL_VOLUME) {
                Sample* s = sample_bank_get_sample(cell->sample_slot);
                volume = (s && s->loaded) ? s->settings.volume : 1.0f;
            }
            
            // Convert volume (0..1) to velocity (1..128)
            int velocity = (int)(volume * 128.0f);
            if (velocity < 1) velocity = 1;
            if (velocity > 128) velocity = 128;

            // Resolve pitch from cell or sample settings
            float pitch = cell->settings.pitch;
            if (pitch == DEFAULT_CELL_PITCH) {
                Sample* s = sample_bank_get_sample(cell->sample_slot);
                pitch = (s && s->loaded) ? s->settings.pitch : 1.0f;
            }

            // Guard against non-positive pitch values for log2f
            if (pitch <= 0.0f) {
                pitch = 1.0f;
            }

            // Convert pitch ratio to semitones
            float semitones = 12.0f * log2f(pitch);
            int final_note = SUNVOX_BASE_NOTE + (int)roundf(semitones);
            if (final_note < 0) final_note = 0;
            if (final_note > 127) final_note = 127;
            
            // Get sample offset from sample bank (if any)
            int offset_frames = 0;
            Sample* sample = sample_bank_get_sample(cell->sample_slot);
            if (sample && sample->loaded) {
                offset_frames = sample->offset_frames;
            }
            
            // Use offset-aware event setter if offset is non-zero
            if (offset_frames > 0) {
                // Unlock before calling the offset function (it locks internally)
                sv_unlock_slot(SUNVOX_SLOT);
                sunvox_wrapper_set_pattern_event_with_offset(
                    pat_id, col, local_line, final_note, velocity,
                    cell->sample_slot, offset_frames  // Pass sample slot, not mod_id
                );
                sv_lock_slot(SUNVOX_SLOT);
                prnt_debug("📝 [SUNVOX] Set pattern event with offset [section=%d, line=%d, col=%d]: note=%d, vel=%d, slot=%d, offset=%d",
                     section_index, local_line, col, final_note, velocity, cell->sample_slot, offset_frames);
            } else {
                // Regular event without offset
                int result = sv_set_pattern_event(
                    SUNVOX_SLOT,
                    pat_id,              // section's pattern
                    col,                 // track
                    local_line,          // line within pattern
                    final_note,          // note
                    velocity,            // velocity
                    mod_id + 1,          // module (1-indexed)
                    0,                   // no controller/effect
                    0                    // no parameter
                );
                
                if (result == 0) {
                    prnt_debug("📝 [SUNVOX] Set pattern event [section=%d, line=%d, col=%d]: note=%d, vel=%d, mod=%d",
                         section_index, local_line, col, final_note, velocity, mod_id + 1);
                } else {
                    prnt_err("❌ [SUNVOX] Failed to set pattern event: %d", result);
                }
            }
        }
    } else {
        // Empty cell - clear event
        sv_set_pattern_event(
            SUNVOX_SLOT,
            pat_id,
            col,
            local_line,
            0, 0, 0, 0, 0
        );
    }
    
    sv_unlock_slot(SUNVOX_SLOT);
}

// Set pattern event with sample offset effects (09xx coarse, 07xx fine)
// This enables precise sample positioning with sub-step accuracy
// Accepts sample_slot instead of mod_id, looks up the module internally
void sunvox_wrapper_set_pattern_event_with_offset(
    int pat_id, 
    int track, 
    int line, 
    int note,
    int velocity, 
    int sample_slot,  // Changed: now accepts sample slot, not module ID
    int offset_frames
) {
    if (!g_sunvox_initialized) return;
    
    // Look up the module ID for this sample slot
    if (sample_slot < 0 || sample_slot >= MAX_SAMPLE_SLOTS) {
        prnt_err("❌ [SUNVOX] Invalid sample slot for offset: %d", sample_slot);
        return;
    }
    
    int section_index = 0;
    for (int s = 0; s < MAX_SECTIONS; s++) {
        if (g_section_patterns[s] == pat_id) {
            section_index = s;
            break;
        }
    }
    int layer = table_get_layer_for_col(section_index, track);
    int mod_id = get_sampler_module_for_layer_slot(layer, sample_slot);
    if (mod_id < 0) {
        prnt_err("❌ [SUNVOX] No sampler module for slot %d", sample_slot);
        return;
    }
    
    // Split offset into coarse and fine components
    // Coarse (09xx): multiplied by 256 internally by SunVox
    // Fine (07xx): direct frame count (0-255)
    int coarse = offset_frames / 256;
    int fine = offset_frames % 256;
    
    // Clamp to valid ranges (0-255 for both)
    if (coarse > 255) coarse = 255;
    if (fine > 255) fine = 255;
    
    sv_lock_slot(SUNVOX_SLOT);
    
    // Set main note with coarse offset (effect 09xx)
    if (coarse > 0) {
        sv_set_pattern_event(
            SUNVOX_SLOT, pat_id, track, line,
            note, velocity, mod_id + 1,
            0x0900, // Effect 09 (coarse offset)
            coarse  // Multiplied by 256 internally
        );
        prnt_debug("🎯 [SUNVOX] Set note with coarse offset 09%02X at line=%d track=%d slot=%d mod=%d", 
                   coarse, line, track, sample_slot, mod_id);
    } else {
        // No offset, just regular note
        sv_set_pattern_event(
            SUNVOX_SLOT, pat_id, track, line,
            note, velocity, mod_id + 1, 0, 0
        );
    }
    
    // Set fine offset on next track if needed and available
    if (fine > 0 && track + 1 < table_get_max_cols()) {
        sv_set_pattern_event(
            SUNVOX_SLOT, pat_id, track + 1, line,
            0, 0, mod_id + 1, // Same module, no note
            0x0700, // Effect 07 (fine offset)
            fine
        );
        prnt_debug("🎯 [SUNVOX] Set fine offset 07%02X at line=%d track=%d", fine, line, track + 1);
    }
    
    sv_unlock_slot(SUNVOX_SLOT);
    
    prnt_debug("🎯 [SUNVOX] Set event with offset: slot=%d mod=%d line=%d frames=%d (coarse=%d, fine=%d)",
               sample_slot, mod_id, line, offset_frames, coarse, fine);
}

// Sync entire table to SunVox pattern
// Create a pattern for a section
int sunvox_wrapper_create_section_pattern(int section_index, int section_length) {
    if (!g_sunvox_initialized) return -1;
    if (section_index < 0 || section_index >= MAX_SECTIONS) return -1;
    
    // Check if pattern already exists - if so, just resize it seamlessly
    int existing_pat_id = g_section_patterns[section_index];
    if (existing_pat_id >= 0) {
        // Pattern exists - resize it instead of recreating
        sv_lock_slot(SUNVOX_SLOT);
        
        int max_cols = table_get_max_cols();
        int old_lines = sv_get_pattern_lines(SUNVOX_SLOT, existing_pat_id);
        int result = sv_set_pattern_size(SUNVOX_SLOT, existing_pat_id, max_cols, section_length);
        
        // CRITICAL FIX: Verify the resize actually worked by reading back the size
        int actual_lines = sv_get_pattern_lines(SUNVOX_SLOT, existing_pat_id);
        int actual_tracks = sv_get_pattern_tracks(SUNVOX_SLOT, existing_pat_id);
        
        if (result == 0 && actual_lines == section_length && actual_tracks == max_cols) {
            prnt("📏 [SUNVOX] Resized existing pattern %d for section %d from %d to %d lines (seamless, verified)", 
                 existing_pat_id, section_index, old_lines, section_length);
            
            // Sync the section data to the resized pattern
            sunvox_wrapper_sync_section(section_index);
            
            sv_unlock_slot(SUNVOX_SLOT);
            
            // SEAMLESS FIX: Update timeline positions without stopping playback
            sunvox_wrapper_update_timeline_seamless(section_index);
            
            return 0;
        } else {
            prnt_err("❌ [SUNVOX] Pattern resize FAILED verification: result=%d, expected %dx%d, got %dx%d", 
                     result, max_cols, section_length, actual_tracks, actual_lines);
            prnt_err("❌ [SUNVOX] sv_set_pattern_size() returned success but pattern wasn't actually resized!");
            prnt_err("❌ [SUNVOX] Falling back to pattern recreation to ensure correct size");
            sv_unlock_slot(SUNVOX_SLOT);
            // Fall through to recreation logic
        }
    }
    
    // Pattern doesn't exist or resize failed - create new one
    // Check if playback is active BEFORE any modifications
    int was_playing = (sv_end_of_song(SUNVOX_SLOT) == 0);
    
    // If pattern already exists, remove it first (this is the fallback case)
    if (g_section_patterns[section_index] >= 0) {
        sunvox_wrapper_remove_section_pattern(section_index);
    }
    
    sv_lock_slot(SUNVOX_SLOT);
    
    int max_cols = table_get_max_cols();
    
    char name[32];
    snprintf(name, sizeof(name), "Section%d", section_index);
    
    
    int pat_id = sv_new_pattern(
        SUNVOX_SLOT,
        -1,              // clone = -1 (create new)
        0,               // x position (will be set via timeline)
        section_index,   // y position (for visual ordering)
        max_cols,        // tracks = columns
        section_length,  // lines = section length
        0,               // icon seed
        name             // name
    );
    
    if (pat_id < 0) {
        prnt_err("❌ [SUNVOX] Failed to create pattern for section %d: %d", section_index, pat_id);
        sv_unlock_slot(SUNVOX_SLOT);
        return -1;
    }
    
    g_section_patterns[section_index] = pat_id;
    
    // Verify pattern was created with correct size
    int actual_lines = sv_get_pattern_lines(SUNVOX_SLOT, pat_id);
    int actual_tracks = sv_get_pattern_tracks(SUNVOX_SLOT, pat_id);
    
    prnt("✅ [SUNVOX] Created pattern %d for section %d (requested: %d x %d, actual: %d x %d)", 
         pat_id, section_index, max_cols, section_length, actual_tracks, actual_lines);
    
    // Force pattern size if SunVox rounded it
    if (actual_lines != section_length || actual_tracks != max_cols) {
        prnt("⚠️ [SUNVOX] Pattern size mismatch, forcing to %d x %d", max_cols, section_length);
        sv_set_pattern_size(SUNVOX_SLOT, pat_id, max_cols, section_length);
        
        // Verify again
        actual_lines = sv_get_pattern_lines(SUNVOX_SLOT, pat_id);
        actual_tracks = sv_get_pattern_tracks(SUNVOX_SLOT, pat_id);
    }
    
    sv_unlock_slot(SUNVOX_SLOT);
    
    // CRITICAL FIX: Set NO_NOTES_OFF flag to prevent samples from being cut off at loop boundary
    // This allows seamless looping - notes continue playing when pattern wraps around
    sv_lock_slot(SUNVOX_SLOT);
    int result = sv_pattern_set_flags(SUNVOX_SLOT, pat_id, SV_PATTERN_FLAG_NO_NOTES_OFF, 1);
    sv_unlock_slot(SUNVOX_SLOT);
    
    if (result == 0) {
        prnt("✅ [SUNVOX] Set NO_NOTES_OFF flag on pattern %d for seamless looping", pat_id);
    } else {
        prnt_err("❌ [SUNVOX] Failed to set NO_NOTES_OFF flag on pattern %d (error: %d)", pat_id, result);
    }
    
    // Sync section content to pattern
    sunvox_wrapper_sync_section(section_index);
    
    
    // Update timeline (unless we're already updating it - prevent recursion)
    if (!g_updating_timeline) {
        sunvox_wrapper_update_timeline();
        
        // If playback was active, restart it to apply new timeline
        // Note: This only happens when a pattern is recreated, not resized
        if (was_playing) {
            prnt_debug("🔄 [SUNVOX] Restarting playback to apply new pattern (pattern was recreated)");
            sv_stop(SUNVOX_SLOT);
            sv_rewind(SUNVOX_SLOT, 0);
            sv_play(SUNVOX_SLOT);
        }
    }
    
    return 0;
}

// Remove a pattern for a section
void sunvox_wrapper_remove_section_pattern(int section_index) {
    if (!g_sunvox_initialized) return;
    if (section_index < 0 || section_index >= MAX_SECTIONS) return;
    
    int pat_id = g_section_patterns[section_index];
    if (pat_id < 0) return; // No pattern to remove
    
    sv_lock_slot(SUNVOX_SLOT);
    sv_remove_pattern(SUNVOX_SLOT, pat_id);
    sv_unlock_slot(SUNVOX_SLOT);
    
    g_section_patterns[section_index] = -1;
    prnt_debug("🗑️ [SUNVOX] Removed pattern for section %d", section_index);
    
    // Update timeline
    sunvox_wrapper_update_timeline();
}

// Reset ALL SunVox patterns (used before import to ensure clean state)
void sunvox_wrapper_reset_all_patterns(void) {
    if (!g_sunvox_initialized) return;
    
    prnt_debug("🔄 [SUNVOX] === RESETTING ALL PATTERNS ===");
    
    // Stop playback first
    sv_stop(SUNVOX_SLOT);
    sv_rewind(SUNVOX_SLOT, 0);
    
    // Lock before removing all patterns
    sv_lock_slot(SUNVOX_SLOT);
    
    // Get number of pattern slots
    int num_pattern_slots = sv_get_number_of_patterns(SUNVOX_SLOT);
    prnt_debug("🔍 [SUNVOX] Found %d pattern slots", num_pattern_slots);
    
    // Remove all existing patterns
    int removed_count = 0;
    for (int i = 0; i < num_pattern_slots; i++) {
        int lines = sv_get_pattern_lines(SUNVOX_SLOT, i);
        if (lines > 0) {
            prnt_debug("🗑️ [SUNVOX] Removing pattern %d (%d lines)", i, lines);
            sv_remove_pattern(SUNVOX_SLOT, i);
            removed_count++;
        }
    }
    
    sv_unlock_slot(SUNVOX_SLOT);
    
    // Clear all section pattern mappings
    for (int i = 0; i < MAX_SECTIONS; i++) {
        g_section_patterns[i] = -1;
    }
    
    // Reset SunVox state variables
    g_song_mode = 0; // Loop mode
    g_current_section = 0;
    
    prnt("✅ [SUNVOX] Reset complete: removed %d patterns, cleared all mappings", removed_count);
}

// Sync entire section to its pattern
void sunvox_wrapper_sync_section(int section_index) {
    if (!g_sunvox_initialized) {
        prnt_err("❌ [SUNVOX] Cannot sync section %d - SunVox not initialized", section_index);
        return;
    }
    if (section_index < 0 || section_index >= MAX_SECTIONS) {
        prnt_err("❌ [SUNVOX] Invalid section index: %d", section_index);
        return;
    }
    
    int pat_id = g_section_patterns[section_index];
    if (pat_id < 0) {
        prnt_err("❌ [SUNVOX] Cannot sync section %d - pattern doesn't exist (pat_id=%d)", 
                 section_index, pat_id);
        return; // Pattern doesn't exist
    }
    
    int section_start = table_get_section_start_step(section_index);
    int section_length = table_get_section_step_count(section_index);
    int max_cols = table_get_max_cols();
    
    prnt_debug("🔄 [SUNVOX] Syncing section %d (start=%d, length=%d, pat_id=%d)", 
         section_index, section_start, section_length, pat_id);
    
    int synced_cells = 0;
    int empty_cells = 0;
    
    for (int local_line = 0; local_line < section_length; local_line++) {
        int global_step = section_start + local_line;
        for (int col = 0; col < max_cols; col++) {
            // Sync this cell
            Cell* cell = table_get_cell(global_step, col);
            
            sv_lock_slot(SUNVOX_SLOT);

            // Respect layer/column mute+solo while building SunVox patterns.
            // Global layer solo: if any layer is soloed, only layer-soloed layers are audible.
            // Per-layer column solo: if any column in that layer is soloed, only soloed columns there.
            int should_mute = !sunvox_wrapper_is_cell_audible(section_index, col);

            if (should_mute || !cell || cell->sample_slot == -1) {
                // Empty cell - clear pattern event
                sv_set_pattern_event(SUNVOX_SLOT, pat_id, col, local_line, 
                                    0, 0, 0, 0, 0);
                empty_cells++;
            } else {
                // Set note event
                int layer = table_get_layer_for_col(section_index, col);
                int mod_id = get_sampler_module_for_layer_slot(layer, cell->sample_slot);
                if (mod_id >= 0) {
                    synced_cells++;
                    float volume = (cell->settings.volume == DEFAULT_CELL_VOLUME) 
                        ? sample_bank_get_sample(cell->sample_slot)->settings.volume 
                        : cell->settings.volume;
                    int velocity = (int)(volume * 128.0f);
                    if (velocity < 1) velocity = 1;
                    if (velocity > 128) velocity = 128;
                    
                    // Resolve pitch
                    float pitch = (cell->settings.pitch == DEFAULT_CELL_PITCH)
                        ? sample_bank_get_sample(cell->sample_slot)->settings.pitch
                        : cell->settings.pitch;
                    
                    // Guard for log2f
                    if (pitch <= 0.0f) {
                        pitch = 1.0f;
                    }
                    // Convert pitch ratio to semitones
                    float semitones = 12.0f * log2f(pitch);
                    int final_note = SUNVOX_BASE_NOTE + (int)roundf(semitones);
                    if (final_note < 0) final_note = 0;
                    if (final_note > 127) final_note = 127;

                    sv_set_pattern_event(
                        SUNVOX_SLOT, 
                        pat_id, 
                        col, 
                        local_line, 
                        final_note,        // note
                        velocity,          // velocity
                        mod_id + 1,        // module
                        0,                 // no controller
                        0                  // no controller value
                    );
                } else {
                    // Cell has data but module doesn't exist
                    prnt_err("⚠️ [SUNVOX] Cell [%d, %d] slot=%d but module doesn't exist (mod_id=%d)", 
                             global_step, col, cell->sample_slot, mod_id);
                }
            }
            
            sv_unlock_slot(SUNVOX_SLOT);
        }
    }
    
    prnt("✅ [SUNVOX] Section %d sync complete: %d notes synced, %d cells cleared", 
         section_index, synced_cells, empty_cells);
}

// Set playback mode and update timeline
void sunvox_wrapper_set_playback_mode(int song_mode, int current_section, int current_loop) {
    int mode_changed = (g_song_mode != song_mode);
    int was_loop_mode = !g_song_mode;
    
    g_song_mode = song_mode;
    g_current_section = current_section;
    
    // ===== NO-CLONE SOLUTION: Use pattern loop counting =====
    
    if (song_mode) {
        // Song mode: Setup pattern sequence and loop counts
        prnt_debug("🎵 [SUNVOX] Entering SONG MODE");
        
        // Get sections and their loop counts from playback state
        const PlaybackState* pb_state = playback_get_state_ptr();
        int sections_count = table_get_sections_count();
        
        // Build pattern sequence array
        int pattern_sequence[64];
        int seq_count = 0;
        
        for (int i = 0; i < sections_count && seq_count < 64; i++) {
            int pat_id = g_section_patterns[i];
            if (pat_id < 0) continue;
            
            int loops = pb_state ? pb_state->sections_loops_num_storage[i] : 1;
            
            // Set loop count for this pattern
            sv_set_pattern_loop_count(SUNVOX_SLOT, pat_id, loops);
            prnt("  📍 [SUNVOX] Pattern %d (section %d): %d loops", pat_id, i, loops);
            
            // Add to sequence
            pattern_sequence[seq_count++] = pat_id;
        }
        
        sv_set_pattern_sequence(SUNVOX_SLOT, pattern_sequence, seq_count);
        prnt("  📋 [SUNVOX] Pattern sequence: %d patterns", seq_count);
        
        // Find the pattern corresponding to the *current_section* to start from.
        int start_pat = -1;
        if (current_section >= 0 && current_section < sections_count) {
            start_pat = g_section_patterns[current_section];
        }

        // Fallback to the first pattern in the sequence if the current section has no pattern.
        if (start_pat < 0 && seq_count > 0) {
            start_pat = pattern_sequence[0];
        }

        if (start_pat >= 0) {
            sv_set_pattern_loop(SUNVOX_SLOT, start_pat);
            sv_set_autostop(SUNVOX_SLOT, 1);
            prnt("  ▶️ [SUNVOX] Starting song mode from pattern %d (section %d)", start_pat, current_section);
        }
        sunvox_wrapper_apply_section_layer_reverb(current_section);
        sunvox_wrapper_apply_section_layer_eq(current_section);
        sunvox_wrapper_apply_section_layer_volume(current_section);
    } else {
        // Loop mode: Enable infinite loop for current section
        prnt_debug("🔁 [SUNVOX] Entering LOOP MODE (section %d)", current_section);
        
        int pat_id = g_section_patterns[current_section];
        if (pat_id >= 0) {
            // CRITICAL FIX: Clear pattern sequence to prevent advancement
            prnt("  🗑️ [SUNVOX] Clearing pattern sequence for loop mode");
            int empty_sequence[1] = {pat_id};
            sv_set_pattern_sequence(SUNVOX_SLOT, empty_sequence, 1);
            
            // Set infinite loop (0 = infinite)
            sv_set_pattern_loop_count(SUNVOX_SLOT, pat_id, 0);
            prnt("  ⚙️ [SUNVOX] Set pattern %d loop_count=0 (infinite)", pat_id);
            
            // Calculate seamless position if switching from song mode
            int current_line = sv_get_current_line(SUNVOX_SLOT);
            int pat_lines = sv_get_pattern_lines(SUNVOX_SLOT, pat_id);
            int pat_x = sv_get_pattern_x(SUNVOX_SLOT, pat_id);
            
            int offset_from_start = current_line - pat_x;
            int local_offset = offset_from_start % pat_lines;
            int target_line = pat_x + local_offset;
            
            if (mode_changed && !was_loop_mode) {
                // CRITICAL: Set position FIRST, then enable pattern loop
                prnt("  🔄 [SUNVOX] Setting position to line %d (step %d within pattern)", 
                     target_line, local_offset);
                sv_set_position(SUNVOX_SLOT, target_line);
            }
            
            // Enable pattern loop (playhead is now in valid range)
            sv_set_pattern_loop(SUNVOX_SLOT, pat_id);
            sv_set_autostop(SUNVOX_SLOT, 0);  // Infinite loop
            prnt("  🔁 [SUNVOX] Looping pattern %d infinitely", pat_id);
        }
        sunvox_wrapper_apply_section_layer_reverb(current_section);
        sunvox_wrapper_apply_section_layer_eq(current_section);
        sunvox_wrapper_apply_section_layer_volume(current_section);
    }
}

// SEAMLESS timeline update for pattern size changes (add/remove steps)
// Updates pattern positions and forces boundary recalculation WITHOUT stopping playback
void sunvox_wrapper_update_timeline_seamless(int section_index) {
    if (!g_sunvox_initialized || g_updating_timeline) {
        prnt("⚠️ [SUNVOX TIMELINE SEAMLESS] Skipped: initialized=%d, updating=%d", 
             g_sunvox_initialized, g_updating_timeline);
        return;
    }
    g_updating_timeline = 1;
    
    int sections_count = table_get_sections_count();
    int was_playing = (sv_end_of_song(SUNVOX_SLOT) == 0);
    int current_line = sv_get_current_line(SUNVOX_SLOT);
    
    prnt("🗺️ [SUNVOX TIMELINE SEAMLESS] === RECALCULATING PATTERN POSITIONS ===");
    prnt("🗺️ [SUNVOX TIMELINE SEAMLESS] section_index=%d, sections_count=%d, was_playing=%d", 
         section_index, sections_count, was_playing);
    
    // CRITICAL: Track by pattern ID, not section index (for reordering support)
    int playing_pattern_id = -1;
    int pattern_local_offset = 0;
    if (was_playing) {
        for (int i = 0; i < sections_count; i++) {
            int pat_id = g_section_patterns[i];
            if (pat_id < 0) continue;
            int pat_x = sv_get_pattern_x(SUNVOX_SLOT, pat_id);
            int pat_lines = sv_get_pattern_lines(SUNVOX_SLOT, pat_id);
            if (current_line >= pat_x && current_line < pat_x + pat_lines) {
                playing_pattern_id = pat_id;  // Save pattern ID, not section index
                pattern_local_offset = current_line - pat_x;
                break;
            }
        }
    }
    
    // Save loop counter before refreshing (song mode only)
    int saved_loop_counter = -1;
    if (was_playing && g_song_mode && playing_pattern_id >= 0) {
        saved_loop_counter = sv_get_pattern_current_loop(SUNVOX_SLOT, playing_pattern_id);
    }
    
    // Update pattern X positions and recalculate proj_lines atomically (within lock)
    sv_lock_slot(SUNVOX_SLOT);
    
    prnt("🗺️ [SUNVOX TIMELINE SEAMLESS] Recalculating X positions for all patterns:");
    int timeline_x = 0;
    int mismatches = 0;
    for (int i = 0; i < sections_count; i++) {
        int pat_id = g_section_patterns[i];
        if (pat_id < 0) {
            prnt("  ⚠️ Section %d: NO PATTERN (skipped)", i);
            continue;
        }
        int pat_lines = sv_get_pattern_lines(SUNVOX_SLOT, pat_id);
        int table_steps = table_get_section_step_count(i);
        int table_start = table_get_section_start_step(i);
        
        sv_set_pattern_xy(SUNVOX_SLOT, pat_id, timeline_x, i);
        
        // Verify consistency between table and SunVox
        if (pat_lines != table_steps) {
            prnt("  ❌ Section %d: MISMATCH! Pattern %d has %d lines but table has %d steps!", 
                 i, pat_id, pat_lines, table_steps);
            mismatches++;
        } else if (timeline_x != table_start) {
            prnt("  ⚠️ Section %d: Position mismatch! Pattern X=%d but table start=%d (diff=%d)", 
                 i, timeline_x, table_start, timeline_x - table_start);
        } else {
            prnt("  ✅ Section %d: Pattern %d at x=%d (%d lines, ends at %d) [table consistent]", 
                 i, pat_id, timeline_x, pat_lines, timeline_x + pat_lines);
        }
        timeline_x += pat_lines;
    }
    prnt("🗺️ [SUNVOX TIMELINE SEAMLESS] Total timeline length: %d lines", timeline_x);
    if (mismatches > 0) {
        prnt("⚠️ [SUNVOX TIMELINE SEAMLESS] WARNING: Found %d pattern/table size mismatches!", mismatches);
    }
    prnt("🗺️ [SUNVOX TIMELINE SEAMLESS] ==========================================");
    
    // Calculate new playhead position
    int new_line = 0;
    if (playing_pattern_id >= 0) {
        int new_pat_x = sv_get_pattern_x(SUNVOX_SLOT, playing_pattern_id);
        int new_pat_lines = sv_get_pattern_lines(SUNVOX_SLOT, playing_pattern_id);
        // Clamp offset if pattern shrank
        if (pattern_local_offset >= new_pat_lines) {
            pattern_local_offset = new_pat_lines - 1;
        }
        new_line = new_pat_x + pattern_local_offset;
    }
    
    // CRITICAL: Call sv_set_position() WHILE LOCK HELD to prevent race condition
    // This forces proj_lines recalculation atomically with pattern position updates
    // sv_set_position() -> sunvox_set_position() -> sunvox_sort_patterns() -> proj_lines updated
    // Without atomic execution, audio callback can see stale proj_lines between updates
    sv_set_position(SUNVOX_SLOT, new_line);
    
    sv_unlock_slot(SUNVOX_SLOT);
    
    // Refresh mode-specific settings
    if (was_playing) {
        if (g_song_mode && playing_pattern_id >= 0) {
            // Song mode: Refresh loop counts and restore counter
            const PlaybackState* pb_state = playback_get_state_ptr();
            for (int i = 0; i < sections_count; i++) {
                int pat_id = g_section_patterns[i];
                if (pat_id < 0) continue;
                int loops = pb_state ? pb_state->sections_loops_num_storage[i] : 1;
                sv_set_pattern_loop_count(SUNVOX_SLOT, pat_id, loops);
            }
            
            // Restore loop counter for currently playing pattern
            if (saved_loop_counter >= 0) {
                sv_set_pattern_current_loop(SUNVOX_SLOT, playing_pattern_id, saved_loop_counter);
            }
            
            sv_set_pattern_loop(SUNVOX_SLOT, playing_pattern_id);
            sv_set_autostop(SUNVOX_SLOT, 1);
            
        } else if (section_index == g_current_section && g_section_patterns[section_index] >= 0) {
            // Loop mode: Refresh infinite loop on resized pattern
            int loop_pat_id = g_section_patterns[section_index];
            sv_set_pattern_loop_count(SUNVOX_SLOT, loop_pat_id, 0);  // 0 = infinite
            sv_set_pattern_loop(SUNVOX_SLOT, loop_pat_id);
            sv_set_autostop(SUNVOX_SLOT, 0);
        }
    }
    
    g_updating_timeline = 0;
}

// Seamless section reordering
// Called after table_reorder_section has already moved the data
void sunvox_wrapper_reorder_section(int from_index, int to_index) {
    prnt_debug("🔄 [SUNVOX] Seamless reorder: section %d → %d", from_index, to_index);
    
    // CRITICAL: Reorder the pattern associations to match the new section order
    // Save the pattern ID being moved
    int moving_pattern_id = g_section_patterns[from_index];
    
    // Shift pattern associations to match table reorder
    if (from_index < to_index) {
        // Moving down: shift patterns [from+1..to] up by one
        for (int i = from_index; i < to_index; i++) {
            g_section_patterns[i] = g_section_patterns[i + 1];
        }
        g_section_patterns[to_index] = moving_pattern_id;
    } else {
        // Moving up: shift patterns [to..from-1] down by one
        for (int i = from_index; i > to_index; i--) {
            g_section_patterns[i] = g_section_patterns[i - 1];
        }
        g_section_patterns[to_index] = moving_pattern_id;
    }
    
    prnt("  ↪️ [SUNVOX] Pattern associations reordered");
    
    // Use seamless update - it now tracks by pattern ID so reordering works correctly
    // Pass -1 as section_index since we don't need loop mode refresh (reorder affects all modes)
    sunvox_wrapper_update_timeline_seamless(-1);
}

// Update timeline with current section order
// NEW: Always use song mode layout (all patterns + clones)
// Mode switching handled by sv_set_pattern_loop(), NOT by rebuilding timeline!
void sunvox_wrapper_update_timeline(void) {
    if (!g_sunvox_initialized) return;
    
    // Prevent recursion
    if (g_updating_timeline) {
        prnt("⚠️ [SUNVOX] update_timeline called recursively, skipping");
        return;
    }
    g_updating_timeline = 1;
    
    int sections_count = table_get_sections_count();
    
    // Check if playback is active
    int was_playing = (sv_end_of_song(SUNVOX_SLOT) == 0);
    
    // Stop playback before timeline rebuild to avoid glitches
    // (Note: This only happens during initial setup or section structure changes,
    //  NOT during mode switching which is now seamless!)
    if (was_playing) {
        prnt("⏸️ [SUNVOX] Stopping playback for timeline rebuild");
        sv_stop(SUNVOX_SLOT);
    }
    
    // ===== NO-CLONE APPROACH: Simple linear layout =====
    // One pattern per section, placed sequentially
    // Loop counting is handled in SunVox engine via sv_set_pattern_loop_count()
    prnt_debug("📋 [SUNVOX] Building simple timeline: %d sections (NO CLONES)", sections_count);
    
    sv_lock_slot(SUNVOX_SLOT);
    
    // Layout patterns sequentially
    prnt("🗺️ [SUNVOX TIMELINE] === BUILDING PATTERN LAYOUT ===");
    int timeline_x = 0;
    for (int i = 0; i < sections_count; i++) {
        int pat_id = g_section_patterns[i];
        if (pat_id < 0) continue;
        
        int pat_lines = sv_get_pattern_lines(SUNVOX_SLOT, pat_id);
        
        // Place pattern at current X position
        sv_set_pattern_xy(SUNVOX_SLOT, pat_id, timeline_x, i);
        prnt("  📍 [SUNVOX] Section %d: Pattern %d at x=%d (%d lines, ends at %d)", 
             i, pat_id, timeline_x, pat_lines, timeline_x + pat_lines);
        
        timeline_x += pat_lines;
    }
    
    sv_unlock_slot(SUNVOX_SLOT);
    prnt("✅ [SUNVOX] Simple timeline built: %d lines total (0 clones)", timeline_x);
    prnt("🗺️ [SUNVOX TIMELINE] ===================================");
    
    g_updating_timeline = 0;
    
    
    // Always rewind to beginning after timeline rebuild
    sv_rewind(SUNVOX_SLOT, 0);
    
    if (was_playing) {
        // Resume playback from beginning
        prnt("▶️ [SUNVOX] Restarting playback from beginning (timeline rebuild)");
        sv_play(SUNVOX_SLOT);
        
    } else {
        // Playback was stopped
        prnt_debug("⏮️ [SUNVOX] Rewound to beginning (playback stopped)");
    }
}

// Start playback
int sunvox_wrapper_play(void) {
    if (!g_sunvox_initialized) {
        prnt_err("❌ [SUNVOX] Not initialized");
        return -1;
    }
    
    prnt("▶️ [SUNVOX] Starting playback from current position");
    
    // Debug: Check audio status
    int audio_callback = sv_get_sample_rate();
    prnt_debug("🔊 [SUNVOX] Audio sample rate: %d Hz", audio_callback);
    
    // Debug: Check module volume and mute status
    for (int i = 0; i < 3; i++) {
        int mod_id = get_sampler_module_for_layer_slot(0, i);
        if (mod_id >= 0) {
            uint32_t flags = sv_get_module_flags(SUNVOX_SLOT, mod_id);
            int muted = (flags & SV_MODULE_FLAG_MUTE) != 0;
            prnt_debug("🔍 [SUNVOX] Module %d: exists=%d, muted=%d", 
                 mod_id, (flags & SV_MODULE_FLAG_EXISTS) != 0, muted);
        }
    }
    
    // Use sv_play() to start from current position (set by sv_rewind)
    int result = sv_play(SUNVOX_SLOT);
    if (result < 0) {
        prnt_err("❌ [SUNVOX] Failed to start playback: %d", result);
        return -1;
    }
    
    // Verify playback status
    int status = sv_end_of_song(SUNVOX_SLOT);
    prnt_debug("🎵 [SUNVOX] Playback status after start: %d (0=playing)", status);
    
    return 0;
}

// Stop playback
void sunvox_wrapper_stop(void) {
    if (!g_sunvox_initialized) return;
    
    prnt_debug("⏹️ [SUNVOX] Stopping playback");
    
    // Send all notes off on all tracks to immediately stop all playing sounds
    sv_lock_slot(SUNVOX_SLOT);
    for (int track = 0; track < table_get_max_cols(); track++) {
        // Send NOTE_OFF (128) to all modules on this track
        sv_send_event(SUNVOX_SLOT, track, 128, 0, 0, 0, 0);
    }
    sv_unlock_slot(SUNVOX_SLOT);
    
    sv_stop(SUNVOX_SLOT);
    
    prnt_debug("✅ [SUNVOX] Stopped playback and sent all notes off");
}

// Set BPM
void sunvox_wrapper_set_bpm(int bpm) {
    if (!g_sunvox_initialized) return;
    
    // Clamp BPM to valid SunVox range (1-16000)
    if (bpm < 1) bpm = 1;
    if (bpm > 16000) bpm = 16000;
    
    prnt_debug("🎵 [SUNVOX] Setting BPM to %d", bpm);
    
    // Set BPM using SunVox effect 0x1F
    // sv_send_event(slot, track_num, note, vel, module, ctl, ctl_val)
    // - slot: SUNVOX_SLOT (0)
    // - track_num: 0 (first track)
    // - note: 0 (no note)
    // - vel: 0 (no velocity)
    // - module: 0 (no specific module)
    // - ctl: 0x1F (BPM effect code)
    // - ctl_val: bpm (the BPM value)
    
    sv_lock_slot(SUNVOX_SLOT);
    int result = sv_send_event(SUNVOX_SLOT, 0, 0, 0, 0, 0x1F, bpm);
    sv_unlock_slot(SUNVOX_SLOT);
    
    if (result < 0) {
        prnt_err("❌ [SUNVOX] Failed to set BPM: sv_send_event returned %d", result);
    } else {
        // Verify the BPM was actually set by reading it back
        int actual_bpm = sv_get_song_bpm(SUNVOX_SLOT);
        if (actual_bpm == bpm) {
            prnt("✅ [SUNVOX] BPM set to %d successfully (verified)", bpm);
        } else {
            prnt("⚠️ [SUNVOX] BPM set command sent, but verification shows %d instead of %d", actual_bpm, bpm);
        }
    }
}

// Set playback region (loop range)
void sunvox_wrapper_set_region(int start, int end) {
    if (!g_sunvox_initialized) return;
    
    prnt_debug("🎭 [SUNVOX] Setting region: %d to %d", start, end);
    
    // Stop all currently playing notes by sending note-off to all samplers
    // Only needed if playback is active
    int is_playing = (sv_end_of_song(SUNVOX_SLOT) == 0);
    
    if (is_playing) {
        sv_lock_slot(SUNVOX_SLOT);
        
        int max_cols = table_get_max_cols();
        for (int track = 0; track < max_cols; track++) {
            for (int layer = 0; layer < MAX_LAYERS_PER_SECTION; layer++) {
                for (int i = 0; i < MAX_SAMPLE_SLOTS; i++) {
                    int mod_id = get_sampler_module_for_layer_slot(layer, i);
                    if (mod_id >= 0) {
                        sv_send_event(SUNVOX_SLOT, track, 128, 0, mod_id + 1, 0, 0);
                    }
                }
            }
        }
        
        sv_unlock_slot(SUNVOX_SLOT);
        
        prnt("🔇 [SUNVOX] Stopped all playing notes for region change");
    }
}

// Get current playback line/step
int sunvox_wrapper_get_current_line(void) {
    if (!g_sunvox_initialized) return -1;
    
    return sv_get_current_line(SUNVOX_SLOT);
}

// Get pattern X position for a section (for calculating local position in loop mode)
int sunvox_wrapper_get_section_pattern_x(int section_index) {
    if (!g_sunvox_initialized) return 0;
    if (section_index < 0 || section_index >= MAX_SECTIONS) return 0;
    
    int pat_id = g_section_patterns[section_index];
    if (pat_id < 0) return 0;
    
    return sv_get_pattern_x(SUNVOX_SLOT, pat_id);
}

// Trigger notes at a specific step
void sunvox_wrapper_trigger_step(int step) {
    if (!g_sunvox_initialized) return;
    
    prnt_debug("🎯 [SUNVOX] Triggering notes at step %d", step);
    
    int section = table_get_section_at_step(step);
    if (section < 0) return;

    sv_lock_slot(SUNVOX_SLOT);
    
    int max_cols = table_get_max_cols();
    for (int col = 0; col < max_cols; col++) {
        Cell* cell = table_get_cell(step, col);
        if (!cell || cell->sample_slot == -1) {
            continue; // Empty cell
        }

        if (!sunvox_wrapper_is_cell_audible(section, col)) continue;
        
        int layer = table_get_layer_for_col(section, col);
        int mod_id = get_sampler_module_for_layer_slot(layer, cell->sample_slot);
        if (mod_id < 0) {
            continue; // Sample not loaded
        }
        
        // Calculate velocity
        float volume = (cell->settings.volume == DEFAULT_CELL_VOLUME) 
            ? sample_bank_get_sample(cell->sample_slot)->settings.volume 
            : cell->settings.volume;
        int velocity = (int)(volume * 128.0f);
        if (velocity < 1) velocity = 1;
        if (velocity > 128) velocity = 128;
        
        // Resolve and convert pitch to note
        float pitch = (cell->settings.pitch == DEFAULT_CELL_PITCH)
            ? sample_bank_get_sample(cell->sample_slot)->settings.pitch
            : cell->settings.pitch;
        
        if (pitch <= 0.0f) {
            pitch = 1.0f;
        }
        float semitones = 12.0f * log2f(pitch);
        int final_note = SUNVOX_BASE_NOTE + (int)roundf(semitones);
        if (final_note < 0) final_note = 0;
        if (final_note > 127) final_note = 127;

        // Send note-on event
        // sv_send_event(slot, track, note, vel, module, ctl, ctl_val)
        sv_send_event(
            SUNVOX_SLOT,        // slot
            col,                // track/column
            final_note,         // note
            velocity,           // velocity
            mod_id + 1,         // module (sampler ID + 1)
            0,                  // no controller
            0                   // no controller value
        );
        
        prnt_debug("🎵 [SUNVOX] Triggered note [step=%d, col=%d]: mod=%d, vel=%d, note=%d", 
             step, col, mod_id, velocity, final_note);
    }
    
    sv_unlock_slot(SUNVOX_SLOT);
}

// Render audio frames (called from audio callback)
int sunvox_wrapper_render(float* buf, int frames) {
    if (!g_sunvox_initialized) return 0;
    
    // Call SunVox audio callback to render audio
    uint32_t out_time = sv_get_ticks();
    return sv_audio_callback(buf, frames, 0, out_time);
}

// Check if SunVox is initialized
int sunvox_wrapper_is_initialized(void) {
    return g_sunvox_initialized;
}

// Debug: Dump all pattern information (disabled to reduce log noise)
// void sunvox_wrapper_debug_dump_patterns(const char* context) {
//     if (!g_sunvox_initialized) return;
//
//     prnt_debug("🔍 [SUNVOX DEBUG DUMP] ========== %s ==========", context);
//
//     // Get number of pattern slots from SunVox
//     int num_pattern_slots = sv_get_number_of_patterns(SUNVOX_SLOT);
//     prnt_debug("🔍 [SUNVOX DEBUG] SunVox has %d pattern slots", num_pattern_slots);
//
//     // List all patterns that exist (slots that contain patterns)
//     int actual_patterns = 0;
//     for (int i = 0; i < num_pattern_slots; i++) {
//         int lines = sv_get_pattern_lines(SUNVOX_SLOT, i);
//         if (lines > 0) {
//             actual_patterns++;
//             int tracks = sv_get_pattern_tracks(SUNVOX_SLOT, i);
//             int x = sv_get_pattern_x(SUNVOX_SLOT, i);
//             int y = sv_get_pattern_y(SUNVOX_SLOT, i);
//             const char* name = sv_get_pattern_name(SUNVOX_SLOT, i);
//
//             prnt("🔍   Pattern %d: \"%s\" - %d x %d lines, position (%d, %d)",
//                  i, name ? name : "???", tracks, lines, x, y);
//         }
//     }
//     prnt_debug("🔍 [SUNVOX DEBUG] %d actual patterns exist (out of %d slots)", actual_patterns, num_pattern_slots);
//
//     // Show our mapping
//     prnt_debug("🔍 [SUNVOX DEBUG] Our section->pattern mapping:");
//     for (int i = 0; i < MAX_SECTIONS; i++) {
//         if (g_section_patterns[i] >= 0) {
//             int lines = sv_get_pattern_lines(SUNVOX_SLOT, g_section_patterns[i]);
//             prnt("🔍   Section %d -> Pattern %d (%d lines)", i, g_section_patterns[i], lines);
//         }
//     }
//
//     // Get song length
//     int song_length = sv_get_song_length_lines(SUNVOX_SLOT);
//     prnt_debug("🔍 [SUNVOX DEBUG] Song length (from sv_get_song_length_lines): %d lines", song_length);
//
//     // Get current line
//     int current_line = sv_get_current_line(SUNVOX_SLOT);
//     prnt_debug("🔍 [SUNVOX DEBUG] Current playback line: %d", current_line);
//
//     // Get autostop setting
//     int autostop = sv_get_autostop(SUNVOX_SLOT);
//     prnt_debug("🔍 [SUNVOX DEBUG] Autostop: %d (0=loop, 1=stop at end)", autostop);
//
//     // Get playback status
//     int playing = (sv_end_of_song(SUNVOX_SLOT) == 0);
//     prnt_debug("🔍 [SUNVOX DEBUG] Playing: %s", playing ? "YES" : "NO");
//
//     prnt_debug("🔍 [SUNVOX DEBUG] ================================");
// }

int sunvox_wrapper_get_pattern_current_loop(int section_index) {
    if (!g_sunvox_initialized) return 0;
    if (section_index < 0 || section_index >= MAX_SECTIONS) return 0;
    
    int pat_id = g_section_patterns[section_index];
    if (pat_id < 0) return 0;
    
    return sv_get_pattern_current_loop(SUNVOX_SLOT, pat_id);
}


// ===== Live Preview (SunVox-based) =====
// Plays short notes for sample slots or specific cells without touching patterns.
// Always overlays current playback and sustains until the next change/end.
// Track selection is derived from current table columns to remain valid if max columns changes.

static int g_preview_active = 0;
static int g_preview_module = -1; // sampler module id
static int g_preview_track = 0;   // track used for preview note-on/off
static int g_preview_note = 0;    // last note triggered

static inline int preview_compute_track(void) {
    int max_cols = table_get_max_cols();
    if (max_cols <= 0) return 0;
    // Use the last available track to avoid collisions with visible lanes
    return max_cols - 1;
}

static inline int preview_velocity_from_volume(float volume01) {
    if (volume01 <= 0.0f) return 0;
    int velocity = (int)(volume01 * 128.0f);
    if (velocity < 1) velocity = 1;
    if (velocity > 128) velocity = 128;
    return velocity;
}

static inline int preview_note_from_pitch(float ratio) {
    if (ratio <= 0.0f) ratio = 1.0f;
    float semitones = 12.0f * log2f(ratio);
    int final_note = SUNVOX_BASE_NOTE + (int)roundf(semitones);
    if (final_note < 0) final_note = 0;
    if (final_note > 127) final_note = 127;
    return final_note;
}

static void preview_stop_internal(void) {
    if (!g_sunvox_initialized) return;
    if (!g_preview_active || g_preview_module < 0) return;

    int track = g_preview_track;
    int module_plus = g_preview_module + 1;

    // Send NOTE_OFF for the previous preview note on the same track/module
    sv_send_event(SUNVOX_SLOT, track, 128 /* NOTE_OFF */, 0, module_plus, 0, 0);

    g_preview_active = 0;
    g_preview_module = -1;
    g_preview_note = 0;
}

extern "C" void sunvox_preview_stop(void) {
    preview_stop_internal();
}

extern "C" int sunvox_preview_slot(int slot, float pitch, float volume) {
    if (!g_sunvox_initialized) return -1;
    if (slot < 0 || slot >= MAX_SAMPLE_SLOTS) return -1;

    // Volume 0 => stop preview, don't play
    if (volume <= 0.0f) {
        preview_stop_internal();
        return 0;
    }

    int mod_id = get_preview_dry_sampler_for_slot(slot);
    if (mod_id < 0) return -1;

    // Stop previous preview (if any)
    preview_stop_internal();

    int track = preview_compute_track();
    int note = preview_note_from_pitch(pitch);
    int vel = preview_velocity_from_volume(volume);

    int res = sv_send_event(SUNVOX_SLOT, track, note, vel, mod_id + 1, 0, 0);
    if (res < 0) return res;

    g_preview_active = 1;
    g_preview_module = mod_id;
    g_preview_track = track;
    g_preview_note = note;
    return 0;
}

extern "C" int sunvox_preview_cell(int step, int column, float pitch, float volume) {
    if (!g_sunvox_initialized) return -1;
    if (step < 0 || column < 0) return -1;

    // Resolve cell
    Cell* cell = table_get_cell(step, column);
    if (!cell || cell->sample_slot < 0 || cell->sample_slot >= MAX_SAMPLE_SLOTS) return -1;

    // Resolve effective volume
    float resolved_volume = volume;
    if (resolved_volume == DEFAULT_CELL_VOLUME) {
        Sample* s = sample_bank_get_sample(cell->sample_slot);
        resolved_volume = (s && s->loaded) ? s->settings.volume : 1.0f;
    }
    if (resolved_volume <= 0.0f) {
        preview_stop_internal();
        return 0;
    }

    // Resolve effective pitch
    float resolved_pitch = pitch;
    if (resolved_pitch == DEFAULT_CELL_PITCH) {
        Sample* s = sample_bank_get_sample(cell->sample_slot);
        resolved_pitch = (s && s->loaded) ? s->settings.pitch : 1.0f;
    }

    int section = table_get_section_at_step(step);
    int layer = table_get_layer_for_col(section, column);
    int mod_id = get_sampler_module_for_layer_slot(layer, cell->sample_slot);
    if (mod_id < 0) return -1;

    // Stop previous preview
    preview_stop_internal();

    int track = preview_compute_track();
    int note = preview_note_from_pitch(resolved_pitch);
    int vel = preview_velocity_from_volume(resolved_volume);

    int res = sv_send_event(SUNVOX_SLOT, track, note, vel, mod_id + 1, 0, 0);
    if (res < 0) return res;

    g_preview_active = 1;
    g_preview_module = mod_id;
    g_preview_track = track;
    g_preview_note = note;
    return 0;
}

// ===== Microphone Input Module Management =====
// NOTE: Input module removed - mic recording now bypasses SunVox entirely
// Mic audio is captured directly to WAV file without going through SunVox
// See docs/features/microphone_dual_output_architecture.md for archived approach

// Wrapper for SunVox sv_get_module_scope2 (for waveform visualization)
// This wrapper is needed to expose the SunVox function through FFI with proper visibility
uint32_t sunvox_wrapper_get_module_scope2(int slot, int mod_num, int channel, int16_t* dest_buf, uint32_t samples_to_read) {
    // Forward call to actual SunVox function (already available from sunvox.h)
    return sv_get_module_scope2(slot, mod_num, channel, dest_buf, samples_to_read);
}
