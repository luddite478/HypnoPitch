import '../../utils/log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:path_provider/path_provider.dart';
import '../../ffi/sample_bank_bindings.dart';
import '../../utils/app_colors.dart';
import 'ui_selection.dart';
import 'sync_profiling_helpers.dart';

/// Simple data class to hold native sample bank state snapshot
class _NativeSampleBankState {
  final int maxSlots;
  final int loadedCount;
  final ffi.Pointer<Sample> samplesPtr;

  const _NativeSampleBankState({
    required this.maxSlots,
    required this.loadedCount,
    required this.samplesPtr,
  });
}

/// Flutter state management for native sample bank
///
/// This follows the same pattern as playback.dart with authoritative native state
/// and seqlock-based synchronization. Native holds all sample loading state,
/// Flutter only maintains UI helpers and ValueNotifiers for reactive updates.
class SampleBankState extends ChangeNotifier {
  static const int maxSampleSlots = 26; // A-Z (0-25)
  static const int _lastDedicatedUserSlot =
      24; // Keep Z(25) for preview/recording paths

  final SampleBankBindings _sample_bank_ffi;

  // Auto-save callback (set by ThreadsState)
  void Function()? _onStateChanged;

  // Private state fields (synced from native)
  int _maxSlots = 26;
  int _loadedCount = 0;
  ffi.Pointer<Sample> _samplesPtr = ffi.nullptr;
  final List<bool> _slotsLoaded = List.filled(maxSampleSlots, false);
  // Per-sample notifiers for UI bindings
  final Map<int, ValueNotifier<double>> _sampleVolumeNotifiers = {};
  final Map<int, ValueNotifier<double>> _samplePitchNotifiers = {};
  final Map<int, ValueNotifier<bool>> _sampleProcessingNotifiers = {};

  // UI-only state (not synced from native)
  final List<String?> _slotNames = List.filled(maxSampleSlots, null);
  final List<String?> _slotPaths = List.filled(maxSampleSlots, null);
  final List<Color?> _sampleColors =
      List.filled(maxSampleSlots, null); // Project-specific colors
  // Sample offsets (in frames at 48kHz) - managed by Flutter, synced to native via pattern updates
  final List<int> _sampleOffsets = List.filled(maxSampleSlots, 0);
  int _activeSlot = 0;
  int _lastSyncedVersion = -1;
  final SyncProfiler _syncProfiler =
      SyncProfiler(profileLabel: 'SAMPLE_BANK_PROFILE');

  // ValueNotifiers for UI binding
  final ValueNotifier<int> loadedCountNotifier = ValueNotifier<int>(0);
  final ValueNotifier<List<bool>> slotsLoadedNotifier =
      ValueNotifier<List<bool>>(List.filled(maxSampleSlots, false));
  final ValueNotifier<int> activeSlotNotifier = ValueNotifier<int>(0);

  final UiSelectionState? _uiSelection; // optional injection

  SampleBankState({UiSelectionState? uiSelection})
      : _sample_bank_ffi = SampleBankBindings(),
        _uiSelection = uiSelection {
    _initializeSampleBank();
  }

  void _initializeSampleBank() {
    Log.d('🏗️ [SAMPLE_BANK_STATE] Initializing sample bank state');

    // Ensure native sample bank is initialized/reset
    _sample_bank_ffi.sampleBankInit();

    // Sync initial state from native
    syncSampleBankState();

    Log.d('✅ [SAMPLE_BANK_STATE] Sample bank state initialized');
  }

  /// Load sample into a slot by manifest ID (required).
  Future<bool> loadSample(int slot, String sampleId) async {
    return _loadSampleByManifestId(slot, sampleId);
  }

