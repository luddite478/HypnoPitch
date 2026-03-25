import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../utils/app_colors.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../state/sequencer/table.dart';
import '../../../state/sequencer/sample_bank.dart';
import '../../../state/sequencer/edit.dart';
import '../../../state/sequencer/playback.dart';
import '../../../ffi/playback_bindings.dart';
import '../../../ffi/table_bindings.dart' show CellData;
// musical notes handled elsewhere if needed
import 'generic_slider.dart';
import '../../../state/sequencer/slider_overlay.dart';


// Pitch conversion utilities
class PitchConversion {
  /// Convert UI slider value (0.0-1.0) to pitch ratio (0.03125-32.0)
  /// UI: 0.0 = -12 semitones, 0.5 = 0 semitones, 1.0 = +12 semitones
  static double uiValueToPitchRatio(double uiValue) {
    if (uiValue < 0.0 || uiValue > 1.0) return 1.0; // Fallback to original pitch
    
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
    );
  }

  factory SoundSettingsWidget.forMaster() {
    return const SoundSettingsWidget(
      type: SettingsType.master,
      title: 'Master Settings',
      headerButtons: ['BPM', 'MASTER'],
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
  String _selectedControl = 'VOL'; // Default to VOL for cell/sample, will be set to first button for master
  
  // Simple variables for main layout areas (same as master settings template)
  double _headerButtonsHeight = 0.45;     // 25% for header buttons area
  double _sliderTileHeightPercent = 0.50; // 60% for slider tile area
  double _spacingHeight = 0.02;           // 2% for spacing between areas
  
  // Simple variables for slider components heights (within the slider tile)
  // Reserved for future layout tuning

  // Debounce timers for pitch changes
  Timer? _cellPitchDebounceTimer;
  Timer? _samplePitchDebounceTimer;
  // Processing timers to stop spinner heuristically
  Timer? _processingStopTimer; // fallback (kept in case polling misses)
  Timer? _processingPollTimer;
  // Debounce timers for volume
  Timer? _sampleVolumeDebounceTimer;
  Timer? _cellVolumeDebounceTimer;

  @override
  void initState() {
    super.initState();
    // Set default control based on type
    if (widget.type == SettingsType.master) {
      _selectedControl = widget.headerButtons.isNotEmpty ? widget.headerButtons.first : 'BPM';
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer4<TableState, SampleBankState, EditState, PlaybackState>(
      builder: (context, tableState, sampleBankState, editState, playbackState, child) {
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
            final _HasDataAndIndex hdi = _resolveHasDataAndIndex(widget.type, tableState, sampleBankState, editState);
            final bool hasData = hdi.hasData;
            final int? currentIndex = hdi.index;
            
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
                    child: _buildScrollableHeader(headerHeight, labelFontSize, tableState, sampleBankState, editState, currentIndex),
                  ),
                  
                  // Top spacer - controllable via _spacingHeight
                  Spacer(flex: (_spacingHeight * 100).round()),
                  
                  // Slider tile area - controllable via _sliderTileHeightPercent
                  Expanded(
                    flex: (_sliderTileHeightPercent * 100).round(),
                    child: () {
                      if (widget.type == SettingsType.cell) {
                        return (hasData && currentIndex != null)
                            ? _buildActiveControl(tableState, sampleBankState, editState, playbackState, currentIndex, contentHeight, padding, labelFontSize)
                            : const SizedBox.shrink();
                      } else {
                        return (hasData && currentIndex != null)
                            ? _buildActiveControl(tableState, sampleBankState, editState, playbackState, currentIndex, contentHeight, padding, labelFontSize)
                            : _buildNoDataMessage(contentHeight, labelFontSize);
                      }
                    }(),
                  ),
                  
                  // Bottom spacer - controllable via _spacingHeight
                  Spacer(flex: (_spacingHeight * 100).round()),
                  
                  // Remaining space (auto-adjusts based on other areas)
                  Spacer(flex: ((1.0 - _headerButtonsHeight - _spacingHeight - _sliderTileHeightPercent - _spacingHeight) * 100).round().clamp(0, 100)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildScrollableHeader(double headerHeight, double labelFontSize, TableState tableState, SampleBankState sampleBankState, EditState editState, int? currentIndex) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // Preview button (speaker) for cell/sample settings, placed left of VOL
          if (widget.type != SettingsType.master)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: SizedBox(
                width: 48,
                child: _buildPreviewButton(headerHeight * 0.7, tableState, sampleBankState, editState, currentIndex),
              ),
            ),
          // Header buttons from the configuration
          ...widget.headerButtons.map((buttonName) {
            return Padding(
              padding: const EdgeInsets.only(right: 8.0), // Spacing between buttons
              child: SizedBox(
                width: 80, // Fixed width for each button
                child: _buildSettingsButton(
                  buttonName, 
                  _selectedControl == buttonName, 
                  headerHeight * 0.7, 
                  labelFontSize, 
                  () {
                    setState(() {
                      _selectedControl = buttonName;
                    });
                  }
                ),
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
    );
  }

  Widget _buildActiveControl(TableState tableState, SampleBankState sampleBankState, EditState editState, PlaybackState playbackState, int index, double height, double padding, double fontSize) {
    // Handle different control types based on current selection and settings type
    if (widget.type == SettingsType.master) {
      return _buildMasterControl(playbackState, _selectedControl, height, padding, fontSize);
    } else {
      // Cell and Sample controls
      switch (_selectedControl) {
        case 'VOL':
          return _buildVolumeControl(tableState, sampleBankState, editState, index, height, padding, fontSize);
        case 'KEY':
          return _buildPitchControl(tableState, sampleBankState, editState, index, height, padding, fontSize);
        // case 'EQ':
        //   return _buildPlaceholderControl('EQ', 'Equalizer settings', height, padding, fontSize);
        // case 'RVB':
        //   return _buildPlaceholderControl('RVB', 'Reverb settings', height, padding, fontSize);
        // case 'DLY':
        //   return _buildPlaceholderControl('DLY', 'Delay settings', height, padding, fontSize);
        default:
          return _buildVolumeControl(tableState, sampleBankState, editState, index, height, padding, fontSize);
      }
    }
  }

  Widget _buildMasterControl(PlaybackState sequencer, String controlType, double height, double padding, double fontSize) {
    switch (controlType) {
      case 'BPM':
        return _buildBPMControl(sequencer, height, padding, fontSize);
      case 'MASTER':
        return _buildPlaceholderControl('MASTER', 'Master volume and effects', height, padding, fontSize);
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

  Widget _buildBPMControl(PlaybackState sequencer, double height, double padding, double fontSize) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: padding * 0.5, 
        vertical: padding * 0.3
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

  Widget _buildVolumeControl(TableState tableState, SampleBankState sampleBankState, EditState editState, int index, double height, double padding, double fontSize) {
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
        final sectionStart = tableState.getSectionStartStep(tableState.uiSelectedSection);
        final layerStart = tableState.getLayerStartCol(tableState.uiSelectedLayer);
        final step = sectionStart + row;
        final colAbs = layerStart + col;
        final cellPtr = tableState.getCellPointer(step, colAbs);
        final cellData = CellData.fromPointer(cellPtr);
        final int? cellSample = cellData.isNotEmpty ? cellData.sampleSlot : null;
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
      padding: EdgeInsets.symmetric(horizontal: padding * 0.3, vertical: padding * 0.05),
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
                    _sampleVolumeDebounceTimer = Timer(const Duration(milliseconds: 200), () {
                      sampleBankState.setSampleSettings(index, volume: value);
                    });
                  },
                  height: height,
                  sliderOverlay: context.read<SliderOverlayState>(),
                  contextLabel: 'Sample ${sampleBankState.getSlotLetter(index)}',
                ),
              )
            : _buildCellVolumeSlider(tableState, index, height),
      ),
    );
  }

  Widget _buildPitchControl(TableState tableState, SampleBankState sampleBankState, EditState editState, int index, double height, double padding, double fontSize) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: padding * 0.3, vertical: padding * 0.05),
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
                builder: (context, pitch, _) => ValueListenableBuilder<bool>(
                  valueListenable: sampleBankState.getSampleProcessingNotifier(index),
                  builder: (context, isProcessing, __) {
                    // Provide processing source to overlay instead of mutating overlay state
                    final overlay = context.read<SliderOverlayState>();
                    overlay.setProcessingSource(sampleBankState.getSampleProcessingNotifier(index));
                    return GenericSlider(
                      value: PitchConversion.pitchRatioToUiValue(pitch),
                      min: 0.0,
                      max: 1.0,
                      divisions: 24,
                      type: SliderType.pitch,
                      onChanged: (value) {
                        // Debounce sample pitch commit
                        _samplePitchDebounceTimer?.cancel();
                        _samplePitchDebounceTimer = Timer(const Duration(milliseconds: 250), () {
                          final ratio = PitchConversion.uiValueToPitchRatio(value);
                          sampleBankState.setSampleSettings(index, pitch: ratio);
                        });
                      },
                      height: height,
                      sliderOverlay: overlay,
                      processingSource: sampleBankState.getSampleProcessingNotifier(index),
                      contextLabel: 'Sample ${sampleBankState.getSlotLetter(index)}',
                    );
                  },
                ),
              )
            : _buildCellPitchSlider(tableState, index, height),
      ),
    );
  }

  Widget _buildPlaceholderControl(String title, String description, double height, double padding, double fontSize) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: padding * 0.5, 
        vertical: padding * 0.3
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
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              style: TextStyle(
                color: AppColors.sequencerAccent,
                fontSize: fontSize * 1.8,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: height * 0.05),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.sequencerLightText,
                fontSize: fontSize * 1.1,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
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

  Widget _buildSettingsButton(String label, bool isSelected, double height, double fontSize, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
      ),
    );
  }

  Widget _buildPreviewButton(double height, TableState tableState, SampleBankState sampleBankState, EditState editState, int? currentIndex) {
    final isEnabled = () {
      if (widget.type == SettingsType.sample) {
        final idx = sampleBankState.activeSlot;
        return sampleBankState.isSlotLoaded(idx);
      } else if (widget.type == SettingsType.cell) {
        final sel = _resolveSelectedCell(editState);
        if (sel == null) return false;
        final visibleCols = tableState.getVisibleCols().length;
        final row = sel ~/ visibleCols;
        final col = sel % visibleCols;
        final step = tableState.getSectionStartStep(tableState.uiSelectedSection) + row;
        final colAbs = tableState.getLayerStartCol(tableState.uiSelectedLayer) + col;
        final cell = CellData.fromPointer(tableState.getCellPointer(step, colAbs));
        return cell.isNotEmpty && cell.sampleSlot >= 0;
      }
      return false;
    }();

    return GestureDetector(
      onTap: !isEnabled ? null : () => _triggerPreview(tableState, sampleBankState, editState),
      child: Opacity(
        opacity: isEnabled ? 1.0 : 0.4,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: AppColors.sequencerSurfaceRaised,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: AppColors.sequencerBorder, width: 0.5),
            boxShadow: const [
              BoxShadow(color: AppColors.sequencerShadow, blurRadius: 1, offset: Offset(0, 0.5)),
            ],
          ),
          child: const Center(
            child: Icon(
              Icons.volume_up,
              color: AppColors.sequencerText,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }

  void _triggerPreview(TableState tableState, SampleBankState sampleBankState, EditState editState) {
    final bindings = PlaybackBindings();
    if (widget.type == SettingsType.sample) {
      final idx = sampleBankState.activeSlot;
      if (!sampleBankState.isSlotLoaded(idx)) return;
      final vol = sampleBankState.getSampleVolumeNotifier(idx).value;
      final pitch = sampleBankState.getSamplePitchNotifier(idx).value;
      bindings.previewSlot(idx, pitch, vol);
      return;
    }
    // Cell preview
    final sel = _resolveSelectedCell(editState);
    if (sel == null) return;
    final visibleCols = tableState.getVisibleCols().length;
    final row = sel ~/ visibleCols;
    final col = sel % visibleCols;
    final step = tableState.getSectionStartStep(tableState.uiSelectedSection) + row;
    final colAbs = tableState.getLayerStartCol(tableState.uiSelectedLayer) + col;
    final cell = CellData.fromPointer(tableState.getCellPointer(step, colAbs));
    if (!cell.isNotEmpty || cell.sampleSlot < 0) return;
    // Resolve effective settings
    double effVol = cell.volume;
    if (effVol < 0.0) {
      final sd = sampleBankState.getSampleData(cell.sampleSlot);
      effVol = (sd.volume >= 0.0 && sd.volume <= 1.0) ? sd.volume : 1.0;
    }
    double effPitch = cell.pitch;
    if (effPitch < 0.0) {
      final sd = sampleBankState.getSampleData(cell.sampleSlot);
      effPitch = (sd.pitch > 0.0) ? sd.pitch : 1.0;
    }
    bindings.previewCell(step, colAbs, effPitch, effVol);
  }

  // Helpers
  static int? _resolveSelectedCell(EditState editState) {
    final selected = editState.selectedCells;
    if (selected.isEmpty) return null;
    return selected.first;
  }

  _HasDataAndIndex _resolveHasDataAndIndex(SettingsType type, TableState tableState, SampleBankState sampleBankState, EditState editState) {
    if (type == SettingsType.sample) {
      final idx = sampleBankState.activeSlot;
      final has = sampleBankState.isSlotLoaded(idx) || sampleBankState.getSlotName(idx) != null;
      return _HasDataAndIndex(hasData: has, index: idx);
    } else if (type == SettingsType.cell) {
      final selectedCell = _resolveSelectedCell(editState);
      if (selectedCell == null) return const _HasDataAndIndex(hasData: false, index: null);
      final visibleCols = tableState.getVisibleCols().length;
      final row = selectedCell ~/ visibleCols;
      final col = selectedCell % visibleCols;
      final step = tableState.getSectionStartStep(tableState.uiSelectedSection) + row;
      final colAbs = tableState.getLayerStartCol(tableState.uiSelectedLayer) + col;
      final cellPtr = tableState.getCellPointer(step, colAbs);
      final cellData = CellData.fromPointer(cellPtr);
      return _HasDataAndIndex(hasData: cellData.isNotEmpty, index: selectedCell);
    }
    return const _HasDataAndIndex(hasData: true, index: 0);
  }

  // Delete action moved to Edit Buttons; keep stub removed.

  Widget _buildCellVolumeSlider(TableState tableState, int selectedCellIndex, double height) {
    final visibleCols = tableState.getVisibleCols().length;
    final row = selectedCellIndex ~/ visibleCols;
    final col = selectedCellIndex % visibleCols;
    final step = tableState.getSectionStartStep(tableState.uiSelectedSection) + row;
    final colAbs = tableState.getLayerStartCol(tableState.uiSelectedLayer) + col;
    final cellNotifier = tableState.getCellNotifier(step, colAbs);
    return ValueListenableBuilder<CellData>(
      valueListenable: cellNotifier,
      builder: (context, cell, _) {
        final sampleBank = context.read<SampleBankState>();
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
            if (cell.isNotEmpty && cell.sampleSlot != -1) {
              _cellVolumeDebounceTimer?.cancel();
              _cellVolumeDebounceTimer = Timer(const Duration(milliseconds: 150), () {
                tableState.setCellSettings(step, colAbs, volume: value);
              });
            }
          },
          height: height,
          sliderOverlay: context.read<SliderOverlayState>(),
          contextLabel: 'Cell ${row + 1}:${col + 1}',
        );
      },
    );
  }

  Widget _buildCellPitchSlider(TableState tableState, int selectedCellIndex, double height) {
    final visibleCols = tableState.getVisibleCols().length;
    final row = selectedCellIndex ~/ visibleCols;
    final col = selectedCellIndex % visibleCols;
    final step = tableState.getSectionStartStep(tableState.uiSelectedSection) + row;
    final colAbs = tableState.getLayerStartCol(tableState.uiSelectedLayer) + col;
    final cellNotifier = tableState.getCellNotifier(step, colAbs);
    return ValueListenableBuilder<CellData>(
      valueListenable: cellNotifier,
      builder: (context, cell, _) {
        final sampleBank = context.read<SampleBankState>();
        double defaultPitch = 1.0;
        if (cell.sampleSlot >= 0) {
          final sd = sampleBank.getSampleData(cell.sampleSlot);
          defaultPitch = (sd.pitch > 0.0) ? sd.pitch : 1.0;
        }
        final effectiveRatio = (cell.pitch < 0.0) ? defaultPitch : cell.pitch;
        final uiPitch = PitchConversion.pitchRatioToUiValue(effectiveRatio);
        final overlay = context.read<SliderOverlayState>();
        final sampleSlot = cell.sampleSlot;
        if (sampleSlot >= 0) {
          return ValueListenableBuilder<bool>(
            valueListenable: sampleBank.getSampleProcessingNotifier(sampleSlot),
            builder: (context, isProcessing, ___) {
              // Provide processing source to overlay during interaction
              overlay.setProcessingSource(sampleBank.getSampleProcessingNotifier(sampleSlot));
              return GenericSlider(
                value: uiPitch,
                min: 0.0,
                max: 1.0,
                divisions: 24,
                type: SliderType.pitch,
                onChanged: (value) {
                  if (cell.isNotEmpty && cell.sampleSlot != -1) {
                    // Debounce cell pitch commit
                    _cellPitchDebounceTimer?.cancel();
                    _cellPitchDebounceTimer = Timer(const Duration(milliseconds: 250), () {
                      final ratio = PitchConversion.uiValueToPitchRatio(value);
                      tableState.setCellSettings(step, colAbs, pitch: ratio);
                    });
                  }
                },
                height: height,
                sliderOverlay: overlay,
                processingSource: sampleBank.getSampleProcessingNotifier(sampleSlot),
                contextLabel: 'Cell ${row + 1}:${col + 1}',
              );
            },
          );
        } else {
          // No sample → no processing
          // No sample → ensure processing source is null
          overlay.setProcessingSource(null);
          return GenericSlider(
            value: uiPitch,
            min: 0.0,
            max: 1.0,
            divisions: 24,
            type: SliderType.pitch,
            onChanged: (_) {},
            height: height,
            sliderOverlay: overlay,
            processingSource: null,
            contextLabel: 'Cell ${row + 1}:${col + 1}',
          );
        }
      },
    );
  }

  // (watch helpers removed in favor of direct ValueListenableBuilder wiring)
} 

class _HasDataAndIndex {
  final bool hasData;
  final int? index;
  const _HasDataAndIndex({required this.hasData, required this.index});
}