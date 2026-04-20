import 'dart:convert';
import 'package:flutter/material.dart'; // For Color class
import '../sample_reference_resolver.dart';
import '../../state/sequencer/table.dart';
import '../../state/sequencer/playback.dart';
import '../../state/sequencer/sample_bank.dart';
import '../../ffi/undo_redo_bindings.dart';
import 'debug_snapshot.dart';

enum MissingSampleReason {
  missingSampleId,
  unknownSampleId,
  missingAssetPath,
  fileNotFound,
  loadFailed,
}

class MissingSampleIssue {
  final int slot;
  final String? sampleId;
  final String? filePath;
  final String? displayName;
  final MissingSampleReason reason;
  final String? details;

  const MissingSampleIssue({
    required this.slot,
    required this.reason,
    this.sampleId,
    this.filePath,
    this.displayName,
    this.details,
  });
}

class SnapshotImportReport {
  final List<MissingSampleIssue> missingSamples;
  final int loadedSampleCount;
  final int failedSampleCount;

  const SnapshotImportReport({
    required this.missingSamples,
    required this.loadedSampleCount,
    required this.failedSampleCount,
  });

  const SnapshotImportReport.empty()
      : missingSamples = const [],
        loadedSampleCount = 0,
        failedSampleCount = 0;
}

/// Snapshot import service for sequencer state
class SnapshotImporter {
  final TableState _tableState;
  final PlaybackState _playbackState;
  final SampleBankState _sampleBankState;
  SnapshotImportReport _lastImportReport = const SnapshotImportReport.empty();

  SnapshotImporter({
    required TableState tableState,
    required PlaybackState playbackState,
    required SampleBankState sampleBankState,
  })  : _tableState = tableState,
        _playbackState = playbackState,
        _sampleBankState = sampleBankState;

  SnapshotImportReport get lastImportReport => _lastImportReport;

