import 'package:flutter/foundation.dart';
import 'dart:ffi' as ffi;
import '../../ffi/playback_bindings.dart';
import 'table.dart';
import 'sync_profiling_helpers.dart';

/// Flutter state management for native sequencer playback
///
/// This file maintains references to native playback state and provides
/// controls for starting/stopping sequencer, setting BPM, and managing
/// song/loop modes with playback regions.
///
/// ## How to Add a New Property
///
/// To add a new property that syncs from native to Flutter state:
///
/// 1. **Add private field to PlaybackState:**
///    ```dart
///    int _myNewProperty = 0;
///    ```
///
/// 2. **Add ValueNotifier for UI binding:**
///    ```dart
///    final ValueNotifier<int> myNewPropertyNotifier = ValueNotifier<int>(0);
///    ```
///
/// 3. **Add field to _NativePlaybackState:**
///    ```dart
///    class _NativePlaybackState {
///      // ... existing fields
///      final int myNewProperty;
///
///      const _NativePlaybackState({
///        // ... existing parameters
///        required this.myNewProperty,
///      });
///    }
///    ```
///
/// 4. **Update syncPlaybackState() to read native value:**
///    ```dart
///    nativePlaybackState = _NativePlaybackState(
///      // ... existing fields
///      myNewProperty: ptr.ref.my_new_property,
///    );
///    ```
///
/// 5. **Add comparison in _updateStateFromNative():**
///    ```dart
///    if (_myNewProperty != nativePlaybackState.myNewProperty) {
///      _myNewProperty = nativePlaybackState.myNewProperty;
///      myNewPropertyNotifier.value = nativePlaybackState.myNewProperty;
///      anyChanged = true;
///    }
///    ```
///
/// 6. **Add getter (optional):**
///    ```dart
///    int get myNewProperty => _myNewProperty;
///    ```
///
/// 7. **Dispose the ValueNotifier:**
///    ```dart
///    myNewPropertyNotifier.dispose();
///    ```
///

/// Simple data class to hold native state snapshot
class _NativePlaybackState {
  final bool isPlaying;
  final int currentStep;
  final int bpm;
  final int regionStart;
  final int regionEnd;
  final bool songMode;
  final int currentSection;
  final int currentSectionLoop;
  final ffi.Pointer<ffi.Int32> sectionsLoopsNum;

  const _NativePlaybackState({
    required this.isPlaying,
    required this.currentStep,
    required this.bpm,
    required this.regionStart,
    required this.regionEnd,
    required this.songMode,
    required this.currentSection,
    required this.currentSectionLoop,
    required this.sectionsLoopsNum,
  });
}

class PlaybackState extends ChangeNotifier {
  static const int minLoopsPerSection = 1;
  static const int maxLoopsPerSection = 1024;

  final PlaybackBindings _playback_ffi;
  final TableState _tableState;

  // Auto-save callback (set by ThreadsState)
  void Function()? _onStateChanged;

  // Private state fields
  int _bpm = 120;
  double _masterVolume = 1.0; // 0.0..1.0
  int _currentStep = 0;
  bool _isPlaying = false;
  bool _songMode = false;
  int _currentSection = 0;
  int _currentSectionLoop = 0;
  int _currentSectionLoopsNum = 4;
  bool _initialized = false;
  int _lastSyncedVersion = -1;
  final SyncProfiler _syncProfiler =
      SyncProfiler(profileLabel: 'PLAYBACK_PROFILE');

  // Developer settings (UI-only, not synced from native)
  bool _enhancedPlaybackLogging = false;

  // ValueNotifiers for UI binding
  final ValueNotifier<int> currentStepNotifier = ValueNotifier<int>(0);
  final ValueNotifier<bool> isPlayingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<int> bpmNotifier = ValueNotifier<int>(120);
  final ValueNotifier<double> masterVolumeNotifier = ValueNotifier<double>(1.0);
  final ValueNotifier<bool> songModeNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<int> regionStartNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> regionEndNotifier = ValueNotifier<int>(16);
  final ValueNotifier<int> currentSectionNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> currentSectionLoopNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> currentSectionLoopsNumNotifier =
      ValueNotifier<int>(4);

  // UI-only state (not synced from native)
  // Slot playing moved to TableState
  // Panel mode moved to MultitaskPanelState

