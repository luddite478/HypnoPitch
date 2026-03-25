#include "undo_redo.h"
#include "sunvox_wrapper.h"
#include <string.h>
#include <stdlib.h>

static UndoRedoState g_undo_redo_state = {0};

static inline void state_write_begin() { g_undo_redo_state.version++; }
static inline void state_write_end()   { g_undo_redo_state.version++; }
static inline void state_update_prefix() {
    g_undo_redo_state.count = g_undo_redo_state.history_count;
    g_undo_redo_state.can_undo = (g_undo_redo_state.history_count > 0 && g_undo_redo_state.cursor > 0) ? 1 : 0;
    g_undo_redo_state.can_redo = (g_undo_redo_state.history_count > 0 && g_undo_redo_state.cursor >= 0 && g_undo_redo_state.cursor < g_undo_redo_state.history_count - 1) ? 1 : 0;
}

// Helpers for separate-state history snapshots
static void free_entry(SequencerSnapshot* e) {
    if (!e) return;
    if (e->table) { free(e->table); e->table = NULL; }
    if (e->playback) { free(e->playback); e->playback = NULL; }
    if (e->sample_bank) { free(e->sample_bank); e->sample_bank = NULL; }
}

static void capture_current_snapshot(SequencerSnapshot* out) {
    if (!out) return;
    out->table = (TableState*)malloc(sizeof(TableState));
    out->playback = (PlaybackState*)malloc(sizeof(PlaybackState));
    out->sample_bank = (SampleBankState*)malloc(sizeof(SampleBankState));
    if (out->table) {
        const TableState* t = table_state_get_ptr();
        if (t) memcpy(out->table, t, sizeof(TableState)); else memset(out->table, 0, sizeof(TableState));
    }
    if (out->playback) {
        const PlaybackState* p = playback_state_get_ptr();
        if (p) memcpy(out->playback, p, sizeof(PlaybackState)); else memset(out->playback, 0, sizeof(PlaybackState));
    }
    if (out->sample_bank) {
        const SampleBankState* sb = sample_bank_state_get_ptr();
        if (sb) memcpy(out->sample_bank, sb, sizeof(SampleBankState)); else memset(out->sample_bank, 0, sizeof(SampleBankState));
    }
}

static int snapshots_equal(const SequencerSnapshot* a, const SequencerSnapshot* b) {
    if (!a || !b) return 0;
    if (!a->table || !b->table) return 0;
    if (!a->playback || !b->playback) return 0;
    if (!a->sample_bank || !b->sample_bank) return 0;
    if (memcmp(a->table, b->table, sizeof(TableState)) != 0) return 0;
    if (memcmp(a->playback, b->playback, sizeof(PlaybackState)) != 0) return 0;
    if (memcmp(a->sample_bank, b->sample_bank, sizeof(SampleBankState)) != 0) return 0;
    return 1;
}

// Common append logic with redo-tail handling, capacity, dedupe and state update
static void append_snapshot(SequencerSnapshot* new_snapshot) {
    if (new_snapshot == NULL) return;
    // If we have undone some steps, drop the redo tail and free snapshots.
    if (g_undo_redo_state.cursor >= 0 && g_undo_redo_state.cursor < g_undo_redo_state.history_count - 1) {
        for (int i = g_undo_redo_state.cursor + 1; i < g_undo_redo_state.history_count; i++) {
            free_entry(&g_undo_redo_state.history[i]);
        }
        g_undo_redo_state.history_count = g_undo_redo_state.cursor + 1;
    }
    // Ensure capacity: if full, discard oldest by freeing and shifting left by one.
    if (g_undo_redo_state.history_count >= UNDO_REDO_MAX_HISTORY) {
        free_entry(&g_undo_redo_state.history[0]);
        memmove(&g_undo_redo_state.history[0], &g_undo_redo_state.history[1], sizeof(SequencerSnapshot) * (UNDO_REDO_MAX_HISTORY - 1));
        g_undo_redo_state.history_count = UNDO_REDO_MAX_HISTORY - 1;
        if (g_undo_redo_state.cursor > 0) g_undo_redo_state.cursor -= 1; else g_undo_redo_state.cursor = -1;
    }
    // Deduplicate identical consecutive entries
    if (g_undo_redo_state.history_count > 0 && snapshots_equal(new_snapshot, &g_undo_redo_state.history[g_undo_redo_state.history_count - 1])) {
        // Drop new snapshot since it's identical
        free_entry(new_snapshot);
        state_write_begin();
        state_update_prefix();
        state_write_end();
        return;
    }
    // Append by moving ownership of pointers into history
    g_undo_redo_state.history[g_undo_redo_state.history_count] = *new_snapshot;
    g_undo_redo_state.history_count += 1;
    g_undo_redo_state.cursor = g_undo_redo_state.history_count - 1;
    state_write_begin();
    state_update_prefix();
    state_write_end();
}

