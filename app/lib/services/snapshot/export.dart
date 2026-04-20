import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'; // For Color class
import 'dart:ffi' as ffi;
import '../../ffi/sample_bank_bindings.dart';
import '../../state/sequencer/table.dart';
import '../../state/sequencer/playback.dart';
import '../../state/sequencer/sample_bank.dart';
import 'debug_snapshot.dart';
import 'snapshot_table_validator.dart';

/// Snapshot export service for sequencer state
class SnapshotExporter {
  static const int schemaVersion = 3;

  final TableState _tableState;
  final PlaybackState _playbackState;
  final SampleBankState _sampleBankState;

  const SnapshotExporter({
    required TableState tableState,
    required PlaybackState playbackState,
    required SampleBankState sampleBankState,
  }) : _tableState = tableState,
       _playbackState = playbackState,
       _sampleBankState = sampleBankState;

  /// Export current sequencer state to JSON string
  String exportToJson({
    required String name,
    String? id,
    String? description,
  }) {
    const maxAttempts = 3;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      // Align Dart-cached section count and pointers with native before serializing.
      final synced = _tableState.syncTableStateForSerialization();
      if (!synced) {
        debugPrint(
            '⚠️ [SNAPSHOT_EXPORT] Table sync did not fully stabilize before export (attempt $attempt/$maxAttempts)');
      }
      final nativeSectionsCount = _tableState.getTableStatePtr().ref.sections_count;
      final snapshot = _buildSnapshot(
        name: name,
        id: id,
        description: description,
      );
      final source = snapshot['source'] as Map<String, dynamic>?;
      final table = source?['table'] as Map<String, dynamic>?;
      final exportedSectionsCount = table?['sections_count'];
      final structurallyValid = SnapshotTableValidator.isValidSnapshotSource(
        snapshot,
        maxSteps: _tableState.maxSteps,
        maxCols: _tableState.maxCols,
      );
      final missingReferencedSlots = _findReferencedButUnloadedSlots(snapshot);

      if (exportedSectionsCount != nativeSectionsCount) {
        debugPrint(
            '⚠️ [SNAPSHOT_EXPORT] sections_count mismatch (native=$nativeSectionsCount, exported=$exportedSectionsCount), attempt $attempt/$maxAttempts');
      } else if (!structurallyValid) {
        debugPrint(
            '⚠️ [SNAPSHOT_EXPORT] structural validation failed, attempt $attempt/$maxAttempts');
      } else if (missingReferencedSlots.isNotEmpty) {
        debugPrint(
            '⚠️ [SNAPSHOT_EXPORT] sample bank mismatch, referenced but unloaded slots: $missingReferencedSlots');
        throw StateError(
          'Cannot export project: table references unloaded sample slots ${_formatSlotList(missingReferencedSlots)}.',
        );
      } else {
        return JsonEncoder.withIndent('  ').convert(snapshot);
      }
    }

