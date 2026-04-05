import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../services/sample_asset_resolver.dart';
import '../utils/local_audio_path.dart';

class LibrarySampleBrowserItem {
  final String name;
  final bool isFolder;
  final String pathValue;
  final String? sampleId;
  final bool isBuiltIn;

  const LibrarySampleBrowserItem({
    required this.name,
    required this.isFolder,
    required this.pathValue,
    required this.isBuiltIn,
    this.sampleId,
  });
}

class LibrarySamplesState extends ChangeNotifier {
  static const String _defaultRootName = 'Default';
  static const String customSampleIdPrefix = 'custom:';
  static const Set<String> _audioExtensions = {
    '.wav',
    '.mp3',
    '.m4a',
    '.aif',
    '.aiff',
    '.flac',
    '.ogg',
  };

  bool _isLoading = true;
  bool _isInitialized = false;

  bool _isInDefault = false;
  String? _currentCustomFolder;
  List<String> _defaultPath = [];

  Map<String, dynamic> _builtInManifest = {};
  List<LibrarySampleBrowserItem> _currentBuiltInItems = [];
  final Map<String, List<String>> _customFolderFiles = {};

  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  bool get isAtRoot => !_isInDefault && _currentCustomFolder == null;
  bool get isInDefault => _isInDefault;
  String? get currentCustomFolder => _currentCustomFolder;
  List<String> get defaultPath => List.unmodifiable(_defaultPath);

  List<String> get customFolders {
    final folders = _customFolderFiles.keys.toList()..sort();
    return List.unmodifiable(folders);
  }

  List<LibrarySampleBrowserItem> get currentBuiltInItems =>
      List.unmodifiable(_currentBuiltInItems);

  List<String> get currentCustomFiles {
    if (_currentCustomFolder == null) return const [];
    final files = List<String>.from(_customFolderFiles[_currentCustomFolder] ?? []);
    files.sort((a, b) => path.basename(a).compareTo(path.basename(b)));
    return List.unmodifiable(files);
  }

  List<String> customFilesForFolder(String folderName) {
    final files = List<String>.from(_customFolderFiles[folderName] ?? const []);
    files.sort((a, b) => path.basename(a).compareTo(path.basename(b)));
    return List.unmodifiable(files);
  }

  String get currentPathLabel {
    if (isAtRoot) return 'samples/';
    if (_isInDefault) {
      if (_defaultPath.isEmpty) return 'samples/default/';
      return 'samples/default/${_defaultPath.join('/')}/';
    }
    return 'samples/custom/${_currentCustomFolder ?? ''}/';
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isLoading = true;
    notifyListeners();

    await Future.wait([
      _loadBuiltInManifest(),
      _loadCustomIndex(),
    ]);

    _isInitialized = true;
    _isLoading = false;
    notifyListeners();
  }

  void openRoot() {
    _isInDefault = false;
    _currentCustomFolder = null;
    _defaultPath = [];
    notifyListeners();
  }

  void openDefaultRoot() {
    _isInDefault = true;
    _currentCustomFolder = null;
    _defaultPath = [];
    _refreshBuiltInItems();
    notifyListeners();
  }

  void openDefaultFolder(String folderName) {
    if (!_isInDefault) return;
    _defaultPath = [..._defaultPath, folderName];
    _refreshBuiltInItems();
    notifyListeners();
  }

  void openCustomFolder(String folderName) {
    if (!_customFolderFiles.containsKey(folderName)) return;
    _isInDefault = false;
    _currentCustomFolder = folderName;
    notifyListeners();
  }

  void navigateBack() {
    if (_isInDefault) {
      if (_defaultPath.isNotEmpty) {
        _defaultPath = _defaultPath.sublist(0, _defaultPath.length - 1);
        _refreshBuiltInItems();
      } else {
        openRoot();
        return;
      }
      notifyListeners();
      return;
    }

    if (_currentCustomFolder != null) {
      openRoot();
    }
  }