  PlaybackState(this._tableState) : _playback_ffi = PlaybackBindings() {
    _initializePlayback();
  }

  void _initializePlayback() {
    debugPrint('🎵 [PLAYBACK_STATE] Initializing native playback system');

    final result = _playback_ffi.playbackInit();
    if (result == 0) {
      _initialized = true;
      debugPrint('✅ [PLAYBACK_STATE] Playback system initialized');
      // Apply initial master volume to native engine
      try {
        _playback_ffi.playbackSetMasterVolume(_masterVolume);
      } catch (_) {}
    } else {
      debugPrint(
          '❌ [PLAYBACK_STATE] Failed to initialize playback system: $result');
    }
  }

  /// Start sequencer playback
  void start() {
    if (!_initialized) {
      debugPrint('❌ [PLAYBACK_STATE] Cannot start - not initialized');
      return;
    }

    final int sectionToStart =
        _isPlaying ? _currentSection : _tableState.uiSelectedSection;
    _playback_ffi.switchToSection(sectionToStart);
    final firstStep = _tableState.getSectionStartStep(sectionToStart);

    final result = _playback_ffi.playbackStart(_bpm, firstStep);
    if (result == 0) {
      debugPrint(
          '▶️ [PLAYBACK_STATE] Started playback (BPM: $_bpm, start step: $firstStep)');
    } else {
      debugPrint('❌ [PLAYBACK_STATE] Failed to start playback: $result');
    }
  }

  /// Stop sequencer playback
  void stop() {
    if (!_initialized) return;
    _playback_ffi.playbackStop();
    debugPrint('⏹️ [PLAYBACK_STATE] Stopped playback');
  }

  void togglePlayback() {
    if (_isPlaying) {
      stop();
    } else {
      start();
    }
  }

  void setBpm(int bpm) {
    if (bpm >= 60 && bpm <= 300) {
      if (_initialized) {
        _playback_ffi.playbackSetBpm(bpm);
      }
      debugPrint('🎵 [PLAYBACK_STATE] Set BPM to $bpm');
    } else {
      debugPrint('❌ [PLAYBACK_STATE] Invalid BPM: $bpm (must be 60-300)');
    }
  }

  // Master volume 0.0..1.0
  void setMasterVolume(double volume01) {
    final v = volume01.clamp(0.0, 1.0);
    _masterVolume = v;
    masterVolumeNotifier.value = v;
    if (_initialized) {
      _playback_ffi.playbackSetMasterVolume(v);
    }
  }

  // NOTE: sv_audio_callback2 bypass methods removed - mic bypasses SunVox entirely now

  // ===== Live preview helpers (UI wires these with debounce) =====
  void previewSampleSlot(int slot,
      {required double pitchRatio, required double volume01}) {
    if (!_initialized) return;
    // vol==0 => stop preview; otherwise start/restart
    if (volume01 <= 0.0) {
      _playback_ffi.previewStopSample();
      return;
    }
    _playback_ffi.previewSlot(slot, pitchRatio, volume01);
  }

  void previewCell(
      {required int step,
      required int colAbs,
      required double pitchRatio,
      required double volume01}) {
    if (!_initialized) return;
    if (volume01 <= 0.0) {
      _playback_ffi.previewStopCell();
      return;
    }
    _playback_ffi.previewCell(step, colAbs, pitchRatio, volume01);
  }

  void stopPreview() {
    if (!_initialized) return;
    _playback_ffi.previewStopSample();
    _playback_ffi.previewStopCell();
  }

  void setSongMode(bool songMode) {
    // Delegate to native; UI will update via syncPlaybackState()
    if (_initialized) {
      _playback_ffi.playbackSetMode(songMode ? 1 : 0);
    }
    debugPrint('🎭 [PLAYBACK_STATE] Set mode to ${songMode ? "song" : "loop"}');
  }

  /// Set section loop cunt
  void setSectionLoopsNum(int section, int loops) {
    if (loops >= minLoopsPerSection && loops <= maxLoopsPerSection) {
      if (_initialized) {
        _playback_ffi.playbackSetSectionLoopsNum(section, loops);
      }
      debugPrint('🔁 [PLAYBACK_STATE] Set section $section loops to $loops');
    } else {
      debugPrint(
          '❌ [PLAYBACK_STATE] Invalid loop count: $loops (must be $minLoopsPerSection-$maxLoopsPerSection)');
    }
  }

