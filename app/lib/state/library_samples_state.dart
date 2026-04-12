import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
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
  final String? folderKey;
  final String? sampleId;
  final bool isBuiltIn;

  const LibrarySampleBrowserItem({
    required this.name,
    required this.isFolder,
    required this.pathValue,
    this.folderKey,
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
  final Map<String, List<CustomSampleEntry>> _customFolderEntries = {};

  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  bool get isAtRoot => !_isInDefault && _currentCustomFolder == null;
  bool get isInDefault => _isInDefault;
  String? get currentCustomFolder => _currentCustomFolder;
  List<String> get defaultPath => List.unmodifiable(_defaultPath);

  List<String> get customFolders {
    final folders = _customFolderEntries.keys.toList()..sort();
    return List.unmodifiable(folders);
  }

  List<LibrarySampleBrowserItem> get currentBuiltInItems =>
      List.unmodifiable(_currentBuiltInItems);

  List<String> get currentCustomFiles {
    if (_currentCustomFolder == null) return const [];
    final entries = List<CustomSampleEntry>.from(
        _customFolderEntries[_currentCustomFolder] ?? []);
    entries.sort((a, b) => a.fileName.compareTo(b.fileName));
    final files = entries.map((e) => e.filePath).toList(growable: false);
    return List.unmodifiable(files);
  }

  List<String> customFilesForFolder(String folderName) {
    final entries = List<CustomSampleEntry>.from(
        _customFolderEntries[folderName] ?? const []);
    entries.sort((a, b) => a.fileName.compareTo(b.fileName));
    final files = entries.map((e) => e.filePath).toList(growable: false);
    return List.unmodifiable(files);
  }

  List<CustomSampleEntry> customEntriesForFolder(String folderName) {
    final entries = List<CustomSampleEntry>.from(
        _customFolderEntries[folderName] ?? const []);
    entries.sort((a, b) => a.fileName.compareTo(b.fileName));
    return List.unmodifiable(entries);
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
    if (!_customFolderEntries.containsKey(folderName)) return;
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
    final existing = List<CustomSampleEntry>.from(
        _customFolderEntries[normalizedFolder] ?? []);
    final imported = <CustomSampleEntry>[];
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

      final destinationName =
          _uniqueFileName(folderPath, path.basename(sourcePath));
      final destinationPath = path.join(folderPath.path, destinationName);
      try {
        await File(sourcePath).copy(destinationPath);
        final importedFile = File(destinationPath);
        final digest = await sha256.bind(importedFile.openRead()).first;
        final id = customSampleIdForHash(digest.toString());
        imported.add(
          CustomSampleEntry(
            id: id,
            fileName: destinationName,
            filePath: destinationPath,
            importedAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
        );
      } catch (_) {
        skipped++;
      }
    }

    final merged = _dedupeEntries([...existing, ...imported]);
    _customFolderEntries[normalizedFolder] = merged;
    await _persistCustomIndex();

    _isLoading = false;
    notifyListeners();

    return ImportCustomSamplesResult(
      importedCount: imported.length,
      skippedCount: skipped,
      createdFolder: existing.isEmpty,
      errorMessage:
          imported.isEmpty ? 'No supported audio files were imported.' : null,
    );
  }

  String sampleIdForCustomFile(String folderName, String filePath) {
    final normalized = LocalAudioPath.normalize(filePath);
    final entries = _customFolderEntries[folderName] ?? const [];
    for (final entry in entries) {
      if (LocalAudioPath.normalize(entry.filePath) == normalized) {
        return entry.id;
      }
    }
    // Backward-compatible fallback for old callers/index.
    return customSampleIdFor(folderName: folderName, filePath: filePath);
  }

  static bool isCustomSampleId(String sampleId) {
    return sampleId.startsWith(customSampleIdPrefix);
  }

  static bool isCustomHashSampleId(String sampleId) {
    if (!isCustomSampleId(sampleId)) return false;
    final value = sampleId.substring(customSampleIdPrefix.length);
    return value.isNotEmpty && !value.contains('/');
  }

  static String customSampleIdFor({
    required String folderName,
    required String filePath,
  }) {
    final safeFolder = folderName.trim();
    final fileName = path.basename(filePath);
    return '$customSampleIdPrefix$safeFolder/$fileName';
  }

  static String customSampleIdForHash(String hashHex) {
    return '$customSampleIdPrefix${hashHex.trim().toLowerCase()}';
  }

  static String formatSampleLabel(String input) {
    var text = input.replaceAll('___sharp___', '#');
    text = text.replaceAll('_', ' ');
    text = text.replaceAllMapped(
      RegExp(r'\b([a-g])\s*sharp\s*(\d)\b', caseSensitive: false),
      (m) => '${m.group(1)!.toUpperCase()}#${m.group(2)!}',
    );
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text;
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
    final entries = List<CustomSampleEntry>.from(
        _customFolderEntries[folderName] ?? const []);
    if (entries.isEmpty) return false;

    final normalized = LocalAudioPath.normalize(filePath);
    final match = entries
        .where((e) => LocalAudioPath.normalize(e.filePath) == normalized);
    if (match.isEmpty) return false;

    for (final item in match.toList()) {
      entries.remove(item);
      try {
        final file = File(item.filePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }

    if (entries.isEmpty) {
      _customFolderEntries.remove(folderName);
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
      _customFolderEntries[folderName] = _dedupeEntries(entries);
    }

    await _persistCustomIndex();
    notifyListeners();
    return true;
  }

  /// Deletes a custom folder and all audio files inside (disk + index).
  Future<bool> removeCustomFolder(String folderName) async {
    final trimmed = folderName.trim();
    if (trimmed.isEmpty || !_customFolderEntries.containsKey(trimmed)) {
      return false;
    }

    _customFolderEntries.remove(trimmed);

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

  static Future<String?> resolveCustomSampleIdPath(
    String sampleId, {
    String? filePathHint,
  }) async {
    final folderName = customFolderFromSampleId(sampleId);
    final fileName = customFileNameFromSampleId(sampleId);
    if (folderName != null && fileName != null) {
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

      final byName = await LocalAudioPath.resolve(fileName);
      if (byName != null && byName.isNotEmpty) return byName;
    }

    if (isCustomHashSampleId(sampleId)) {
      final entries = await _readCustomEntriesFromDisk();
      final candidate = entries.firstWhere(
        (e) => e.id == sampleId,
        orElse: () => const CustomSampleEntry.empty(),
      );
      if (candidate.id.isNotEmpty) {
        final resolved = await LocalAudioPath.resolve(candidate.filePath);
        if (resolved != null && resolved.isNotEmpty) return resolved;
      }
    }

    if (filePathHint != null && filePathHint.trim().isNotEmpty) {
      final resolved = await LocalAudioPath.resolve(filePathHint);
      if (resolved != null && resolved.isNotEmpty) return resolved;
    }

    return null;
  }

  static Future<String?> findCustomSampleIdForPath(String filePath) async {
    final normalized = LocalAudioPath.normalize(filePath);
    final entries = await _readCustomEntriesFromDisk();
    for (final entry in entries) {
      if (LocalAudioPath.normalize(entry.filePath) == normalized) {
        return entry.id;
      }
    }
    return null;
  }

  Future<CustomSampleRegistrationResult> registerRecoveredCustomSample({
    required String sourcePath,
    String folderName = 'Recovered',
  }) async {
    final normalizedFolder =
        folderName.trim().isEmpty ? 'Recovered' : folderName.trim();
    final extension = path.extension(sourcePath).toLowerCase();
    if (!_audioExtensions.contains(extension)) {
      return const CustomSampleRegistrationResult(
        success: false,
        errorMessage: 'Unsupported file type.',
      );
    }

    final folderDir = await _ensureCustomFolder(normalizedFolder);
    final destinationName =
        _uniqueFileName(folderDir, path.basename(sourcePath));
    final destinationPath = path.join(folderDir.path, destinationName);
    await File(sourcePath).copy(destinationPath);

    final digest = await sha256.bind(File(destinationPath).openRead()).first;
    final id = customSampleIdForHash(digest.toString());

    final entries = List<CustomSampleEntry>.from(
        _customFolderEntries[normalizedFolder] ?? const []);
    entries.add(
      CustomSampleEntry(
        id: id,
        fileName: destinationName,
        filePath: destinationPath,
        importedAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    _customFolderEntries[normalizedFolder] = _dedupeEntries(entries);
    await _persistCustomIndex();
    notifyListeners();

    return CustomSampleRegistrationResult(
      success: true,
      sampleId: id,
      filePath: destinationPath,
      folderName: normalizedFolder,
    );
  }

  Future<CustomSampleRegistrationResult> registerArchivedCustomSample({
    required Uint8List bytes,
    required String sampleId,
    required String fileName,
    String folderName = 'Imported',
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (!isCustomSampleId(sampleId)) {
      return const CustomSampleRegistrationResult(
        success: false,
        errorMessage: 'Archive sample id must use the custom: prefix.',
      );
    }

    final digest = sha256.convert(bytes).toString();
    final canonicalId = customSampleIdForHash(digest);
    if (isCustomHashSampleId(sampleId) && canonicalId != sampleId) {
      return const CustomSampleRegistrationResult(
        success: false,
        errorMessage: 'Embedded sample hash does not match sample id.',
      );
    }

    final existing = _findCustomEntryById(canonicalId);
    if (existing != null) {
      final resolvedPath = await LocalAudioPath.resolve(existing.filePath);
      if (resolvedPath != null && resolvedPath.isNotEmpty) {
        return CustomSampleRegistrationResult(
          success: true,
          sampleId: existing.id,
          filePath: resolvedPath,
          folderName: _folderNameForEntryId(existing.id),
        );
      }
      _removeCustomEntriesById(canonicalId);
    }

    final normalizedFolder =
        folderName.trim().isEmpty ? 'Imported' : folderName.trim();
    final folderDir = await _ensureCustomFolder(normalizedFolder);
    final safeFileName = path.basename(
      fileName.trim().isEmpty ? '${digest.substring(0, 12)}.wav' : fileName,
    );
    final destinationName = _uniqueFileName(folderDir, safeFileName);
    final destinationPath = path.join(folderDir.path, destinationName);
    await File(destinationPath).writeAsBytes(bytes, flush: true);

    final entries = List<CustomSampleEntry>.from(
        _customFolderEntries[normalizedFolder] ?? const []);
    entries.add(
      CustomSampleEntry(
        id: canonicalId,
        fileName: destinationName,
        filePath: destinationPath,
        importedAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    _customFolderEntries[normalizedFolder] = _dedupeEntries(entries);
    await _persistCustomIndex();
    notifyListeners();

    return CustomSampleRegistrationResult(
      success: true,
      sampleId: canonicalId,
      filePath: destinationPath,
      folderName: normalizedFolder,
    );
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
        _customFolderEntries.clear();
        return;
      }

      final decoded = json.decode(await indexFile.readAsString());
      if (decoded is! Map<String, dynamic>) {
        _customFolderEntries.clear();
        return;
      }

      final result = _decodeCustomIndex(decoded);
      _customFolderEntries
        ..clear()
        ..addAll(result);
      await _migrateLegacyEntryIdsToHashes();
    } catch (_) {
      _customFolderEntries.clear();
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
        final fallback = path.basenameWithoutExtension(parts[0]);
        final displayRaw = sampleData['display_name'];
        final displayName = displayRaw is String && displayRaw.isNotEmpty
            ? displayRaw
            : fallback;
        items.add(
          LibrarySampleBrowserItem(
            name: formatSampleLabel(displayName),
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
          name: formatSampleLabel(folder),
          isFolder: true,
          pathValue: '$prefix$folder',
          folderKey: folder,
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
    final folderDir = Directory(
        path.join(docs.path, 'library_samples', 'custom', folderName));
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
    final folders = <String, List<Map<String, dynamic>>>{};
    for (final entry in _customFolderEntries.entries) {
      folders[entry.key] = entry.value.map((e) => e.toJson()).toList();
    }
    final encoded = const JsonEncoder.withIndent('  ').convert({
      'schema_version': 2,
      'folders': folders,
    });
    await indexFile.writeAsString(encoded, flush: true);
  }

  Future<void> _migrateLegacyEntryIdsToHashes() async {
    var changed = false;
    final migrated = <String, List<CustomSampleEntry>>{};
    for (final folderEntry in _customFolderEntries.entries) {
      final next = <CustomSampleEntry>[];
      for (final entry in folderEntry.value) {
        if (!entry.id.contains('/')) {
          next.add(entry);
          continue;
        }
        try {
          final file = File(entry.filePath);
          if (!await file.exists()) {
            next.add(entry);
            continue;
          }
          final digest = await sha256.bind(file.openRead()).first;
          final newId = customSampleIdForHash(digest.toString());
          if (newId != entry.id) {
            changed = true;
            next.add(
              CustomSampleEntry(
                id: newId,
                fileName: entry.fileName,
                filePath: entry.filePath,
                importedAtMs: entry.importedAtMs,
              ),
            );
          } else {
            next.add(entry);
          }
        } catch (_) {
          next.add(entry);
        }
      }
      migrated[folderEntry.key] = _dedupeEntries(next);
    }
    if (changed) {
      _customFolderEntries
        ..clear()
        ..addAll(migrated);
      await _persistCustomIndex();
    }
  }

  static String defaultRootName() => _defaultRootName;

  static Future<File> _staticIndexFile() async {
    final docs = await getApplicationDocumentsDirectory();
    final rootDir = Directory(path.join(docs.path, 'library_samples'));
    if (!await rootDir.exists()) {
      await rootDir.create(recursive: true);
    }
    return File(path.join(rootDir.path, 'custom_index.json'));
  }

  static Future<List<CustomSampleEntry>> _readCustomEntriesFromDisk() async {
    try {
      final indexFile = await _staticIndexFile();
      if (!await indexFile.exists()) return const [];
      final decoded = json.decode(await indexFile.readAsString());
      if (decoded is! Map<String, dynamic>) return const [];
      final map = _decodeCustomIndex(decoded);
      return map.values.expand((list) => list).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static Map<String, List<CustomSampleEntry>> _decodeCustomIndex(
      Map<String, dynamic> decoded) {
    final result = <String, List<CustomSampleEntry>>{};

    final version = decoded['schema_version'];
    final foldersNode =
        (version == 2 && decoded['folders'] is Map<String, dynamic>)
            ? decoded['folders'] as Map<String, dynamic>
            : decoded;

    for (final folderEntry in foldersNode.entries) {
      final folderName = folderEntry.key;
      final rawValue = folderEntry.value;
      if (rawValue is! List) continue;

      final parsed = <CustomSampleEntry>[];
      for (final item in rawValue) {
        if (item is String) {
          final fileName = path.basename(item);
          parsed.add(
            CustomSampleEntry(
              id: customSampleIdFor(folderName: folderName, filePath: item),
              fileName: fileName,
              filePath: item,
              importedAtMs: 0,
            ),
          );
          continue;
        }
        if (item is! Map<String, dynamic>) continue;
        final filePath = item['path'];
        if (filePath is! String || filePath.isEmpty) continue;
        final fileName = (item['file_name'] is String &&
                (item['file_name'] as String).isNotEmpty)
            ? item['file_name'] as String
            : path.basename(filePath);
        final id = (item['id'] is String && (item['id'] as String).isNotEmpty)
            ? item['id'] as String
            : customSampleIdFor(folderName: folderName, filePath: filePath);
        parsed.add(
          CustomSampleEntry(
            id: id,
            fileName: fileName,
            filePath: filePath,
            importedAtMs: (item['imported_at'] as num?)?.toInt() ?? 0,
          ),
        );
      }
      result[folderName] = _dedupeEntries(parsed);
    }
    return result;
  }

  static List<CustomSampleEntry> _dedupeEntries(
      List<CustomSampleEntry> entries) {
    final byPath = <String, CustomSampleEntry>{};
    for (final entry in entries) {
      final key = LocalAudioPath.normalize(entry.filePath);
      byPath[key] = entry;
    }
    final deduped = byPath.values.toList();
    deduped.sort((a, b) => a.fileName.compareTo(b.fileName));
    return deduped;
  }

  CustomSampleEntry? _findCustomEntryById(String sampleId) {
    for (final folderEntries in _customFolderEntries.values) {
      for (final entry in folderEntries) {
        if (entry.id == sampleId) {
          return entry;
        }
      }
    }
    return null;
  }

  String? _folderNameForEntryId(String sampleId) {
    for (final folderEntry in _customFolderEntries.entries) {
      if (folderEntry.value.any((entry) => entry.id == sampleId)) {
        return folderEntry.key;
      }
    }
    return null;
  }

  void _removeCustomEntriesById(String sampleId) {
    final emptyFolders = <String>[];
    for (final folderEntry in _customFolderEntries.entries) {
      folderEntry.value.removeWhere((entry) => entry.id == sampleId);
      if (folderEntry.value.isEmpty) {
        emptyFolders.add(folderEntry.key);
      }
    }
    for (final folder in emptyFolders) {
      _customFolderEntries.remove(folder);
    }
  }
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

class CustomSampleRegistrationResult {
  final bool success;
  final String? sampleId;
  final String? filePath;
  final String? folderName;
  final String? errorMessage;

  const CustomSampleRegistrationResult({
    required this.success,
    this.sampleId,
    this.filePath,
    this.folderName,
    this.errorMessage,
  });
}

class CustomSampleEntry {
  final String id;
  final String fileName;
  final String filePath;
  final int importedAtMs;

  const CustomSampleEntry({
    required this.id,
    required this.fileName,
    required this.filePath,
    required this.importedAtMs,
  });

  const CustomSampleEntry.empty()
      : id = '',
        fileName = '',
        filePath = '',
        importedAtMs = 0;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'file_name': fileName,
      'path': filePath,
      'imported_at': importedAtMs,
    };
  }
}
