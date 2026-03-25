#ifndef TABLE_H
#define TABLE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Constants
#define MAX_SEQUENCER_STEPS 2048
#define MAX_SEQUENCER_COLS 20  // 5 layers × 4 cols/layer
#define MAX_SAMPLE_SLOTS 26
#define MAX_SECTIONS 64
#define DEFAULT_SECTION_STEPS 16
// Layers (per section)
#define MAX_LAYERS_PER_SECTION 5
#define MAX_COLS_PER_LAYER 4

// Pitch configuration
// Special default values indicating "inherit from sample bank"
#define DEFAULT_CELL_PITCH  -1.0f
#define DEFAULT_CELL_VOLUME -1.0f
// Supported pitch ratio range (C0..C10)
#define PITCH_MIN_RATIO 0.03125f
#define PITCH_MAX_RATIO 32.0f

// Cell audio settings
typedef struct {
    float volume;               // 0.0 to 1.0
    float pitch;                // PITCH_MIN_RATIO..PITCH_MAX_RATIO, or DEFAULT_CELL_PITCH to inherit sample bank
} CellSettings;

// Core cell data structure
typedef struct {
    int sample_slot;            // -1 = empty, 0-25 = sample index (A-Z)
    CellSettings settings;      // audio settings
    int is_processing;          // 1 while preprocessing is queued for resolved pitch for this cell
} Cell;

// Section structure - each section can have different number of steps
typedef struct {
    int start_step;             // Starting step in the table
    int num_steps;              // Number of steps in this section
} Section;

// Layer structure - per-section fixed number of layers with length (columns count)
typedef struct {
    int len;                    // Number of columns in this layer (default MAX_COLS_PER_LAYER)
} Layer;

// Single live table state (authoritative). The first fields are read by Flutter via FFI.
// Keep these header fields at the top to allow Dart to map them as a prefix view.
typedef struct {
    // Seqlock version (even=stable, odd=writer in progress)
    uint32_t version;
    // Lightweight dirty marker for Flutter.
    // Unlike `version`, this does NOT guard read consistency; it only indicates
    // "some table content changed since last observed epoch".
    // Flutter uses it to skip expensive visible-cell scans when unchanged.
    uint32_t content_epoch;

    // Scalars visible to Flutter
    int sections_count;             // number of sections

    // Pointer views to internal arrays (assigned in table_init)
    Cell* table_ptr;                // &table[0][0]
    Section* sections_ptr;          // &sections[0]
    Layer* layers_ptr;              // &layers[0][0]

    // Canonical storage (arrays are static, pointers above reference these)
    Cell table[MAX_SEQUENCER_STEPS][MAX_SEQUENCER_COLS];
    Section sections[MAX_SECTIONS];
    Layer layers[MAX_SECTIONS][MAX_LAYERS_PER_SECTION];
} TableState;

// Table management functions
__attribute__((visibility("default"))) __attribute__((used))
void table_init(void);

__attribute__((visibility("default"))) __attribute__((used))
Cell* table_get_cell(int step, int col);

__attribute__((visibility("default"))) __attribute__((used))
void table_set_cell(int step, int col, int sample_slot, float volume, float pitch, int undo_record);

// New: set only cell settings (volume/pitch)
__attribute__((visibility("default"))) __attribute__((used))
void table_set_cell_settings(int step, int col, float volume, float pitch, int undo_record);

// New: set only cell sample slot
__attribute__((visibility("default"))) __attribute__((used))
void table_set_cell_sample_slot(int step, int col, int sample_slot, int undo_record);

__attribute__((visibility("default"))) __attribute__((used))
void table_clear_cell(int step, int col, int undo_record);

// Bulk clear all cells at once (efficient for import/reset operations)
__attribute__((visibility("default"))) __attribute__((used))
void table_clear_all_cells(void);

__attribute__((visibility("default"))) __attribute__((used))
void table_insert_step(int section_index, int at_step, int undo_record);

