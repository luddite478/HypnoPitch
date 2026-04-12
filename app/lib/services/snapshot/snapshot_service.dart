import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import '../../services/sample_reference_resolver.dart';
import '../../state/library_samples_state.dart';
import 'export.dart';
import 'import.dart';
import 'archive_service.dart';
import '../../state/sequencer/table.dart';
import '../../state/sequencer/playback.dart';
import '../../state/sequencer/sample_bank.dart';

export 'import.dart'
    show MissingSampleIssue, MissingSampleReason, SnapshotImportReport;
export 'archive_service.dart' show snapshotArchiveFileExtension;

class SnapshotArchiveImportResult {
  final bool success;
  final int restoredEmbeddedSampleCount;

  const SnapshotArchiveImportResult({
    required this.success,
    required this.restoredEmbeddedSampleCount,
  });
}

/// Main snapshot service that combines export and import functionality
class SnapshotService {
  final SnapshotExporter _exporter;
  final SnapshotImporter _importer;
  final LibrarySamplesState? _librarySamplesState;
  final SnapshotArchiveService _archiveService;

  SnapshotService._(
    this._exporter,
    this._importer,
    this._librarySamplesState,
    this._archiveService,
  );

  /// Create a snapshot service with the required state objects
  factory SnapshotService({
    required TableState tableState,
    required PlaybackState playbackState,
    required SampleBankState sampleBankState,
    LibrarySamplesState? librarySamplesState,
  }) {
    final exporter = SnapshotExporter(
      tableState: tableState,
      playbackState: playbackState,
      sampleBankState: sampleBankState,
    );
    final importer = SnapshotImporter(
      tableState: tableState,
      playbackState: playbackState,
      sampleBankState: sampleBankState,
    );
    return SnapshotService._(
      exporter,
      importer,
      librarySamplesState,
      const SnapshotArchiveService(),
    );
  }

  /// Export current sequencer state to JSON string
  String exportToJson({
    required String name,
    String? id,
    String? description,
  }) {
    return _exporter.exportToJson(
      name: name,
      id: id,
      description: description,
    );
  }

  /// Import sequencer state from JSON string
  Future<bool> importFromJson(String jsonString) {
    return _importer.importFromJson(jsonString);
  }

  Future<Uint8List> exportToArchiveBytes({
    required String name,
    String? id,
    String? description,
  }) async {
    final snapshotJson = exportToJson(
      name: name,
      id: id,
      description: description,
    );
    final snapshot = json.decode(snapshotJson) as Map<String, dynamic>;
    final embeddedSamples = await _collectEmbeddedSamples(snapshot);
    final snapshotSchemaVersion =
        (snapshot['schema_version'] as num?)?.toInt() ??
            SnapshotExporter.schemaVersion;
    final portableProjectJson =
        const JsonEncoder.withIndent('  ').convert(snapshot);
    return _archiveService.buildArchiveBytes(
      projectJson: portableProjectJson,
      snapshotSchemaVersion: snapshotSchemaVersion,
      embeddedSamples: embeddedSamples,
    );
  }

  Future<SnapshotArchiveImportResult> importFromArchiveBytes(
    Uint8List bytes,
  ) async {
    final librarySamplesState = _librarySamplesState;
    if (librarySamplesState == null) {
      throw StateError(
        'Archive import requires LibrarySamplesState for embedded custom samples.',
      );
    }

    final payload = _archiveService.parseArchiveBytes(bytes);
    if (!validateJson(payload.projectJson)) {
      throw const FormatException(
          'Archive project.json is not a valid snapshot.');
    }

    final metadata = getSnapshotMetadata(payload.projectJson);
    final importFolder = _archiveImportFolderName(metadata?['name'] as String?);
    var restoredEmbeddedSampleCount = 0;
    for (final sample in payload.manifest.embeddedSamples) {
      final sampleBytes = payload.embeddedSampleBytes[sample.sampleId];
      if (sampleBytes == null) {
        throw FormatException(
          'Archive is missing bytes for embedded sample ${sample.sampleId}.',
        );
      }
      final actualDigest = sha256.convert(sampleBytes).toString();
      if (actualDigest != sample.sha256) {
        throw StateError(
          'Embedded sample ${sample.sampleId} failed integrity validation.',
        );
      }
      final registration =
          await librarySamplesState.registerArchivedCustomSample(
        bytes: sampleBytes,
        sampleId: sample.sampleId,
        fileName: sample.fileName,
        folderName: importFolder,
      );
      if (!registration.success) {
        throw StateError(
          registration.errorMessage ??
              'Failed to restore embedded sample ${sample.sampleId}.',
        );
      }
      restoredEmbeddedSampleCount++;
    }

    final success = await importFromJson(payload.projectJson);
    return SnapshotArchiveImportResult(
      success: success,
      restoredEmbeddedSampleCount: restoredEmbeddedSampleCount,
    );
  }