  /// Load recorded audio from file path (not asset)
  ///
  /// This method loads audio files directly from the filesystem (e.g., recorded WAV files)
  /// rather than from Flutter assets. Used for loading microphone recordings into samples.
  Future<bool> loadRecordedAudio(int slot, String filePath,
      {String? displayName}) async {
    if (slot < 0 || slot >= maxSampleSlots) {
      Log.d('❌ [SAMPLE_BANK_STATE] Invalid slot: $slot');
      return false;
    }

    try {
      Log.d(
          '🎙️ [SAMPLE_BANK_STATE] Loading recorded audio into slot $slot: $filePath');

      // Check if file exists
      final file = File(filePath);
      if (!await file.exists()) {
        Log.d('❌ [SAMPLE_BANK_STATE] File does not exist: $filePath');
        return false;
      }

      // Convert file path to native C string
      final pathBytes = utf8.encode(filePath);
      final pathPtr = calloc<ffi.Char>(pathBytes.length + 1);
      for (int i = 0; i < pathBytes.length; i++) {
        pathPtr[i] = pathBytes[i];
      }
      pathPtr[pathBytes.length] = 0;

      // Use special ID for recorded audio with timestamp
      final sampleId = 'recording_${DateTime.now().millisecondsSinceEpoch}';
      final idBytes = utf8.encode(sampleId);
      final idPtr = calloc<ffi.Char>(idBytes.length + 1);
      for (int i = 0; i < idBytes.length; i++) {
        idPtr[i] = idBytes[i];
      }
      idPtr[idBytes.length] = 0;

      final result =
          _sample_bank_ffi.sampleBankLoadWithId(slot, pathPtr, idPtr);

      calloc.free(pathPtr);
      calloc.free(idPtr);

      if (result == 0) {
        _slotNames[slot] = displayName ?? 'Recorded Audio';
        _slotPaths[slot] = filePath;
        _sampleColors[slot] = const Color(0xFFE57373); // Red for recordings

        Log.d('✅ [SAMPLE_BANK_STATE] Loaded recorded audio into slot $slot');
        syncSampleBankState();
        notifyListeners();
        return true;
      } else {
        Log.d('❌ [SAMPLE_BANK_STATE] Failed to load recorded audio: $result');
        return false;
      }
    } catch (e) {
      Log.d('❌ [SAMPLE_BANK_STATE] Error loading recorded audio: $e');
      return false;
    }
  }

  /// Load sample from asset path into slot with a stable sampleId (internal)
  Future<bool> _loadSampleWithId(
      int slot, String assetPath, String sampleId) async {
    if (slot < 0 || slot >= maxSampleSlots) {
      Log.d('❌ [SAMPLE_BANK_STATE] Invalid slot: $slot');
      return false;
    }
    try {
      Log.d(
          '📂 [SAMPLE_BANK_STATE] Loading sample with id into slot $slot: $assetPath (id=$sampleId)');

      final tempFilePath = await _copyAssetToTempFile(assetPath);
      if (tempFilePath == null) {
        Log.d(
            '❌ [SAMPLE_BANK_STATE] Failed to copy asset to temp file: $assetPath');
        return false;
      }

      // Convert file path to native C string
      final pathBytes = utf8.encode(tempFilePath);
      final pathPtr = calloc<ffi.Char>(pathBytes.length + 1);
      for (int i = 0; i < pathBytes.length; i++) {
        pathPtr[i] = pathBytes[i];
      }
      pathPtr[pathBytes.length] = 0;

      // Convert id to native C string
      final idBytes = utf8.encode(sampleId);
      final idPtr = calloc<ffi.Char>(idBytes.length + 1);
      for (int i = 0; i < idBytes.length; i++) {
        idPtr[i] = idBytes[i];
      }
      idPtr[idBytes.length] = 0;

      final result =
          _sample_bank_ffi.sampleBankLoadWithId(slot, pathPtr, idPtr);

      calloc.free(pathPtr);
      calloc.free(idPtr);

      if (result == 0) {
        _slotNames[slot] = assetPath.split('/').last;
        _slotPaths[slot] = assetPath;

        // Assign color from default palette if not already set (preserve project colors on import)
        if (_sampleColors[slot] == null) {
          final color = _defaultBankColors[slot % _defaultBankColors.length];
          _sampleColors[slot] = color;
          Log.d('🎨 [SAMPLE_BANK_STATE] Assigned color to slot $slot');
        }

        Log.d(
            '✅ [SAMPLE_BANK_STATE] Loaded sample $slot with id: ${_slotNames[slot]}');
        return true;
      } else {
        Log.d(
            '❌ [SAMPLE_BANK_STATE] Failed to load sample with id $slot: $result');
        return false;
      }
    } catch (e) {
      Log.d('❌ [SAMPLE_BANK_STATE] Error loading sample with id $slot: $e');
      return false;
    }
  }

