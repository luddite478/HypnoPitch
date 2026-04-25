import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'wheel_select_widget.dart';

/// Which sub-panel fills the bottom region of [LayerSettingsWidget].
enum LayerSettingsBottomPanel {
  /// Per-column mute/solo (and mic strip when recording).
  muteSoloColumns,
  volume,
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
  int _reverbSection = -1;
  int _reverbLayer = -1;
  double _reverbSend01 = 0.0;

  int _volumeSection = -1;
  int _volumeLayer = -1;
  double _layerVolume01 = 1.0;

  int _layerEqBand = 0;

  LayerSettingsBottomPanel _bottomPanel = LayerSettingsBottomPanel.muteSoloColumns;

  /// Scrollable top chrome: layer badge, mute/solo group, EQ/RVB, mic row.
  /// Matches [SoundSettingsWidget] header row: `_headerButtonsHeight` (0.45).
  static const double _soundSettingsHeaderRowFraction = 0.45;
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
            final masterHeaderH =
                innerHeightAdj * _soundSettingsHeaderRowFraction;
            final masterHeaderButtonFontSize =
                (masterHeaderH * 0.25).clamp(8.0, 11.0);
            final masterHeaderButtonHeight = masterHeaderH * 0.7;
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
                          layerBadgeBlinkOpacity: _layerBadgeBlinkOpacity,
                          viewportWidth: topConstraints.maxWidth,
                          buttonHeight: buttonH,
                          labelFontSize: labelFontSize,
                          masterHeaderButtonFontSize: masterHeaderButtonFontSize,
                          masterHeaderButtonHeight: masterHeaderButtonHeight,
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

