import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'sound_grid_widget.dart';
import 'sound_grid_side_control_widget.dart';
import 'section_creation_overlay.dart';
import '../../../state/sequencer/table.dart';
import '../../../state/sequencer/playback.dart';
import '../../../state/sequencer/edit.dart';
import '../../../state/sequencer/section_settings.dart';
import '../../../utils/app_colors.dart';

// Body element modes for switching between different content
enum SequencerBodyMode {
  soundGrid,
  sampleSelection,
  sampleBrowser,
}

class SequencerBody extends StatefulWidget {
  final VoidCallback? onOpenNavMenu;
  final VoidCallback? onSettings;

  const SequencerBody({
    super.key,
    this.onOpenNavMenu,
    this.onSettings,
  });

  // 🎯 SIZING CONFIGURATION - Easy to control layout proportions
  static const double sideControlWidthPercent =
      8.0; // Left side control takes 8% of total width
  static const double soundGridWidthPercent =
      89.0; // Sound grid takes 89% of total width
  static const double rightGutterWidthPercent =
      3.0; // Right gutter takes 3% of total width

  @override
  State<SequencerBody> createState() => _SequencerBodyState();
}

class _SequencerBodyState extends State<SequencerBody> {
  late final PageController _pageController;
  bool _isUserScrolling = false;

  late final TableState _tableState;
  late final SectionSettingsState _sectionSettingsState;
  int _prevSectionsCount = -1;
  int _prevUiSelectedSection = -1;

  @override
  void initState() {
    super.initState();
    final table = context.read<TableState>();
    final maxIndex = (table.sectionsCount - 1).clamp(0, TableState.maxSections);
    final initialPage = table.uiSelectedSection.clamp(0, maxIndex);
    _pageController = PageController(
      initialPage: initialPage,
      viewportFraction: 1.0,
    );
    _tableState = table;
    _sectionSettingsState = context.read<SectionSettingsState>();
    _prevSectionsCount = _tableState.sectionsCount;
    _prevUiSelectedSection = _tableState.uiSelectedSection;
    _tableState.addListener(_onTableChangedForPageSync);
    _sectionSettingsState.addListener(_onSectionSettingsChangedForPageSync);
  }

  void _onSectionSettingsChangedForPageSync() {
    _schedulePageSyncToUiSection();
  }

  void _onTableChangedForPageSync() {
    final table = _tableState;
    if (table.sectionsCount == _prevSectionsCount &&
        table.uiSelectedSection == _prevUiSelectedSection) {
      return;
    }
    _prevSectionsCount = table.sectionsCount;
    _prevUiSelectedSection = table.uiSelectedSection;
    _schedulePageSyncToUiSection();
  }

