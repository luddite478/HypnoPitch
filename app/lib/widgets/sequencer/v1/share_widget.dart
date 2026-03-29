import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import '../../../state/sequencer/recording.dart';
import '../../../state/sequencer/multitask_panel.dart';
import '../../../state/threads_state.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ShareWidget extends StatelessWidget {
  const ShareWidget({super.key});

  // Configurable layout percentages
  static const double _headerHeightPercent = 0.20;      // 20% for header
  static const double _publishButtonHeightPercent = 0.15; // 15% for publish button (when visible)
  static const double _recordingsHeightPercent = 0.65;   // 65% for recordings (or 80% without publish)
  static const double _paddingPercent = 0.02;            // 2% padding
  static const double _spacingPercent = 0.015;           // 1.5% spacing

  @override
  Widget build(BuildContext context) {
    return Consumer3<RecordingState, ThreadsState, MultitaskPanelState>(
      builder: (context, recording, threadsState, panelState, child) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(8),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Calculate responsive sizes based on available space - INHERIT from parent (like sample_banks_widget)
              final panelHeight = constraints.maxHeight;
              final panelWidth = constraints.maxWidth;
              
              // Use same pattern as sample_banks_widget: 80% content height, 5% padding
              final contentHeight = panelHeight * 0.8; // Use 80% of given height (leaves 20% for natural spacing)
              final padding = panelHeight * 0.05; // 5% of given height
              final borderRadius = contentHeight * 0.08; // Scale with content height
              
              // Publish flow removed in new model; hide publish button
              final canPublish = false;
              
              // Calculate layout: top button row + spacing + recordings area
              final buttonRowHeight = contentHeight * 0.25; // 25% of content for button row
              final spacingBetween = padding * 0.5; // Spacing as fraction of base padding
              final recordingsHeight = contentHeight * 0.75 - spacingBetween; // 75% minus spacing
              
              // Sizing for elements
              final buttonFontSize = (buttonRowHeight * 0.35).clamp(8.0, 14.0);
              final closeButtonSize = buttonRowHeight * 0.7; // Proportional close button
              final iconSize = (closeButtonSize * 0.5).clamp(10.0, 16.0);
              
              return Container(
                padding: EdgeInsets.symmetric(horizontal: padding), // Only horizontal padding like sample_banks_widget
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(borderRadius),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center, // Center content vertically in available space
                  children: [
                    // Top button row
                    Container(
                      height: buttonRowHeight,
                      child: Row(
                        children: [
                          // Publish button (if available)
                          if (canPublish) ...[
                            Expanded(
                              child: Container(
                                height: buttonRowHeight,
                                child: ElevatedButton(
                                  onPressed: () => _publishProject(context),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orangeAccent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(borderRadius * 0.5),
                                    ),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: padding * 0.5,
                                      vertical: padding * 0.3,
                                    ),
                                  ),
                                  child: Text(
                                    'Publish',
                                    style: TextStyle(
                                      fontSize: buttonFontSize,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: padding * 0.5), // Spacing as fraction of base padding
                          ] else ...[
                            // If no publish button, add spacer to push close button to right
                            const Spacer(),
                          ],
                          
                          // Close button with proper proportions
                          GestureDetector(
                            onTap: () => panelState.showPlaceholder(),
                            child: Container(
                              width: closeButtonSize,
                              height: closeButtonSize,
                              decoration: BoxDecoration(
                                color: Colors.grey.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(borderRadius * 0.3),
                                border: Border.all(
                                  color: Colors.grey.withOpacity(0.4),
                                  width: 1,
                                ),
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.close,
                                  color: Colors.grey,
                                  size: iconSize,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    SizedBox(height: spacingBetween), // Spacing between rows
                    
                    // Recordings area
                    Container(
                      height: recordingsHeight,
                      child: _buildRecordingsList(context, recording, recordingsHeight, panelWidth - (padding * 2)),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildRecordingsList(BuildContext context, RecordingState recording, double availableHeight, double availableWidth) {
    if (recording.localRecordings.isEmpty) {
      // Empty state with proportional sizing
      final emptyIconSize = availableHeight * 0.25;
      final emptyFontSize = availableHeight * 0.08;
      final emptyPadding = availableHeight * 0.05;
      
      return Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.2),
          borderRadius: BorderRadius.circular(emptyPadding),
          border: Border.all(color: Colors.grey.withOpacity(0.3)),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.mic_off,
                color: Colors.grey,
                size: emptyIconSize.clamp(12.0, 24.0),
              ),
              SizedBox(height: emptyPadding * 0.5),
              Text(
                'No recordings yet',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: emptyFontSize.clamp(6.0, 12.0),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Horizontal scrollable layout following sample_banks_widget pattern
    return LayoutBuilder(
      builder: (context, constraints) {
        final recordingCount = recording.localRecordings.length;
        
        // Use same pattern as sample_banks_widget: calculate item width to show 2.5 items
        final itemWidth = availableWidth / 2.5; // Show 2.5 items for scrolling hint
        final itemSpacing = availableHeight * 0.03; // Spacing as fraction of height
        final itemPadding = availableHeight * 0.04; // Internal padding as fraction of height
        
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: recording.localRecordings.asMap().entries.map((entry) {
              final index = entry.key;
              final recordingPath = entry.value;
              
              return Container(
                width: itemWidth,
                height: availableHeight,
                margin: EdgeInsets.only(
                  right: index < recordingCount - 1 ? itemSpacing : 0,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(itemPadding),
                  border: Border.all(
                    color: Colors.green.withOpacity(0.4),
                    width: 1,
                  ),
                ),
                child: _buildRecordingItem(context, recording, recordingPath, index, availableHeight, itemPadding),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildRecordingItem(BuildContext context, RecordingState recordingState, String recording, int index, double availableHeight, double itemPadding) {
    return LayoutBuilder(
      builder: (context, itemConstraints) {
        // Use same pattern as sample_banks_widget: 80% content height, proper spacing
        final contentHeight = itemConstraints.maxHeight * 0.8; // Use 80% of available height
        
        // Layout: title + spacing + buttons
        final titleHeight = contentHeight * 0.3; // 30% of content for title
        final spacingHeight = itemPadding * 0.5; // Spacing as fraction of base padding
        final buttonAreaHeight = contentHeight * 0.7 - spacingHeight; // 70% minus spacing
        
        // Sizing calculations
        final titleFontSize = (titleHeight * 0.4).clamp(6.0, 12.0);
        final buttonSize = buttonAreaHeight * 0.8; // Buttons take 80% of button area height
        final buttonIconSize = (buttonSize * 0.4).clamp(8.0, 16.0);
        final buttonSpacing = itemPadding * 0.4; // Spacing between buttons
        
        return Container(
          padding: EdgeInsets.all(itemPadding),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center, // Center content vertically
            children: [
              // Title section
              Container(
                height: titleHeight,
                child: Center(
                  child: Text(
                    'Take ${index + 1}',
                    style: TextStyle(
                      color: Colors.lightGreen,
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              
              SizedBox(height: spacingHeight), // Spacing between title and buttons
              
              // Button area
              Container(
                height: buttonAreaHeight,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Play button
                    Container(
                      width: buttonSize,
                      height: buttonSize,
                      child: _buildCompactActionButton(
                        icon: Icons.play_arrow,
                        color: Colors.green,
                        iconSize: buttonIconSize,
                        borderRadius: itemPadding * 0.5,
                        onTap: () => _playRecording(recording),
                      ),
                    ),
                    
                    SizedBox(width: buttonSpacing), // Spacing between buttons
                    
                    // Share button
                    Container(
                      width: buttonSize,
                      height: buttonSize,
                      child: _buildCompactActionButton(
                        icon: Icons.share,
                        color: Colors.blue,
                        iconSize: buttonIconSize,
                        borderRadius: itemPadding * 0.5,
                        onTap: () => _shareSpecificRecording(context, recording),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCompactActionButton({
    required IconData icon,
    required Color color,
    required double iconSize,
    required double borderRadius,
    required VoidCallback? onTap,
  }) {
    final isEnabled = onTap != null;
    final effectiveColor = isEnabled ? color : color.withOpacity(0.3);
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity, // Use full width/height of parent container
        height: double.infinity,
        decoration: BoxDecoration(
          color: effectiveColor.withOpacity(0.15),
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color: effectiveColor.withOpacity(0.5),
            width: 1,
          ),
        ),
        child: Center(
          child: Icon(
            icon,
            color: effectiveColor,
            size: iconSize,
          ),
        ),
      ),
    );
  }

  void _playRecording(String filePath) async {
    try {
      // TODO: Implement audio playback using your audio player
      // For now, just show a placeholder message
      debugPrint('Playing recording: $filePath');
    } catch (e) {
      debugPrint('Failed to play recording: $e');
    }
  }

  void _shareSpecificRecording(BuildContext context, String filePath) async {
    try {
      final file = File(filePath);
      
      if (await file.exists()) {
        final appName = dotenv.env['APP_NAME']!;
        await Share.shareXFiles(
          [XFile(filePath)],
          text: 'Check out my track created with $appName!',
          subject: '$appName track',
        );
      } else {
        _showError(context, 'Recording file not found');
      }
    } catch (e) {
      _showError(context, 'Failed to share recording: $e');
    }
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  void _publishProject(BuildContext context) async {
    try {
      // Close share panel
      Provider.of<MultitaskPanelState>(context, listen: false).showPlaceholder();
      
      // Show loading indicator
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Publishing project...'),
          backgroundColor: Colors.orangeAccent,
          duration: Duration(seconds: 2),
        ),
      );

      print('🚀 Starting publish process...');
      
      // Get active thread info before publishing
      final threadsState = Provider.of<ThreadsState>(context, listen: false);
      final activeThread = threadsState.activeThread;
      
      print('📋 Active thread before publish: ${activeThread?.id}');
      print('📋 Active thread messages count: ${activeThread?.messageIds.length ?? 0}');
      print('👤 Current user ID: ${threadsState.currentUserId}');
      print('👤 Current user name: ${threadsState.currentUserName}');

      // Publish to database (title will be auto-generated as 6-char ID)
      // Migrate to explicit publish flow handled elsewhere; stub here
      final success = true;
      
      print('✅ Publish result: $success');
      
      // Check active thread after publishing
      final activeThreadAfter = threadsState.activeThread;
      print('📋 Active thread after publish: ${activeThreadAfter?.id}');
      print('📋 Active thread messages count after: ${activeThreadAfter?.messageIds.length ?? 0}');
      
      if (!context.mounted) return;
      
      if (success) {
        // Refresh threads to make sure we have the latest data
        await threadsState.loadThreads();
        print('🔄 Threads refreshed after publish');
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Project published successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to publish project'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('❌ Publish error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
} 