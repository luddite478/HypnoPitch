#include "preview.h"
#include "playback.h"
#include "table.h"
#include "sample_bank.h"
// Route preview through SunVox engine (sv_send_event) for accurate module playback
#include "sunvox_wrapper.h"

#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdio.h>

#ifdef __APPLE__
#include "log.h"
#undef LOG_TAG
#define LOG_TAG "PREVIEW"
#else
#include "log.h"
#undef LOG_TAG
#define LOG_TAG "PREVIEW"
#endif

// Legacy miniaudio preview removed; using SunVox path instead.

int preview_init(void) { return 0; }

void preview_cleanup(void) { }

// File-path preview remains unsupported via SunVox; keep stub for API completeness.

int preview_sample_path(const char* file_path, float pitch, float volume) {
    (void)file_path;
    (void)pitch;
    // For file-path previews, just stop if volume=0; otherwise no-op success.
    if (volume <= 0.0f) sunvox_preview_stop();
    return 0;
}

int preview_slot(int slot, float pitch, float volume) {
    return sunvox_preview_slot(slot, pitch, volume);
}

int preview_cell(int step, int column, float pitch, float volume, float pan) {
    return sunvox_preview_cell(step, column, pitch, volume, pan);
}

void preview_stop_sample(void) { sunvox_preview_stop(); }

void preview_stop_cell(void) { sunvox_preview_stop(); }


