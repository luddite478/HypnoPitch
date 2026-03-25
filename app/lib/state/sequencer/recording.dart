import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';
import '../../ffi/playback_bindings.dart';
import '../../conversion_library.dart';
import 'dart:io';
import 'package:path/path.dart' as path;

/// State management for recording functionality
/// Handles audio recording controls and status
class RecordingState extends ChangeNotifier {
  static const int _dedicatedRecordingLayerFallback = 4; // 5th layer (0-indexed)
  final PlaybackBindings _playback = PlaybackBindings();
  final ConversionLibrary _conversion = ConversionLibrary();
  
  // Callback for when recording is complete and should be saved as message
  Future<void> Function()? _onRecordingComplete;

  bool _isRecording = false;
  String? _currentRecordingPath;
  DateTime? _recordingStartTime;
  Timer? _durationTimer;
  Duration _recordingDuration = Duration.zero;
  final List<String> _localRecordings = [];
  
  // Conversion state
  bool _isConverting = false;
  String? _conversionError;
  String? _convertedMp3Path;
  Future<String?>? _activeMp3Conversion;
  int _takeVersion = 0;
  bool _isPreviewing = false;
  Timer? _previewTimer;
  
  // Upload state
  bool _isUploading = false;
  String? _uploadedRenderUrl;
  String? _uploadError;
  
  // Offset tracking (in frames at 48kHz)
  int _recordingOffsetFrames = 0;
  
  // Track which section and layer the recording was made on
  int? _recordingSection;
  int _recordingLayer = 0;  // Track (column) where recording should be placed
  
  // Armed state - recording waits for loop boundary before starting
  // This allows recording to be aligned to the start of a loop
  bool _isArmed = false;
  int? _armedSection;       // Section when armed (to detect section change)
  int? _armedSectionLoop;   // Loop index when armed (to detect loop boundary)
  
  // Dependencies for sample loading (will be set by UI)
  // ignore: unused_field
  dynamic _playbackState;
  // ignore: unused_field
  dynamic _tableState;
  // ignore: unused_field
  dynamic _sampleBankState;
  
  // Value notifiers for UI binding
  final ValueNotifier<bool> isRecordingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isArmedNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<Duration> recordingDurationNotifier = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<String?> recordingPathNotifier = ValueNotifier<String?>(null);
  final ValueNotifier<List<String>> recordingsNotifier = ValueNotifier<List<String>>(<String>[]);
  final ValueNotifier<bool> isConvertingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<String?> conversionErrorNotifier = ValueNotifier<String?>(null);
  final ValueNotifier<String?> convertedMp3PathNotifier = ValueNotifier<String?>(null);
  
  // Getters
  bool get isRecording => _isRecording;
  bool get isArmed => _isArmed;
  String? get currentRecordingPath => _currentRecordingPath;
  DateTime? get recordingStartTime => _recordingStartTime;
  Duration get recordingDuration => _recordingDuration;
  List<String> get localRecordings => List.unmodifiable(_localRecordings);
  bool get isConverting => _isConverting;
  String? get conversionError => _conversionError;
  String? get convertedMp3Path => _convertedMp3Path;
  bool get isPreviewing => _isPreviewing;
  bool get isUploading => _isUploading;
  String? get uploadedRenderUrl => _uploadedRenderUrl;
  String? get uploadError => _uploadError;