  void switchToSection(int targetIndex) {
    if (!_initialized) return;
    if (targetIndex < 0) targetIndex = 0;
    _playback_ffi.switchToSection(targetIndex);
    debugPrint('🎯 [PLAYBACK_STATE] switchToSection → $targetIndex');
  }

  void switchToPreviousSection() {
    final prev = _currentSection - 1;
    if (prev < 0) return;
    switchToSection(prev);
    debugPrint('🎯 [PLAYBACK_STATE] switchToSection → $prev');
  }

  void switchToNextSection() {
    final next = _currentSection + 1;
    if (next >= _tableState.sectionsCount) return;
    switchToSection(next);
  }

  // Get loops count for a specific section (reads native pointer directly)
  int getSectionLoopsNum(int sectionIndex) {
    try {
      final ptr = _playback_ffi.playbackGetStatePtr();
      if (ptr.address == 0) return _currentSectionLoopsNum;
      if (sectionIndex < 0) return _currentSectionLoopsNum;
      return ptr.ref.sections_loops_num.elementAt(sectionIndex).value;
    } catch (_) {
      return _currentSectionLoopsNum;
    }
  }

  /// Get pointer to native playback state (for snapshot export)
  ffi.Pointer<NativePlaybackState> getPlaybackStatePtr() {
    return _playback_ffi.playbackGetStatePtr();
  }

  /// Sync current state from native (called by timer)
  void syncPlaybackState() {
    if (!_initialized) return;

    final ffi.Pointer<NativePlaybackState> ptr =
        _playback_ffi.playbackGetStatePtr();
    if (ptr.address == 0) return;
    final int initialVersion = ptr.ref.version;
    if ((initialVersion & 1) == 0 && initialVersion == _lastSyncedVersion) {
      return;
    }

    final syncWatch = Stopwatch()..start();
    int tries = 0;
    const maxTries = 3;
    late final _NativePlaybackState nativePlaybackState;
    int stableVersion = initialVersion;

    // Seqlock pattern: read with version check for consistency
    while (true) {
      final v1 = ptr.ref.version;
      if ((v1 & 1) != 0) {
        // writer in progress
        if (++tries >= maxTries) return; // skip this frame
        continue;
      }
      nativePlaybackState = _NativePlaybackState(
        isPlaying: ptr.ref.is_playing != 0,
        currentStep: ptr.ref.current_step,
        bpm: ptr.ref.bpm,
        regionStart: ptr.ref.region_start,
        regionEnd: ptr.ref.region_end,
        songMode: ptr.ref.song_mode != 0,
        currentSection: ptr.ref.current_section,
        currentSectionLoop: ptr.ref.current_section_loop,
        sectionsLoopsNum: ptr.ref.sections_loops_num,
      );
      final v2 = ptr.ref.version;
      if (v1 == v2) {
        stableVersion = v2;
        break;
      }
      if (++tries >= maxTries) return;
    }

    _lastSyncedVersion = stableVersion;
    _updateStateFromNative(nativePlaybackState);

    syncWatch.stop();
    _syncProfiler.recordCall(elapsedMicros: syncWatch.elapsedMicroseconds);
  }

