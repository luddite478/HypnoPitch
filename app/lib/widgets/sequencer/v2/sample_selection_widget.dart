import 'package:flutter/material.dart';
import '../../../utils/log.dart';
import 'package:provider/provider.dart';
import '../../../utils/app_colors.dart';
import '../../../state/sequencer/sample_browser.dart';
import '../../../state/sequencer/sample_bank.dart';
import '../../../state/sequencer/playback.dart';
import '../../../state/sequencer/table.dart';
import '../../../state/app_state.dart';

Future<void> _selectSampleForCurrentTarget(
  BuildContext context, {
  required SampleBrowserState browserState,
  required SampleBankState sampleBankState,
  required SampleItem item,
}) async {
  final targetCol = browserState.targetCol;
  final targetStep = browserState.targetStep;
  final explicitBankSlot = browserState.targetBankSlot;
  final sampleId = item.sampleId;

  if (targetCol == null || sampleId == null) {
    browserState.hide();
    if (context.mounted) Navigator.of(context).pop();
    return;
  }

  int? resolvedSlot;
  var showSampleLimitDialog = false;

  // Cell-targeted selection should not overwrite an existing bank slot.
  // Resolve by sample id into a dedicated slot (or reuse same-id slot).
  if (targetStep != null) {
    resolvedSlot = await sampleBankState.loadSampleForCell(sampleId);
    if (resolvedSlot == null) {
      if (!sampleBankState.hasFreeDedicatedSlot) {
        showSampleLimitDialog = true;
        Log.d(
            '❌ Dedicated sample bank full (A–Y), cannot load sample id=$sampleId');
      } else {
        Log.d('❌ Failed to load sample id=$sampleId (load error?)');
      }
    } else {
      Log.d(
        'Loading sample id=$sampleId into dedicated bank slot $resolvedSlot (grid col $targetCol)',
      );
      final tableState = context.read<TableState>();
      tableState.setCell(targetStep, targetCol, resolvedSlot, -1.0, -1.0);
    }
  } else {
    // Explicit slot editing (sample bank context): keep existing behavior.
    final slot = explicitBankSlot ?? sampleBankState.activeSlot;
    if (slot >= 0 && slot < SampleBankState.maxSampleSlots) {
      Log.d('Loading sample id=$sampleId into explicit bank slot $slot');
      final success = await sampleBankState.loadSample(slot, sampleId);
      if (success) {
        resolvedSlot = slot;
      }
    }
  }

  if (resolvedSlot == null) {
    debugPrint('❌ Failed to resolve/load sample slot for id=$sampleId');
  } else {
    debugPrint('✅ Sample loaded into slot $resolvedSlot');
    // Tutorial step verification: real sample assignment completed.
    context.read<AppState>().completeSampleSelectionStep();
  }

  browserState.hide();
  if (context.mounted) Navigator.of(context).pop();

  if (showSampleLimitDialog && context.mounted) {
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1f2937),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: const Text(
            'Sample limit reached',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'You can load at most 25 different samples (A–Y) in this project. '
            'Remove a sample from the grid or unload one from the bank to add a new sound.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'OK',
                style: TextStyle(color: Colors.cyanAccent),
              ),
            ),
          ],
        );
      },
    );
  }
}

class SampleSelectionWidget extends StatelessWidget {
  const SampleSelectionWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<SampleBrowserState, SampleBankState>(
      builder: (context, sampleBrowserState, sampleBankState, child) {
        return Container(
          color: AppColors.sequencerSurfaceBase,
          child: _buildContent(context, sampleBrowserState, sampleBankState),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context, SampleBrowserState browserState, SampleBankState sampleBankState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Navigation bar (back button + current path)
        _buildNavBar(context, browserState),
        // Grid / list of items
        Expanded(
          child: _buildItemList(context, browserState, sampleBankState),
        ),
      ],
    );
  }