  /// Import sequencer state from JSON string
  Future<bool> importFromJson(String jsonString,
      {Function(String, double)? onProgress}) async {
    try {
      debugPrint('📥 [SNAPSHOT_IMPORT] === STARTING IMPORT FROM JSON ===');
      _lastImportReport = const SnapshotImportReport.empty();

      final dynamic jsonData = json.decode(jsonString);
      if (jsonData is! Map<String, dynamic>) {
        debugPrint('❌ [SNAPSHOT_IMPORT] Invalid JSON structure');
        return false;
      }

      final snapshot = jsonData;
      final source = snapshot['source'] as Map<String, dynamic>;

      // CRITICAL STEP 1: Stop playback completely
      onProgress?.call('Stopping playback...', 0.02);
      debugPrint('🛑 [SNAPSHOT_IMPORT] STEP 1: Stopping playback');
      _playbackState.stop();

      // CRITICAL STEP 2: Reset ALL SunVox patterns (this removes all patterns and clears mappings)
      onProgress?.call('Resetting audio engine...', 0.05);
      debugPrint('🔄 [SNAPSHOT_IMPORT] STEP 2: Resetting ALL SunVox patterns');
      _tableState.resetAllSunVoxPatterns();

      // CRITICAL STEP 3: Clear sample bank
      onProgress?.call('Clearing samples...', 0.08);
      debugPrint('🧹 [SNAPSHOT_IMPORT] STEP 3: Clearing sample bank');
      for (int i = 0; i < SampleBankState.maxSampleSlots; i++) {
        _sampleBankState.unloadSample(i);
      }

      // CRITICAL STEP 4: Clear all table cells (WITHOUT syncing to SunVox since patterns are gone)
      onProgress?.call('Clearing table...', 0.1);
      debugPrint('🧹 [SNAPSHOT_IMPORT] STEP 4: Clearing all table cells');
      _clearAllTableCells();

      // CRITICAL STEP 5: Reset sections to section 0 only
      onProgress?.call('Resetting sections...', 0.15);
      debugPrint('🔄 [SNAPSHOT_IMPORT] STEP 5: Resetting to single section');
      final currentSections = _tableState.sectionsCount;
      for (int i = currentSections - 1; i > 0; i--) {
        _tableState.deleteSection(i, undoRecord: false);
      }

      // Now import fresh data

      // STEP 6: Import sample bank
      onProgress?.call('Loading samples...', 0.2);
      debugPrint('📦 [SNAPSHOT_IMPORT] STEP 6: Importing sample bank');
      if (source.containsKey('sample_bank')) {
        final success = await _importSampleBankState(
            source['sample_bank'] as Map<String, dynamic>);
        if (!success) {
          debugPrint('❌ [SNAPSHOT_IMPORT] Failed to import sample bank state');
          return false;
        }
      }

      // STEP 7: Import table structure and data
      // CRITICAL: Disable automatic SunVox sync during import to avoid syncing to non-existent patterns
      onProgress?.call('Loading table structure...', 0.3);
      debugPrint('📊 [SNAPSHOT_IMPORT] STEP 7: Importing table structure');
      debugPrint(
          '🔇 [SNAPSHOT_IMPORT] Disabling automatic SunVox sync during import');
      _tableState.disableSunvoxSync();

      int importedSectionsCount = 1;

      try {
        if (source.containsKey('table')) {
          final tableData = source['table'] as Map<String, dynamic>;
          importedSectionsCount = tableData['sections_count'] as int;

          final success = _importTableState(tableData);
          if (!success) {
            debugPrint('❌ [SNAPSHOT_IMPORT] Failed to import table state');
            return false;
          }
        }

        // STEP 8: Create SunVox patterns and sync all section data
        // This is THE critical step where we rebuild the entire SunVox pattern structure
        // IMPORTANT: Use the sections count from JSON, not from tableState (which may have stale cached value)
        onProgress?.call('Creating audio patterns...', 0.6);
        debugPrint(
            '🎵 [SNAPSHOT_IMPORT] STEP 8: Creating SunVox patterns and syncing data');

        // Converge cached and native counts before section-indexed sync.
        debugPrint(
            '🔄 [SNAPSHOT_IMPORT] Syncing table state to expected sections=$importedSectionsCount');
        final sectionsSynced = _tableState.syncTableStateUntilSectionsCount(
          importedSectionsCount,
          maxAttempts: 24,
        );
        debugPrint(
            '${sectionsSynced ? '✅' : '⚠️'} [SNAPSHOT_IMPORT] Section sync status: native=${_tableState.getNativeSectionsCount()} cached=${_tableState.sectionsCount} expected=$importedSectionsCount');

        _createAllSunVoxPatterns(importedSectionsCount);
      } finally {
        // ALWAYS re-enable automatic SunVox sync, even if import fails
        debugPrint('🔊 [SNAPSHOT_IMPORT] Re-enabling automatic SunVox sync');
        _tableState.enableSunvoxSync();
      }

      // STEP 9: Import playback settings
      onProgress?.call('Loading playback settings...', 0.8);
      debugPrint('⚙️ [SNAPSHOT_IMPORT] STEP 9: Importing playback settings');
      if (source.containsKey('playback')) {
        final success =
            _importPlaybackState(source['playback'] as Map<String, dynamic>);
        if (!success) {
          debugPrint('❌ [SNAPSHOT_IMPORT] Failed to import playback state');
          return false;
        }
      }

      // STEP 9b: Import per-section/per-layer FX state (v2 schema).
      if (source.containsKey('table')) {
        final tableData = source['table'] as Map<String, dynamic>;
        final success = _importLayerFxState(tableData);
        if (!success) {
          debugPrint('❌ [SNAPSHOT_IMPORT] Failed to import layer FX state');
          return false;
        }
      }

      _augmentImportReportWithReferencedSlotGaps(source);

      // STEP 10: Sync UI state with imported playback state
      onProgress?.call('Finalizing...', 0.9);
      debugPrint('✨ [SNAPSHOT_IMPORT] STEP 10: Syncing UI state');
      // Note: Don't call switchToSection here - it was already called in _importPlaybackState
      // and would override the timeline setup (creating a loop-mode timeline for section 0 only)
      // Sync UI selected section to match playback current section
      _tableState.setUiSelectedSection(_playbackState.currentSection);
      _tableState.setUiSelectedLayer(0);

      onProgress?.call('Clearing undo history...', 0.95);
      debugPrint('🗑️ [SNAPSHOT_IMPORT] STEP 11: Clearing undo/redo history');
      UndoRedoFfi.clear();
      debugPrint('✅ [SNAPSHOT_IMPORT] Undo/redo history cleared (fresh start)');

      onProgress?.call('Import complete!', 1.0);
      debugPrint('✅ [SNAPSHOT_IMPORT] === IMPORT COMPLETED SUCCESSFULLY ===');

      // Debug: Print final state
      debugPrint('📋 [SNAPSHOT_IMPORT] === FINAL STATE AFTER IMPORT ===');
      SnapshotDebugger.printTableState(_tableState);
      SnapshotDebugger.printSampleBankState(_sampleBankState);
      SnapshotDebugger.printPlaybackState(_playbackState);

      return true;
    } catch (e, stackTrace) {
      debugPrint('❌ [SNAPSHOT_IMPORT] Import failed: $e');
      debugPrint('📋 [SNAPSHOT_IMPORT] Stack trace: $stackTrace');
      return false;
    }
  }