__attribute__((visibility("default"))) __attribute__((used))
void table_delete_step(int section_index, int at_step, int undo_record);

// Single setters to be used for batch updates from Flutter side
__attribute__((visibility("default"))) __attribute__((used))
void table_set_section(int index, int start_step, int num_steps, int undo_record);

__attribute__((visibility("default"))) __attribute__((used))
void table_set_layer_len(int section_index, int layer_index, int len, int undo_record);

// Layer mute/solo (per-layer, applies to all sections)
__attribute__((visibility("default"))) __attribute__((used))
void table_set_layer_mute(int layer, int mute);

__attribute__((visibility("default"))) __attribute__((used))
void table_set_layer_solo(int layer, int solo);

__attribute__((visibility("default"))) __attribute__((used))
int table_get_layer_mute(int layer);

__attribute__((visibility("default"))) __attribute__((used))
int table_get_layer_solo(int layer);

__attribute__((visibility("default"))) __attribute__((used))
int table_get_layer_for_col(int section, int col);

// Per-column mute/solo:
// - mute is per (layer, col_in_layer)
// - solo is per (layer, col_in_layer)
__attribute__((visibility("default"))) __attribute__((used))
void table_set_layer_col_mute(int layer, int col_in_layer, int mute);

__attribute__((visibility("default"))) __attribute__((used))
int table_get_layer_col_mute(int layer, int col_in_layer);

__attribute__((visibility("default"))) __attribute__((used))
void table_set_layer_col_solo(int layer, int col_in_layer, int solo);

__attribute__((visibility("default"))) __attribute__((used))
int table_get_layer_col_solo(int layer, int col_in_layer);

__attribute__((visibility("default"))) __attribute__((used))
int table_get_col_in_layer(int section, int col);


// Getters for table dimensions
__attribute__((visibility("default"))) __attribute__((used))
int table_get_max_steps(void);

__attribute__((visibility("default"))) __attribute__((used))
int table_get_max_cols(void);

__attribute__((visibility("default"))) __attribute__((used))
int table_get_sections_count(void);

// Section management
__attribute__((visibility("default"))) __attribute__((used))
int table_get_section_start_step(int section_index);

__attribute__((visibility("default"))) __attribute__((used))
int table_get_section_step_count(int section_index);

__attribute__((visibility("default"))) __attribute__((used))
int table_get_section_at_step(int step);

__attribute__((visibility("default"))) __attribute__((used))
void table_set_section_step_count(int section_index, int steps, int undo_record);


// Section append/delete
__attribute__((visibility("default"))) __attribute__((used))
void table_append_section(int steps, int copy_from_section, int undo_record);

__attribute__((visibility("default"))) __attribute__((used))
void table_delete_section(int section_index, int undo_record);

// Section reordering (move section from one position to another)
__attribute__((visibility("default"))) __attribute__((used))
void table_reorder_section(int from_index, int to_index, int undo_record);

// Return a stable pointer to the native TableState (prefix-mapped by Dart)
__attribute__((visibility("default"))) __attribute__((used))
const TableState* table_get_state_ptr(void);

// Returns current content epoch (dirty marker).
// Intended for change detection, not seqlock-style consistency checks.
__attribute__((visibility("default"))) __attribute__((used))
uint32_t table_get_content_epoch(void);

// Accessor for full live state (read-only; do not mutate from Dart)
__attribute__((visibility("default"))) __attribute__((used))
const TableState* table_state_get_ptr(void);

// Apply a full table state (used by Undo/Redo and imports)
__attribute__((visibility("default"))) __attribute__((used))
void table_apply_state(const TableState* state);

// Disable/enable automatic SunVox sync (for bulk operations like import)
__attribute__((visibility("default"))) __attribute__((used))
void table_disable_sunvox_sync(void);

__attribute__((visibility("default"))) __attribute__((used))
void table_enable_sunvox_sync(void);


#ifdef __cplusplus
}
#endif

#endif // TABLE_H