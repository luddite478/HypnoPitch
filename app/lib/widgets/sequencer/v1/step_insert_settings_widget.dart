import 'package:flutter/material.dart';
// duplicate import removed
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../state/sequencer/edit.dart';
import '../../../state/sequencer/multitask_panel.dart';
import '../../../utils/app_colors.dart';
import 'generic_slider.dart';
import '../../../state/sequencer/slider_overlay.dart';

class StepInsertSettingsWidget extends StatelessWidget {
  const StepInsertSettingsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<EditState, MultitaskPanelState>(
      builder: (context, editState, panelState, child) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.sequencerSurfaceBase,
            borderRadius: BorderRadius.circular(2), // Sharp corners
            border: Border.all(
              color: AppColors.sequencerBorder,
              width: 0.5,
            ),
            boxShadow: [
              // Protruding effect
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final panelHeight = constraints.maxHeight;
              final sliderHeight = panelHeight * 0.7;
              final textHeight = panelHeight * 0.3;
              final padding = panelHeight * 0.03;
              
              return Column(
                children: [
                  // Title and close button
                  Container(
                    height: textHeight,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Jump Insert: ${editState.stepInsertSize} cells',
                            style: TextStyle(
                              color: AppColors.sequencerText,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => panelState.showPlaceholder(),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.close,
                              color: AppColors.sequencerLightText,
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Slider styled like sound settings tile
                  Container(
                    height: sliderHeight,
                    padding: EdgeInsets.all(padding),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: padding * 0.3,
                        vertical: padding * 0.05,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.sequencerSurfaceRaised,
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(
                          color: AppColors.sequencerBorder,
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.sequencerShadow,
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                          BoxShadow(
                            color: AppColors.sequencerSurfaceRaised,
                            blurRadius: 1,
                            offset: const Offset(0, -0.5),
                          ),
                        ],
                      ),
                      child: Center(
                        child: GenericSlider(
                          value: editState.stepInsertSize.toDouble(),
                          min: 1,
                          max: 16,
                          divisions: 15,
                          type: SliderType.steps,
                          onChanged: (value) {
                            editState.setStepInsertSize(value.round());
                          },
                          height: sliderHeight,
                          sliderOverlay: context.read<SliderOverlayState>(),
                          contextLabel: 'Jump Insert',
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
} 