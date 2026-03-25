import 'package:flutter/foundation.dart';
import '../../config/debug_flags.dart';

typedef SyncProfileDetailsBuilder = String Function();

/// Shared rolling-window profiler for state sync methods.
class SyncProfiler {
  final String profileLabel;
  final int windowCalls;

  int _callsSinceLog = 0;
  int _microsAccumulated = 0;

  SyncProfiler({
    required this.profileLabel,
    this.windowCalls = 180,
  });

  void recordCall({
    required int elapsedMicros,
    SyncProfileDetailsBuilder? detailsBuilder,
  }) {
    _callsSinceLog++;
    _microsAccumulated += elapsedMicros;

    if (!kShouldLogSequencerProfiling || _callsSinceLog < windowCalls) {
      return;
    }

    final avgMs = (_microsAccumulated / _callsSinceLog) / 1000.0;
    final details = detailsBuilder?.call();
    final detailsSuffix =
        (details == null || details.isEmpty) ? '' : ' $details';

    debugPrint(
      '📈 [$profileLabel] avg sync ${avgMs.toStringAsFixed(3)}ms '
      'for $_callsSinceLog calls$detailsSuffix',
    );

    _callsSinceLog = 0;
    _microsAccumulated = 0;
  }
}
