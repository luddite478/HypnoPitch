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
import 'sequencer_layer_label.dart';

/// Which sub-panel fills the bottom region of [LayerSettingsWidget].
enum LayerSettingsBottomPanel {
  /// Per-column mute/solo (and mic strip when recording).
  muteSoloColumns,
  eq,
  reverb,
}

class LayerSettingsWidget extends StatefulWidget {
  const LayerSettingsWidget({super.key});

  @override
  State<LayerSettingsWidget> createState() => _LayerSettingsWidgetState();
}

class _LayerSettingsWidgetState extends State<LayerSettingsWidget>
    with SingleTickerProviderStateMixin {
  String _selectedMicControl = 'VOL';

  LayerSettingsBottomPanel _bottomPanel = LayerSettingsBottomPanel.muteSoloColumns;

  /// Scrollable top chrome: layer badge, mute/solo group, EQ/REVERB stubs, mic row.
  static const double _topChromeHeightFraction = 0.40;
  static const double _contentHeightPercent = 0.54;
  static const double _spacingHeight = 0.02;

  late final AnimationController _layerBadgeBlinkController;
  late final Animation<double> _layerBadgeBlinkOpacity;
  int? _lastLayerIndexForBlink;

  @override
  void initState() {
    super.initState();
    _layerBadgeBlinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _layerBadgeBlinkOpacity = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 0.38), weight: 1),
      TweenSequenceItem(
          tween: Tween(begin: 0.38, end: 1.0), weight: 1),
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 0.48), weight: 1),
      TweenSequenceItem(
          tween: Tween(begin: 0.48, end: 1.0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _layerBadgeBlinkController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _layerBadgeBlinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<TableState, PlaybackState>(
      builder: (context, tableState, playbackState, child) {
        final micState = context.watch<MicrophoneState>();
        final recordingState = context.watch<RecordingState>();
        final waveformState = context.watch<RecordingWaveformState>();
        final layerIndex = tableState.uiSelectedLayer;

        if (_lastLayerIndexForBlink != layerIndex) {
          final previous = _lastLayerIndexForBlink;
          _lastLayerIndexForBlink = layerIndex;
          if (previous != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _layerBadgeBlinkController.forward(from: 0);
                setState(() {
                  _bottomPanel = LayerSettingsBottomPanel.muteSoloColumns;
                });
              }
            });
          }
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final panelHeight = constraints.maxHeight;
            final padding = panelHeight * 0.03;

            final innerHeight = panelHeight - padding * 2;
            const borderThickness = 1.0;
            final innerHeightAdj = innerHeight - borderThickness * 2;

            final contentHeight = innerHeightAdj * _contentHeightPercent;
            final labelFontSize =
                (innerHeightAdj * 0.065).clamp(8.0, 11.0);
            final layerBadgeFontSize =
                (innerHeightAdj * 0.11).clamp(13.0, 20.0);
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
                    flex: safeFlex(_topChromeHeightFraction),
                    child: LayoutBuilder(
                      builder: (context, topConstraints) {
                        final chromeH =
                            innerHeightAdj * _topChromeHeightFraction;
                        final buttonH = (chromeH * 0.22).clamp(22.0, 34.0);
                        return _buildHorizontalLayerMenuStrip(
                          layerBadgeFontSize: layerBadgeFontSize,
                          layerBadgeBlinkOpacity: _layerBadgeBlinkOpacity,
                          viewportWidth: topConstraints.maxWidth,
                          buttonHeight: buttonH,
                          labelFontSize: labelFontSize,
                          layerIndex: layerIndex,
                          tableState: tableState,
                          micState: micState,
                          bottomPanel: _bottomPanel,
                          onSelectBottomPanel: (panel) {
                            setState(() => _bottomPanel = panel);
                          },
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
                      bottomPanel: _bottomPanel,
                    ),
                  ),
                  Spacer(flex: safeFlex(_spacingHeight)),
                  Builder(
                    builder: (context) {
                      final trailingFlex = ((1.0 -
                                  _topChromeHeightFraction -
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

  /// Layer badge + mute/solo + EQ/REVERB + mic controls in one horizontal strip.
  /// Scroll prevents horizontal overflow on narrow panels (see flutter_overflow_prevention_guide).
  Widget _buildHorizontalLayerMenuStrip({
    required double layerBadgeFontSize,
    required Animation<double> layerBadgeBlinkOpacity,
    required double viewportWidth,
    required double buttonHeight,
    required double labelFontSize,
    required int layerIndex,
    required TableState tableState,
    required MicrophoneState micState,
    required LayerSettingsBottomPanel bottomPanel,
    required void Function(LayerSettingsBottomPanel panel) onSelectBottomPanel,
  }) {
    const double gap = 8.0;
    final safeW = viewportWidth.isFinite ? viewportWidth : 320.0;
    // Round down; leave headroom vs viewport (guide: buffer / floor).
    final badgeMaxOuterW =
        (safeW * 0.34).floorToDouble().clamp(48.0, 100.0);

    return Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.hardEdge,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildLayerTitleBadge(
              layerBadgeFontSize,
              layerBadgeBlinkOpacity,
              badgeMaxOuterW,
              layerIndex,
            ),
            const SizedBox(width: gap),
            _buildLayerMuteSoloGroup(
              labelFontSize: labelFontSize,
              buttonHeight: buttonHeight,
              layerIndex: layerIndex,
              tableState: tableState,
              isBottomSelected:
                  bottomPanel == LayerSettingsBottomPanel.muteSoloColumns,
              onSelectMuteSoloPanel: () => onSelectBottomPanel(
                    LayerSettingsBottomPanel.muteSoloColumns,
                  ),
            ),
            const SizedBox(width: gap),
            _buildBottomPanelChip(
              title: 'EQ',
              labelFontSize: labelFontSize,
              selected: bottomPanel == LayerSettingsBottomPanel.eq,
              enabled: true,
              onTap: () =>
                  onSelectBottomPanel(LayerSettingsBottomPanel.eq),
            ),
            const SizedBox(width: gap),
            _buildBottomPanelChip(
              title: 'REVERB',
              labelFontSize: labelFontSize,
              selected: bottomPanel == LayerSettingsBottomPanel.reverb,
              enabled: true,
              onTap: () =>
                  onSelectBottomPanel(LayerSettingsBottomPanel.reverb),
            ),
            if (enableMicrophoneIntegration) ...[
              const SizedBox(width: gap),
              ..._buildMicHeaderWidgets(
                buttonHeight: buttonHeight,
                labelFontSize: labelFontSize,
                tableState: tableState,
                micState: micState,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Layer letter badge; fixed max width from parent [maxBadgeWidth] (floored upstream).
  Widget _buildLayerTitleBadge(
    double layerBadgeFontSize,
    Animation<double> layerBadgeBlinkOpacity,
    double maxBadgeWidth,
    int layerIndex,
  ) {
    final badgeHeight = (layerBadgeFontSize * 1.55).clamp(28.0, 40.0);

    return FadeTransition(
      opacity: layerBadgeBlinkOpacity,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: 40,
          maxWidth: maxBadgeWidth,
          maxHeight: badgeHeight,
        ),
        child: SizedBox(
          height: badgeHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.sequencerSurfaceBase,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(
                color: AppColors.sequencerBorder,
                width: 1,
              ),
            ),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: Text(
                    sequencerLayerLabelForIndex(layerIndex),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.sequencerLightText,
                      fontSize: layerBadgeFontSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Bordered group: tappable [mute/solo] label selects column M/S bottom panel; [M] [S] are layer controls.
  Widget _buildLayerMuteSoloGroup({
    required double labelFontSize,
    required double buttonHeight,
    required int layerIndex,
    required TableState tableState,
    required bool isBottomSelected,
    required VoidCallback onSelectMuteSoloPanel,
  }) {
    final labelStyle = TextStyle(
      color: AppColors.sequencerLightText.withOpacity(0.9),
      fontSize: (labelFontSize * 0.95).clamp(7.5, 10.5),
      fontWeight: FontWeight.w600,
      letterSpacing: 0.35,
      height: 1.05,
    );
    const labelButtonGap = 8.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onSelectMuteSoloPanel,
              borderRadius: BorderRadius.circular(2),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 52, maxWidth: 72),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(
                      color: isBottomSelected
                          ? AppColors.sequencerAccent
                          : AppColors.sequencerBorder.withOpacity(0.5),
                      width: isBottomSelected ? 1.5 : 0.5,
                    ),
                    color: isBottomSelected
                        ? AppColors.sequencerAccent.withOpacity(0.12)
                        : null,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: Text(
                      'mute/\nsolo',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: labelStyle,
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: labelButtonGap),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 36,
                height: buttonHeight,
                child: _buildSettingsButton(
                  'M',
                  tableState.isLayerMuted(layerIndex),
                  buttonHeight,
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
              const SizedBox(width: 6),
              SizedBox(
                width: 36,
                height: buttonHeight,
                child: _buildSettingsButton(
                  'S',
                  tableState.isLayerSoloed(layerIndex),
                  buttonHeight,
                  labelFontSize,
                  () => tableState.setLayerSoloed(
                        layerIndex,
                        !tableState.isLayerSoloed(layerIndex),
                      ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanelChip({
    required String title,
    required double labelFontSize,
    required bool selected,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final textStyle = TextStyle(
      color: enabled
          ? AppColors.sequencerText
          : AppColors.sequencerText.withOpacity(0.35),
      fontSize: labelFontSize,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.4,
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(2),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 64, maxWidth: 120),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.sequencerAccent.withOpacity(0.14)
                  : AppColors.sequencerSurfacePressed.withOpacity(0.65),
              borderRadius: BorderRadius.circular(2),
              border: Border.all(
                color: selected
                    ? AppColors.sequencerAccent
                    : AppColors.sequencerBorder.withOpacity(0.75),
                width: selected ? 1.25 : 0.5,
              ),
            ),
            child: Center(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: textStyle,
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildMicHeaderWidgets({
    required double buttonHeight,
    required double labelFontSize,
    required TableState tableState,
    required MicrophoneState micState,
  }) {
    final layerIndex = tableState.uiSelectedLayer;
    return [
      _buildToggleButton(
        buttonHeight,
        labelFontSize,
        tableState,
        micState,
      ),
      if (tableState.getLayerMode(layerIndex) == LayerMode.rec) ...[
        const SizedBox(width: 8.0),
        SizedBox(
          width: 70,
          child: _buildSettingsButton(
            'VOL',
            _selectedMicControl == 'VOL',
            buttonHeight,
            labelFontSize,
            () {
              setState(() {
                _selectedMicControl = 'VOL';
              });
            },
          ),
        ),
        const SizedBox(width: 8.0),
        SizedBox(
          width: 90,
          child: _buildSettingsButton(
            _buildInputButtonLabel(micState),
            _selectedMicControl == 'INPUT',
            buttonHeight,
            labelFontSize,
            () {
              setState(() {
                _selectedMicControl = 'INPUT';
              });
            },
          ),
        ),
        const SizedBox(width: 8.0),
        SizedBox(
          width: 90,
          child: _buildSettingsButton(
            'OFFSET',
            _selectedMicControl == 'OFFSET',
            buttonHeight,
            labelFontSize,
            () {
              setState(() {
                _selectedMicControl = 'OFFSET';
              });
            },
          ),
        ),
      ],
    ];
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
    double fontSize, {
    required LayerSettingsBottomPanel bottomPanel,
  }) {
    switch (bottomPanel) {
      case LayerSettingsBottomPanel.eq:
        return _buildBottomPlaceholderPanel(
          title: 'EQ',
          height: height,
          padding: padding,
          fontSize: fontSize,
        );
      case LayerSettingsBottomPanel.reverb:
        return _buildBottomPlaceholderPanel(
          title: 'REVERB',
          height: height,
          padding: padding,
          fontSize: fontSize,
        );
      case LayerSettingsBottomPanel.muteSoloColumns:
        return _buildMuteSoloBottomContent(
          tableState,
          playbackState,
          micState,
          recordingState,
          waveformState,
          height,
          padding,
          fontSize,
        );
    }
  }

  /// Stub until EQ/reverb editors are wired (same pattern as column M/S selection).
  Widget _buildBottomPlaceholderPanel({
    required String title,
    required double height,
    required double padding,
    required double fontSize,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(padding * 0.5),
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceRaised,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: AppColors.sequencerBorder, width: 1),
      ),
      child: Center(
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppColors.sequencerLightText.withOpacity(0.55),
            fontSize: (fontSize * 1.15).clamp(10.0, 14.0),
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  /// Per-column mute/solo strip; in REC mode, mic controls above the strip.
  Widget _buildMuteSoloBottomContent(
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

    if (!enableMicrophoneIntegration || currentMode != LayerMode.rec) {
      return _buildColumnMuteSoloControls(
        tableState: tableState,
        layerIndex: layerIndex,
        padding: padding,
        fontSize: fontSize,
      );
    }

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
