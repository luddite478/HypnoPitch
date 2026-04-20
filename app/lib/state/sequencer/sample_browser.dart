import '../../utils/log.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../../services/sample_asset_resolver.dart';
import '../library_samples_state.dart';
import 'sample_bank.dart';
import 'playback.dart';

/// Top-level sample-bank folder order (then any other folders A–Z, case-insensitive).
const List<String> _sampleBankFolderOrder = [
  'synth',
  'drums',
  'noise',
  'acoustic',
];

int _sampleBankFolderRank(String name) {
  final i = _sampleBankFolderOrder.indexOf(name.toLowerCase());
  return i < 0 ? _sampleBankFolderOrder.length : i;
}

void _sortSampleBankFolders(List<String> folders) {
  folders.sort((a, b) {
    final ra = _sampleBankFolderRank(a);
    final rb = _sampleBankFolderRank(b);
    if (ra != rb) return ra.compareTo(rb);
    return a.toLowerCase().compareTo(b.toLowerCase());
  });
}

// Temporary sample browser state for the new sequencer implementation
// This integrates the existing sample browser logic with our new sequencer
class SampleBrowserState extends ChangeNotifier {
  static const String _customRootSegment = 'custom';
  bool _isVisible = false;
  bool _isLoading = true;
  List<String> _currentPath = [];
  final List<SampleItem> _currentItems = [];
  Map<String, dynamic>? _manifestData;
  String? _assetErrorMessage;
  int? _targetStep;
  int? _targetCol;

  /// Bank slot for load/place (A–Z index). When null, UI should use [SampleBankState.activeSlot].
  /// [targetCol] is only the grid column; conflating the two made every cell in a column share one color.
  int? _targetBankSlot;
  final LibrarySamplesState? _librarySamplesState;

  SampleBrowserState({
    LibrarySamplesState? librarySamplesState,
  }) : _librarySamplesState = librarySamplesState {
    _librarySamplesState?.addListener(_onLibrarySamplesChanged);
  }

  bool get isVisible => _isVisible;
  bool get isLoading => _isLoading;
  List<String> get currentPath => _currentPath;
  List<SampleItem> get currentItems => _currentItems;
  int? get targetStep => _targetStep;
  int? get targetCol => _targetCol;
  int? get targetBankSlot => _targetBankSlot;
  String? get assetErrorMessage => _assetErrorMessage;

  bool get _isInCustomBranch =>
      _currentPath.isNotEmpty && _currentPath.first == _customRootSegment;

  bool get _hasCustomFolders =>
      (_librarySamplesState?.customFolders.isNotEmpty ?? false);

  void _onLibrarySamplesChanged() {
    _refreshCurrentItems();
  }

  // Initialize the sample browser with manifest data
  Future<void> initialize() async {
    _isLoading = true;
    _assetErrorMessage = null;
    notifyListeners();

    try {
      await _librarySamplesState?.initialize();
      final sampleResolver = SampleAssetResolver.instance;
      final samplesMap = await sampleResolver.loadSamplesManifest();
      if (samplesMap.isNotEmpty) {
        _manifestData = samplesMap;
        _refreshCurrentItems();
        Log.d(
            '📁 Sample browser initialized with ${_manifestData?.keys.length ?? 0} samples');
      } else {
        Log.d('❌ Invalid manifest structure: no samples key found');
        _manifestData = {};
        _assetErrorMessage ??= 'Built-in sample manifest is empty.';
      }
    } catch (e) {
      Log.d('❌ Failed to load samples manifest: $e');
      _manifestData = {}; // Empty fallback
      _assetErrorMessage = 'Failed to load built-in samples.';
    }

    _isLoading = false;
    notifyListeners();
  }

  // Show the sample browser for a specific cell
  void showForCell(int step, int col, {int? bankSlot}) {
    _ensureBuiltInManifestReady();
    _targetStep = step;
    _targetCol = col;
    _targetBankSlot = bankSlot;
    _isVisible = true;
    notifyListeners();
    Log.d(
        '📁 Showing sample browser for cell [$step, $col] bankSlot=$bankSlot');
  }

  // Show for a sample bank slot (V2 compatibility)
  void showForSlot(int slot) {
    _ensureBuiltInManifestReady();
    _targetStep = null;
    _targetCol = slot; // Reuse targetCol for slot
    _targetBankSlot = slot;
    _isVisible = true;
    notifyListeners();
    Log.d('📁 Showing sample browser for slot $slot');
  }

