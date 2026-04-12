# Pattern export/import and sample identity

This document is the merged reference for:

- **Sample identity** (built-in vs custom, resolution, recovery)
- **Project snapshots** (JSON `schema_version` and what they carry)
- **Portable pattern archives** (`.hypnopattern` ZIP bundles for sharing projects across devices)

Related code lives under `app/lib/services/snapshot/`, `app/lib/state/library_samples_state.dart`, and `app/lib/services/sample_reference_resolver.dart`.

---

## Overview

### Scanner-first update contract

For built-in samples, this project now follows a **scanner-first** contract:

- You can add, rename, move, or delete files under `app/samples/` without manually editing `samples_manifest.json`.
- The scanner (`app/sample_scanner.py`) does the heavy lifting: hash identity, alias carry-forward, compatibility checks, and display metadata generation.
- The iOS run script (`app/run-ios.sh`) runs the scanner automatically before build/deploy so manifest updates stay in sync with filesystem changes.

What this means in practice:

1. Drop or reorganize files in `app/samples/`.
2. Run `./run-ios.sh ...` (or run `sample_scanner.py` directly).
3. Build/import old patterns — resolver uses canonical IDs + aliases to keep compatibility where bytes match.

No hand-maintained manifest editing should be needed for day-to-day sample library changes.

---

### Two ways state leaves the app

1. **JSON snapshot** (`exportToJson` / `importFromJson`)  
   Used for **working-state drafts**, checkpoints, and any flow that stores a snapshot map in app cache. It serializes **metadata** for the sample bank (`sample_id`, optional `file_path` hints, colors, settings). **Custom audio files are not embedded**; portability depends on identity resolution and the local library index.

2. **Portable archive** (`exportToArchiveBytes` / `importFromArchiveBytes`)  
   Used for **manual Export/Import Project** from the sequencer drawer. The artifact is a **ZIP** with extension **`.hypnopattern`** containing `project.json` plus **embedded bytes** for non–built-in samples. This is the format intended for **cross-device** exchange when custom samples are involved.

Built-in samples are **never** embedded; they resolve via `samples_manifest.json` and bundle assets.

---

## Portable archive format (`.hypnopattern`)

The container is a normal ZIP file (implemented with the Dart `archive` package).

| Entry | Role |
|-------|------|
| `project.json` | Full snapshot JSON (same shape as `exportToJson` output: `schema_version`, `source.table`, `source.playback`, `source.sample_bank`, etc.). After export packaging, loaded custom slots in `sample_bank` use canonical `custom:<sha256>` IDs and `file_path` cleared where embedded. |
| `manifest.json` | Archive metadata: `archive_format_version`, `snapshot_schema_version`, `created_at`, optional `app_version`, and `embedded_samples[]`. |
| `samples/<sha256>.<ext>` | One file per **deduplicated** embedded custom/local sample (extension from portable file name). |

`archive_format_version` is **independent** of snapshot `schema_version`. Current archive format version is **1** (`SnapshotArchiveManifest.currentFormatVersion`).

Each `embedded_samples[]` entry includes at least: `sample_id`, `archive_path`, `file_name`, `sha256`, optional `original_path`, optional `display_name`.

### Import order for archives

1. Parse ZIP; require `manifest.json` and `project.json`; reject unsafe paths (traversal, duplicates).
2. For each embedded sample: verify **SHA-256** of bytes matches manifest; register into the local custom library via `LibrarySamplesState.registerArchivedCustomSample` (folder name derived from project metadata when possible).
3. Run the normal **JSON snapshot importer** on `project.json` (`SnapshotImporter.importFromJson`).

`SnapshotService.importFromArchiveBytes` returns how many embedded samples were restored; the UI can show that alongside `lastImportReport` for any remaining missing slots.

### Export packaging

`SnapshotService.exportToArchiveBytes`:

1. Calls `exportToJson` (validates table vs sample bank consistency, including referenced slots loaded).
2. For each **loaded** bank slot that resolves to something other than **built-in**, reads file bytes, computes `custom:<sha256>`, dedupes by hash, and rewrites that slot’s `sample_id` / `file_path` in the in-memory snapshot map before encoding `project.json`.
3. Builds the ZIP with `SnapshotArchiveService.buildArchiveBytes`.

