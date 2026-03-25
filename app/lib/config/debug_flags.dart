import 'package:flutter/foundation.dart';

// Toggle performance/profiling logs in sequencer paths.
// Keep false during regular development to avoid noisy console output.
const bool kEnableSequencerProfilingLogs = false;

// Centralized guard for profiling logs.
const bool kShouldLogSequencerProfiling =
    kDebugMode && kEnableSequencerProfilingLogs;
