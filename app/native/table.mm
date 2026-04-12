#include "table.h"
#include "undo_redo.h"
#include "sunvox_wrapper.h"  // For SunVox pattern sync
#include "playback.h"         // For switch_to_section
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <string>
#include <math.h>

// Platform-specific logging
#ifdef __APPLE__
    #include "log.h"
    #undef LOG_TAG
    #define LOG_TAG "TABLE"
#elif defined(__ANDROID__)
    #include "log.h"
    #undef LOG_TAG
    #define LOG_TAG "TABLE"
#else
    #include "log.h"
    #undef LOG_TAG
    #define LOG_TAG "TABLE"
#endif

// Global table state consolidated into a single struct
static TableState g_table_state; // zero-initialized

// Layer mute/solo state (per-layer index 0..MAX_LAYERS_PER_SECTION-1)
static uint8_t g_layer_mute[MAX_LAYERS_PER_SECTION] = {0};
static uint8_t g_layer_solo[MAX_LAYERS_PER_SECTION] = {0};
// Per-column mute/solo:
// - mute is per (layer, col_in_layer)
// - solo is per (layer, col_in_layer)
static uint8_t g_layer_col_mute[MAX_LAYERS_PER_SECTION][MAX_COLS_PER_LAYER] = {{0}};
static uint8_t g_layer_col_solo[MAX_LAYERS_PER_SECTION][MAX_COLS_PER_LAYER] = {{0}};

// Flag to disable automatic SunVox sync during bulk operations (import/undo/redo)
static int g_disable_sunvox_sync = 0;
// Transaction mode for batched UI edits.
// While active, we suppress per-cell SunVox sync and per-cell undo records.
static int g_edit_txn_depth = 0;
static uint8_t g_edit_txn_touched_sections[MAX_SECTIONS] = {0};

// Seqlock helper functions for unified state
static inline void state_write_begin() {
    g_table_state.version++; // odd = write in progress
}

static inline void state_write_end() {
    g_table_state.version++; // even = stable
}

// Dirty marker used by Flutter to avoid rescanning visible cells when table
// content has not changed. This is separate from seqlock `version`:
// - `version` protects snapshot consistency during concurrent writes.
// - `content_epoch` signals that content changed since last seen value.
static inline void table_mark_content_changed() {
    g_table_state.content_epoch++;
    if (g_table_state.content_epoch == 0) {
        g_table_state.content_epoch = 1;
    }
}

// Helper to set a cell to default values
static inline void table_set_cell_defaults(Cell* cell) {
    if (!cell) return;
    cell->sample_slot = -1;
    cell->settings.volume = DEFAULT_CELL_VOLUME;
    cell->settings.pitch = DEFAULT_CELL_PITCH;
    cell->is_processing = 0;
}

static inline uint8_t clamp_u8(int v) {
    if (v < 0) return 0;
    if (v > 255) return 255;
    return (uint8_t)v;
}

static inline int8_t clamp_eq_db(int v) {
    if (v < SECTION_LAYER_EQ_MIN_DB) return SECTION_LAYER_EQ_MIN_DB;
    if (v > SECTION_LAYER_EQ_MAX_DB) return SECTION_LAYER_EQ_MAX_DB;
    return (int8_t)v;
}

static inline void table_txn_reset_touched_sections() {
    memset(g_edit_txn_touched_sections, 0, sizeof(g_edit_txn_touched_sections));
}

static inline void table_txn_mark_section_touched(int section_index) {
    if (section_index < 0 || section_index >= MAX_SECTIONS) return;
    g_edit_txn_touched_sections[section_index] = 1;
}

static inline void table_txn_mark_step_touched_internal(int step) {
    if (step < 0 || step >= MAX_SEQUENCER_STEPS) return;
    const int section = table_get_section_at_step(step);
    table_txn_mark_section_touched(section);
}

// Helper to recompute all section start_step values to ensure they are contiguous
// This ensures there are no gaps or overlaps in the section ranges
// Call this after any operation that modifies section structure or step counts
static void table_recompute_section_starts(void) {
    prnt_debug("🔧 [TABLE_RECOMPUTE] === RECOMPUTING SECTION STARTS ===");
    prnt_debug("🔧 [TABLE_RECOMPUTE] Sections count: %d", g_table_state.sections_count);
    
    int cursor = 0;
    for (int i = 0; i < g_table_state.sections_count; i++) {
        int old_start = g_table_state.sections[i].start_step;
        int num_steps = g_table_state.sections[i].num_steps;
        g_table_state.sections[i].start_step = cursor;
        
        prnt_debug("🔧 [TABLE_RECOMPUTE]   Section %d: start %d -> %d, steps: %d",
                  i, old_start, cursor, num_steps);
        
        cursor += num_steps;
    }
    
    prnt_debug("🔧 [TABLE_RECOMPUTE] Total steps after recompute: %d", cursor);
    prnt_debug("🔧 [TABLE_RECOMPUTE] === RECOMPUTE COMPLETE ===");
}