---

## JSON snapshots and `schema_version`

- **`schema_version: 1`**: legacy; importer still accepts it where validation allows.
- **`schema_version: 2`**: older structured snapshot format, including blocks such as:
  - `source.table.mute_solo` (and legacy parallel keys)
  - `source.table.layer_fx`
  - `source.playback.master_fx` (and legacy master fields)
- **`schema_version: 3`**: current exporter default (`SnapshotExporter.schemaVersion`).

The importer validates and accepts v1/v2/v3 and prefers the newer nested blocks when present.

**Working-state cache** (`WorkingStateCacheService`) wraps snapshots in an envelope (`version`, `pattern_id`, `saved_at`, `snapshot`); that envelope version is **not** the same field as snapshot `schema_version`.

---

## Sample identity model

### Built-in samples

- Canonical ID: `builtin.*`
- Source: `app/samples_manifest.json` (see `app/sample_scanner.py`).
- Manifest entry fields include:
  - `path` (original asset-relative path)
  - `asset_key` (scanner-generated safe load key; preferred on iOS)
  - `sha256`
  - `legacy_hash_12`
  - `aliases[]`
  - optional `legacy_ids[]`
  - UI metadata (`display_name`, `display_path`, `source_file_name`)
- Resolution uses aliases: canonical id, `legacy_hash_12`, `aliases[]`, optional `legacy_ids[]`.
- Once a built-in sample ships, its canonical id should stay stable even if the file is renamed or moved inside `app/samples/`.
- ID slug normalization uses deterministic replacements (including `# -> ___sharp___` in IDs) while UI labels stay human-friendly (`#` shown where relevant).

### Maintaining built-in samples safely

Treat `samples_manifest.json` as the compatibility contract, not the folder structure.

- **Additions** are safe: new files get new canonical `builtin.*` ids.
- **Renames / moves** are safe only when the scanner merges against the previous manifest and preserves the shipped canonical id while updating `path`.
- **Content changes** should not silently reuse a shipped built-in id; keep the old audio or mint a new built-in sample.
- **Deletions** require an explicit compatibility decision, because old projects and imports may still reference the removed canonical id.
- **File names**: avoid `#` in built-in asset paths. On iOS, `rootBundle.load` can fail for keys containing `#` (URI fragment), even when `AssetManifest` lists them. Prefer spelling like `Csharp6` or `fsharp3` instead of `C#6` / `f#3`.
- **Spaces**: prefer `underscores` over spaces in filenames when you can; iOS builds have occasionally failed to load assets whose manifest keys contain spaces (the app also tries percent-encoded fallbacks). Underscores are the safest portable choice.

Operationally:

1. Run `app/sample_scanner.py` against the existing `samples_manifest.json` so it can merge by hash and carry forward aliases.
2. Let the manifest keep old ids reachable through `legacy_ids[]` / `aliases[]`.
3. Keep `app/pubspec.yaml` asset paths aligned with any new or moved folders under `app/samples/`.
4. Before shipping, verify an older project / import fixture still resolves built-in ids through the regenerated manifest.
5. Prefer running through `app/run-ios.sh`, which now scans samples automatically before iOS build steps.

The scanner intentionally keeps disk names untouched (manifest-only normalization), so you can add/move/delete files in `app/samples/` without hand-editing manifest JSON.

### Custom samples

- Canonical ID: `custom:<sha256>` (hash of **file content**).
- Path in the index is **hint/metadata**, not identity.
- Persisted under app documents in `library_samples/custom_index.json` (schema v2: `folders` → list of entries with `id`, `file_name`, `path`, `imported_at`).
- Custom user imports stay on the existing `LibrarySamplesState` pipeline; only UI label formatting is aligned with built-ins.

---

## Resolution pipeline

Primary resolver: `app/lib/services/sample_reference_resolver.dart`.

Order of resolution:

1. If `sample_id` present: built-in via manifest, or custom via `LibrarySamplesState.resolveCustomSampleIdPath` / index.
2. Else use `file_path` hint and `LocalAudioPath` / basename fallbacks.
3. Return structured failure reasons for UI and `SnapshotImportReport`.

`SampleBankState.loadSampleReference` uses this resolver before loading into native slots.