  /// Update local state and notifiers when native state changes
  void _updateStateFromNative(_NativePlaybackState nativePlaybackState) {
    bool anyChanged = false;

    // Check and update each property
    if (_currentStep != nativePlaybackState.currentStep) {
      _currentStep = nativePlaybackState.currentStep;
      currentStepNotifier.value = nativePlaybackState.currentStep;
      anyChanged = true;
    }

    if (_isPlaying != nativePlaybackState.isPlaying) {
      _isPlaying = nativePlaybackState.isPlaying;
      isPlayingNotifier.value = nativePlaybackState.isPlaying;
      anyChanged = true;
    }

    if (_bpm != nativePlaybackState.bpm) {
      _bpm = nativePlaybackState.bpm;
      bpmNotifier.value = nativePlaybackState.bpm;
      anyChanged = true;
    }

    if (_songMode != nativePlaybackState.songMode) {
      _songMode = nativePlaybackState.songMode;
      songModeNotifier.value = nativePlaybackState.songMode;
      anyChanged = true;
    }

    if (regionStartNotifier.value != nativePlaybackState.regionStart) {
      regionStartNotifier.value = nativePlaybackState.regionStart;
      anyChanged = true;
    }

    if (regionEndNotifier.value != nativePlaybackState.regionEnd) {
      regionEndNotifier.value = nativePlaybackState.regionEnd;
      anyChanged = true;
    }

    if (_currentSection != nativePlaybackState.currentSection) {
      _currentSection = nativePlaybackState.currentSection;
      currentSectionNotifier.value = nativePlaybackState.currentSection;
      anyChanged = true;
      if (_songMode && _isPlaying) {
        _tableState.setUiSelectedSection(_currentSection);
      }
    }

    if (_currentSectionLoop != nativePlaybackState.currentSectionLoop) {
      debugPrint(
          '🔄 [LOOP_COUNTER_DEBUG] Flutter: $_currentSectionLoop → ${nativePlaybackState.currentSectionLoop} (songMode=$_songMode)');
      _currentSectionLoop = nativePlaybackState.currentSectionLoop;
      currentSectionLoopNotifier.value = nativePlaybackState.currentSectionLoop;
      anyChanged = true;
    }

    final currentSectionLoopsNum = nativePlaybackState.sectionsLoopsNum
        .elementAt(nativePlaybackState.currentSection)
        .value;
    if (_currentSectionLoopsNum != currentSectionLoopsNum) {
      _currentSectionLoopsNum = currentSectionLoopsNum;
      currentSectionLoopsNumNotifier.value = currentSectionLoopsNum;
      anyChanged = true;
    }

    // Only notify listeners once if any changes occurred
    if (anyChanged) {
      notifyListeners();
    }
  }

  // Getters
  int get bpm => _bpm;
  int get currentStep => _currentStep;
  bool get isPlaying => _isPlaying;
  bool get songMode => _songMode;
  int get currentSection => _currentSection;
  int get currentSectionLoop => _currentSectionLoop;
  int get currentSectionLoopsNum => _currentSectionLoopsNum;
  bool get initialized => _initialized;
  bool get enhancedPlaybackLogging => _enhancedPlaybackLogging;

  /// Get loops count for all sections as a list (length = sectionsCount)
  List<int> getSectionsLoopsNum() {
    final List<int> result = [];
    try {
      final ptr = _playback_ffi.playbackGetStatePtr();
      if (ptr.address == 0) return result;
      final count = _tableState.sectionsCount;
      for (int i = 0; i < count; i++) {
        result.add(ptr.ref.sections_loops_num.elementAt(i).value);
      }
    } catch (_) {}
    return result;
  }

  /// Set enhanced playback logging (for debugging)
  void setEnhancedPlaybackLogging(bool enabled) {
    if (_enhancedPlaybackLogging == enabled) return;
    _enhancedPlaybackLogging = enabled;

    if (_initialized) {
      try {
        _playback_ffi.playbackSetEnhancedLogging(enabled ? 1 : 0);
        debugPrint(
            '🐛 [PLAYBACK_STATE] Enhanced playback logging ${enabled ? "enabled" : "disabled"}');
      } catch (e) {
        debugPrint('⚠️ [PLAYBACK_STATE] Failed to set enhanced logging: $e');
      }
    }

    notifyListeners();
  }

  /// Set callback for state changes (used by ThreadsState for auto-save)
  void setOnStateChanged(void Function()? callback) {
    _onStateChanged = callback;
  }

  @override
  void notifyListeners() {
    super.notifyListeners();

    // Trigger auto-save if callback is set
    _onStateChanged?.call();
  }

  @override
  void dispose() {
    debugPrint('🧹 [PLAYBACK_STATE] Disposing playback state');

    if (_initialized) {
      stop();
      _playback_ffi.playbackCleanup();
    }

    // Dispose all ValueNotifiers
    currentStepNotifier.dispose();
    isPlayingNotifier.dispose();
    bpmNotifier.dispose();
    songModeNotifier.dispose();
    regionStartNotifier.dispose();
    regionEndNotifier.dispose();
    currentSectionNotifier.dispose();
    currentSectionLoopNotifier.dispose();
    currentSectionLoopsNumNotifier.dispose();
    masterVolumeNotifier.dispose();

    super.dispose();
  }
}