    throw StateError(
      'Snapshot export failed after bounded retries; keeping previous latest-state file.',
    );
  }

  Map<String, dynamic> _buildSnapshot({
    required String name,
    String? id,
    String? description,
  }) {
    debugPrint('📋 [SNAPSHOT_EXPORT] === STATE BEFORE EXPORT ===');
    SnapshotDebugger.printTableState(_tableState);
    SnapshotDebugger.printSampleBankState(_sampleBankState);
    SnapshotDebugger.printPlaybackState(_playbackState);

    return {
      'schema_version': schemaVersion,
      'id': id ?? _generateSnapshotId(),
      'name': name,
      'description': description,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'source': {
        'table': _exportTableState(),
        'playback': _exportPlaybackState(),
        'sample_bank': _exportSampleBankState(),
      },
      'renders': [], // Empty for now, can be extended later
    };
  }

  String _generateSnapshotId() {
    // Generate a simple ID based on timestamp
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return timestamp.toRadixString(16).padLeft(24, '0');
  }

  Map<String, dynamic> _exportTableState() {
    debugPrint('📊 [SNAPSHOT_EXPORT] Exporting table state');

    final sectionsCount = _tableState.sectionsCount;

    // Export sections using public getters
    final sections = <Map<String, dynamic>>[];
    for (int i = 0; i < sectionsCount; i++) {
      sections.add({
        'start_step': _tableState.getSectionStartStep(i),
        'num_steps': _tableState.getSectionStepCount(i),
      });
    }

    // Export layers (read from native layers array using public API)
    final layers = <List<int>>[];
    final statePtr = _tableState.getTableStatePtr();
    final layersBase = statePtr.ref.layers_ptr;
    for (int s = 0; s < sectionsCount; s++) {
      final sectionLayers = <int>[];
      for (int l = 0; l < TableState.maxLayersPerSection; l++) {
        final li = s * TableState.maxLayersPerSection + l;
        sectionLayers.add((layersBase + li).ref.len);
      }
      layers.add(sectionLayers);
    }

    // Export table cells (only active rows)
    final table_cells = <List<Map<String, dynamic>>>[];
    int totalSteps = 0;
    for (final section in sections) {
      totalSteps += section['num_steps'] as int;
    }

    for (int step = 0; step < totalSteps && step < _tableState.maxSteps; step++) {
      final row = <Map<String, dynamic>>[];
      for (int col = 0; col < _tableState.maxCols; col++) {
        final cellPtr = _tableState.getCellPointer(step, col);
        final cell = cellPtr.ref;
        row.add({
          'sample_slot': cell.sample_slot,
          'settings': {
            'volume': cell.settings.volume,
            'pitch': cell.settings.pitch,
          },
        });
      }
      table_cells.add(row);
    }

    // Export layer modes (per-layer operational mode: sequence or rec)
    final layerModes = <String, String>{};
    for (int layer = 0; layer < TableState.maxLayersPerSection; layer++) {
      final mode = _tableState.getLayerMode(layer);
      layerModes[layer.toString()] = mode.name;
    }

    // Export mute/solo state (sparse bool maps; only true values are persisted)
    final layerMuted = <String, bool>{};
    final layerSoloed = <String, bool>{};
    final layerColumnMuted = <String, bool>{};
    final layerColumnSoloed = <String, bool>{};

    for (int layer = 0; layer < TableState.maxLayersPerSection; layer++) {
      if (_tableState.isLayerMuted(layer)) {
        layerMuted[layer.toString()] = true;
      }
      if (_tableState.isLayerSoloed(layer)) {
        layerSoloed[layer.toString()] = true;
      }
      for (int col = 0; col < TableState.maxColsPerLayer; col++) {
        final key = '$layer:$col';
        if (_tableState.isLayerColumnMuted(layer, col)) {
          layerColumnMuted[key] = true;
        }
        if (_tableState.isLayerColumnSoloed(layer, col)) {
          layerColumnSoloed[key] = true;
        }
      }
    }

    // Export per-section/per-layer FX as explicit normalized values.
    final layerFx = <String, Map<String, dynamic>>{};
    for (int section = 0; section < sectionsCount; section++) {
      final sectionLayers = <String, dynamic>{};
      for (int layer = 0; layer < TableState.maxLayersPerSection; layer++) {
        sectionLayers[layer.toString()] = {
          'volume01': _playbackState.getSectionLayerVolume(section, layer),
          'reverb': {
            'send01': _playbackState.getSectionLayerReverbSend(section, layer),
            'room01': _playbackState.getSectionLayerReverbRoom(section, layer),
            'damp01': _playbackState.getSectionLayerReverbDamp(section, layer),
          },
          'eq_db': {
            'low': _playbackState.getSectionLayerEqBandDb(section, layer, 0),
            'mid': _playbackState.getSectionLayerEqBandDb(section, layer, 1),
            'high': _playbackState.getSectionLayerEqBandDb(section, layer, 2),
          },
        };
      }
      layerFx[section.toString()] = sectionLayers;
    }

    return {
      'sections_count': sectionsCount,
      'sections': sections,
      'layers': layers,
      'table_cells': table_cells,
      'layer_modes': layerModes,
      // Legacy top-level keys kept for backward compatibility.
      'layer_muted': layerMuted,
      'layer_soloed': layerSoloed,
      'layer_column_muted': layerColumnMuted,
      'layer_column_soloed': layerColumnSoloed,
      // v2 extendable groups.
      'mute_solo': {
        'layer_muted': layerMuted,
        'layer_soloed': layerSoloed,
        'layer_column_muted': layerColumnMuted,
        'layer_column_soloed': layerColumnSoloed,
      },
      'layer_fx': layerFx,
    };
  }

  Map<String, dynamic> _exportPlaybackState() {
    debugPrint('🎵 [SNAPSHOT_EXPORT] Exporting playback state');

    final playbackPtr = _playbackState.getPlaybackStatePtr();
    int tries = 0;
    const maxTries = 3;

    // Seqlock reader pattern
    while (true) {
      final v1 = playbackPtr.ref.version;
      if ((v1 & 1) != 0) { // Odd = writer active
        if (++tries >= maxTries) {
          debugPrint('⚠️ [SNAPSHOT_EXPORT] Failed to read playback state');
          return _getDefaultPlaybackState();
        }
        continue;
      }

      final sectionsLoopsNum = <int>[];
      final loopsPtr = playbackPtr.ref.sections_loops_num;
      for (int i = 0; i < 64; i++) { // MAX_SECTIONS = 64
        sectionsLoopsNum.add(loopsPtr.elementAt(i).value);
      }

      final v2 = playbackPtr.ref.version;
      if (v1 == v2) {
        return {
          'bpm': playbackPtr.ref.bpm,
          'region_start': playbackPtr.ref.region_start,
          'region_end': playbackPtr.ref.region_end,
          'song_mode': playbackPtr.ref.song_mode,
          'current_section': playbackPtr.ref.current_section,
          'current_section_loop': playbackPtr.ref.current_section_loop,
          'sections_loops_num': sectionsLoopsNum,
          // v2 extendable block: full master FX state.
          'master_fx': {
            'volume01': _playbackState.masterVolume,
            'reverb_wet01': _playbackState.masterReverbWet,
            'eq_db': {
              'low': _playbackState.masterEqLowDbNotifier.value,
              'mid': _playbackState.masterEqMidDbNotifier.value,
              'high': _playbackState.masterEqHighDbNotifier.value,
            },
          },
          // Legacy duplicated fields for easier fallback parsing.
          'master_volume01': _playbackState.masterVolume,
          'master_reverb_wet01': _playbackState.masterReverbWet,
          'master_eq_low_db': _playbackState.masterEqLowDbNotifier.value,
          'master_eq_mid_db': _playbackState.masterEqMidDbNotifier.value,
          'master_eq_high_db': _playbackState.masterEqHighDbNotifier.value,
        };
      }
      if (++tries >= maxTries) {
        debugPrint('⚠️ [SNAPSHOT_EXPORT] Failed to read playback state');
        return _getDefaultPlaybackState();
      }
    }
  }

  Map<String, dynamic> _getDefaultPlaybackState() {
    return {
      'bpm': 120,
      'region_start': 0,
      'region_end': 16,
      'song_mode': 0,
      'current_section': 0,
      'current_section_loop': 0,
      'sections_loops_num': List.filled(64, 4),
      'master_fx': {
        'volume01': 1.0,
        'reverb_wet01': 0.0,
        'eq_db': {
          'low': 0,
          'mid': 0,
          'high': 0,
        },
      },
      'master_volume01': 1.0,
      'master_reverb_wet01': 0.0,
      'master_eq_low_db': 0,
      'master_eq_mid_db': 0,
      'master_eq_high_db': 0,
    };
  }

  Map<String, dynamic> _exportSampleBankState() {
    debugPrint('🎛️ [SNAPSHOT_EXPORT] Exporting sample bank state');

    final sampleBankPtr = _sampleBankState.getSampleBankStatePtr();
    final uiColors = _sampleBankState.uiBankColors;
    final maxSlots = SampleBankState.maxSampleSlots;
    int tries = 0;
    const maxTries = 3;

    // Seqlock reader pattern
    while (true) {
      final v1 = sampleBankPtr.ref.version;
      if ((v1 & 1) != 0) { // Odd = writer active
        if (++tries >= maxTries) {
          debugPrint('⚠️ [SNAPSHOT_EXPORT] Failed to read sample bank state');
          return _getDefaultSampleBankState();
        }
        continue;
      }

      final samples = <Map<String, dynamic>>[];
      final samplesPtr = sampleBankPtr.ref.samples_ptr;
      for (int i = 0; i < maxSlots; i++) {
        final samplePtr = samplesPtr + i;
        final sampleData = SampleData.fromPointer(samplePtr);
        
        // Build sample entry
        final sampleEntry = <String, dynamic>{
          'loaded': sampleData.loaded,
          'settings': {
            'volume': sampleData.volume,
            'pitch': sampleData.pitch,
          },
          'sample_id': sampleData.id,
          'file_path': sampleData.filePath,
          'display_name': sampleData.displayName,
        };
        
        // Always include project-specific color (for all slots, loaded or not)
        final color = i < uiColors.length ? uiColors[i] : uiColors[0];
        final hexColor = _colorToHex(color);
        sampleEntry['color'] = hexColor;
        
        samples.add(sampleEntry);
      }

      final v2 = sampleBankPtr.ref.version;
      if (v1 == v2) {
        return {
          'max_slots': maxSlots,
          'samples': samples,
        };
      }
      if (++tries >= maxTries) {
        debugPrint('⚠️ [SNAPSHOT_EXPORT] Failed to read sample bank state');
        return _getDefaultSampleBankState();
      }
    }
  }

  Map<String, dynamic> _getDefaultSampleBankState() {
    final maxSlots = SampleBankState.maxSampleSlots;
    final samples = <Map<String, dynamic>>[];
    for (int i = 0; i < maxSlots; i++) {
      samples.add({
        'loaded': false,
        'settings': {
          'volume': 1.0,
          'pitch': 1.0,
        },
        'sample_id': null,
        'file_path': null,
        'display_name': null,
        // No color for empty slots
      });
    }
    return {
      'max_slots': maxSlots,
      'samples': samples,
    };
  }

  List<int> _findReferencedButUnloadedSlots(Map<String, dynamic> snapshot) {
    final source = snapshot['source'] as Map<String, dynamic>?;
    final table = source?['table'] as Map<String, dynamic>?;
    final sampleBank = source?['sample_bank'] as Map<String, dynamic>?;
    final tableCells = table?['table_cells'] as List<dynamic>? ?? const [];
    final samples = sampleBank?['samples'] as List<dynamic>? ?? const [];

    final maxSlots = ((sampleBank?['max_slots'] as num?)?.toInt() ??
            SampleBankState.maxSampleSlots)
        .clamp(1, SampleBankState.maxSampleSlots);

    final referencedSlots = <int>{};
    for (final row in tableCells) {
      if (row is! List<dynamic>) continue;
      for (final cell in row) {
        if (cell is! Map<String, dynamic>) continue;
        final slot = (cell['sample_slot'] as num?)?.toInt() ?? -1;
        if (slot >= 0 && slot < maxSlots) {
          referencedSlots.add(slot);
        }
      }
    }

    final missing = <int>[];
    for (final slot in referencedSlots.toList()..sort()) {
      final sampleData =
          slot < samples.length ? samples[slot] as Map<String, dynamic>? : null;
      final loaded = sampleData?['loaded'] == true;
      if (!loaded) {
        missing.add(slot);
      }
    }
    return missing;
  }

  String _formatSlotList(List<int> slots) {
    return slots
        .map((slot) {
          final label = slot < 26 ? String.fromCharCode(65 + slot) : '${slot + 1}';
          return '$label($slot)';
        })
        .join(', ');
  }
  
  /// Convert Color to hex string (e.g., #FF5733)
  String _colorToHex(Color color) {
    return '#${color.red.toRadixString(16).padLeft(2, '0')}'
           '${color.green.toRadixString(16).padLeft(2, '0')}'
           '${color.blue.toRadixString(16).padLeft(2, '0')}'.toUpperCase();
  }
}