// Initialize table with default values
void table_init(void) {
    prnt_debug("🎵 [TABLE] Initializing table: %d x %d", MAX_SEQUENCER_STEPS, MAX_SEQUENCER_COLS);
    // Reset mute/solo state so every table init starts from a neutral audible state.
    memset(g_layer_mute, 0, sizeof(g_layer_mute));
    memset(g_layer_solo, 0, sizeof(g_layer_solo));
    memset(g_layer_col_mute, 0, sizeof(g_layer_col_mute));
    memset(g_layer_col_solo, 0, sizeof(g_layer_col_solo));
    
    // Clear all cells
    for (int step = 0; step < MAX_SEQUENCER_STEPS; step++) {
        for (int col = 0; col < MAX_SEQUENCER_COLS; col++) {
            table_set_cell_defaults(&g_table_state.table[step][col]);
        }
    }
    
    g_table_state.sections_count = 1;
    g_table_state.sections[0].start_step = 0;
    g_table_state.sections[0].num_steps = DEFAULT_SECTION_STEPS;  // Default section size

    // Initialize layers metadata for all sections with default lengths
    for (int s = 0; s < MAX_SECTIONS; s++) {
        for (int l = 0; l < MAX_LAYERS_PER_SECTION; l++) {
            g_table_state.layers[s][l].len = MAX_COLS_PER_LAYER;
            g_table_state.section_layer_reverb[s][l].send = 0;
            g_table_state.section_layer_reverb[s][l].room = 128;
            g_table_state.section_layer_reverb[s][l].damp = 128;
            g_table_state.section_layer_eq[s][l].low_db = 0;
            g_table_state.section_layer_eq[s][l].mid_db = 0;
            g_table_state.section_layer_eq[s][l].high_db = 0;
            g_table_state.section_layer_volume[s][l] = 255;
        }
    }

    // Initialize FFI-visible fields for unified state
    g_table_state.version = 0;
    g_table_state.content_epoch = 1;
    g_table_state.table_ptr = &g_table_state.table[0][0];
    g_table_state.sections_ptr = &g_table_state.sections[0];
    g_table_state.layers_ptr = &g_table_state.layers[0][0];
    
    prnt("✅ [TABLE] Table initialized successfully");

    // Note: SunVox patterns will be created in playback_init() after SunVox is initialized
    // Do not seed undo/redo baseline here; a single baseline is recorded after all modules init
}

// Get pointer to cell (direct memory access for Flutter FFI)
Cell* table_get_cell(int step, int col) {
    if (step < 0 || step >= MAX_SEQUENCER_STEPS || col < 0 || col >= MAX_SEQUENCER_COLS) {
        prnt_err("❌ [TABLE] Cell access out of bounds: [%d, %d]", step, col);
        return NULL;
    }
    return &g_table_state.table[step][col];
}

// Set cell data and mark as changed
void table_set_cell(int step, int col, int sample_slot, float volume, float pitch, int undo_record) {
    Cell* cell = table_get_cell(step, col);
    if (!cell) return;
    
    // Validate parameters
    if (sample_slot < -1 || sample_slot >= MAX_SAMPLE_SLOTS) {
        prnt_err("❌ [TABLE] Invalid sample_slot: %d", sample_slot);
        return;
    }
    
    // Update cell
    cell->sample_slot = sample_slot;
    cell->settings.volume = volume;
    cell->settings.pitch = pitch;
    cell->is_processing = 0;
    table_mark_content_changed();
    
    prnt_debug("🎵 [TABLE] Set cell [%d, %d]: slot=%d, vol=%.2f, pitch=%.2f", 
         step, col, sample_slot, volume, pitch);

    // Track touched section for batched edit reconciliation.
    table_txn_mark_step_touched_internal(step);

    // Sync cell to SunVox pattern (unless sync is disabled for bulk operations
    // or we're inside a batched edit transaction).
    if (sunvox_wrapper_is_initialized() && !g_disable_sunvox_sync && g_edit_txn_depth == 0) {
        sunvox_wrapper_sync_cell(step, col);
    }

    if (undo_record && g_edit_txn_depth == 0) {
        UndoRedoManager_record();
    }
}

// Set only volume/pitch settings for a cell
void table_set_cell_settings(int step, int col, float volume, float pitch, int undo_record) {
    Cell* cell = table_get_cell(step, col);
    if (!cell) return;


    cell->settings.volume = volume;
    cell->settings.pitch = pitch;
    table_mark_content_changed();
    prnt_debug("🎚️ [TABLE] Set settings [%d, %d]: vol=%.2f, pitch=%.2f", step, col, volume, pitch);

    // Track touched section for batched edit reconciliation.
    table_txn_mark_step_touched_internal(step);

    // Sync cell to SunVox pattern (unless sync is disabled for bulk operations
    // or we're inside a batched edit transaction).
    if (sunvox_wrapper_is_initialized() && !g_disable_sunvox_sync && g_edit_txn_depth == 0) {
        sunvox_wrapper_sync_cell(step, col);
    }

    if (undo_record && g_edit_txn_depth == 0) {
        UndoRedoManager_record();
    }
}

// Set only sample slot for a cell
void table_set_cell_sample_slot(int step, int col, int sample_slot, int undo_record) {
    Cell* cell = table_get_cell(step, col);
    if (!cell) return;
    if (sample_slot < -1 || sample_slot >= MAX_SAMPLE_SLOTS) {
        prnt_err("❌ [TABLE] Invalid sample_slot: %d", sample_slot);
        return;
    }
    cell->sample_slot = sample_slot;
    table_mark_content_changed();
    prnt("🎵 [TABLE] Set sample slot [%d, %d]: slot=%d", step, col, sample_slot);
    
    // Track touched section for batched edit reconciliation.
    table_txn_mark_step_touched_internal(step);

    // Sync cell to SunVox pattern (unless sync is disabled for bulk operations
    // or we're inside a batched edit transaction).
    if (sunvox_wrapper_is_initialized() && !g_disable_sunvox_sync && g_edit_txn_depth == 0) {
        sunvox_wrapper_sync_cell(step, col);
    }
    
    if (undo_record && g_edit_txn_depth == 0) {
        UndoRedoManager_record();
    }
}

// Clear cell and mark as changed
void table_clear_cell(int step, int col, int undo_record) {
    Cell* cell = table_get_cell(step, col);
    if (!cell) return;
    
    table_set_cell_defaults(cell);
    table_mark_content_changed();
    
    // prnt("🧹 [TABLE] Cleared cell [%d, %d]", step, col);  // Commented out to reduce log spam

    // Track touched section for batched edit reconciliation.
    table_txn_mark_step_touched_internal(step);

    // Sync cell to SunVox pattern (unless sync is disabled for bulk operations
    // or we're inside a batched edit transaction).
    if (sunvox_wrapper_is_initialized() && !g_disable_sunvox_sync && g_edit_txn_depth == 0) {
        sunvox_wrapper_sync_cell(step, col);
    }

    if (undo_record && g_edit_txn_depth == 0) {
        UndoRedoManager_record();
    }
}