static void apply_snapshot_at_cursor(void) {
    if (g_undo_redo_state.cursor < 0 || g_undo_redo_state.cursor >= g_undo_redo_state.history_count) return;
    g_undo_redo_state.is_applying = 1;
    const SequencerSnapshot* e = &g_undo_redo_state.history[g_undo_redo_state.cursor];
    if (e->table) table_apply_state(e->table);
    if (e->playback) playback_apply_state(e->playback);
    sample_bank_set_apply_mode(1);
    if (e->sample_bank) sample_bank_apply_state(e->sample_bank);
    sample_bank_set_apply_mode(0);
    // Reconcile SunVox events from restored table/sample state so audible state
    // matches the just-applied snapshot deterministically.
    if (sunvox_wrapper_is_initialized()) {
        const int sections_count = table_get_sections_count();
        for (int section = 0; section < sections_count; section++) {
            sunvox_wrapper_sync_section(section);
        }
    }
    g_undo_redo_state.is_applying = 0;
}

void UndoRedoManager_init(void) {
    g_undo_redo_state.history_count = 0;
    g_undo_redo_state.cursor = -1;
    g_undo_redo_state.is_applying = 0;
    g_undo_redo_state.version = 0;
    // Zero pointers
    for (int i = 0; i < UNDO_REDO_MAX_HISTORY; i++) {
        g_undo_redo_state.history[i].table = NULL;
        g_undo_redo_state.history[i].playback = NULL;
        g_undo_redo_state.history[i].sample_bank = NULL;
    }
    state_write_begin();
    state_update_prefix();
    state_write_end();
    // no public seqlock; single state only
    
}

void UndoRedoManager_clear(void) {
    for (int i = 0; i < g_undo_redo_state.history_count; i++) {
        free_entry(&g_undo_redo_state.history[i]);
    }
    g_undo_redo_state.history_count = 0;
    g_undo_redo_state.cursor = -1;
    state_write_begin();
    state_update_prefix();
    state_write_end();
}

// Record state AFTER a mutation has occurred.
void UndoRedoManager_record(void) {
    if (g_undo_redo_state.is_applying) return;
    SequencerSnapshot entry;
    entry.table = NULL; entry.playback = NULL; entry.sample_bank = NULL;
    capture_current_snapshot(&entry);
    append_snapshot(&entry);
}

// Removed specialized record functions in favor of unified UndoRedoManager_record()

int UndoRedoManager_canUndo(void) {
    return (g_undo_redo_state.history_count > 0 && g_undo_redo_state.cursor > 0) ? 1 : 0;
}

int UndoRedoManager_canRedo(void) {
    return (g_undo_redo_state.history_count > 0 && g_undo_redo_state.cursor >= 0 && g_undo_redo_state.cursor < g_undo_redo_state.history_count - 1) ? 1 : 0;
}

int UndoRedoManager_undo(void) {
    if (!UndoRedoManager_canUndo()) return 0;
    g_undo_redo_state.cursor -= 1;
    apply_snapshot_at_cursor();
    state_write_begin();
    state_update_prefix();
    state_write_end();
    
    return 1;
}

int UndoRedoManager_redo(void) {
    if (!UndoRedoManager_canRedo()) return 0;
    g_undo_redo_state.cursor += 1;
    apply_snapshot_at_cursor();
    state_write_begin();
    state_update_prefix();
    state_write_end();
    
    return 1;
}

const UndoRedoState* UndoRedoManager_get_state_ptr(void) {
    return &g_undo_redo_state;
}

const UndoRedoState* undo_redo_state_get_ptr(void) {
    return &g_undo_redo_state;
}


