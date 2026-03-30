import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/sequencer/table.dart';
import '../../state/sequencer/sample_bank.dart';
import '../../state/sequencer/playback.dart';
import '../../state/sequencer/sample_browser.dart';
import '../../ffi/table_bindings.dart' show CellData;
import '../../utils/app_colors.dart';

/// Simplified sound grid widget for testing
/// 
/// Shows a grid of cells representing the sequencer table.
/// Supports 4 layers (sound grids) with layer switching.
/// Each cell shows the loaded sample and can be tapped to add/remove samples.
class SimplifiedSoundGrid extends StatefulWidget {
  const SimplifiedSoundGrid({super.key});

  @override
  State<SimplifiedSoundGrid> createState() => _SimplifiedSoundGridState();
}

class _SimplifiedSoundGridState extends State<SimplifiedSoundGrid> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer4<TableState, SampleBankState, PlaybackState, SampleBrowserState>(
      builder: (context, tableState, sampleBank, playback, sampleBrowser, child) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.sequencerSurfaceBase,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: AppColors.sequencerBorder,
              width: 1,
            ),
          ),
          child: Column(
            children: [
              // Layer selector and controls (always visible)
              _buildHeader(tableState),
              
              // Main content area - either grid or sample browser
              Expanded(
                child: sampleBrowser.isVisible 
                    ? _buildSampleBrowser(context, tableState, sampleBank, sampleBrowser)
                    : _buildGrid(tableState, sampleBank, playback),
              ),
              
              // Step controls (always visible)
              _buildStepControls(tableState),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(TableState tableState) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceRaised,
        border: Border(
          bottom: BorderSide(
            color: AppColors.sequencerBorder,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          const Text(
            'Layer:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          
          // Layer selector
          Expanded(
            child: Row(
              children: List.generate(tableState.totalLayers, (index) {
                final isActive = tableState.uiSelectedLayer == index;
                return GestureDetector(
                  onTap: () => tableState.setUiSelectedLayer(index),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isActive ? AppColors.sequencerAccent : AppColors.sequencerSurfacePressed,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isActive ? AppColors.sequencerAccent : AppColors.sequencerBorder,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: isActive ? AppColors.sequencerPageBackground : AppColors.sequencerText,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          
          // Grid info
          Text(
            '${tableState.getSectionStepCount()} steps',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(TableState tableState, SampleBankState sampleBank, PlaybackState playback) {
    final visibleCols = tableState.getVisibleCols();
    
    return ListView.builder(
      controller: _scrollController,
      itemCount: tableState.getSectionStepCount(),
      itemBuilder: (context, step) {
        return _buildGridRow(context, tableState, sampleBank, playback, step, visibleCols);
      },
    );
  }

  Widget _buildGridRow(BuildContext context, TableState tableState, SampleBankState sampleBank, 
                      PlaybackState playback, int step, List<int> visibleCols) {
    final isCurrentStep = playback.currentStep == step && playback.isPlaying;
    
    return Container(
      height: 50,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: isCurrentStep ? AppColors.sequencerAccent.withOpacity(0.1) : null,
        borderRadius: BorderRadius.circular(2),
        border: isCurrentStep ? Border.all(
          color: AppColors.sequencerAccent,
          width: 2,
        ) : null,
      ),
      child: Row(
        children: [
          // Step number
          Container(
            width: 40,
            child: Center(
              child: Text(
                '${step + 1}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isCurrentStep ? AppColors.sequencerAccent : AppColors.sequencerText,
                ),
              ),
            ),
          ),
          
          // Grid cells for visible columns
          Expanded(
            child: Row(
              children: visibleCols.map((col) {
                return Expanded(
                  child: _buildGridCell(context, tableState, sampleBank, step, col),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridCell(BuildContext context, TableState tableState, SampleBankState sampleBank, 
                       int step, int col) {
    return ValueListenableBuilder<CellData>(
      valueListenable: tableState.getCellNotifier(step, col),
      builder: (context, cellData, child) {
        final isEmpty = cellData.isEmpty;
        final sampleSlot = cellData.sampleSlot;
        
        return GestureDetector(
          onTap: () => _handleCellTap(tableState, sampleBank, step, col, isEmpty, sampleSlot),
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: _getCellColor(isEmpty, sampleSlot, sampleBank),
              borderRadius: BorderRadius.circular(2),
              border: Border.all(
                color: AppColors.sequencerBorder,
                width: 1,
              ),
            ),
            child: Center(
              child: _getCellContent(isEmpty, sampleSlot, sampleBank, cellData),
            ),
          ),
        );
      },
    );
  }

  Widget _getCellContent(bool isEmpty, int sampleSlot, SampleBankState sampleBank, CellData cellData) {
    if (isEmpty) {
      return Container(); // Empty cell
    } else {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${sampleSlot + 1}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: Colors.white,
            ),
          ),
          if (cellData.volume != 1.0)
            Text(
              '${(cellData.volume * 100).round()}%',
              style: const TextStyle(
                fontSize: 8,
                color: Colors.white70,
              ),
            ),
        ],
      );
    }
  }

  Color _getCellColor(bool isEmpty, int sampleSlot, SampleBankState sampleBank) {
    if (isEmpty) {
      return AppColors.sequencerSurfacePressed;
    } else {
      // Use the same color logic as sample bank
      final colors = [
        AppColors.sequencerAccent,
        AppColors.sequencerSecondaryButton,
        Colors.blue,
        Colors.green,
        Colors.orange,
        Colors.purple,
      ];
      return colors[sampleSlot % colors.length];
    }
  }

  void _handleCellTap(TableState tableState, SampleBankState sampleBank, 
                     int step, int col, bool isEmpty, int currentSampleSlot) {
    final sampleBrowser = Provider.of<SampleBrowserState>(context, listen: false);
    
    if (isEmpty) {
      sampleBrowser.showForCell(step, col, bankSlot: sampleBank.activeSlot);
      debugPrint('🎯 Opening sample browser for empty cell [$step, $col] slot=${sampleBank.activeSlot}');
    } else {
      // Remove sample from cell
      tableState.clearCell(step, col);
      debugPrint('🗑️ Removed sample from cell [$step, $col]');
    }
  }

  Widget _buildStepControls(TableState tableState) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceRaised,
        border: Border(
          top: BorderSide(
            color: AppColors.sequencerBorder,
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Decrease steps
          ElevatedButton(
            onPressed: tableState.getSectionStepCount() > 1 ? () {
              final newSteps = tableState.getSectionStepCount() - 1;
              tableState.setSectionStepCount(tableState.uiSelectedSection, newSteps);
            } : null,
            child: const Icon(Icons.remove),
          ),
          
          Text(
            '${tableState.getSectionStepCount()} steps',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          
          // Increase steps
          ElevatedButton(
            onPressed: tableState.getSectionStepCount() < 256 ? () {
              final newSteps = tableState.getSectionStepCount() + 1;
              tableState.setSectionStepCount(tableState.uiSelectedSection, newSteps);
            } : null,
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  // 🔥 TEMPORARY SAMPLE BROWSER INTEGRATION
  // This shows the existing sample browser widget when a cell is clicked
  Widget _buildSampleBrowser(BuildContext context, TableState tableState, 
                           SampleBankState sampleBank, SampleBrowserState sampleBrowser) {
    return Container(
      color: AppColors.sequencerSurfaceBase,
      child: Column(
        children: [
          // Header with cell info and close button
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            decoration: BoxDecoration(
              color: AppColors.sequencerSurfaceRaised,
              border: Border(
                bottom: BorderSide(
                  color: AppColors.sequencerBorder,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.music_note,
                  color: AppColors.sequencerAccent,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  'Select sample for cell [${sampleBrowser.targetStep! + 1}, ${sampleBrowser.targetCol! + 1}]',
                  style: TextStyle(
                    color: AppColors.sequencerText,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => sampleBrowser.hide(),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.sequencerSurfacePressed,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                        color: AppColors.sequencerBorder,
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      Icons.close,
                      color: AppColors.sequencerAccent,
                      size: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Sample browser content
          Expanded(
            child: _buildCustomSampleBrowser(context, tableState, sampleBank, sampleBrowser),
          ),
        ],
      ),
    );
  }

  // Custom sample browser implementation based on the v1 widget
  Widget _buildCustomSampleBrowser(BuildContext context, TableState tableState, 
                                  SampleBankState sampleBank, SampleBrowserState sampleBrowser) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Navigation header
          Row(
            children: [
              if (sampleBrowser.currentPath.isNotEmpty) ...[
                GestureDetector(
                  onTap: () => sampleBrowser.navigateBack(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.sequencerSurfaceRaised,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                        color: AppColors.sequencerBorder,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.arrow_back,
                          color: AppColors.sequencerText,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'BACK',
                          style: TextStyle(
                            color: AppColors.sequencerText,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  sampleBrowser.currentPath.isEmpty 
                      ? 'samples/' 
                      : 'samples/${sampleBrowser.currentPath.join('/')}/',
                  style: TextStyle(
                    color: AppColors.sequencerLightText,
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Sample items grid
          Expanded(
            child: sampleBrowser.currentItems.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.folder_open,
                          color: AppColors.sequencerLightText,
                          size: 32,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Loading samples...',
                          style: TextStyle(
                            color: AppColors.sequencerLightText,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                : GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 1.2,
                    ),
                    itemCount: sampleBrowser.currentItems.length,
                    itemBuilder: (context, index) {
                      final item = sampleBrowser.currentItems[index];
                      return GestureDetector(
                        onTap: () async => _handleSampleItemTap(
                          context, tableState, sampleBank, sampleBrowser, item),
                        child: Container(
                          decoration: BoxDecoration(
                            color: item.isFolder 
                                ? AppColors.sequencerSurfaceRaised
                                : AppColors.sequencerAccent.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: item.isFolder 
                                  ? AppColors.sequencerBorder
                                  : AppColors.sequencerAccent,
                              width: 1,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                item.isFolder ? Icons.folder : Icons.music_note,
                                color: item.isFolder 
                                    ? AppColors.sequencerAccent
                                    : AppColors.sequencerText,
                                size: 24,
                              ),
                              const SizedBox(height: 4),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Text(
                                  item.name,
                                  style: TextStyle(
                                    color: AppColors.sequencerText,
                                    fontSize: 10,
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
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // Handle sample item selection
  Future<void> _handleSampleItemTap(BuildContext context, TableState tableState, 
                           SampleBankState sampleBank, SampleBrowserState sampleBrowser, 
                           SampleItem item) async {
    if (item.isFolder) {
      // Navigate into folder
      sampleBrowser.navigateToFolder(item.name);
    } else {
      // Select sample by manifest id
      final sampleId = item.sampleId;
      if (sampleId != null && sampleBrowser.targetStep != null && sampleBrowser.targetCol != null) {
        final slot = await _loadSampleIntoBankById(sampleBank, sampleId);
        final success = slot != -1;
        if (success) {
          tableState.setCell(sampleBrowser.targetStep!, sampleBrowser.targetCol!, slot, 1.0, 1.0);
          debugPrint('✅ Added sample id=$sampleId to cell [${sampleBrowser.targetStep}, ${sampleBrowser.targetCol}] with slot $slot');
        }
        sampleBrowser.hide();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Sample added to cell!' : 'Failed to load sample'),
            duration: const Duration(seconds: 1),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }

  // Load sample by manifest id into the first available bank slot
  Future<int> _loadSampleIntoBankById(SampleBankState sampleBank, String sampleId) async {
    for (int i = 0; i < 26; i++) {
      if (!sampleBank.isSlotLoaded(i)) {
        final success = await sampleBank.loadSample(i, sampleId);
        return success ? i : -1;
      }
    }
    return -1; // No empty slots
  }
}



