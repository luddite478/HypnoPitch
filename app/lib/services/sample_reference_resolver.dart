import 'package:path/path.dart' as p;

import '../state/library_samples_state.dart';
import '../utils/local_audio_path.dart';
import 'sample_asset_resolver.dart';

enum SampleReferenceKind {
  builtIn,
  custom,
  localFile,
  unknown,
}

enum SampleResolveFailureReason {
  missingSampleId,
  unknownSampleId,
  missingAssetPath,
  fileNotFound,
}

class SampleReferenceResolution {
  final bool isResolved;
  final SampleReferenceKind kind;
  final String? canonicalSampleId;
  final String? assetPath;
  final String? localPath;
  final SampleResolveFailureReason? failureReason;
  final String? message;

  const SampleReferenceResolution._({
    required this.isResolved,
    required this.kind,
    this.canonicalSampleId,
    this.assetPath,
    this.localPath,
    this.failureReason,
    this.message,
  });

  factory SampleReferenceResolution.resolvedBuiltIn({
    required String canonicalSampleId,
    required String assetPath,
  }) {
    return SampleReferenceResolution._(
      isResolved: true,
      kind: SampleReferenceKind.builtIn,
      canonicalSampleId: canonicalSampleId,
      assetPath: assetPath,
    );
  }

  factory SampleReferenceResolution.resolvedCustom({
    required String canonicalSampleId,
    required String localPath,
  }) {
    return SampleReferenceResolution._(
      isResolved: true,
      kind: SampleReferenceKind.custom,
      canonicalSampleId: canonicalSampleId,
      localPath: localPath,
    );
  }

  factory SampleReferenceResolution.resolvedLocal({
    String? canonicalSampleId,
    required String localPath,
  }) {
    return SampleReferenceResolution._(
      isResolved: true,
      kind: SampleReferenceKind.localFile,
      canonicalSampleId: canonicalSampleId,
      localPath: localPath,
    );
  }

  factory SampleReferenceResolution.failure({
    required SampleResolveFailureReason reason,
    String? message,
  }) {
    return SampleReferenceResolution._(
      isResolved: false,
      kind: SampleReferenceKind.unknown,
      failureReason: reason,
      message: message,
    );
  }
}

class SampleReferenceResolver {
  SampleReferenceResolver._();

  static final SampleReferenceResolver instance = SampleReferenceResolver._();

  final SampleAssetResolver _assetResolver = SampleAssetResolver.instance;

  Future<SampleReferenceResolution> resolve({
    String? sampleId,
    String? filePathHint,
  }) async {
    final normalizedId = sampleId?.trim();
    final normalizedHint = filePathHint?.trim();

    if (normalizedId != null && normalizedId.isNotEmpty) {
      if (LibrarySamplesState.isCustomSampleId(normalizedId)) {
        final localPath = await LibrarySamplesState.resolveCustomSampleIdPath(
          normalizedId,
          filePathHint: normalizedHint,
        );
        if (localPath != null && localPath.isNotEmpty) {
          final canonicalId =
              await LibrarySamplesState.findCustomSampleIdForPath(localPath) ??
                  normalizedId;
          return SampleReferenceResolution.resolvedCustom(
            canonicalSampleId: canonicalId,
            localPath: localPath,
          );
        }
      } else {
        final builtIn = await _assetResolver.resolveBuiltInSample(normalizedId);
        if (builtIn != null) {
          return SampleReferenceResolution.resolvedBuiltIn(
            canonicalSampleId: builtIn.canonicalId,
            assetPath: builtIn.assetPathForLoad,
          );
        }
      }
    }

    if (normalizedHint != null && normalizedHint.isNotEmpty) {
      final localPath = await LocalAudioPath.resolve(normalizedHint);
      if (localPath != null && localPath.isNotEmpty) {
        final resolvedCustomId =
            await LibrarySamplesState.findCustomSampleIdForPath(localPath);
        return SampleReferenceResolution.resolvedLocal(
          canonicalSampleId: resolvedCustomId ?? normalizedId,
          localPath: localPath,
        );
      }

      if (normalizedId != null &&
          normalizedId.isNotEmpty &&
          LibrarySamplesState.isCustomSampleId(normalizedId)) {
        final byName = await LibrarySamplesState.resolveCustomSampleIdPath(
          normalizedId,
          filePathHint: normalizedHint,
        );
        if (byName != null && byName.isNotEmpty) {
          return SampleReferenceResolution.resolvedCustom(
            canonicalSampleId: normalizedId,
            localPath: byName,
          );
        }
      }

      final guessedName = p.basename(normalizedHint);
      if (guessedName.isNotEmpty) {
        final byName = await LocalAudioPath.resolve(guessedName);
        if (byName != null && byName.isNotEmpty) {
          final resolvedCustomId =
              await LibrarySamplesState.findCustomSampleIdForPath(byName);
          return SampleReferenceResolution.resolvedLocal(
            canonicalSampleId: resolvedCustomId ?? normalizedId,
            localPath: byName,
          );
        }
      }
    }

    if (normalizedId == null || normalizedId.isEmpty) {
      return SampleReferenceResolution.failure(
        reason: SampleResolveFailureReason.missingSampleId,
        message: 'Sample id is missing.',
      );
    }

    if (LibrarySamplesState.isCustomSampleId(normalizedId)) {
      return SampleReferenceResolution.failure(
        reason: SampleResolveFailureReason.fileNotFound,
        message: 'Custom sample not found on disk.',
      );
    }

    final builtIn = await _assetResolver.resolveBuiltInSample(normalizedId);
    if (builtIn == null) {
      return SampleReferenceResolution.failure(
        reason: SampleResolveFailureReason.unknownSampleId,
        message: 'Sample id is not present in manifest.',
      );
    }
    if (builtIn.assetPath.isEmpty) {
      return SampleReferenceResolution.failure(
        reason: SampleResolveFailureReason.missingAssetPath,
        message: 'Manifest sample does not have a valid path.',
      );
    }
    return SampleReferenceResolution.resolvedBuiltIn(
      canonicalSampleId: builtIn.canonicalId,
      assetPath: builtIn.assetPathForLoad,
    );
  }
}