For built-ins, `SampleAssetResolver` prefers manifest `asset_key` (when present) and falls back through raw/encoded key variants to improve iOS compatibility with special characters.

UI naming is decoupled from engine-safe IDs/keys:

- Runtime/sample-bank identity uses canonical IDs (`builtin.*`, `custom:<sha256>`).
- Browser/library labels use scanner/custom metadata and friendly formatting (`___sharp___` -> `#`, underscore cleanup, note-name formatting).

---

## Snapshot import and missing-sample recovery

Implementation: `app/lib/services/snapshot/import.dart`.

- Per-slot load failures are recorded in **`SnapshotImportReport`** (`missingSamples`, counts). Exposed as `SnapshotService.lastImportReport`.
- After import, the sequencer can show a **Missing Samples** dialog (`sequencer_screen_v2.dart`): locate file, replace from library, or skip.

Additional reporting: if the table references a slot that never loaded, issues are augmented so silent “empty bank” states are visible.

### UI overflow (Missing Samples dialog)

Follow `app/docs/dart_ui_guide/flutter_overflow_prevention_guide.md`: responsive actions, scroll, ellipsis on long names.

---

## Sequencer drawer: Export / Import Project

- **Export**: writes **`.hypnopattern`** bytes via `FilePicker.platform.saveFile` with `bytes:` (required on Android/iOS).
- **Import**: reads picked file bytes; if `validateArchiveBytes` succeeds, runs **archive import**; otherwise attempts **legacy JSON** snapshot validation and `importFromJson`.

Extensions allowed in the picker include `hypnopattern`, `json`, and `zip` (ZIP is treated as archive if it parses as our format).

---

## Backward compatibility

- Old **built-in** identifiers and manifest aliases.
- Old **custom** IDs: `custom:<folder>/<filename>` (resolved with legacy paths where possible).
- Old **custom index** (folder → list of paths) normalized on load.
- **Plain JSON** project files: still importable from the drawer when bytes are not a valid portable archive.
- Snapshots that only have `file_path` hints: resolver + missing-sample flow.
- Built-in file renames remain compatible only if the manifest preserves the shipped canonical id and its aliases.
- User-imported (custom) samples remain on `custom:<sha256>` identity; scanner automation is for built-ins only.

---

## Integrity and safety (archives)

- Manifest entries must not duplicate `sample_id`.
- Built-in manifest aliases / `legacy_ids[]` must not collide across different samples.
- ZIP member paths normalized; reject traversal (`..`) and absolute paths.
- Embedded bytes must match manifest `sha256` before registration.
- `registerArchivedCustomSample` rejects hash mismatch vs `custom:<sha256>` id when applicable.

---

## Risks and limits

- **Large projects**: full archive is built in memory; very large custom audio files may stress mobile RAM.
- **JSON-only** shares without archives still require manual recovery or existing library files on the target device.
- **Export** retries table/native sync and runs `SnapshotTableValidator`; it **throws** if the grid still references sample slots that are not loaded (see `SnapshotExporter.exportToJson`).
- **Hard guarantee boundary**: compatibility is strongest when file bytes are unchanged; replacing content with different audio under an old logical sample requires explicit compatibility intent.

---

## Key files

| Area | Path |
|------|------|
| Archive format / ZIP | `app/lib/services/snapshot/archive_service.dart` |
| Orchestration | `app/lib/services/snapshot/snapshot_service.dart` |
| JSON export | `app/lib/services/snapshot/export.dart` |
| JSON import | `app/lib/services/snapshot/import.dart` |
| Table validation | `app/lib/services/snapshot/snapshot_table_validator.dart` |
| Resolver | `app/lib/services/sample_reference_resolver.dart` |
| Built-in assets | `app/lib/services/sample_asset_resolver.dart` |
| Custom index + archive registration | `app/lib/state/library_samples_state.dart` |
| Bank / FFI | `app/lib/state/sequencer/sample_bank.dart` |
| Drawer UX | `app/lib/screens/sequencer_screen_v2.dart` |
| Manifest generation | `app/sample_scanner.py`, `app/samples_manifest.json` |
| Dependency | `archive` (see `app/pubspec.yaml`) |

---

## Historical note

This document **supersedes** the standalone `sample_identity_and_missing_recovery.md`, which now points here for the full narrative.