  /// Load sample by manifest id using samples_manifest.json (internal)
  Future<bool> _loadSampleByManifestId(int slot, String sampleId) async {
    try {
      final manifestString =
          await rootBundle.loadString('samples_manifest.json');
      final fullManifest = json.decode(manifestString);
      if (fullManifest is Map && fullManifest.containsKey('samples')) {
        final samplesMap = fullManifest['samples'] as Map<String, dynamic>;
        final entry = samplesMap[sampleId];
        if (entry is Map && entry['path'] is String) {
          final assetPath = entry['path'] as String;
          return await _loadSampleWithId(slot, assetPath, sampleId);
        } else {
          Log.d(
              '❌ [SAMPLE_BANK_STATE] Manifest id not found or invalid: $sampleId');
          return false;
        }
      } else {
        Log.d('❌ [SAMPLE_BANK_STATE] Invalid manifest structure');
        return false;
      }
    } catch (e) {
      Log.d('❌ [SAMPLE_BANK_STATE] Failed to load manifest: $e');
      return false;
    }
  }

  /// Copy Flutter asset to temporary file for native access
  Future<String?> _copyAssetToTempFile(String assetPath) async {
    try {
      // Load asset as bytes
      final ByteData data = await rootBundle.load(assetPath);
      final Uint8List bytes = data.buffer.asUint8List();

      // Get temporary directory
      final Directory tempDir = await getTemporaryDirectory();

      // Create unique filename
      final String fileName = assetPath.split('/').last;
      final String tempPath = '${tempDir.path}/sample_$fileName';

      // Write bytes to temp file
      final File tempFile = File(tempPath);
      await tempFile.writeAsBytes(bytes);

      Log.d('📁 [SAMPLE_BANK_STATE] Copied asset to temp file: $tempPath');
      return tempPath;
    } catch (e) {
      Log.d('❌ [SAMPLE_BANK_STATE] Failed to copy asset: $e');
      return null;
    }
  }

  /// Unload sample from slot
  void unloadSample(int slot) {
    if (slot < 0 || slot >= maxSampleSlots) {
      Log.d('❌ [SAMPLE_BANK_STATE] Invalid slot: $slot');
      return;
    }

    _sample_bank_ffi.sampleBankUnload(slot);

    // Clear UI-only metadata
    _slotNames[slot] = null;
    _slotPaths[slot] = null;
    _sampleColors[slot] = null; // Clear color when unloading

    // Native state will be synced automatically by timer
    Log.d('🗑️ [SAMPLE_BANK_STATE] Unloaded sample $slot');
  }

  /// Set active slot for UI
  void setActiveSlot(int slot) {
    if (slot >= 0 && slot < maxSampleSlots) {
      _activeSlot = slot;
      activeSlotNotifier.value = slot;
      notifyListeners();
      Log.d('🎯 [SAMPLE_BANK_STATE] Set active slot to $slot');
      // If unified selection is available, mark sample bank as active selection
      _uiSelection?.selectSampleBank(slot);
    }
  }

  /// Get slot letter (A-Z)
  String getSlotLetter(int slot) {
    if (slot < 0 || slot >= maxSampleSlots) return '?';
    return String.fromCharCode(65 + slot); // A=65
  }

  /// Get slot index from letter
  int getSlotFromLetter(String letter) {
    if (letter.length != 1) return -1;
    final code = letter.toUpperCase().codeUnitAt(0);
    if (code >= 65 && code <= 90) {
      // A-Z
      return code - 65;
    }
    return -1;
  }

  // Direct sample access (like table system)
  ffi.Pointer<Sample> getSamplePointer(int slot) {
    return _sample_bank_ffi.sampleBankGetSample(slot);
  }

  /// Get pointer to native sample bank state (for snapshot export)
  ffi.Pointer<NativeSampleBankState> getSampleBankStatePtr() {
    return _sample_bank_ffi.sampleBankGetStatePtr();
  }