  /// Clear all table cells WITHOUT syncing to SunVox (patterns don't exist yet)
  /// Uses efficient bulk clear operation instead of clearing cells one by one
  void _clearAllTableCells() {
    debugPrint(
        '🧹 [SNAPSHOT_IMPORT] Clearing all table cells (bulk operation)');
    _tableState.clearAllCells();
    debugPrint('✅ [SNAPSHOT_IMPORT] Cleared all table cells');
  }

  /// Create SunVox patterns for all sections and sync data
  /// This is called AFTER table structure and cells are imported
  /// sectionsCount: The number of sections from the imported data (not from tableState which may be stale)
  void _createAllSunVoxPatterns(int sectionsCount) {
    debugPrint(
        '🎵 [SNAPSHOT_IMPORT] Creating patterns for $sectionsCount sections');

    // For each section, we need to ensure a SunVox pattern exists and is synced
    // The appendSection() and setSectionStepCount() calls already created/resized patterns
    // Now we need to sync the cell data to those patterns
    for (int i = 0; i < sectionsCount; i++) {
      // Sync this section to SunVox pattern
      // The native code will log detailed info about what gets synced
      debugPrint('  🔄 Section $i: syncing to SunVox pattern');
      debugPrint('     Syncing to SunVox pattern...');
      _tableState.syncSectionToSunVox(i);
    }

    debugPrint('✅ [SNAPSHOT_IMPORT] All patterns created and synced');

    // CRITICAL FIX: Recalculate timeline positions seamlessly
    // During import, setSectionStepCount() was called incrementally, triggering timeline
    // updates when only SOME patterns existed. This caused incorrect X positions.
    // Now that ALL patterns exist, we recalculate the timeline one final time.
    // We use the seamless update (not full rebuild) to preserve the seamless approach.
    debugPrint(
        '🔄 [SNAPSHOT_IMPORT] Recalculating final timeline positions (seamless)');
    _tableState.updateTimelineSeamless();
    debugPrint('✅ [SNAPSHOT_IMPORT] Timeline positions finalized');
  }

