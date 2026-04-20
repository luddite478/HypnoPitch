import 'package:flutter/foundation.dart';
import 'dart:ffi' as ffi;
import '../../state/sequencer/table.dart';
import '../../state/sequencer/playback.dart';
import '../../state/sequencer/sample_bank.dart';

/// Debug utility to print detailed snapshot state
class SnapshotDebugger {
  static void printTableState(TableState tableState) {
    debugPrint('=== TABLE STATE DEBUG ===');
    debugPrint('Sections count: ${tableState.sectionsCount}');
    
    for (int i = 0; i < tableState.sectionsCount; i++) {
      final start = tableState.getSectionStartStep(i);
      final steps = tableState.getSectionStepCount(i);
      debugPrint('Section $i: start=$start, steps=$steps (range: $start-${start + steps - 1})');
      
      // Print layer configuration
      final statePtr = tableState.getTableStatePtr();
      final layersBase = statePtr.ref.layers_ptr;
      for (int l = 0; l < TableState.maxLayersPerSection; l++) {
        final li = i * TableState.maxLayersPerSection + l;
        final len = (layersBase + li).ref.len;
        debugPrint('  Layer $l: $len columns');
      }
      
      // Count non-empty cells in this section
      int nonEmptyCells = 0;
      for (int step = start; step < start + steps; step++) {
        for (int col = 0; col < tableState.maxCols; col++) {
          final cellData = tableState.readCell(step, col);
          if (cellData.sampleSlot >= 0) {
            nonEmptyCells++;
            if (nonEmptyCells <= 5) {  // Print first 5 cells
              debugPrint('    Cell[$step,$col]: slot=${cellData.sampleSlot}, vol=${cellData.volume.toStringAsFixed(2)}, pitch=${cellData.pitch.toStringAsFixed(2)}');
            }
          }
        }
      }
      debugPrint('  Total non-empty cells: $nonEmptyCells');
    }
    debugPrint('=========================');
  }
  
  static void printSampleBankState(SampleBankState sampleBankState) {
    debugPrint('=== SAMPLE BANK STATE DEBUG ===');
    debugPrint('Loaded count: ${sampleBankState.loadedCount}');
    
    for (int i = 0; i < SampleBankState.maxSampleSlots; i++) {
      if (sampleBankState.isSlotLoaded(i)) {
        final data = sampleBankState.getSampleData(i);
        debugPrint('Slot $i (${sampleBankState.getSlotLetter(i)}): ${data.displayName}');
        debugPrint('  Volume: ${data.volume.toStringAsFixed(2)}, Pitch: ${data.pitch.toStringAsFixed(2)}');
        debugPrint('  ID: ${data.id}');
      }
    }
    debugPrint('================================');
  }
  
  static void printPlaybackState(PlaybackState playbackState) {
    debugPrint('=== PLAYBACK STATE DEBUG ===');
    debugPrint('BPM: ${playbackState.bpm}');
    debugPrint('Song mode: ${playbackState.songMode}');
    debugPrint('Current section: ${playbackState.currentSection}');
    
    final loops = playbackState.getSectionsLoopsNum();
    for (int i = 0; i < loops.length && i < 10; i++) {
      debugPrint('Section $i loops: ${loops[i]}');
    }
    debugPrint('============================');
  }
}