// Bulk clear all cells (efficient for import/reset operations)
// This clears all cells in the table without syncing to SunVox
// Used during import when SunVox patterns are reset separately
void table_clear_all_cells(void) {
    prnt("🧹 [TABLE] Bulk clearing all cells (%d x %d = %d cells)", 
         MAX_SEQUENCER_STEPS, MAX_SEQUENCER_COLS, MAX_SEQUENCER_STEPS * MAX_SEQUENCER_COLS);
    
    state_write_begin();
    
    // Clear all cells in one pass
    for (int step = 0; step < MAX_SEQUENCER_STEPS; step++) {
        for (int col = 0; col < MAX_SEQUENCER_COLS; col++) {
            table_set_cell_defaults(&g_table_state.table[step][col]);
        }
    }
    
    state_write_end();
    table_mark_content_changed();
    
    prnt("✅ [TABLE] Bulk clear complete");
    
    // Note: We do NOT sync to SunVox here as this is used during import
    // when patterns are being reset separately. The caller is responsible
    // for syncing after the import is complete.
}

// Insert step at given position
void table_insert_step(int section_index, int at_step, int undo_record) {
    if (section_index < 0 || section_index >= g_table_state.sections_count) {
        prnt_err("❌ [TABLE] Invalid section index: %d", section_index);
        return;
    }
    
    int section_start = g_table_state.sections[section_index].start_step;
    int section_end = section_start + g_table_state.sections[section_index].num_steps;
    
    // Calculate total table size before insertion
    int total_steps = 0;
    for (int i = 0; i < g_table_state.sections_count; i++) {
        total_steps += g_table_state.sections[i].num_steps;
    }
    
    if (at_step < section_start || at_step > section_end || total_steps >= MAX_SEQUENCER_STEPS) {
        prnt_err("❌ [TABLE] Cannot insert step at %d (section: %d-%d, total: %d, max: %d)", 
                 at_step, section_start, section_end, total_steps, MAX_SEQUENCER_STEPS);
        return;
    }
    
    // Mutate under seqlock
    state_write_begin();

    // CRITICAL: Shift ALL rows from the end of table down to insertion point
    // This ensures subsequent sections' data moves down by 1 row
    for (int step = total_steps - 1; step >= at_step; step--) {
        for (int col = 0; col < MAX_SEQUENCER_COLS; col++) {
            g_table_state.table[step + 1][col] = g_table_state.table[step][col];
        }
    }
    
    // Clear the new row at insertion point
    for (int col = 0; col < MAX_SEQUENCER_COLS; col++) {
        table_set_cell_defaults(&g_table_state.table[at_step][col]);
    }
    
    // Increase section length
    g_table_state.sections[section_index].num_steps++;
    // Recompute all section start_step values to eliminate gaps
    table_recompute_section_starts();

    state_write_end();
    table_mark_content_changed();
    
    prnt("➕ [TABLE] Inserted step at %d in section %d (section steps: %d, total steps: %d)", 
         at_step, section_index, g_table_state.sections[section_index].num_steps, total_steps + 1);

    // Recreate SunVox pattern with new size
    sunvox_wrapper_create_section_pattern(section_index, g_table_state.sections[section_index].num_steps);

    if (undo_record) {
        UndoRedoManager_record();
    }
}

// Delete step at given position
void table_delete_step(int section_index, int at_step, int undo_record) {
    if (section_index < 0 || section_index >= g_table_state.sections_count) {
        prnt_err("❌ [TABLE] Invalid section index: %d", section_index);
        return;
    }
    
    int section_start = g_table_state.sections[section_index].start_step;
    int section_end = section_start + g_table_state.sections[section_index].num_steps;
    
    // Calculate total table size before deletion
    int total_steps = 0;
    for (int i = 0; i < g_table_state.sections_count; i++) {
        total_steps += g_table_state.sections[i].num_steps;
    }
    
    if (at_step < section_start || at_step >= section_end || g_table_state.sections[section_index].num_steps <= 1) {
        prnt_err("❌ [TABLE] Cannot delete step at %d (section: %d-%d, steps: %d)", 
                 at_step, section_start, section_end-1, g_table_state.sections[section_index].num_steps);
        return;
    }
    
    // Mutate under seqlock
    state_write_begin();

    // CRITICAL: Shift ALL rows from deletion point to end of table up by 1
    // This ensures subsequent sections' data moves up by 1 row
    for (int step = at_step; step < total_steps - 1; step++) {
        for (int col = 0; col < MAX_SEQUENCER_COLS; col++) {
            g_table_state.table[step][col] = g_table_state.table[step + 1][col];
        }
    }
    
    // Clear the last row in table (now empty after shift)
    for (int col = 0; col < MAX_SEQUENCER_COLS; col++) {
        table_set_cell_defaults(&g_table_state.table[total_steps - 1][col]);
    }
    
    // Decrease section length
    g_table_state.sections[section_index].num_steps--;
    // Recompute all section start_step values to eliminate gaps
    table_recompute_section_starts();

    state_write_end();
    table_mark_content_changed();
    
    prnt("➖ [TABLE] Deleted step at %d in section %d (section steps: %d, total steps: %d)", 
         at_step, section_index, g_table_state.sections[section_index].num_steps, total_steps - 1);

    // Recreate SunVox pattern with new size
    sunvox_wrapper_create_section_pattern(section_index, g_table_state.sections[section_index].num_steps);

    if (undo_record) {
        UndoRedoManager_record();
    }
}

int table_get_max_steps(void) {
    return MAX_SEQUENCER_STEPS;
}

int table_get_max_cols(void) {
    return MAX_SEQUENCER_COLS;
}