  /// Layer badge + mute/solo + EQ/RVB + mic controls in one horizontal strip.
  /// Scroll prevents horizontal overflow on narrow panels (see flutter_overflow_prevention_guide).
  Widget _buildHorizontalLayerMenuStrip({
    required Animation<double> layerBadgeBlinkOpacity,
    required double viewportWidth,
    required double buttonHeight,
    required double labelFontSize,
    required double masterHeaderButtonFontSize,
    required double masterHeaderButtonHeight,
    required int layerIndex,
    required TableState tableState,
    required MicrophoneState micState,
    required LayerSettingsBottomPanel bottomPanel,
    required void Function(LayerSettingsBottomPanel panel) onSelectBottomPanel,
  }) {
    final safeW = viewportWidth.isFinite ? viewportWidth : 320.0;
    // Same cap as [SoundSettingsWidget._buildContextLabelTile] (buffer / floor).
    final contextLabelMaxWidth = math.max(
      36.0,
      (safeW * 0.179).floorToDouble(),
    );

    return Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.hardEdge,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: _buildLayerTitleBadge(
                letterFontSize: masterHeaderButtonFontSize,
                tileHeight: masterHeaderButtonHeight,
                layerBadgeBlinkOpacity: layerBadgeBlinkOpacity,
                maxBadgeWidth: contextLabelMaxWidth,
                layerIndex: layerIndex,
              ),
            ),
            _buildMasterStyleHeaderButton(
              label: 'M/S',
              height: masterHeaderButtonHeight,
              fontSize: masterHeaderButtonFontSize,
              selected:
                  bottomPanel == LayerSettingsBottomPanel.muteSoloColumns,
              onTap: () =>
                  onSelectBottomPanel(LayerSettingsBottomPanel.muteSoloColumns),
              fitMultilineLabel: true,
            ),
            _buildMasterStyleHeaderButton(
              label: 'VOL',
              height: masterHeaderButtonHeight,
              fontSize: masterHeaderButtonFontSize,
              selected: bottomPanel == LayerSettingsBottomPanel.volume,
              onTap: () =>
                  onSelectBottomPanel(LayerSettingsBottomPanel.volume),
            ),
            _buildMasterStyleHeaderButton(
              label: 'EQ',
              height: masterHeaderButtonHeight,
              fontSize: masterHeaderButtonFontSize,
              selected: bottomPanel == LayerSettingsBottomPanel.eq,
              onTap: () =>
                  onSelectBottomPanel(LayerSettingsBottomPanel.eq),
            ),
            _buildMasterStyleHeaderButton(
              label: 'RVB',
              height: masterHeaderButtonHeight,
              fontSize: masterHeaderButtonFontSize,
              selected: bottomPanel == LayerSettingsBottomPanel.reverb,
              onTap: () =>
                  onSelectBottomPanel(LayerSettingsBottomPanel.reverb),
            ),
            if (enableMicrophoneIntegration) ...[
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

  /// Layer letter badge — same tile height and font scale as [SoundSettingsWidget]
  /// header row (`headerHeight * 0.7`, `headerHeight * 0.25` clamped).
  Widget _buildLayerTitleBadge({
    required double letterFontSize,
    required double tileHeight,
    required Animation<double> layerBadgeBlinkOpacity,
    required double maxBadgeWidth,
    required int layerIndex,
  }) {
    return FadeTransition(
      opacity: layerBadgeBlinkOpacity,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: 36,
          maxWidth: maxBadgeWidth,
          maxHeight: tileHeight,
        ),
        child: SizedBox(
          height: tileHeight,
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
              // Slightly tighter than master context label (8,4) in sound_settings.
              padding:
                  const EdgeInsets.symmetric(horizontal: 6.0, vertical: 3.0),
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
                      fontSize: letterFontSize,
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

  /// Same look as [SoundSettingsWidget] `_buildSettingsButton` (VOL / RVB / EQ row).
  /// [fitMultilineLabel] scales two-line labels (e.g. mute/solo) to the button height.
  Widget _buildMasterStyleHeaderButton({
    required String label,
    required double height,
    required double fontSize,
    required bool selected,
    required VoidCallback onTap,
    bool fitMultilineLabel = false,
  }) {
    final textStyle = TextStyle(
      color: selected
          ? AppColors.sequencerPageBackground
          : AppColors.sequencerText,
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
      height: fitMultilineLabel ? 1.05 : null,
    );
    final textWidget = Text(
      label,
      textAlign: TextAlign.center,
      maxLines: fitMultilineLabel ? 2 : 1,
      style: textStyle,
    );

    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: SizedBox(
        width: 80,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.sequencerAccent
                  : AppColors.sequencerSurfaceRaised,
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
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Center(
              child: fitMultilineLabel
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.center,
                      child: textWidget,
                    )
                  : textWidget,
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
              HapticFeedback.lightImpact();
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
              HapticFeedback.lightImpact();
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
      onTap: canTap && onTap != null
          ? () {
              HapticFeedback.lightImpact();
              onTap();
            }
          : null,
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
      case LayerSettingsBottomPanel.volume:
        return _buildLayerVolumePanel(
          tableState: tableState,
          playbackState: playbackState,
          height: height,
          padding: padding,
          fontSize: fontSize,
        );
      case LayerSettingsBottomPanel.eq:
        return _buildLayerEqPanel(
          tableState: tableState,
          playbackState: playbackState,
          padding: padding,
        );
      case LayerSettingsBottomPanel.reverb:
        return _buildLayerReverbPanel(
          tableState: tableState,
          playbackState: playbackState,
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

  static const List<String> _kLayerEqBandLabels = ['LOW', 'MID', 'HIGH'];

  String _layerEqBandLabel(int band) =>
      _kLayerEqBandLabels[band.clamp(0, 2)];

  String _formatLayerEqDbWheel(int v) {
    if (v == 0) return '0';
    return v > 0 ? '+$v' : '$v';
  }

  void _cycleLayerEqBand(int delta) {
    setState(() {
      _layerEqBand = (_layerEqBand + delta + 3) % 3;
    });
    HapticFeedback.lightImpact();
  }

  Widget _buildLayerEqArrowButton({
    required IconData icon,
    required VoidCallback onTap,
    required double size,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.sequencerSurfaceRaised,
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: AppColors.sequencerShadow,
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Center(
          child: Icon(
            icon,
            color: AppColors.sequencerAccent,
            size: size * 0.70,
          ),
        ),
      ),
    );
  }

  Widget _buildLayerEqPanel({
    required TableState tableState,
    required PlaybackState playbackState,
    required double padding,
  }) {
    final int section = tableState.uiSelectedSection;
    final int layer = tableState.uiSelectedLayer;
    final int db = playbackState.getSectionLayerEqBandDb(section, layer, _layerEqBand);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: padding * 0.5,
        vertical: padding * 0.3,
      ),
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxH = constraints.maxHeight;
          final buttonSize = (maxH * 0.72).clamp(22.0, 52.0);
          final labelBoxHeight = buttonSize;
          final spacing = (maxH * 0.12).clamp(2.0, 8.0);
          final gapBesideDivider = (padding * 0.35).clamp(4.0, 10.0);

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 2,
                child: Padding(
                  padding: EdgeInsets.only(right: gapBesideDivider),
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: padding * 0.1),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildLayerEqArrowButton(
                            icon: Icons.chevron_left,
                            size: buttonSize,
                            onTap: () => _cycleLayerEqBand(-1),
                          ),
                          SizedBox(width: spacing),
                          Expanded(
                            child: Align(
                              alignment: Alignment.center,
                              child: Container(
                                height: labelBoxHeight,
                                constraints: const BoxConstraints(minWidth: 0),
                                decoration: BoxDecoration(
                                  color: AppColors.sequencerSurfacePressed,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                alignment: Alignment.center,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4.0),
                                    child: Text(
                                      _layerEqBandLabel(_layerEqBand),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: AppColors.sequencerAccent,
                                        fontSize: labelBoxHeight * 0.42,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: spacing),
                          _buildLayerEqArrowButton(
                            icon: Icons.chevron_right,
                            size: buttonSize,
                            onTap: () => _cycleLayerEqBand(1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                width: 1,
                color: AppColors.sequencerBorder,
              ),
              Expanded(
                flex: 3,
                child: Padding(
                  padding: EdgeInsets.only(left: gapBesideDivider),
                  child: ClipRect(
                    clipBehavior: Clip.hardEdge,
                    child: WheelSelectWidget(
                      key: ValueKey<int>(
                          section * 1000 + layer * 10 + _layerEqBand),
                      value: db,
                      minValue: PlaybackState.masterEqMinDb,
                      maxValue: PlaybackState.masterEqMaxDb,
                      valueFormatter: _formatLayerEqDbWheel,
                      onValueChanged: (v) {
                        playbackState.setSectionLayerEqBandDb(
                          section: section,
                          layer: layer,
                          band: _layerEqBand,
                          db: v,
                        );
                        setState(() {});
                      },
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLayerVolumePanel({
    required TableState tableState,
    required PlaybackState playbackState,
    required double height,
    required double padding,
    required double fontSize,
  }) {
    final int section = tableState.uiSelectedSection;
    final int layer = tableState.uiSelectedLayer;

    if (_volumeSection != section || _volumeLayer != layer) {
      _volumeSection = section;
      _volumeLayer = layer;
      _layerVolume01 = playbackState
          .getSectionLayerVolume(section, layer)
          .clamp(0.0, 1.0);
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(padding * 0.5),
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceRaised,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: AppColors.sequencerBorder, width: 1),
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
      child: GenericSlider(
        value: _layerVolume01,
        min: 0.0,
        max: 1.0,
        divisions: 100,
        type: SliderType.volume,
        onChanged: (v) {
          final next = v.clamp(0.0, 1.0);
          setState(() {
            _layerVolume01 = next;
          });
          playbackState.setSectionLayerVolume(
            section: section,
            layer: layer,
            volume01: next,
          );
        },
        height: height,
        sliderOverlay: context.read<SliderOverlayState>(),
        contextLabel: 'L${layer + 1}',
      ),
    );
  }

  Widget _buildLayerReverbPanel({
    required TableState tableState,
    required PlaybackState playbackState,
    required double height,
    required double padding,
    required double fontSize,
  }) {
    final int section = tableState.uiSelectedSection;
    final int layer = tableState.uiSelectedLayer;

    if (_reverbSection != section || _reverbLayer != layer) {
      _reverbSection = section;
      _reverbLayer = layer;
      _reverbSend01 = playbackState
          .getSectionLayerReverbSend(section, layer)
          .clamp(0.0, 1.0);
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(padding * 0.5),
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceRaised,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: AppColors.sequencerBorder, width: 1),
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
      child: GenericSlider(
        value: _reverbSend01,
        min: 0.0,
        max: 1.0,
        divisions: 100,
        type: SliderType.reverb,
        onChanged: (v) {
          final next = v.clamp(0.0, 1.0);
          setState(() {
            _reverbSend01 = next;
          });
          playbackState.setSectionLayerReverb(
            section: section,
            layer: layer,
            send01: next,
          );
        },
        height: height,
        sliderOverlay: context.read<SliderOverlayState>(),
        contextLabel: 'L${layer + 1}',
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

    return LayoutBuilder(
        builder: (context, constraints) {
          final px = (constraints.maxWidth * 0.008).clamp(2.0, 5.0);
          final py = (constraints.maxHeight * 0.04).clamp(1.0, 4.0);
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
                final gap = (constraints.maxWidth * 0.012).clamp(4.0, 8.0);
                final h = constraints.maxHeight;
                // Wide tiles + horizontal scroll keeps M/S large and easy to tap.
                const tileMinWidth = 118.0;
                final layerMuted = tableState.isLayerMuted(layerIndex);
                final layerSoloed = tableState.isLayerSoloed(layerIndex);
                final appState = context.watch<AppState>();
                final layerMuteTutorialKey =
                    appState.activeTutorialStep ==
                                TutorialStep.sequencerLayersHint &&
                            appState.isLayersTabDone &&
                            !appState.isLayersUnmuteDone
                        ? context.read<AppState>().layerMuteButtonTutorialKey
                        : null;

                Widget sizedTile(Widget child) => SizedBox(
                      width: tileMinWidth,
                      height: h,
                      child: child,
                    );

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.hardEdge,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(right: gap),
                        child: sizedTile(
                          _buildColumnMuteSoloTile(
                            layerIndex: layerIndex,
                            isAllTile: true,
                            colInLayer: null,
                            isColMuted: false,
                            isLayerMuted: layerMuted,
                            muteButtonActive: layerMuted,
                            soloVisual: !layerMuted && layerSoloed,
                            fontSize: fontSize,
                            tableState: tableState,
                            layerMuteTutorialKey: layerMuteTutorialKey,
                          ),
                        ),
                      ),
                      ...List.generate(visibleColumns, (colInLayer) {
                        final isColMuted = tableState.isLayerColumnMuted(
                            layerIndex, colInLayer);
                        final isColSoloed = tableState.isLayerColumnSoloed(
                            layerIndex, colInLayer);
                        final muteButtonActive = layerMuted || isColMuted;
                        final soloVisual =
                            !layerMuted && (layerSoloed || isColSoloed);
                        final isLast = colInLayer == visibleColumns - 1;
                        return Padding(
                          padding: EdgeInsets.only(right: isLast ? 0 : gap),
                          child: sizedTile(
                            _buildColumnMuteSoloTile(
                              layerIndex: layerIndex,
                              isAllTile: false,
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
                    ],
                  ),
                );
              },
            ),
          );
        },
    );
  }

  Widget _buildColumnMuteSoloTile({
    required int layerIndex,
    required bool isAllTile,
    required int? colInLayer,
    required bool isColMuted,
    required bool isLayerMuted,
    required bool muteButtonActive,
    required bool soloVisual,
    required double fontSize,
    required TableState tableState,
    Key? layerMuteTutorialKey,
  }) {
    final mutedVisual =
        isAllTile ? isLayerMuted : (isLayerMuted || isColMuted);
    final labelText =
        isAllTile ? 'ALL' : 'COL${colInLayer! + 1}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceBase,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: AppColors.sequencerBorder, width: 0.5),
      ),
      foregroundDecoration: mutedVisual
          ? BoxDecoration(
              color: Colors.black.withOpacity(0.18),
              borderRadius: BorderRadius.circular(2),
            )
          : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final labelFontSizeTile =
              (fontSize * 0.95).clamp(8.0, 11.0);
          const gapAfterLabel = 5.0;
          const gapBetweenMs = 6.0;

          void onMuteTap() {
            if (isAllTile) {
              final nextMuted = !tableState.isLayerMuted(layerIndex);
              tableState.setLayerMuted(layerIndex, nextMuted);
              final appState = context.read<AppState>();
              if (appState.activeTutorialStep ==
                  TutorialStep.sequencerLayersHint) {
                appState.markLayersMuteToggleAction(
                  isMutedAfterToggle: nextMuted,
                );
              }
            } else {
              tableState.setLayerColumnMuted(
                layerIndex,
                colInLayer!,
                !muteButtonActive,
              );
            }
          }

          void onSoloTap() {
            if (isAllTile) {
              tableState.setLayerSoloed(
                layerIndex,
                !tableState.isLayerSoloed(layerIndex),
              );
            } else {
              tableState.setLayerColumnSoloed(
                layerIndex,
                colInLayer!,
                !soloVisual,
              );
            }
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                labelText,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: TextStyle(
                  color: mutedVisual
                      ? AppColors.sequencerLightText.withOpacity(0.65)
                      : AppColors.sequencerLightText,
                  fontSize: labelFontSizeTile,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: gapAfterLabel),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, b) {
                          final bh = b.maxHeight;
                          final bfs = (bh * 0.42).clamp(12.0, 18.0);
                          return _buildSettingsButton(
                            'M',
                            muteButtonActive,
                            bh,
                            bfs,
                            onMuteTap,
                            key: layerMuteTutorialKey,
                            tutorialTarget: isAllTile
                                ? TutorialInteractionTarget.layerMuteButton
                                : null,
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: gapBetweenMs),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, b) {
                          final bh = b.maxHeight;
                          final bfs = (bh * 0.42).clamp(12.0, 18.0);
                          return _buildSettingsButton(
                            'S',
                            soloVisual,
                            bh,
                            bfs,
                            onSoloTap,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

}