  Future<ImportCustomSamplesResult> importFilesToCustomFolder({
    required String folderName,
    required List<PlatformFile> files,
  }) async {
    final normalizedFolder = folderName.trim();
    if (normalizedFolder.isEmpty) {
      return const ImportCustomSamplesResult(
        importedCount: 0,
        skippedCount: 0,
        createdFolder: false,
        errorMessage: 'Folder name cannot be empty.',
      );
    }

    _isLoading = true;
    notifyListeners();

    final folderPath = await _ensureCustomFolder(normalizedFolder);
    final existing = List<String>.from(_customFolderFiles[normalizedFolder] ?? []);
    final imported = <String>[];
    int skipped = 0;

    for (final pickedFile in files) {
      final sourcePath = pickedFile.path;
      if (sourcePath == null || sourcePath.isEmpty) {
        skipped++;
        continue;
      }

      final extension = path.extension(sourcePath).toLowerCase();
      if (!_audioExtensions.contains(extension)) {
        skipped++;
        continue;
      }

      final destinationName = _uniqueFileName(folderPath, path.basename(sourcePath));
      final destinationPath = path.join(folderPath.path, destinationName);
      try {
        await File(sourcePath).copy(destinationPath);
        imported.add(destinationPath);
      } catch (_) {
        skipped++;
      }
    }

    final merged = {...existing, ...imported}.toList()..sort();
    _customFolderFiles[normalizedFolder] = merged;
    await _persistCustomIndex();

    _isLoading = false;
    notifyListeners();

    return ImportCustomSamplesResult(
      importedCount: imported.length,
      skippedCount: skipped,
      createdFolder: existing.isEmpty,
      errorMessage: imported.isEmpty ? 'No supported audio files were imported.' : null,
    );
  }

  String sampleIdForCustomFile(String folderName, String filePath) {
    return customSampleIdFor(folderName: folderName, filePath: filePath);
  }

  static bool isCustomSampleId(String sampleId) {
    return sampleId.startsWith(customSampleIdPrefix);
  }

  static String customSampleIdFor({
    required String folderName,
    required String filePath,
  }) {
    final safeFolder = folderName.trim();
    final fileName = path.basename(filePath);
    return '$customSampleIdPrefix$safeFolder/$fileName';
  }

  static String? customFileNameFromSampleId(String sampleId) {
    if (!isCustomSampleId(sampleId)) return null;
    final value = sampleId.substring(customSampleIdPrefix.length);
    final slashIndex = value.indexOf('/');
    if (slashIndex <= 0 || slashIndex >= value.length - 1) return null;
    return value.substring(slashIndex + 1);
  }

  static String? customFolderFromSampleId(String sampleId) {
    if (!isCustomSampleId(sampleId)) return null;
    final value = sampleId.substring(customSampleIdPrefix.length);
    final slashIndex = value.indexOf('/');
    if (slashIndex <= 0 || slashIndex >= value.length - 1) return null;
    return value.substring(0, slashIndex);
  }

