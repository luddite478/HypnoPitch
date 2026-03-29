import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// import 'package:path/path.dart' as path;
import 'package:share_plus/share_plus.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../../utils/app_colors.dart';
import '../../../state/sequencer/recording.dart';

class RecordingWidget extends StatelessWidget {
  const RecordingWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<RecordingState>(
      builder: (context, recording, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            // Calculate responsive sizes based on available space - INHERIT from parent
            final panelHeight = constraints.maxHeight;
            final panelWidth = constraints.maxWidth;
            
            // Use ALL available space - no minimums, just scale everything down
            final padding = panelHeight * 0.06; // 6% of given height
            final borderRadius = panelHeight * 0.08; // Scale with height
            
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
              child: recording.currentRecordingPath != null 
                  ? _buildRecordingMenu(context, recording, panelHeight, panelWidth, padding, borderRadius)
                  : _buildEmptyState(panelHeight, panelWidth, padding, borderRadius),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState(double panelHeight, double panelWidth, double padding, double borderRadius) {
    final fontSize = (panelHeight * 0.25).clamp(10.0, double.infinity);
    final verticalSpacing = panelHeight * 0.02; // Minimal vertical spacing (2%)
    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: padding, // Only horizontal padding like sample_banks_widget  
        vertical: verticalSpacing, // Minimal vertical spacing
      ),
      child: Center(
        child: Text(
          'No Recording',
          style: TextStyle(
            color: Colors.grey,
            fontSize: fontSize,
            fontWeight: FontWeight.w300,
          ),
        ),
      ),
    );
  }

  Widget _buildRecordingMenu(BuildContext context, RecordingState recording, 
      double panelHeight, double panelWidth, double padding, double borderRadius) {
    
    // final fileName = path.basename(recording.currentRecordingPath ?? 'recording.wav');
    
    // Follow sample_banks_widget pattern: only horizontal padding to avoid overflow
    final horizontalPadding = padding;
    final verticalSpacing = panelHeight * 0.02; // Minimal vertical spacing (2%)
    
    // Calculate available height after minimal spacing
    final availableHeight = panelHeight - (verticalSpacing * 2); // Top and bottom spacing
    
    // Single recording layout: compact header and buttons, no list
    final titleHeight = availableHeight * 0.20;
    final buttonAreaHeight = availableHeight * 0.55;
    
    final titleFontSize = (titleHeight * 0.24).clamp(10.0, 20.0);
    final buttonSize = (buttonAreaHeight * 0.4).clamp(28.0, 56.0);
    final iconSize = (buttonSize * 0.4).clamp(12.0, 24.0);
    // final statusFontSize = (availableHeight * 0.14).clamp(8.0, 14.0);
    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding, // Only horizontal padding like sample_banks_widget
        vertical: verticalSpacing, // Minimal vertical spacing
      ),
      child: Column(
        children: [
          // Title row (left title, right close)
          Container(
            height: titleHeight,
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Recording',
                    style: TextStyle(
                      color: AppColors.sequencerText,
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: Consumer<RecordingState>(
                    builder: (context, rec, _) => GestureDetector(
                      onTap: rec.hideOverlay,
                      child: Container(
                        width: titleHeight * 0.6,
                        height: titleHeight * 0.6,
                        decoration: BoxDecoration(
                          color: AppColors.sequencerSurfacePressed,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.sequencerAccent.withOpacity(0.8), width: 1),
                        ),
                        child: Icon(
                          Icons.close,
                          color: AppColors.sequencerAccent,
                          size: iconSize,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Buttons section (compact buttons centered) for new take
          Container(
            height: buttonAreaHeight,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Consumer<RecordingState>(
                  builder: (context, rec, _) => _buildSequencerButton(
                    icon: rec.isPreviewing ? Icons.stop : Icons.play_arrow,
                    onTap: rec.isConverting ? null : () => _togglePreview(rec),
                    iconColor: rec.isPreviewing ? Colors.redAccent : Colors.greenAccent,
                  ),
                ),
                SizedBox(width: horizontalPadding * 0.5),
                Consumer<RecordingState>(
                  builder: (context, rec, _) => _buildSequencerButton(
                    icon: Icons.delete, 
                    onTap: rec.isConverting ? null : () => _showDeleteConfirmation(context, rec), 
                    iconColor: Colors.redAccent
                  ),
                ),
                SizedBox(width: horizontalPadding * 0.5),
                Consumer<RecordingState>(
                  builder: (context, rec, _) => _buildSequencerButton(
                    icon: Icons.share, 
                    onTap: rec.isConverting ? null : () => _shareRecordingAuto(context, rec), 
                    iconColor: Colors.cyanAccent
                  ),
                ),
              ],
            ),
          ),
          
          // Conversion status indicator (spinner while converting)
          Consumer<RecordingState>(
            builder: (context, rec, _) {
              if (rec.isConverting) {
                return Container(
                  height: availableHeight * 0.15,
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Converting to MP3...',
                          style: TextStyle(
                            color: Colors.orange,
                            fontSize: (availableHeight * 0.12).clamp(10.0, 14.0),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              } else if (rec.conversionError != null) {
                return Container(
                  height: availableHeight * 0.15,
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error,
                          color: Colors.red,
                          size: 16,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Conversion failed',
                            style: TextStyle(
                              color: Colors.red,
                              fontSize: (availableHeight * 0.12).clamp(10.0, 14.0),
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return SizedBox(height: availableHeight * 0.15);
            },
          ),
          
          // Optional footer space to avoid cramped look
          SizedBox(height: verticalSpacing),
        ],
      ),
    );
  }

  Widget _buildSequencerButton({
    required IconData icon,
    required VoidCallback? onTap,
    required Color iconColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.sequencerSurfacePressed,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.sequencerBorder, width: 1),
          boxShadow: [
            BoxShadow(
              color: AppColors.sequencerShadow,
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Center(
          child: Icon(icon, color: onTap == null ? Colors.grey : iconColor, size: 20),
        ),
      ),
    );
  }

  // Removed old action button in favor of sequencer-styled button

  // Removed status area (not used)

  void _togglePreview(RecordingState recording) {
    recording.togglePreview();
  }

  void _showDeleteConfirmation(BuildContext context, RecordingState recording) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1f2937),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: const Text(
            'Delete Recording?', 
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
          ),
          content: const Text(
            'This will permanently delete the recording. This action cannot be undone.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancel', 
                style: TextStyle(color: Colors.cyanAccent)
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                recording.clearRecording();
              },
              child: const Text(
                'Delete', 
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)
              ),
            ),
          ],
        );
      },
    );
  }

  void _shareRecordingAuto(BuildContext context, RecordingState recording) async {
    try {
      // Ensure MP3 is ready; if not, convert first
      final mp3 = await recording.getShareableMp3Path(bitrateKbps: 320);
      if (mp3 == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conversion failed. Cannot share.')),
        );
        return;
      }
      final appName = dotenv.env['APP_NAME']!;
      await Share.shareXFiles(
        [XFile(mp3)],
        text: 'Check out my track created with $appName!',
        subject: '$appName track',
      );
    } catch (e) {
      debugPrint('Failed to share recording: $e');
    }
  }

  }