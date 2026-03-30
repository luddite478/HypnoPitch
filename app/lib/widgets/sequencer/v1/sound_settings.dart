import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../utils/app_colors.dart';
import 'package:provider/provider.dart';
import '../../../state/sequencer/table.dart';
import '../../../state/sequencer/sample_bank.dart';
import '../../../state/sequencer/sample_browser.dart';
import '../../../state/sequencer/edit.dart';
import '../../../state/sequencer/playback.dart';
import '../../../state/app_state.dart';
import '../../../ffi/table_bindings.dart' show CellData;
// musical notes handled elsewhere if needed
import 'generic_slider.dart';
import '../../../state/sequencer/slider_overlay.dart';
import 'wheel_select_widget.dart';
import 'sample_selection_widget.dart';
import '../../tutorial_pulse_widget.dart';

// Pitch conversion utilities
class PitchConversion {
  /// Convert UI slider value (0.0-1.0) to pitch ratio (0.03125-32.0)
  /// UI: 0.0 = -12 semitones, 0.5 = 0 semitones, 1.0 = +12 semitones
  static double uiValueToPitchRatio(double uiValue) {
    if (uiValue < 0.0 || uiValue > 1.0)
      return 1.0; // Fallback to original pitch

    // Convert: UI 0.0→-12 semitones, 0.5→0 semitones, 1.0→+12 semitones
    final semitones = uiValue * 24.0 - 12.0;
    return math.pow(2.0, semitones / 12.0).toDouble();
  }

  /// Convert pitch ratio (0.03125-32.0) to UI slider value (0.0-1.0)
  static double pitchRatioToUiValue(double ratio) {
    if (ratio <= 0.0) return 0.5; // Fallback to center

    // Convert: ratio → semitones → UI value
    final semitones = 12.0 * (math.log(ratio) / math.ln2);
    return (semitones + 12.0) / 24.0;
  }

  /// Convert pitch ratio to semitones (-12 to +12)
  static int pitchRatioToSemitones(double ratio) {
    if (ratio <= 0.0) return 0;
    final semitones = 12.0 * (math.log(ratio) / math.ln2);
    return semitones.round().clamp(-12, 12);
  }

  /// Convert semitones (-12 to +12) to pitch ratio
  static double semitonesToPitchRatio(int semitones) {
    return math.pow(2.0, semitones / 12.0).toDouble();
  }
}

enum SettingsType { cell, sample, master }

class SoundSettingsWidget extends StatefulWidget {
  final SettingsType type;
  final String title;
  final List<String> headerButtons;
  final VoidCallback closeAction;
  final String noDataMessage;
  final IconData noDataIcon;
  final bool showDeleteButton;
  final bool showCloseButton;

  const SoundSettingsWidget({
    super.key,
    required this.type,
    required this.title,
    required this.headerButtons,
    required this.closeAction,
    required this.noDataMessage,
    required this.noDataIcon,
    this.showDeleteButton = false,
    this.showCloseButton = true,
  });

  // Factory constructors for common use cases
  factory SoundSettingsWidget.forCell() {
    return const SoundSettingsWidget(
      type: SettingsType.cell,
      title: 'Cell Settings',
      headerButtons: ['VOL', 'KEY'],
      closeAction: _noop,
      noDataMessage: 'Tap a cell with a sample to configure',
      noDataIcon: Icons.grid_off,
      showCloseButton: false,
    );
  }

  factory SoundSettingsWidget.forSample() {
    return const SoundSettingsWidget(
      type: SettingsType.sample,
      title: 'Sample Settings',
      headerButtons: ['VOL', 'KEY'],
      closeAction: _noop,
      noDataMessage: 'Select a sample to configure',
      noDataIcon: Icons.music_off,
      showCloseButton: false,
    );
  }

  factory SoundSettingsWidget.forMaster() {
    return const SoundSettingsWidget(
      type: SettingsType.master,
      title: 'Master Settings',
      headerButtons: ['VOL', 'BPM'],
      closeAction: _noop,
      noDataMessage: 'Master controls not available',
      noDataIcon: Icons.settings,
      showDeleteButton: false,
      showCloseButton: false,
    );
  }

  static void _noop() {}

  @override
  State<SoundSettingsWidget> createState() => _SoundSettingsWidgetState();
}

class _SoundSettingsWidgetState extends State<SoundSettingsWidget> {
  String _selectedControl =
      'VOL'; // Default to VOL for cell/sample, will be set to first button for master

  // Simple variables for main layout areas (same as master settings template)
  double _headerButtonsHeight = 0.45; // 25% for header buttons area
  double _sliderTileHeightPercent = 0.50; // 60% for slider tile area
  double _spacingHeight = 0.02; // 2% for spacing between areas

  // Simple variables for slider components heights (within the slider tile)
  // Reserved for future layout tuning
  // Preview debounce (ms) for live sound during slider drag (single control point)
  static const int _previewDebounceMs = 40;

  // Debounce timers for pitch changes
  Timer? _cellPitchDebounceTimer;
  Timer? _samplePitchDebounceTimer;
  // Processing timers to stop spinner heuristically
  Timer? _processingStopTimer; // fallback (kept in case polling misses)
  Timer? _processingPollTimer;
  // Debounce timers for volume
  Timer? _sampleVolumeDebounceTimer;
  Timer? _cellVolumeDebounceTimer;
  // Live preview debounce (single timer for both sliders)
  Timer? _previewDebounceTimer;

  @override
  void initState() {
    super.initState();
    // Set default control based on type
    if (widget.type == SettingsType.master) {
      _selectedControl =
          widget.headerButtons.isNotEmpty ? widget.headerButtons.first : 'BPM';
    } else {
      _selectedControl = 'VOL';
    }
  }