  Future<bool> _importSampleBankState(
      Map<String, dynamic> sampleBankData) async {
    try {
      debugPrint('🎛️ [SNAPSHOT_IMPORT] Importing sample bank state');

      final maxSlots = SampleBankState.maxSampleSlots;
      final samples =
          (sampleBankData['samples'] as List<dynamic>? ?? const <dynamic>[]);
      final snapshotSlots = samples.length.clamp(0, maxSlots);
      final snapshotMaxSlots = ((sampleBankData['max_slots'] as num?)?.toInt() ??
              samples.length)
          .clamp(0, maxSlots);
      debugPrint(
          '🎛️ [SNAPSHOT_IMPORT] Sample slots in snapshot: list=${samples.length}, max_slots=$snapshotMaxSlots, importing up to $snapshotSlots');

      // Clear existing samples and colors first
      _sampleBankState.clearAllColors(); // Clear all project colors
      for (int i = 0; i < maxSlots; i++) {
        _sampleBankState.unloadSample(i);
      }

      final missingIssues = <MissingSampleIssue>[];
      int loadedCount = 0;

      // Import samples
      for (int i = 0; i < snapshotSlots; i++) {
        final sampleData = samples[i] as Map<String, dynamic>;
        final loaded = sampleData['loaded'] as bool;
        final settings = sampleData['settings'] as Map<String, dynamic>?;
        final volume = ((settings?['volume'] ?? 1.0) as num).toDouble();
        final pitch = ((settings?['pitch'] ?? 1.0) as num).toDouble();
        final sampleId = sampleData['sample_id'] as String?;
        final filePath = sampleData['file_path'] as String?;

        // Import color if present (project-specific colors)
        if (sampleData.containsKey('color')) {
          final colorHex = sampleData['color'] as String;
          try {
            final color = _hexToColor(colorHex);
            _sampleBankState.setSampleColor(i, color);
            debugPrint(
                '🎨 [SNAPSHOT_IMPORT] Imported color for slot $i: $colorHex');
          } catch (e) {
            debugPrint(
                '⚠️ [SNAPSHOT_IMPORT] Failed to parse color for slot $i: $e');
          }
        }

        if (loaded) {
          final loadResult = await _sampleBankState.loadSampleReference(
            i,
            sampleId: sampleId,
            filePathHint: filePath,
            displayName: sampleData['display_name'] as String?,
          );
          if (loadResult.success) {
            loadedCount++;
          } else {
            final reason = _mapMissingReason(loadResult.failureReason);
            missingIssues.add(
              MissingSampleIssue(
                slot: i,
                sampleId: sampleId,
                filePath: filePath,
                displayName: sampleData['display_name'] as String?,
                reason: reason,
                details: loadResult.message,
              ),
            );
            debugPrint(
                '⚠️ [SNAPSHOT_IMPORT] Failed to load sample slot=$i id=$sampleId path=$filePath reason=$reason');
          }
        }

        // Set volume and pitch regardless of load success
        _sampleBankState.setSampleSettings(i, volume: volume, pitch: pitch);
      }

      _sampleBankState.syncSampleBankState();

      _lastImportReport = SnapshotImportReport(
        missingSamples: List.unmodifiable(missingIssues),
        loadedSampleCount: loadedCount,
        failedSampleCount: missingIssues.length,
      );

      debugPrint('✅ [SNAPSHOT_IMPORT] Sample bank state imported');
      return true;
    } catch (e) {
      debugPrint('❌ [SNAPSHOT_IMPORT] Sample bank import failed: $e');
      return false;
    }
  }

  MissingSampleReason _mapMissingReason(
    SampleResolveFailureReason? reason,
  ) {
    switch (reason) {
      case SampleResolveFailureReason.missingSampleId:
        return MissingSampleReason.missingSampleId;
      case SampleResolveFailureReason.unknownSampleId:
        return MissingSampleReason.unknownSampleId;
      case SampleResolveFailureReason.missingAssetPath:
        return MissingSampleReason.missingAssetPath;
      case SampleResolveFailureReason.fileNotFound:
        return MissingSampleReason.fileNotFound;
      case null:
        return MissingSampleReason.loadFailed;
    }
  }

  void _augmentImportReportWithReferencedSlotGaps(Map<String, dynamic> source) {
    final tableData = source['table'] as Map<String, dynamic>?;
    final sampleBankData = source['sample_bank'] as Map<String, dynamic>?;
    final tableCells = tableData?['table_cells'] as List<dynamic>? ?? const [];
    final samples = sampleBankData?['samples'] as List<dynamic>? ?? const [];

    final referencedSlots = <int>{};
    for (final row in tableCells) {
      if (row is! List<dynamic>) continue;
      for (final cell in row) {
        if (cell is! Map<String, dynamic>) continue;
        final slot = (cell['sample_slot'] as num?)?.toInt() ?? -1;
        if (slot >= 0 && slot < SampleBankState.maxSampleSlots) {
          referencedSlots.add(slot);
        }
      }
    }

    if (referencedSlots.isEmpty) {
      return;
    }

    _sampleBankState.syncSampleBankState();
    final missing = List<MissingSampleIssue>.from(_lastImportReport.missingSamples);
    final existingSlots = missing.map((issue) => issue.slot).toSet();

    for (final slot in referencedSlots.toList()..sort()) {
      if (_sampleBankState.isSlotLoaded(slot) || existingSlots.contains(slot)) {
        continue;
      }
      final sampleData =
          slot < samples.length ? samples[slot] as Map<String, dynamic>? : null;
      missing.add(
        MissingSampleIssue(
          slot: slot,
          sampleId: sampleData?['sample_id'] as String?,
          filePath: sampleData?['file_path'] as String?,
          displayName: sampleData?['display_name'] as String?,
          reason: MissingSampleReason.loadFailed,
          details:
              'Table references slot ${slot < 26 ? String.fromCharCode(65 + slot) : slot + 1}, but no sample is loaded there after import.',
        ),
      );
    }

    if (missing.length == _lastImportReport.missingSamples.length) {
      return;
    }

    _lastImportReport = SnapshotImportReport(
      missingSamples: List.unmodifiable(missing),
      loadedSampleCount: _lastImportReport.loadedSampleCount,
      failedSampleCount: missing.length,
    );
  }

