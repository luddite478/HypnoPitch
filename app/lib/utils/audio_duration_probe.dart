import 'package:just_audio/just_audio.dart';

/// One-shot duration probe for local audio files. Caches by [filePath].
class AudioDurationProbe {
  AudioDurationProbe._();

  static final Map<String, double> _cache = {};

  static double? cachedSeconds(String filePath) => _cache[filePath];

  static String _assetCacheKey(String assetPath) => 'asset:$assetPath';

  /// Returns duration in seconds, or null if unavailable.
  static Future<double?> secondsForFilePath(String filePath) async {
    if (_cache.containsKey(filePath)) {
      return _cache[filePath];
    }
    final player = AudioPlayer();
    try {
      await player.setFilePath(filePath);
      Duration? d = player.duration;
      if (d == null || d.inMilliseconds <= 0) {
        try {
          d = await player.durationStream
              .firstWhere((e) => e != null && e.inMilliseconds > 0)
              .timeout(const Duration(seconds: 5));
        } catch (_) {}
      }
      if (d == null || d.inMilliseconds <= 0) {
        return null;
      }
      final sec = d.inMicroseconds / 1000000.0;
      _cache[filePath] = sec;
      return sec;
    } catch (_) {
      return null;
    } finally {
      await player.dispose();
    }
  }

  /// [assetPath] is a Flutter asset key (e.g. `samples/drums/kick.wav`).
  static Future<double?> secondsForBundleAsset(String assetPath) async {
    final key = _assetCacheKey(assetPath);
    if (_cache.containsKey(key)) {
      return _cache[key];
    }
    final player = AudioPlayer();
    try {
      await player.setAsset(assetPath);
      Duration? d = player.duration;
      if (d == null || d.inMilliseconds <= 0) {
        try {
          d = await player.durationStream
              .firstWhere((e) => e != null && e.inMilliseconds > 0)
              .timeout(const Duration(seconds: 5));
        } catch (_) {}
      }
      if (d == null || d.inMilliseconds <= 0) {
        return null;
      }
      final sec = d.inMicroseconds / 1000000.0;
      _cache[key] = sec;
      return sec;
    } catch (_) {
      return null;
    } finally {
      await player.dispose();
    }
  }

  /// Built-in manifest paths use bundle assets; custom library paths are local files.
  static Future<double?> secondsForSampleBrowserPath({
    required String path,
    required bool isCustom,
  }) async {
    if (isCustom) {
      return secondsForFilePath(path);
    }
    return secondsForBundleAsset(path);
  }
}