  /// Simple dedicated-slot resolver for grid-cell sample selection.
  /// Reuses a slot if the same sample id is already loaded, otherwise loads
  /// into the first free user slot (A-Y). Returns null when no slot is available.
  Future<int?> loadSampleForCell(String sampleId) async {
    // 1) Reuse already loaded sample id.
    for (int slot = 0; slot <= _lastDedicatedUserSlot; slot++) {
      if (!isSlotLoaded(slot)) continue;
      if (getSampleData(slot).id == sampleId) {
        return slot;
      }
    }

    // 2) Load into first empty user slot.
    for (int slot = 0; slot <= _lastDedicatedUserSlot; slot++) {
      if (isSlotLoaded(slot)) continue;
      final ok = await loadSample(slot, sampleId);
      return ok ? slot : null;
    }

    return null;
  }

  SampleData getSampleData(int slot) {
    final ptr = getSamplePointer(slot);
    if (ptr.address == 0) {
      return const SampleData(
          loaded: false, volume: 1.0, pitch: 1.0, isProcessing: false);
    }
    return SampleData.fromPointer(ptr);
  }

  void setSampleVolume(int slot, double volume) {
    _sample_bank_ffi.sampleBankSetSampleVolume(slot, volume);
    // Update notifier for reactive UI
    _sampleVolumeNotifiers[slot]?.value = volume;
  }

  void setSamplePitch(int slot, double pitch) {
    _sample_bank_ffi.sampleBankSetSamplePitch(slot, pitch);
    // Update notifier for reactive UI
    _samplePitchNotifiers[slot]?.value = pitch;
  }

  /// Update sample settings (volume, pitch) via a single call path
  void setSampleSettings(int slot, {double? volume, double? pitch}) {
    final v = (volume ?? getSampleData(slot).volume).clamp(0.0, 1.0);
    final p = (pitch ?? getSampleData(slot).pitch).clamp(0.25, 4.0);
    _sample_bank_ffi.sampleBankSetSampleSettings(slot, v, p);
    _sampleVolumeNotifiers[slot]?.value = v;
    _samplePitchNotifiers[slot]?.value = p;
    Log.d(
        '🎚️ [SAMPLE_BANK_STATE] Set sample settings slot=$slot vol=${volume?.toStringAsFixed(2)} pitch=${pitch?.toStringAsFixed(2)}');
  }

  /// Set offset for sample slot (in frames)
  void setSampleOffset(int slot, int offsetFrames) {
    if (slot >= 0 && slot < maxSampleSlots) {
      _sampleOffsets[slot] = offsetFrames.clamp(0, 16777215);

      // TODO: Resync all cells using this sample
      // This would require calling sunvox_wrapper_sync_cell for each cell
      // For now, offset changes will be reflected on next pattern sync

      notifyListeners();
      Log.d(
          '🎯 [SAMPLE_BANK_STATE] Set sample offset slot=$slot frames=$offsetFrames');
    }
  }

  /// Get offset for sample slot (in frames)
  int getSampleOffset(int slot) {
    if (slot >= 0 && slot < maxSampleSlots) {
      return _sampleOffsets[slot];
    }
    return 0;
  }

  // Getters (state comes from native, metadata from local)
  bool isSlotLoaded(int slot) {
    if (slot < 0 || slot >= maxSampleSlots) return false;
    return _slotsLoaded[slot];
  }

  String? getSlotName(int slot) {
    if (slot < 0 || slot >= maxSampleSlots) return null;
    return _slotNames[slot];
  }

  String? getSlotPath(int slot) {
    if (slot < 0 || slot >= maxSampleSlots) return null;
    return _slotPaths[slot];
  }

  int get activeSlot => _activeSlot;
  int get maxSlots => _maxSlots;
  int get loadedCount => _loadedCount;
  List<bool> get slotsLoaded => List.unmodifiable(_slotsLoaded);
  List<String?> get slotNames => List.unmodifiable(_slotNames);
  List<String?> get slotPaths => List.unmodifiable(_slotPaths);