  bool _importTableState(Map<String, dynamic> tableData) {
    try {
      debugPrint('📊 [SNAPSHOT_IMPORT] Importing table state');

      final sectionsCount = tableData['sections_count'] as int;
      final sections = tableData['sections'] as List<dynamic>;
      final layers = tableData['layers'] as List<dynamic>? ?? [];
      final tableCells = tableData['table_cells'] as List<dynamic>? ?? [];

      debugPrint('📊 [SNAPSHOT_IMPORT] Sections count: $sectionsCount');
      debugPrint('📊 [SNAPSHOT_IMPORT] Layers data length: ${layers.length}');
      debugPrint('📊 [SNAPSHOT_IMPORT] Table cells rows: ${tableCells.length}');

      if (sectionsCount != sections.length) {
        debugPrint(
            '❌ [SNAPSHOT_IMPORT] Sections count mismatch: expected $sectionsCount, got ${sections.length}');
        return false;
      }

      // Reconcile against native section count first; cached Dart count may be stale.
      final currentNativeCount = _tableState.getNativeSectionsCount();
      debugPrint(
          '📊 [SNAPSHOT_IMPORT] Current sections (native=$currentNativeCount, cached=${_tableState.sectionsCount}), target: $sectionsCount');
      if (currentNativeCount > sectionsCount) {
        debugPrint('🔄 [SNAPSHOT_IMPORT] Deleting extra sections');
        for (int i = currentNativeCount - 1; i >= sectionsCount; i--) {
          _tableState.deleteSection(i, undoRecord: false);
        }
      } else if (currentNativeCount < sectionsCount) {
        debugPrint('🔄 [SNAPSHOT_IMPORT] Adding missing sections');
        for (int i = currentNativeCount; i < sectionsCount; i++) {
          _tableState.appendSection(undoRecord: false);
        }
      }
      final converged = _tableState.syncTableStateUntilSectionsCount(
        sectionsCount,
        maxAttempts: 24,
      );
      if (!converged) {
        debugPrint(
            '⚠️ [SNAPSHOT_IMPORT] Section count did not fully converge after reconcile (native=${_tableState.getNativeSectionsCount()}, cached=${_tableState.sectionsCount}, expected=$sectionsCount)');
      }

      // Apply per-section step counts
      debugPrint('🔄 [SNAPSHOT_IMPORT] Setting section step counts');
      for (int i = 0; i < sections.length; i++) {
        final sectionData = sections[i] as Map<String, dynamic>;
        final numSteps = sectionData['num_steps'] as int;
        debugPrint('  Section $i: $numSteps steps');
        _tableState.setSectionStepCount(i, numSteps, undoRecord: false);
      }

      // Import layers using bulk update - CRITICAL: ensure all sections get their layer data
      debugPrint('🔄 [SNAPSHOT_IMPORT] Importing layers for all sections');
      final layersLenFlat = <int>[];

      // We must provide layer data for ALL sections (5 layers per section)
      for (int s = 0; s < sectionsCount; s++) {
        if (s < layers.length) {
          final sectionLayers = layers[s] as List<dynamic>;
          debugPrint('  Section $s layers: ${sectionLayers.length} layers');

          // Import all 5 layers for this section
          for (int l = 0; l < 5; l++) {
            if (l < sectionLayers.length) {
              final len = (sectionLayers[l] as num).toInt();
              layersLenFlat.add(len);
              debugPrint('    Layer $l: $len columns');
            } else {
              // Default to 4 columns if layer data is missing (L4 for mic track defaults to 0)
              layersLenFlat.add(l == 4 ? 0 : 4);
              debugPrint('    Layer $l: ${l == 4 ? 0 : 4} columns (default)');
            }
          }
        } else {
          // If no layer data for this section, use defaults (5 layers, L4 empty for mic)
          debugPrint(
              '  Section $s: using default layer configuration (5 layers, L4 empty)');
          for (int l = 0; l < 5; l++) {
            layersLenFlat.add(l == 4 ? 0 : 4);
          }
        }
      }

      if (layersLenFlat.isNotEmpty) {
        debugPrint(
            '🔄 [SNAPSHOT_IMPORT] Applying ${layersLenFlat.length} layer configurations');
        _tableState.updateManyLayers(0, sectionsCount, layersLenFlat);
      }

      // Import table cells individually
      debugPrint('🔄 [SNAPSHOT_IMPORT] Importing table cells');
      int cellsImported = 0;
      for (int step = 0; step < tableCells.length; step++) {
        final row = tableCells[step] as List<dynamic>;
        for (int col = 0;
            col < row.length && col < _tableState.maxCols;
            col++) {
          final cellData = row[col] as Map<String, dynamic>;
          final sampleSlot = cellData['sample_slot'] as int;

          // Skip empty cells to save processing time
          if (sampleSlot < 0) continue;

          final settings = cellData['settings'] as Map<String, dynamic>?;
          final volume = ((settings?['volume'] ?? 1.0) as num).toDouble();
          final pitch = ((settings?['pitch'] ?? 1.0) as num).toDouble();

          // Set slot and settings
          _tableState.setCell(step, col, sampleSlot, volume, pitch,
              undoRecord: false);
          cellsImported++;
        }
      }

      // Import layer modes (per-layer operational mode: sequence or rec)
      if (tableData.containsKey('layer_modes')) {
        debugPrint('🔄 [SNAPSHOT_IMPORT] Importing layer modes');
        final layerModesData = tableData['layer_modes'] as Map<String, dynamic>;
        for (final entry in layerModesData.entries) {
          final layer = int.parse(entry.key);
          final modeName = entry.value as String;
          try {
            final mode = LayerMode.values.byName(modeName);
            _tableState.setLayerMode(layer, mode);
            debugPrint('  Layer $layer: $modeName');
          } catch (e) {
            debugPrint(
                '⚠️ [SNAPSHOT_IMPORT] Invalid layer mode for layer $layer: $modeName');
          }
        }
      }

      _importMuteSoloState(tableData);

      debugPrint(
          '✅ [SNAPSHOT_IMPORT] Table state imported: $cellsImported non-empty cells');
      return true;
    } catch (e) {
      debugPrint('❌ [SNAPSHOT_IMPORT] Table import failed: $e');
      return false;
    }
  }