int table_get_sections_count(void) {
    return g_table_state.sections_count;
}

// Helper to calculate which section a step belongs to
int table_get_section_at_step(int step) {
    for (int i = 0; i < g_table_state.sections_count; i++) {
        int start = g_table_state.sections[i].start_step;
        int end = start + g_table_state.sections[i].num_steps;
        if (step >= start && step < end) {
            return i;
        }
    }
    return -1; // Not in any section
}

int table_get_section_start_step(int section_index) {
    if (section_index < 0 || section_index >= g_table_state.sections_count) {
        return 0;
    }
    return g_table_state.sections[section_index].start_step;
}

int table_get_section_step_count(int section_index) {
    if (section_index < 0 || section_index >= g_table_state.sections_count) {
        return DEFAULT_SECTION_STEPS; // Default section size
    }
    return g_table_state.sections[section_index].num_steps;
}

// Section management functions
void table_set_section_step_count(int section_index, int steps, int undo_record) {
    if (section_index < 0 || section_index >= g_table_state.sections_count) {
        prnt_err("❌ [TABLE] Invalid section index: %d", section_index);
        return;
    }
    
    if (steps > 0 && steps <= MAX_SEQUENCER_STEPS) {
        state_write_begin();
        g_table_state.sections[section_index].num_steps = steps;
        // Recompute all section start_step values to eliminate gaps
        table_recompute_section_starts();
        state_write_end();
        table_mark_content_changed();
        
        prnt("📏 [TABLE] Set section %d step count to %d", section_index, steps);
        
        // Recreate SunVox pattern with new size
        sunvox_wrapper_create_section_pattern(section_index, steps);
        
        if (undo_record) {
            UndoRedoManager_record();
        }
    } else {
        prnt_err("❌ [TABLE] Invalid steps count: %d", steps);
    }
}

// Append a new section; if copy_from_section >= 0, copy its cells and step count; otherwise use provided steps
void table_append_section(int steps, int copy_from_section, int undo_record) {
    if (g_table_state.sections_count >= MAX_SECTIONS) {
        prnt_err("❌ [TABLE] Cannot append section: max sections reached");
        return;
    }

    int new_index = g_table_state.sections_count;
    int new_steps = steps;
    if (copy_from_section >= 0 && copy_from_section < g_table_state.sections_count) {
        new_steps = g_table_state.sections[copy_from_section].num_steps;
    }
    if (new_steps <= 0 || new_steps > MAX_SEQUENCER_STEPS) {
        new_steps = DEFAULT_SECTION_STEPS; // fallback
    }

    // Calculate start step for new section at the end of current table
    int start = 0;
    for (int i = 0; i < g_table_state.sections_count; i++) {
        start += g_table_state.sections[i].num_steps;
    }

    // Initialize section metadata (start_step will be recomputed below)
    g_table_state.sections[new_index].start_step = start;
    g_table_state.sections[new_index].num_steps = new_steps;

    // Initialize layers for new section to default lengths
    for (int l = 0; l < MAX_LAYERS_PER_SECTION; l++) {
        g_table_state.layers[new_index][l].len = MAX_COLS_PER_LAYER;
        g_table_state.section_layer_reverb[new_index][l].send = 0;
        g_table_state.section_layer_reverb[new_index][l].room = 128;
        g_table_state.section_layer_reverb[new_index][l].damp = 128;
        g_table_state.section_layer_eq[new_index][l].low_db = 0;
        g_table_state.section_layer_eq[new_index][l].mid_db = 0;
        g_table_state.section_layer_eq[new_index][l].high_db = 0;
        g_table_state.section_layer_volume[new_index][l] = 255;
    }

    // Copy section-layer reverb from template section when requested.
    if (copy_from_section >= 0 && copy_from_section < g_table_state.sections_count) {
        for (int l = 0; l < MAX_LAYERS_PER_SECTION; l++) {
            g_table_state.section_layer_reverb[new_index][l] = g_table_state.section_layer_reverb[copy_from_section][l];
            g_table_state.section_layer_eq[new_index][l] = g_table_state.section_layer_eq[copy_from_section][l];
            g_table_state.section_layer_volume[new_index][l] = g_table_state.section_layer_volume[copy_from_section][l];
        }
    }

    // Copy cells if requested
    if (copy_from_section >= 0 && copy_from_section < g_table_state.sections_count) {
        int src_start = g_table_state.sections[copy_from_section].start_step;
        for (int step = 0; step < new_steps; step++) {
            for (int col = 0; col < MAX_SEQUENCER_COLS; col++) {
                g_table_state.table[start + step][col] = g_table_state.table[src_start + step][col];
            }
        }
    } else {
        // Clear new section cells
        for (int step = 0; step < new_steps; step++) {
            for (int col = 0; col < MAX_SEQUENCER_COLS; col++) {
                table_set_cell_defaults(&g_table_state.table[start + step][col]);
            }
        }
    }

    state_write_begin();

    g_table_state.sections_count++;
    // Recompute all section start_step values to eliminate gaps
    table_recompute_section_starts();

    state_write_end();
    table_mark_content_changed();

    prnt("🆕 [TABLE] Appended section %d (steps=%d, start=%d)", new_index, new_steps, start);
    
    // Check if playback is active before we modify anything
    const PlaybackState* pb_state = playback_get_state_ptr();
    int was_playing = pb_state ? pb_state->is_playing : 0;
    int bpm = pb_state ? pb_state->bpm : 120;
    
    // Stop playback first to prevent audio artifacts during section creation
    if (was_playing) {
        playback_stop();
    }
    
    // Create SunVox pattern for this section (won't restart playback since we stopped it)
    sunvox_wrapper_create_section_pattern(new_index, new_steps);
    
    // Switch to the new section (this will set up timeline and position)
    switch_to_section(new_index);
    
    // Manually restart playback if it was active before
    if (was_playing) {
        int section_start_step = table_get_section_start_step(new_index);
        playback_start(bpm, section_start_step);
    }

    if (undo_record) {
        UndoRedoManager_record();
    }
}

