import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'; // For Color class
import 'dart:ffi' as ffi;
import '../../ffi/sample_bank_bindings.dart';
import '../../state/sequencer/table.dart';
import '../../state/sequencer/playback.dart';
import '../../state/sequencer/sample_bank.dart';
import 'debug_snapshot.dart';

/// Snapshot export service for sequencer state
class SnapshotExporter {
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
    debugPrint('📋 [SNAPSHOT_EXPORT] === STATE BEFORE EXPORT ===');
    SnapshotDebugger.printTableState(_tableState);
    SnapshotDebugger.printSampleBankState(_sampleBankState);
    SnapshotDebugger.printPlaybackState(_playbackState);
    
    final snapshot = {
      'schema_version': 1,
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

    return JsonEncoder.withIndent('  ').convert(snapshot);
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
      for (int l = 0; l < 4; l++) { // MAX_LAYERS_PER_SECTION = 4
        final li = s * 4 + l;
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

    return {
      'sections_count': sectionsCount,
      'sections': sections,
      'layers': layers,
      'table_cells': table_cells,
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
    };
  }

  Map<String, dynamic> _exportSampleBankState() {
    debugPrint('🎛️ [SNAPSHOT_EXPORT] Exporting sample bank state');

    final sampleBankPtr = _sampleBankState.getSampleBankStatePtr();
    final uiColors = _sampleBankState.uiBankColors;  // Get UI colors
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
      for (int i = 0; i < 26; i++) { // MAX_SAMPLE_SLOTS = 26
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
          'max_slots': sampleBankPtr.ref.max_slots,
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
    final samples = <Map<String, dynamic>>[];
    for (int i = 0; i < 26; i++) {
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
      'max_slots': 26,
      'samples': samples,
    };
  }
  
  /// Convert Color to hex string (e.g., #FF5733)
  String _colorToHex(Color color) {
    return '#${color.red.toRadixString(16).padLeft(2, '0')}'
           '${color.green.toRadixString(16).padLeft(2, '0')}'
           '${color.blue.toRadixString(16).padLeft(2, '0')}'.toUpperCase();
  }
}