  // Convenience getter that uses native count instead of recalculating
  int get loadedSampleCount => _loadedCount;

  // Per-sample notifiers (lazy)
  ValueNotifier<double> getSampleVolumeNotifier(int slot) {
    return _sampleVolumeNotifiers.putIfAbsent(slot, () {
      final data = getSampleData(slot);
      return ValueNotifier<double>(data.volume);
    });
  }

  ValueNotifier<double> getSamplePitchNotifier(int slot) {
    return _samplePitchNotifiers.putIfAbsent(slot, () {
      final data = getSampleData(slot);
      return ValueNotifier<double>(data.pitch);
    });
  }

  ValueNotifier<bool> getSampleProcessingNotifier(int slot) {
    return _sampleProcessingNotifiers.putIfAbsent(slot, () {
      final data = getSampleData(slot);
      return ValueNotifier<bool>(data.isProcessing);
    });
  }

  // UI-only helpers for V2 compatibility
  static const List<Color> _defaultBankColors = [
    Color(0xFFE57373), // Red
    Color(0xFFFFB74D), // Orange
    Color(0xFFFFF176), // Yellow
    Color(0xFFAED581), // Light Green
    Color(0xFF81C784), // Green
    Color(0xFF4DB6AC), // Teal
    Color(0xFF64B5F6), // Blue
    Color(0xFF9575CD), // Purple
    Color(0xFFBA68C8), // Pink
    Color(0xFFA1887F), // Brown
    Color(0xFF90A4AE), // Blue Grey
    Color(0xFFFFAB91), // Deep Orange
    Color(0xFFDCE775), // Lime
    Color(0xFF80CBC4), // Cyan
    Color(0xFF7986CB), // Indigo
    Color(0xFFB39DDB), // Deep Purple
  ];

  /// Get colors for all slots - uses project-specific colors or defaults
  List<Color> get uiBankColors {
    return List.generate(maxSampleSlots, (i) {
      return _sampleColors[i] ??
          _defaultBankColors[i % _defaultBankColors.length];
    });
  }

  /// Set color for a specific sample slot (project-specific)
  void setSampleColor(int slot, Color color) {
    if (slot >= 0 && slot < maxSampleSlots) {
      _sampleColors[slot] = color;
      notifyListeners();
    }
  }

  /// Get color for a specific sample slot (null if not set)
  Color? getSampleColor(int slot) {
    if (slot >= 0 && slot < maxSampleSlots) {
      return _sampleColors[slot];
    }
    return null;
  }

  /// Clear all sample colors (used when loading new project)
  void clearAllColors() {
    for (int i = 0; i < maxSampleSlots; i++) {
      _sampleColors[i] = null;
    }
    notifyListeners();
  }

  /// Assign random colors from the dark forest/berry palette to all sample slots
  ///
  /// This is called when creating a new project to give each project a unique
  /// color scheme. The 26 palette colors are shuffled randomly and assigned
  /// to slots A-Z, ensuring visual distinction between projects.
  void assignRandomProjectColors() {
    // Verify palette has exactly 26 unique colors
    assert(AppColors.sampleBankPalette.length == maxSampleSlots,
        'Palette must have exactly 26 colors for 26 sample slots');
    assert(AppColors.sampleBankPalette.toSet().length == maxSampleSlots,
        'All 26 palette colors must be unique (found ${AppColors.sampleBankPalette.toSet().length} unique colors)');

    // Create a copy of the palette and shuffle it
    final shuffledColors = List<Color>.from(AppColors.sampleBankPalette);
    shuffledColors.shuffle(math.Random());

    // Assign shuffled colors to all 26 slots (one-to-one mapping, no duplicates)
    for (int i = 0; i < maxSampleSlots; i++) {
      _sampleColors[i] = shuffledColors[i];
    }

    Log.d(
        '🎨 [SAMPLE_BANK_STATE] Assigned random project colors from dark forest palette');

    // Notify UI listeners
    notifyListeners();

    // Trigger auto-save if callback is set
    _onStateChanged?.call();
  }

  void uiHandleBankChange(int slot) {
    setActiveSlot(slot);
  }

