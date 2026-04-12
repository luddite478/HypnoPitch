import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

const String snapshotArchiveFileExtension = 'hypnopattern';

class SnapshotArchiveEmbeddedSampleSource {
  final String sampleId;
  final String fileName;
  final String sha256;
  final Uint8List bytes;
  final String? originalPath;
  final String? displayName;

  const SnapshotArchiveEmbeddedSampleSource({
    required this.sampleId,
    required this.fileName,
    required this.sha256,
    required this.bytes,
    this.originalPath,
    this.displayName,
  });

  String get archivePath {
    final ext = p.extension(fileName).toLowerCase();
    return 'samples/$sha256$ext';
  }
}

class SnapshotArchiveEmbeddedSample {
  final String sampleId;
  final String archivePath;
  final String fileName;
  final String sha256;
  final String? originalPath;
  final String? displayName;

  const SnapshotArchiveEmbeddedSample({
    required this.sampleId,
    required this.archivePath,
    required this.fileName,
    required this.sha256,
    this.originalPath,
    this.displayName,
  });

  factory SnapshotArchiveEmbeddedSample.fromJson(Map<String, dynamic> json) {
    return SnapshotArchiveEmbeddedSample(
      sampleId: json['sample_id'] as String,
      archivePath: json['archive_path'] as String,
      fileName: json['file_name'] as String,
      sha256: json['sha256'] as String,
      originalPath: json['original_path'] as String?,
      displayName: json['display_name'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sample_id': sampleId,
      'archive_path': archivePath,
      'file_name': fileName,
      'sha256': sha256,
      'original_path': originalPath,
      'display_name': displayName,
    };
  }
}

class SnapshotArchiveManifest {
  static const int currentFormatVersion = 1;

  final int archiveFormatVersion;
  final int snapshotSchemaVersion;
  final String createdAt;
  final String? appVersion;
  final List<SnapshotArchiveEmbeddedSample> embeddedSamples;

  const SnapshotArchiveManifest({
    required this.archiveFormatVersion,
    required this.snapshotSchemaVersion,
    required this.createdAt,
    required this.embeddedSamples,
    this.appVersion,
  });

  factory SnapshotArchiveManifest.fromJson(Map<String, dynamic> json) {
    final rawEmbeddedSamples =
        json['embedded_samples'] as List<dynamic>? ?? const [];
    final embeddedSamples = <SnapshotArchiveEmbeddedSample>[];
    for (final item in rawEmbeddedSamples) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException(
            'Archive manifest has an invalid sample entry.');
      }
      embeddedSamples.add(SnapshotArchiveEmbeddedSample.fromJson(item));
    }
    return SnapshotArchiveManifest(
      archiveFormatVersion:
          (json['archive_format_version'] as num?)?.toInt() ?? 0,
      snapshotSchemaVersion:
          (json['snapshot_schema_version'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at'] as String? ?? '',
      appVersion: json['app_version'] as String?,
      embeddedSamples: embeddedSamples,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'archive_format_version': archiveFormatVersion,
      'snapshot_schema_version': snapshotSchemaVersion,
      'created_at': createdAt,
      'app_version': appVersion,
      'embedded_samples':
          embeddedSamples.map((sample) => sample.toJson()).toList(),
    };
  }
}

class SnapshotArchiveImportPayload {
  final String projectJson;
  final SnapshotArchiveManifest manifest;
  final Map<String, Uint8List> embeddedSampleBytes;

  const SnapshotArchiveImportPayload({
    required this.projectJson,
    required this.manifest,
    required this.embeddedSampleBytes,
  });
}

class SnapshotArchiveService {
  static const String manifestPath = 'manifest.json';
  static const String projectPath = 'project.json';

  const SnapshotArchiveService();

