#ifndef PREVIEW_H
#define PREVIEW_H

#ifdef __cplusplus
extern "C" {
#endif

// Initialize/cleanup preview subsystem
__attribute__((visibility("default"))) __attribute__((used))
int preview_init(void);

__attribute__((visibility("default"))) __attribute__((used))
void preview_cleanup(void);

// Preview APIs (fire-and-forget, mixed into global node graph)
__attribute__((visibility("default"))) __attribute__((used))
int preview_sample_path(const char* file_path, float pitch, float volume);

__attribute__((visibility("default"))) __attribute__((used))
int preview_slot(int slot, float pitch, float volume);

__attribute__((visibility("default"))) __attribute__((used))
int preview_cell(int step, int column, float pitch, float volume, float pan);

__attribute__((visibility("default"))) __attribute__((used))
void preview_stop_sample(void);

__attribute__((visibility("default"))) __attribute__((used))
void preview_stop_cell(void);

#ifdef __cplusplus
}
#endif

#endif // PREVIEW_H