  bool _importPlaybackState(Map<String, dynamic> playbackData) {
    try {
      debugPrint('🎵 [SNAPSHOT_IMPORT] Importing playback state');

      final bpm = ((playbackData['bpm'] ?? _playbackState.bpm) as num).toInt();
      final songMode = ((playbackData['song_mode'] ?? (_playbackState.songMode ? 1 : 0))
              as num)
          .toInt();
      final currentSection =
          ((playbackData['current_section'] ?? 0) as num).toInt();
      final sectionsLoopsNum =
          (playbackData['sections_loops_num'] as List<dynamic>?) ??
              const <dynamic>[];

      debugPrint(
          '  📊 Saved state: BPM=$bpm, songMode=$songMode, currentSection=$currentSection');

      // Set playback parameters
      _playbackState.setBpm(bpm);
      _playbackState.setSongMode(songMode != 0);

      // Note: Region setting would need to be added to PlaybackState if not already available

      // Set section loop counts
      for (int i = 0; i < sectionsLoopsNum.length && i < 64; i++) {
        final loops = (sectionsLoopsNum[i] as num).toInt();
        _playbackState.setSectionLoopsNum(i, loops);
      }

      // Import master FX (v2 nested block preferred; legacy keys fallback).
      final masterFx = playbackData['master_fx'] as Map<String, dynamic>?;
      final eqDb = masterFx?['eq_db'] as Map<String, dynamic>?;
      final volume01 = ((masterFx?['volume01'] ??
                  playbackData['master_volume01'] ??
                  _playbackState.masterVolume)
              as num)
          .toDouble();
      final reverbWet01 = ((masterFx?['reverb_wet01'] ??
                  playbackData['master_reverb_wet01'] ??
                  _playbackState.masterReverbWet)
              as num)
          .toDouble();
      final eqLow = ((eqDb?['low'] ??
                  playbackData['master_eq_low_db'] ??
                  _playbackState.masterEqLowDbNotifier.value)
              as num)
          .toInt();
      final eqMid = ((eqDb?['mid'] ??
                  playbackData['master_eq_mid_db'] ??
                  _playbackState.masterEqMidDbNotifier.value)
              as num)
          .toInt();
      final eqHigh = ((eqDb?['high'] ??
                  playbackData['master_eq_high_db'] ??
                  _playbackState.masterEqHighDbNotifier.value)
              as num)
          .toInt();

      _playbackState.setMasterVolume(volume01);
      _playbackState.setMasterReverbWet(reverbWet01);
      _playbackState.setMasterEqBandDb(0, eqLow);
      _playbackState.setMasterEqBandDb(1, eqMid);
      _playbackState.setMasterEqBandDb(2, eqHigh);

      // IMPORTANT: Always start from section 0 on import for consistency
      // The saved currentSection is informational only and could cause UI confusion
      // if the project was saved mid-playback or at a later section
      debugPrint(
          '  🔄 Resetting to section 0 (saved section was $currentSection)');
      _playbackState.switchToSection(0);

      debugPrint('✅ [SNAPSHOT_IMPORT] Playback state imported');
      return true;
    } catch (e) {
      debugPrint('❌ [SNAPSHOT_IMPORT] Playback import failed: $e');
      return false;
    }
  }