  Uint8List buildArchiveBytes({
    required String projectJson,
    required int snapshotSchemaVersion,
    required List<SnapshotArchiveEmbeddedSampleSource> embeddedSamples,
    String? appVersion,
  }) {
    final archive = Archive();
    final manifest = SnapshotArchiveManifest(
      archiveFormatVersion: SnapshotArchiveManifest.currentFormatVersion,
      snapshotSchemaVersion: snapshotSchemaVersion,
      createdAt: DateTime.now().toUtc().toIso8601String(),
      appVersion: appVersion,
      embeddedSamples: embeddedSamples
          .map(
            (sample) => SnapshotArchiveEmbeddedSample(
              sampleId: sample.sampleId,
              archivePath: sample.archivePath,
              fileName: sample.fileName,
              sha256: sample.sha256,
              originalPath: sample.originalPath,
              displayName: sample.displayName,
            ),
          )
          .toList(growable: false),
    );

    archive.addFile(ArchiveFile.string(projectPath, projectJson));
    archive.addFile(
      ArchiveFile.string(
        manifestPath,
        const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
      ),
    );
    for (final sample in embeddedSamples) {
      archive.addFile(ArchiveFile.bytes(sample.archivePath, sample.bytes));
    }

    return ZipEncoder().encodeBytes(archive);
  }

  SnapshotArchiveImportPayload parseArchiveBytes(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final filesByPath = <String, ArchiveFile>{};
    for (final entry in archive) {
      if (entry.isFile) {
        final normalizedPath = _normalizeArchivePath(entry.name);
        if (normalizedPath == null) {
          throw const FormatException(
              'Archive contains an invalid entry path.');
        }
        if (filesByPath.containsKey(normalizedPath)) {
          throw FormatException(
              'Archive contains duplicate entry: $normalizedPath');
        }
        filesByPath[normalizedPath] = entry;
      }
    }

    final manifestFile = filesByPath[manifestPath];
    final projectFile = filesByPath[projectPath];
    if (manifestFile == null || projectFile == null) {
      throw const FormatException(
        'Archive must contain manifest.json and project.json.',
      );
    }

    final manifestJson = utf8.decode(manifestFile.content);
    final manifestData = json.decode(manifestJson);
    if (manifestData is! Map<String, dynamic>) {
      throw const FormatException(
          'Archive manifest is not a valid JSON object.');
    }
    final manifest = SnapshotArchiveManifest.fromJson(manifestData);
    if (manifest.archiveFormatVersion !=
        SnapshotArchiveManifest.currentFormatVersion) {
      throw FormatException(
        'Unsupported archive format version: ${manifest.archiveFormatVersion}.',
      );
    }

    final embeddedSampleBytes = <String, Uint8List>{};
    final sampleIds = <String>{};
    for (final sample in manifest.embeddedSamples) {
      if (!sampleIds.add(sample.sampleId)) {
        throw FormatException(
          'Archive manifest contains a duplicate sample id: ${sample.sampleId}',
        );
      }
      final normalizedPath = _normalizeArchivePath(sample.archivePath);
      if (normalizedPath == null) {
        throw FormatException(
          'Archive sample path is invalid: ${sample.archivePath}',
        );
      }
      final archiveFile = filesByPath[normalizedPath];
      if (archiveFile == null) {
        throw FormatException(
            'Archive is missing embedded sample: $normalizedPath');
      }
      embeddedSampleBytes[sample.sampleId] = archiveFile.content;
    }

    return SnapshotArchiveImportPayload(
      projectJson: utf8.decode(projectFile.content),
      manifest: manifest,
      embeddedSampleBytes: embeddedSampleBytes,
    );
  }

  bool validateArchiveBytes(Uint8List bytes) {
    try {
      parseArchiveBytes(bytes);
      return true;
    } catch (_) {
      return false;
    }
  }

  String? _normalizeArchivePath(String rawPath) {
    final normalized = p.posix.normalize(rawPath.replaceAll('\\', '/'));
    if (normalized.isEmpty ||
        normalized.startsWith('/') ||
        normalized == '.' ||
        normalized.startsWith('../') ||
        normalized.contains('/../')) {
      return null;
    }
    return normalized;
  }
}
