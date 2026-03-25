import 'package:flutter/material.dart';
// duplicate import removed
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../state/sequencer/slider_overlay.dart';
import '../../../utils/app_colors.dart';

class ValueControlOverlay extends StatelessWidget {
  const ValueControlOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SliderOverlayState>(
      builder: (context, sliderOverlay, child) {
        return ValueListenableBuilder<bool>(
          valueListenable: sliderOverlay.isInteractingNotifier,
          builder: (context, isInteracting, child) {
            if (!isInteracting) {
              return IgnorePointer(
                ignoring: true,
                child: const SizedBox.shrink(),
              );
            }

            return Stack(
              children: [
                // Dark overlay background
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.6),
                  ),
                ),
                
                // Value display overlay
                Positioned.fill(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 40.0,
                        vertical: 30.0,
                      ),
                      decoration: const BoxDecoration(
                        // Make the tile fully transparent with no border/shadow
                        color: Colors.transparent,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Context (Sample/Cell)
                          ValueListenableBuilder<String>(
                            valueListenable: sliderOverlay.contextNotifier,
                            builder: (context, ctx, child) {
                              if (ctx.isEmpty) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: Text(
                                  ctx,
                                  style: TextStyle(
                                    color: AppColors.sequencerLightText.withOpacity(0.9),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              );
                            },
                          ),
                          // Setting name
                          ValueListenableBuilder<String>(
                            valueListenable: sliderOverlay.settingNameNotifier,
                            builder: (context, setting, child) {
                              return Text(
                                setting,
                                style: TextStyle(
                                  color: AppColors.sequencerLightText,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 1.0,
                                ),
                              );
                            },
                          ),
                          
                          const SizedBox(height: 20),
                          
                          // Value display
                          ValueListenableBuilder<String>(
                            valueListenable: sliderOverlay.valueNotifier,
                            builder: (context, value, child) {
                              return Text(
                                value,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 48,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2.0,
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 12),

                          // Reserve fixed space to avoid layout jumps when spinner shows/hides
                          SizedBox(
                            height: 20,
                            child: Center(
                              child: ValueListenableBuilder<bool>(
                                valueListenable: sliderOverlay.processingSource ?? ValueNotifier<bool>(false),
                                builder: (context, isProcessing, child) {
                                  return isProcessing
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: AppColors.sequencerAccent,
                                          ),
                                        )
                                      : const SizedBox(width: 18, height: 18);
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
} 