import 'dart:async';

import 'package:flutter/material.dart';
import '../../../utils/log.dart';
import 'package:provider/provider.dart';
import '../../../utils/app_colors.dart';
import '../../../utils/audio_duration_probe.dart';
import '../../../state/sequencer/sample_browser.dart';
import '../../../state/sequencer/sample_bank.dart';
import '../../../state/sequencer/playback.dart';
import '../../../state/sequencer/table.dart';
import '../../../state/sequencer/edit.dart';
import '../../../state/app_state.dart';
import '../../pattern_recordings_overlay.dart';

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
            '❌ Dedicated sample bank full (1-${SampleBankState.previewSlot}), cannot load sample id=$sampleId');
      } else {
        Log.d('❌ Failed to load sample id=$sampleId (load error?)');
      }
    } else {
      final slot = resolvedSlot;
      Log.d(
        'Loading sample id=$sampleId into dedicated bank slot $slot (grid col $targetCol)',
      );
      final tableState = context.read<TableState>();
      final editState = context.read<EditState>();
      final abs = editState.getSelectedAbsoluteCells();
      if (editState.isInSelectionMode && abs.length > 1) {
        tableState.runCellBatchEdit(() {
          for (final c in abs) {
            tableState.setCell(c.step, c.col, slot, -1.0, -1.0);
          }
        });
      } else {
        tableState.setCell(targetStep, targetCol, slot, -1.0, -1.0);
      }
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
    final userSlotsCount = SampleBankState.previewSlot;
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        final screenSize = MediaQuery.sizeOf(dialogContext);
        final dialogWidth =
            screenSize.width * PatternRecordingsOverlay.kDialogWidthFactor;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.zero,
          child: Center(
            child: Container(
              width: dialogWidth,
              decoration: BoxDecoration(
                color: AppColors.sequencerSurfaceRaised,
                borderRadius: BorderRadius.circular(1.0),
                border: Border.all(
                  color: AppColors.sequencerBorder,
                  width: 0.5,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: AppColors.sequencerBorder,
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Sample limit reached',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.sequencerText,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        IconButton(
                          icon:
                              Icon(Icons.close, color: AppColors.sequencerText),
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          iconSize: 18,
                          padding: const EdgeInsets.all(6),
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                    child: Text(
                      'You can load at most $userSlotsCount different samples '
                      '(slots 1-$userSlotsCount) in '
                      'this project. Remove a sample from the grid or unload '
                      'one from the bank to add a new sound.',
                      style: TextStyle(
                        fontSize: 16,
                        color: AppColors.sequencerLightText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
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

  Widget _buildContent(BuildContext context, SampleBrowserState browserState,
      SampleBankState sampleBankState) {
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.sequencerSurfaceRaised,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: AppColors.sequencerBorder, width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_back,
                            color: AppColors.sequencerText, size: 16),
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

  Widget _buildItemList(BuildContext context, SampleBrowserState browserState,
      SampleBankState sampleBankState) {
    if (browserState.isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open,
                color: AppColors.sequencerLightText, size: 24),
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
      final message = browserState.assetErrorMessage ?? 'No samples found';
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open,
                color: AppColors.sequencerLightText, size: 24),
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
        return _FileListTile(
            item: item,
            browserState: browserState,
            sampleBankState: sampleBankState);
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
            return _GridTile(
                item: item,
                browserState: browserState,
                sampleBankState: sampleBankState);
          },
        );
      },
    );
  }
}

/// Same chrome as [PatternRecordingsOverlay] recording rows: play column, info,
/// single action (SELECT) instead of add-to-library + menu, plus progress bar.
class _SampleBrowserAudioTile extends StatefulWidget {
  const _SampleBrowserAudioTile({
    required this.item,
    required this.browserState,
    required this.sampleBankState,
  });

  final SampleItem item;
  final SampleBrowserState browserState;
  final SampleBankState sampleBankState;

  @override
  State<_SampleBrowserAudioTile> createState() =>
      _SampleBrowserAudioTileState();
}

class _SampleBrowserAudioTileState extends State<_SampleBrowserAudioTile> {
  double? _durationSec;
  double _progress = 0;
  DateTime? _previewStart;
  Timer? _progressTimer;
  int? _lastHandledGeneration;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    widget.browserState.addListener(_onBrowserChanged);
    _listening = true;
    _loadDuration();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onBrowserChanged();
    });
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    if (_listening) {
      widget.browserState.removeListener(_onBrowserChanged);
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _SampleBrowserAudioTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.browserState != widget.browserState) {
      oldWidget.browserState.removeListener(_onBrowserChanged);
      widget.browserState.addListener(_onBrowserChanged);
    }
    if (oldWidget.item.path != widget.item.path ||
        oldWidget.item.isCustom != widget.item.isCustom) {
      _durationSec = null;
      _loadDuration();
    }
  }

  Future<void> _loadDuration() async {
    final sec = await AudioDurationProbe.secondsForSampleBrowserPath(
      path: widget.item.path,
      isCustom: widget.item.isCustom,
    );
    if (!mounted) return;
    setState(() => _durationSec = sec);
  }

  void _onBrowserChanged() {
    final id = widget.browserState.previewingSampleId;
    final gen = widget.browserState.previewGeneration;
    final isThis = id == widget.item.sampleId;

    if (!isThis) {
      if (_progressTimer != null || _progress > 0) {
        _progressTimer?.cancel();
        _progressTimer = null;
        _lastHandledGeneration = null;
        setState(() {
          _progress = 0;
          _previewStart = null;
        });
      }
      return;
    }

    if (_lastHandledGeneration != gen) {
      _lastHandledGeneration = gen;
      _previewStart = DateTime.now();
      _progressTimer?.cancel();
      _progressTimer =
          Timer.periodic(const Duration(milliseconds: 40), _tickProgress);
      setState(() => _progress = 0);
    }
  }

  void _tickProgress(Timer timer) {
    if (!mounted) return;
    final start = _previewStart;
    if (start == null) return;
    const fallbackSec = 3.0;
    final total = (_durationSec != null && _durationSec! > 0)
        ? _durationSec!
        : fallbackSec;
    final elapsed = DateTime.now().difference(start).inMilliseconds / 1000.0;
    final p = (elapsed / total).clamp(0.0, 1.0);
    if (p >= 1.0) {
      timer.cancel();
      _progressTimer = null;
      if (!mounted) return;
      final playbackState = context.read<PlaybackState>();
      widget.browserState.stopActiveSamplePreview(playbackState);
      setState(() {
        _progress = 0;
        _previewStart = null;
      });
      return;
    }
    setState(() => _progress = p);
  }

  @override
  Widget build(BuildContext context) {
    final playbackState = context.read<PlaybackState>();
    final id = widget.browserState.previewingSampleId;
    final isThisPreview = id == widget.item.sampleId;
    final showProgressBar =
        isThisPreview && (_progress > 0 || _progressTimer != null);
    final isActivelyPreviewing = isThisPreview && _progress < 1.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final isVerySmall = availableWidth < 350;

        return Container(
          decoration: BoxDecoration(
            color: AppColors.sequencerSurfaceBase,
            borderRadius: BorderRadius.circular(1.0),
            border: Border.all(
              color: AppColors.sequencerBorder,
              width: 0.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.sequencerSurfaceRaised,
                      border: Border(
                        right: BorderSide(
                          color: AppColors.sequencerBorder,
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: IconButton(
                      onPressed: widget.item.sampleId == null
                          ? null
                          : () async {
                              if (isActivelyPreviewing) {
                                widget.browserState
                                    .stopActiveSamplePreview(playbackState);
                              } else {
                                await widget.browserState.previewSample(
                                  widget.item,
                                  widget.sampleBankState,
                                  playbackState,
                                );
                              }
                            },
                      icon: Icon(
                        isActivelyPreviewing
                            ? Icons.stop_rounded
                            : Icons.play_arrow,
                        size: 22,
                      ),
                      color: AppColors.sequencerAccent,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: isVerySmall ? 6 : 8,
                        vertical: 6,
                      ),
                      child: Text(
                        widget.item.name,
                        style: TextStyle(
                          fontSize: isVerySmall ? 13 : 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.sequencerText,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: AppColors.sequencerBorder,
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: widget.item.sampleId == null
                            ? null
                            : () async {
                                await _selectSampleForCurrentTarget(
                                  context,
                                  browserState: widget.browserState,
                                  sampleBankState: widget.sampleBankState,
                                  item: widget.item,
                                );
                              },
                        child: Container(
                          constraints: const BoxConstraints(
                            minWidth: 72,
                            maxHeight: 44,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          alignment: Alignment.center,
                          child: Text(
                            'SELECT',
                            style: TextStyle(
                              fontSize: isVerySmall ? 11 : 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: AppColors.sequencerAccent,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (showProgressBar)
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: AppColors.sequencerBorder,
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: Stack(
                    children: [
                      Container(
                        color: AppColors.sequencerSurfaceRaised,
                      ),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: _progress.clamp(0.0, 1.0),
                        child: Container(
                          color: AppColors.sequencerAccent,
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
}

// ─── File list tile (Takes-style row) ──────────────────────────────────────

class _FileListTile extends StatelessWidget {
  const _FileListTile({
    required this.item,
    required this.browserState,
    required this.sampleBankState,
  });

  final SampleItem item;
  final SampleBrowserState browserState;
  final SampleBankState sampleBankState;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: _SampleBrowserAudioTile(
        item: item,
        browserState: browserState,
        sampleBankState: sampleBankState,
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
    if (!item.isFolder) {
      return Padding(
        padding: const EdgeInsets.all(2),
        child: Center(
          child: _SampleBrowserAudioTile(
            item: item,
            browserState: browserState,
            sampleBankState: sampleBankState,
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () =>
          browserState.navigateToFolder(item.name, folderKey: item.folderKey),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.sequencerSurfaceRaised,
          borderRadius: BorderRadius.circular(4),
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
        child: LayoutBuilder(
          builder: (context, tileConstraints) {
            final iconSize = tileConstraints.maxHeight * 0.4;
            final fontSize = tileConstraints.maxWidth * 0.08;

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
          },
        ),
      ),
    );
  }
}