// Delete a section by index; shifts subsequent sections up and compacts start_step
void table_delete_section(int section_index, int undo_record) {
    if (section_index < 0 || section_index >= g_table_state.sections_count) {
        prnt_err("❌ [TABLE] Invalid section index: %d", section_index);
        return;
    }
    if (g_table_state.sections_count <= 1) {
        prnt_err("❌ [TABLE] Cannot delete the last remaining section");
        return;
    }

    int remove_start = g_table_state.sections[section_index].start_step;
    int remove_steps = g_table_state.sections[section_index].num_steps;
    int total_steps = 0;
    for (int i = 0; i < g_table_state.sections_count; i++) total_steps += g_table_state.sections[i].num_steps;

    state_write_begin();

    // Shift table cells up to cover removed section range
    for (int step = remove_start; step < total_steps - remove_steps; step++) {
        for (int col = 0; col < MAX_SEQUENCER_COLS; col++) {
            g_table_state.table[step][col] = g_table_state.table[step + remove_steps][col];
        }
    }
    // Clear trailing cells
    for (int step = total_steps - remove_steps; step < total_steps; step++) {
        for (int col = 0; col < MAX_SEQUENCER_COLS; col++) {
            table_set_cell_defaults(&g_table_state.table[step][col]);
        }
    }

    // Shift sections metadata down and recompute start_step chain
    for (int i = section_index; i < g_table_state.sections_count - 1; i++) {
        g_table_state.sections[i] = g_table_state.sections[i + 1];
        // Shift layers row along with section metadata
        for (int l = 0; l < MAX_LAYERS_PER_SECTION; l++) {
            g_table_state.layers[i][l] = g_table_state.layers[i + 1][l];
            g_table_state.section_layer_reverb[i][l] = g_table_state.section_layer_reverb[i + 1][l];
            g_table_state.section_layer_eq[i][l] = g_table_state.section_layer_eq[i + 1][l];
            g_table_state.section_layer_volume[i][l] = g_table_state.section_layer_volume[i + 1][l];
        }
    }
    g_table_state.sections_count--;
    // Recompute all section start_step values to eliminate gaps
    table_recompute_section_starts();
    // Reset trailing layers row to defaults
    for (int l = 0; l < MAX_LAYERS_PER_SECTION; l++) {
        g_table_state.layers[g_table_state.sections_count][l].len = MAX_COLS_PER_LAYER;
        g_table_state.section_layer_reverb[g_table_state.sections_count][l].send = 0;
        g_table_state.section_layer_reverb[g_table_state.sections_count][l].room = 128;
        g_table_state.section_layer_reverb[g_table_state.sections_count][l].damp = 128;
        g_table_state.section_layer_eq[g_table_state.sections_count][l].low_db = 0;
        g_table_state.section_layer_eq[g_table_state.sections_count][l].mid_db = 0;
        g_table_state.section_layer_eq[g_table_state.sections_count][l].high_db = 0;
        g_table_state.section_layer_volume[g_table_state.sections_count][l] = 255;
    }

    state_write_end();
    table_mark_content_changed();

    prnt("🗑️ [TABLE] Deleted section %d (steps=%d)", section_index, remove_steps);
    
    // Remove SunVox pattern (it was at the end before shift)
    sunvox_wrapper_remove_section_pattern(g_table_state.sections_count); // old last index
    
    // Recreate all section patterns since they shifted
    for (int i = 0; i < g_table_state.sections_count; i++) {
        sunvox_wrapper_create_section_pattern(i, g_table_state.sections[i].num_steps);
    }

    if (undo_record) {
        UndoRedoManager_record();
    }
}

