import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../state/sequencer/table.dart';
import '../../../state/sequencer/playback.dart';
import '../../../state/sequencer/microphone.dart';
import '../../../state/sequencer/recording.dart';
import '../../../state/sequencer/recording_waveform.dart';
import '../../../state/sequencer/slider_overlay.dart';
import '../../../state/app_state.dart';
import '../../../config/feature_flags.dart';
import '../../../utils/app_colors.dart';
import 'generic_slider.dart';
import 'offset_controls_widget.dart';

class LayerSettingsWidget extends StatefulWidget {
  const LayerSettingsWidget({super.key});

  @override
  State<LayerSettingsWidget> createState() => _LayerSettingsWidgetState();
}

class _LayerSettingsWidgetState extends State<LayerSettingsWidget> {
  String _selectedMicControl = 'VOL';

  double _headerButtonsHeight = 0.45;
  double _contentHeightPercent = 0.50;
  double _spacingHeight = 0.02;

  @override
  Widget build(BuildContext context) {
    return Consumer2<TableState, PlaybackState>(
      builder: (context, tableState, playbackState, child) {
        final micState = context.watch<MicrophoneState>();
        final recordingState = context.watch<RecordingState>();
        final waveformState = context.watch<RecordingWaveformState>();
        final layerIndex = tableState.uiSelectedLayer;

        return LayoutBuilder(
          builder: (context, constraints) {
            final panelHeight = constraints.maxHeight;
            final padding = panelHeight * 0.03;

            final innerHeight = panelHeight - padding * 2;
            const borderThickness = 1.0;
            final innerHeightAdj = innerHeight - borderThickness * 2;

            final headerHeight = innerHeightAdj * _headerButtonsHeight;
            final contentHeight = innerHeightAdj * _contentHeightPercent;
            final labelFontSize = (headerHeight * 0.25).clamp(8.0, 11.0);
            int safeFlex(double fraction) {
              final flex = (fraction * 100).round();
              return flex > 0 ? flex : 1;
            }

            return Container(
              padding: EdgeInsets.all(padding),
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
              child: Column(
                children: [
                  Expanded(
                    flex: safeFlex(_headerButtonsHeight),
                    child: LayoutBuilder(
                      builder: (context, headerConstraints) {
                        return _buildHeader(
                          headerHeight,
                          labelFontSize,
                          headerConstraints.maxWidth,
                          layerIndex,
                          tableState,
                          micState,
                        );
                      },
                    ),
                  ),
                  Spacer(flex: safeFlex(_spacingHeight)),
                  Expanded(
                    flex: safeFlex(_contentHeightPercent),
                    child: _buildActiveControl(
                      tableState,
                      playbackState,
                      micState,
                      recordingState,
                      waveformState,
                      contentHeight,
                      padding,
                      labelFontSize,
                    ),
                  ),
                  Spacer(flex: safeFlex(_spacingHeight)),
                  Builder(
                    builder: (context) {
                      final trailingFlex = ((1.0 -
                                  _headerButtonsHeight -
                                  _spacingHeight -
                                  _contentHeightPercent -
                                  _spacingHeight) *
                              100)
                          .round()
                          .clamp(0, 100);
                      return trailingFlex > 0
                          ? Spacer(flex: trailingFlex)
                          : const SizedBox.shrink();
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHeader(
    double headerHeight,
    double labelFontSize,
    double availableWidth,
    int layerIndex,
    TableState tableState,
    MicrophoneState micState,
  ) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Container(
                width: 50,
                height: headerHeight * 0.7,
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                decoration: BoxDecoration(
                  color: AppColors.sequencerSurfaceBase,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: AppColors.sequencerBorder, width: 1),
                ),
                child: Center(
                  child: Text(
                    '${layerIndex + 1}',
                    style: TextStyle(
                      color: AppColors.sequencerLightText,
                      fontSize: labelFontSize,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
            // M and S (mute/solo) toggle buttons
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: SizedBox(
                width: 36,
                child: _buildSettingsButton(
                  'M',
                  tableState.isLayerMuted(layerIndex),
                  headerHeight * 0.7,
                  labelFontSize,
                  () {
                    final nextMuted = !tableState.isLayerMuted(layerIndex);
                    tableState.setLayerMuted(layerIndex, nextMuted);
                    final appState = context.read<AppState>();
                    if (appState.activeTutorialStep ==
                        TutorialStep.sequencerLayersHint) {
                      appState.markLayersMuteToggleAction(
                        isMutedAfterToggle: nextMuted,
                      );
                    }
                  },
                  key: context.watch<AppState>().activeTutorialStep ==
                              TutorialStep.sequencerLayersHint &&
                          context.watch<AppState>().isLayersTabDone &&
                          !context.watch<AppState>().isLayersUnmuteDone
                      ? context.read<AppState>().layerMuteButtonTutorialKey
                      : null,
                  tutorialTarget: TutorialInteractionTarget.layerMuteButton,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: SizedBox(
                width: 36,
                child: _buildSettingsButton(
                  'S',
                  tableState.isLayerSoloed(layerIndex),
                  headerHeight * 0.7,
                  labelFontSize,
                  () => tableState.setLayerSoloed(layerIndex, !tableState.isLayerSoloed(layerIndex)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: enableMicrophoneIntegration
                  ? _buildToggleButton(
                      headerHeight * 0.7,
                      labelFontSize,
                      tableState,
                      micState,
                    )
                  : const SizedBox.shrink(),
            ),
            if (enableMicrophoneIntegration && tableState.getLayerMode(layerIndex) == LayerMode.rec) ...[
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: SizedBox(
                  width: 70,
                  child: _buildSettingsButton(
                    'VOL',
                    _selectedMicControl == 'VOL',
                    headerHeight * 0.7,
                    labelFontSize,
                    () {
                      setState(() {
                        _selectedMicControl = 'VOL';
                      });
                    },
                  ),
                ),
              ),
              // NOTE: MON (monitoring) tab removed - mic recording now bypasses SunVox
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: SizedBox(
                  width: 90,
                  child: _buildSettingsButton(
                    _buildInputButtonLabel(micState),
                    _selectedMicControl == 'INPUT',
                    headerHeight * 0.7,
                    labelFontSize,
                    () {
                      setState(() {
                        _selectedMicControl = 'INPUT';
                      });
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: SizedBox(
                  width: 90,
                  child: _buildSettingsButton(
                    'OFFSET',
                    _selectedMicControl == 'OFFSET',
                    headerHeight * 0.7,
                    labelFontSize,
                    () {
                      setState(() {
                        _selectedMicControl = 'OFFSET';
                      });
                    },
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildToggleButton(double height, double fontSize, TableState tableState, MicrophoneState micState) {
    final layerIndex = tableState.uiSelectedLayer;
    final currentMode = tableState.getLayerMode(layerIndex);
    final isSequence = currentMode == LayerMode.sequence;
    const innerPadding = 3.0;
    
    return Container(
      height: height,
      padding: const EdgeInsets.all(innerPadding),
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfacePressed,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: AppColors.sequencerBorder,
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.sequencerShadow.withOpacity(0.3),
            blurRadius: 1.5,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // SEQUENCE button (left side)
          GestureDetector(
            onTap: () {
              tableState.setLayerMode(layerIndex, LayerMode.sequence);
            },
            child: Container(
              width: 90 - innerPadding,
              height: height - (innerPadding * 2),
              decoration: BoxDecoration(
                color: isSequence ? AppColors.sequencerAccent : Colors.transparent,
                borderRadius: BorderRadius.circular(3),
                boxShadow: isSequence ? [
                  BoxShadow(
                    color: AppColors.sequencerAccent.withOpacity(0.4),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ] : null,
              ),
              child: Center(
                child: Text(
                  'SEQUENCE',
                  style: TextStyle(
                    color: isSequence ? AppColors.sequencerPageBackground : AppColors.sequencerText.withOpacity(0.6),
                    fontSize: fontSize,
                    fontWeight: isSequence ? FontWeight.w700 : FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: innerPadding),
          // REC button (right side)
          GestureDetector(
            onTap: () {
              if (!micState.isMicEnabled) {
                micState.enableMicrophone();
              }
              tableState.setLayerMode(layerIndex, LayerMode.rec);
            },
            child: Container(
              width: 70 - innerPadding,
              height: height - (innerPadding * 2),
              decoration: BoxDecoration(
                color: !isSequence ? AppColors.sequencerAccent : Colors.transparent,
                borderRadius: BorderRadius.circular(3),
                boxShadow: !isSequence ? [
                  BoxShadow(
                    color: AppColors.sequencerAccent.withOpacity(0.4),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ] : null,
              ),
              child: Center(
                child: Text(
                  'REC',
                  style: TextStyle(
                    color: !isSequence ? AppColors.sequencerPageBackground : AppColors.sequencerText.withOpacity(0.6),
                    fontSize: fontSize,
                    fontWeight: !isSequence ? FontWeight.w700 : FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _buildInputButtonLabel(MicrophoneState micState) {
    final kind = micState.getCurrentInputKindLabel();
    if (kind == 'WIRED') return 'IN:WIRED';
    if (kind == 'BUILT-IN') return 'IN:BUILT';
    return 'INPUT';
  }

  Widget _buildSettingsButton(
    String label,
    bool isSelected,
    double height,
    double fontSize,
    VoidCallback? onTap, {
    Key? key,
    TutorialInteractionTarget? tutorialTarget,
  }) {
    final appState = context.watch<AppState>();
    final canTap = tutorialTarget == null
        ? !appState.isTutorialRunning
        : appState.canInteractWithTutorialTarget(tutorialTarget);
    return GestureDetector(
      key: key,
      onTap: canTap ? onTap : null,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.sequencerAccent : AppColors.sequencerSurfaceRaised,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: AppColors.sequencerBorder,
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.sequencerShadow,
              blurRadius: 1.5,
              offset: const Offset(0, 1),
            ),
            BoxShadow(
              color: AppColors.sequencerSurfaceRaised,
              blurRadius: 0.5,
              offset: const Offset(0, -0.5),
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? AppColors.sequencerPageBackground : AppColors.sequencerText,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveControl(
    TableState tableState,
    PlaybackState playbackState,
    MicrophoneState micState,
    RecordingState recordingState,
    RecordingWaveformState waveformState,
    double height,
    double padding,
    double fontSize,
  ) {
    final layerIndex = tableState.uiSelectedLayer;
    final currentMode = tableState.getLayerMode(layerIndex);

    // Sequence mode: dedicate the whole active area to per-column M/S controls.
    // This replaces the old steps counter panel.
    if (!enableMicrophoneIntegration || currentMode != LayerMode.rec) {
      return _buildColumnMuteSoloControls(
        tableState: tableState,
        layerIndex: layerIndex,
        padding: padding,
        fontSize: fontSize,
      );
    }

    // REC mode: keep mic controls, and show compact per-column M/S strip below.
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = (constraints.maxHeight * 0.03).clamp(2.0, 8.0);
        return Column(
          children: [
            Expanded(
              flex: 58,
              child: _buildLineMicControl(
                tableState,
                playbackState,
                micState,
                recordingState,
                waveformState,
                height,
                padding,
                fontSize,
              ),
            ),
            SizedBox(height: gap),
            Expanded(
              flex: 39,
              child: _buildColumnMuteSoloControls(
                tableState: tableState,
                layerIndex: layerIndex,
                padding: padding,
                fontSize: fontSize,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLineMicControl(
    TableState tableState,
    PlaybackState playbackState,
    MicrophoneState micState,
    RecordingState recordingState,
    RecordingWaveformState waveformState,
    double height,
    double padding,
    double fontSize,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          height: constraints.maxHeight,
          padding: EdgeInsets.symmetric(horizontal: padding * 0.3, vertical: padding * 0.15),
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
          child: _buildMicActiveControl(
            micState,
            waveformState,
            playbackState,
            tableState,
            constraints.maxHeight,
            padding,
            fontSize,
          ),
        );
      },
    );
  }

  Widget _buildMicActiveControl(
    MicrophoneState micState,
    RecordingWaveformState waveformState,
    PlaybackState playbackState,
    TableState tableState,
    double height,
    double padding,
    double fontSize,
  ) {
    switch (_selectedMicControl) {
      // NOTE: MON case removed - monitoring is no longer available
      case 'INPUT':
        return _buildInputSelectorControl(micState, height);
      case 'OFFSET':
        return OffsetControlsWidget(
          waveformState: waveformState,
          layer: tableState.uiSelectedLayer,
          section: playbackState.currentSection,
        );
      case 'VOL':
      default:
        return _buildVolumeControl(micState, height);
    }
  }

  Widget _buildVolumeControl(MicrophoneState micState, double height) {
    return ValueListenableBuilder<double>(
      valueListenable: micState.micVolumeNotifier,
      builder: (context, volume, _) => GenericSlider(
        value: volume,
        min: 0.0,
        max: 1.0,
        divisions: 100,
        type: SliderType.volume,
        onChanged: (value) => micState.setMicVolume(value),
        height: height,
        sliderOverlay: context.read<SliderOverlayState>(),
        contextLabel: 'Mic',
      ),
    );
  }

  // NOTE: _buildMonitorControl removed - monitoring is no longer available
  // Mic recording now bypasses SunVox entirely

  Widget _buildInputSelectorControl(MicrophoneState micState, double height) {
    final availableInputs = micState.getAvailableInputs();
    final currentInputUid = micState.getCurrentInputUid();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: availableInputs.map((device) {
          final isSelected = device.uid == currentInputUid;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: GestureDetector(
              onTap: () {
                micState.setPreferredInput(device.uid);
                setState(() {});
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.sequencerAccent.withOpacity(0.3) : AppColors.sequencerSurfacePressed,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isSelected ? AppColors.sequencerAccent : AppColors.sequencerBorder,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      device.isBluetooth ? Icons.bluetooth : Icons.phone_iphone,
                      size: height * 0.30,
                      color: isSelected ? AppColors.sequencerAccent : AppColors.sequencerText,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      device.name,
                      style: TextStyle(
                        color: isSelected ? AppColors.sequencerAccent : AppColors.sequencerText,
                        fontSize: height * 0.18,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (isSelected) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.check_circle,
                        size: height * 0.22,
                        color: AppColors.sequencerAccent,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildColumnMuteSoloControls({
    required TableState tableState,
    required int layerIndex,
    required double padding,
    required double fontSize,
  }) {
    final visibleColumns = tableState.getVisibleCols(layerIndex).length;
    if (visibleColumns <= 0) {
      return const SizedBox.shrink();
    }

    return Container(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final px = (constraints.maxWidth * 0.015).clamp(3.0, 8.0);
          final py = (constraints.maxHeight * 0.08).clamp(1.0, 6.0);
          return Container(
            padding: EdgeInsets.symmetric(horizontal: px, vertical: py),
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
            child: AnimatedBuilder(
              animation: Listenable.merge([
                tableState.layerMuteSoloNotifier,
                tableState.columnMuteSoloNotifier,
              ]),
              builder: (context, _) {
                final gap = (constraints.maxWidth * 0.01).clamp(3.0, 8.0);
                final layerMuted = tableState.isLayerMuted(layerIndex);
                final layerSoloed = tableState.isLayerSoloed(layerIndex);
                return Row(
                  children: List.generate(visibleColumns, (colInLayer) {
                    final isColMuted = tableState.isLayerColumnMuted(layerIndex, colInLayer);
                    final isColSoloed = tableState.isLayerColumnSoloed(layerIndex, colInLayer);
                    final muteButtonActive = layerMuted || isColMuted;
                    // Layer mute suppresses column solo UI; solo cannot be on while layer is muted.
                    final soloVisual =
                        !layerMuted && (layerSoloed || isColSoloed);
                    final isLast = colInLayer == visibleColumns - 1;
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: isLast ? 0 : gap),
                        child: _buildColumnMuteSoloTile(
                          layerIndex: layerIndex,
                          colInLayer: colInLayer,
                          isColMuted: isColMuted,
                          isLayerMuted: layerMuted,
                          muteButtonActive: muteButtonActive,
                          soloVisual: soloVisual,
                          fontSize: fontSize,
                          tableState: tableState,
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildColumnMuteSoloTile({
    required int layerIndex,
    required int colInLayer,
    required bool isColMuted,
    required bool isLayerMuted,
    required bool muteButtonActive,
    required bool soloVisual,
    required double fontSize,
    required TableState tableState,
  }) {
    final mutedVisual = isLayerMuted || isColMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceBase,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: AppColors.sequencerBorder, width: 0.5),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tileHeight = constraints.maxHeight;
          final showLabel = tileHeight >= 34;
          final gap = showLabel ? (tileHeight * 0.08).clamp(1.0, 4.0) : 0.0;
          final buttonHeight = showLabel
              ? (tileHeight * 0.50).clamp(12.0, 28.0)
              : (tileHeight * 0.78).clamp(10.0, 24.0);
          final buttonFontSize = (buttonHeight * 0.38).clamp(7.0, 11.0);
          final labelFontSize = (fontSize * 0.9).clamp(7.0, 11.0);

          return Column(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (showLabel)
                Text(
                  'COL${colInLayer + 1}',
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: TextStyle(
                    color: mutedVisual
                        ? AppColors.sequencerLightText.withOpacity(0.65)
                        : AppColors.sequencerLightText,
                    fontSize: labelFontSize,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.35,
                  ),
                ),
              if (showLabel) SizedBox(height: gap),
              Row(
                mainAxisSize: MainAxisSize.max,
                children: [
                  Expanded(
                    child: _buildSettingsButton(
                      'M',
                      muteButtonActive,
                      buttonHeight,
                      buttonFontSize,
                      () => tableState.setLayerColumnMuted(
                            layerIndex,
                            colInLayer,
                            !muteButtonActive,
                          ),
                    ),
                  ),
                  SizedBox(width: (constraints.maxWidth * 0.05).clamp(2.0, 4.0)),
                  Expanded(
                    child: _buildSettingsButton(
                      'S',
                      soloVisual,
                      buttonHeight,
                      buttonFontSize,
                      () => tableState.setLayerColumnSoloed(
                            layerIndex,
                            colInLayer,
                            !soloVisual,
                          ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
      foregroundDecoration: mutedVisual
          ? BoxDecoration(
              color: Colors.black.withOpacity(0.18),
              borderRadius: BorderRadius.circular(2),
            )
          : null,
    );
  }

}
