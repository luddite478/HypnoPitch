import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/app_colors.dart';
import '../screens/library_screen.dart';
import '../state/app_state.dart';
import 'tutorial_pulse_widget.dart';

class SimplifiedHeaderWidget extends StatelessWidget {
  const SimplifiedHeaderWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 66, 66, 66),
        border: Border(
          bottom: BorderSide(
            color: AppColors.sequencerBorder,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Transform.scale(
            alignment: Alignment.centerLeft,
            scale: 1.55,
            child: Image.asset(
              'icons/white_mane1.jpg',
              width: 40,
              height: 40,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
          const SizedBox(width: 2),
          
          // Spacer
          const Expanded(
            child: SizedBox(),
          ),
          
          // Right side - Library icon
          TutorialPulseWidget(
            enabled: appState.activeTutorialStep ==
                TutorialStep.sequencerProjectsLibraryHint,
            borderRadius: BorderRadius.circular(10),
            child: IconButton(
              key: appState.activeTutorialStep ==
                      TutorialStep.sequencerProjectsLibraryHint
                  ? appState.projectsLibraryFolderTutorialKey
                  : null,
              onPressed: () {
                appState.markProjectsLibraryFolderOpenAction();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const LibraryScreen(),
                  ),
                );
              },
              icon: Icon(
                Icons.folder_outlined,
                color: AppColors.sequencerText,
                size: 28,
              ),
              style: IconButton.styleFrom(
                backgroundColor: Colors.transparent,
              ),
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            ),
          ),
        ],
      ),
    );
  }
}
