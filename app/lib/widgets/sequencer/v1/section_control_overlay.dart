import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../utils/app_colors.dart';
import '../../../state/sequencer/playback.dart';

class SectionControlOverlay extends StatelessWidget {
  const SectionControlOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PlaybackState>(
      builder: (context, playbackState, child) {
        return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              _buildHeader(context),
              
              // Current section settings
              _buildCurrentSectionSettings(context, playbackState),
              
              // Footer with controls
              _buildFooter(context),
            ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final headerHeight = screenSize.height * 0.08;
    
    return Container(
      height: headerHeight,
      decoration: BoxDecoration(
        // Header should be fully opaque so controls never appear translucent
        color: AppColors.sequencerSurfaceRaised,
        border: Border(
          bottom: BorderSide(
            color: AppColors.sequencerBorder,
            width: 1,
          ),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: screenSize.width * 0.02),
        child: Row(
          children: [
            const Spacer(),
            Text(
              'Section Settings',
              style: TextStyle(
                color: AppColors.sequencerLightText,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentSectionSettings(BuildContext context, PlaybackState playbackState) {
    final screenSize = MediaQuery.of(context).size;
    
    return Container(
      // Opaque surface behind buttons to avoid any bleed-through from semi-transparent overlay
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceBase,
        border: Border(
          bottom: BorderSide(
            color: AppColors.sequencerBorder,
            width: 1,
          ),
        ),
      ),
      padding: EdgeInsets.all(screenSize.width * 0.04),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          
          // Loop count controls
          Container(
            padding: EdgeInsets.symmetric(vertical: screenSize.height * 0.02),
            child: Column(
              children: [
                // Loop count label
                Text(
                  'Loop Count',
                  style: TextStyle(
                    color: AppColors.sequencerLightText,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                
                SizedBox(height: screenSize.height * 0.02),
                
                // Loop count controls: left arrow - number - right arrow
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Left arrow button
                    _buildArrowButton(
                      context,
                      icon: Icons.chevron_left,
                      onTap: () {
                        final currentIndex = playbackState.currentSection;
                        final currentCount = playbackState.currentSectionLoopsNum;
                        if (currentCount > PlaybackState.minLoopsPerSection) {
                          playbackState.setSectionLoopsNum(currentIndex, currentCount - 1);
                        }
                      },
                      enabled: playbackState.currentSectionLoopsNum > PlaybackState.minLoopsPerSection,
                    ),
                    
                    SizedBox(width: screenSize.width * 0.06),
                    
                    // Current loop count
                    Container(
                      width: screenSize.width * 0.15,
                      height: screenSize.height * 0.06,
                      decoration: BoxDecoration(
                        color: AppColors.sequencerSurfacePressed,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: AppColors.sequencerAccent,
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '${playbackState.currentSectionLoopsNum}',
                          style: TextStyle(
                            color: AppColors.sequencerAccent,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    
                    SizedBox(width: screenSize.width * 0.06),
                    
                    // Right arrow button
                    _buildArrowButton(
                      context,
                      icon: Icons.chevron_right,
                      onTap: () {
                        final currentIndex = playbackState.currentSection;
                        final currentCount = playbackState.currentSectionLoopsNum;
                        if (currentCount < PlaybackState.maxLoopsPerSection) {
                          playbackState.setSectionLoopsNum(currentIndex, currentCount + 1);
                        }
                      },
                      enabled: playbackState.currentSectionLoopsNum < PlaybackState.maxLoopsPerSection,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArrowButton(BuildContext context, {
    required IconData icon,
    required VoidCallback onTap,
    required bool enabled,
  }) {
    final screenSize = MediaQuery.of(context).size;
    
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: screenSize.width * 0.12,
        height: screenSize.height * 0.06,
        decoration: BoxDecoration(
          color: enabled 
              ? AppColors.sequencerSurfaceRaised
              : AppColors.sequencerSurfacePressed,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: enabled 
                ? AppColors.sequencerAccent
                : AppColors.sequencerBorder,
            width: 2,
          ),
          boxShadow: enabled ? [
            BoxShadow(
              color: AppColors.sequencerShadow,
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ] : null,
        ),
        child: Center(
          child: Icon(
            icon,
            color: enabled 
                ? AppColors.sequencerAccent
                : AppColors.sequencerBorder,
            size: screenSize.width * 0.06,
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return const SizedBox.shrink();
  }
} 