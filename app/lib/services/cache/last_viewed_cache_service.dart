import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Service for tracking when user last viewed each project
/// Used to determine if a project has been updated by collaborators since last view
class LastViewedCacheService {
  static const String _cacheDir = 'cache/last_viewed';
  
  /// Save last viewed timestamp for a thread
  static Future<bool> saveLastViewed(String threadId, DateTime timestamp) async {
    try {
      final file = await _getFile(threadId);
      final data = {
        'thread_id': threadId,
        'last_viewed_at': timestamp.toIso8601String(),
      };
      await file.writeAsString(json.encode(data));
      debugPrint('📅 [LAST_VIEWED] Saved last viewed for thread $threadId: $timestamp');
      return true;
    } catch (e) {
      debugPrint('❌ [LAST_VIEWED] Error saving last viewed: $e');
      return false;
    }
  }
  
  /// Get last viewed timestamp for a thread
  static Future<DateTime?> getLastViewed(String threadId) async {
    try {
      final file = await _getFile(threadId);
      if (!await file.exists()) {
        return null;
      }
      
      final contents = await file.readAsString();
      final data = json.decode(contents) as Map<String, dynamic>;
      final timestamp = DateTime.parse(data['last_viewed_at'] as String);
      
      return timestamp;
    } catch (e) {
      debugPrint('⚠️ [LAST_VIEWED] Error reading last viewed: $e');
      return null;
    }
  }
  
  /// Clear last viewed timestamp for a thread
  static Future<void> clearLastViewed(String threadId) async {
    try {
      final file = await _getFile(threadId);
      if (await file.exists()) {
        await file.delete();
        debugPrint('🗑️ [LAST_VIEWED] Cleared last viewed for thread $threadId');
      }
    } catch (e) {
      debugPrint('⚠️ [LAST_VIEWED] Error clearing last viewed: $e');
    }
  }
  
  /// Clear all last viewed timestamps
  static Future<void> clearAll() async {
    try {
      final dir = await _getCacheDirectory();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        debugPrint('🗑️ [LAST_VIEWED] Cleared all last viewed timestamps');
      }
    } catch (e) {
      debugPrint('⚠️ [LAST_VIEWED] Error clearing all: $e');
    }
  }
  
  /// Get file for a specific thread
  static Future<File> _getFile(String threadId) async {
    final dir = await _getCacheDirectory();
    return File('${dir.path}/$threadId.json');
  }
  
  /// Get cache directory
  static Future<Directory> _getCacheDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/$_cacheDir');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}


