import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../utils/app_colors.dart';
import '../../../state/sequencer/sample_browser.dart';
import '../../../state/sequencer/sample_bank.dart';
import '../../../ffi/playback_bindings.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:io';

// Main sizing control variables for easy adjustment
class SampleBrowserSizing {
  // Tile dimensions
  static const double tileAspectRatio = 2.0; // Width:Height ratio (makes tiles shorter)
  static const double tileSpacing = 2.0; // Spacing between tiles in percent of screen width
  static const double tilePadding = 1.5; // Internal padding in percent of tile size
  
  // File tile split ratios
  static const double playButtonAreaRatio = 0.5; // Top 50% for play button
  static const double pickAreaRatio = 0.5; // Bottom 50% for file info
  
  // Button sizes
  static const double headerButtonHeight = 12.0; // Header buttons height in percent of header
  static const double closeButtonSize = 8.0; // Close button size in percent of screen width
  static const double backButtonHeight = 8.0; // Back button height in percent of header
}

class SampleSelectionWidget extends StatelessWidget {
  const SampleSelectionWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<SampleBrowserState, SampleBankState>(
      builder: (context, sampleBrowserState, sampleBankState, child) {

        
        return Container(
          decoration: BoxDecoration(
            color: AppColors.sequencerSurfaceBase,
            borderRadius: BorderRadius.circular(2), // Sharp corners
            border: Border.all(
              color: AppColors.sequencerBorder,
              width: 1,
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
          child: _buildSampleBrowser(context),
        );
      },
    );
  }

  Widget _buildSampleBrowser(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with sample selection info - using responsive sizing
          LayoutBuilder(
            builder: (context, headerConstraints) {
              final screenWidth = headerConstraints.maxWidth;
              final backButtonHeight = screenWidth * (SampleBrowserSizing.backButtonHeight / 100);
              final closeButtonSize = screenWidth * (SampleBrowserSizing.closeButtonSize / 100);
              final headerFontSize = screenWidth * 0.035;
              final pathFontSize = screenWidth * 0.025;
              
              // Access state from context within the nested builder
              final browserState = context.read<SampleBrowserState>();
              
              return Row(
                children: [
                  if (browserState.currentPath.isNotEmpty) ...[
                                          GestureDetector(
                        onTap: () {
                          // Navigation works the same for both browsers
                          browserState.navigateBack();
                        },
                      child: Container(
                        height: backButtonHeight.clamp(32.0, 50.0),
                        padding: EdgeInsets.symmetric(
                          horizontal: screenWidth * 0.03,
                          vertical: screenWidth * 0.01,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.sequencerSurfaceRaised,
                          borderRadius: BorderRadius.circular(6),
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
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.arrow_back, 
                              color: AppColors.sequencerText, 
                              size: (headerFontSize * 1.2).clamp(14.0, 20.0),
                            ),
                            SizedBox(width: screenWidth * 0.015),
                            Text(
                              'BACK',
                              style: TextStyle(
                                color: AppColors.sequencerText,
                                fontSize: headerFontSize.clamp(12.0, 16.0),
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(width: screenWidth * 0.02),
                  ],
                  Expanded(
                    child: Text(
                      browserState.currentPath.isEmpty 
                          ? 'samples/' 
                          : 'samples/${browserState.currentPath.join('/')}/',
                      style: TextStyle(
                        color: AppColors.sequencerLightText,
                        fontSize: pathFontSize.clamp(10.0, 14.0),
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.3,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      // Close the sample browser using the new state
                      browserState.hide();
                    },
                    child: Container(
                      width: closeButtonSize.clamp(40.0, 60.0),
                      height: closeButtonSize.clamp(40.0, 60.0),
                      decoration: BoxDecoration(
                        color: AppColors.sequencerSurfacePressed,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: AppColors.sequencerAccent.withOpacity(0.8),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.sequencerShadow,
                            blurRadius: 3,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.close,
                        color: AppColors.sequencerAccent,
                        size: (closeButtonSize * 0.5).clamp(18.0, 28.0),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          
          // Vertical scrolling 2-column grid as requested
          Expanded(
            child: context.watch<SampleBrowserState>().isLoading
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.folder_open,
                          color: AppColors.sequencerLightText,
                          size: 24,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Loading samples...',
                          style: TextStyle(
                            color: AppColors.sequencerLightText,
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  )
                : context.watch<SampleBrowserState>().currentItems.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.folder_open,
                          color: AppColors.sequencerLightText,
                          size: 24,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No samples found',
                          style: TextStyle(
                            color: AppColors.sequencerLightText,
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final screenWidth = constraints.maxWidth;
                      final spacing = screenWidth * (SampleBrowserSizing.tileSpacing / 100);
                      
                      final items = context.watch<SampleBrowserState>().currentItems;
                      final folders = items.where((i) => i.isFolder).toList();
                      final files = items.where((i) => !i.isFolder).toList();

                      // If this folder contains files (and no subfolders), show a simple list of files
                      if (folders.isEmpty && files.isNotEmpty) {
                        return ListView.builder(
                          padding: EdgeInsets.all(spacing),
                          itemCount: files.length,
                          itemBuilder: (context, index) {
                            final item = files[index];
                            final browserState = context.read<SampleBrowserState>();
                            final sampleBankState = context.read<SampleBankState>();

                            final fileNameStyle = TextStyle(
                              color: AppColors.sequencerText,
                              fontSize: (screenWidth * 0.035).clamp(12.0, 16.0),
                              fontWeight: FontWeight.w600,
                            );
                            final metaStyle = TextStyle(
                              color: AppColors.sequencerLightText,
                              fontSize: (screenWidth * 0.028).clamp(10.0, 13.0),
                              fontWeight: FontWeight.w600,
                            );

                            return Container(
                              margin: EdgeInsets.only(bottom: spacing),
                              decoration: BoxDecoration(
                                color: AppColors.sequencerSurfaceRaised,
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
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(6),
                                  onTap: () async {
                                    final targetSlot = browserState.targetCol;
                                    if (targetSlot != null && item.sampleId != null) {
                                      debugPrint('🎵 Loading sample id=${item.sampleId} into slot $targetSlot');
                                      final success = await sampleBankState.loadSample(targetSlot, item.sampleId!);
                                      debugPrint(success ? '✅ Sample loaded successfully' : '❌ Failed to load sample');
                                    }
                                    browserState.hide();
                                  },
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(horizontal: spacing, vertical: spacing * 0.8),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: fileNameStyle,
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                item.name.toLowerCase().endsWith('.wav') ? 'WAV' :
                                                item.name.toLowerCase().endsWith('.mp3') ? 'MP3' :
                                                item.name.toLowerCase().endsWith('.m4a') ? 'M4A' : 'AUDIO',
                                                style: metaStyle,
                                              ),
                                            ],
                                          ),
                                        ),
                                        GestureDetector(
                                          onTap: () async {
                                            // Preview asset by dumping it to a temp file, then calling native preview
                                            final bindings = PlaybackBindings();
                                            final assetPath = item.path;
                                            if (assetPath.isNotEmpty) {
                                              try {
                                                final data = await rootBundle.load(assetPath);
                                                final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
                                                final safeName = assetPath.replaceAll('/', '_');
                                                final tmpFile = File('${Directory.systemTemp.path}/preview_$safeName');
                                                await tmpFile.writeAsBytes(bytes, flush: true);
                                                final cPath = tmpFile.path.toNativeUtf8();
                                                try {
                                                  bindings.previewSamplePath(cPath, 1.0, 1.0);
                                                } finally {
                                                  malloc.free(cPath);
                                                }
                                              } catch (_) {}
                                            }
                                          },
                                          child: Container(
                                            width: (screenWidth * 0.10).clamp(40.0, 56.0),
                                            height: (screenWidth * 0.10).clamp(40.0, 56.0),
                                            decoration: BoxDecoration(
                                              color: AppColors.sequencerAccent.withOpacity(0.15),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: AppColors.sequencerAccent.withOpacity(0.6), width: 1),
                                            ),
                                            child: Icon(
                                              Icons.play_arrow,
                                              color: AppColors.sequencerAccent,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      }

                      // Otherwise keep existing grid (folders or mixed content)
                      return GridView.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2, // 2 columns as requested
                          crossAxisSpacing: spacing,
                          mainAxisSpacing: spacing,
                          childAspectRatio: SampleBrowserSizing.tileAspectRatio, // Controlled aspect ratio
                        ),
                        itemCount: items.length,
                        padding: EdgeInsets.all(spacing),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final browserState = context.read<SampleBrowserState>();
                            
                      return GestureDetector(
                        onTap: () {
                          // Only handle folder navigation at the main tile level
                          if (item.isFolder) {
                            browserState.navigateToFolder(item.name);
                          }
                          // File selection is handled by the bottom part's onTap
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: item.isFolder 
                                ? AppColors.sequencerSurfaceRaised
                                : AppColors.sequencerAccent.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: item.isFolder 
                                  ? AppColors.sequencerBorder
                                  : AppColors.sequencerAccent.withOpacity(0.6),
                              width: 1,
                            ),
                            boxShadow: [
                              // Protruding effect for all items
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
                          child: LayoutBuilder(
                            builder: (context, tileConstraints) {
                              final tilePadding = tileConstraints.maxWidth * (SampleBrowserSizing.tilePadding / 100);
                              final iconSize = tileConstraints.maxHeight * 0.4;
                              final fontSize = tileConstraints.maxWidth * 0.08;
                              
                              return item.isFolder 
                                  ? // Folder layout
                                    Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(tilePadding),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.folder,
                                              color: AppColors.sequencerAccent,
                                              size: iconSize.clamp(20.0, 40.0),
                                            ),
                                            SizedBox(height: tilePadding * 0.5),
                                            Flexible(
                                              child: Text(
                                                item.name,
                                                style: TextStyle(
                                                  color: AppColors.sequencerText,
                                                  fontSize: fontSize.clamp(8.0, 14.0),
                                                  fontWeight: FontWeight.w500,
                                                ),
                                                textAlign: TextAlign.center,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                  : // File layout with 50/50 split
                                    Column(
                                      children: [
                                        // Top 50% - Play button area
                                        Expanded(
                                          flex: (SampleBrowserSizing.playButtonAreaRatio * 100).round(),
                                          child: GestureDetector(
                                            onTap: () async {
                                              final bindings = PlaybackBindings();
                                              final assetPath = item.path;
                                              if (assetPath.isNotEmpty) {
                                                try {
                                                  final data = await rootBundle.load(assetPath);
                                                  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
                                                  final safeName = assetPath.replaceAll('/', '_');
                                                  final tmpFile = File('${Directory.systemTemp.path}/preview_$safeName');
                                                  await tmpFile.writeAsBytes(bytes, flush: true);
                                                  final cPath = tmpFile.path.toNativeUtf8();
                                                  try {
                                                    bindings.previewSamplePath(cPath, 1.0, 1.0);
                                                  } finally {
                                                    malloc.free(cPath);
                                                  }
                                                } catch (_) {}
                                              }
                                            },
                                            child: Container(
                                              width: double.infinity,
                                              decoration: BoxDecoration(
                                                color: AppColors.sequencerSurfacePressed,
                                                borderRadius: const BorderRadius.only(
                                                  topLeft: Radius.circular(4),
                                                  topRight: Radius.circular(4),
                                                ),
                                                border: const Border(
                                                  bottom: BorderSide(
                                                    color: AppColors.sequencerBorder,
                                                    width: 1,
                                                  ),
                                                ),
                                              ),
                                              child: Center(
                                                child: Container(
                                                  width: tileConstraints.maxHeight * 0.25,
                                                  height: tileConstraints.maxHeight * 0.25,
                                                  decoration: BoxDecoration(
                                                    color: AppColors.sequencerAccent.withOpacity(0.9),
                                                    borderRadius: BorderRadius.circular(tileConstraints.maxHeight * 0.125),
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
                                                    ],
                                                  ),
                                                  child: Icon(
                                                    Icons.play_arrow,
                                                    color: AppColors.sequencerPageBackground,
                                                    size: (tileConstraints.maxHeight * 0.15).clamp(12.0, 20.0),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        // Bottom 50% - Pick/Select area
                                        Expanded(
                                          flex: (SampleBrowserSizing.pickAreaRatio * 100).round(),
                                          child: GestureDetector(
                                            onTap: () async {
                                              final browserState = context.read<SampleBrowserState>();
                                              final sampleBankState = context.read<SampleBankState>();
                                              
                                              if (item.isFolder) {
                                                browserState.navigateToFolder(item.name);
                                              } else {
                                                // Load sample by manifest id into the target slot
                                                final targetSlot = browserState.targetCol;
                                                if (targetSlot != null && item.sampleId != null) {
                                                  debugPrint('🎵 Loading sample id=${item.sampleId} into slot $targetSlot');
                                                  final success = await sampleBankState.loadSample(targetSlot, item.sampleId!);
                                                  debugPrint(success ? '✅ Sample loaded successfully' : '❌ Failed to load sample');
                                                }
                                                // Hide the browser after selection
                                                browserState.hide();
                                              }
                                            },
                                            child: Container(
                                              width: double.infinity,
                                              padding: EdgeInsets.all(tilePadding),
                                              decoration: const BoxDecoration(
                                                color: AppColors.sequencerAccent,
                                                borderRadius: BorderRadius.only(
                                                  bottomLeft: Radius.circular(4),
                                                  bottomRight: Radius.circular(4),
                                                ),
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  // File name
                                                  Expanded(
                                                    child: Text(
                                                      item.name,
                                                      style: TextStyle(
                                                        color: AppColors.sequencerPageBackground,
                                                        fontSize: (fontSize * 0.8).clamp(6.0, 12.0),
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                      maxLines: 2,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  // File type and tap hint
                                                  Text(
                                                    item.name.toLowerCase().endsWith('.wav') ? 'WAV' :
                                                    item.name.toLowerCase().endsWith('.mp3') ? 'MP3' :
                                                    item.name.toLowerCase().endsWith('.m4a') ? 'M4A' : 'AUDIO',
                                                    style: TextStyle(
                                                      color: AppColors.sequencerPageBackground.withOpacity(0.8),
                                                      fontSize: (fontSize * 0.6).clamp(5.0, 10.0),
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                  Text(
                                                    'TAP TO SELECT',
                                                    style: TextStyle(
                                                      color: AppColors.sequencerPageBackground.withOpacity(0.9),
                                                      fontSize: (fontSize * 0.5).clamp(4.0, 8.0),
                                                      fontWeight: FontWeight.w700,
                                                      letterSpacing: 0.5,
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
                          ),
                        ),
                        );
                      },
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
} 