  Future<bool> removeCustomFile({
    required String folderName,
    required String filePath,
  }) async {
    final files = List<String>.from(_customFolderFiles[folderName] ?? const []);
    if (files.isEmpty) return false;

    final normalized = LocalAudioPath.normalize(filePath);
    final match = files.where((f) => LocalAudioPath.normalize(f) == normalized);
    if (match.isEmpty) return false;

    for (final item in match.toList()) {
      files.remove(item);
      try {
        final file = File(item);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }

    if (files.isEmpty) {
      _customFolderFiles.remove(folderName);
      if (_currentCustomFolder == folderName) {
        openRoot();
      }
      try {
        final docs = await getApplicationDocumentsDirectory();
        final folderDir = Directory(
          path.join(docs.path, 'library_samples', 'custom', folderName),
        );
        if (await folderDir.exists()) {
          await folderDir.delete(recursive: true);
        }
      } catch (_) {}
    } else {
      _customFolderFiles[folderName] = files..sort();
    }

    await _persistCustomIndex();
    notifyListeners();
    return true;
  }

  /// Deletes a custom folder and all audio files inside (disk + index).
  Future<bool> removeCustomFolder(String folderName) async {
    final trimmed = folderName.trim();
    if (trimmed.isEmpty || !_customFolderFiles.containsKey(trimmed)) {
      return false;
    }

    _customFolderFiles.remove(trimmed);

    if (_currentCustomFolder == trimmed) {
      openRoot();
    }

    try {
      final docs = await getApplicationDocumentsDirectory();
      final folderDir = Directory(
        path.join(docs.path, 'library_samples', 'custom', trimmed),
      );
      if (await folderDir.exists()) {
        await folderDir.delete(recursive: true);
      }
    } catch (_) {}

    await _persistCustomIndex();
    notifyListeners();
    return true;
  }

  static Future<String?> resolveCustomSampleIdPath(String sampleId) async {
    final folderName = customFolderFromSampleId(sampleId);
    final fileName = customFileNameFromSampleId(sampleId);
    if (folderName == null || fileName == null) return null;

    try {
      final docs = await getApplicationDocumentsDirectory();
      final directPath = path.join(
        docs.path,
        'library_samples',
        'custom',
        folderName,
        fileName,
      );
      final direct = File(directPath);
      if (await direct.exists()) {
        return direct.path;
      }
    } catch (_) {}

    return LocalAudioPath.resolve(fileName);
  }

  Future<void> _loadBuiltInManifest() async {
    try {
      final sampleResolver = SampleAssetResolver.instance;
      await sampleResolver.ensureBuiltInSamplesReady();
      _builtInManifest = await sampleResolver.loadSamplesManifest();
    } catch (_) {
      _builtInManifest = {};
    }

    _refreshBuiltInItems();
  }

  Future<void> _loadCustomIndex() async {
    try {
      final indexFile = await _indexFile();
      if (!await indexFile.exists()) {
        _customFolderFiles.clear();
        return;
      }

      final decoded = json.decode(await indexFile.readAsString());
      if (decoded is! Map<String, dynamic>) {
        _customFolderFiles.clear();
        return;
      }

      final result = <String, List<String>>{};
      for (final entry in decoded.entries) {
        if (entry.value is List) {
          final files = (entry.value as List)
              .whereType<String>()
              .where((p) => p.isNotEmpty)
              .toList()
            ..sort();
          result[entry.key] = files;
        }
      }
      _customFolderFiles
        ..clear()
        ..addAll(result);
    } catch (_) {
      _customFolderFiles.clear();
    }
  }

  void _refreshBuiltInItems() {
    final items = <LibrarySampleBrowserItem>[];
    final folders = <String>{};

    final prefix = _defaultPath.isEmpty
        ? 'samples/'
        : 'samples/${_defaultPath.join('/')}/';

    for (final entry in _builtInManifest.entries) {
      final sampleId = entry.key;
      final sampleData = entry.value;
      if (sampleData is! Map || sampleData['path'] is! String) continue;
      final fullPath = sampleData['path'] as String;
      if (!fullPath.startsWith(prefix)) continue;

      final relativePath = fullPath.substring(prefix.length);
      final parts = relativePath.split('/');
      if (parts.length == 1) {
        items.add(
          LibrarySampleBrowserItem(
            name: parts[0],
            isFolder: false,
            pathValue: fullPath,
            sampleId: sampleId,
            isBuiltIn: true,
          ),
        );
      } else if (parts.isNotEmpty) {
        folders.add(parts[0]);
      }
    }

    final sortedFolders = folders.toList()..sort();
    for (final folder in sortedFolders) {
      items.insert(
        0,
        LibrarySampleBrowserItem(
          name: folder,
          isFolder: true,
          pathValue: '$prefix$folder',
          isBuiltIn: true,
        ),
      );
    }

    items.sort((a, b) {
      if (a.isFolder && !b.isFolder) return -1;
      if (!a.isFolder && b.isFolder) return 1;
      return a.name.compareTo(b.name);
    });
    _currentBuiltInItems = items;
  }

  Future<File> _indexFile() async {
    final docs = await getApplicationDocumentsDirectory();
    final rootDir = Directory(path.join(docs.path, 'library_samples'));
    if (!await rootDir.exists()) {
      await rootDir.create(recursive: true);
    }
    return File(path.join(rootDir.path, 'custom_index.json'));
  }

  Future<Directory> _ensureCustomFolder(String folderName) async {
    final docs = await getApplicationDocumentsDirectory();
    final folderDir =
        Directory(path.join(docs.path, 'library_samples', 'custom', folderName));
    if (!await folderDir.exists()) {
      await folderDir.create(recursive: true);
    }
    return folderDir;
  }

  String _uniqueFileName(Directory folderDir, String originalName) {
    final base = path.basenameWithoutExtension(originalName);
    final ext = path.extension(originalName);
    var candidate = originalName;
    var index = 1;
    while (File(path.join(folderDir.path, candidate)).existsSync()) {
      candidate = '${base}_$index$ext';
      index++;
    }
    return candidate;
  }

  Future<void> _persistCustomIndex() async {
    final indexFile = await _indexFile();
    final encoded = const JsonEncoder.withIndent('  ').convert(_customFolderFiles);
    await indexFile.writeAsString(encoded, flush: true);
  }

  static String defaultRootName() => _defaultRootName;
}

class ImportCustomSamplesResult {
  final int importedCount;
  final int skippedCount;
  final bool createdFolder;
  final String? errorMessage;

  const ImportCustomSamplesResult({
    required this.importedCount,
    required this.skippedCount,
    required this.createdFolder,
    this.errorMessage,
  });
}
