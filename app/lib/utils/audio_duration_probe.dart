import 'package:just_audio/just_audio.dart';

/// One-shot duration probe for local audio files. Caches by [filePath].
class AudioDurationProbe {
  AudioDurationProbe._();

  static final Map<String, double> _cache = {};

  static double? cachedSeconds(String filePath) => _cache[filePath];

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
}
