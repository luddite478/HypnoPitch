import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../state/threads_state.dart';
import '../state/audio_player_state.dart';
import '../state/user_state.dart';
import '../state/sequencer/sample_bank.dart';
import '../models/thread/thread.dart';
import '../models/thread/thread_user.dart';
import '../services/threads_api.dart';

import '../utils/app_colors.dart';
import '../utils/thread_name_generator.dart';
import 'sequencer_screen.dart';
import '../widgets/simplified_header_widget.dart';
import '../widgets/pattern_preview_widget.dart';
import '../ffi/table_bindings.dart';
import '../ffi/playback_bindings.dart';
import '../ffi/sample_bank_bindings.dart';
import '../widgets/buttons/action_button.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({Key? key}) : super(key: key);
  
  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  String? _error;
  bool _isOpeningProject = false;
  final Set<String> _deletingThreadIds = {}; // Prevent double deletion
  Timer? _timestampUpdateTimer; // Periodic timer to update relative timestamps
  final ValueNotifier<int> _timestampTick = ValueNotifier<int>(0); // Tick counter for timestamp updates
  
  // Cache snapshot Futures to prevent recreation on rebuilds (eliminates flicker)
  final Map<String, Future<Map<String, dynamic>?>> _snapshotFutureCache = {};
  int _previousWorkingStateVersion = 0;
  
  // Track last seen version for each project to detect changes during build
  final Map<String, int> _projectVersionCache = {};

  // ============================================================================
  // LAYOUT CONTROL VARIABLES - CENTRALIZED CONFIGURATION
  // ============================================================================
  // All adjustable layout parameters in one place. Change these to customize appearance.
  // Using 2-column grid layout similar to Google Docs
  
  // ----------------------------------------------------------------------------
  // TESTING & DEBUG CONTROLS
  // ----------------------------------------------------------------------------
  // Enable/disable mock projects for testing layer boundaries and UI layout
  static const bool _showMockProjects = false;  // Set to true to show mock test projects
  
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
  
  // Collaborator update highlight (blue tint for unviewed updates)
  // When a collaborator updates a project:
  // 1. Tile background changes to bright blue (25% opacity)
  // 2. "MODIFIED" label and timestamp in footer turn bright blue (full opacity)
  static const Color _collaboratorUpdateColor = Color(0xFF4A7BA7); // Bright blue (#4A7BA7)
  static const double _collaboratorUpdateOpacity = 0.25; // 25% opacity for background tint
  
  // ----------------------------------------------------------------------------
  // OVERLAY CONTROLS (Participants & Steps)
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
  // Examples: 'sourceSans3', 'roboto', 'inter', 'montserrat', 'poppins', 'openSans'
  static const String _overlayFontFamily = 'CrimsonPro';
  
  // Corner radius for overlays (0.0 = squared corners)
  static const double _overlayCornerRadius = 4.0;
  
  // Extension space around text (how much the background extends beyond text)
  // This controls the padding around the text content
  static const double _overlayHorizontalExtension = 14.0; // Horizontal padding (left & right)
  static const double _overlayVerticalExtension = 2.0;    // Vertical padding (top & bottom)
  
  // Overlay positioning offset from table corners
  // Controls spacing between overlay and pattern table edge (individual controls for each overlay)
  // Participants overlay (top right)
  static const double _participantsOverlayHorizontalOffset = 5.0; // Horizontal spacing from right edge
  static const double _participantsOverlayVerticalOffset = 5.0;   // Vertical spacing from top edge
  static const double _participantsOverlayFontSize = 12.0; // Font size for participant names
  static const double _participantsOnlineIndicatorSize = 6.0; // Size of online status dot
  static const double _participantsOnlineIndicatorSpacing = 6.0; // Space between dot and name
  // Metadata overlay (top left) - shows LEN, STP, HST
  static const double _metadataOverlayHorizontalOffset = 5.0; // Horizontal spacing from left edge
  static const double _metadataOverlayVerticalOffset = 5.0;   // Vertical spacing from top edge
  static const double _metadataOverlayLabelFontSize = 12.0; // Font size for labels (LEN, STP, HST)
  static const double _metadataOverlayNumberFontSize = 15.0; // Font size for numbers
  
  // Footer section (bottom of tile - shows created/modified dates)
  static const bool _showFooter = true; // Show/hide footer with dates
  static const double _footerHeight = 20.0; // Height of footer section
  static const double _footerHorizontalPadding = 12.0; // Horizontal padding inside footer
  static const double _footerLabelFontSize = 10.0; // Font size for "CREATED"/"MODIFIED" labels
  static const double _footerDateFontSize = 10.0; // Font size for date/time text
  static const Color _footerBackgroundColor = AppColors.sequencerSurfaceBase; // Footer background
  static const double _footerBackgroundOpacity = 0.8; // Footer background opacity
  static const Color _footerTextColor = AppColors.sequencerLightText; // Footer text color
  static const double _footerTextOpacity = 1.0; // Footer text opacity
  static const double _footerLabelOpacity = 0.7; // Opacity for "CREATED"/"MODIFIED" labels (lighter)
  
  // Font family for footer text (use GoogleFonts method name)
  // Examples: 'sourceSans3', 'roboto', 'inter', 'montserrat', 'poppins', 'openSans'
  static const String _footerFontFamily = 'sourceSans3';
  
  // Gradient edge fade controls
  // These create a gradient from transparent edges to solid center
  // Horizontal gradient (left-right fade on participants overlay)
  static const double _overlayHorizontalFadeWidth = 0.01; // 0.0-1.0, percentage of overlay width to fade (larger padding + smaller fade = more solid center)
  // Vertical gradient (top-bottom fade on both overlays)
  static const double _overlayVerticalFadeHeight = 0.5; // 0.0-1.0, percentage of overlay height to fade
  
  // ----------------------------------------------------------------------------
  // CREATE NEW PATTERN BUTTON (FAB) CONTROLS
  // ----------------------------------------------------------------------------
  // Floating Action Button appearance settings
  static const double _fabCornerRadius = 11.0; // Corner radius (0.0 = square, larger = more rounded)
  static const Color _fabBackgroundColor = Color.fromARGB(255, 66, 66, 66); // Button background color
  static Color _fabIconColor = Color.fromARGB(255, 185, 185, 185); // Plus sign color
  static const double _fabElevation = 4.0; // Shadow elevation
  static const double _fabIconSize = 50.0; // Size of plus icon

  // Helper method to get font family based on font family string
  static TextStyle _getFontStyle(String fontFamily, {
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    double? letterSpacing,
    double? height,
  }) {
    // Map font family string to GoogleFonts method
    switch (fontFamily.toLowerCase()) {
      case 'sourcesans3':
        return GoogleFonts.sourceSans3(
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
        // Default to sourceSans3 if unknown font family
        return GoogleFonts.sourceSans3(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
          letterSpacing: letterSpacing,
          height: height,
        );
    }
  }

  /// Build projects list - extracted to eliminate nested Consumer
  Widget _buildProjectsList(BuildContext context, ThreadsState threadsState) {
    // Use pre-computed sorted threads (no async, no flicker!)
    final sortedProjects = threadsState.sortedThreads;
    final projects = [...sortedProjects];
    
    // Add mock projects for testing layer boundaries (controlled by _showMockProjects flag)
    if (_showMockProjects) {
      _addMockProject(projects);
    }
    
    if (projects.isEmpty) {
      return const SizedBox.shrink(); // Show nothing when no projects
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Invites section (if current user has pending invites)
        _buildInvitesSection(context, threadsState),
        
        // Header with sorting controls
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            'PATTERNS',
            style: GoogleFonts.sourceSans3(
              color: AppColors.sequencerText,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
            ),
          ),
        ),
        
        // Projects list (single column)
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.all(_listPadding),
            itemCount: projects.length,
            separatorBuilder: (context, index) => SizedBox(height: _tileSpacing),
            itemBuilder: (context, index) {
              return _buildProjectCard(projects[index]);
            },
          ),
        ),
      ],
    );
  }
  
  /// Build invites section - extracted to eliminate Consumer2
  Widget _buildInvitesSection(BuildContext context, ThreadsState threadsState) {
    final userState = context.read<UserState>();
    final invites = userState.currentUser?.pendingInvitesToThreads ?? const [];
    
    if (invites.isEmpty) {
      return const SizedBox.shrink();
    }
    
    // Ensure missing invite thread summaries are loaded
    final existingIds = threadsState.threads.map((t) => t.id).toSet();
    final missing = invites.where((id) => !existingIds.contains(id)).toList();
    
    if (missing.isNotEmpty) {
      // Load missing invites once (not in postFrameCallback to avoid setState loop)
      Future.microtask(() async {
        for (final id in missing) {
          try {
            await threadsState.ensureThreadSummary(id);
          } catch (e) {
            debugPrint('⚠️ [PROJECTS] Failed to load invite $id: $e');
          }
        }
      });
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            'INVITES',
            style: GoogleFonts.sourceSans3(
              color: AppColors.sequencerText,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
            ),
          ),
        ),
        ...invites.map((id) {
          final t = threadsState.threads.firstWhere(
            (x) => x.id == id,
            orElse: () => Thread(
              id: id,
              name: ThreadNameGenerator.generate(id),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
              users: const [],
              messageIds: const [],
              invites: const [],
            ),
          );
          return _buildInviteCard(t.users.isEmpty ? null : t, userState, id);
        }).toList(),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    // Configure status bar to be transparent (shows background pattern through)
    // This affects both iOS and Android
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent, // Transparent status bar background
        statusBarIconBrightness: Brightness.dark, // Dark icons (for light background)
        statusBarBrightness: Brightness.light, // iOS status bar brightness
      ),
    );
    
    // Start periodic timer to update relative timestamps (every 10 seconds)
    // Uses ValueNotifier to only rebuild timestamp widgets, not entire screen
    _timestampUpdateTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        _timestampTick.value++; // Increment tick to trigger ValueListenableBuilder
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // Monitor working state version changes to invalidate snapshot cache
    // (Fallback for cases where working state updates while on projects screen)
    final threadsState = context.read<ThreadsState>();
    debugPrint('🔍 [PROJECTS] didChangeDependencies: current version=${threadsState.workingStateVersion}, previous=$_previousWorkingStateVersion');
    
    if (threadsState.workingStateVersion != _previousWorkingStateVersion) {
      debugPrint('🔄 [PROJECTS] Version changed! Old: $_previousWorkingStateVersion, New: ${threadsState.workingStateVersion}');
      
      // Working state changed - invalidate cache for active thread
      if (threadsState.activeThread != null) {
        final threadId = threadsState.activeThread!.id;
        final hadCache = _snapshotFutureCache.containsKey(threadId);
        _snapshotFutureCache.remove(threadId);
        debugPrint('📸 [PROJECTS] Invalidated snapshot cache for $threadId (had cache: $hadCache)');
      } else {
        debugPrint('⚠️ [PROJECTS] No active thread to invalidate cache for');
      }
      
      _previousWorkingStateVersion = threadsState.workingStateVersion;
      
      // Force rebuild to show updated pattern preview
      if (mounted) {
        debugPrint('🔨 [PROJECTS] Calling setState() to trigger rebuild');
        setState(() {});
      } else {
        debugPrint('⚠️ [PROJECTS] Widget not mounted, skipping setState()');
      }
    } else {
      debugPrint('✅ [PROJECTS] Version unchanged, no action needed');
    }
  }

  @override
  void dispose() {
    // Cancel timestamp update timer
    _timestampUpdateTimer?.cancel();
    _timestampTick.dispose();
    
    // Restore default system UI styling when leaving this screen
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
      final userState = Provider.of<UserState>(context, listen: false);
      final threadsState = Provider.of<ThreadsState>(context, listen: false);
      
      // Invalidate snapshot cache for active thread (if any)
      // This ensures pattern preview shows latest working state when returning from sequencer
      bool cacheInvalidated = false;
      if (threadsState.activeThread != null) {
        final threadId = threadsState.activeThread!.id;
        _snapshotFutureCache.remove(threadId);
        cacheInvalidated = true;
        debugPrint('📸 [PROJECTS] Invalidated snapshot cache for active thread: $threadId');
      }
      
      // Load threads (returns cached data immediately if available)
      await threadsState.loadThreads();
      
      // Refresh in background if already loaded (collaborative data)
      if (threadsState.hasLoaded) {
        // Refresh user and threads in background
        _refreshInBackground(userState, threadsState);
      } else {
        // First load - also fetch invites
        await _loadInvites(userState, threadsState);
      }
      
      setState(() {
        _error = null;
      });
      
      // Force rebuild if cache was invalidated to show updated pattern preview
      if (cacheInvalidated && mounted) {
        debugPrint('🔄 [PROJECTS] Forcing rebuild to show updated pattern preview');
        setState(() {});
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load projects: $e';
      });
    }
  }
  
  Future<void> _refreshInBackground(UserState userState, ThreadsState threadsState) async {
    try {
      // Refresh current user to fetch pending_invites_to_threads
      await userState.refreshCurrentUserFromServer();
      
      // Refresh threads in background
      await threadsState.refreshThreadsInBackground();
      
      // Also load invite thread summaries
      await _loadInvites(userState, threadsState);
    } catch (e) {
      debugPrint('❌ [PROJECTS] Background refresh error: $e');
      // Don't show error to user for background refresh
    }
  }
  
  Future<void> _loadInvites(UserState userState, ThreadsState threadsState) async {
    final invites = userState.currentUser?.pendingInvitesToThreads ?? const [];
    for (final threadId in invites) {
      await threadsState.ensureThreadSummary(threadId);
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.sequencerPageBackground, // Solid background color matching sequencer
      body: Stack(
        children: [
          SafeArea(
        child: Column(
          children: [
            // Simplified header with library icon
            const SimplifiedHeaderWidget(),
            
            Consumer<ThreadsState>(
              builder: (context, threadsState, _) {
                // Show loading only on first load (no cached data)
                if (threadsState.isLoading && !threadsState.hasLoaded) {
                  return Expanded(
                    child: Center(
                      child: CircularProgressIndicator(color: AppColors.sequencerAccent),
                    ),
                  );
                }
                
                return Expanded(
                  child: Stack(
                    children: [
                      Column(
                        children: [
                          // Projects List
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Projects content
                                Expanded(
                                  child:                                   _error != null
                                      ? Center(
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.error_outline, color: AppColors.sequencerLightText, size: 48),
                                              const SizedBox(height: 12),
                                              Text(
                                                _error!, 
                                                style: GoogleFonts.sourceSans3(
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
                                                  style: GoogleFonts.sourceSans3(
                                                    color: AppColors.sequencerText,
                                                    fontWeight: FontWeight.bold,
                                                    letterSpacing: 1.0,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      : _buildProjectsList(context, threadsState),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      // Show subtle refresh indicator when refreshing in background
                      if (threadsState.isRefreshing && threadsState.hasLoaded)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: AppColors.sequencerSurfaceRaised.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.sequencerBorder),
                            ),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppColors.sequencerAccent,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
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
          // Custom positioned floating action button
          Positioned(
            right: 30,
            bottom: 30,
            child: Material(
              color: _fabBackgroundColor,
              elevation: _fabElevation,
              borderRadius: BorderRadius.circular(_fabCornerRadius),
              child: InkWell(
                onTap: () async {
                  // Stop any playing audio from playlist/renders
                  context.read<AudioPlayerState>().stop();
                  // Clear active thread context for new project
                  context.read<ThreadsState>().setActiveThread(null);
                  // Initialize native subsystems (idempotent: init performs cleanup)
                  try {
                    TableBindings().tableInit();
                    PlaybackBindings().playbackInit();
                    SampleBankBindings().sampleBankInit();
                    // Assign random colors for new project from dark forest/berry palette
                    context.read<SampleBankState>().assignRandomProjectColors();
                  } catch (e) {
                    debugPrint('❌ Failed to init native subsystems: $e');
                  }
                  // Navigate to sequencer using PatternScreen which handles version routing
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const PatternScreen(),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(_fabCornerRadius),
                child: Container(
                  width: 56,
                  height: 56,
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
        ],
      ),
    );
  }


  Widget _buildProjectCard(Thread project) {
    final threadsState = context.read<ThreadsState>();
    final currentVersion = threadsState.workingStateVersion;
    
    debugPrint('🎴 [PROJECTS] Building card for ${project.id}, workingStateVersion=$currentVersion');
    
    // Check if version changed for this project and invalidate cache if needed
    // This is necessary because didChangeDependencies() doesn't fire after Navigator.pop()
    final lastSeenVersion = _projectVersionCache[project.id];
    if (lastSeenVersion != null && lastSeenVersion != currentVersion) {
      // Version changed since last build - invalidate cache
      final hadCache = _snapshotFutureCache.containsKey(project.id);
      _snapshotFutureCache.remove(project.id);
      debugPrint('🔄 [PROJECTS] Version changed for ${project.id} ($lastSeenVersion → $currentVersion), invalidated cache (had: $hadCache)');
    }
    
    // Update version cache for next build
    _projectVersionCache[project.id] = currentVersion;
    
    // Check if project was updated by collaborators (pre-computed, instant!)
    final hasCollaboratorUpdates = threadsState.hasCollaboratorUpdates(project.id);
    
    // Wrap in RepaintBoundary to isolate repaints and prevent flicker
    return RepaintBoundary(
      child: Container(
          // Rebuild when project's message count changes (new checkpoint saved)
          // Note: Footer still updates on auto-save via its own FutureBuilder key
          key: ValueKey('${project.id}_${project.messageIds.length}'),
          height: _tileHeight,
          decoration: BoxDecoration(
            // Blue-tinted background if updated by collaborators
            color: hasCollaboratorUpdates 
                ? _collaboratorUpdateColor.withOpacity(_collaboratorUpdateOpacity)
                : _tileBackgroundColor,
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
          onTap: () => _openProject(project),
          onLongPress: () => _showDeleteDialog(project),
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
                            key: ValueKey('preview_${project.id}_${threadsState.workingStateVersion}'),
                            project: project,
                            getProjectSnapshot: _getProjectSnapshot,
                            getSampleBankColors: _getSampleBankColors,
                            fadeOverlayColor: _tileBackgroundColor,
                            innerPadding: const EdgeInsets.all(6),
                            workingStateVersion: threadsState.workingStateVersion,
                          ),
                        ),
                        
                        // Participants overlay (top right)
                        _buildParticipantsOverlay(project),
                        
                        // Metadata overlay (top left)
                        _buildMetadataOverlay(project),
                      ],
                    ),
                  ),
                  
                  // Footer section (below pattern preview)
                  if (_showFooter)
                    _buildFooter(project),
                ],
              ),
            ),
          ),
        ),
    );
  }
  
  /// Builds participants overlay for top right corner
  Widget _buildParticipantsOverlay(Thread project) {
    final userState = context.read<UserState>();
    final currentUserId = userState.currentUser?.id ?? '';
    final otherParticipants = project.users
        .where((u) => u.id != currentUserId)
        .toList();
    
    if (otherParticipants.isEmpty) {
      return const SizedBox.shrink();
    }
    
    // Position at the corner of the pattern table (accounting for innerPadding)
    // innerPadding = 6px (from PatternPreviewWidget)
    const patternInnerPadding = 6.0;
    const maxVisible = 5;
    
    // Build list of participants to display (max 5 + "and N others" if needed)
    final List<Widget> participantWidgets = [];
    final visibleParticipants = otherParticipants.take(maxVisible).toList();
    final remaining = otherParticipants.length - maxVisible;
    
    // Add visible participants with online status indicators
    for (final user in visibleParticipants) {
      participantWidgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Online status indicator (green dot)
              Container(
                width: _participantsOnlineIndicatorSize,
                height: _participantsOnlineIndicatorSize,
                margin: EdgeInsets.only(right: _participantsOnlineIndicatorSpacing),
                decoration: BoxDecoration(
                  color: user.isOnline 
                      ? AppColors.menuOnlineIndicator  // Green for online
                      : _overlayTextColor.withOpacity(0.3),  // Gray for offline
                  shape: BoxShape.circle,
                ),
              ),
              // Username
              Text(
                user.username,
                style: _getFontStyle(
                  _overlayFontFamily,
                  color: _overlayTextColor.withOpacity(_overlayTextOpacity),
                  fontSize: _participantsOverlayFontSize,
                  fontWeight: _overlayTextFontWeight,
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    // Add "and N others" if there are more
    if (remaining > 0) {
      participantWidgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            'and $remaining others',
            style: _getFontStyle(
              _overlayFontFamily,
              color: _overlayTextColor.withOpacity(_overlayTextOpacity * 0.7),
              fontSize: _participantsOverlayFontSize,
              fontWeight: _overlayTextFontWeight,
            ),
          ),
        ),
      );
    }
    
    return Positioned(
      top: patternInnerPadding + _participantsOverlayVerticalOffset,
      right: patternInnerPadding + _participantsOverlayHorizontalOffset,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_overlayCornerRadius),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Background layer with gradient edges (positioned behind text)
            Positioned.fill(
              child: _buildOverlayBackground(),
            ),
            // Text layer with padding (defines size, drawn on top)
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: _overlayHorizontalExtension,
                vertical: _overlayVerticalExtension,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: participantWidgets,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  /// Builds metadata overlay for top left corner
  /// Shows LEN (sections), STP (total steps), HST (message history count)
  Widget _buildMetadataOverlay(Thread project) {
    // Helper to calculate font size based on digit count
    // 4 digits or less: use normal size, more than 4: scale down to fit
    double _getNumberFontSize(int number) {
      final digitCount = number.toString().length;
      if (digitCount <= 4) {
        return _metadataOverlayNumberFontSize;
      } else {
        // Scale down proportionally for numbers > 4 digits
        return _metadataOverlayNumberFontSize * (4.0 / digitCount);
      }
    }
    
    // Helper to build a metric row with fixed-width number container
    Widget _buildMetricRow(String label, int value) {
      return Row(
        mainAxisSize: MainAxisSize.min,
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
          const SizedBox(width: 4),
          // Fixed-width container for numbers (sized for 4 digits)
          SizedBox(
            width: _metadataOverlayNumberFontSize * 2.4, // Approximately 4 digits width
            child: Text(
              '$value',
              textAlign: TextAlign.end,
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
      future: _getProjectSnapshot(project.id),
      builder: (context, snapshot) {
        int sectionsCount = 0; // LEN
        int totalSteps = 0; // STP
        
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
        
        // HST: Message count from thread
        final messageCount = project.messageIds.length;
        
        // Position at the corner of the pattern table (accounting for innerPadding)
        // innerPadding = 6px (from PatternPreviewWidget)
        const patternInnerPadding = 6.0;
        
        return Positioned(
          top: patternInnerPadding + _metadataOverlayVerticalOffset,
          left: patternInnerPadding + _metadataOverlayHorizontalOffset,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_overlayCornerRadius),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Background layer with gradient edges (positioned behind text)
                Positioned.fill(
                  child: _buildOverlayBackground(),
                ),
                // Text layer with padding (defines size, drawn on top)
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: _overlayHorizontalExtension,
                    vertical: _overlayVerticalExtension,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // LEN (sections count)
                      _buildMetricRow('LEN', sectionsCount),
                      const SizedBox(height: 2),
                      // STP (total steps)
                      _buildMetricRow('STP', totalSteps),
                      const SizedBox(height: 2),
                      // HST (message history count)
                      _buildMetricRow('HST', messageCount),
                    ],
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
  Widget _buildFooter(Thread project) {
    // Check if project has collaborator updates for blue highlighting
    final threadsState = context.read<ThreadsState>();
    final hasCollaboratorUpdates = threadsState.hasCollaboratorUpdates(project.id);
    
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
        return 'just now'; // Show "just now" instead of "0s ago"
      } else if (difference.inSeconds < 60) {
        return '${difference.inSeconds}s ago';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes}m ago';
      } else {
        return '${difference.inHours}h ago';
      }
    }
    
    final createdDate = formatDate(project.createdAt);
    
    final footerColor = _footerBackgroundColor.withOpacity(_footerBackgroundOpacity);
    debugPrint('🎨 [FOOTER] Background color: $footerColor, opacity: $_footerBackgroundOpacity');
    
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
          // Modified date (right) - Shows working state timestamp if newer
          // Uses FutureBuilder for async timestamp fetch + ValueListenableBuilder for periodic updates
          FutureBuilder<DateTime>(
            key: ValueKey('modified_${project.id}_${context.read<ThreadsState>().workingStateVersion}'),
            future: context.read<ThreadsState>().getThreadModifiedAt(project.id, project.updatedAt),
            builder: (context, snapshot) {
              final timestamp = snapshot.data ?? project.updatedAt;
              
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'MODIFIED',
                    style: _getFontStyle(
                      _footerFontFamily,
                      // Use bright blue when collaborator updated, otherwise default color
                      color: hasCollaboratorUpdates
                          ? _collaboratorUpdateColor
                          : _footerTextColor.withOpacity(_footerLabelOpacity),
                      fontSize: _footerLabelFontSize,
                      fontWeight: _overlayTextFontWeight,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 4),
                  // ValueListenableBuilder only rebuilds this Text widget every 10 seconds
                  ValueListenableBuilder<int>(
                    valueListenable: _timestampTick,
                    builder: (context, tick, child) {
                      // Recalculate relative time on each tick
                      final modifiedDateText = formatRelativeTime(timestamp);
                      return Text(
                        modifiedDateText,
                        style: _getFontStyle(
                          _footerFontFamily,
                          // Use bright blue when collaborator updated, otherwise default color
                          color: hasCollaboratorUpdates
                              ? _collaboratorUpdateColor
                              : _footerTextColor.withOpacity(_footerTextOpacity),
                          fontSize: _footerDateFontSize,
                          fontWeight: _overlayTextFontWeight,
                        ),
                      );
                    },
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
  /// Supports both horizontal and vertical fade with independent controls
  /// Uses CustomPaint for proper gradient composition
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
  
  
  // Mock projects for testing layer boundaries
  void _addMockProject(List<Thread> projects) {
    const mockId1 = 'mock-layer-test-project-1';
    const mockId2 = 'mock-layer-test-project-2';
    
    // Only add if not already present
    final existingIds = projects.map((p) => p.id).toSet();
    
    // Mock project 1: With 3 participants
    if (!existingIds.contains(mockId1)) {
      final mockProject1 = Thread(
        id: mockId1,
        name: '🧪 MOCK: 3-Digit Test (LEN=123, HST=456)',
        createdAt: DateTime.now().subtract(const Duration(days: 100)),
        updatedAt: DateTime.now().subtract(const Duration(hours: 5, minutes: 30)), // 5.5 hours ago
        users: [
          ThreadUser(
            id: 'mock-user-1',
            username: 'Vsevolod',
            name: 'Alice Johnson',
            joinedAt: DateTime.now().subtract(const Duration(days: 95)),
            isOnline: true,
          ),
          ThreadUser(
            id: 'mock-user-2',
            username: 'superpuper bro hello',
            name: 'Bob Smith',
            joinedAt: DateTime.now().subtract(const Duration(days: 90)),
            isOnline: false,
          ),
          ThreadUser(
            id: 'mock-user-3',
            username: 'User3',
            name: 'Charlie Brown',
            joinedAt: DateTime.now().subtract(const Duration(days: 85)),
            isOnline: false,
          ),
          ThreadUser(
            id: 'mock-user-3',
            username: 'User3',
            name: 'Charlie Brown',
            joinedAt: DateTime.now().subtract(const Duration(days: 85)),
            isOnline: false,
          ),
          ThreadUser(
            id: 'mock-user-3',
            username: 'User3',
            name: 'Charlie Brown',
            joinedAt: DateTime.now().subtract(const Duration(days: 85)),
            isOnline: false,
          ),
          ThreadUser(
            id: 'mock-user-3',
            username: 'User3',
            name: 'Charlie Brown',
            joinedAt: DateTime.now().subtract(const Duration(days: 85)),
            isOnline: false,
          ),
        ],
        messageIds: List.generate(456, (i) => 'msg$i'), // 456 messages for HST counter (3 digits)
        invites: const [],
        isLocal: true,
      );
      projects.insert(0, mockProject1);
    }
    
    // Mock project 2: Solo project (no additional participants)
    if (!existingIds.contains(mockId2)) {
      final userState = context.read<UserState>();
      final currentUserId = userState.currentUser?.id ?? 'mock-current-user';
      final currentUsername = userState.currentUser?.username ?? 'CurrentUser';
      
      final mockProject2 = Thread(
        id: mockId2,
        name: '🧪 MOCK: Solo Project (64 steps)',
        createdAt: DateTime.now().subtract(const Duration(days: 50)),
        updatedAt: DateTime.now().subtract(const Duration(minutes: 25)), // 25 minutes ago
        users: [
          ThreadUser(
            id: currentUserId,
            username: currentUsername,
            name: 'Current User',
            joinedAt: DateTime.now().subtract(const Duration(days: 50)),
            isOnline: true,
          ),
        ],
        messageIds: List.generate(64, (i) => 'msg$i'), // 64 messages
        invites: const [],
        isLocal: true,
      );
      projects.insert(1, mockProject2); // Add as second item
    }
  }
  
  /// Extracts sample bank colors from snapshot data
  /// Follows schema: sample_bank has 'samples' array with 'loaded' flag and optional 'color'
  /// Returns colors for ALL 25 slots (A-Y) - slot 25 (Z) is internal preview slot
  /// ONLY loaded samples have colors - unloaded slots return empty cell color
  /// Pattern preview expects array index to match sample slot number!
  /// This function matches the signature expected by PatternPreviewWidget
  List<Color> _getSampleBankColors(Map<String, dynamic> snapshotData) {
    final List<Color> colors = [];
    
    try {
      // Extract sample_bank from snapshot
      final source = snapshotData['source'] as Map<String, dynamic>?;
      if (source == null) {
        debugPrint('⚠️ [COLOR] No source in snapshot data');
        return List.generate(25, (i) => AppColors.sequencerCellEmpty);
      }
      
      final sampleBankData = source['sample_bank'] as Map<String, dynamic>?;
      if (sampleBankData == null) {
        debugPrint('⚠️ [COLOR] No sample_bank in source');
        return List.generate(25, (i) => AppColors.sequencerCellEmpty);
      }
      
      final samples = sampleBankData['samples'] as List<dynamic>?;
      if (samples == null) {
        debugPrint('⚠️ [COLOR] No samples in sample_bank');
        return List.generate(25, (i) => AppColors.sequencerCellEmpty);
      }
      
      // Process first 25 slots (A-Y) - skip slot 25 (Z) which is internal preview
      // ONLY use color for loaded samples (project-specific colors)
      // Pattern preview uses array index as sample_slot number
      final slotsToProcess = samples.length.clamp(0, 25);
      int loadedCount = 0;
      int coloredCount = 0;
      
      debugPrint('🎨 [COLOR] Processing $slotsToProcess sample slots');
      
      for (int i = 0; i < slotsToProcess; i++) {
        final sample = samples[i];
        if (sample is Map<String, dynamic>) {
          final loaded = sample['loaded'] as bool? ?? false;
          final hasColor = sample.containsKey('color');
          
          if (loaded) loadedCount++;
          
          // ONLY use color if sample is loaded AND has color field
          if (loaded && hasColor) {
            final colorHex = sample['color'] as String;
            try {
              final color = _hexToColor(colorHex);
              colors.add(color);
              coloredCount++;
              if (coloredCount <= 3) { // Only log first 3 to avoid spam
                debugPrint('✅ [COLOR] Slot $i: loaded with color $colorHex');
              }
            } catch (e) {
              debugPrint('❌ [COLOR] Slot $i parse error: $e');
              colors.add(AppColors.sequencerCellEmpty);
            }
          } else {
            // Use empty cell color for unloaded slots
            colors.add(AppColors.sequencerCellEmpty);
          }
        } else {
          colors.add(AppColors.sequencerCellEmpty);
        }
      }
      
      debugPrint('🎨 [COLOR] Summary: $loadedCount loaded, $coloredCount with colors out of $slotsToProcess slots');
      
      // If we have fewer than 25 colors, fill the rest with empty color
      while (colors.length < 25) {
        colors.add(AppColors.sequencerCellEmpty);
      }
    } catch (e) {
      debugPrint('❌ [PROJECTS] Error parsing sample bank colors: $e');
      // Return empty colors on error
      return List.generate(25, (i) => AppColors.sequencerCellEmpty);
    }
    
    return colors;
  }
  
  /// Convert hex color string to Color object (e.g., "#FF5733" -> Color)
  Color _hexToColor(String hex) {
    final buffer = StringBuffer();
    if (hex.startsWith('#')) {
      buffer.write(hex.substring(1)); // Remove #
    } else {
      buffer.write(hex);
    }
    return Color(int.parse(buffer.toString(), radix: 16) + 0xFF000000);
  }
  Future<Map<String, dynamic>?> _getProjectSnapshot(String threadId) {
    // Return cached Future to prevent recreation on rebuild (eliminates flicker!)
    final hasCache = _snapshotFutureCache.containsKey(threadId);
    debugPrint('📸 [PROJECTS] _getProjectSnapshot called for $threadId (has cache: $hasCache)');
    
    return _snapshotFutureCache.putIfAbsent(threadId, () async {
      try {
        debugPrint('🆕 [PROJECTS] Creating NEW snapshot Future for $threadId');
        
        // Special handling for mock projects
        if (threadId == 'mock-layer-test-project-1') {
          return _createMockSnapshot(sectionsCount: 123);
        }
        if (threadId == 'mock-layer-test-project-2') {
          return _createMockSnapshot(sectionsCount: 64);
        }
        
        // Use unified cache from ThreadsState
        final threadsState = context.read<ThreadsState>();
        debugPrint('📥 [PROJECTS] Calling threadsState.loadProjectSnapshot for $threadId');
        final snapshot = await threadsState.loadProjectSnapshot(threadId);
        
        if (snapshot == null || snapshot.isEmpty) {
          debugPrint('⚠️ [PROJECTS] No snapshot for $threadId - returning empty pattern');
          return _createEmptySnapshot();
        }
        
        // Debug: Check if snapshot has table cells with data
        try {
          final source = snapshot['source'] as Map<String, dynamic>?;
          final table = source?['table'] as Map<String, dynamic>?;
          final tableCells = table?['table_cells'] as List<dynamic>?;
          final sampleBank = source?['sample_bank'] as Map<String, dynamic>?;
          final samples = sampleBank?['samples'] as List<dynamic>?;
          final loadedCount = samples?.where((s) => (s as Map)['loaded'] == true).length ?? 0;
          debugPrint('✅ [PROJECTS] Loaded snapshot for $threadId: ${tableCells?.length ?? 0} rows, $loadedCount loaded samples');
        } catch (e) {
          debugPrint('⚠️ [PROJECTS] Error parsing snapshot details: $e');
        }
        
        return snapshot;
      } catch (e) {
        debugPrint('❌ [PROJECTS] Error loading snapshot for $threadId: $e');
        return _createEmptySnapshot();
      }
    });
  }
  
  /// Create mock snapshot with colors for testing
  Map<String, dynamic> _createMockSnapshot({int sectionsCount = 123}) {
    return {
      'source': {
        'table': {
          'sections': List.generate(sectionsCount, (i) => {
            'num_steps': 16,
            'start_step': i * 16,
          }),
          'layers': [
            [
              {'len': 2},  // Layer 1: 2 columns
              {'len': 6},  // Layer 2: 6 columns
              {'len': 5},  // Layer 3: 5 columns
              {'len': 7},  // Layer 4: 7 columns
              {'len': 8},  // Layer 5: 8 columns
              {'len': 4},  // Layer 6: 4 columns
              {'len': 2},  // Layer 7: 2 columns
              {'len': 1},  // Layer 8: 1 column
            ]
          ],
          'table_cells': List.generate(16, (row) {
            return List.generate(35, (col) {
              // Add some cells with sample slots
              if ((row + col) % 3 == 0) {
                return {'sample_slot': (col % 8)};
              }
              return null;
            });
          }),
        },
        'sample_bank': {
          'max_slots': 26,
          'samples': List.generate(26, (i) {
            // First 10 slots loaded with colors
            final loaded = i < 10;
            return {
              'loaded': loaded,
              'settings': {
                'volume': 1.0,
                'pitch': 1.0,
              },
              if (loaded) 'color': '#${((i * 30) % 255).toRadixString(16).padLeft(2, '0')}'
                                      '${((i * 60) % 255).toRadixString(16).padLeft(2, '0')}'
                                      '${((i * 90) % 255).toRadixString(16).padLeft(2, '0')}'.toUpperCase(),
            };
          }),
        },
      },
    };
  }
  
  /// Creates an empty snapshot structure for threads with no messages
  /// This allows pattern preview to show an empty grid instead of error state
  /// Follows schema: sample_bank.json
  Map<String, dynamic> _createEmptySnapshot() {
    return {
      'source': {
        'table': {
          'sections_count': 1,
          'sections': [
            {'start_step': 0, 'num_steps': 16}
          ],
          'layers': [
            [4, 4, 4, 4] // 4 layers with 4 columns each (16 total)
          ],
          'table_cells': List.generate(
            16, // 16 steps
            (step) => List.generate(
              16, // 16 columns
              (col) => {
                'sample_slot': -1, // Empty cell
                'settings': {'volume': -1.0, 'pitch': -1.0}
              },
            ),
          ),
        },
        'sample_bank': {
          'max_slots': 26,  // Schema requires 26 (includes preview slot Z)
          'samples': List.generate(26, (i) => {
            'loaded': false,  // All slots empty
            'settings': {
              'volume': 1.0,
              'pitch': 1.0,
            },
          }),
        },
      },
    };
  }

  Widget _buildInviteCard(Thread? thread, UserState userState, String threadId) {
    final currentUsername = userState.currentUser?.username ?? '';
    final needsUsername = currentUsername.isEmpty;

    return StatefulBuilder(
      builder: (context, setLocalState) {
        final TextEditingController usernameController = TextEditingController();
        String? usernameError;
        bool isUpdatingUsername = false;

        String? validateUsername(String username) {
          if (username.isEmpty) return 'Username required';
          if (username.length < 3) return 'Min 3 characters';
          final validPattern = RegExp(r'^[a-zA-Z0-9_-]+$');
          if (!validPattern.hasMatch(username)) return 'Only letters, numbers, _ and -';
          return null;
        }

        Future<void> handleAccept() async {
          // If username is needed, validate first
          if (needsUsername) {
            final username = usernameController.text.trim();
            final error = validateUsername(username);
            if (error != null) {
              setLocalState(() => usernameError = error);
              return;
            }

            setLocalState(() => isUpdatingUsername = true);
            try {
              final success = await userState.updateUsername(username);
              if (!success) {
                setLocalState(() {
                  usernameError = 'Failed to create username';
                  isUpdatingUsername = false;
                });
                return;
              }
            } catch (e) {
              setLocalState(() {
                usernameError = e.toString().replaceFirst('Exception: ', '');
                isUpdatingUsername = false;
              });
              return;
            }
          }

          // Accept invite
          await ThreadsApi.acceptInvite(threadId: threadId, userId: userState.currentUser!.id);
          final userSvc = context.read<UserState>();
          final threadsState = context.read<ThreadsState>();
          await userSvc.refreshCurrentUserFromServer();
          await threadsState.loadThreads();
          final invites = userSvc.currentUser?.pendingInvitesToThreads ?? const [];
          for (final id in invites) {
            await threadsState.ensureThreadSummary(id);
          }
          if (mounted) setState(() {});
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            color: AppColors.sequencerSurfaceRaised,
            border: Border(
              left: BorderSide(
                color: AppColors.sequencerAccent.withOpacity(0.5),
                width: 2,
              ),
              bottom: BorderSide(
                color: AppColors.sequencerBorder,
                width: 0.5,
              ),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Row 1: Project info
                  Row(
                    children: [
                      // Emojis
                      ColorFiltered(
                        colorFilter: const ColorFilter.matrix(<double>[
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0,      0,      0,      1, 0,
                        ]),
                        child: Text(
                          thread?.name ?? '',
                          style: GoogleFonts.sourceSans3(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 2.0,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Checkpoint counter
                      Text(
                        '${thread?.messageIds.length ?? 0}',
                        style: GoogleFonts.sourceSans3(
                          color: AppColors.sequencerLightText,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      // Participant chips
                      if (thread != null)
                        _buildParticipantsChips(thread)
                      else
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.sequencerBorder.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'invite',
                            style: GoogleFonts.sourceSans3(
                              color: AppColors.sequencerLightText,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),

                  // Row 2 (conditional): Username creation field
                  if (needsUsername) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.sequencerAccent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: AppColors.sequencerAccent,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.person, color: AppColors.sequencerAccent, size: 16),
                          const SizedBox(width: 8),
                            Expanded(
                            child: TextField(
                              controller: usernameController,
                              style: GoogleFonts.sourceSans3(
                                color: AppColors.sequencerText,
                                fontSize: 14,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Create username to accept',
                                hintStyle: GoogleFonts.sourceSans3(
                                  color: AppColors.sequencerLightText,
                                  fontSize: 14,
                                ),
                                errorText: usernameError,
                                errorStyle: GoogleFonts.sourceSans3(
                                  color: Colors.red,
                                  fontSize: 11,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              onChanged: (value) {
                                setLocalState(() {
                                  usernameError = null;
                                });
                              },
                            ),
                          ),
                          if (isUpdatingUsername)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    AppColors.sequencerAccent,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],

                  // Row 3: Action buttons
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ActionButton(
                        label: 'ACCEPT',
                        background: AppColors.sequencerAccent,
                        border: AppColors.sequencerAccent,
                        textColor: AppColors.sequencerText,
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        fontSize: 12,
                        onTap: () => handleAccept(),
                      ),
                      const SizedBox(width: 8),
                      ActionButton(
                        label: 'DENY',
                        background: AppColors.sequencerSurfaceBase,
                        border: AppColors.sequencerBorder,
                        textColor: AppColors.sequencerText,
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        fontSize: 12,
                        onTap: () async {
                          await ThreadsApi.declineInvite(threadId: threadId, userId: userState.currentUser!.id);
                          final userSvc = context.read<UserState>();
                          final threadsState = context.read<ThreadsState>();
                          await userSvc.refreshCurrentUserFromServer();
                          await threadsState.loadThreads();
                          final invites = userSvc.currentUser?.pendingInvitesToThreads ?? const [];
                          for (final id in invites) {
                            await threadsState.ensureThreadSummary(id);
                          }
                          if (mounted) setState(() {});
                        },
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildParticipantsChips(Thread project) {
    final userState = context.read<UserState>();
    final me = userState.currentUser?.id;
    final others = project.users.where((u) => u.id != me).map((u) => u.username).toList();
    if (others.isEmpty) return const SizedBox.shrink();
    final List<Widget> chips = [];
    const maxVisible = 5;
    for (final username in others.take(maxVisible)) {
      chips.add(Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.sequencerBorder.withOpacity(0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          username,
          style: GoogleFonts.sourceSans3(color: AppColors.sequencerLightText, fontSize: 12, fontWeight: FontWeight.w500),
          overflow: TextOverflow.ellipsis,
        ),
      ));
    }
    final remaining = others.length - maxVisible;
    if (remaining > 0) {
      chips.add(Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.sequencerBorder.withOpacity(0.3),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          'and $remaining others',
          style: GoogleFonts.sourceSans3(color: AppColors.sequencerLightText, fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ));
    }
    return SizedBox(
      width: 280,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        child: Row(children: chips),
      ),
    );
  }


  Future<void> _openProject(Thread project) async {
    await _loadProjectInSequencer(project);
  }

  Future<void> _loadProjectInSequencer(Thread project) async {
    try {
      if (mounted) {
        setState(() {
          _isOpeningProject = true;
        });
      }

      // Set active thread context so Sequencer V2 doesn't create a new unpublished thread
      final threadsState = context.read<ThreadsState>();
      threadsState.setActiveThread(project);

      // Stop any playing audio from playlist/renders
      context.read<AudioPlayerState>().stop();
      
      // Use unified loader (handles initialization, caching, and import)
      // This will:
      // 1. Check and initialize native systems if needed (one-time)
      // 2. Check cache first, fetch from API if needed
      // 3. Import snapshot with proper resets (surgical, not full reinit)
      // 4. Clear undo/redo history for fresh start
      debugPrint('📂 [PROJECTS] Loading project ${project.id} via unified loader');
      final success = await threadsState.loadProjectIntoSequencer(project.id);
      
      if (!success) {
        debugPrint('⚠️ [PROJECTS] Project has no snapshot - will start empty');
      }

      // Navigate to sequencer using PatternScreen
      // Pass null snapshot since import already loaded everything
      if (mounted) {
        setState(() {
          _isOpeningProject = false;
        });
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const PatternScreen(initialSnapshot: null),
          ),
        );
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

  void _showDeleteDialog(Thread project) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.sequencerSurfaceRaised,
          title: Text(
            'Delete Project',
            style: GoogleFonts.sourceSans3(
              color: AppColors.sequencerText,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            'Are you sure you want to delete this pattern? This will delete it for all participants.',
            style: GoogleFonts.sourceSans3(
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
                style: GoogleFonts.sourceSans3(
                  color: AppColors.sequencerLightText,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _deleteProject(project);
              },
              child: Text(
                'Delete',
                style: GoogleFonts.sourceSans3(
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

  Future<void> _deleteProject(Thread project) async {
    // Prevent double deletion
    if (_deletingThreadIds.contains(project.id)) {
      return;
    }
    
    final threadsState = context.read<ThreadsState>();
    final isOfflineThread = project.isLocal == true;
    Thread? removedThread;
    
    try {
      _deletingThreadIds.add(project.id);
      
      // Optimistically remove the thread immediately from the UI
      removedThread = threadsState.removeThreadOptimistically(project.id);
      
      // Show loading indicator
      if (mounted) {
        setState(() {
          _isOpeningProject = true;
        });
      }

      // Skip API call for offline threads (they don't exist on server)
      if (!isOfflineThread) {
        await ThreadsApi.deleteThread(project.id);
      }

      // Refresh the projects list to ensure consistency
      await threadsState.loadThreads();

      if (mounted) {
        setState(() {
          _isOpeningProject = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Failed to delete project: $e');
      
      // If optimistic removal happened, restore the thread by refreshing
      if (removedThread != null) {
        await threadsState.loadThreads();
      }
      
      if (mounted) {
        setState(() {
          _isOpeningProject = false;
        });
      }
    } finally {
      _deletingThreadIds.remove(project.id);
    }
  }
}

// ============================================================================
// OVERLAY GRADIENT PAINTER
// ============================================================================
// Custom painter for overlay backgrounds with gradient edges
// Properly composites horizontal and vertical gradients for fade effect

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
    
    // Calculate alpha at each point based on both horizontal and vertical position
    // Edges fade to transparent, center stays at full opacity
    final paint = Paint();
    
    // Create gradient shader that handles both horizontal and vertical fading
    paint.shader = _createCombinedGradientShader(rect);
    
    // Draw with or without rounded corners
    if (cornerRadius > 0) {
      final rrect = RRect.fromRectAndRadius(rect, Radius.circular(cornerRadius));
      canvas.drawRRect(rrect, paint);
    } else {
      canvas.drawRect(rect, paint);
    }
  }
  
  Shader _createCombinedGradientShader(Rect rect) {
    // For a proper edge fade, we need to calculate opacity based on distance from edges
    // Using a radial gradient approach centered on the content
    // However, Flutter's built-in gradients don't directly support this
    // We'll use a workaround with LinearGradient for horizontal fade
    
    // If no fading, return solid color
    if (horizontalFade <= 0 && verticalFade <= 0) {
      return LinearGradient(
        colors: [
          backgroundColor.withOpacity(opacity),
          backgroundColor.withOpacity(opacity),
        ],
      ).createShader(rect);
    }
    
    // For now, use horizontal fade (most visible effect for right-aligned overlays)
    // Create stops for smooth fade from edges
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