  void _importMuteSoloState(Map<String, dynamic> tableData) {
    // Import layer mute/solo (clear all first, then restore from snapshot).
    _tableState.clearAllLayerMuteSolo();

    final muteSoloData = tableData['mute_solo'] as Map<String, dynamic>?;
    final layerMutedData = (muteSoloData?['layer_muted'] ??
            tableData['layer_muted']) as Map<String, dynamic>?;
    final layerSoloedData = (muteSoloData?['layer_soloed'] ??
            tableData['layer_soloed']) as Map<String, dynamic>?;
    final layerColumnMutedData = (muteSoloData?['layer_column_muted'] ??
            tableData['layer_column_muted']) as Map<String, dynamic>?;
    final layerColumnSoloedData = (muteSoloData?['layer_column_soloed'] ??
            tableData['layer_column_soloed']) as Map<String, dynamic>?;

    if (layerMutedData != null) {
      for (final entry in layerMutedData.entries) {
        final layer = int.tryParse(entry.key);
        if (layer == null) continue;
        _tableState.setLayerMuted(layer, entry.value == true);
      }
    }
    if (layerSoloedData != null) {
      for (final entry in layerSoloedData.entries) {
        final layer = int.tryParse(entry.key);
        if (layer == null) continue;
        _tableState.setLayerSoloed(layer, entry.value == true);
      }
    }
    if (layerColumnMutedData != null) {
      for (final entry in layerColumnMutedData.entries) {
        final parts = entry.key.split(':');
        if (parts.length != 2) continue;
        final layer = int.tryParse(parts[0]);
        final col = int.tryParse(parts[1]);
        if (layer == null || col == null) continue;
        _tableState.setLayerColumnMuted(layer, col, entry.value == true);
      }
    }
    if (layerColumnSoloedData != null) {
      for (final entry in layerColumnSoloedData.entries) {
        final parts = entry.key.split(':');
        if (parts.length != 2) continue;
        final layer = int.tryParse(parts[0]);
        final col = int.tryParse(parts[1]);
        if (layer == null || col == null) continue;
        _tableState.setLayerColumnSoloed(layer, col, entry.value == true);
      }
    } else if (tableData.containsKey('column_soloed')) {
      // Backward compatibility: old snapshots stored global column solo.
      // Apply it to every layer to preserve previous audible intent.
      final columnSoloedData = tableData['column_soloed'] as Map<String, dynamic>;
      for (final entry in columnSoloedData.entries) {
        final col = int.tryParse(entry.key);
        if (col == null) continue;
        final soloed = entry.value == true;
        for (int layer = 0; layer < TableState.maxLayersPerSection; layer++) {
          _tableState.setLayerColumnSoloed(layer, col, soloed);
        }
      }
    }
  }