// Reorder section: move section from from_index to to_index
// Uses copy-paste approach to physically move data blocks
void table_reorder_section(int from_index, int to_index, int undo_record) {
    if (from_index < 0 || from_index >= g_table_state.sections_count) {
        prnt_err("❌ [TABLE] Invalid from_index: %d", from_index);
        return;
    }
    if (to_index < 0 || to_index >= g_table_state.sections_count) {
        prnt_err("❌ [TABLE] Invalid to_index: %d", to_index);
        return;
    }
    if (from_index == to_index) {
        prnt("⚠️ [TABLE] Reorder no-op: from_index == to_index");
        return;
    }

    prnt("🔄 [TABLE] Reordering section %d → %d", from_index, to_index);

    // Save section metadata and layers for the moving section
    Section moving_section = g_table_state.sections[from_index];
    Layer moving_layers[MAX_LAYERS_PER_SECTION];
    SectionLayerReverb moving_layer_reverb[MAX_LAYERS_PER_SECTION];
    SectionLayerEq moving_layer_eq[MAX_LAYERS_PER_SECTION];
    uint8_t moving_layer_volume[MAX_LAYERS_PER_SECTION];
    for (int l = 0; l < MAX_LAYERS_PER_SECTION; l++) {
        moving_layers[l] = g_table_state.layers[from_index][l];
        moving_layer_reverb[l] = g_table_state.section_layer_reverb[from_index][l];
        moving_layer_eq[l] = g_table_state.section_layer_eq[from_index][l];
        moving_layer_volume[l] = g_table_state.section_layer_volume[from_index][l];
    }

    // Allocate temporary buffer for moving section's data
    int moving_steps = moving_section.num_steps;
    Cell* temp_buffer = (Cell*)malloc(moving_steps * MAX_SEQUENCER_COLS * sizeof(Cell));
    if (!temp_buffer) {
        prnt_err("❌ [TABLE] Failed to allocate temp buffer for reorder");
        return;
    }

    // Copy moving section's data to temp buffer
    int moving_start = moving_section.start_step;
    for (int step = 0; step < moving_steps; step++) {
        for (int col = 0; col < MAX_SEQUENCER_COLS; col++) {
            temp_buffer[step * MAX_SEQUENCER_COLS + col] = g_table_state.table[moving_start + step][col];
        }
    }

    state_write_begin();

    // Shift sections metadata and data
    if (from_index < to_index) {
        // Moving down: shift sections [from+1..to] up by one
        for (int i = from_index; i < to_index; i++) {
            g_table_state.sections[i] = g_table_state.sections[i + 1];
            for (int l = 0; l < MAX_LAYERS_PER_SECTION; l++) {
                g_table_state.layers[i][l] = g_table_state.layers[i + 1][l];
                g_table_state.section_layer_reverb[i][l] = g_table_state.section_layer_reverb[i + 1][l];
                g_table_state.section_layer_eq[i][l] = g_table_state.section_layer_eq[i + 1][l];
                g_table_state.section_layer_volume[i][l] = g_table_state.section_layer_volume[i + 1][l];
            }
        }
        // Place moving section at to_index
        g_table_state.sections[to_index] = moving_section;
        for (int l = 0; l < MAX_LAYERS_PER_SECTION; l++) {
            g_table_state.layers[to_index][l] = moving_layers[l];
            g_table_state.section_layer_reverb[to_index][l] = moving_layer_reverb[l];
            g_table_state.section_layer_eq[to_index][l] = moving_layer_eq[l];
            g_table_state.section_layer_volume[to_index][l] = moving_layer_volume[l];
        }
    } else {
        // Moving up: shift sections [to..from-1] down by one
        for (int i = from_index; i > to_index; i--) {
            g_table_state.sections[i] = g_table_state.sections[i - 1];
            for (int l = 0; l < MAX_LAYERS_PER_SECTION; l++) {
                g_table_state.layers[i][l] = g_table_state.layers[i - 1][l];
                g_table_state.section_layer_reverb[i][l] = g_table_state.section_layer_reverb[i - 1][l];
                g_table_state.section_layer_eq[i][l] = g_table_state.section_layer_eq[i - 1][l];
                g_table_state.section_layer_volume[i][l] = g_table_state.section_layer_volume[i - 1][l];
            }
        }
        // Place moving section at to_index
        g_table_state.sections[to_index] = moving_section;
        for (int l = 0; l < MAX_LAYERS_PER_SECTION; l++) {
            g_table_state.layers[to_index][l] = moving_layers[l];
            g_table_state.section_layer_reverb[to_index][l] = moving_layer_reverb[l];
            g_table_state.section_layer_eq[to_index][l] = moving_layer_eq[l];
            g_table_state.section_layer_volume[to_index][l] = moving_layer_volume[l];
        }
    }

    // Rebuild entire table data in new order
    int cursor = 0;
    Cell* rebuild_buffer = (Cell*)malloc(MAX_SEQUENCER_STEPS * MAX_SEQUENCER_COLS * sizeof(Cell));
    if (!rebuild_buffer) {
        free(temp_buffer);
        state_write_end();
        prnt_err("❌ [TABLE] Failed to allocate rebuild buffer");
        return;
    }

    for (int i = 0; i < g_table_state.sections_count; i++) {
        int section_steps = g_table_state.sections[i].num_steps;
        int old_start = g_table_state.sections[i].start_step; // Still points to old position
        
        // Copy from old position to rebuild buffer
        if (i == to_index) {
            // This is the moved section - copy from temp buffer
            for (int step = 0; step < section_steps; step++) {
                for (int col = 0; col < MAX_SEQUENCER_COLS; col++) {
                    rebuild_buffer[(cursor + step) * MAX_SEQUENCER_COLS + col] = 
                        temp_buffer[step * MAX_SEQUENCER_COLS + col];
                }
            }
        } else {
            // Regular section - copy from original location
            for (int step = 0; step < section_steps; step++) {
                for (int col = 0; col < MAX_SEQUENCER_COLS; col++) {
                    rebuild_buffer[(cursor + step) * MAX_SEQUENCER_COLS + col] = 
                        g_table_state.table[old_start + step][col];
                }
            }
        }
        
        cursor += section_steps;
    }

    // Recompute all section start_step values to eliminate gaps
    table_recompute_section_starts();

    // Copy rebuild buffer back to table
    for (int step = 0; step < cursor; step++) {
        for (int col = 0; col < MAX_SEQUENCER_COLS; col++) {
            g_table_state.table[step][col] = rebuild_buffer[step * MAX_SEQUENCER_COLS + col];
        }
    }

    state_write_end();
    table_mark_content_changed();

    free(temp_buffer);
    free(rebuild_buffer);

    prnt("✅ [TABLE] Reordered section %d → %d", from_index, to_index);

    // Call SunVox seamless reorder wrapper
    sunvox_wrapper_reorder_section(from_index, to_index);

    if (undo_record) {
        UndoRedoManager_record();
    }
}

// Set section metadata directly (start_step, num_steps)
void table_set_section(int index, int start_step, int num_steps, int undo_record) {
    if (index < 0 || index >= MAX_SECTIONS) {
        prnt_err("❌ [TABLE] Invalid section index: %d", index);
        return;
    }
    if (num_steps <= 0 || num_steps > MAX_SEQUENCER_STEPS) {
        prnt_err("❌ [TABLE] Invalid section steps: %d", num_steps);
        return;
    }
    if (start_step < 0 || start_step >= MAX_SEQUENCER_STEPS) {
        prnt_err("❌ [TABLE] Invalid section start: %d", start_step);
        return;
    }

    state_write_begin();
    g_table_state.sections[index].start_step = start_step;
    g_table_state.sections[index].num_steps = num_steps;
    // Note: Recompute may overwrite start_step, but that's intentional to ensure consistency
    table_recompute_section_starts();
    state_write_end();
    table_mark_content_changed();

    prnt("📐 [TABLE] Set section %d (start=%d, steps=%d)", index, start_step, num_steps);

    if (undo_record) {
        UndoRedoManager_record();
    }
}

