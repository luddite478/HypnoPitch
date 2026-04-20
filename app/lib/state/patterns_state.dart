import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/pattern.dart';
import '../models/checkpoint.dart';
import '../services/local_pattern_service.dart';
import '../services/local_checkpoint_service.dart';
import '../services/cache/working_state_cache_service.dart';
import '../utils/app_colors.dart';
import 'sequencer/sample_bank.dart';

/// Local-only state for managing patterns and checkpoints
/// Replaces ThreadsState with simplified local storage
class PatternsState extends ChangeNotifier {
  static const bool _enableDemoStarterPatterns = bool.fromEnvironment(
    'ENABLE_DEMO_PATTERNS',
    defaultValue: false,
  );
  static const Set<String> _demoStarterNames = {
    'Starter - Night Drive',
    'Starter - Alley Bounce',
    'Starter - Dusty Swing',
    'Starter - Broken Metro',
  };

  // Data
  Pattern? _activePattern;
  List<Pattern> _patterns = [];
  Map<String, List<Checkpoint>> _checkpointsByPattern = {};
  
  // UI state
  bool _isLoading = false;
  String? _error;
  bool _hasLoaded = false;
  
  final _uuid = const Uuid();

  /// Sequencer screens register here so [setActivePattern] can flush the current
  /// draft to disk **before** the active id changes (shared [TableState]).
  final List<Future<void> Function()> _beforeActivePatternSwitch = [];
  
  // Ensure patterns are always sorted by most recently updated first
  void _sortPatternsByUpdatedAtDesc() {
    _patterns.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }
  
  // Getters
  Pattern? get activePattern => _activePattern;
  List<Pattern> get patterns => List.unmodifiable(_patterns);
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasLoaded => _hasLoaded;
  /// Get checkpoints for a specific pattern
  List<Checkpoint> getCheckpoints(String patternId) {
    return List.unmodifiable(_checkpointsByPattern[patternId] ?? []);
  }
  
  /// Get checkpoints for active pattern
  List<Checkpoint> get activeCheckpoints {
    if (_activePattern == null) return [];
    return getCheckpoints(_activePattern!.id);
  }
  
  @override
  void dispose() {
    super.dispose();
  }
  
  // ============================================================================
  // Pattern Management
  // ============================================================================
  