  Future<void> uiPickFileForSlot(int slot) async {
    // Placeholder implementation - would open file picker in real implementation
    Log.d('🎵 [SAMPLE_BANK_STATE] Pick file for slot $slot (placeholder)');
  }

  /// Sync sample bank state from native using seqlock pattern (called by timer each frame)
  void syncSampleBankState() {
    final ffi.Pointer<NativeSampleBankState> ptr =
        _sample_bank_ffi.sampleBankGetStatePtr();
    if (ptr.address == 0) return;
    final int initialVersion = ptr.ref.version;
    if ((initialVersion & 1) == 0 && initialVersion == _lastSyncedVersion) {
      return;
    }

    final syncWatch = Stopwatch()..start();
    int tries = 0;
    const int maxTries = 3;
    late final _NativeSampleBankState nativeSampleBankState;
    int stableVersion = initialVersion;

    // Seqlock pattern: read with version check for consistency
    while (true) {
      final v1 = ptr.ref.version;
      if ((v1 & 1) != 0) {
        // writer in progress
        if (++tries >= maxTries) return; // skip this frame
        continue;
      }
      nativeSampleBankState = _NativeSampleBankState(
        maxSlots: ptr.ref.max_slots,
        loadedCount: ptr.ref.loaded_count,
        samplesPtr: ptr.ref.samples_ptr,
      );
      final v2 = ptr.ref.version;
      if (v1 == v2) {
        stableVersion = v2;
        break;
      }
      if (++tries >= maxTries) return;
    }

    _lastSyncedVersion = stableVersion;
    _updateStateFromNative(nativeSampleBankState);

    syncWatch.stop();
    _syncProfiler.recordCall(elapsedMicros: syncWatch.elapsedMicroseconds);
  }

  /// Update local state when native state changes
  void _updateStateFromNative(_NativeSampleBankState nativeSampleBankState) {
    bool anyChanged = false;

    // Check and update each property
    if (_maxSlots != nativeSampleBankState.maxSlots) {
      _maxSlots = nativeSampleBankState.maxSlots;
      anyChanged = true;
    }

    if (_loadedCount != nativeSampleBankState.loadedCount) {
      _loadedCount = nativeSampleBankState.loadedCount;
      loadedCountNotifier.value = nativeSampleBankState.loadedCount;
      anyChanged = true;
    }

    if (_samplesPtr != nativeSampleBankState.samplesPtr) {
      _samplesPtr = nativeSampleBankState.samplesPtr;
      anyChanged = true;
    }

    // Update slots from samples array directly
    bool slotsChanged = false;
    if (_samplesPtr.address != 0) {
      for (int i = 0; i < maxSampleSlots; i++) {
        final samplePtr = _samplesPtr + i;
        final bool isLoaded = samplePtr.ref.loaded != 0;
        final bool isProcessing = samplePtr.ref.is_processing != 0;
        if (_slotsLoaded[i] != isLoaded) {
          _slotsLoaded[i] = isLoaded;
          slotsChanged = true;
          anyChanged = true;
        }
        if (slotsChanged ||
            isProcessing ||
            _slotNames[i] == null ||
            _slotPaths[i] == null) {
          final sampleData = SampleData.fromPointer(samplePtr);
          _slotNames[i] = sampleData.displayName;
          _slotPaths[i] = sampleData.filePath;
        }

        // Update processing notifier if exists
        final n = _sampleProcessingNotifiers[i];
        if (n != null && n.value != isProcessing) {
          n.value = isProcessing;
        }
      }
    }

    if (slotsChanged) {
      slotsLoadedNotifier.value = List.from(_slotsLoaded);
    }

    // Only notify listeners once if any changes occurred
    if (anyChanged) {
      notifyListeners();
    }
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
    Log.d('🧹 [SAMPLE_BANK_STATE] Disposing sample bank state');

    // Dispose ValueNotifiers
    loadedCountNotifier.dispose();
    slotsLoadedNotifier.dispose();
    activeSlotNotifier.dispose();
    for (final n in _sampleVolumeNotifiers.values) {
      n.dispose();
    }
    for (final n in _samplePitchNotifiers.values) {
      n.dispose();
    }

    super.dispose();
  }
}
