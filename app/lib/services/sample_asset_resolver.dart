import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/log.dart';

class SampleAssetResolver {
  SampleAssetResolver._();

  static final SampleAssetResolver instance = SampleAssetResolver._();
  static const String padPackName = 'samples_pack';
  static const MethodChannel _channel = MethodChannel('hypnopitch/pad');

  Map<String, dynamic>? _samplesManifestCache;
  Map<String, BuiltInSampleResolution>? _builtInAliasesCache;
  String? _cachedAssetPackPath;
  String? _lastAvailabilityMessage;
  Set<String>? _flutterAssetKeySet;
  Future<Set<String>>? _flutterAssetKeysFuture;
  bool _loggedCachedPadPathOnce = false;

  String? get lastAvailabilityMessage => _lastAvailabilityMessage;

  Future<Map<String, dynamic>> loadSamplesManifest() async {
    if (_samplesManifestCache != null) {
      return _samplesManifestCache!;
    }

    final manifestString = await rootBundle.loadString('samples_manifest.json');
    final fullManifest = json.decode(manifestString);
    if (fullManifest is! Map || fullManifest['samples'] is! Map) {
      _samplesManifestCache = {};
      return _samplesManifestCache!;
    }

    _samplesManifestCache =
        Map<String, dynamic>.from(fullManifest['samples'] as Map);
    _builtInAliasesCache = null;
    return _samplesManifestCache!;
  }

  Future<Map<String, BuiltInSampleResolution>> _buildBuiltInAliasMap() async {
    if (_builtInAliasesCache != null) return _builtInAliasesCache!;
    final samplesMap = await loadSamplesManifest();
    _builtInAliasesCache = buildBuiltInAliasMapFromManifest(samplesMap);
    return _builtInAliasesCache!;
  }

  @visibleForTesting
  static Map<String, BuiltInSampleResolution> buildBuiltInAliasMapFromManifest(
    Map<String, dynamic> samplesMap,
  ) {
    final aliases = <String, BuiltInSampleResolution>{};
    for (final entry in samplesMap.entries) {
      final canonicalId = entry.key;
      final raw = entry.value;
      if (raw is! Map) continue;
      final path = raw['path'];
      if (path is! String || path.isEmpty) continue;
      final assetKey =
          raw['asset_key'] is String && (raw['asset_key'] as String).isNotEmpty
              ? raw['asset_key'] as String
              : path;
      final displayName = raw['display_name'] is String &&
              (raw['display_name'] as String).isNotEmpty
          ? raw['display_name'] as String
          : _fallbackDisplayNameFromPath(path);

      void addAlias(String id, String source) {
        if (id.isEmpty) return;
        aliases[id] = BuiltInSampleResolution(
          canonicalId: canonicalId,
          assetPath: path,
          assetKey: assetKey,
          displayName: displayName,
          aliasSource: source,
        );
      }

      addAlias(canonicalId, 'canonical');

      final legacyHash = raw['legacy_hash_12'];
      if (legacyHash is String && legacyHash.isNotEmpty) {
        addAlias(legacyHash, 'legacy_hash_12');
      }

      final aliasList = raw['aliases'];
      if (aliasList is List) {
        for (final value in aliasList) {
          if (value is String && value.isNotEmpty) {
            addAlias(value, 'aliases[]');
          }
        }
      }

      final legacyIds = raw['legacy_ids'];
      if (legacyIds is List) {
        for (final value in legacyIds) {
          if (value is String && value.isNotEmpty) {
            addAlias(value, 'legacy_ids[]');
          }
        }
      }
    }
    return aliases;
  }

  Future<BuiltInSampleResolution?> resolveBuiltInSample(
      String sampleIdOrAlias) async {
    final aliases = await _buildBuiltInAliasMap();
    return aliases[sampleIdOrAlias];
  }

  Future<String?> resolveAssetPathFromSampleId(String sampleId) async {
    final resolved = await resolveBuiltInSample(sampleId);
    return resolved?.assetPathForLoad;
  }

  static String _fallbackDisplayNameFromPath(String path) {
    final base = p.basenameWithoutExtension(path);
    return base.trim().isEmpty ? p.basename(path) : base;
  }

  Future<bool> ensureBuiltInSamplesReady() async {
    if (!Platform.isAndroid) {
      _lastAvailabilityMessage = null;
      return true;
    }

    final packPath = await _resolveAssetPackPath();
    if (packPath == null || packPath.isEmpty) {
      _lastAvailabilityMessage =
          'Built-in samples are still preparing on this Android device. Please retry in a few seconds.';
      Log.d('📦  install-time pack is not available yet');
      return false;
    }

    final sampleRoot = Directory(p.join(packPath, 'samples'));
    if (!await sampleRoot.exists()) {
      _lastAvailabilityMessage =
          'Built-in samples pack is missing files. Reinstall from Play to recover.';
      Log.d('❌  samples directory missing in pack: ${sampleRoot.path}');
      return false;
    }

    _lastAvailabilityMessage = null;
    return true;
  }

