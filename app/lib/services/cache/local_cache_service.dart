import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// Base service for local file-based caching
/// Provides common file I/O operations for all cache services
class LocalCacheService {
  static String? _cacheBasePath;

  /// Get the base cache directory path
  static Future<String> getCacheBasePath() async {
    if (_cacheBasePath != null) return _cacheBasePath!;

    final appName = dotenv.env['APP_NAME'] ?? 'app';
    String baseDir;

    if (Platform.isAndroid) {
      // Use app-specific storage on Android to avoid scoped storage permission errors.
      final appDocDir = await getApplicationDocumentsDirectory();
      baseDir = appDocDir.path;
    } else if (Platform.isIOS) {
      baseDir = path.join(Directory.systemTemp.path, appName);
    } else if (Platform.isMacOS) {
      baseDir = '${Platform.environment['HOME']}/Documents/$appName';
    } else if (Platform.isWindows) {
      baseDir = '${Platform.environment['USERPROFILE']}\\Documents\\$appName';
    } else {
      baseDir = path.join(Directory.systemTemp.path, appName);
    }

    _cacheBasePath = path.join(baseDir, 'cache');
    final dir = Directory(_cacheBasePath!);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    return _cacheBasePath!;
  }

  /// Get a file handle for a cache file (creates parent directories if needed)
  static Future<File> getCacheFile(String relativePath) async {
    final basePath = await getCacheBasePath();
    final filePath = path.join(basePath, relativePath);
    
    // Ensure parent directory exists
    final dir = Directory(path.dirname(filePath));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    return File(filePath);
  }

  /// Get a directory handle for a cache directory
  static Future<Directory> getCacheDirectory(String relativePath) async {
    final basePath = await getCacheBasePath();
    final dirPath = path.join(basePath, relativePath);
    final dir = Directory(dirPath);
    
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    return dir;
  }

  /// Read JSON from cache file
  /// Returns null if file doesn't exist or is invalid
  static Future<Map<String, dynamic>?> readJson(String relativePath) async {
    try {
      final file = await getCacheFile(relativePath);
      if (!await file.exists()) {
        return null;
      }

      final contents = await file.readAsString();
      return jsonDecode(contents) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('❌ [CACHE] Error reading JSON from $relativePath: $e');
      return null;
    }
  }

  /// Write JSON to cache file
  static Future<bool> writeJson(
    String relativePath,
    Map<String, dynamic> data,
  ) async {
    try {
      final file = await getCacheFile(relativePath);
      await file.writeAsString(jsonEncode(data));
      return true;
    } catch (e) {
      debugPrint('❌ [CACHE] Error writing JSON to $relativePath: $e');
      return false;
    }
  }

  /// Delete a cache file
  static Future<bool> deleteFile(String relativePath) async {
    try {
      final file = await getCacheFile(relativePath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ [CACHE] Error deleting file $relativePath: $e');
      return false;
    }
  }

  /// Check if a cache file exists
  static Future<bool> fileExists(String relativePath) async {
    try {
      final file = await getCacheFile(relativePath);
      return await file.exists();
    } catch (e) {
      return false;
    }
  }

  /// List all files in a cache directory
  static Future<List<File>> listFiles(String relativePath) async {
    try {
      final dir = await getCacheDirectory(relativePath);
      if (!await dir.exists()) {
        return [];
      }

      final entities = await dir.list().toList();
      return entities.whereType<File>().toList();
    } catch (e) {
      debugPrint('❌ [CACHE] Error listing files in $relativePath: $e');
      return [];
    }
  }

  /// Get total size of cache directory in bytes
  static Future<int> getDirectorySize(String relativePath) async {
    try {
      final dir = await getCacheDirectory(relativePath);
      if (!await dir.exists()) {
        return 0;
      }

      int totalSize = 0;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
      return totalSize;
    } catch (e) {
      debugPrint('❌ [CACHE] Error calculating directory size: $e');
      return 0;
    }
  }

  /// Clear entire cache directory
  static Future<void> clearCache() async {
    try {
      final basePath = await getCacheBasePath();
      final dir = Directory(basePath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
      }
      _cacheBasePath = null;
      debugPrint('✅ [CACHE] Entire cache cleared');
    } catch (e) {
      debugPrint('❌ [CACHE] Error clearing cache: $e');
    }
  }

  /// Format bytes for display
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

