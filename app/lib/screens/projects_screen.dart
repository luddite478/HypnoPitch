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
import '../widgets/tutorial_pulse_widget.dart';
import '../ffi/table_bindings.dart';
import '../ffi/playback_bindings.dart';
import '../ffi/sample_bank_bindings.dart';
import '../state/sequencer/table.dart';
import '../state/app_state.dart';
import '../services/cache/working_state_cache_service.dart';
import '../services/local_checkpoint_service.dart';
import 'projects_settings_screen.dart';

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
  final ValueNotifier<int> _timestampTick =
      ValueNotifier<int>(0); // Tick counter for timestamp updates

  // Cache snapshot Futures to prevent recreation on rebuilds (eliminates flicker)
  final Map<String, Future<Map<String, dynamic>?>> _snapshotFutureCache = {};

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
  static const double _tileSpacing = 12.0; // Vertical gap between tiles
  static const double _listPadding = 16.0; // Padding around list

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
  static const double _tileBorderRadius =
      1.0; // Rounded corners to match sequencer
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
  static const double _fabIconSize = 50.0;
  static const double _fabSize = 56.0;
  static const double _fabBottomOffset = 30.0;
  static const double _fabRightOffset = 30.0;

  // FAB border & shadow
  static const Color _fabBorderColor = Color.fromARGB(180, 140, 140, 140);
  static const double _fabBorderWidth = 1.5;
  static const List<BoxShadow> _fabBoxShadows = [
    BoxShadow(
      color: Color.fromARGB(140, 0, 0, 0),
      blurRadius: 14,
      offset: Offset(0, 5),
      spreadRadius: 2,
    ),
    BoxShadow(
      color: Color.fromARGB(60, 0, 0, 0),
      blurRadius: 4,
      offset: Offset(0, 1),
    ),
  ];

  // Helper method to get font family based on font family string
  static TextStyle _getFontStyle(
    String fontFamily, {
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
            separatorBuilder: (context, index) =>
                SizedBox(height: _tileSpacing),
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

  Future<void> _openProjectsSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ProjectsSettingsScreen(),
      ),
    );
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
                SimplifiedHeaderWidget(
                  onLogoTap: _openProjectsSettings,
                ),

                Consumer<PatternsState>(
                  builder: (context, patternsState, _) {
                    // Show loading only on first load
                    if (patternsState.isLoading && !patternsState.hasLoaded) {
                      return Expanded(
                        child: Center(
                          child: CircularProgressIndicator(
                              color: AppColors.sequencerAccent),
                        ),
                      );
                    }

                    return Expanded(
                      child: _error != null
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.error_outline,
                                      color: AppColors.sequencerLightText,
                                      size: 48),
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
                                      backgroundColor:
                                          AppColors.sequencerAccent,
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
                  child: CircularProgressIndicator(
                      color: AppColors.sequencerAccent),
                ),
              ),
            ),
          // Floating action button - Create new pattern
          Positioned(
            right: _fabRightOffset,
            bottom: _fabBottomOffset,
            child: TutorialPulseWidget(
              enabled: appState.showProjectsCreatePatternFabHighlight,
              borderRadius: BorderRadius.circular(_fabCornerRadius),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(_fabCornerRadius),
                  border: Border.all(
                    color: _fabBorderColor,
                    width: _fabBorderWidth,
                  ),
                  boxShadow: _fabBoxShadows,
                ),
                child: Material(
                color: _fabBackgroundColor,
                elevation: 0,
                borderRadius: BorderRadius.circular(_fabCornerRadius),
                child: InkWell(
                  onTap: () async {
                    if (_isOpeningProject) return;
                    if (mounted) {
                      setState(() {
                        _isOpeningProject = true;
                      });
                    }
                    final appState = context.read<AppState>();
                    final autoStartedTutorial =
                        appState.consumeAutoStartTutorialOnProjectCreate();
                    if (!autoStartedTutorial) {
                      appState.dismissProjectsCreatePatternFabHint();
                    }
                    try {
                      // Stop any playing audio
                      context.read<AudioPlayerState>().stop();

                      // Create a new pattern
                      final patternsState = context.read<PatternsState>();
                      final newPattern = await patternsState
                          .createPattern(PatternNameGenerator.generate());

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
                        context
                            .read<SampleBankState>()
                            .assignRandomProjectColors();
                        // Reset all layer modes to sequence (fresh start)
                        context.read<TableState>().resetAllLayerModes();
                        // Reset to layer 0
                        context.read<TableState>().setUiSelectedLayer(0);
                      } catch (e) {
                        debugPrint('❌ Failed to init native subsystems: $e');
                      }

                      // Navigate to sequencer
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const PatternScreen(),
                        ),
                      );

                      // When returning from sequencer, clear cache and reload to show updated working state
                      _snapshotFutureCache.clear();
                      await _loadProjects();
                    } finally {
                      if (mounted) {
                        setState(() {
                          _isOpeningProject = false;
                        });
                      }
                    }
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
          ),
        ),
          if (appState.activeTutorialStep ==
              TutorialStep.sequencerProjectsLibraryHint)
            _buildLibraryFolderCoachMark(appState),
        ],
      ),
    );
  }

  Widget _buildLibraryFolderCoachMark(AppState appState) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = Size(constraints.maxWidth, constraints.maxHeight);
          final iconRect = _resolveTutorialRect(
            appState.projectsLibraryFolderTutorialKey,
            context,
          );
          if (iconRect == null) {
            return const SizedBox.shrink();
          }

          const horizontalInset = 12.0;
          final cardWidth =
              (viewport.width * 0.56).clamp(220.0, 320.0).toDouble();
          final desiredLeft = iconRect.center.dx - cardWidth + 28;
          final maxLeft = max(
            horizontalInset,
            viewport.width - cardWidth - horizontalInset,
          );
          final cardLeft =
              desiredLeft.clamp(horizontalInset, maxLeft).toDouble();
          final minTop = MediaQuery.paddingOf(context).top + 6;
          final desiredTop = iconRect.bottom + 10;
          final maxTop = max(minTop, viewport.height - 130);
          final cardTop = desiredTop.clamp(minTop, maxTop).toDouble();

          final arrowStart = Offset(cardLeft + cardWidth - 24, cardTop + 10);
          final arrowEnd = _resolveArrowTarget(
            from: arrowStart,
            targetRect: iconRect,
            edgePadding: 4,
          );

          return Stack(
            children: [
              IgnorePointer(
                child: CustomPaint(
                  size: viewport,
                  painter: _ProjectsTutorialArrowPainter(
                    start: arrowStart,
                    end: arrowEnd,
                    color: AppColors.tutorialArrowColor,
                  ),
                ),
              ),
              Positioned(
                left: cardLeft,
                top: cardTop,
                width: cardWidth,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.tutorialTextOverlayColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppColors.sequencerBorder, width: 0.8),
                    ),
                    child: Text(
                      'Navigate to library now.',
                      style: TextStyle(
                        color: AppColors.sequencerText,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
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

  /// [overlayContext] must be a descendant of the same overlay [Stack] so
  /// bounds match [CustomPaint] / [Positioned] (screen-global rects misalign).
  Rect? _resolveTutorialRect(GlobalKey key, BuildContext overlayContext) {
    final targetContext = key.currentContext;
    if (targetContext == null) return null;
    final renderObject = targetContext.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    final overlay = overlayContext.findRenderObject();
    if (overlay is! RenderBox) return null;
    final topLeft = renderObject.localToGlobal(Offset.zero, ancestor: overlay);
    return topLeft & renderObject.size;
  }

  Offset _resolveArrowTarget({
    required Offset from,
    required Rect targetRect,
    required double edgePadding,
  }) {
    final center = targetRect.center;
    final towardsText = from - center;
    if (towardsText.distanceSquared < 0.0001) return center;

    final halfW = targetRect.width / 2;
    final halfH = targetRect.height / 2;
    final scaleX = towardsText.dx.abs() < 0.0001
        ? double.infinity
        : halfW / towardsText.dx.abs();
    final scaleY = towardsText.dy.abs() < 0.0001
        ? double.infinity
        : halfH / towardsText.dy.abs();
    final scale = min(scaleX, scaleY);
    final edgePoint = Offset(
      center.dx + towardsText.dx * scale,
      center.dy + towardsText.dy * scale,
    );
    final toCenter = center - edgePoint;
    final len = toCenter.distance;
    if (len < 0.0001) return edgePoint;
    final inset = edgePadding.clamp(0.0, 10.0);
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
                          bottomLeft: _showFooter
                              ? Radius.zero
                              : Radius.circular(_tileBorderRadius),
                          bottomRight: _showFooter
                              ? Radius.zero
                              : Radius.circular(_tileBorderRadius),
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
                if (_showFooter) _buildFooter(pattern),
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
    final footerColor =
        _footerBackgroundColor.withOpacity(_footerBackgroundOpacity);

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
    final userSlots = SampleBankState.previewSlot;

    try {
      final source = snapshotData['source'] as Map<String, dynamic>?;
      if (source == null) {
        return List.generate(userSlots, (i) => AppColors.sequencerCellEmpty);
      }

      final sampleBankData = source['sample_bank'] as Map<String, dynamic>?;
      if (sampleBankData == null) {
        return List.generate(userSlots, (i) => AppColors.sequencerCellEmpty);
      }

      final samples = sampleBankData['samples'] as List<dynamic>?;
      if (samples == null) {
        return List.generate(userSlots, (i) => AppColors.sequencerCellEmpty);
      }

      // Process user slots only (preview slot is excluded from card colors).
      final slotsToProcess = samples.length.clamp(0, userSlots);

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
      while (colors.length < userSlots) {
        colors.add(AppColors.sequencerCellEmpty);
      }
    } catch (e) {
      debugPrint('❌ [PROJECTS] Error parsing sample bank colors: $e');
      return List.generate(userSlots, (i) => AppColors.sequencerCellEmpty);
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
        final workingState =
            await WorkingStateCacheService.loadWorkingState(patternId);
        if (workingState != null) {
          debugPrint(
              '📸 [PROJECTS] Loaded working state for pattern preview: $patternId');
          return workingState;
        }

        final checkpoints =
            await LocalCheckpointService.loadCheckpoints(patternId);
        if (checkpoints.isNotEmpty) {
          debugPrint(
              '📸 [PROJECTS] Using latest checkpoint for pattern preview: $patternId');
          return checkpoints.first.snapshot;
        }

        debugPrint(
            '📸 [PROJECTS] No working state or checkpoint; empty preview for: $patternId');
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
          'max_slots': SampleBankState.maxSampleSlots,
          'samples': List.generate(
              SampleBankState.maxSampleSlots,
              (i) => {
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
      context.read<TableState>().setUiSelectedSection(0);

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
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const PatternScreen(),
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
      final rrect =
          RRect.fromRectAndRadius(rect, Radius.circular(cornerRadius));
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

class _ProjectsTutorialArrowPainter extends CustomPainter {
  final Offset start;
  final Offset end;
  final Color color;

  _ProjectsTutorialArrowPainter({
    required this.start,
    required this.end,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(start, end, linePaint);

    final direction = (end - start);
    final angle = direction.direction;
    const arrowLength = 10.0;
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
  bool shouldRepaint(covariant _ProjectsTutorialArrowPainter oldDelegate) {
    return oldDelegate.start != start ||
        oldDelegate.end != end ||
        oldDelegate.color != color;
  }
}