  SnapshotImportReport get lastImportReport => _importer.lastImportReport;

  /// Validate JSON structure
  bool validateJson(String jsonString) {
    return _importer.validateJson(jsonString);
  }

  /// Get snapshot metadata without importing
  Map<String, dynamic>? getSnapshotMetadata(String jsonString) {
    return _importer.getSnapshotMetadata(jsonString);
  }

  bool validateArchiveBytes(Uint8List bytes) {
    return _archiveService.validateArchiveBytes(bytes);
  }

  Future<List<SnapshotArchiveEmbeddedSampleSource>> _collectEmbeddedSamples(
    Map<String, dynamic> snapshot,
  ) async {
    final source = snapshot['source'] as Map<String, dynamic>?;
    final sampleBank = source?['sample_bank'] as Map<String, dynamic>?;
    final samples = sampleBank?['samples'] as List<dynamic>? ?? const [];
    final embeddedSamples = <String, SnapshotArchiveEmbeddedSampleSource>{};

    for (var slot = 0; slot < samples.length; slot++) {
      final sampleData = samples[slot];
      if (sampleData is! Map<String, dynamic>) continue;
      if (sampleData['loaded'] != true) continue;

      final sampleId = sampleData['sample_id'] as String?;
      final filePath = sampleData['file_path'] as String?;
      final resolution = await SampleReferenceResolver.instance.resolve(
        sampleId: sampleId,
        filePathHint: filePath,
      );
      if (resolution.kind == SampleReferenceKind.builtIn) {
        continue;
      }

      final sourcePath = resolution.localPath ?? filePath;
      if (sourcePath == null || sourcePath.isEmpty) {
        throw StateError(
          'Cannot export slot ${_slotLabel(slot)}: sample source path is unavailable.',
        );
      }

      final file = File(sourcePath);
      if (!await file.exists()) {
        throw StateError(
          'Cannot export slot ${_slotLabel(slot)}: source file not found at $sourcePath.',
        );
      }

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        throw StateError(
          'Cannot export slot ${_slotLabel(slot)}: source file is empty.',
        );
      }

      final digest = sha256.convert(bytes).toString();
      final canonicalSampleId =
          LibrarySamplesState.customSampleIdForHash(digest);
      final fileName = _portableFileName(
        sourcePath: sourcePath,
        displayName: sampleData['display_name'] as String?,
        digest: digest,
      );

      embeddedSamples.putIfAbsent(
        canonicalSampleId,
        () => SnapshotArchiveEmbeddedSampleSource(
          sampleId: canonicalSampleId,
          fileName: fileName,
          sha256: digest,
          bytes: bytes,
          originalPath: filePath,
          displayName: sampleData['display_name'] as String?,
        ),
      );

      sampleData['sample_id'] = canonicalSampleId;
      sampleData['file_path'] = null;
      sampleData['display_name'] ??= fileName;
    }

    return embeddedSamples.values.toList(growable: false);
  }

  String _portableFileName({
    required String sourcePath,
    required String digest,
    String? displayName,
  }) {
    final display = displayName?.trim();
    final rawName = (display != null && display.isNotEmpty)
        ? display
        : path.basename(sourcePath);
    final ext = path.extension(rawName).isNotEmpty
        ? path.extension(rawName)
        : path.extension(sourcePath);
    final baseName = path.basenameWithoutExtension(rawName).trim();
    final safeBaseName = baseName.isEmpty
        ? 'sample_${digest.substring(0, 12)}'
        : baseName.replaceAll(RegExp(r'[^\w\-\s\.]'), '_');
    return '$safeBaseName$ext';
  }

  String _archiveImportFolderName(String? projectName) {
    final trimmed = projectName?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return 'Imported';
    }
    final normalized = trimmed
        .replaceAll(RegExp(r'[^\w\-\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return normalized.isEmpty ? 'Imported' : normalized;
  }

  String _slotLabel(int slot) => '${String.fromCharCode(65 + slot)}($slot)';
}

/*
USAGE EXAMPLE:

// 1. Create the service (typically in your app initialization)
final snapshotService = SnapshotService(
  tableState: tableState,
  playbackState: playbackState,
  sampleBankState: sampleBankState,
);

// 2. Export current state
final jsonString = snapshotService.exportToJson(
  name: 'My Awesome Beat',
  description: 'Created with the sequencer',
);

// 3. Save to file or send to server
// await File('snapshot.json').writeAsString(jsonString);

// 4. Import from JSON (when loading from file/server)
final success = await snapshotService.importFromJson(jsonString);
if (success) {
  print('Snapshot imported successfully!');
} else {
  print('Failed to import snapshot');
}

// 5. Validate JSON before importing
if (snapshotService.validateJson(jsonString)) {
  // Safe to import
}

// 6. Get metadata without importing
final metadata = snapshotService.getSnapshotMetadata(jsonString);
print('Snapshot: ${metadata?['name']} by ${metadata?['createdAt']}');
*/