  void _schedulePageSyncToUiSection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncPageControllerToUiSection();
    });
  }

  /// [jumpToPage] during [build] is unreliable; keep the visible page aligned
  /// with [TableState.uiSelectedSection] after programmatic section changes
  /// (e.g. append) and when section-creation closes.
  void _syncPageControllerToUiSection() {
    if (!_pageController.hasClients) return;
    final tableState = _tableState;
    final sectionSettings = _sectionSettingsState;
    if (tableState.sectionsCount <= 0) return;

    final page = _pageController.page;
    final maxPage = tableState.sectionsCount - 1;
    final target =
        tableState.uiSelectedSection.clamp(0, maxPage);
    final lastSectionIndex = maxPage;
    final swipingTowardCreation = page != null &&
        page > (lastSectionIndex + 0.01) &&
        page < tableState.sectionsCount;
    if (_isUserScrolling) return;
    if (sectionSettings.isSectionCreationOpen) return;
    if (swipingTowardCreation) return;
    if (page == null || page.round() != target) {
      _pageController.jumpToPage(target);
    }
  }

  @override
  void dispose() {
    _tableState.removeListener(_onTableChangedForPageSync);
    _sectionSettingsState.removeListener(_onSectionSettingsChangedForPageSync);
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
          children: [
            // Horizontal scrollable content (sound grids + gutters)
            RepaintBoundary(
              child: Container(
                width: double.infinity,
                height: double.infinity,
                child: _buildHorizontalSectionView(context),
              ),
            ),

            // Fixed left side control positioned above scrollable content
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: MediaQuery.of(context).size.width *
                  (SequencerBody.sideControlWidthPercent / 100.0),
              child: SoundGridSideControlWidget(
                side: SideControlSide.left,
                onOpenNavMenu: widget.onOpenNavMenu,
                onSettings: widget.onSettings,
              ),
            ),

            // Recording overlay removed - recordings now auto-save as messages
            // Section settings moved to multitask panel (no longer an overlay)

            // Value control overlay handled at screen level (to optionally include edit buttons)
          ],
    );
  }

  Widget _buildHorizontalSectionView(BuildContext context) {
    return Consumer<TableState>(
      builder: (context, tableState, child) {
        final playbackState = context.read<PlaybackState>();
        final screenWidth = MediaQuery.of(context).size.width;
        final leftControlWidth =
            screenWidth * (SequencerBody.sideControlWidthPercent / 100.0);
        final itemWidth = screenWidth -
            leftControlWidth; // Sound grid + gutter takes remaining space

        // Create a PageView that shows current section + allows preview of adjacent sections
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollStartNotification) {
              _isUserScrolling = true;
            } else if (notification is ScrollEndNotification) {
              _isUserScrolling = false;
            }
            return false;
          },
          child: Consumer<EditState>(
            builder: (context, editState, _) => PageView.builder(
              key: ValueKey<int>(tableState.sectionsCount),
              controller: _pageController,
              physics: editState.isInSelectionMode
                  ? const NeverScrollableScrollPhysics()
                  : const PageScrollPhysics(),
              onPageChanged: (index) {
                // Only change section when page is fully changed
                if (index < tableState.sectionsCount) {
                  // Jump straight to the settled page index. Stepping through
                  // next/previous sections here can reuse stale playback state
                  // while PageView is still reconciling after section inserts.
                  playbackState.switchToSection(index);
                  // Update UI selection separately (use post-frame callback to avoid setState during build)
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (tableState.uiSelectedSection != index) {
                      tableState.setUiSelectedSection(index);
                    }
                  });
                }
              },
              itemCount:
                  tableState.sectionsCount + 1, // +1 for section creation
              itemBuilder: (context, index) {
                return Container(
                  width: itemWidth,
                  margin: EdgeInsets.only(
                      left:
                          leftControlWidth), // Leave space for fixed left control
                  child: Row(
                    children: [
                      // Sound grid area
                      Expanded(
                        flex: (SequencerBody.soundGridWidthPercent *
                                100 /
                                (SequencerBody.soundGridWidthPercent +
                                    SequencerBody.rightGutterWidthPercent))
                            .round(),
                        child: index < tableState.sectionsCount
                            ? _buildSectionGrid(context, tableState, index)
                            : SectionCreationOverlay(
                                onBack: () {
                                  _pageController.animateToPage(
                                    tableState.uiSelectedSection,
                                    duration: const Duration(milliseconds: 220),
                                    curve: Curves.easeOutCubic,
                                  );
                                },
                              ), // Show creation overlay as last item
                      ),

                      // Right gutter
                      Expanded(
                        flex: (SequencerBody.rightGutterWidthPercent *
                                100 /
                                (SequencerBody.soundGridWidthPercent +
                                    SequencerBody.rightGutterWidthPercent))
                            .round(),
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.sequencerPageBackground,
                            border: Border(
                              right: BorderSide(
                                color: AppColors.sequencerBorder,
                                width: 0.5,
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
          ),
        );
      },
    );
  }

  Widget _buildSectionGrid(
      BuildContext context, TableState tableState, int sectionIndex) {
    // Always show the actual grid widget - for previews, we'll temporarily load the section data
    return Consumer<TableState>(
      builder: (context, state, child) {
        if (sectionIndex == state.uiSelectedSection) {
          // Current section: normal interactive grid
          return const SampleGridWidget();
        } else {
          // Preview section: show grid but non-interactive and with preview data
          return _buildPreviewStackedCards(context, state, sectionIndex);
        }
      },
    );
  }

  Widget _buildPreviewStackedCards(
      BuildContext context, TableState tableState, int sectionIndex) {
    // For current section: use the real widget, for others: simple approach
    if (sectionIndex == tableState.uiSelectedSection) {
      return const SampleGridWidget();
    } else {
      return IgnorePointer(
        child: SampleGridWidget(sectionIndexOverride: sectionIndex),
      );
    }
  }
}