  /// Navigate browser to the folder that contains [samplePath].
  /// Accepts both manifest-style paths (samples/...) and absolute paths
  /// that include a /samples/ segment.
  void navigateToSamplePath(String? samplePath) {
    if (samplePath == null || samplePath.trim().isEmpty) return;

    final normalized = samplePath.replaceAll('\\', '/');
    final markerIndex = normalized.indexOf('samples/');
    if (markerIndex < 0) {
      const customMarker = '/library_samples/custom/';
      final customIndex = normalized.indexOf(customMarker);
      if (customIndex >= 0) {
        final customRelative =
            normalized.substring(customIndex + customMarker.length);
        final customParts =
            customRelative.split('/').where((p) => p.isNotEmpty).toList();
        if (customParts.isNotEmpty) {
          final folder = customParts.first;
          _currentPath = [_customRootSegment, folder];
          _refreshCurrentItems();
          Log.d('📁 Navigated to custom sample folder: $folder');
          return;
        }
      }
      Log.d(
          '📁 Sample path has no samples/ segment, keeping current path: $samplePath');
      return;
    }

    final relative = normalized.substring(markerIndex + 'samples/'.length);
    if (relative.isEmpty) {
      _currentPath = [];
      _refreshCurrentItems();
      Log.d('📁 Navigated to samples root from path: $samplePath');
      return;
    }

    final parts = relative.split('/').where((p) => p.isNotEmpty).toList();
    final hasFileName = parts.isNotEmpty && parts.last.contains('.');
    _currentPath = hasFileName ? parts.sublist(0, parts.length - 1) : parts;
    _refreshCurrentItems();
    Log.d('📁 Navigated to sample folder: ${_currentPath.join('/')}');
  }

  // Hide the sample browser
  void hide() {
    _isVisible = false;
    _targetStep = null;
    _targetCol = null;
    _targetBankSlot = null;
    notifyListeners();
    Log.d('📁 Sample browser hidden');
  }

  // Navigate into a folder
  void navigateToFolder(String folderName, {String? folderKey}) {
    _currentPath.add(folderKey ?? folderName);
    _refreshCurrentItems();
    notifyListeners();
    Log.d('📁 Navigated to: ${_currentPath.join('/')}');
  }

  // Navigate back one level
  void navigateBack() {
    if (_currentPath.isNotEmpty) {
      _currentPath.removeLast();
      _refreshCurrentItems();
      notifyListeners();
      Log.d('📁 Navigated back to: ${_currentPath.join('/')}');
    }
  }

  // Select a sample file - returns the full path
  String? selectSample(SampleItem item) {
    if (item.isFolder) return null;

    Log.d('📁 Selected sample: ${item.path}');
    return item.path; // Path is already complete from manifest
  }

  void _ensureBuiltInManifestReady() {
    if (_isLoading) return;
    if (_manifestData != null && _manifestData!.isNotEmpty) return;
    // Lazy recovery path: if browser opens without built-ins loaded, retry load.
    initialize();
  }

  // Dedicated preview slot is always the last slot.
  static const int _previewSlot = SampleBankState.previewSlot;

  // Current preview sample ID (if any)
  String? _previewSampleId;

  /// Bumps when a preview **starts** (including replay) so UI can reset progress.
  int _previewGeneration = 0;

  String? get previewingSampleId => _previewSampleId;

  int get previewGeneration => _previewGeneration;

  /// Preview a sample by loading it temporarily into preview slot and playing it
  /// Similar to how sound settings preview works
  Future<void> previewSample(SampleItem item, SampleBankState sampleBankState,
      PlaybackState playbackState) async {
    if (item.isFolder || item.sampleId == null) return;

    try {
      // Same sample already in preview slot — replay only (must run before clearing id)
      if (_previewSampleId == item.sampleId &&
          sampleBankState.isSlotLoaded(_previewSlot)) {
        playbackState.stopPreview();
        Log.d(
            '▶️ [SAMPLE_BROWSER] Reusing preview slot for sample: ${item.sampleId}');
        playbackState.previewSampleSlot(_previewSlot,
            pitchRatio: 1.0, volume01: 1.0);
        _previewGeneration++;
        notifyListeners();
        return;
      }

      playbackState.stopPreview();
      _previewSampleId = null;
      notifyListeners();

      Log.d(
          '📥 [SAMPLE_BROWSER] Loading sample into preview slot: ${item.sampleId}');
      final success =
          await sampleBankState.loadSample(_previewSlot, item.sampleId!);

      if (success) {
        _previewSampleId = item.sampleId;
        // Wait a tiny bit for sample to be ready, then preview
        await Future.delayed(const Duration(milliseconds: 50));
        playbackState.previewSampleSlot(_previewSlot,
            pitchRatio: 1.0, volume01: 1.0);
        Log.d(
            '▶️ [SAMPLE_BROWSER] Preview started for sample: ${item.sampleId}');
        _previewGeneration++;
        notifyListeners();
      } else {
        Log.d(
            '❌ [SAMPLE_BROWSER] Failed to load sample for preview: ${item.sampleId}');
      }
    } catch (e) {
      Log.d('❌ [SAMPLE_BROWSER] Error previewing sample: $e');
    }
  }

  /// Stop audible preview and clear [previewingSampleId] so UI shows play again.
  /// Does not unload the preview bank slot (sample may still be loaded in Z).
  void stopActiveSamplePreview(PlaybackState playbackState) {
    playbackState.stopPreview();
    _previewSampleId = null;
    notifyListeners();
    Log.d('🛑 [SAMPLE_BROWSER] Active sample preview stopped');
  }

