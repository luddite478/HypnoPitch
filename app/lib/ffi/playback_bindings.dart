import 'dart:ffi' as ffi;

import 'native_library.dart';
import 'package:ffi/ffi.dart' as pkg_ffi;

// Native PlaybackState structure (read-only snapshot)
final class NativePlaybackState extends ffi.Struct {
  @ffi.Uint32()
  external int version; // even=stable, odd=write in progress

  @ffi.Int32()
  external int is_playing;

  @ffi.Int32()
  external int current_step;

  @ffi.Int32()
  external int bpm;

  @ffi.Int32()
  external int region_start;

  @ffi.Int32()
  external int region_end;

  @ffi.Int32()
  external int song_mode;

  external ffi.Pointer<ffi.Int32> sections_loops_num; // pointer to per-section loop counts array

  @ffi.Int32()
  external int current_section;

  @ffi.Int32()
  external int current_section_loop;
}

// Native PlaybackRegion structure (if needed)
final class PlaybackRegion extends ffi.Struct {
  @ffi.Int32()
  external int start;

  @ffi.Int32()
  external int end;
}

/// FFI bindings for native playback functions
class PlaybackBindings {
  PlaybackBindings() {
    final lib = NativeLibrary.instance;

    _playbackInitPtr = lib.lookup<ffi.NativeFunction<ffi.Int32 Function()>>('playback_init');
    playbackInit = _playbackInitPtr.asFunction<int Function()>();

    _playbackCleanupPtr = lib.lookup<ffi.NativeFunction<ffi.Void Function()>>('playback_cleanup');
    playbackCleanup = _playbackCleanupPtr.asFunction<void Function()>();

    _playbackStartPtr = lib.lookup<ffi.NativeFunction<ffi.Int32 Function(ffi.Int32, ffi.Int32)>>('playback_start');
    playbackStart = _playbackStartPtr.asFunction<int Function(int, int)>();

    _playbackStopPtr = lib.lookup<ffi.NativeFunction<ffi.Void Function()>>('playback_stop');
    playbackStop = _playbackStopPtr.asFunction<void Function()>();

    _playbackSetBpmPtr = lib.lookup<ffi.NativeFunction<ffi.Void Function(ffi.Int32)>>('playback_set_bpm');
    playbackSetBpm = _playbackSetBpmPtr.asFunction<void Function(int)>();

    _playbackSetRegionPtr = lib.lookup<ffi.NativeFunction<ffi.Void Function(ffi.Int32, ffi.Int32)>>('playback_set_region');
    playbackSetRegion = _playbackSetRegionPtr.asFunction<void Function(int, int)>();

    _playbackSetModePtr = lib.lookup<ffi.NativeFunction<ffi.Void Function(ffi.Int32)>>('playback_set_mode');
    playbackSetMode = _playbackSetModePtr.asFunction<void Function(int)>();

    _playbackGetStatePtr = lib.lookup<ffi.NativeFunction<ffi.Pointer<NativePlaybackState> Function()>>('playback_get_state_ptr');
    playbackGetStatePtr = _playbackGetStatePtr.asFunction<ffi.Pointer<NativePlaybackState> Function()>();

    _playbackSetSectionLoopsNumPtr = lib.lookup<ffi.NativeFunction<ffi.Void Function(ffi.Int32, ffi.Int32)>>('playback_set_section_loops_num');
    playbackSetSectionLoopsNum = _playbackSetSectionLoopsNumPtr.asFunction<void Function(int, int)>();

    _switchToSectionPtr = lib.lookup<ffi.NativeFunction<ffi.Void Function(ffi.Int32)>>('switch_to_section');
    switchToSection = _switchToSectionPtr.asFunction<void Function(int)>();
    _switchToSectionImmediatePtr = lib.lookup<ffi.NativeFunction<ffi.Void Function(ffi.Int32)>>('switch_to_section_immediate');
    switchToSectionImmediate =
        _switchToSectionImmediatePtr.asFunction<void Function(int)>();
    _switchToSectionSeamlessSongModePtr =
        lib.lookup<ffi.NativeFunction<ffi.Void Function(ffi.Int32)>>(
            'switch_to_section_seamless_song_mode');
    switchToSectionSeamlessSongMode =
        _switchToSectionSeamlessSongModePtr.asFunction<void Function(int)>();

    // Master volume
    _playbackSetMasterVolumePtr = lib.lookup<ffi.NativeFunction<ffi.Void Function(ffi.Float)>>('playback_set_master_volume');
    playbackSetMasterVolume = _playbackSetMasterVolumePtr.asFunction<void Function(double)>();

    _playbackSetMasterReverbPtr = lib.lookup<ffi.NativeFunction<ffi.Void Function(ffi.Float)>>('playback_set_master_reverb');
    playbackSetMasterReverb = _playbackSetMasterReverbPtr.asFunction<void Function(double)>();

    _playbackSetMasterEqBandPtr = lib.lookup<ffi.NativeFunction<ffi.Void Function(ffi.Int32, ffi.Int32)>>('playback_set_master_eq_band');
    playbackSetMasterEqBand = _playbackSetMasterEqBandPtr.asFunction<void Function(int, int)>();

    _playbackSetSectionLayerReverbPtr = lib.lookup<
            ffi.NativeFunction<
                ffi.Void Function(
                    ffi.Int32, ffi.Int32, ffi.Float, ffi.Float, ffi.Float)>>(
        'playback_set_section_layer_reverb');
    playbackSetSectionLayerReverb = _playbackSetSectionLayerReverbPtr
        .asFunction<void Function(int, int, double, double, double)>();

    _playbackGetSectionLayerReverbSendPtr = lib.lookup<
            ffi.NativeFunction<ffi.Float Function(ffi.Int32, ffi.Int32)>>(
        'playback_get_section_layer_reverb_send');
    playbackGetSectionLayerReverbSend =
        _playbackGetSectionLayerReverbSendPtr.asFunction<double Function(int, int)>();

    _playbackGetSectionLayerReverbRoomPtr = lib.lookup<
            ffi.NativeFunction<ffi.Float Function(ffi.Int32, ffi.Int32)>>(
        'playback_get_section_layer_reverb_room');
    playbackGetSectionLayerReverbRoom =
        _playbackGetSectionLayerReverbRoomPtr.asFunction<double Function(int, int)>();

    _playbackGetSectionLayerReverbDampPtr = lib.lookup<
            ffi.NativeFunction<ffi.Float Function(ffi.Int32, ffi.Int32)>>(
        'playback_get_section_layer_reverb_damp');
    playbackGetSectionLayerReverbDamp =
        _playbackGetSectionLayerReverbDampPtr.asFunction<double Function(int, int)>();

    _playbackSetSectionLayerEqBandPtr = lib.lookup<
            ffi.NativeFunction<
                ffi.Void Function(
                    ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32)>>(
        'playback_set_section_layer_eq_band');
    playbackSetSectionLayerEqBand = _playbackSetSectionLayerEqBandPtr
        .asFunction<void Function(int, int, int, int)>();

    _playbackGetSectionLayerEqBandDbPtr = lib.lookup<
            ffi.NativeFunction<ffi.Int32 Function(ffi.Int32, ffi.Int32, ffi.Int32)>>(
        'playback_get_section_layer_eq_band_db');
    playbackGetSectionLayerEqBandDb =
        _playbackGetSectionLayerEqBandDbPtr.asFunction<int Function(int, int, int)>();

    _playbackSetSectionLayerVolumePtr = lib.lookup<
            ffi.NativeFunction<
                ffi.Void Function(ffi.Int32, ffi.Int32, ffi.Float)>>(
        'playback_set_section_layer_volume');
    playbackSetSectionLayerVolume = _playbackSetSectionLayerVolumePtr
        .asFunction<void Function(int, int, double)>();

    _playbackGetSectionLayerVolumePtr = lib.lookup<
            ffi.NativeFunction<ffi.Float Function(ffi.Int32, ffi.Int32)>>(
        'playback_get_section_layer_volume');
    playbackGetSectionLayerVolume = _playbackGetSectionLayerVolumePtr
        .asFunction<double Function(int, int)>();

    // Recording
    _recordingStartPtr = lib.lookup<ffi.NativeFunction<ffi.Int32 Function(ffi.Pointer<ffi.Char>)>>('recording_start');
    recordingStart = _recordingStartPtr.asFunction<int Function(ffi.Pointer<ffi.Char>)>();
    _recordingStopPtr = lib.lookup<ffi.NativeFunction<ffi.Void Function()>>('recording_stop');
    recordingStop = _recordingStopPtr.asFunction<void Function()>();
    _recordingIsActivePtr = lib.lookup<ffi.NativeFunction<ffi.Int32 Function()>>('recording_is_active');
    recordingIsActive = _recordingIsActivePtr.asFunction<int Function()>();

    // Preview
    _previewSamplePathPtr = lib.lookup<ffi.NativeFunction<ffi.Int32 Function(ffi.Pointer<pkg_ffi.Utf8>, ffi.Float, ffi.Float)>>('preview_sample_path');
    previewSamplePath = _previewSamplePathPtr.asFunction<int Function(ffi.Pointer<pkg_ffi.Utf8>, double, double)>();

    _previewSlotPtr = lib.lookup<ffi.NativeFunction<ffi.Int32 Function(ffi.Int32, ffi.Float, ffi.Float)>>('preview_slot');
    previewSlot = _previewSlotPtr.asFunction<int Function(int, double, double)>();

    _previewCellPtr = lib.lookup<ffi.NativeFunction<ffi.Int32 Function(ffi.Int32, ffi.Int32, ffi.Float, ffi.Float)>>('preview_cell');
    previewCell = _previewCellPtr.asFunction<int Function(int, int, double, double)>();

    _previewStopSamplePtr = lib.lookup<ffi.NativeFunction<ffi.Void Function()>>('preview_stop_sample');
    previewStopSample = _previewStopSamplePtr.asFunction<void Function()>();

    _previewStopCellPtr = lib.lookup<ffi.NativeFunction<ffi.Void Function()>>('preview_stop_cell');
    previewStopCell = _previewStopCellPtr.asFunction<void Function()>();

    // SunVox section sync
    _sunvoxSyncSectionPtr = lib.lookup<ffi.NativeFunction<ffi.Void Function(ffi.Int32)>>('sunvox_wrapper_sync_section');
    sunvoxSyncSection = _sunvoxSyncSectionPtr.asFunction<void Function(int)>();

    // SunVox reset all patterns
    _sunvoxResetAllPatternsPtr = lib.lookup<ffi.NativeFunction<ffi.Void Function()>>('sunvox_wrapper_reset_all_patterns');
    sunvoxResetAllPatterns = _sunvoxResetAllPatternsPtr.asFunction<void Function()>();

    // SunVox update timeline seamlessly (pass -1 to update all patterns)
    _sunvoxUpdateTimelineSeamlessPtr = lib.lookup<ffi.NativeFunction<ffi.Void Function(ffi.Int32)>>('sunvox_wrapper_update_timeline_seamless');
    sunvoxUpdateTimelineSeamless = _sunvoxUpdateTimelineSeamlessPtr.asFunction<void Function(int)>();

    // Enhanced playback logging
    _playbackSetEnhancedLoggingPtr = lib.lookup<ffi.NativeFunction<ffi.Void Function(ffi.Int32)>>('playback_set_enhanced_logging');
    playbackSetEnhancedLogging = _playbackSetEnhancedLoggingPtr.asFunction<void Function(int)>();

    // NOTE: sv_audio_callback2 bypass and Input module ID functions removed
    // Mic recording now bypasses SunVox entirely

    // SunVox waveform scope (wrapper)
    _svGetModuleScope2Ptr = lib.lookup<ffi.NativeFunction<ffi.Uint32 Function(ffi.Int32, ffi.Int32, ffi.Int32, ffi.Pointer<ffi.Int16>, ffi.Uint32)>>('sunvox_wrapper_get_module_scope2');
    svGetModuleScope2 = _svGetModuleScope2Ptr.asFunction<int Function(int, int, int, ffi.Pointer<ffi.Int16>, int)>();

    // Get waveform samples from WAV file
    _getWaveformSamplesPtr = lib.lookup<ffi.NativeFunction<ffi.Int32 Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Int16>, ffi.Int32, ffi.Int32)>>('recording_get_waveform_samples');
    getWaveformSamples = _getWaveformSamplesPtr.asFunction<int Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Int16>, int, int)>();

    // Set pattern event with offset (for precise sample positioning)
    _setPatternEventWithOffsetPtr = lib.lookup<ffi.NativeFunction<ffi.Void Function(
      ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32
    )>>('sunvox_wrapper_set_pattern_event_with_offset');
    setPatternEventWithOffset = _setPatternEventWithOffsetPtr.asFunction<void Function(
      int, int, int, int, int, int, int
    )>();
  }

  late final ffi.Pointer<ffi.NativeFunction<ffi.Int32 Function()>> _playbackInitPtr;
  late final int Function() playbackInit;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function()>> _playbackCleanupPtr;
  late final void Function() playbackCleanup;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Int32 Function(ffi.Int32, ffi.Int32)>> _playbackStartPtr;
  late final int Function(int, int) playbackStart;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function()>> _playbackStopPtr;
  late final void Function() playbackStop;


  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Int32)>> _playbackSetBpmPtr;
  late final void Function(int) playbackSetBpm;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Int32, ffi.Int32)>> _playbackSetRegionPtr;
  late final void Function(int, int) playbackSetRegion;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Int32)>> _playbackSetModePtr;
  late final void Function(int) playbackSetMode;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Pointer<NativePlaybackState> Function()>> _playbackGetStatePtr;
  late final ffi.Pointer<NativePlaybackState> Function() playbackGetStatePtr;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Int32, ffi.Int32)>> _playbackSetSectionLoopsNumPtr;
  late final void Function(int, int) playbackSetSectionLoopsNum;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Int32)>> _switchToSectionPtr;
  late final void Function(int) switchToSection;
  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Int32)>>
      _switchToSectionImmediatePtr;
  late final void Function(int) switchToSectionImmediate;
  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Int32)>>
      _switchToSectionSeamlessSongModePtr;
  late final void Function(int) switchToSectionSeamlessSongMode;

  // Master volume
  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Float)>> _playbackSetMasterVolumePtr;
  late final void Function(double) playbackSetMasterVolume;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Float)>> _playbackSetMasterReverbPtr;
  late final void Function(double) playbackSetMasterReverb;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Int32, ffi.Int32)>> _playbackSetMasterEqBandPtr;
  late final void Function(int, int) playbackSetMasterEqBand;
  late final ffi.Pointer<
      ffi.NativeFunction<
          ffi.Void Function(
              ffi.Int32, ffi.Int32, ffi.Float, ffi.Float, ffi.Float)>>
      _playbackSetSectionLayerReverbPtr;
  late final void Function(int, int, double, double, double)
      playbackSetSectionLayerReverb;
  late final ffi.Pointer<
      ffi.NativeFunction<ffi.Float Function(ffi.Int32, ffi.Int32)>>
      _playbackGetSectionLayerReverbSendPtr;
  late final double Function(int, int) playbackGetSectionLayerReverbSend;
  late final ffi.Pointer<
      ffi.NativeFunction<ffi.Float Function(ffi.Int32, ffi.Int32)>>
      _playbackGetSectionLayerReverbRoomPtr;
  late final double Function(int, int) playbackGetSectionLayerReverbRoom;
  late final ffi.Pointer<
      ffi.NativeFunction<ffi.Float Function(ffi.Int32, ffi.Int32)>>
      _playbackGetSectionLayerReverbDampPtr;
  late final double Function(int, int) playbackGetSectionLayerReverbDamp;

  late final ffi.Pointer<
          ffi.NativeFunction<
              ffi.Void Function(ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32)>>
      _playbackSetSectionLayerEqBandPtr;
  late final void Function(int, int, int, int) playbackSetSectionLayerEqBand;
  late final ffi.Pointer<
          ffi.NativeFunction<ffi.Int32 Function(ffi.Int32, ffi.Int32, ffi.Int32)>>
      _playbackGetSectionLayerEqBandDbPtr;
  late final int Function(int, int, int) playbackGetSectionLayerEqBandDb;

  late final ffi.Pointer<
          ffi.NativeFunction<
              ffi.Void Function(ffi.Int32, ffi.Int32, ffi.Float)>>
      _playbackSetSectionLayerVolumePtr;
  late final void Function(int, int, double) playbackSetSectionLayerVolume;
  late final ffi.Pointer<
          ffi.NativeFunction<ffi.Float Function(ffi.Int32, ffi.Int32)>>
      _playbackGetSectionLayerVolumePtr;
  late final double Function(int, int) playbackGetSectionLayerVolume;

  // Recording
  late final ffi.Pointer<ffi.NativeFunction<ffi.Int32 Function(ffi.Pointer<ffi.Char>)>> _recordingStartPtr;
  late final int Function(ffi.Pointer<ffi.Char>) recordingStart;
  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function()>> _recordingStopPtr;
  late final void Function() recordingStop;
  late final ffi.Pointer<ffi.NativeFunction<ffi.Int32 Function()>> _recordingIsActivePtr;
  late final int Function() recordingIsActive;

  // Preview
  late final ffi.Pointer<ffi.NativeFunction<ffi.Int32 Function(ffi.Pointer<pkg_ffi.Utf8>, ffi.Float, ffi.Float)>> _previewSamplePathPtr;
  late final int Function(ffi.Pointer<pkg_ffi.Utf8>, double, double) previewSamplePath;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Int32 Function(ffi.Int32, ffi.Float, ffi.Float)>> _previewSlotPtr;
  late final int Function(int, double, double) previewSlot;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Int32 Function(ffi.Int32, ffi.Int32, ffi.Float, ffi.Float)>> _previewCellPtr;
  late final int Function(int, int, double, double) previewCell;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function()>> _previewStopSamplePtr;
  late final void Function() previewStopSample;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function()>> _previewStopCellPtr;
  late final void Function() previewStopCell;

  // SunVox section sync
  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Int32)>> _sunvoxSyncSectionPtr;
  late final void Function(int) sunvoxSyncSection;

  // SunVox reset all patterns
  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function()>> _sunvoxResetAllPatternsPtr;
  late final void Function() sunvoxResetAllPatterns;

  // SunVox update timeline seamlessly
  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Int32)>> _sunvoxUpdateTimelineSeamlessPtr;
  late final void Function(int) sunvoxUpdateTimelineSeamless;

  // Enhanced playback logging
  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Int32)>> _playbackSetEnhancedLoggingPtr;
  late final void Function(int) playbackSetEnhancedLogging;

  // NOTE: sv_audio_callback2 bypass and Input module ID declarations removed
  // Mic recording now bypasses SunVox entirely

  // SunVox waveform scope
  late final ffi.Pointer<ffi.NativeFunction<ffi.Uint32 Function(ffi.Int32, ffi.Int32, ffi.Int32, ffi.Pointer<ffi.Int16>, ffi.Uint32)>> _svGetModuleScope2Ptr;
  late final int Function(int, int, int, ffi.Pointer<ffi.Int16>, int) svGetModuleScope2;

  // Get waveform samples from WAV file
  late final ffi.Pointer<ffi.NativeFunction<ffi.Int32 Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Int16>, ffi.Int32, ffi.Int32)>> _getWaveformSamplesPtr;
  late final int Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Int16>, int, int) getWaveformSamples;

  // Set pattern event with offset
  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function(
    ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32
  )>> _setPatternEventWithOffsetPtr;
  late final void Function(int, int, int, int, int, int, int) setPatternEventWithOffset;
}