  // (removed legacy ratio-based polling)

  @override
  void dispose() {
    _cellPitchDebounceTimer?.cancel();
    _samplePitchDebounceTimer?.cancel();
    _processingStopTimer?.cancel();
    _processingPollTimer?.cancel();
    _sampleVolumeDebounceTimer?.cancel();
    _cellVolumeDebounceTimer?.cancel();
    _previewDebounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer4<TableState, SampleBankState, EditState, PlaybackState>(
      builder: (context, tableState, sampleBankState, editState, playbackState,
          child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            // Calculate responsive sizes based on available space - INHERIT from parent
            final panelHeight = constraints.maxHeight;

            // Padding & ratios
            final padding = panelHeight * 0.03;

            final innerHeight = panelHeight - padding * 2;
            final borderThickness = 1.0;
            final innerHeightAdj = innerHeight - borderThickness * 2;

            // Use the simple variables for layout calculations
            final headerHeight = innerHeightAdj * _headerButtonsHeight;
            // reserve: final spacingHeight = innerHeightAdj * _spacingHeight;
            final contentHeight = innerHeightAdj * _sliderTileHeightPercent;

            final labelFontSize = (headerHeight * 0.25).clamp(8.0, 11.0);

            // Get current data info
            final _HasDataAndIndex hdi = _resolveHasDataAndIndex(
                widget.type, tableState, sampleBankState, editState);
            final bool hasData = hdi.hasData;
            final int? currentIndex = hdi.index;
            final allSimilarCells = hdi.allSimilarCells;

            return Container(
              padding: EdgeInsets.all(padding),
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
              child: Column(
                children: [
                  // Header buttons area - controllable via _headerButtonsHeight
                  Expanded(
                    flex: (_headerButtonsHeight * 100).round(),
                    child: LayoutBuilder(
                      builder: (context, headerConstraints) {
                        return _buildScrollableHeader(
                            headerHeight,
                            labelFontSize,
                            headerConstraints.maxWidth,
                            tableState,
                            sampleBankState,
                            editState,
                            playbackState,
                            currentIndex,
                            allSimilarCells);
                      },
                    ),
                  ),

                  // Top spacer - controllable via _spacingHeight
                  Spacer(flex: (_spacingHeight * 100).round()),

                  // Slider tile area - controllable via _sliderTileHeightPercent
                  Expanded(
                    flex: (_sliderTileHeightPercent * 100).round(),
                    child: () {
                      if (widget.type == SettingsType.cell) {
                        return (hasData && currentIndex != null)
                            ? _buildActiveControl(
                                tableState,
                                sampleBankState,
                                editState,
                                playbackState,
                                currentIndex,
                                contentHeight,
                                padding,
                                labelFontSize,
                                allSimilarCells)
                            : const SizedBox.shrink();
                      } else {
                        return (hasData && currentIndex != null)
                            ? _buildActiveControl(
                                tableState,
                                sampleBankState,
                                editState,
                                playbackState,
                                currentIndex,
                                contentHeight,
                                padding,
                                labelFontSize,
                                null)
                            : _buildNoDataMessage(contentHeight, labelFontSize);
                      }
                    }(),
                  ),

                  // Bottom spacer - controllable via _spacingHeight
                  Spacer(flex: (_spacingHeight * 100).round()),

                  // Remaining space (auto-adjusts based on other areas)
                  Spacer(
                      flex: ((1.0 -
                                  _headerButtonsHeight -
                                  _spacingHeight -
                                  _sliderTileHeightPercent -
                                  _spacingHeight) *
                              100)
                          .round()
                          .clamp(0, 100)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _getContextLabel(TableState tableState,
      SampleBankState sampleBankState, EditState editState, int? currentIndex) {
    switch (widget.type) {
      case SettingsType.cell:
        if (currentIndex != null) {
          final visibleCols = tableState.getVisibleCols().length;
          final row = currentIndex ~/ visibleCols;
          final col = currentIndex % visibleCols;
          final rowDisplay = row + 1;
          final colDisplay = col + 1;
          return 'Cell $rowDisplay:$colDisplay';
        }
        return 'Cell';
      case SettingsType.sample:
        if (currentIndex != null) {
          return 'Sample slot ${currentIndex + 1}';
        }
        return 'Sample';
      case SettingsType.master:
        return 'Master';
    }
  }

  /// Same effective pitch/volume semantics as the VOL slider live preview.
  void _triggerCellLabelPreview({
    required CellData cell,
    required SampleBankState sampleBank,
    required int step,
    required int colAbs,
    required PlaybackState playback,
  }) {
    if (!cell.isNotEmpty || cell.sampleSlot < 0) return;

    double defaultVol = 1.0;
    if (cell.sampleSlot >= 0) {
      final sd = sampleBank.getSampleData(cell.sampleSlot);
      defaultVol = (sd.volume >= 0.0 && sd.volume <= 1.0) ? sd.volume : 1.0;
    }
    final double vol = (cell.volume < 0.0) ? defaultVol : cell.volume;
    if (vol <= 0.0) {
      playback.stopPreview();
      return;
    }

    double defaultPitch = 1.0;
    if (cell.sampleSlot >= 0) {
      final sd = sampleBank.getSampleData(cell.sampleSlot);
      defaultPitch = (sd.pitch > 0.0) ? sd.pitch : 1.0;
    }
    final effPitch = (cell.pitch < 0.0) ? defaultPitch : cell.pitch;

    playback.stopPreview();
    playback.previewCell(
      step: step,
      colAbs: colAbs,
      pitchRatio: effPitch,
      volume01: vol,
    );
  }

  Widget _buildContextLabelTile(
      double headerHeight,
      double labelFontSize,
      double availableWidth,
      TableState tableState,
      SampleBankState sampleBankState,
      EditState editState,
      PlaybackState playbackState,
      int? currentIndex,
      _AllSimilarCells? allSimilarCells) {
    // Cap width with floor (buffer vs float error); min keeps tiny layouts usable.
    final contextLabelMaxWidth = math.max(
      36.0,
      (availableWidth * 0.179).floorToDouble(),
    );
    final tileHeight = headerHeight * 0.7;

    if (widget.type == SettingsType.cell && currentIndex != null) {
      Color? sampleColor;
      final visibleCols = tableState.getVisibleCols().length;
      final row = currentIndex ~/ visibleCols;
      final col = currentIndex % visibleCols;
      final sectionStart =
          tableState.getSectionStartStep(tableState.uiSelectedSection);
      final layerStart =
          tableState.getLayerStartCol(tableState.uiSelectedLayer);
      final step = sectionStart + row;
      final colAbs = layerStart + col;
      final cellPtr = tableState.getCellPointer(step, colAbs);
      final cellData = CellData.fromPointer(cellPtr);

      if (cellData.isNotEmpty && cellData.sampleSlot >= 0) {
        final slot = cellData.sampleSlot;
        if (slot < sampleBankState.uiBankColors.length) {
          sampleColor = sampleBankState.uiBankColors[slot];
        }
      }
      final String labelText = '${row + 1}-${col + 1}';

      final squareSize = (tileHeight * 0.4).clamp(5.0, 12.0);

      final Widget labelTile = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: contextLabelMaxWidth),
        child: Container(
          height: tileHeight,
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 3.0),
          decoration: BoxDecoration(
            color: AppColors.sequencerSurfaceBase,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: AppColors.sequencerBorder, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (sampleColor != null) ...[
                Container(
                  width: squareSize,
                  height: squareSize,
                  decoration: BoxDecoration(
                    color: sampleColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 3),
              ],
              Expanded(
                child: Text(
                  labelText,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    color: AppColors.sequencerLightText,
                    fontSize: labelFontSize,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      );

      final bool canPreview =
          cellData.isNotEmpty && cellData.sampleSlot >= 0;
      if (canPreview) {
        return Semantics(
          button: true,
          label: 'Play cell sound',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _triggerCellLabelPreview(
                  cell: cellData,
                  sampleBank: sampleBankState,
                  step: step,
                  colAbs: colAbs,
                  playback: playbackState,
                ),
            child: labelTile,
          ),
        );
      }

      return labelTile;
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: contextLabelMaxWidth),
      child: Container(
        height: tileHeight,
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        decoration: BoxDecoration(
          color: AppColors.sequencerSurfaceBase,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: AppColors.sequencerBorder, width: 1),
        ),
        alignment: Alignment.center,
        child: Text(
          _getContextLabel(
              tableState, sampleBankState, editState, currentIndex),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          style: TextStyle(
            color: AppColors.sequencerLightText,
            fontSize: labelFontSize,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildScrollableHeader(
      double headerHeight,
      double labelFontSize,
      double availableWidth,
      TableState tableState,
      SampleBankState sampleBankState,
      EditState editState,
      PlaybackState playbackState,
      int? currentIndex,
      _AllSimilarCells? allSimilarCells) {
    final appState = context.watch<AppState>();
    final cellInfo = _resolveCellSelectionInfo(tableState, currentIndex);
    return Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Context label tile showing which menu is opened
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: _buildContextLabelTile(
                  headerHeight,
                  labelFontSize,
                  availableWidth,
                  tableState,
                  sampleBankState,
                  editState,
                  playbackState,
                  currentIndex,
                  allSimilarCells),
            ),
            if (widget.type == SettingsType.cell &&
                (cellInfo != null || allSimilarCells != null))
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: SizedBox(
                  width: 132,
                  child: _buildCellSampleSelectorButton(
                    headerHeight: headerHeight,
                    fontSize: labelFontSize,
                    sampleBankState: sampleBankState,
                    cellInfo: cellInfo,
                    allSimilarCells: allSimilarCells,
                  ),
                ),
              ),
            // Header buttons from the configuration
            ...widget.headerButtons.map((buttonName) {
              final shouldPulseButton =
                  widget.type == SettingsType.cell &&
                      appState.activeTutorialStep ==
                          TutorialStep.sequencerCellParamsHint &&
                      ((buttonName == 'VOL' &&
                              appState.showCellParamsVolumePointer) ||
                          (buttonName == 'KEY' &&
                              appState.showCellParamsKeyPointer));
              final tutorialButtonKey =
                  widget.type == SettingsType.cell &&
                          appState.activeTutorialStep ==
                              TutorialStep.sequencerCellParamsHint
                      ? (buttonName == 'VOL'
                          ? appState.cellParamsVolumeButtonTutorialKey
                          : (buttonName == 'KEY'
                              ? appState.cellParamsKeyButtonTutorialKey
                              : null))
                      : null;
              return Padding(
                padding: const EdgeInsets.only(
                    right: 8.0), // Spacing between buttons
                child: SizedBox(
                  key: tutorialButtonKey,
                  width: 80, // Fixed width for each button
                  child: _buildSettingsButton(
                      buttonName,
                      _selectedControl == buttonName,
                      headerHeight * 0.7,
                      labelFontSize,
                      shouldPulseButton, () {
                    setState(() {
                      _selectedControl = buttonName;
                    });
                  }),
                ),
              );
            }).toList(),

            // Optional spacing before action buttons
            if (widget.showDeleteButton || widget.showCloseButton)
              const SizedBox(width: 16.0),

            // DEL button (if enabled)
            // Delete moved to Edit Buttons panel

            // Close button (if enabled)
            if (widget.showCloseButton)
              SizedBox(
                width: 60,
                child: GestureDetector(
                  onTap: widget.closeAction,
                  child: Container(
                    height: headerHeight * 0.7,
                    decoration: BoxDecoration(
                      color: AppColors.sequencerSurfacePressed,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                        color: AppColors.sequencerBorder,
                        width: 0.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.sequencerShadow,
                          blurRadius: 1,
                          offset: const Offset(0, 0.5),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(
                        Icons.close,
                        color: AppColors.sequencerLightText,
                        size: (headerHeight * 0.35).clamp(12.0, 18.0),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveControl(
      TableState tableState,
      SampleBankState sampleBankState,
      EditState editState,
      PlaybackState playbackState,
      int index,
      double height,
      double padding,
      double fontSize,
      _AllSimilarCells? allSimilarCells) {
    // Handle different control types based on current selection and settings type
    if (widget.type == SettingsType.master) {
      return _buildMasterControl(
          playbackState, _selectedControl, height, padding, fontSize);
    } else {
      // Cell and Sample controls
      switch (_selectedControl) {
        case 'VOL':
          return _buildVolumeControl(tableState, sampleBankState, editState,
              index, height, padding, fontSize, allSimilarCells);
        case 'KEY':
          return _buildPitchControl(tableState, sampleBankState, editState,
              index, height, padding, fontSize, allSimilarCells);
        // case 'EQ':
        //   return _buildPlaceholderControl('EQ', 'Equalizer settings', height, padding, fontSize);
        // case 'RVB':
        //   return _buildPlaceholderControl('RVB', 'Reverb settings', height, padding, fontSize);
        // case 'DLY':
        //   return _buildPlaceholderControl('DLY', 'Delay settings', height, padding, fontSize);
        default:
          return _buildVolumeControl(tableState, sampleBankState, editState,
              index, height, padding, fontSize, allSimilarCells);
      }
    }
  }

  Widget _buildMasterControl(PlaybackState sequencer, String controlType,
      double height, double padding, double fontSize) {
    switch (controlType) {
      case 'BPM':
        return _buildBPMControl(sequencer, height, padding, fontSize);
      case 'VOL':
        return _buildMasterVolumeControl(sequencer, height, padding, fontSize);
      // case 'COMP':
      //   return _buildPlaceholderControl('COMP', 'Compression settings', height, padding, fontSize);
      // case 'EQ':
      //   return _buildPlaceholderControl('EQ', 'Equalizer settings', height, padding, fontSize);
      // case 'RVB':
      //   return _buildPlaceholderControl('RVB', 'Reverb settings', height, padding, fontSize);
      // case 'DLY':
      //   return _buildPlaceholderControl('DLY', 'Delay settings', height, padding, fontSize);
      // case 'FILTER':
      //   return _buildPlaceholderControl('FILTER', 'Filter settings', height, padding, fontSize);
      // case 'DIST':
      //   return _buildPlaceholderControl('DIST', 'Distortion settings', height, padding, fontSize);
      default:
        return _buildBPMControl(sequencer, height, padding, fontSize);
    }
  }

  Widget _buildMasterVolumeControl(
      PlaybackState sequencer, double height, double padding, double fontSize) {
    return Container(
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
      child: ValueListenableBuilder<double>(
        valueListenable: sequencer.masterVolumeNotifier,
        builder: (context, vol, _) => GenericSlider(
          value: vol,
          min: 0.0,
          max: 1.0,
          divisions: 100,
          type: SliderType.volume,
          onChanged: (value) => sequencer.setMasterVolume(value),
          height: height,
          sliderOverlay: context.read<SliderOverlayState>(),
          contextLabel: 'Master',
        ),
      ),
    );
  }

  Widget _buildBPMControl(
      PlaybackState sequencer, double height, double padding, double fontSize) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: padding * 0.5, vertical: padding * 0.3),
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
      child: ValueListenableBuilder<int>(
        valueListenable: sequencer.bpmNotifier,
        builder: (context, bpm, child) {
          return Center(
            child: GenericSlider(
              value: bpm.toDouble(),
              min: 60,
              max: 300,
              divisions: 240,
              type: SliderType.bpm,
              onChanged: (value) => sequencer.setBpm(value.round()),
              height: height,
              sliderOverlay: context.read<SliderOverlayState>(),
            ),
          );
        },
      ),
    );
  }

  Widget _buildVolumeControl(
      TableState tableState,
      SampleBankState sampleBankState,
      EditState editState,
      int index,
      double height,
      double padding,
      double fontSize,
      _AllSimilarCells? allSimilarCells) {
    // Get info text based on type
    // reserved for future UI text
    // String leftInfo = '';
    // String centerInfo = '';

    if (widget.type == SettingsType.cell) {
      final selectedCell = _resolveSelectedCell(editState);
      if (selectedCell != null) {
        final visibleCols = tableState.getVisibleCols().length;
        final row = selectedCell ~/ visibleCols;
        final col = selectedCell % visibleCols;
        final sectionStart =
            tableState.getSectionStartStep(tableState.uiSelectedSection);
        final layerStart =
            tableState.getLayerStartCol(tableState.uiSelectedLayer);
        final step = sectionStart + row;
        final colAbs = layerStart + col;
        final cellPtr = tableState.getCellPointer(step, colAbs);
        final cellData = CellData.fromPointer(cellPtr);
        final int? cellSample =
            cellData.isNotEmpty ? cellData.sampleSlot : null;
        // leftInfo = 'L1-${row + 1}-${col + 1}-$sampleLetter';

        // Get sample name
        if (cellSample != null) {
          // final sampleName = sampleBankState.getSlotName(cellSample);
        }
      }
    } else {
      // Sample mode
      // leftInfo = String.fromCharCode(65 + index);
      // final sampleName = sampleBankState.getSlotName(index);
    }

    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: padding * 0.3, vertical: padding * 0.05),
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceRaised,
        borderRadius: BorderRadius.circular(2), // Sharp corners
        border: Border.all(
          color: AppColors.sequencerBorder,
          width: 1,
        ),
        boxShadow: [
          // Protruding effect
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
      child: Center(
        child: widget.type == SettingsType.sample
            ? ValueListenableBuilder<double>(
                valueListenable: sampleBankState.getSampleVolumeNotifier(index),
                builder: (context, vol, _) => GenericSlider(
                  value: vol,
                  min: 0.0,
                  max: 1.0,
                  divisions: 100,
                  type: SliderType.volume,
                  onChanged: (value) {
                    _sampleVolumeDebounceTimer?.cancel();
                    _sampleVolumeDebounceTimer =
                        Timer(const Duration(milliseconds: 200), () {
                      sampleBankState.setSampleSettings(index, volume: value);
                    });

                    // Live preview: debounce and restart note
                    final playback = context.read<PlaybackState>();
                    _previewDebounceTimer?.cancel();
                    _previewDebounceTimer =
                        Timer(Duration(milliseconds: _previewDebounceMs), () {
                      if (value <= 0.0) {
                        playback.stopPreview();
                        return;
                      }
                      final pitch =
                          sampleBankState.getSamplePitchNotifier(index).value;
                      playback.previewSampleSlot(index,
                          pitchRatio: pitch, volume01: value);
                    });
                  },
                  height: height,
                  sliderOverlay: context.read<SliderOverlayState>(),
                  onChangeStart: (v) {
                    // Immediate preview start on drag begin
                    final playback = context.read<PlaybackState>();
                    if (v <= 0.0) {
                      playback.stopPreview();
                      return;
                    }
                    final pitch =
                        sampleBankState.getSamplePitchNotifier(index).value;
                    playback.previewSampleSlot(index,
                        pitchRatio: pitch, volume01: v);
                  },
                  onChangeEnd: (_) {
                    // Stop sustaining when user ends interaction
                    final playback = context.read<PlaybackState>();
                    playback.stopPreview();
                  },
                  contextLabel: 'Sample slot ${index + 1}',
                ),
              )
            : _buildCellVolumeSlider(
                tableState, index, height, allSimilarCells),
      ),
    );
  }

  Widget _buildPitchControl(
      TableState tableState,
      SampleBankState sampleBankState,
      EditState editState,
      int index,
      double height,
      double padding,
      double fontSize,
      _AllSimilarCells? allSimilarCells) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: padding * 0.3, vertical: padding * 0.05),
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
      child: Center(
        child: widget.type == SettingsType.sample
            ? ValueListenableBuilder<double>(
                valueListenable: sampleBankState.getSamplePitchNotifier(index),
                builder: (context, pitch, _) {
                  final semitones =
                      PitchConversion.pitchRatioToSemitones(pitch);
                  return SemitoneWheelWidget(
                    semitones: semitones,
                    onSemitonesChanged: (newSemitones) {
                      final ratio =
                          PitchConversion.semitonesToPitchRatio(newSemitones);

                      // Debounce sample pitch commit
                      _samplePitchDebounceTimer?.cancel();
                      _samplePitchDebounceTimer =
                          Timer(const Duration(milliseconds: 250), () {
                        sampleBankState.setSampleSettings(index, pitch: ratio);
                      });

                      // Live preview: immediate restart of note with new pitch
                      final playback = context.read<PlaybackState>();
                      final vol =
                          sampleBankState.getSampleVolumeNotifier(index).value;
                      _previewDebounceTimer?.cancel();
                      _previewDebounceTimer =
                          Timer(Duration(milliseconds: _previewDebounceMs), () {
                        if (vol <= 0.0) {
                          playback.stopPreview();
                          return;
                        }
                        playback.previewSampleSlot(index,
                            pitchRatio: ratio, volume01: vol);
                      });
                    },
                    onChangeStart: () {
                      // No preview on start - let onSemitonesChanged handle it
                      // This prevents double-sound (old pitch then new pitch)
                    },
                    onChangeEnd: () {
                      // Stop preview when scrolling ends
                      final playback = context.read<PlaybackState>();
                      playback.stopPreview();
                    },
                  );
                },
              )
            : _buildCellPitchWheel(tableState, index, height, allSimilarCells),
      ),
    );
  }

  Widget _buildNoDataMessage(double height, double fontSize) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceRaised,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: AppColors.sequencerBorder,
          width: 1,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              widget.noDataIcon,
              color: AppColors.sequencerLightText,
              size: fontSize * 3,
            ),
            SizedBox(height: height * 0.05),
            Text(
              widget.noDataMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.sequencerLightText,
                fontSize: fontSize * 1.2,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsButton(
      String label,
      bool isSelected,
      double height,
      double fontSize,
      bool pulseHighlight,
      VoidCallback? onTap) {
    final button = Container(
      height: height,
      decoration: BoxDecoration(
        color: isSelected
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
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? AppColors.sequencerPageBackground
                : AppColors.sequencerText,
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: TutorialPulseWidget(
        enabled: pulseHighlight,
        borderRadius: BorderRadius.circular(2),
        child: button,
      ),
    );
  }

  _CellSelectionInfo? _resolveCellSelectionInfo(
      TableState tableState, int? currentIndex) {
    if (widget.type != SettingsType.cell || currentIndex == null) return null;
    final visibleCols = tableState.getVisibleCols().length;
    final row = currentIndex ~/ visibleCols;
    final col = currentIndex % visibleCols;
    final sectionStart =
        tableState.getSectionStartStep(tableState.uiSelectedSection);
    final layerStart = tableState.getLayerStartCol(tableState.uiSelectedLayer);
    final step = sectionStart + row;
    final colAbs = layerStart + col;
    final cellData = tableState.getCellNotifier(step, colAbs).value;
    return _CellSelectionInfo(
      row: row,
      col: col,
      step: step,
      colAbs: colAbs,
      cellData: cellData,
    );
  }

  Widget _buildCellSampleSelectorButton({
    required double headerHeight,
    required double fontSize,
    required SampleBankState sampleBankState,
    _CellSelectionInfo? cellInfo,
    _AllSimilarCells? allSimilarCells,
  }) {
    final appState = context.watch<AppState>();
    final slot =
        allSimilarCells?.sampleSlot ?? cellInfo?.cellData.sampleSlot ?? -1;
    final bool hasSample = slot >= 0;
    String label = 'SELECT SAMPLE';
    if (hasSample) {
      final slotName = sampleBankState.getSlotName(slot);
      label = (slotName != null && slotName.trim().isNotEmpty)
          ? _formatCellSampleLabel(slotName)
          : 'SAMPLE ${slot + 1}';
    }

    return GestureDetector(
      onTap: () {
        if (!appState.canInteractWithTutorialTarget(
            TutorialInteractionTarget.selectSampleButton)) {
          return;
        }
        final sampleBrowser = context.read<SampleBrowserState>();
        final sampleBank = context.read<SampleBankState>();
        final playback = context.read<PlaybackState>();
        final table = context.read<TableState>();

        // Open browser in the current sample's folder when available.
        if (hasSample) {
          final slotPath = sampleBankState.getSlotPath(slot);
          sampleBrowser.navigateToSamplePath(slotPath);
        }

        if (allSimilarCells != null) {
          final int bankSlot;
          if (allSimilarCells.sampleSlot != null) {
            bankSlot = allSimilarCells.sampleSlot!;
          } else if (cellInfo != null && cellInfo.cellData.sampleSlot >= 0) {
            bankSlot = cellInfo.cellData.sampleSlot;
          } else {
            bankSlot = sampleBank.activeSlot;
          }
          sampleBrowser.showForCell(
            allSimilarCells.selectedStep,
            allSimilarCells.selectedCol,
            bankSlot: bankSlot,
          );
        } else if (cellInfo != null) {
          final bankSlot = cellInfo.cellData.sampleSlot >= 0
              ? cellInfo.cellData.sampleSlot
              : sampleBank.activeSlot;
          sampleBrowser.showForCell(cellInfo.step, cellInfo.colAbs,
              bankSlot: bankSlot);
        } else {
          return;
        }
        final editState = context.read<EditState>();
        showDialog(
          context: context,
          barrierDismissible: true,
          barrierColor: Colors.black54,
          builder: (_) => MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: sampleBrowser),
              ChangeNotifierProvider.value(value: sampleBank),
              ChangeNotifierProvider.value(value: playback),
              ChangeNotifierProvider.value(value: table),
              ChangeNotifierProvider.value(value: editState),
            ],
            child: const _CellSampleBrowserDialog(),
          ),
        ).then((_) => sampleBrowser.hide());
      },
      child: Container(
        key: appState.activeTutorialStep == TutorialStep.sequencerSelectSampleHint
            ? appState.selectSampleTutorialKey
            : null,
        height: headerHeight * 0.7,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: hasSample
              ? AppColors.sequencerSurfaceRaised
              : const Color(
                  0xFFD3D3D3), // Light gray highlight for add-sample action
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color:
                hasSample ? AppColors.sequencerBorder : const Color(0xFFBDBDBD),
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color:
                  hasSample ? AppColors.sequencerText : const Color(0xFF3A3A3A),
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }

  String _formatCellSampleLabel(String rawName) {
    final trimmed = rawName.trim();
    if (trimmed.isEmpty) return 'SELECT SAMPLE';
    final withoutPrefix = trimmed.replaceFirst(
      RegExp(r'^_?sample[_\-\s]*', caseSensitive: false),
      '',
    );
    final normalized = withoutPrefix.trim();
    return normalized.isEmpty ? trimmed : normalized;
  }

  // Helpers
  static int? _resolveSelectedCell(EditState editState) {
    final selected = editState.selectedCells;
    if (selected.isEmpty) return null;
    return selected.first;
  }

  /// True if at least one cell in the list has a loaded sample (for batch volume edits).
  static bool _anyCellHasSampleForVolume(
      TableState tableState, List<({int step, int col})> cells) {
    for (final c in cells) {
      final ptr = tableState.getCellPointer(c.step, c.col);
      if (ptr.address == 0) continue;
      final cd = CellData.fromPointer(ptr);
      if (cd.isNotEmpty && cd.sampleSlot != -1) return true;
    }
    return false;
  }

  _HasDataAndIndex _resolveHasDataAndIndex(
      SettingsType type,
      TableState tableState,
      SampleBankState sampleBankState,
      EditState editState) {
    if (type == SettingsType.sample) {
      final idx = sampleBankState.activeSlot;
      final has = sampleBankState.isSlotLoaded(idx) ||
          sampleBankState.getSlotName(idx) != null;
      return _HasDataAndIndex(hasData: has, index: idx);
    } else if (type == SettingsType.cell) {
      final selectedBatch = editState.isInSelectionMode
          ? editState.getSelectedBatchForSettings()
          : null;
      if (selectedBatch != null) {
        // Use the selected anchor cell as slider reference for batch editing.
        final sectionStart =
            tableState.getSectionStartStep(tableState.uiSelectedSection);
        final layerStart =
            tableState.getLayerStartCol(tableState.uiSelectedLayer);
        final visibleCols = tableState.getVisibleCols().length;
        final row = selectedBatch.selectedStep - sectionStart;
        final col = selectedBatch.selectedCol - layerStart;
        final refIndex = row * visibleCols + col;
        return _HasDataAndIndex(
          hasData: true,
          index: refIndex,
          allSimilarCells: selectedBatch,
        );
      }
      final selectedCell = _resolveSelectedCell(editState);
      if (selectedCell == null)
        return const _HasDataAndIndex(hasData: false, index: null);
      return _HasDataAndIndex(hasData: true, index: selectedCell);
    }
    return const _HasDataAndIndex(hasData: true, index: 0);
  }

  // Delete action moved to Edit Buttons; keep stub removed.

  Widget _buildCellVolumeSlider(TableState tableState, int selectedCellIndex,
      double height, _AllSimilarCells? allSimilarCells) {
    final visibleCols = tableState.getVisibleCols().length;
    final row = selectedCellIndex ~/ visibleCols;
    final col = selectedCellIndex % visibleCols;
    final step =
        tableState.getSectionStartStep(tableState.uiSelectedSection) + row;
    final colAbs =
        tableState.getLayerStartCol(tableState.uiSelectedLayer) + col;
    final cellNotifier = tableState.getCellNotifier(step, colAbs);
    final cellsList = allSimilarCells?.cells ?? [(step: step, col: colAbs)];
    final batchVolumeEditable = allSimilarCells != null &&
        _anyCellHasSampleForVolume(tableState, cellsList);
    return ValueListenableBuilder<CellData>(
      valueListenable: cellNotifier,
      builder: (context, cell, _) {
        final appState = context.read<AppState>();
        final playback = context.read<PlaybackState>();
        final sliderOverlay = context.read<SliderOverlayState>();
        final sampleBank = context.read<SampleBankState>();
        final canEditVolume = batchVolumeEditable ||
            (cell.isNotEmpty && cell.sampleSlot != -1);
        double defaultVol = 1.0;
        if (cell.sampleSlot >= 0) {
          final sd = sampleBank.getSampleData(cell.sampleSlot);
          // Guard bad values; default should be 1.0 for display
          defaultVol = (sd.volume >= 0.0 && sd.volume <= 1.0) ? sd.volume : 1.0;
        }
        final double vol = (cell.volume < 0.0) ? defaultVol : cell.volume;
        return GenericSlider(
          value: vol,
          min: 0.0,
          max: 1.0,
          divisions: 100,
          type: SliderType.volume,
          onChanged: (value) {
            if (canEditVolume) {
              appState.markCellVolumeAdjusted(value);
              appState.markSelectModeVolumeChanged(value);
              _cellVolumeDebounceTimer?.cancel();
              _cellVolumeDebounceTimer =
                  Timer(const Duration(milliseconds: 150), () {
                tableState.setCellSettingsForCells(cellsList, volume: value);
              });

              // Live preview: debounce and restart note
              _previewDebounceTimer?.cancel();
              _previewDebounceTimer =
                  Timer(Duration(milliseconds: _previewDebounceMs), () {
                if (value <= 0.0) {
                  playback.stopPreview();
                  return;
                }
                // Resolve effective pitch from cell/sample for preview semantics
                final sampleBank = context.read<SampleBankState>();
                double defaultPitch = 1.0;
                if (cell.sampleSlot >= 0) {
                  final sd = sampleBank.getSampleData(cell.sampleSlot);
                  defaultPitch = (sd.pitch > 0.0) ? sd.pitch : 1.0;
                }
                final effPitch = (cell.pitch < 0.0) ? defaultPitch : cell.pitch;
                playback.previewCell(
                    step: step,
                    colAbs: colAbs,
                    pitchRatio: effPitch,
                    volume01: value);
              });
            }
          },
          height: height,
          sliderOverlay: sliderOverlay,
          onChangeStart: (v) {
            if (v <= 0.0 || !canEditVolume) {
              playback.stopPreview();
              return;
            }
            final sampleBank = context.read<SampleBankState>();
            double defaultPitch = 1.0;
            if (cell.sampleSlot >= 0) {
              final sd = sampleBank.getSampleData(cell.sampleSlot);
              defaultPitch = (sd.pitch > 0.0) ? sd.pitch : 1.0;
            }
            final effPitch = (cell.pitch < 0.0) ? defaultPitch : cell.pitch;
            playback.previewCell(
                step: step, colAbs: colAbs, pitchRatio: effPitch, volume01: v);
          },
          onChangeEnd: (value) {
            // GenericSlider clears its transient thumb position on end; the table
            // commit is debounced — flush now so the slider does not snap back.
            _cellVolumeDebounceTimer?.cancel();
            _cellVolumeDebounceTimer = null;
            if (canEditVolume) {
              tableState.setCellSettingsForCells(cellsList, volume: value);
            }
            playback.stopPreview();
          },
          contextLabel: allSimilarCells != null
              ? 'Selection'
              : 'Cell ${row + 1}:${col + 1}',
        );
      },
    );
  }

  Widget _buildCellPitchWheel(TableState tableState, int selectedCellIndex,
      double height, _AllSimilarCells? allSimilarCells) {
    final visibleCols = tableState.getVisibleCols().length;
    final row = selectedCellIndex ~/ visibleCols;
    final col = selectedCellIndex % visibleCols;
    final step =
        tableState.getSectionStartStep(tableState.uiSelectedSection) + row;
    final colAbs =
        tableState.getLayerStartCol(tableState.uiSelectedLayer) + col;
    final cellNotifier = tableState.getCellNotifier(step, colAbs);
    final cellsList = allSimilarCells?.cells ?? [(step: step, col: colAbs)];
    return ValueListenableBuilder<CellData>(
      valueListenable: cellNotifier,
      builder: (context, cell, _) {
        final appState = context.read<AppState>();
        final playback = context.read<PlaybackState>();
        final sampleBank = context.read<SampleBankState>();
        double defaultPitch = 1.0;
        if (cell.sampleSlot >= 0) {
          final sd = sampleBank.getSampleData(cell.sampleSlot);
          defaultPitch = (sd.pitch > 0.0) ? sd.pitch : 1.0;
        }
        final effectiveRatio = (cell.pitch < 0.0) ? defaultPitch : cell.pitch;
        final semitones = PitchConversion.pitchRatioToSemitones(effectiveRatio);

        if (cell.sampleSlot >= 0) {
          return SemitoneWheelWidget(
            semitones: semitones,
            onSemitonesChanged: (newSemitones) {
              if (cell.isNotEmpty && cell.sampleSlot != -1) {
                appState.markCellPitchAdjusted(newSemitones);
                final ratio =
                    PitchConversion.semitonesToPitchRatio(newSemitones);

                // Debounce cell pitch commit
                _cellPitchDebounceTimer?.cancel();
                _cellPitchDebounceTimer =
                    Timer(const Duration(milliseconds: 250), () {
                  tableState.setCellSettingsForCells(cellsList, pitch: ratio);
                });

                // Live preview: immediate restart of note with new pitch
                final sampleBank = context.read<SampleBankState>();
                // Resolve effective volume
                double defaultVol = 1.0;
                if (cell.sampleSlot >= 0) {
                  final sd = sampleBank.getSampleData(cell.sampleSlot);
                  defaultVol =
                      (sd.volume >= 0.0 && sd.volume <= 1.0) ? sd.volume : 1.0;
                }
                final effVol = (cell.volume < 0.0) ? defaultVol : cell.volume;
                _previewDebounceTimer?.cancel();
                _previewDebounceTimer =
                    Timer(Duration(milliseconds: _previewDebounceMs), () {
                  if (effVol <= 0.0) {
                    playback.stopPreview();
                    return;
                  }
                  playback.previewCell(
                      step: step,
                      colAbs: colAbs,
                      pitchRatio: ratio,
                      volume01: effVol);
                });
              }
            },
            onChangeStart: () {
              // No preview on start - let onSemitonesChanged handle it
              // This prevents double-sound (old pitch then new pitch)
            },
            onChangeEnd: () {
              // Stop preview when scrolling ends
              playback.stopPreview();
            },
          );
        } else {
          // No sample → show wheel but disabled
          return SemitoneWheelWidget(
            semitones: semitones,
            onSemitonesChanged: (_) {}, // No action when no sample
            enableHaptic: false,
          );
        }
      },
    );
  }

  // (watch helpers removed in favor of direct ValueListenableBuilder wiring)
}

typedef _AllSimilarCells = ({
  int? sampleSlot,
  int selectedStep,
  int selectedCol,
  List<({int step, int col})> cells
});

class _HasDataAndIndex {
  final bool hasData;
  final int? index;

  /// When set, the selected cell has a sample and SELECT mode is active (edit-all mode).
  final _AllSimilarCells? allSimilarCells;
  const _HasDataAndIndex(
      {required this.hasData, this.index, this.allSimilarCells});
}

class _CellSelectionInfo {
  final int row;
  final int col;
  final int step;
  final int colAbs;
  final CellData cellData;

  const _CellSelectionInfo({
    required this.row,
    required this.col,
    required this.step,
    required this.colAbs,
    required this.cellData,
  });
}

class _CellSampleBrowserDialog extends StatelessWidget {
  const _CellSampleBrowserDialog();

  static const double _kDialogWidthFactor = 0.88;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = screenSize.width * _kDialogWidthFactor;
    final maxHeight = (screenSize.height * 0.85).clamp(400.0, 800.0);
    final sampleBrowser = context.read<SampleBrowserState>();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Center(
        child: Container(
          width: dialogWidth,
          height: maxHeight,
          decoration: BoxDecoration(
            color: AppColors.sequencerSurfaceRaised,
            borderRadius: BorderRadius.circular(1.0),
            border: Border.all(color: AppColors.sequencerBorder, width: 0.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                        color: AppColors.sequencerBorder, width: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.library_music,
                        color: AppColors.sequencerAccent, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'SAMPLES',
                      style: TextStyle(
                        color: AppColors.sequencerText,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.close,
                          color: AppColors.sequencerLightText, size: 20),
                      onPressed: () {
                        sampleBrowser.hide();
                        Navigator.of(context).pop();
                      },
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ],
                ),
              ),
              const Expanded(
                child: SampleSelectionWidget(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
