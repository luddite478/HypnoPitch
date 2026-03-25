import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../state/patterns_state.dart';
import '../state/audio_player_state.dart';
import '../state/sequencer/sample_bank.dart';
import '../models/pattern.dart';

import '../utils/app_colors.dart';
import '../utils/pattern_name_generator.dart';
import 'sequencer_screen.dart';
import '../widgets/simplified_header_widget.dart';
import '../widgets/pattern_preview_widget.dart';
import '../ffi/table_bindings.dart';
import '../ffi/playback_bindings.dart';
import '../ffi/sample_bank_bindings.dart';
import '../state/sequencer/table.dart';
import '../services/cache/working_state_cache_service.dart';
import '../state/app_state.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({Key? key}) : super(key: key);
  
  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  String? _error;
  bool _isOpeningProject = false;
  final Set<String> _deletingPatternIds = {}; // Prevent double deletion
  Timer? _timestampUpdateTimer; // Periodic timer to update relative timestamps
  final ValueNotifier<int> _timestampTick = ValueNotifier<int>(0); // Tick counter for timestamp updates
  
  // Cache snapshot Futures to prevent recreation on rebuilds (eliminates flicker)
  final Map<String, Future<Map<String, dynamic>?>> _snapshotFutureCache = {};
  final GlobalKey _fabKey = GlobalKey();

  // ============================================================================
  // LAYOUT CONTROL VARIABLES - CENTRALIZED CONFIGURATION
  // ============================================================================
  // All adjustable layout parameters in one place. Change these to customize appearance.
  // Using 2-column grid layout similar to Google Docs
  
  // ----------------------------------------------------------------------------
  // LIST LAYOUT CONTROL
  // ----------------------------------------------------------------------------
  // Single column layout with horizontal tiles
  
  // Spacing between tiles
  static const double _tileSpacing = 12.0;  // Vertical gap between tiles
  static const double _listPadding = 16.0;  // Padding around list
  
  // ----------------------------------------------------------------------------
  // TILE DIMENSIONS CONTROL
  // ----------------------------------------------------------------------------
  // Fixed tile height (in logical pixels)
  // Recommended: 120-180px for comfortable viewing
  static const double _tileHeight = 180.0;
  
  // ----------------------------------------------------------------------------
  // TILE BACKGROUND COLOR
  // ----------------------------------------------------------------------------
  // Controls the background color of the entire project tile
  static const Color _tileBackgroundColor = AppColors.sequencerSurfaceRaised;
  static const double _tileBorderRadius = 1.0;  // Rounded corners to match sequencer
  static const double _tileElevation = 2.0;
  
  // ----------------------------------------------------------------------------
  // OVERLAY CONTROLS (Metadata only - participants removed)
  // ----------------------------------------------------------------------------
  // Background overlay color (color of the overlay backgrounds)
  static const Color _overlayBackgroundColor = AppColors.sequencerSurfaceBase;
  
  // Background overlay opacity (0.0 = fully transparent, 1.0 = fully opaque)
  static const double _overlayBackgroundOpacity = 0.95;
  
  // Text color (color of the text on overlays)
  static const Color _overlayTextColor = AppColors.sequencerText;
  
  // Text opacity (0.0 = fully transparent, 1.0 = fully opaque)
  static const double _overlayTextOpacity = 1.0;
  
  // Text font weight (w100-w900, or use FontWeight.normal, FontWeight.bold, etc.)
  static const FontWeight _overlayTextFontWeight = FontWeight.w700;
  
  // Font family for overlay text (use GoogleFonts method name)
  static const String _overlayFontFamily = 'CrimsonPro';
  
  // Corner radius for overlays (0.0 = squared corners)
  static const double _overlayCornerRadius = 4.0;
  
  // Extension space around text (how much the background extends beyond text)
  static const double _overlayHorizontalExtension = 14.0;
  static const double _overlayVerticalExtension = 2.0;
  
  // Metadata overlay (top left) - shows LEN, STP, HST
  static const double _metadataOverlayHorizontalOffset = 5.0;
  static const double _metadataOverlayVerticalOffset = 5.0;
  static const double _metadataOverlayLabelFontSize = 12.0;
  static const double _metadataOverlayNumberFontSize = 15.0;
  
  // Footer section (bottom of tile - shows created/modified dates)
  static const bool _showFooter = true;
  static const double _footerHeight = 20.0;
  static const double _footerHorizontalPadding = 12.0;
  static const double _footerLabelFontSize = 10.0;
  static const double _footerDateFontSize = 10.0;
  static const Color _footerBackgroundColor = AppColors.sequencerSurfaceBase;
  static const double _footerBackgroundOpacity = 0.8;
  static const Color _footerTextColor = AppColors.sequencerLightText;
  static const double _footerTextOpacity = 1.0;
  static const double _footerLabelOpacity = 0.7;
  
  // Font family for footer text
  static const String _footerFontFamily = 'sourceSans3';
  
  // Gradient edge fade controls
  static const double _overlayHorizontalFadeWidth = 0.01;
  static const double _overlayVerticalFadeHeight = 0.5;
  
  // ----------------------------------------------------------------------------
  // CREATE NEW PATTERN BUTTON (FAB) CONTROLS
  // ----------------------------------------------------------------------------
  static const double _fabCornerRadius = 11.0;
  static const Color _fabBackgroundColor = Color.fromARGB(255, 66, 66, 66);
  static Color _fabIconColor = Color.fromARGB(255, 185, 185, 185);
  static const double _fabElevation = 4.0;
  static const double _fabIconSize = 50.0;
  static const double _fabSize = 56.0;
  static const double _fabBottomOffset = 30.0;
  static const double _fabRightOffset = 30.0;

  // Helper method to get font family based on font family string
  static TextStyle _getFontStyle(String fontFamily, {
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    double? letterSpacing,
    double? height,
  }) {
    switch (fontFamily.toLowerCase()) {
      case 'sourcesans3':
        return TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
          letterSpacing: letterSpacing,
          height: height,
        );
      case 'roboto':
        return GoogleFonts.roboto(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
          letterSpacing: letterSpacing,
          height: height,
        );
      case 'inter':
        return GoogleFonts.inter(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
          letterSpacing: letterSpacing,
          height: height,
        );
      case 'montserrat':
        return GoogleFonts.montserrat(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
          letterSpacing: letterSpacing,
          height: height,
        );
      case 'poppins':
        return GoogleFonts.poppins(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
          letterSpacing: letterSpacing,
          height: height,
        );
      case 'opensans':
        return GoogleFonts.openSans(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
          letterSpacing: letterSpacing,
          height: height,
        );
      default:
        return TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
          letterSpacing: letterSpacing,
          height: height,
        );
    }
  }

  /// Build projects list
  Widget _buildProjectsList(BuildContext context, PatternsState patternsState) {
    // Always show most recently modified patterns first
    final patterns = [...patternsState.patterns]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    
    if (patterns.isEmpty) {
      return const SizedBox.shrink(); // Show nothing when no patterns
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            'PATTERNS',
            style: TextStyle(
              color: AppColors.sequencerText,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
            ),
          ),
        ),
        
        // Patterns list (single column)
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.all(_listPadding),
            itemCount: patterns.length,
            separatorBuilder: (context, index) => SizedBox(height: _tileSpacing),
            itemBuilder: (context, index) {
              return _buildProjectCard(patterns[index]);
            },
          ),
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    // Configure status bar
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
    );
    
    // Start periodic timer to update relative timestamps
    _timestampUpdateTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        _timestampTick.value++;
      }
    });
    
    // Stop any playing audio when ProjectsScreen becomes visible
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final audioPlayer = context.read<AudioPlayerState>();
        audioPlayer.stop();
        _loadProjects();
      }
    });
  }

  @override
  void dispose() {
    _timestampUpdateTimer?.cancel();
    _timestampTick.dispose();
    
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
    );
    super.dispose();
  }

  Future<void> _loadProjects() async {
    try {
      final patternsState = Provider.of<PatternsState>(context, listen: false);
      
      // Clear snapshot cache to force reload of working states
      _snapshotFutureCache.clear();
      
      // Load patterns
      await patternsState.loadPatterns();
      
      setState(() {
        _error = null;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load patterns: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return Scaffold(
      backgroundColor: AppColors.sequencerPageBackground,
      body: Stack(
        children: [
          SafeArea(
        child: Column(
          children: [
            // Simplified header with library icon
            const SimplifiedHeaderWidget(),
            
                Consumer<PatternsState>(
                  builder: (context, patternsState, _) {
                    // Show loading only on first load
                    if (patternsState.isLoading && !patternsState.hasLoaded) {
                  return Expanded(
                    child: Center(
                      child: CircularProgressIndicator(color: AppColors.sequencerAccent),
                    ),
                  );
                }
                
                return Expanded(
                      child: _error != null
                                      ? Center(
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.error_outline, color: AppColors.sequencerLightText, size: 48),
                                              const SizedBox(height: 12),
                                              Text(
                                                _error!, 
                                                style: TextStyle(
                                                  color: AppColors.sequencerText,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              const SizedBox(height: 12),
                                              ElevatedButton(
                                                onPressed: () {
                                                  _loadProjects();
                                                },
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: AppColors.sequencerAccent,
                                                ),
                                                child: Text(
                                                  'RETRY',
                                                  style: TextStyle(
                                                    color: AppColors.sequencerText,
                                                    fontWeight: FontWeight.bold,
                                                    letterSpacing: 1.0,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                          : _buildProjectsList(context, patternsState),
                );
              },
            ),
          ],
        ),
      ),
          if (_isOpeningProject)
            Positioned.fill(
              child: Container(
                color: AppColors.sequencerPageBackground.withOpacity(0.8),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.sequencerAccent),
                ),
              ),
            ),
          // Floating action button - Create new pattern
          Positioned(
            right: _fabRightOffset,
            bottom: _fabBottomOffset,
            child: Material(
              key: _fabKey,
              color: _fabBackgroundColor,
              elevation: _fabElevation,
              borderRadius: BorderRadius.circular(_fabCornerRadius),
              child: InkWell(
                onTap: () async {
                  // Stop any playing audio
                  context.read<AudioPlayerState>().stop();
                  
                  // Create a new pattern
                  final patternsState = context.read<PatternsState>();
                  final newPattern = await patternsState.createPattern(PatternNameGenerator.generate());
                  
                  if (newPattern == null) {
                    debugPrint('❌ Failed to create new pattern');
                    return;
                  }
                  
                  // Set as active pattern
                  await patternsState.setActivePattern(newPattern);
                  
                  // Initialize native subsystems
                  try {
                    TableBindings().tableInit();
                    PlaybackBindings().playbackInit();
                    SampleBankBindings().sampleBankInit();
                    // Assign random colors for new project
                    context.read<SampleBankState>().assignRandomProjectColors();
                    // Reset all layer modes to sequence (fresh start)
                    context.read<TableState>().resetAllLayerModes();
                    // Reset to layer 0
                    context.read<TableState>().setUiSelectedLayer(0);
                  } catch (e) {
                    debugPrint('❌ Failed to init native subsystems: $e');
                  }
                  
                  // Navigate to sequencer
                  appState.advanceTutorialFromProjectsPlus();
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const PatternScreen(),
                    ),
                  );
                  
                  // When returning from sequencer, clear cache and reload to show updated working state
                  _snapshotFutureCache.clear();
                  await _loadProjects();
                },
                borderRadius: BorderRadius.circular(_fabCornerRadius),
                child: Container(
                  width: _fabSize,
                  height: _fabSize,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.add,
                    size: _fabIconSize,
                    color: _fabIconColor,
                  ),
                ),
              ),
            ),
          ),
          if (appState.isInitialized && appState.showTutorialPromptThisSession)
            _buildQuickTutorialPrompt(appState),
          if (appState.activeTutorialStep == TutorialStep.projectsPlusButtonHint)
            _buildPlusButtonCoachMark(appState),
        ],
      ),
    );
  }

  Widget _buildQuickTutorialPrompt(AppState appState) {
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = (screenWidth * 0.82).clamp(240.0, 420.0).toDouble();

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: Container(
          alignment: Alignment.center,
          color: Colors.black.withOpacity(0.22),
          child: Material(
            color: AppColors.sequencerSurfaceRaised.withOpacity(0.98),
            elevation: 12,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: cardWidth,
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.sequencerBorder, width: 1),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: IconButton(
                      onPressed: appState.dismissTutorialPromptForSession,
                      icon: Icon(Icons.close, color: AppColors.sequencerLightText, size: 22),
                      tooltip: 'Dismiss',
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(height: 2),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: appState.startProjectsQuickTutorial,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.sequencerAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        'Run quick tutorial',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlusButtonCoachMark(AppState appState) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
          final fabRect = _resolveFabRect(viewportSize);
          final safeTop = MediaQuery.of(context).padding.top;
          final textWidth = (viewportSize.width * 0.62).clamp(200.0, 340.0).toDouble();

          double textLeft = (viewportSize.width - textWidth) / 2;
          textLeft = textLeft
              .clamp(16.0, viewportSize.width - textWidth - 16.0)
              .toDouble();

          double textTop = (viewportSize.height * 0.5) - 32;
          final minTextTop = safeTop + 24;
          final maxTextTop = viewportSize.height - 140;
          textTop = textTop.clamp(minTextTop, maxTextTop).toDouble();

          final textCenter = Offset(textLeft + textWidth / 2, textTop + 30);
          final arrowTarget = _resolveArrowTarget(
            from: textCenter,
            targetRect: fabRect,
            edgePadding: 4,
          );

          return Stack(
            children: [
              IgnorePointer(
                child: Container(
                  color: Colors.black.withOpacity(0.12),
                ),
              ),
              IgnorePointer(
                child: CustomPaint(
                  painter: _TutorialArrowPainter(
                    start: textCenter,
                    end: arrowTarget,
                    color: AppColors.sequencerAccent,
                  ),
                  size: viewportSize,
                ),
              ),
              Positioned(
                left: textLeft,
                top: textTop,
                width: textWidth,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.sequencerSurfaceBase.withOpacity(0.88),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.sequencerBorder, width: 0.8),
                    ),
                    child: Text(
                      'Tap + button to create new pattern',
                      style: TextStyle(
                        color: AppColors.sequencerText,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 72,
                right: 16,
                child: _buildTutorialControls(appState),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTutorialControls(AppState appState) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.sequencerSurfaceRaised.withOpacity(0.92),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.sequencerBorder, width: 0.8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        appState.tutorialStepLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        softWrap: true,
                        style: TextStyle(
                          color: AppColors.sequencerText,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${appState.tutorialStepDisplayIndex}/${AppState.tutorialTotalSteps}',
                      style: TextStyle(
                        color: AppColors.sequencerText,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 4),
                    ElevatedButton(
                      onPressed: appState.goBackTutorialManually,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.sequencerSurfaceBase,
                        foregroundColor: AppColors.sequencerText,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                      child: Text(
                        'Back',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Rect _resolveFabRect(Size viewportSize) {
    final context = _fabKey.currentContext;
    if (context != null) {
      final box = context.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        final topLeft = box.localToGlobal(Offset.zero);
        return topLeft & box.size;
      }
    }

    return Rect.fromLTWH(
      viewportSize.width - _fabRightOffset - _fabSize,
      viewportSize.height - _fabBottomOffset - _fabSize,
      _fabSize,
      _fabSize,
    );
  }

  Offset _resolveArrowTarget({
    required Offset from,
    required Rect targetRect,
    required double edgePadding,
  }) {
    final center = targetRect.center;
    final towardsText = from - center;

    if (towardsText.distanceSquared < 0.0001) {
      return center;
    }

    final halfW = targetRect.width / 2;
    final halfH = targetRect.height / 2;
    final scaleX =
        towardsText.dx.abs() < 0.0001 ? double.infinity : halfW / towardsText.dx.abs();
    final scaleY =
        towardsText.dy.abs() < 0.0001 ? double.infinity : halfH / towardsText.dy.abs();
    final scale = scaleX < scaleY ? scaleX : scaleY;

    final edgePoint = Offset(
      center.dx + towardsText.dx * scale,
      center.dy + towardsText.dy * scale,
    );

    final toCenter = center - edgePoint;
    final len = toCenter.distance;
    if (len < 0.0001) return edgePoint;

    final inset = edgePadding.clamp(0.0, 12.0).toDouble();
    return Offset(
      edgePoint.dx + (toCenter.dx / len) * inset,
      edgePoint.dy + (toCenter.dy / len) * inset,
    );
  }

  Widget _buildProjectCard(Pattern pattern) {
    // Wrap in RepaintBoundary to isolate repaints
    return RepaintBoundary(
      child: Container(
        key: ValueKey('${pattern.id}_${pattern.checkpointIds.length}'),
          height: _tileHeight,
          decoration: BoxDecoration(
          color: _tileBackgroundColor,
            borderRadius: BorderRadius.circular(_tileBorderRadius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: _tileElevation * 2,
                offset: Offset(0, _tileElevation),
              ),
            ],
            border: Border.all(
              color: AppColors.sequencerBorder,
              width: 0.5,
            ),
          ),
          child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(_tileBorderRadius),
        child: InkWell(
            onTap: () => _openProject(pattern),
            onLongPress: () => _showDeleteDialog(pattern),
          borderRadius: BorderRadius.circular(_tileBorderRadius),
              child: Column(
                children: [
                  // Pattern preview with overlays
                  Expanded(
                    child: Stack(
                      children: [
                        // Pattern preview fills entire tile
                        ClipRRect(
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(_tileBorderRadius),
                            topRight: Radius.circular(_tileBorderRadius),
                            bottomLeft: _showFooter ? Radius.zero : Radius.circular(_tileBorderRadius),
                            bottomRight: _showFooter ? Radius.zero : Radius.circular(_tileBorderRadius),
                          ),
                          child: PatternPreviewWidget(
                          key: ValueKey('preview_${pattern.id}'),
                          project: pattern,
                            getProjectSnapshot: _getProjectSnapshot,
                            getSampleBankColors: _getSampleBankColors,
                            fadeOverlayColor: _tileBackgroundColor,
                            innerPadding: const EdgeInsets.all(6),
                          workingStateVersion: 0, // Not used in offline mode
                        ),
                      ),
                      
                      // Metadata overlay (top left) - shows LEN, STP, HST
                      _buildMetadataOverlay(pattern),
                      ],
                    ),
                  ),
                  
                  // Footer section (below pattern preview)
                  if (_showFooter)
                  _buildFooter(pattern),
                ],
              ),
            ),
        ),
      ),
    );
  }
  
  /// Builds metadata overlay for top left corner
  /// Shows STEPS (total steps) and LENGTH (sections)
  Widget _buildMetadataOverlay(Pattern pattern) {
    // Helper to calculate font size based on digit count
    double _getNumberFontSize(int number) {
      final digitCount = number.toString().length;
      if (digitCount <= 4) {
        return _metadataOverlayNumberFontSize;
      } else {
        return _metadataOverlayNumberFontSize * (4.0 / digitCount);
      }
    }
    
    // Helper to build a metric row with label on left and number on right
    Widget _buildMetricRow(String label, int value) {
      return Row(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: _getFontStyle(
              _overlayFontFamily,
              color: _overlayTextColor.withOpacity(_overlayTextOpacity * 0.7),
              fontSize: _metadataOverlayLabelFontSize,
              fontWeight: _overlayTextFontWeight,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: _metadataOverlayNumberFontSize * 2.2,
            child: Text(
              '$value',
              textAlign: TextAlign.right,
              style: _getFontStyle(
                _overlayFontFamily,
                color: _overlayTextColor.withOpacity(_overlayTextOpacity),
                fontSize: _getNumberFontSize(value),
                fontWeight: _overlayTextFontWeight,
              ),
            ),
          ),
        ],
      );
    }
    
    return FutureBuilder<Map<String, dynamic>?>(
      future: _getProjectSnapshot(pattern.id),
      builder: (context, snapshot) {
        int sectionsCount = 0; // LENGTH
        int totalSteps = 0; // STEPS
        
        if (snapshot.hasData && snapshot.data != null) {
          try {
            final source = snapshot.data!['source'] as Map<String, dynamic>?;
            final table = source?['table'] as Map<String, dynamic>?;
            final sections = table?['sections'] as List<dynamic>?;
            sectionsCount = sections?.length ?? 0;
            
            // Calculate total steps across all sections
            if (sections != null) {
              for (var section in sections) {
                if (section is Map<String, dynamic>) {
                  final numSteps = section['num_steps'] as int? ?? 0;
                  totalSteps += numSteps;
                }
              }
            }
          } catch (e) {
            sectionsCount = 0;
            totalSteps = 0;
          }
        }
        
        // Position at the corner of the pattern table
        const patternInnerPadding = 6.0;
        
        return Positioned(
          top: patternInnerPadding + _metadataOverlayVerticalOffset,
          right: patternInnerPadding + _metadataOverlayHorizontalOffset,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_overlayCornerRadius),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Background layer
                Positioned.fill(
                  child: _buildOverlayBackground(),
                ),
                // Text layer with padding
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: _overlayHorizontalExtension,
                    vertical: _overlayVerticalExtension,
                  ),
                  child: IntrinsicWidth(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildMetricRow('STEPS', totalSteps),
                        const SizedBox(height: 2),
                        _buildMetricRow('LENGTH', sectionsCount),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  
  /// Builds footer section showing created and modified dates
  Widget _buildFooter(Pattern pattern) {
    // Format absolute dates with slashes
    String formatDate(DateTime date) {
      return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
    }
    
    // Format relative time for recent dates (< 48 hours)
    String formatRelativeTime(DateTime date) {
      final now = DateTime.now();
      final difference = now.difference(date);
      
      // If more than 48 hours, show absolute date
      if (difference.inHours >= 48) {
        return formatDate(date);
      }
      
      // Less than 48 hours - show relative time
      if (difference.inSeconds < 5) {
        return 'just now';
      } else if (difference.inSeconds < 60) {
        return '${difference.inSeconds}s ago';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes}m ago';
      } else {
        return '${difference.inHours}h ago';
      }
    }
    
    final createdDate = formatDate(pattern.createdAt);
    final footerColor = _footerBackgroundColor.withOpacity(_footerBackgroundOpacity);
    
    return Container(
      height: _footerHeight,
      decoration: BoxDecoration(
        color: footerColor,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(_tileBorderRadius),
          bottomRight: Radius.circular(_tileBorderRadius),
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: _footerHorizontalPadding),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Created date (left)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'CREATED',
                style: _getFontStyle(
                  _footerFontFamily,
                  color: _footerTextColor.withOpacity(_footerLabelOpacity),
                  fontSize: _footerLabelFontSize,
                  fontWeight: _overlayTextFontWeight,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                createdDate,
                style: _getFontStyle(
                  _footerFontFamily,
                  color: _footerTextColor.withOpacity(_footerTextOpacity),
                  fontSize: _footerDateFontSize,
                  fontWeight: _overlayTextFontWeight,
                ),
              ),
            ],
          ),
          // Modified date (right)
          ValueListenableBuilder<int>(
            valueListenable: _timestampTick,
            builder: (context, tick, child) {
              final modifiedDateText = formatRelativeTime(pattern.updatedAt);
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'MODIFIED',
                    style: _getFontStyle(
                      _footerFontFamily,
                      color: _footerTextColor.withOpacity(_footerLabelOpacity),
                      fontSize: _footerLabelFontSize,
                      fontWeight: _overlayTextFontWeight,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                        modifiedDateText,
                        style: _getFontStyle(
                          _footerFontFamily,
                      color: _footerTextColor.withOpacity(_footerTextOpacity),
                          fontSize: _footerDateFontSize,
                          fontWeight: _overlayTextFontWeight,
                        ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
  
  /// Builds overlay background with gradient edges
  Widget _buildOverlayBackground() {
    return IgnorePointer(
      child: CustomPaint(
        painter: _OverlayGradientPainter(
          backgroundColor: _overlayBackgroundColor,
          opacity: _overlayBackgroundOpacity,
          horizontalFade: _overlayHorizontalFadeWidth,
          verticalFade: _overlayVerticalFadeHeight,
          cornerRadius: _overlayCornerRadius,
        ),
        child: Container(),
      ),
    );
  }
  
  /// Extracts sample bank colors from snapshot data
  List<Color> _getSampleBankColors(Map<String, dynamic> snapshotData) {
    final List<Color> colors = [];
    
    try {
      final source = snapshotData['source'] as Map<String, dynamic>?;
      if (source == null) {
        return List.generate(25, (i) => AppColors.sequencerCellEmpty);
      }
      
      final sampleBankData = source['sample_bank'] as Map<String, dynamic>?;
      if (sampleBankData == null) {
        return List.generate(25, (i) => AppColors.sequencerCellEmpty);
      }
      
      final samples = sampleBankData['samples'] as List<dynamic>?;
      if (samples == null) {
        return List.generate(25, (i) => AppColors.sequencerCellEmpty);
      }
      
      // Process first 25 slots (A-Y)
      final slotsToProcess = samples.length.clamp(0, 25);
      
      for (int i = 0; i < slotsToProcess; i++) {
        final sample = samples[i];
        if (sample is Map<String, dynamic>) {
          final hasColor = sample.containsKey('color');
          
          // Preview should stay colorful even if snapshot has inconsistent loaded flags.
          if (hasColor) {
            final rawColor = sample['color'];
            if (rawColor is String && rawColor.isNotEmpty) {
              try {
                colors.add(_hexToColor(rawColor));
                continue;
              } catch (_) {
                // Fall through to palette fallback.
              }
            }
          }

          // Fallback to deterministic palette by slot index.
          if (i < AppColors.sampleBankPalette.length) {
            colors.add(AppColors.sampleBankPalette[i]);
          } else {
            colors.add(AppColors.sequencerCellEmpty);
          }
        } else {
          colors.add(AppColors.sequencerCellEmpty);
        }
      }
      
      // Fill remaining slots
      while (colors.length < 25) {
        colors.add(AppColors.sequencerCellEmpty);
      }
    } catch (e) {
      debugPrint('❌ [PROJECTS] Error parsing sample bank colors: $e');
      return List.generate(25, (i) => AppColors.sequencerCellEmpty);
    }
    
    return colors;
  }
  
  /// Convert hex color string to Color object
  Color _hexToColor(String hex) {
    final buffer = StringBuffer();
    if (hex.startsWith('#')) {
      buffer.write(hex.substring(1));
    } else {
      buffer.write(hex);
    }
    return Color(int.parse(buffer.toString(), radix: 16) + 0xFF000000);
  }

  Future<Map<String, dynamic>?> _getProjectSnapshot(String patternId) {
    return _snapshotFutureCache.putIfAbsent(patternId, () async {
      try {
        // Try to load working state (auto-saved snapshot) first
        final workingState = await WorkingStateCacheService.loadWorkingState(patternId);
        if (workingState != null) {
          debugPrint('📸 [PROJECTS] Loaded working state for pattern preview: $patternId');
          return workingState;
        }
        
        // TODO: If no working state, try to load latest checkpoint
        // For now, return empty snapshot
        debugPrint('📸 [PROJECTS] No working state found, using empty snapshot for: $patternId');
          return _createEmptySnapshot();
        } catch (e) {
        debugPrint('❌ [PROJECTS] Error loading snapshot for $patternId: $e');
        return _createEmptySnapshot();
      }
    });
  }
  
  /// Creates an empty snapshot structure for patterns with no checkpoints
  Map<String, dynamic> _createEmptySnapshot() {
    return {
      'source': {
        'table': {
          'sections_count': 1,
          'sections': [
            {'start_step': 0, 'num_steps': 16}
          ],
          'layers': [
            [4, 4, 4, 4]
          ],
          'table_cells': List.generate(
            16,
            (step) => List.generate(
              16,
              (col) => {
                'sample_slot': -1,
                'settings': {'volume': -1.0, 'pitch': -1.0}
              },
            ),
          ),
        },
        'sample_bank': {
          'max_slots': 26,
          'samples': List.generate(26, (i) => {
            'loaded': false,
            'settings': {
              'volume': 1.0,
              'pitch': 1.0,
            },
          }),
        },
      },
    };
  }

  Future<void> _openProject(Pattern pattern) async {
    try {
      if (mounted) {
        setState(() {
          _isOpeningProject = true;
        });
      }

      // Set active pattern
      final patternsState = context.read<PatternsState>();
      await patternsState.setActivePattern(pattern);

      // Stop any playing audio
      context.read<AudioPlayerState>().stop();
      
      // Reset layer modes and selection (fresh start for each pattern)
      context.read<TableState>().resetAllLayerModes();
      context.read<TableState>().setUiSelectedLayer(0);

      // Keep a stable fallback snapshot in case working-state import is invalid.
      final checkpoints = patternsState.getCheckpoints(pattern.id);
      final fallbackSnapshot = checkpoints.isNotEmpty ? checkpoints.first.snapshot : null;
      
      // Initialize native systems
      try {
        TableBindings().tableInit();
        PlaybackBindings().playbackInit();
        SampleBankBindings().sampleBankInit();
      } catch (e) {
        debugPrint('❌ Failed to init native systems: $e');
      }

      // Navigate to sequencer
      if (mounted) {
        setState(() {
          _isOpeningProject = false;
        });
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PatternScreen(initialSnapshot: fallbackSnapshot),
          ),
        );
        
        // When returning from sequencer, clear cache and reload to show updated working state
        _snapshotFutureCache.clear();
        await _loadProjects();
      }
    } catch (e) {
      debugPrint('❌ Failed to open project: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningProject = false;
        });
      }
    }
  }

  void _showDeleteDialog(Pattern pattern) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.sequencerSurfaceRaised,
          title: Text(
            'Delete Pattern',
            style: TextStyle(
              color: AppColors.sequencerText,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            'Are you sure you want to delete this pattern? This will delete all checkpoints.',
            style: TextStyle(
              color: AppColors.sequencerLightText,
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: AppColors.sequencerLightText,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _deleteProject(pattern);
              },
              child: Text(
                'Delete',
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteProject(Pattern pattern) async {
    // Prevent double deletion
    if (_deletingPatternIds.contains(pattern.id)) {
      return;
    }
    
    final patternsState = context.read<PatternsState>();
    
    try {
      _deletingPatternIds.add(pattern.id);
      
      // Show loading indicator
      if (mounted) {
        setState(() {
          _isOpeningProject = true;
        });
      }

      // Delete pattern
      await patternsState.deletePattern(pattern.id);

      if (mounted) {
        setState(() {
          _isOpeningProject = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Failed to delete pattern: $e');
      
      if (mounted) {
        setState(() {
          _isOpeningProject = false;
        });
      }
    } finally {
      _deletingPatternIds.remove(pattern.id);
    }
  }
}

// ============================================================================
// OVERLAY GRADIENT PAINTER
// ============================================================================
class _OverlayGradientPainter extends CustomPainter {
  final Color backgroundColor;
  final double opacity;
  final double horizontalFade;
  final double verticalFade;
  final double cornerRadius;

  _OverlayGradientPainter({
    required this.backgroundColor,
    required this.opacity,
    required this.horizontalFade,
    required this.verticalFade,
    required this.cornerRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint();
    paint.shader = _createCombinedGradientShader(rect);
    
    if (cornerRadius > 0) {
      final rrect = RRect.fromRectAndRadius(rect, Radius.circular(cornerRadius));
      canvas.drawRRect(rrect, paint);
    } else {
      canvas.drawRect(rect, paint);
    }
  }
  
  Shader _createCombinedGradientShader(Rect rect) {
    if (horizontalFade <= 0 && verticalFade <= 0) {
      return LinearGradient(
        colors: [
          backgroundColor.withOpacity(opacity),
          backgroundColor.withOpacity(opacity),
        ],
      ).createShader(rect);
    }
    
    final stops = <double>[
      0.0,
      horizontalFade > 0 ? horizontalFade : 0.0,
      horizontalFade > 0 ? 1.0 - horizontalFade : 1.0,
      1.0,
    ];
    
    final colors = <Color>[
      backgroundColor.withOpacity(0.0),
      backgroundColor.withOpacity(opacity),
      backgroundColor.withOpacity(opacity),
      backgroundColor.withOpacity(0.0),
    ];
    
    return LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      stops: stops,
      colors: colors,
    ).createShader(rect);
  }

  @override
  bool shouldRepaint(_OverlayGradientPainter oldDelegate) {
    return oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.opacity != opacity ||
        oldDelegate.horizontalFade != horizontalFade ||
        oldDelegate.verticalFade != verticalFade ||
        oldDelegate.cornerRadius != cornerRadius;
  }
}

class _TutorialArrowPainter extends CustomPainter {
  final Offset start;
  final Offset end;
  final Color color;

  _TutorialArrowPainter({
    required this.start,
    required this.end,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..lineTo(end.dx, end.dy);

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, linePaint);

    final direction = (end - start);
    final angle = direction.direction;
    const arrowLength = 11.0;
    const arrowSpread = 0.6;

    final arrowPath = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(
        end.dx - arrowLength * cos(angle - arrowSpread),
        end.dy - arrowLength * sin(angle - arrowSpread),
      )
      ..moveTo(end.dx, end.dy)
      ..lineTo(
        end.dx - arrowLength * cos(angle + arrowSpread),
        end.dy - arrowLength * sin(angle + arrowSpread),
      );

    canvas.drawPath(arrowPath, linePaint);
  }

  @override
  bool shouldRepaint(covariant _TutorialArrowPainter oldDelegate) {
    return oldDelegate.start != start ||
        oldDelegate.end != end ||
        oldDelegate.color != color;
  }
}
