import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../utils/app_colors.dart';
import '../../../state/app_state.dart';
import '../../../state/sequencer/table.dart';

class SectionCreationOverlay extends StatelessWidget {
  const SectionCreationOverlay({super.key, VoidCallback? onBack});

  @override
  Widget build(BuildContext context) {
    return Consumer2<TableState, AppState>(
      builder: (context, tableState, appState, child) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.sequencerSurfaceBase,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
              color: AppColors.sequencerBorder,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.sequencerShadow,
                blurRadius: 3,
                offset: const Offset(0, 2),
              ),
              BoxShadow(
                color: AppColors.sequencerSurfaceRaised,
                blurRadius: 1,
                offset: const Offset(0, -1),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: MediaQuery.of(context).size.width * 0.04,
              vertical: MediaQuery.of(context).size.height * 0.02,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildPrimaryButton(
                  context,
                  tutorialKey: appState.sectionCreatePrimaryButtonTutorialKey,
                  text: 'Create new section',
                  onPressed: () => tableState.appendSection(),
                ),
                SizedBox(height: MediaQuery.of(context).size.height * 0.02),
                Text(
                  'Copy from:',
                  style: TextStyle(
                    color: AppColors.sequencerLightText,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: MediaQuery.of(context).size.height * 0.01),
                Expanded(
                  child: ListView.separated(
                    itemCount: tableState.sectionsCount,
                    separatorBuilder: (_, __) => SizedBox(
                      height: MediaQuery.of(context).size.height * 0.01,
                    ),
                    itemBuilder: (context, index) {
                      return _buildCopyFromButton(
                        context,
                        sectionIndex: index,
                        onPressed: () => tableState.appendSection(copyFrom: index),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPrimaryButton(
    BuildContext context, {
    GlobalKey? tutorialKey,
    required String text,
    required VoidCallback onPressed,
  }) {
    Widget child = GestureDetector(
      onTap: onPressed,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          vertical: MediaQuery.of(context).size.height * 0.02,
        ),
        decoration: BoxDecoration(
          color: AppColors.sequencerAccent,
          borderRadius: BorderRadius.circular(2),
        ),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
    if (tutorialKey != null) {
      child = KeyedSubtree(key: tutorialKey, child: child);
    }
    return child;
  }

  Widget _buildCopyFromButton(
    BuildContext context, {
    required int sectionIndex,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          vertical: MediaQuery.of(context).size.height * 0.015,
          horizontal: MediaQuery.of(context).size.width * 0.03,
        ),
        decoration: BoxDecoration(
          color: AppColors.sequencerSurfacePressed,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: AppColors.sequencerBorder,
            width: 1,
          ),
        ),
        child: Text(
          '${sectionIndex + 1}',
          style: TextStyle(
            color: AppColors.sequencerLightText,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
} 