  bool _importLayerFxState(Map<String, dynamic> tableData) {
    try {
      final layerFx = tableData['layer_fx'] as Map<String, dynamic>?;
      if (layerFx == null) return true; // Optional block for backward compatibility.

      for (final sectionEntry in layerFx.entries) {
        final section = int.tryParse(sectionEntry.key);
        if (section == null ||
            section < 0 ||
            section >= _tableState.sectionsCount) {
          continue;
        }
        final perLayer = sectionEntry.value as Map<String, dynamic>?;
        if (perLayer == null) continue;
        for (final layerEntry in perLayer.entries) {
          final layer = int.tryParse(layerEntry.key);
          if (layer == null ||
              layer < 0 ||
              layer >= TableState.maxLayersPerSection) {
            continue;
          }
          final layerValue = layerEntry.value as Map<String, dynamic>?;
          if (layerValue == null) continue;

          final reverb = layerValue['reverb'] as Map<String, dynamic>?;
          final eqDb = layerValue['eq_db'] as Map<String, dynamic>?;

          final send01 =
              ((reverb?['send01'] ?? _playbackState.getSectionLayerReverbSend(section, layer))
                      as num)
                  .toDouble();
          final room01 =
              ((reverb?['room01'] ?? _playbackState.getSectionLayerReverbRoom(section, layer))
                      as num)
                  .toDouble();
          final damp01 =
              ((reverb?['damp01'] ?? _playbackState.getSectionLayerReverbDamp(section, layer))
                      as num)
                  .toDouble();
          _playbackState.setSectionLayerReverb(
            section: section,
            layer: layer,
            send01: send01,
            room01: room01,
            damp01: damp01,
          );

          final low = ((eqDb?['low'] ??
                      _playbackState.getSectionLayerEqBandDb(section, layer, 0))
                  as num)
              .toInt();
          final mid = ((eqDb?['mid'] ??
                      _playbackState.getSectionLayerEqBandDb(section, layer, 1))
                  as num)
              .toInt();
          final high = ((eqDb?['high'] ??
                      _playbackState.getSectionLayerEqBandDb(section, layer, 2))
                  as num)
              .toInt();
          _playbackState.setSectionLayerEqBandDb(
            section: section,
            layer: layer,
            band: 0,
            db: low,
          );
          _playbackState.setSectionLayerEqBandDb(
            section: section,
            layer: layer,
            band: 1,
            db: mid,
          );
          _playbackState.setSectionLayerEqBandDb(
            section: section,
            layer: layer,
            band: 2,
            db: high,
          );

          final volume01 = ((layerValue['volume01'] ??
                  _playbackState.getSectionLayerVolume(section, layer))
              as num)
              .toDouble()
              .clamp(0.0, 1.0);
          _playbackState.setSectionLayerVolume(
            section: section,
            layer: layer,
            volume01: volume01,
          );
        }
      }
      return true;
    } catch (e) {
      debugPrint('❌ [SNAPSHOT_IMPORT] Layer FX import failed: $e');
      return false;
    }
  }

  /// Validate JSON structure against expected schema
  bool validateJson(String jsonString) {
    try {
      final dynamic jsonData = json.decode(jsonString);
      if (jsonData is! Map<String, dynamic>) return false;

      final schemaVersion = jsonData['schema_version'];
      if (schemaVersion != 1 &&
          schemaVersion != 2 &&
          schemaVersion != 3) {
        return false;
      }

      final source = jsonData['source'];
      if (source is! Map<String, dynamic>) return false;

      // Basic validation - check required fields exist
      final requiredModules = ['table', 'playback', 'sample_bank'];
      for (final module in requiredModules) {
        if (!source.containsKey(module)) {
          debugPrint('⚠️ [SNAPSHOT_VALIDATE] Missing module: $module');
          return false;
        }
      }

      return true;
    } catch (e) {
      debugPrint('❌ [SNAPSHOT_VALIDATE] Validation failed: $e');
      return false;
    }
  }

  /// Get snapshot metadata without importing
  Map<String, dynamic>? getSnapshotMetadata(String jsonString) {
    try {
      final dynamic jsonData = json.decode(jsonString);
      if (jsonData is! Map<String, dynamic>) return null;

      final snapshot = jsonData;
      return {
        'id': snapshot['id'],
        'name': snapshot['name'],
        'description': snapshot['description'],
        'created_at': snapshot['created_at'],
        'schema_version': snapshot['schema_version'],
      };
    } catch (e) {
      debugPrint('❌ [SNAPSHOT_METADATA] Failed to get metadata: $e');
      return null;
    }
  }

  /// Convert hex color string to Color object (e.g., "#FF5733" -> Color)
  Color _hexToColor(String hex) {
    final buffer = StringBuffer();
    if (hex.startsWith('#')) {
      buffer.write(hex.substring(1)); // Remove #
    } else {
      buffer.write(hex);
    }
    return Color(int.parse(buffer.toString(), radix: 16) + 0xFF000000);
  }
}
