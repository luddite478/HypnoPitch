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
  final VoidCallback? onBack;
  final VoidCallback? onSettings;
  final VoidCallback? onRecordings;

  const SequencerBody({
    super.key,
    this.onBack,
    this.onSettings,
    this.onRecordings,
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

  @override
  void initState() {
    super.initState();
    final initialPage = context.read<TableState>().uiSelectedSection;
    _pageController = PageController(
      initialPage: initialPage,
      viewportFraction: 1.0,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Selector<
        TableState,
        ({
          bool isSectionControlOpen,
          bool isSectionCreationOpen,
          int numSections,
          int currentIndex
        })>(
      selector: (context, tableState) => (
        isSectionControlOpen: false, // Moved to SectionSettingsState
        isSectionCreationOpen: false, // Moved to SectionSettingsState
        numSections: tableState.sectionsCount,
        currentIndex: tableState.uiSelectedSection,
      ),
      builder: (context, data, child) {
        final sectionSettings = context.watch<SectionSettingsState>();
        // Keep PageView in sync with current section during song mode auto-advance
        if (_pageController.hasClients) {
          final double? page = _pageController.page;
          final bool atTarget =
              page != null ? page.round() == data.currentIndex : false;
          final bool swipingTowardCreation =
              page != null && page > (data.numSections - 1) - 0.01;
          final bool creationOpen = sectionSettings.isSectionCreationOpen;

          if (!atTarget &&
              !_isUserScrolling &&
              !creationOpen &&
              !swipingTowardCreation) {
            _pageController.jumpToPage(data.currentIndex);
          }
        }

        // Always render base stack and conditionally layer overlay menus so left panel remains visible
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
                onBack: widget.onBack,
                onSettings: widget.onSettings,
                onRecordings: widget.onRecordings,
              ),
            ),

            // Recording overlay removed - recordings now auto-save as messages
            // Section settings moved to multitask panel (no longer an overlay)

            // Value control overlay handled at screen level (to optionally include edit buttons)
          ],
        );
      },
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
              controller: _pageController,
              physics: editState.isInSelectionMode
                  ? const NeverScrollableScrollPhysics()
                  : const PageScrollPhysics(),
              onPageChanged: (index) {
                // Only change section when page is fully changed
                if (index < tableState.sectionsCount) {
                  // Switch both playback (sound) and UI (visuals) separately
                  final currentIndex = tableState.uiSelectedSection;
                  if (index > currentIndex) {
                    // Moving forward - update both playback and UI
                    for (int i = currentIndex; i < index; i++) {
                      playbackState.switchToNextSection();
                    }
                  } else if (index < currentIndex) {
                    // Moving backward - update both playback and UI
                    for (int i = currentIndex; i > index; i--) {
                      playbackState.switchToPreviousSection();
                    }
                  }
                  // Update UI selection separately (use post-frame callback to avoid setState during build)
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    tableState.setUiSelectedSection(index);
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
