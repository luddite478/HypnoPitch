import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'sequencer_screen_v1.dart';
import 'sequencer_screen_v2.dart';
import '../state/sequencer_version_state.dart';

/// Main sequencer screen that routes to the appropriate layout version
/// based on the selected layout in SequencerVersionState
class PatternScreen extends StatelessWidget {
  final Map<String, dynamic>? initialSnapshot;
  final bool openThreadView; // If true, opens to thread view tab instead of sequencer
  
  const PatternScreen({super.key, this.initialSnapshot, this.openThreadView = false});

  @override
  Widget build(BuildContext context) {
    return Consumer<SequencerVersionState>(
      builder: (context, versionState, child) {
        debugPrint('🎵 PatternScreen: Building with version ${versionState.currentVersion}, openThreadView: $openThreadView');
        return versionState.isV1 
            ? SequencerScreenV1(initialSnapshot: initialSnapshot)
            : SequencerScreenV2(initialSnapshot: initialSnapshot, openThreadView: openThreadView);
      },
    );
  }
}