// Set per-section layer length
void table_set_layer_len(int section_index, int layer_index, int len, int undo_record) {
    if (section_index < 0 || section_index >= MAX_SECTIONS) {
        prnt_err("❌ [TABLE] Invalid section index: %d", section_index);
        return;
    }
    if (layer_index < 0 || layer_index >= MAX_LAYERS_PER_SECTION) {
        prnt_err("❌ [TABLE] Invalid layer index: %d", layer_index);
        return;
    }
    if (len < 0 || len > MAX_SEQUENCER_COLS) {
        prnt_err("❌ [TABLE] Invalid layer len: %d", len);
        return;
    }

    state_write_begin();
    g_table_state.layers[section_index][layer_index].len = len;
    state_write_end();
    table_mark_content_changed();

    prnt("📏 [TABLE] Set layer len section=%d layer=%d len=%d", section_index, layer_index, len);

    if (undo_record) {
        UndoRedoManager_record();
    }
}

// Layer mute/solo
void table_set_layer_mute(int layer, int mute) {
    if (layer < 0 || layer >= MAX_LAYERS_PER_SECTION) return;
    g_layer_mute[layer] = mute ? 1 : 0;
}

void table_set_layer_solo(int layer, int solo) {
    if (layer < 0 || layer >= MAX_LAYERS_PER_SECTION) return;
    g_layer_solo[layer] = solo ? 1 : 0;
}

int table_get_layer_mute(int layer) {
    if (layer < 0 || layer >= MAX_LAYERS_PER_SECTION) return 0;
    return g_layer_mute[layer] ? 1 : 0;
}

int table_get_layer_solo(int layer) {
    if (layer < 0 || layer >= MAX_LAYERS_PER_SECTION) return 0;
    return g_layer_solo[layer] ? 1 : 0;
}

__attribute__((visibility("default"))) __attribute__((used))
void table_set_layer_col_mute(int layer, int col_in_layer, int mute) {
    if (layer < 0 || layer >= MAX_LAYERS_PER_SECTION) return;
    if (col_in_layer < 0 || col_in_layer >= MAX_COLS_PER_LAYER) return;
    g_layer_col_mute[layer][col_in_layer] = mute ? 1 : 0;
}

__attribute__((visibility("default"))) __attribute__((used))
int table_get_layer_col_mute(int layer, int col_in_layer) {
    if (layer < 0 || layer >= MAX_LAYERS_PER_SECTION) return 0;
    if (col_in_layer < 0 || col_in_layer >= MAX_COLS_PER_LAYER) return 0;
    return g_layer_col_mute[layer][col_in_layer] ? 1 : 0;
}

__attribute__((visibility("default"))) __attribute__((used))
void table_set_layer_col_solo(int layer, int col_in_layer, int solo) {
    if (layer < 0 || layer >= MAX_LAYERS_PER_SECTION) return;
    if (col_in_layer < 0 || col_in_layer >= MAX_COLS_PER_LAYER) return;
    g_layer_col_solo[layer][col_in_layer] = solo ? 1 : 0;
}

__attribute__((visibility("default"))) __attribute__((used))
int table_get_layer_col_solo(int layer, int col_in_layer) {
    if (layer < 0 || layer >= MAX_LAYERS_PER_SECTION) return 0;
    if (col_in_layer < 0 || col_in_layer >= MAX_COLS_PER_LAYER) return 0;
    return g_layer_col_solo[layer][col_in_layer] ? 1 : 0;
}

// Map column to layer index for a given section (uses layers[section] lengths)
int table_get_layer_for_col(int section, int col) {
    if (section < 0 || section >= g_table_state.sections_count) return -1;
    if (col < 0 || col >= MAX_SEQUENCER_COLS) return -1;

    int start = 0;
    for (int l = 0; l < MAX_LAYERS_PER_SECTION; l++) {
        int len = g_table_state.layers[section][l].len;
        if (col < start + len) return l;
        start += len;
    }
    return -1;
}

// Map absolute column to column index within its layer for a given section.
// Returns -1 if column is outside all layer ranges.
int table_get_col_in_layer(int section, int col) {
    if (section < 0 || section >= g_table_state.sections_count) return -1;
    if (col < 0 || col >= MAX_SEQUENCER_COLS) return -1;

    int start = 0;
    for (int l = 0; l < MAX_LAYERS_PER_SECTION; l++) {
        int len = g_table_state.layers[section][l].len;
        if (col < start + len) return col - start;
        start += len;
    }
    return -1;
}

void table_set_section_layer_reverb(int section, int layer, int send, int room, int damp, int undo_record) {
    if (section < 0 || section >= MAX_SECTIONS) return;
    if (layer < 0 || layer >= MAX_LAYERS_PER_SECTION) return;

    state_write_begin();
    g_table_state.section_layer_reverb[section][layer].send = clamp_u8(send);
    g_table_state.section_layer_reverb[section][layer].room = clamp_u8(room);
    g_table_state.section_layer_reverb[section][layer].damp = clamp_u8(damp);
    state_write_end();
    table_mark_content_changed();

    if (undo_record) {
        UndoRedoManager_record();
    }
}

int table_get_section_layer_reverb_send(int section, int layer) {
    if (section < 0 || section >= MAX_SECTIONS) return 0;
    if (layer < 0 || layer >= MAX_LAYERS_PER_SECTION) return 0;
    return g_table_state.section_layer_reverb[section][layer].send;
}

int table_get_section_layer_reverb_room(int section, int layer) {
    if (section < 0 || section >= MAX_SECTIONS) return 128;
    if (layer < 0 || layer >= MAX_LAYERS_PER_SECTION) return 128;
    return g_table_state.section_layer_reverb[section][layer].room;
}

int table_get_section_layer_reverb_damp(int section, int layer) {
    if (section < 0 || section >= MAX_SECTIONS) return 128;
    if (layer < 0 || layer >= MAX_LAYERS_PER_SECTION) return 128;
    return g_table_state.section_layer_reverb[section][layer].damp;
}