  /// Load all patterns from local storage
  Future<void> loadPatterns() async {
    if (_hasLoaded) {
      debugPrint('📦 [PATTERNS_STATE] Already loaded');
      return;
    }
    
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();
      
      _patterns = await LocalPatternService.loadPatterns();
      if (_enableDemoStarterPatterns) {
        await _seedStarterPatternsIfNeeded();
      } else {
        _hideDemoPatternsFromList();
      }
      _sortPatternsByUpdatedAtDesc();
      _hasLoaded = true;
      
      debugPrint('📦 [PATTERNS_STATE] Loaded ${_patterns.length} patterns');
    } catch (e) {
      _error = 'Failed to load patterns: $e';
      debugPrint('❌ [PATTERNS_STATE] Error loading patterns: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Seed 4 starter patterns when app storage is empty.
  Future<void> _seedStarterPatternsIfNeeded() async {
    if (_patterns.isNotEmpty) {
      return;
    }

    final seedDefinitions = <Map<String, dynamic>>[
      {
        'name': 'Starter - Night Drive',
        'section_steps': <int>[32], // LENGTH = 1
        'seed': 1701,
        'bpm': 112,
        'layers': <int>[4, 4, 4, 4, 0],
        'kick': <int>[0, 8, 16, 24, 28],
        'snare': <int>[8, 24],
        'closed_hat': <int>[2, 6, 10, 14, 18, 22, 26, 30],
        'open_hat': <int>[15, 31],
        'perc': <int>[12, 20, 27],
        'tom': <int>[11, 23],
        'ride': <int>[4, 20],
        'clap': <int>[8, 24],
        'shaker': <int>[1, 5, 9, 13, 17, 21, 25, 29],
      },
      {
        'name': 'Starter - Alley Bounce',
        'section_steps': <int>[16, 16], // LENGTH = 2
        'seed': 1702,
        'bpm': 126,
        'layers': <int>[5, 3, 4, 4, 0],
        'kick': <int>[0, 5, 11, 16, 21, 27, 30],
        'snare': <int>[8, 24],
        'closed_hat': <int>[1, 3, 7, 9, 13, 15, 17, 19, 23, 25, 29, 31],
        'open_hat': <int>[12, 20, 28],
        'perc': <int>[6, 14, 22, 26],
        'tom': <int>[19, 27],
        'ride': <int>[4, 12, 20, 28],
        'clap': <int>[8, 24, 26],
        'shaker': <int>[2, 6, 10, 14, 18, 22, 26, 30],
      },
      {
        'name': 'Starter - Dusty Swing',
        'section_steps': <int>[16, 16, 16, 16, 16], // LENGTH = 5
        'seed': 1703,
        'bpm': 94,
        'layers': <int>[3, 5, 4, 4, 0],
        'kick': <int>[0, 7, 12, 16, 23, 28, 32, 39, 44],
        'snare': <int>[12, 28, 44],
        'closed_hat': <int>[2, 5, 9, 14, 18, 21, 25, 30, 34, 37, 41, 46],
        'open_hat': <int>[15, 31, 47],
        'perc': <int>[10, 19, 27, 35, 43],
        'tom': <int>[11, 26, 42],
        'ride': <int>[6, 22, 38],
        'clap': <int>[12, 28, 44],
        'shaker': <int>[3, 8, 13, 19, 24, 29, 35, 40, 45],
      },
      {
        'name': 'Starter - Broken Metro',
        'section_steps': <int>[16, 16, 16, 16], // LENGTH = 4
        'seed': 1704,
        'bpm': 132,
        'layers': <int>[4, 4, 5, 3, 0],
        'kick': <int>[0, 6, 10, 16, 22, 28, 33, 38, 42, 48, 54, 60],
        'snare': <int>[16, 32, 48],
        'closed_hat': <int>[
          1, 3, 5, 7, 9, 11, 13, 15,
          17, 19, 21, 23, 25, 27, 29, 31,
          35, 37, 39, 41, 43, 45, 47, 49,
          51, 53, 55, 57, 59, 61, 63,
        ],
        'open_hat': <int>[12, 28, 44, 60],
        'perc': <int>[14, 26, 40, 52, 58],
        'tom': <int>[30, 46, 62],
        'ride': <int>[4, 20, 36, 52],
        'clap': <int>[16, 32, 48],
        'shaker': <int>[2, 6, 10, 14, 18, 22, 26, 30, 34, 38, 42, 46, 50, 54, 58, 62],
      },
    ];

    final now = DateTime.now();
    int seededCount = 0;

    for (int i = 0; i < seedDefinitions.length; i++) {
      final def = seedDefinitions[i];
      final pattern = Pattern(
        id: _uuid.v4(),
        name: def['name'] as String,
        createdAt: now.subtract(Duration(minutes: (seedDefinitions.length - i) * 3)),
        updatedAt: now.subtract(Duration(minutes: seedDefinitions.length - i)),
        checkpointIds: const [],
        metadata: const {'demo_seed': true},
      );

      final saved = await LocalPatternService.savePattern(pattern);
      if (!saved) {
        continue;
      }

      final snapshot = _buildStarterSnapshot(
        name: pattern.name,
        sectionStepCounts: def['section_steps'] as List<int>,
        seed: def['seed'] as int,
        bpm: def['bpm'] as int,
        layers: def['layers'] as List<int>,
        kickSteps: def['kick'] as List<int>,
        snareSteps: def['snare'] as List<int>,
        closedHatSteps: def['closed_hat'] as List<int>,
        openHatSteps: def['open_hat'] as List<int>,
        percSteps: def['perc'] as List<int>,
        tomSteps: def['tom'] as List<int>,
        rideSteps: def['ride'] as List<int>,
        clapSteps: def['clap'] as List<int>,
        shakerSteps: def['shaker'] as List<int>,
      );

      await WorkingStateCacheService.saveWorkingState(pattern.id, snapshot);
      seededCount++;
    }

    _patterns = await LocalPatternService.loadPatterns();
    _hideDemoPatternsFromList();
    debugPrint('🌱 [PATTERNS_STATE] Seeded $seededCount starter patterns');
  }

  void _hideDemoPatternsFromList() {
    _patterns = _patterns.where((p) => !_isDemoPattern(p)).toList();
  }

  bool _isDemoPattern(Pattern pattern) {
    final isTaggedDemo = pattern.metadata?['demo_seed'] == true;
    return isTaggedDemo || _demoStarterNames.contains(pattern.name);
  }

  Map<String, dynamic> _buildStarterSnapshot({
    required String name,
    required List<int> sectionStepCounts,
    required int seed,
    required int bpm,
    required List<int> layers,
    required List<int> kickSteps,
    required List<int> snareSteps,
    required List<int> closedHatSteps,
    required List<int> openHatSteps,
    required List<int> percSteps,
    required List<int> tomSteps,
    required List<int> rideSteps,
    required List<int> clapSteps,
    required List<int> shakerSteps,
  }) {
    const totalCols = 16;
    final rng = Random(seed);
    final sections = sectionStepCounts.where((s) => s > 0).toList();
    final totalSteps = sections.fold<int>(0, (sum, value) => sum + value);
    final kickSet = kickSteps.toSet();
    final snareSet = snareSteps.toSet();
    final closedHatSet = closedHatSteps.toSet();
    final openHatSet = openHatSteps.toSet();
    final percSet = percSteps.toSet();
    final tomSet = tomSteps.toSet();
    final rideSet = rideSteps.toSet();
    final clapSet = clapSteps.toSet();
    final shakerSet = shakerSteps.toSet();

    final tableCells = List.generate(
      totalSteps,
      (_) => List.generate(
        totalCols,
        (_) => {
          'sample_slot': -1,
          'settings': {'volume': -1.0, 'pitch': -1.0},
        },
      ),
    );

    final kickCols = <int>[0, 1, 2];
    final snareCols = <int>[3, 4, 5];
    final closedHatCols = <int>[6, 7, 8];
    final openHatCols = <int>[9, 10];
    final percCols = <int>[11, 12];
    final tomCols = <int>[13];
    final rideCols = <int>[14];
    final fxCols = <int>[15];

    void placeHit({
      required int step,
      required int slot,
      required List<int> preferredCols,
      double duplicateChance = 0.0,
    }) {
      if (step < 0 || step >= totalSteps) return;
      final primaryCol = preferredCols[rng.nextInt(preferredCols.length)];
      tableCells[step][primaryCol]['sample_slot'] = slot;

      if (duplicateChance > 0 && rng.nextDouble() < duplicateChance) {
        final secondaryCol = preferredCols[rng.nextInt(preferredCols.length)];
        tableCells[step][secondaryCol]['sample_slot'] = slot;
      }
    }

    for (int step = 0; step < totalSteps; step++) {
      if (kickSet.contains(step)) {
        placeHit(step: step, slot: 0, preferredCols: kickCols, duplicateChance: 0.12);
      }
      if (snareSet.contains(step)) {
        placeHit(step: step, slot: 1, preferredCols: snareCols, duplicateChance: 0.08);
      }
      if (closedHatSet.contains(step)) {
        placeHit(step: step, slot: 2, preferredCols: closedHatCols, duplicateChance: 0.15);
      }
      if (openHatSet.contains(step)) {
        placeHit(step: step, slot: 3, preferredCols: openHatCols, duplicateChance: 0.05);
      }
      if (percSet.contains(step)) {
        placeHit(step: step, slot: 4, preferredCols: percCols, duplicateChance: 0.10);
      }
      if (tomSet.contains(step)) {
        placeHit(step: step, slot: 5, preferredCols: tomCols);
      }
      if (rideSet.contains(step)) {
        placeHit(step: step, slot: 6, preferredCols: rideCols, duplicateChance: 0.05);
      }
      if (clapSet.contains(step)) {
        placeHit(step: step, slot: 7, preferredCols: snareCols, duplicateChance: 0.05);
      }
      if (shakerSet.contains(step)) {
        placeHit(step: step, slot: 8, preferredCols: percCols, duplicateChance: 0.08);
      }

      // Ghosts and fills for more realistic-looking previews.
      if (!closedHatSet.contains(step) && rng.nextDouble() < 0.08) {
        placeHit(step: step, slot: 2, preferredCols: closedHatCols);
      }
      if (!kickSet.contains(step) && rng.nextDouble() < 0.04) {
        placeHit(step: step, slot: 0, preferredCols: kickCols);
      }
      if ((step + 1) % 16 == 0 && rng.nextDouble() < 0.55) {
        placeHit(step: step, slot: 9, preferredCols: fxCols);
      }
    }

    final sampleNames = <String>[
      'Kick',
      'Snare',
      'Closed Hat',
      'Open Hat',
      'Perc',
      'Tom',
      'Ride',
      'Clap',
      'Shaker',
      'FX',
    ];
    final palette = List<Color>.from(AppColors.sampleBankPalette)..shuffle(Random(seed * 97 + 13));
    final sampleColors = List<String>.generate(
      sampleNames.length,
      (index) => _colorToHex(palette[index % palette.length]),
    );

    final samples = List.generate(SampleBankState.maxSampleSlots, (index) {
      final isLoaded = index < sampleColors.length;
      return <String, dynamic>{
        'loaded': isLoaded,
        'settings': {
          'volume': 1.0,
          'pitch': 1.0,
        },
        'sample_id': isLoaded ? 'starter_sample_$index' : null,
        'file_path': isLoaded ? '/starter/sample_$index.wav' : null,
        'display_name': isLoaded
            ? (index < sampleNames.length ? sampleNames[index] : 'Starter ${index + 1}')
            : null,
        if (isLoaded) 'color': sampleColors[index],
      };
    });

    return {
      'schema_version': 1,
      'id': 'starter_${name.replaceAll(' ', '_').toLowerCase()}',
      'name': name,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'source': {
        'table': {
          'sections_count': sections.length,
          'sections': _buildSections(sections),
          'layers': List.generate(sections.length, (_) => List<int>.from(layers)),
          'table_cells': tableCells,
          'layer_modes': {
            '0': 'sequence',
            '1': 'sequence',
            '2': 'sequence',
            '3': 'sequence',
            '4': 'sequence',
          },
        },
        'playback': {
          'bpm': bpm,
          'region_start': 0,
          'region_end': totalSteps,
          'song_mode': 0,
          'current_section': 0,
          'current_section_loop': 0,
          'sections_loops_num': List.filled(64, 4),
        },
        'sample_bank': {
          'max_slots': SampleBankState.maxSampleSlots,
          'samples': samples,
        },
      },
      'renders': const [],
    };
  }

  List<Map<String, int>> _buildSections(List<int> sectionStepCounts) {
    int currentStart = 0;
    final out = <Map<String, int>>[];
    for (final count in sectionStepCounts) {
      out.add({
        'start_step': currentStart,
        'num_steps': count,
      });
      currentStart += count;
    }
    return out;
  }

  String _colorToHex(Color color) {
    return '#${color.red.toRadixString(16).padLeft(2, '0')}'
        '${color.green.toRadixString(16).padLeft(2, '0')}'
        '${color.blue.toRadixString(16).padLeft(2, '0')}'.toUpperCase();
  }
  
  /// Create new pattern
  Future<Pattern?> createPattern(String name) async {
    try {
      final pattern = Pattern(
        id: _uuid.v4(),
        name: name,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        checkpointIds: [],
      );
      
      final success = await LocalPatternService.savePattern(pattern);
      
      if (success) {
        _patterns = [pattern, ..._patterns];
        _sortPatternsByUpdatedAtDesc();
        notifyListeners();
        
        debugPrint('📦 [PATTERNS_STATE] Created pattern: ${pattern.id}');
        return pattern;
      }
      
      return null;
    } catch (e) {
      debugPrint('❌ [PATTERNS_STATE] Error creating pattern: $e');
      return null;
    }
  }
  
  /// Delete pattern
  Future<bool> deletePattern(String patternId) async {
    try {
      final success = await LocalPatternService.deletePattern(patternId);
      
      if (success) {
        _patterns = _patterns.where((p) => p.id != patternId).toList();
        _checkpointsByPattern.remove(patternId);
        
        // Clear active pattern if it was deleted
        if (_activePattern?.id == patternId) {
          _activePattern = null;
        }
        
        notifyListeners();
        debugPrint('📦 [PATTERNS_STATE] Deleted pattern: $patternId');
        return true;
      }
      
      return false;
    } catch (e) {
      debugPrint('❌ [PATTERNS_STATE] Error deleting pattern: $e');
      return false;
    }
  }
  
  void addBeforeActivePatternSwitchListener(Future<void> Function() listener) {
    _beforeActivePatternSwitch.add(listener);
  }

  void removeBeforeActivePatternSwitchListener(Future<void> Function() listener) {
    _beforeActivePatternSwitch.remove(listener);
  }

  /// Set active pattern and load its checkpoints
  Future<void> setActivePattern(Pattern pattern) async {
    try {
      if (_activePattern?.id == pattern.id) {
        if (!_checkpointsByPattern.containsKey(pattern.id)) {
          await loadCheckpoints(pattern.id);
        }
        return;
      }

      // Flush in-memory sequencer draft for the outgoing pattern while activePattern
      // still matches that session (shared TableState).
      for (final fn in List<Future<void> Function()>.from(_beforeActivePatternSwitch)) {
        await fn();
      }

      _activePattern = pattern;
      notifyListeners();

      // Load checkpoints for this pattern if not already loaded
      if (!_checkpointsByPattern.containsKey(pattern.id)) {
        await loadCheckpoints(pattern.id);
      }

      debugPrint('📦 [PATTERNS_STATE] Set active pattern: ${pattern.id}');
    } catch (e) {
      debugPrint('❌ [PATTERNS_STATE] Error setting active pattern: $e');
    }
  }
  
  /// Update pattern name
  Future<bool> updatePatternName(String patternId, String newName) async {
    try {
      final pattern = _patterns.firstWhere((p) => p.id == patternId);
      final updatedPattern = pattern.copyWith(
        name: newName,
        updatedAt: DateTime.now(),
      );
      
      final success = await LocalPatternService.savePattern(updatedPattern);
      
      if (success) {
        final index = _patterns.indexWhere((p) => p.id == patternId);
        if (index >= 0) {
          _patterns = List.from(_patterns)..[index] = updatedPattern;
          _sortPatternsByUpdatedAtDesc();
          
          if (_activePattern?.id == patternId) {
            _activePattern = updatedPattern;
          }
          
          notifyListeners();
        }
        
        debugPrint('📦 [PATTERNS_STATE] Updated pattern name: $patternId');
        return true;
      }
      
      return false;
    } catch (e) {
      debugPrint('❌ [PATTERNS_STATE] Error updating pattern name: $e');
      return false;
    }
  }
  
  // ============================================================================
  // Checkpoint Management
  // ============================================================================
  
  /// Load checkpoints for a pattern
  Future<void> loadCheckpoints(String patternId) async {
    try {
      final checkpoints = await LocalCheckpointService.loadCheckpoints(patternId);
      _checkpointsByPattern[patternId] = checkpoints;
      notifyListeners();
      
      debugPrint('💾 [PATTERNS_STATE] Loaded ${checkpoints.length} checkpoints for pattern $patternId');
    } catch (e) {
      debugPrint('❌ [PATTERNS_STATE] Error loading checkpoints: $e');
    }
  }
  
  /// Save new checkpoint
  Future<Checkpoint?> saveCheckpoint({
    required Map<String, dynamic> snapshot,
    Map<String, dynamic>? snapshotMetadata,
    String? audioFilePath,
    double? audioDuration,
  }) async {
    if (_activePattern == null) {
      debugPrint('❌ [PATTERNS_STATE] No active pattern');
      return null;
    }
    
    try {
      final checkpoint = Checkpoint(
        id: _uuid.v4(),
        createdAt: DateTime.now(),
        patternId: _activePattern!.id,
        snapshot: snapshot,
        snapshotMetadata: snapshotMetadata,
        audioFilePath: audioFilePath,
        audioDuration: audioDuration,
      );
      
      final success = await LocalCheckpointService.saveCheckpoint(checkpoint);
      
      if (success) {
        // Add checkpoint to local cache
        final checkpoints = _checkpointsByPattern[_activePattern!.id] ?? [];
        _checkpointsByPattern[_activePattern!.id] = [checkpoint, ...checkpoints];
        
        // Update pattern's checkpoint IDs
        final updatedPattern = _activePattern!.copyWith(
          checkpointIds: [checkpoint.id, ..._activePattern!.checkpointIds],
          updatedAt: DateTime.now(),
        );
        
        await LocalPatternService.savePattern(updatedPattern);
        
        // Update in memory
        final index = _patterns.indexWhere((p) => p.id == _activePattern!.id);
        if (index >= 0) {
          _patterns = List.from(_patterns)..[index] = updatedPattern;
        }
        _activePattern = updatedPattern;
        _sortPatternsByUpdatedAtDesc();

        notifyListeners();
        debugPrint('💾 [PATTERNS_STATE] Saved checkpoint: ${checkpoint.id}');
        return checkpoint;
      }
      
      return null;
    } catch (e) {
      debugPrint('❌ [PATTERNS_STATE] Error saving checkpoint: $e');
      return null;
    }
  }
  
  /// Load checkpoint (restore snapshot to sequencer)
  Future<Checkpoint?> loadCheckpoint(String checkpointId) async {
    if (_activePattern == null) {
      debugPrint('❌ [PATTERNS_STATE] No active pattern');
      return null;
    }
    
    try {
      final checkpoint = await LocalCheckpointService.getCheckpoint(
        _activePattern!.id,
        checkpointId,
      );
      
      if (checkpoint != null) {
        debugPrint('💾 [PATTERNS_STATE] Loaded checkpoint: $checkpointId');
      }
      
      return checkpoint;
    } catch (e) {
      debugPrint('❌ [PATTERNS_STATE] Error loading checkpoint: $e');
      return null;
    }
  }
  
  /// Delete checkpoint
  Future<bool> deleteCheckpoint(String checkpointId) async {
    if (_activePattern == null) {
      debugPrint('❌ [PATTERNS_STATE] No active pattern');
      return false;
    }
    
    try {
      final success = await LocalCheckpointService.deleteCheckpoint(
        _activePattern!.id,
        checkpointId,
      );
      
      if (success) {
        // Remove from local cache
        final checkpoints = _checkpointsByPattern[_activePattern!.id] ?? [];
        _checkpointsByPattern[_activePattern!.id] = 
            checkpoints.where((c) => c.id != checkpointId).toList();
        
        // Update pattern's checkpoint IDs
        final updatedPattern = _activePattern!.copyWith(
          checkpointIds: _activePattern!.checkpointIds
              .where((id) => id != checkpointId)
              .toList(),
          updatedAt: DateTime.now(),
        );
        
        await LocalPatternService.savePattern(updatedPattern);
        
        // Update in memory
        final index = _patterns.indexWhere((p) => p.id == _activePattern!.id);
        if (index >= 0) {
          _patterns = List.from(_patterns)..[index] = updatedPattern;
        }
        _activePattern = updatedPattern;
        _sortPatternsByUpdatedAtDesc();
        
        notifyListeners();
        debugPrint('💾 [PATTERNS_STATE] Deleted checkpoint: $checkpointId');
        return true;
      }
      
      return false;
    } catch (e) {
      debugPrint('❌ [PATTERNS_STATE] Error deleting checkpoint: $e');
      return false;
    }
  }
  
  /// Update pattern's updatedAt timestamp (for auto-save)
  Future<void> updatePatternTimestamp() async {
    if (_activePattern == null) return;
    await updatePatternTimestampForId(_activePattern!.id);
  }

  /// Like [updatePatternTimestamp] but for a specific id (e.g. sequencer saves draft
  /// for the pattern it loaded, which must match [activePattern] for that session).
  Future<void> updatePatternTimestampForId(String patternId) async {
    try {
      final index = _patterns.indexWhere((p) => p.id == patternId);
      if (index < 0) return;

      final updatedPattern = _patterns[index].copyWith(
        updatedAt: DateTime.now(),
      );

      await LocalPatternService.savePattern(updatedPattern);

      _patterns = List.from(_patterns)..[index] = updatedPattern;
      if (_activePattern?.id == patternId) {
        _activePattern = updatedPattern;
      }

      _sortPatternsByUpdatedAtDesc();
      notifyListeners();
      debugPrint('⏰ [PATTERNS_STATE] Updated pattern timestamp: $patternId');
    } catch (e) {
      debugPrint('❌ [PATTERNS_STATE] Error updating pattern timestamp: $e');
    }
  }
  
  // ============================================================================
  // Clear
  // ============================================================================
  
  /// Clear all data (e.g., for testing)
  void clear() {
    _activePattern = null;
    _patterns = [];
    _checkpointsByPattern = {};
    _beforeActivePatternSwitch.clear();
    _hasLoaded = false;
    _error = null;
    _isLoading = false;
    notifyListeners();
    debugPrint('📦 [PATTERNS_STATE] Cleared all data');
  }
}
