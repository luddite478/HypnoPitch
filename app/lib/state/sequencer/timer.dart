import '../../utils/log.dart';
import '../../config/debug_flags.dart';
import 'package:flutter/scheduler.dart';
import 'dart:math' as math;
import 'table.dart';
import 'playback.dart';
import 'sample_bank.dart';
import 'undo_redo.dart';
import 'sync_frequency_policy.dart';

/// Ticker-based timer for efficient native state synchronization
///
/// This state handles frame-by-frame updates from native layer using Flutter's
/// Ticker system. It queries changed cells from native and updates ValueNotifiers
/// to trigger minimal UI refreshes.
class TimerState {
  Ticker? _ticker;
  final TableState tableState;
  final PlaybackState playbackState;
  final SampleBankState sampleBankState;
  final UndoRedoState undoRedoState;

  bool _isRunning = false;
  int _frameCount = 0;
  int _profileWindowFrames = 0;
  int _tableSyncSkips = 0;
  int _sampleSyncSkips = 0;
  int _undoSyncSkips = 0;
  SyncFrequencyPolicy _syncFrequencyPolicy = SyncFrequencyPolicy.idle;
  int _tableSyncMicros = 0;
  int _playbackSyncMicros = 0;
  int _sampleSyncMicros = 0;
  int _undoSyncMicros = 0;
  int _tickMicros = 0;

  TimerState({
    required this.tableState,
    required this.playbackState,
    required this.sampleBankState,
    required this.undoRedoState,
  });

  void start() {
    if (_isRunning) return;

    _ticker = Ticker(_onTick);
    _ticker!.start();
    _isRunning = true;

    Log.d('⏰ [TIMER_STATE] Started timer system');
  }

  void stop() {
    if (!_isRunning) return;

    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
    _isRunning = false;

    Log.d('⏹️ [TIMER_STATE] Stopped timer system');
  }

  /// Called every frame by Flutter's Ticker
  void _onTick(Duration elapsed) {
    _frameCount++;

    final tickWatch = Stopwatch()..start();
    try {
      _syncFrequencyPolicy = SyncFrequencyPolicy.forPlaybackState(
        isPlaying: playbackState.isPlaying,
      );

      final playbackWatch = Stopwatch()..start();
      playbackState.syncPlaybackState();
      playbackWatch.stop();
      _playbackSyncMicros += playbackWatch.elapsedMicroseconds;

      if ((_frameCount % _syncFrequencyPolicy.tableCadence) == 0) {
        final tableWatch = Stopwatch()..start();
        tableState.syncTableState();
        tableWatch.stop();
        _tableSyncMicros += tableWatch.elapsedMicroseconds;
      } else {
        _tableSyncSkips++;
      }

      if ((_frameCount % _syncFrequencyPolicy.sampleCadence) == 0) {
        final sampleWatch = Stopwatch()..start();
        sampleBankState.syncSampleBankState();
        sampleWatch.stop();
        _sampleSyncMicros += sampleWatch.elapsedMicroseconds;
      } else {
        _sampleSyncSkips++;
      }

      if ((_frameCount % _syncFrequencyPolicy.undoCadence) == 0) {
        final undoWatch = Stopwatch()..start();
        undoRedoState.syncFromNative();
        undoWatch.stop();
        _undoSyncMicros += undoWatch.elapsedMicroseconds;
      } else {
        _undoSyncSkips++;
      }
    } catch (e) {
      Log.d('❌ [TIMER_STATE] Error in tick: $e');
    } finally {
      tickWatch.stop();
      _tickMicros += tickWatch.elapsedMicroseconds;
      _profileWindowFrames++;

      if (kShouldLogSequencerProfiling && _profileWindowFrames >= 180) {
        final frames = math.max(1, _profileWindowFrames);
        final avgTickMs = _tickMicros / frames / 1000.0;
        final avgPlaybackMs = _playbackSyncMicros / frames / 1000.0;
        final avgTableMs = _tableSyncMicros / frames / 1000.0;
        final avgSampleMs = _sampleSyncMicros / frames / 1000.0;
        final avgUndoMs = _undoSyncMicros / frames / 1000.0;
        Log.d(
          '[TIMER_PROFILE] frames=$frames avg_tick=${avgTickMs.toStringAsFixed(3)}ms '
              'playback=${avgPlaybackMs.toStringAsFixed(3)}ms table=${avgTableMs.toStringAsFixed(3)}ms '
              'sample=${avgSampleMs.toStringAsFixed(3)}ms undo=${avgUndoMs.toStringAsFixed(3)}ms '
              'skips(table/sample/undo)=$_tableSyncSkips/$_sampleSyncSkips/$_undoSyncSkips '
              'cadence(table/sample/undo)=${_syncFrequencyPolicy.tableCadence}/${_syncFrequencyPolicy.sampleCadence}/${_syncFrequencyPolicy.undoCadence}',
          'TIMER_STATE',
        );

        _profileWindowFrames = 0;
        _tableSyncSkips = 0;
        _sampleSyncSkips = 0;
        _undoSyncSkips = 0;
        _tableSyncMicros = 0;
        _playbackSyncMicros = 0;
        _sampleSyncMicros = 0;
        _undoSyncMicros = 0;
        _tickMicros = 0;
      }
    }
  }

  void dispose() {
    stop();
    Log.d('🧹 [TIMER_STATE] Disposed timer state');
  }

  bool get isRunning => _isRunning;
  int get frameCount => _frameCount;
}