  /// Stop preview and optionally clean up preview slot
  void stopPreview(PlaybackState playbackState, {bool unload = false}) {
    playbackState.stopPreview();
    if (unload) {
      _previewSampleId = null;
      notifyListeners();
      Log.d('🛑 [SAMPLE_BROWSER] Preview stopped and slot cleared');
    } else {
      Log.d('🛑 [SAMPLE_BROWSER] Preview stopped (slot kept for reuse)');
    }
  }

  // Refresh current items based on current path
  void _refreshCurrentItems() {
    _currentItems.clear();

    if (_isInCustomBranch) {
      _refreshCustomItems();
      Log.d('📁 Refreshed custom items for path: ${_currentPath.join('/')}');
      notifyListeners();
      return;
    }

    if (_manifestData != null) {
      _refreshBuiltInItems();
    } else {
      Log.d('📁 No manifest data available');
    }

    if (_currentPath.isEmpty && _hasCustomFolders) {
      _currentItems.add(
        SampleItem(
          name: _customRootSegment,
          isFolder: true,
          path: 'samples/$_customRootSegment',
          isCustom: true,
        ),
      );
    }

    Log.d('📁 Refreshed items for path: ${_currentPath.join('/')}');
    Log.d('📁 Current items count: ${_currentItems.length}');
    notifyListeners();
  }

  void _refreshCustomItems() {
    final customFolders =
        _librarySamplesState?.customFolders ?? const <String>[];
    if (_currentPath.length == 1) {
      for (final folder in customFolders) {
        _currentItems.add(
          SampleItem(
            name: LibrarySamplesState.formatSampleLabel(folder),
            isFolder: true,
            path: 'samples/$_customRootSegment/$folder',
            isCustom: true,
            folderKey: folder,
          ),
        );
      }
      return;
    }

    final folderName = _currentPath[1];
    final entries = _librarySamplesState?.customEntriesForFolder(folderName) ??
        const <CustomSampleEntry>[];
    for (final entry in entries) {
      _currentItems.add(
        SampleItem(
          name: LibrarySamplesState.formatSampleLabel(entry.fileName),
          isFolder: false,
          path: entry.filePath,
          sampleId: entry.id,
          isCustom: true,
        ),
      );
    }
  }

  void _refreshBuiltInItems() {
    // Build virtual folder structure from flat manifest
    final folders = <String>{};
    final files = <SampleItem>[];

    // Get the current path prefix
    final currentPathPrefix = _currentPath.join('/');
    final searchPrefix =
        currentPathPrefix.isEmpty ? 'samples/' : 'samples/$currentPathPrefix/';

    Log.d('📁 Searching for items with prefix: $searchPrefix');

    // Go through all samples in manifest
    int totalSamples = 0;
    int matchingSamples = 0;

    for (final entry in _manifestData!.entries) {
      totalSamples++;
      final sampleId = entry.key;
      final sampleData = entry.value;

      if (sampleData is Map && sampleData.containsKey('path')) {
        final fullPath = sampleData['path'] as String;

        // Check if this sample is in the current directory
        if (fullPath.startsWith(searchPrefix)) {
          matchingSamples++;
          final relativePath = fullPath.substring(searchPrefix.length);
          final pathParts = relativePath.split('/');

          if (pathParts.length == 1) {
            // This is a file in current directory
            final displayRaw = sampleData['display_name'];
            final displayName = displayRaw is String && displayRaw.isNotEmpty
                ? displayRaw
                : p.basenameWithoutExtension(pathParts[0]);
            files.add(SampleItem(
              name: LibrarySamplesState.formatSampleLabel(displayName),
              isFolder: false,
              path: fullPath,
              sampleId: sampleId,
            ));
          } else if (pathParts.isNotEmpty) {
            // This is in a subdirectory
            folders.add(pathParts[0]);
          }
        }
      }
    }

    // Add folders first (built-in order, then others alphabetically)
    final sortedFolders = folders.toList();
    _sortSampleBankFolders(sortedFolders);
    for (final folder in sortedFolders) {
      _currentItems.add(SampleItem(
        name: LibrarySamplesState.formatSampleLabel(folder),
        isFolder: true,
        path: '$searchPrefix$folder',
        folderKey: folder,
      ));
    }

    // Add files (sorted by name)
    files.sort((a, b) => a.name.compareTo(b.name));
    _currentItems.addAll(files);

    Log.d('📁 Total samples in manifest: $totalSamples');
    Log.d('📁 Matching samples: $matchingSamples');
    Log.d('📁 Found ${folders.length} folders, ${files.length} files');
  }

  @override
  void dispose() {
    _librarySamplesState?.removeListener(_onLibrarySamplesChanged);
    super.dispose();
  }
}

// Sample item data class
class SampleItem {
  final String name;
  final bool isFolder;
  final String path;
  final String? folderKey;
  final String? sampleId; // ID from manifest for files
  final bool isCustom;

  SampleItem({
    required this.name,
    required this.isFolder,
    required this.path,
    this.folderKey,
    this.sampleId,
    this.isCustom = false,
  });

  @override
  String toString() =>
      'SampleItem(name: $name, folderKey: $folderKey, isFolder: $isFolder, path: $path, sampleId: $sampleId, isCustom: $isCustom)';
}