  Widget _buildNavBar(BuildContext context, SampleBrowserState browserState) {
    return Consumer<SampleBrowserState>(
      builder: (context, state, _) {
        final hasPath = state.currentPath.isNotEmpty;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.sequencerBorder, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              if (hasPath)
                GestureDetector(
                  onTap: () => state.navigateBack(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.sequencerSurfaceRaised,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.sequencerBorder, width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_back, color: AppColors.sequencerText, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          'BACK',
                          style: TextStyle(
                            color: AppColors.sequencerText,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (hasPath) const SizedBox(width: 8),
              Expanded(
                child: Text(
                  state.currentPath.isEmpty
                      ? 'samples/'
                      : 'samples/${state.currentPath.join('/')}/',
                  style: TextStyle(
                    color: AppColors.sequencerLightText,
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildItemList(BuildContext context, SampleBrowserState browserState, SampleBankState sampleBankState) {
    if (browserState.isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, color: AppColors.sequencerLightText, size: 24),
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
      );
    }

    if (browserState.currentItems.isEmpty) {
      final message =
          browserState.assetErrorMessage ?? 'No samples found';
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, color: AppColors.sequencerLightText, size: 24),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(
                color: AppColors.sequencerLightText,
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Consumer<SampleBrowserState>(
      builder: (context, state, _) {
        final items = state.currentItems;
        final folders = items.where((i) => i.isFolder).toList();
        final files = items.where((i) => !i.isFolder).toList();

        // Pure-file directory → list view with tap-to-play + SELECT button
        if (folders.isEmpty && files.isNotEmpty) {
          return _buildFileList(context, files, state, sampleBankState);
        }

        // Mixed or folder-only → 2-column grid
        return _buildFolderGrid(context, items, state, sampleBankState);
      },
    );
  }

  // ─── File list (pure-file directory) ───────────────────────────────────────

  Widget _buildFileList(
    BuildContext context,
    List<SampleItem> files,
    SampleBrowserState browserState,
    SampleBankState sampleBankState,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final item = files[index];
        return _FileListTile(item: item, browserState: browserState, sampleBankState: sampleBankState);
      },
    );
  }

  // ─── Folder / mixed grid ───────────────────────────────────────────────────

  Widget _buildFolderGrid(
    BuildContext context,
    List<SampleItem> items,
    SampleBrowserState browserState,
    SampleBankState sampleBankState,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = constraints.maxWidth * 0.02;
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: 2.0,
          ),
          itemCount: items.length,
          padding: EdgeInsets.all(spacing),
          itemBuilder: (context, index) {
            final item = items[index];
            return _GridTile(item: item, browserState: browserState, sampleBankState: sampleBankState);
          },
        );
      },
    );
  }
}

// ─── File list tile with tap-to-play + SELECT button ───────────────────────

class _FileListTile extends StatelessWidget {
  const _FileListTile({
    required this.item,
    required this.browserState,
    required this.sampleBankState,
  });

  final SampleItem item;
  final SampleBrowserState browserState;
  final SampleBankState sampleBankState;

  String get _formatLabel {
    final n = item.name.toLowerCase();
    if (n.endsWith('.wav')) return 'WAV';
    if (n.endsWith('.mp3')) return 'MP3';
    if (n.endsWith('.m4a')) return 'M4A';
    return 'AUDIO';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final playbackState = context.read<PlaybackState>();
        await browserState.previewSample(item, sampleBankState, playbackState);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // File name + format
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.sequencerText,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatLabel,
                      style: TextStyle(
                        color: AppColors.sequencerLightText,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // SELECT button
              _ActionButton(
                label: 'SELECT',
                filled: true,
                onTap: () async {
                  await _selectSampleForCurrentTarget(
                    context,
                    browserState: browserState,
                    sampleBankState: sampleBankState,
                    item: item,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Shared action button ───────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: filled ? AppColors.sequencerAccent : AppColors.sequencerAccent.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: AppColors.sequencerAccent.withOpacity(filled ? 1.0 : 0.6),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: filled ? AppColors.sequencerPageBackground : AppColors.sequencerAccent,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Grid tile (folder or file) ────────────────────────────────────────────

class _GridTile extends StatelessWidget {
  const _GridTile({
    required this.item,
    required this.browserState,
    required this.sampleBankState,
  });

  final SampleItem item;
  final SampleBrowserState browserState;
  final SampleBankState sampleBankState;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        if (item.isFolder) {
          browserState.navigateToFolder(item.name);
          return;
        }
        final playbackState = context.read<PlaybackState>();
        await browserState.previewSample(item, sampleBankState, playbackState);
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
            BoxShadow(
              color: AppColors.sequencerShadow,
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, tileConstraints) {
            final iconSize = tileConstraints.maxHeight * 0.4;
            final fontSize = tileConstraints.maxWidth * 0.08;

            if (item.isFolder) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.folder,
                        color: AppColors.sequencerAccent,
                        size: iconSize.clamp(20.0, 40.0),
                      ),
                      const SizedBox(height: 4),
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
              );
            }

            // File tile: tap tile to play, keep dedicated SELECT action
            return Column(
              children: [
                // Top — sample name / preview area
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: AppColors.sequencerSurfacePressed,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(4),
                        topRight: Radius.circular(4),
                      ),
                      border: Border(
                        bottom: BorderSide(color: AppColors.sequencerBorder, width: 1),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    alignment: Alignment.center,
                    child: Text(
                      item.name,
                      style: TextStyle(
                        color: AppColors.sequencerText,
                        fontSize: (fontSize * 0.75).clamp(7.0, 12.0),
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                // Bottom — SELECT
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      await _selectSampleForCurrentTarget(
                        context,
                        browserState: browserState,
                        sampleBankState: sampleBankState,
                        item: item,
                      );
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(6),
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
                          Text(
                            'SELECT',
                            style: TextStyle(
                              color: AppColors.sequencerPageBackground.withOpacity(0.9),
                              fontSize: (fontSize * 0.5).clamp(4.0, 9.0),
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
  }
}
