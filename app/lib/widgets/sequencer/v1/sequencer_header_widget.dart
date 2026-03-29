import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../state/sequencer/microphone.dart';
import '../../../screens/sequencer_settings_screen.dart';
import '../../../utils/app_colors.dart';

class SequencerHeaderWidget extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback? onBack;

  const SequencerHeaderWidget({
    super.key,
    this.onBack,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppColors.menuBorder,
            width: 1,
          ),
        ),
      ),
      child: AppBar(
        backgroundColor: AppColors.sequencerSurfaceBase,
        foregroundColor: AppColors.sequencerText,
        elevation: 0,
        leading: onBack != null 
            ? IconButton(
                icon: Icon(
                  Icons.arrow_back, 
                  color: AppColors.sequencerText,
                ),
                onPressed: onBack,
                iconSize: 20,
              )
            : null,
        title: const SizedBox.shrink(), // No title for sequencer mode to save space
        actions: _buildActions(context),
      ),
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    return [
      // Settings button
      IconButton(
        icon: Icon(
          Icons.settings,
          color: AppColors.sequencerAccent,
        ),
        onPressed: () => _navigateToSequencerSettings(context),
        iconSize: 18,
        padding: const EdgeInsets.all(2),
        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      ),
      
      const SizedBox(width: 4),
    ];
  }

  void _navigateToSequencerSettings(BuildContext context) {
    // Pass existing providers to settings screen
    final microphoneState = Provider.of<MicrophoneState>(context, listen: false);
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChangeNotifierProvider.value(
          value: microphoneState,
          child: const SequencerSettingsScreen(),
        ),
      ),
    );
  }
}