  String get formattedDuration {
    final minutes = _recordingDuration.inMinutes;
    final seconds = _recordingDuration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // Recording controls
  
  /// Request recording - always starts immediately (message-style UX)
  /// Returns true if recording started successfully
  Future<bool> requestRecording({String? outputPath, int layer = 0}) async {
    if (_isRecording) {
      debugPrint('❌ [RECORDING] Already recording');
      return false;
    }
    if (_isArmed) {
      debugPrint('❌ [RECORDING] Already armed');
      return false;
    }
    
    _recordingLayer = _resolveDedicatedRecordingLayer();
    debugPrint('🎙️ [RECORDING] Starting immediately (no loop-boundary arming)');
    return await startRecording(outputPath: outputPath, layer: layer);
  }
  
  /// Cancel armed state without starting recording
  void cancelArmed() {
    if (!_isArmed) return;
    
    _isArmed = false;
    _armedSection = null;
    _armedSectionLoop = null;
    
    isArmedNotifier.value = _isArmed;
    notifyListeners();
    
    debugPrint('🚫 [RECORDING] Armed state cancelled');
  }
  
  /// Check if loop boundary crossed and trigger recording if armed
  /// Call this from playback state listener when currentSectionLoop changes
  void checkLoopBoundary({
    required int currentSection,
    required int currentSectionLoop,
    required int currentStep,
  }) {
    if (!_isArmed) return;
    
    // Check if we crossed a loop boundary (loop index changed) or wrapped to section start
    final loopChanged = currentSectionLoop != _armedSectionLoop;
    final sectionChanged = currentSection != _armedSection;
    
    // Get section start step to check if we're at beginning
    final sectionStartStep = _tableState?.getSectionStartStep(currentSection) ?? 0;
    final atSectionStart = currentStep == sectionStartStep;
    
    if (loopChanged || sectionChanged || atSectionStart) {
      debugPrint('🎯 [RECORDING] Loop boundary detected! Loop: $_armedSectionLoop → $currentSectionLoop, Section: $_armedSection → $currentSection');
      
      // Clear armed state
      _isArmed = false;
      _armedSection = null;
      _armedSectionLoop = null;
      isArmedNotifier.value = _isArmed;
      
      // Start recording immediately
      startRecording(layer: _recordingLayer);
    }
  }
  
  /// Start recording immediately (internal, called after arming or directly)
  Future<bool> startRecording({String? outputPath, int layer = 0}) async {
    if (_isRecording) {
      debugPrint('❌ [RECORDING] Already recording');
      return false;
    }
    try {
      // Clear armed state if set (safety)
      if (_isArmed) {
        _isArmed = false;
        _armedSection = null;
        _armedSectionLoop = null;
        isArmedNotifier.value = _isArmed;
      }
      
      // Capture which section and layer we're recording on
      _recordingSection = _playbackState?.currentSection ?? 0;
      _recordingLayer = _resolveDedicatedRecordingLayer();
      _takeVersion++;
      _activeMp3Conversion = null;
      debugPrint('🎙️ [RECORDING] Starting recording on section $_recordingSection, layer $_recordingLayer');
      // Reset conversion state for the new take without deleting past files.
      // Each take must keep its own WAV/MP3 so recordings stack independently.
      _convertedMp3Path = null;
      _conversionError = null;
      _isConverting = false;
      isConvertingNotifier.value = _isConverting;
      convertedMp3PathNotifier.value = _convertedMp3Path;
      conversionErrorNotifier.value = _conversionError;

      _currentRecordingPath = outputPath ?? await _generateDateTimeRecordingPath();
      final pathPtr = _currentRecordingPath!.toNativeUtf8();
      final res = _playback.recordingStart(pathPtr.cast<ffi.Char>());
      malloc.free(pathPtr);
      if (res != 0) {
        debugPrint('❌ [RECORDING] Native start failed: $res');
        _currentRecordingPath = null;
        return false;
      }
      _isRecording = true;
      _recordingStartTime = DateTime.now();
      _recordingDuration = Duration.zero;
      // Ensure previous timer is stopped and UI shows 00:00 immediately
      _stopDurationTimer();
      recordingDurationNotifier.value = Duration.zero;
      isRecordingNotifier.value = _isRecording;
      recordingPathNotifier.value = _currentRecordingPath;
      notifyListeners();
      clearConversionStatus(); // Clear any previous conversion status
      _startDurationTimer();
      debugPrint('🎙️ [RECORDING] Started → $_currentRecordingPath');
      return true;
    } catch (e) {
      debugPrint('❌ [RECORDING] Failed to start recording: $e');
      return false;
    }
  }
  
  Future<bool> stopRecording() async {
    // If armed but not recording, cancel the armed state
    if (_isArmed && !_isRecording) {
      cancelArmed();
      return true;
    }
    
    if (!_isRecording) {
      debugPrint('❌ [RECORDING] Not recording');
      return false;
    }
    
    try {
      _playback.recordingStop();
      _isRecording = false;
      _stopDurationTimer();
      
      // Update notifiers
      isRecordingNotifier.value = _isRecording;
      if (_currentRecordingPath != null) {
        // Insert newest on top
        _localRecordings.insert(0, _currentRecordingPath!);
        recordingsNotifier.value = List<String>.from(_localRecordings);
      }
      
      notifyListeners();
      debugPrint('⏹️ [RECORDING] Stopped recording. Duration: $formattedDuration');
      
      // Immediately trigger callback to save message and switch view
      if (_onRecordingComplete != null) {
        await _onRecordingComplete!();
      }
      
      // Auto-load recorded audio as sample for playback (async, no await to not block)
      _autoLoadRecordedSample();
      
      // Convert WAV -> MP3 in background (happens after message is created)
      _convertInBackground();
      return true;
    } catch (e) {
      debugPrint('❌ [RECORDING] Failed to stop recording: $e');
      return false;
    }
  }

  void clearRecording() {
    if (_isRecording) {
      stopRecording();
    }
    
    _currentRecordingPath = null;
    _recordingStartTime = null;
    _recordingDuration = Duration.zero;
    
    recordingPathNotifier.value = null;
    recordingDurationNotifier.value = Duration.zero;
    notifyListeners();
    debugPrint('🗑️ [RECORDING] Cleared current recording');
  }

  void removeRecording(String filePath) {
    _localRecordings.remove(filePath);
    recordingsNotifier.value = List<String>.from(_localRecordings);
    
    notifyListeners();
    debugPrint('🗑️ [RECORDING] Removed recording: $filePath');
  }

  /// Set dependencies for sample loading (called by UI during initialization)
  void setDependencies({
    required dynamic playbackState,
    required dynamic tableState,
    required dynamic sampleBankState,
  }) {
    _playbackState = playbackState;
    _tableState = tableState;
    _sampleBankState = sampleBankState;
  }

  /// Load recorded audio as sample after recording completes
  Future<bool> loadRecordedAudioAsSample({int? targetSlot}) async {
    if (_currentRecordingPath == null) {
      debugPrint('❌ [RECORDING] No recording path to load');
      return false;
    }
    
    // Find available slot or use slot 25 (last slot, reserved for recordings)
    targetSlot ??= 25;
    
    // Calculate duration for memory warning
    final file = File(_currentRecordingPath!);
    if (!await file.exists()) {
      debugPrint('❌ [RECORDING] Recording file does not exist: $_currentRecordingPath');
      return false;
    }
    
    final fileSizeBytes = await file.length();
    final estimatedMemoryMB = fileSizeBytes / (1024 * 1024);
    
    // Warn if recording is large (>30 MB)
    if (estimatedMemoryMB > 30) {
      debugPrint('⚠️ [RECORDING] Large recording: ${estimatedMemoryMB.toStringAsFixed(1)} MB');
      // User should be notified in UI if needed
    }
    
    // Load into sample bank
    if (_sampleBankState != null) {
      try {
        final displayName = 'Recorded ${DateTime.now().toString().substring(11, 19)}';
        final success = await _sampleBankState.loadRecordedAudio(
          targetSlot, 
          _currentRecordingPath!,
          displayName: displayName,
        );
        
        if (success) {
          debugPrint('✅ [RECORDING] Loaded recording into sample slot $targetSlot');
          return true;
        } else {
          debugPrint('❌ [RECORDING] Failed to load recording into sample bank');
          return false;
        }
      } catch (e) {
        debugPrint('❌ [RECORDING] Error loading recording as sample: $e');
        return false;
      }
    } else {
      debugPrint('⚠️ [RECORDING] Sample bank state not available');
      return false;
    }
  }

  /// Generate pattern notes for recorded audio playback
  void _generatePlaybackPattern(
    int sampleSlot,
    int offsetFrames,
  ) {
    if (_playbackState == null || _tableState == null) {
      debugPrint('⚠️ [RECORDING] Playback or table state not available for pattern generation');
      return;
    }

    try {
      final section = _recordingSection ?? _playbackState.currentSection;

      // Resolve the correct absolute step and column for this recording.
      // Using layer index directly as a SunVox track was wrong (layer 1 ≠ column 1).
      // Writing via setCell persists through any future syncSectionToSunVox calls,
      // whereas the old setPatternEventWithOffset bypassed the table entirely.
      final int startStep = _tableState.getSectionStartStep(section);
      final cols = _tableState.getVisibleCols(_recordingLayer);
      if (cols.isNotEmpty) {
        // Dedicated recording layer path: clear start-step cells on that layer
        // so latest take replaces previous take trigger without touching other layers.
        for (final int col in cols) {
          _tableState.clearCell(startStep, col, undoRecord: false);
        }
      }

      // Place in first free column on dedicated recording layer.
      final int startCol = _tableState.findFirstFreeColInLayerAtStep(startStep, _recordingLayer);

      debugPrint('🎵 [RECORDING] Placing recording in table: section=$section, step=$startStep, col=$startCol, slot=$sampleSlot');

      _tableState.setCell(
        startStep,
        startCol,
        sampleSlot,
        -1.0, // sentinel: inherit volume from sample bank
        -1.0, // sentinel: inherit pitch from sample bank
        undoRecord: false,
      );

      debugPrint('✅ [RECORDING] Recording placed at table[$startStep][$startCol] → slot $sampleSlot (layer $_recordingLayer of section $section)');
    } catch (e) {
      debugPrint('❌ [RECORDING] Error generating playback pattern: $e');
    }
  }

  int _resolveDedicatedRecordingLayer() {
    try {
      final int totalLayers = (_tableState?.totalLayers as int?) ?? 0;
      if (totalLayers > 0) {
        return totalLayers - 1;
      }
    } catch (_) {}
    return _dedicatedRecordingLayerFallback;
  }

  /// Auto-load recorded audio as sample in background
  Future<void> _autoLoadRecordedSample() async {
    try {
      debugPrint('🔄 [RECORDING] Auto-loading recorded audio as sample...');
      final loaded = await loadRecordedAudioAsSample(targetSlot: 25);
      
      if (loaded) {
        debugPrint('✅ [RECORDING] Successfully loaded as sample, generating pattern');
        _generatePlaybackPattern(25, _recordingOffsetFrames);
      } else {
        debugPrint('❌ [RECORDING] Failed to auto-load recorded audio');
      }
    } catch (e) {
      debugPrint('❌ [RECORDING] Error during auto-load: $e');
    }
  }

  // Conversion methods
  Future<bool> convertToMp3({int bitrateKbps = 192}) async {
    final mp3Path = await ensureMp3Ready(bitrateKbps: bitrateKbps);
    return mp3Path != null;
  }

  void clearConversionError() {
    _conversionError = null;
    conversionErrorNotifier.value = _conversionError;
    notifyListeners();
  }

  void clearConversionStatus() {
    _conversionError = null;
    _convertedMp3Path = null;
    conversionErrorNotifier.value = _conversionError;
    convertedMp3PathNotifier.value = _convertedMp3Path;
    notifyListeners();
  }

  void clearUploadStatus() {
    _isUploading = false;
    _uploadedRenderUrl = null;
    _uploadError = null;
    notifyListeners();
  }

  void setUploading(bool value) {
    _isUploading = value;
    notifyListeners();
  }

  void setUploadedRenderUrl(String? url) {
    _uploadedRenderUrl = url;
    notifyListeners();
  }

  void setUploadError(String? error) {
    _uploadError = error;
    notifyListeners();
  }

  // Playback preview controls for the latest recording (prefers MP3 if available)
  Future<void> togglePreview() async {
    if (_isPreviewing) {
      _playback.previewStopSample();
      _isPreviewing = false;
      _previewTimer?.cancel();
      _previewTimer = null;
      notifyListeners();
      return;
    }

    final pathToPlay = _convertedMp3Path ?? _currentRecordingPath;
    if (pathToPlay == null) return;
    try {
      final cPath = pathToPlay.toNativeUtf8();
      try {
        final rc = _playback.previewSamplePath(cPath, 1.0, 1.0);
        if (rc == 0) {
          _isPreviewing = true;
          // Start timer to detect when playback ends (estimate 30 seconds max)
          _previewTimer = Timer(const Duration(seconds: 30), () {
            if (_isPreviewing) {
              _isPreviewing = false;
              _previewTimer?.cancel();
              _previewTimer = null;
              notifyListeners();
            }
          });
          notifyListeners();
        }
      } finally {
        malloc.free(cPath);
      }
    } catch (_) {}
  }

  void stopPreviewIfActive() {
    if (_isPreviewing) {
      _playback.previewStopSample();
      _isPreviewing = false;
      _previewTimer?.cancel();
      _previewTimer = null;
      notifyListeners();
    }
  }

  // Returns MP3 path, converting first if needed
  Future<String?> getShareableMp3Path({int bitrateKbps = 320}) async {
    return ensureMp3Ready(bitrateKbps: bitrateKbps);
  }

  /// Returns MP3 path, awaiting any in-flight conversion for the current take.
  Future<String?> ensureMp3Ready({int bitrateKbps = 320}) async {
    final existingPath = _convertedMp3Path;
    if (existingPath != null && await File(existingPath).exists()) {
      return existingPath;
    }

    final inFlight = _activeMp3Conversion;
    if (inFlight != null) {
      return await inFlight;
    }

    final takeVersion = _takeVersion;
    final future = _runMp3Conversion(
      takeVersion: takeVersion,
      bitrateKbps: bitrateKbps,
    );
    _activeMp3Conversion = future;
    try {
      return await future;
    } finally {
      if (identical(_activeMp3Conversion, future)) {
        _activeMp3Conversion = null;
      }
    }
  }

  // Callback registration for automatic message creation
  void setOnRecordingComplete(Future<void> Function()? callback) {
    _onRecordingComplete = callback;
  }

  // Callback for when conversion completes (to update message with MP3 path)
  Function(String mp3Path)? _onConversionComplete;
  void setOnConversionComplete(Function(String mp3Path)? callback) {
    _onConversionComplete = callback;
  }

  // Convert to MP3 in background (after message is already created)
  Future<void> _convertInBackground() async {
    try {
      debugPrint('🔄 [RECORDING] Starting background conversion...');
      final mp3Path = await ensureMp3Ready(bitrateKbps: 320);

      if (mp3Path != null) {
        debugPrint('✅ [RECORDING] Conversion complete: $mp3Path');
        // Notify that conversion is complete (to update message with MP3 path)
        if (_onConversionComplete != null) {
          _onConversionComplete!(mp3Path);
        }
      } else {
        debugPrint('❌ [RECORDING] Conversion failed');
      }
    } catch (e) {
      debugPrint('❌ [RECORDING] Error during conversion: $e');
    }
  }

  // Recording path helpers (moved from ReliableStorage)
  Future<String> _recordingsDirectory() async {
    final base = await _deriveWritableBasePath();
    final dir = Directory(path.join(base, 'recordings'));
    await dir.create(recursive: true);
    return dir.path;
  }

  Future<String> _generateDateTimeRecordingPath() async {
    final dir = await _recordingsDirectory();
    final now = DateTime.now();
    final ts = '${now.year.toString().padLeft(4,'0')}'
        '${now.month.toString().padLeft(2,'0')}'
        '${now.day.toString().padLeft(2,'0')}'
        '_'
        '${now.hour.toString().padLeft(2,'0')}'
        '${now.minute.toString().padLeft(2,'0')}'
        '${now.second.toString().padLeft(2,'0')}';
    String p = path.join(dir, '$ts.wav');
    int suffix = 1;
    while (await File(p).exists()) {
      p = path.join(dir, '${ts}_$suffix.wav');
      suffix++;
    }
    return p;
  }
  
  Future<String> _deriveWritableBasePath() async {
    final appName = dotenv.env['APP_NAME']!;
    if (Platform.isAndroid) {
      // Use app-specific storage on Android to avoid scoped storage denials.
      final appDocDir = await getApplicationDocumentsDirectory();
      return appDocDir.path;
    }
    if (Platform.isIOS) {
      // Use Documents directory for persistent storage on iOS
      final appDocDir = await getApplicationDocumentsDirectory();
      return appDocDir.path;
    }
    if (Platform.isMacOS) {
      return '${Platform.environment['HOME']}/Documents/$appName';
    }
    if (Platform.isWindows) {
      return '${Platform.environment['USERPROFILE']}\\Documents\\$appName';
    }
    return path.join(Directory.systemTemp.path, appName);
  }

  // Private methods
  void _startDurationTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_recordingStartTime != null) {
        _recordingDuration = DateTime.now().difference(_recordingStartTime!);
        recordingDurationNotifier.value = _recordingDuration;
        notifyListeners();
      }
    });
  }
  
  void _stopDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = null;
  }

  Future<String?> _runMp3Conversion({
    required int takeVersion,
    required int bitrateKbps,
  }) async {
    final wavPath = _currentRecordingPath;
    if (wavPath == null) {
      debugPrint('❌ [CONVERSION] No recording to convert');
      return null;
    }

    try {
      _isConverting = true;
      _conversionError = null;
      _convertedMp3Path = null;

      if (takeVersion == _takeVersion) {
        isConvertingNotifier.value = _isConverting;
        conversionErrorNotifier.value = _conversionError;
        convertedMp3PathNotifier.value = _convertedMp3Path;
        notifyListeners();
      }

      debugPrint('🔄 [CONVERSION] Starting WAV to MP3 conversion...');

      // Initialize conversion library if needed
      if (!_conversion.isLoaded) {
        _conversion.initialize();
      }

      if (!_conversion.isLoaded) {
        throw Exception('Failed to load conversion library: ${_conversion.loadError}');
      }

      // Initialize the conversion engine
      if (!_conversion.init()) {
        throw Exception('Failed to initialize conversion engine');
      }

      // Generate MP3 output path
      final mp3Path = wavPath.replaceAll('.wav', '.mp3');

      // Check if WAV file exists
      final wavFile = File(wavPath);
      if (!await wavFile.exists()) {
        throw Exception('WAV file does not exist: $wavPath');
      }

      // Perform conversion in background isolate
      final success = await ConversionLibrary.convertInBackground(wavPath, mp3Path, bitrateKbps);
      if (!success) {
        throw Exception('Conversion failed - check logs for details');
      }

      if (takeVersion == _takeVersion) {
        _convertedMp3Path = mp3Path;
        convertedMp3PathNotifier.value = _convertedMp3Path;
        notifyListeners();
      } else {
        debugPrint('⚠️ [CONVERSION] Ignoring stale conversion result for old take');
      }

      debugPrint('✅ [CONVERSION] Successfully converted to MP3: $mp3Path');

      // Delete WAV after successful conversion
      try {
        await File(wavPath).delete();
        debugPrint('🗑️ [CONVERSION] Deleted source WAV: $wavPath');
      } catch (e) {
        debugPrint('⚠️ [CONVERSION] Could not delete WAV: $e');
      }

      return mp3Path;
    } catch (e) {
      if (takeVersion == _takeVersion) {
        _conversionError = e.toString();
        conversionErrorNotifier.value = _conversionError;
        notifyListeners();
      }
      debugPrint('❌ [CONVERSION] Conversion failed: $e');
      return null;
    } finally {
      if (takeVersion == _takeVersion) {
        _isConverting = false;
        isConvertingNotifier.value = _isConverting;
        notifyListeners();
      }
    }
  }
  
  @override
  void dispose() {
    _stopDurationTimer();
    _previewTimer?.cancel();
    isRecordingNotifier.dispose();
    isArmedNotifier.dispose();
    recordingDurationNotifier.dispose();
    recordingPathNotifier.dispose();
    recordingsNotifier.dispose();
    isConvertingNotifier.dispose();
    conversionErrorNotifier.dispose();
    convertedMp3PathNotifier.dispose();
    super.dispose();
  }
}