  Future<Uint8List?> loadAudioBytes(String assetPath) async {
    Log.d(
      '🔎 [SAMPLE_ASSET_RESOLVER] loadAudioBytes start path=$assetPath '
      'os=${Platform.operatingSystem}',
    );

    if (Platform.isAndroid && assetPath.startsWith('samples/')) {
      final packPath = await _resolveAssetPackPath();
      final padUsable = packPath != null && packPath.isNotEmpty;
      Log.d(
        '🔎 [SAMPLE_ASSET_RESOLVER] PAD usable=$padUsable '
        'packPath=${packPath ?? "null"}',
      );

      if (padUsable) {
        final filePath = p.join(packPath, assetPath);
        final file = File(filePath);
        final exists = await file.exists();
        Log.d(
          '🔎 [SAMPLE_ASSET_RESOLVER] PAD file exists=$exists path=$filePath',
        );
        if (exists) {
          final len = await file.length();
          Log.d(
            '🔎 [SAMPLE_ASSET_RESOLVER] reading from PAD len=$len bytes',
          );
          return await file.readAsBytes();
        }
        Log.d('❌  Missing packed sample file: $filePath');
      } else {
        Log.d(
          '📦  Falling back to rootBundle for $assetPath '
          '(PAD path null/empty — typical for flutter run / plain APK)',
        );
      }

      final nativeBytes = await _loadAudioBytesViaNativeAssetAccess(assetPath);
      if (nativeBytes != null) {
        Log.d(
          '🔎 [SAMPLE_ASSET_RESOLVER] native asset access OK '
          'bytes=${nativeBytes.length}',
        );
        return nativeBytes;
      }
    }

    try {
      final data = await _loadRootBundleBytesWithIosFallbacks(assetPath);
      Log.d(
        '🔎 [SAMPLE_ASSET_RESOLVER] rootBundle OK bytes=${data.lengthInBytes}',
      );
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (e, st) {
      Log.d('❌ [SAMPLE_ASSET_RESOLVER] rootBundle.load failed: $e');
      Log.d('🔎 [SAMPLE_ASSET_RESOLVER] stack: $st');
      await _logFlutterAssetBundleDiagnostics(assetPath);
      rethrow;
    }
  }

  /// iOS has seen cases where [AssetManifest] lists a key but the first
  /// [rootBundle.load] fails (spaces / encoding). Try alternate keys.
  Future<ByteData> _loadRootBundleBytesWithIosFallbacks(
      String assetPath) async {
    final keys = <String>{assetPath};
    if (Platform.isIOS) {
      final decoded = Uri.decodeFull(assetPath);
      if (decoded != assetPath) {
        keys.add(decoded);
      }
      if (assetPath.contains(' ')) {
        keys.add(assetPath.replaceAll(' ', '%20'));
      }
      final bySegment = assetPath.split('/').map(Uri.encodeComponent).join('/');
      if (bySegment != assetPath) {
        keys.add(bySegment);
      }
      final bySegmentDecoded = Uri.decodeFull(bySegment);
      if (bySegmentDecoded != bySegment) {
        keys.add(bySegmentDecoded);
      }
    }

    Object? lastError;
    StackTrace? lastStack;
    for (final key in keys) {
      try {
        Log.d('🔎 [SAMPLE_ASSET_RESOLVER] rootBundle.load("$key") …');
        return await rootBundle.load(key);
      } catch (e, st) {
        lastError = e;
        lastStack = st;
        Log.d(
          '🔎 [SAMPLE_ASSET_RESOLVER] rootBundle.load try failed key="$key": $e',
        );
      }
    }
    Error.throwWithStackTrace(lastError!, lastStack ?? StackTrace.empty);
  }

  Future<Uint8List?> _loadAudioBytesViaNativeAssetAccess(
      String assetPath) async {
    try {
      Log.d(
        '🔎 [SAMPLE_ASSET_RESOLVER] trying native readAssetBytes for $assetPath',
      );
      final bytes = await _channel.invokeMethod<Uint8List>(
        'readAssetBytes',
        {
          'packName': padPackName,
          'assetPath': assetPath,
        },
      );
      if (bytes == null || bytes.isEmpty) {
        Log.d(
          '🔎 [SAMPLE_ASSET_RESOLVER] native readAssetBytes returned null/empty',
        );
        return null;
      }
      return bytes;
    } catch (e) {
      Log.d('❌ [SAMPLE_ASSET_RESOLVER] native readAssetBytes failed: $e');
      return null;
    }
  }

  Future<String?> copyAssetToTempFile(String assetPath,
      {String prefix = 'sample_'}) async {
    try {
      final bytes = await loadAudioBytes(assetPath);
      if (bytes == null) return null;

      final tempDir = await getTemporaryDirectory();
      final fileName = p.basename(assetPath);
      final tempPath = p.join(tempDir.path, '$prefix$fileName');
      final tempFile = File(tempPath);
      await tempFile.writeAsBytes(bytes, flush: true);
      return tempPath;
    } catch (e) {
      Log.d('❌ [SAMPLE_ASSET_RESOLVER] Failed to copy $assetPath: $e');
      return null;
    }
  }

  Future<String?> _resolveAssetPackPath() async {
    if (_cachedAssetPackPath != null && _cachedAssetPackPath!.isNotEmpty) {
      if (!_loggedCachedPadPathOnce) {
        _loggedCachedPadPathOnce = true;
        Log.d(
          '🔎 [SAMPLE_ASSET_RESOLVER] PAD cache hit path=$_cachedAssetPackPath',
        );
      }
      return _cachedAssetPackPath;
    }

    try {
      Log.d(
        '🔎 [SAMPLE_ASSET_RESOLVER] invoking MethodChannel '
        'hypnopitch/pad getAssetPackPath pack=$padPackName',
      );
      final packPath = await _channel.invokeMethod<String>(
        'getAssetPackPath',
        {'packName': padPackName},
      );
      if (packPath != null && packPath.isNotEmpty) {
        _cachedAssetPackPath = packPath;
      }
      Log.d('📦  Asset pack path: ${packPath ?? "null"}');
      return packPath;
    } catch (e, st) {
      Log.d('❌  getAssetPackPath failed: $e');
      Log.d('🔎 [SAMPLE_ASSET_RESOLVER] getAssetPackPath stack: $st');
      return null;
    }
  }

  Future<Set<String>> _loadFlutterAssetKeySet() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      return manifest.listAssets().toSet();
    } catch (e) {
      Log.d(
        '❌ [SAMPLE_ASSET_RESOLVER] AssetManifest.loadFromAssetBundle failed: $e',
      );
      return {};
    }
  }

  Future<Set<String>> _flutterAssetKeys() async {
    if (_flutterAssetKeySet != null) return _flutterAssetKeySet!;
    _flutterAssetKeysFuture ??= _loadFlutterAssetKeySet();
    final keys = await _flutterAssetKeysFuture!;
    _flutterAssetKeySet = keys;
    return keys;
  }

  /// Runs when [rootBundle.load] throws — explains PAD-only vs bundled Flutter assets.
  Future<void> _logFlutterAssetBundleDiagnostics(String assetPath) async {
    final keys = await _flutterAssetKeys();
    final baseName = p.basename(assetPath);
    final samplesCount = keys.where((k) => k.startsWith('samples/')).length;
    final exact = keys.contains(assetPath);
    Log.d(
      '🔎 [SAMPLE_ASSET_RESOLVER] Flutter AssetManifest: '
      'totalKeys=${keys.length} samples/* keys=$samplesCount '
      'exactMatchForRequest=$exact',
    );
    if (!exact) {
      final sameFileName =
          keys.where((k) => k.endsWith(baseName)).take(8).toList();
      if (sameFileName.isNotEmpty) {
        Log.d(
          '🔎 [SAMPLE_ASSET_RESOLVER] manifest paths ending with '
          'same filename (max 8): $sameFileName',
        );
      }
      final clickPrefix = keys
          .where((k) => k.startsWith('samples/noise/click/'))
          .take(6)
          .toList();
      Log.d(
        '🔎 [SAMPLE_ASSET_RESOLVER] sample keys under samples/noise/click/ '
        '(max 6): $clickPrefix',
      );
    }
    Log.d(
      '🔎 [SAMPLE_ASSET_RESOLVER] hint: If samples/* count is 0, this build '
      'likely used pubspec without samples/ (PAD release). Install via '
      'bundletool from AAB with samples_pack, or use flutter run / debug APK '
      'with samples/ still listed in pubspec.yaml.',
    );
  }
}

class BuiltInSampleResolution {
  final String canonicalId;
  final String assetPath;
  final String assetKey;
  final String displayName;
  final String aliasSource;

  String get assetPathForLoad => Platform.isIOS ? assetKey : assetPath;

  const BuiltInSampleResolution({
    required this.canonicalId,
    required this.assetPath,
    required this.assetKey,
    required this.displayName,
    required this.aliasSource,
  });
}