void table_set_section_layer_eq(int section, int layer, int low_db, int mid_db, int high_db, int undo_record) {
    if (section < 0 || section >= MAX_SECTIONS) return;
    if (layer < 0 || layer >= MAX_LAYERS_PER_SECTION) return;

    state_write_begin();
    g_table_state.section_layer_eq[section][layer].low_db = clamp_eq_db(low_db);
    g_table_state.section_layer_eq[section][layer].mid_db = clamp_eq_db(mid_db);
    g_table_state.section_layer_eq[section][layer].high_db = clamp_eq_db(high_db);
    state_write_end();
    table_mark_content_changed();

    if (undo_record) {
        UndoRedoManager_record();
    }
}

void table_set_section_layer_eq_band(int section, int layer, int band, int db, int undo_record) {
    if (section < 0 || section >= MAX_SECTIONS) return;
    if (layer < 0 || layer >= MAX_LAYERS_PER_SECTION) return;
    if (band < 0 || band > 2) return;

    state_write_begin();
    int8_t c = clamp_eq_db(db);
    if (band == 0) g_table_state.section_layer_eq[section][layer].low_db = c;
    else if (band == 1) g_table_state.section_layer_eq[section][layer].mid_db = c;
    else g_table_state.section_layer_eq[section][layer].high_db = c;
    state_write_end();
    table_mark_content_changed();

    if (undo_record) {
        UndoRedoManager_record();
    }
}

int table_get_section_layer_eq_band_db(int section, int layer, int band) {
    if (section < 0 || section >= MAX_SECTIONS) return 0;
    if (layer < 0 || layer >= MAX_LAYERS_PER_SECTION) return 0;
    if (band < 0 || band > 2) return 0;
    if (band == 0) return g_table_state.section_layer_eq[section][layer].low_db;
    if (band == 1) return g_table_state.section_layer_eq[section][layer].mid_db;
    return g_table_state.section_layer_eq[section][layer].high_db;
}

void table_set_section_layer_volume(int section, int layer, int level, int undo_record) {
    if (section < 0 || section >= MAX_SECTIONS) return;
    if (layer < 0 || layer >= MAX_LAYERS_PER_SECTION) return;

    state_write_begin();
    g_table_state.section_layer_volume[section][layer] = (uint8_t)clamp_u8(level);
    state_write_end();
    table_mark_content_changed();

    if (undo_record) {
        UndoRedoManager_record();
    }
}

int table_get_section_layer_volume(int section, int layer) {
    if (section < 0 || section >= MAX_SECTIONS) return 255;
    if (layer < 0 || layer >= MAX_LAYERS_PER_SECTION) return 255;
    return (int)g_table_state.section_layer_volume[section][layer];
}

// Return pointer to unified state for Flutter FFI access
const TableState* table_get_state_ptr(void) { return &g_table_state; }

// Exposes the dirty marker to Dart side for optional polling-based checks.
uint32_t table_get_content_epoch(void) { return g_table_state.content_epoch; }

// Expose live state for read
const TableState* table_state_get_ptr(void) { return &g_table_state; }

// Disable automatic SunVox sync (for bulk operations like import/undo/redo)
void table_disable_sunvox_sync(void) {
    g_disable_sunvox_sync = 1;
    prnt("🔇 [TABLE] Disabled automatic SunVox sync");
}

// Re-enable automatic SunVox sync
void table_enable_sunvox_sync(void) {
    g_disable_sunvox_sync = 0;
    prnt("🔊 [TABLE] Enabled automatic SunVox sync");
}

void table_begin_edit_transaction(void) {
    if (g_edit_txn_depth == 0) {
        table_txn_reset_touched_sections();
    }
    g_edit_txn_depth++;
}

void table_mark_step_touched(int step) {
    table_txn_mark_step_touched_internal(step);
}

void table_end_edit_transaction(int record_undo) {
    if (g_edit_txn_depth <= 0) return;
    g_edit_txn_depth--;
    if (g_edit_txn_depth > 0) return;

    // Flush one section-level sync per touched section.
    if (sunvox_wrapper_is_initialized() && !g_disable_sunvox_sync) {
        for (int section = 0; section < g_table_state.sections_count; section++) {
            if (!g_edit_txn_touched_sections[section]) continue;
            sunvox_wrapper_sync_section(section);
        }
    }

    if (record_undo) {
        UndoRedoManager_record();
    }
    table_txn_reset_touched_sections();
}

// Apply a native snapshot used by Undo/Redo
void table_apply_state(const TableState* snap) {
    state_write_begin();

    // Copy full state
    g_table_state.sections_count = snap->sections_count;
    if (g_table_state.sections_count < 0) g_table_state.sections_count = 0;
    if (g_table_state.sections_count > MAX_SECTIONS) g_table_state.sections_count = MAX_SECTIONS;
    // table
    for (int r = 0; r < MAX_SEQUENCER_STEPS; r++) {
        for (int c = 0; c < MAX_SEQUENCER_COLS; c++) {
            g_table_state.table[r][c] = snap->table[r][c];
        }
    }
    // sections
    for (int i = 0; i < MAX_SECTIONS; i++) {
        g_table_state.sections[i] = snap->sections[i];
    }
    // layers
    for (int s = 0; s < MAX_SECTIONS; s++) {
        for (int l = 0; l < MAX_LAYERS_PER_SECTION; l++) {
            g_table_state.layers[s][l] = snap->layers[s][l];
            g_table_state.section_layer_reverb[s][l] = snap->section_layer_reverb[s][l];
            g_table_state.section_layer_eq[s][l] = snap->section_layer_eq[s][l];
            g_table_state.section_layer_volume[s][l] = snap->section_layer_volume[s][l];
        }
    }

    state_write_end();
    table_mark_content_changed();
    prnt("📥 [TABLE] Applied TableState (sections=%d)", g_table_state.sections_count);
}
