import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../state/threads_state.dart';
import '../../../state/audio_player_state.dart';
import '../../../services/audio_cache_service.dart';
import '../../../models/thread/thread.dart';
import '../../../models/thread/message.dart';
import '../../../models/thread/thread_user.dart';
import '../../../utils/app_colors.dart';
import '../../sequencer/v2/message_sections_chain.dart';

typedef MessageContextMenuCallback = void Function(BuildContext context, Message message, Offset globalPosition);
typedef ApplyMessageCallback = void Function(BuildContext context, Message message);
typedef AddToLibraryCallback = void Function(BuildContext context, Render render);

class ThreadViewWidget extends StatefulWidget {
  final ScrollController scrollController;
  final bool isLoadingOlderMessages;
  final MessageContextMenuCallback onShowMessageContextMenu;
  final ApplyMessageCallback onApplyMessage;
  final AddToLibraryCallback onAddToLibrary;

  const ThreadViewWidget({
    super.key,
    required this.scrollController,
    required this.isLoadingOlderMessages,
    required this.onShowMessageContextMenu,
    required this.onApplyMessage,
    required this.onAddToLibrary,
  });

  @override
  State<ThreadViewWidget> createState() => _ThreadViewWidgetState();
}

class _ThreadViewWidgetState extends State<ThreadViewWidget> {
  final GlobalKey<AnimatedListState> _animatedListKey = GlobalKey<AnimatedListState>();
  List<Message> _displayedMessages = [];
  String? _optimisticRenderKey;
  String? _highlightedRenderKey; // Track newly added recording for highlight
  
  // Configurable chat alignment percentages
  static const double singleUserLeftMarginPercent = 0.02; // 2% left margin for single user
  static const double currentUserLeftMarginPercent = 0.02; // 2% left margin for current user (multi-user)
  static const double otherUserRightMarginPercent = 0.02; // 2% right margin for other users
  static const double layer3WidthPercent = 0.975; // Layer 3 (sections + buttons) is 90% of message width
  
  // Color controls for all 3 message levels
  static const Color messageHeaderColor = Colors.transparent; // Layer 1: Header background color (transparent for lighter feel)
  static const Color messageRenderColor = Color.fromARGB(255, 70, 67, 67); // Layer 2: Render player background color
  static const double messageRenderOpacity = 0.3; // Opacity of render player background
  static const Color messageChainContainerColor = Color.fromARGB(255, 239, 236, 236); // Layer 3: Chain+buttons container background color
  static const double messageChainContainerOpacity = 0.05; // Opacity of chain+buttons container (0.0 to 1.0)
  
  // Chain divider controls
  static const Color chainDividerColor = Color.fromARGB(255, 95, 95, 95); // Light gray color for section dividers
  static const double chainDividerWidth = 1.0; // Width of dividers
  static const bool showChainDividers = true; // Enable/disable dividers
  static const int chainDividerSpacingLayers = 4; // Number of layers to use for calculating divider spacing (default: 4 layers)
    
  // Padding controls
  static const double chainInternalVerticalPadding = 0.0; // Vertical padding inside chain rectangles (top and bottom of numbers)
  static const double chainContainerHeight = 40.0; // Height of the chain container
  
  // Padding controls for chain element inside yellow container (top, left, bottom, right)
  static const double chainElementPaddingTop = 7.0;
  static const double chainElementPaddingLeft = 10.0;
  static const double chainElementPaddingBottom = 0.0;
  static const double chainElementPaddingRight = 10.0;
  
  // Padding controls for buttons inside yellow container (top, left, bottom, right)
  static const double buttonsPaddingTop = 2.0;
  static const double buttonsPaddingBottom = 1.0;
  static const double buttonsPaddingLeft = 10.0;
  static const double buttonsPaddingRight = 10.0;
  
  // Button color controls
  static const Color loadButtonBackgroundColor = Color.fromARGB(255, 84, 84, 81); // Load button background color
  static const double loadButtonBackgroundOpacity = 0.4; // Load button background opacity
  static const Color loadButtonForegroundColor = AppColors.sequencerText; // Load button text color
  
  // Spacing between messages
  static const double messageSpacing = 20.0;
 


  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.sequencerSurfaceRaised,
      child: Consumer<ThreadsState>(
        builder: (context, threadsState, child) {
          final thread = threadsState.activeThread;
          final messages = threadsState.activeThreadMessages;

          if (thread == null) {
            return Center(
              child: Text(
                'No active thread',
                style: GoogleFonts.sourceSans3(
                  color: AppColors.sequencerText,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            );
          }

          if (messages.isEmpty && threadsState.isLoadingMessages(thread.id)) {
            return Center(
              child: CircularProgressIndicator(color: AppColors.sequencerAccent),
            );
          }

          // Reset displayed messages when empty
          if (messages.isEmpty && _displayedMessages.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _displayedMessages = [];
                });
              }
            });
          }

          // Detect new messages and animate them in
          _updateDisplayedMessages(messages, threadsState);

          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final allMessagesToday = _displayedMessages.isEmpty || _displayedMessages.every((msg) {
            final msgDate = DateTime(msg.timestamp.year, msg.timestamp.month, msg.timestamp.day);
            return msgDate == today;
          });

          return Stack(
            children: [
              AnimatedList(
                key: _animatedListKey,
                controller: widget.scrollController,
                reverse: true,
                padding: const EdgeInsets.only(
                  top: 8,
                  left: 12,
                  right: 12,
                  bottom: 52,
                ),
                initialItemCount: _displayedMessages.length + (widget.isLoadingOlderMessages ? 1 : 0),
                itemBuilder: (context, index, animation) {
                  if (index == _displayedMessages.length) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: CircularProgressIndicator(color: AppColors.sequencerAccent),
                      ),
                    );
                  }

                  final reversedIndex = _displayedMessages.length - 1 - index;
                  final message = _displayedMessages[reversedIndex];
                  final isCurrentUser = message.userId == threadsState.currentUserId;

                  bool needsDivider = false;
                  if (!allMessagesToday) {
                    if (reversedIndex == _displayedMessages.length - 1) {
                      needsDivider = true;
                    } else if (reversedIndex == 0) {
                      needsDivider = true;
                    } else if (reversedIndex > 0) {
                      final olderMessage = _displayedMessages[reversedIndex - 1];
                      needsDivider = _needsDayDivider(olderMessage.timestamp, message.timestamp);
                    }
                  }

                  Widget bubble = _buildMessageBubble(context, thread, message, isCurrentUser);

                  if (needsDivider) {
                    bubble = Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildDayDivider(message.timestamp),
                        const SizedBox(height: 8),
                        bubble,
                      ],
                    );
                  }

                  return _buildMessageAnimation(bubble, animation, isNewMessage: index == 0);
                },
              ),
              if (_displayedMessages.isEmpty)
                Positioned.fill(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'No checkpoints yet',
                          style: GoogleFonts.sourceSans3(
                            color: AppColors.sequencerText,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _updateDisplayedMessages(List<Message> newMessages, ThreadsState threadsState) {
    if (_displayedMessages.length < newMessages.length) {
      final animatedList = _animatedListKey.currentState;
      
      if (animatedList != null) {
        final List<Message> newlyAdded = newMessages.sublist(_displayedMessages.length);
        
        for (int i = 0; i < newlyAdded.length; i++) {
          final message = newlyAdded[i];
          _displayedMessages.add(message);
          
          // Highlight new recordings (defer to avoid setState during build)
          if (message.renders.isNotEmpty) {
            final render = message.renders.first;
            final renderKey = '${message.id}::${render.id}';
            
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _highlightedRenderKey = renderKey;
                });
                
                // Clear highlight after 3 seconds
                Future.delayed(const Duration(seconds: 3), () {
                  if (mounted && _highlightedRenderKey == renderKey) {
                    setState(() {
                      _highlightedRenderKey = null;
                    });
                  }
                });
              }
            });
          }
          
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              animatedList.insertItem(0, duration: const Duration(milliseconds: 350));
              
              // Scroll to show the new message at the bottom (position 0 in reverse list)
              // Delay slightly to ensure the animation has started and the item has height
              Future.delayed(const Duration(milliseconds: 50), () {
                if (mounted && widget.scrollController.hasClients) {
                  widget.scrollController.animateTo(
                    0.0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  );
                }
              });
            }
          });
        }
      } else {
        // AnimatedList not ready yet, just set messages directly
        _displayedMessages = List.from(newMessages);
        // Scroll to bottom once AnimatedList is ready
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && widget.scrollController.hasClients) {
            widget.scrollController.jumpTo(0.0);
          }
        });
      }
    } else if (_displayedMessages.length > newMessages.length) {
      final animatedList = _animatedListKey.currentState;
      
      if (animatedList != null) {
        final thread = threadsState.activeThread;
        final currentUserId = threadsState.currentUserId;
        
        if (thread != null) {
          final removedIndices = <int>[];
          for (int i = 0; i < _displayedMessages.length; i++) {
            final msg = _displayedMessages[i];
            if (!newMessages.any((m) => m.id == msg.id)) {
              removedIndices.add(i);
            }
          }
          
          for (int i = removedIndices.length - 1; i >= 0; i--) {
            final removedIndex = removedIndices[i];
            final removedMessage = _displayedMessages[removedIndex];
            final isCurrentUser = removedMessage.userId == currentUserId;
            
            animatedList.removeItem(
              removedIndex,
              (context, animation) => SizeTransition(
                sizeFactor: animation,
                child: FadeTransition(
                  opacity: animation,
                  child: _buildMessageBubble(
                    context,
                    thread,
                    removedMessage,
                    isCurrentUser,
                  ),
                ),
              ),
              duration: const Duration(milliseconds: 250),
            );
          }
        }
        
        _displayedMessages = List.from(newMessages);
      } else {
        _displayedMessages = List.from(newMessages);
      }
    } else {
      bool isDifferent = false;
      for (int i = 0; i < newMessages.length; i++) {
        final oldMsg = _displayedMessages[i];
        final newMsg = newMessages[i];
        
        if (oldMsg.id != newMsg.id) {
          isDifferent = true;
          break;
        }
        
        if (oldMsg.renders.length != newMsg.renders.length) {
          isDifferent = true;
          break;
        }
        
        for (int j = 0; j < oldMsg.renders.length; j++) {
          if (oldMsg.renders[j].uploadStatus != newMsg.renders[j].uploadStatus ||
              oldMsg.renders[j].id != newMsg.renders[j].id ||
              oldMsg.renders[j].url != newMsg.renders[j].url) {
            isDifferent = true;
            break;
          }
        }
        if (isDifferent) break;
      }
      
      if (isDifferent) {
        _displayedMessages = List.from(newMessages);
      }
    }
  }

  Widget _buildMessageAnimation(Widget child, Animation<double> animation, {bool isNewMessage = false}) {
    if (!isNewMessage) {
      return child;
    }
    
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.3),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      )),
      child: FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: Curves.easeIn,
        ),
        child: child,
      ),
    );
  }

  Widget _buildMessageBubble(
    BuildContext context,
    Thread thread,
    Message message,
    bool isCurrentUser,
  ) {
    final userName = thread.users.firstWhere(
      (u) => u.id == message.userId,
      orElse: () => ThreadUser(
        id: message.userId,
        username: 'user_${message.userId.substring(0, 6)}',
        name: '',
        joinedAt: DateTime.now(),
      ),
    ).name;

    final shouldShowUsername = userName.isNotEmpty && thread.users.length > 1;
    final isMultiUser = thread.users.length > 1;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) => widget.onShowMessageContextMenu(context, message, details.globalPosition),
      onLongPressStart: (details) => widget.onShowMessageContextMenu(context, message, details.globalPosition),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Calculate margins based on chat type and user
          final double leftMargin;
          final double rightMargin;
          
          if (!isMultiUser) {
            // Single user: small left margin for all messages
            leftMargin = constraints.maxWidth * singleUserLeftMarginPercent;
            rightMargin = 0;
          } else if (isCurrentUser) {
            // Multi-user, current user: small left margin, align right
            leftMargin = constraints.maxWidth * currentUserLeftMarginPercent;
            rightMargin = 0;
          } else {
            // Multi-user, other user: small right margin, align left
            leftMargin = 0;
            rightMargin = constraints.maxWidth * otherUserRightMarginPercent;
          }

          return Container(
            margin: EdgeInsets.only(
              left: leftMargin,
              right: rightMargin,
              bottom: messageSpacing,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Layer 1: Header (username + timestamp) - transparent background, no borders
                Container(
                  decoration: BoxDecoration(
                    color: messageHeaderColor,
                    borderRadius: message.renders.isEmpty 
                        ? const BorderRadius.only(
                            topLeft: Radius.circular(2),
                            topRight: Radius.circular(2),
                            bottomLeft: Radius.circular(2),
                            bottomRight: Radius.circular(2),
                          )
                        : const BorderRadius.only(
                            topLeft: Radius.circular(2),
                            topRight: Radius.circular(2),
                          ),
                  ),
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (shouldShowUsername) ...[
                        Text(
                          userName,
                          style: GoogleFonts.sourceSans3(
                            color: const Color.fromARGB(255, 240, 238, 230).withOpacity(0.85),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (message.sendStatus == SendStatus.failed && isCurrentUser) ...[
                        Icon(Icons.error, color: AppColors.sequencerAccent, size: 16),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        _formatTimestamp(message.timestamp),
                        style: GoogleFonts.sourceSans3(
                          color: const Color.fromARGB(255, 240, 238, 230).withOpacity(0.7),
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Layer 2: Optional render audio bar - light transparent background
                if (message.renders.isNotEmpty)
                  for (final render in message.renders)
                    Container(
                      decoration: BoxDecoration(
                        color: messageRenderColor.withOpacity(messageRenderOpacity),
                        borderRadius: const BorderRadius.all(Radius.circular(6)),
                        border: Border.all(
                          color: AppColors.sequencerBorder.withOpacity(0.2),
                          width: 0.5,
                        ),
                      ),
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Center(
                        child: _buildRenderButton(context, message, render),
                      ),
                    ),
                
                // Layer 3: Sections chain + buttons (90% width, shifted based on user)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final bottomElementWidth = constraints.maxWidth * layer3WidthPercent;
                    // Move the entire parent container: right for current user, left for other participants
                    return Align(
                      alignment: isCurrentUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        width: bottomElementWidth,
                      decoration: BoxDecoration(
                        color: messageChainContainerColor.withOpacity(messageChainContainerOpacity),
                        borderRadius: const BorderRadius.all(Radius.circular(6)),
                        border: Border.all(
                          color: AppColors.sequencerBorder.withOpacity(0.15),
                          width: 0.5,
                        ),
                      ),
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Chain element with controllable padding
                          Padding(
                            padding: EdgeInsets.only(
                              top: chainElementPaddingTop,
                              left: chainElementPaddingLeft,
                              bottom: chainElementPaddingBottom,
                              right: chainElementPaddingRight,
                            ),
                            child: _buildMessagePreviewFromMetadata(message),
                          ),
                          // Buttons row with controllable padding
                          Padding(
                            padding: EdgeInsets.only(
                              top: buttonsPaddingTop,
                              left: buttonsPaddingLeft,
                              bottom: buttonsPaddingBottom,
                              right: buttonsPaddingRight,
                            ),
                            child: ElevatedButton(
                              onPressed: () => widget.onApplyMessage(context, message),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: loadButtonBackgroundColor.withOpacity(loadButtonBackgroundOpacity),
                                foregroundColor: loadButtonForegroundColor,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                                minimumSize: const Size(double.infinity, 30),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              child: const Text(
                                'Load',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ],
                      ),
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMessagePreviewFromMetadata(Message message) {
    final meta = message.snapshotMetadata ?? const {};
    final sectionsCount = (meta['sections_count'] as num?)?.toInt() ?? 0;
    final stepsPerSectionMeta = (meta['sections_steps'] as List?)?.map((e) => (e as num).toInt()).toList() ?? const <int>[];
    final loopsMeta = (meta['sections_loops_num'] as List?)?.map((e) => (e as num).toInt()).toList() ?? const <int>[];
    final layersMeta = (meta['layers'] as List?)?.map((e) => (e as num).toInt()).toList() ?? const <int>[];

    final loopsTrimmed = loopsMeta.length >= sectionsCount
        ? loopsMeta.take(sectionsCount).toList()
        : List<int>.from(loopsMeta)..addAll(List<int>.filled(sectionsCount - loopsMeta.length, loopsMeta.isNotEmpty ? loopsMeta.last : 4));

    final int defaultLayersPerSection = (layersMeta.isNotEmpty ? layersMeta.first : 4);
    final layersTrimmed = layersMeta.length >= sectionsCount
        ? layersMeta.take(sectionsCount).toList()
        : List<int>.from(layersMeta)..addAll(List<int>.filled(sectionsCount - layersMeta.length, defaultLayersPerSection));

    final stepsPerSectionTrimmed = () {
      if (stepsPerSectionMeta.isEmpty) return List<int>.filled(sectionsCount, 16);
      if (stepsPerSectionMeta.length >= sectionsCount) {
        return stepsPerSectionMeta.take(sectionsCount).toList();
      }
      final list = List<int>.from(stepsPerSectionMeta);
      list.addAll(List<int>.filled(sectionsCount - stepsPerSectionMeta.length, stepsPerSectionMeta.last));
      return list;
    }();

    return Container(
      height: chainContainerHeight, // Controllable height of chain container
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceRaised,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: AppColors.sequencerBorder, width: 0.5),
      ),
        child: MessageSectionsChain(
          sectionsCount: sectionsCount,
          stepsPerSection: stepsPerSectionTrimmed,
          loopsPerSection: loopsTrimmed,
          layersPerSection: layersTrimmed,
          verticalPadding: chainInternalVerticalPadding, // Controllable vertical padding inside chain rectangles
          dividerColor: chainDividerColor, // Light gray dividers
          dividerWidth: chainDividerWidth, // Divider width
          showDividers: showChainDividers, // Enable/disable dividers
          dividerSpacingLayers: chainDividerSpacingLayers, // Number of layers for divider spacing
        ),
    );
  }

  Widget _buildRenderButton(BuildContext context, Message message, Render render) {
    final isUploading = render.uploadStatus == RenderUploadStatus.uploading;
    final isFailed = render.uploadStatus == RenderUploadStatus.failed;
    final hasLocalFile = render.localPath != null;
    final isConverting = hasLocalFile && render.localPath!.endsWith('.wav');
    
    // Allow playback if we have a local file, even during upload or after failure
    final isPlayable = hasLocalFile || (!isUploading && !isFailed);
    
    return Consumer<AudioPlayerState>(
      builder: (context, audioPlayer, _) {
        final isPlaying = audioPlayer.isPlayingRender(message.id, render.id);
        final isLoadingFromNetwork = audioPlayer.isLoadingRender(message.id, render.id);
        final isThisRender = audioPlayer.currentlyPlayingMessageId == message.id && 
                             audioPlayer.currentlyPlayingRenderId == render.id;
        
        return FutureBuilder<bool>(
          future: (isUploading || isFailed) ? Future.value(false) : AudioCacheService.isCached(render.url),
          builder: (context, snapshot) {
            final renderKey = '${message.id}::${render.id}';
            final bool isOptimistic = _optimisticRenderKey == renderKey;
            
            if (isOptimistic) {
              final shouldClear = (isThisRender && isPlaying) || (!isThisRender && !isLoadingFromNetwork);
              if (shouldClear) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() { _optimisticRenderKey = null; });
                  }
                });
              }
            }
            
            // Don't show loading if we have a local file (instant playback!)
            final bool showLoading = (isUploading && !hasLocalFile) || (isLoadingFromNetwork && !isThisRender && !isOptimistic);
            final bool isHighlighted = _highlightedRenderKey == renderKey;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              decoration: isFailed 
                  ? BoxDecoration(
                      color: AppColors.sequencerAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: AppColors.sequencerAccent,
                        width: 0.5,
                      ),
                    )
                  : isHighlighted
                      ? BoxDecoration(
                          color: AppColors.sequencerAccent.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: AppColors.sequencerAccent.withOpacity(0.3),
                            width: 1.0,
                          ),
                        )
                      : null,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: !isPlayable ? null : () async {
                      final player = context.read<AudioPlayerState>();
                      if (isThisRender && isPlaying) {
                        setState(() { _optimisticRenderKey = null; });
                        await player.playRender(
                          messageId: message.id,
                          render: render,
                          localPathIfRecorded: render.localPath,
                        );
                      } else {
                        setState(() { _optimisticRenderKey = renderKey; });
                        await player.playRender(
                          messageId: message.id,
                          render: render,
                          localPathIfRecorded: render.localPath,
                        );
                      }
                    },
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: isFailed
                            ? AppColors.sequencerAccent
                            : showLoading
                                ? AppColors.sequencerBorder.withOpacity(0.5)
                                : AppColors.sequencerText.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: isFailed
                          ? Icon(Icons.error, color: AppColors.sequencerText, size: 16)
                          : showLoading
                              ? Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.sequencerLightText,
                                    value: isLoadingFromNetwork && audioPlayer.downloadProgress > 0 
                                        ? audioPlayer.downloadProgress 
                                        : null,
                                  ),
                                )
                              : Icon(
                                  (isPlaying || (isOptimistic && isThisRender)) ? Icons.pause : Icons.play_arrow,
                                  color: AppColors.sequencerPageBackground,
                                  size: 16,
                                ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: isFailed
                        ? Text(
                            'Upload failed - file too large or network error',
                            style: GoogleFonts.sourceSans3(
                              color: AppColors.sequencerAccent,
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                            ),
                          )
                        : isConverting
                            ? Row(
                                children: [
                                  SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.sequencerLightText,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Converting to MP3...',
                                    style: GoogleFonts.sourceSans3(
                                      color: AppColors.sequencerLightText,
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              )
                            : (isUploading && !hasLocalFile)
                            ? Row(
                                children: [
                                  Text(
                                    'Uploading...',
                                    style: GoogleFonts.sourceSans3(
                                      color: AppColors.sequencerLightText,
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Container(
                                      height: 2,
                                      decoration: BoxDecoration(
                                        color: AppColors.sequencerBorder.withOpacity(0.3),
                                        borderRadius: BorderRadius.circular(1),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : isThisRender
                                ? SliderTheme(
                                    data: SliderThemeData(
                                      trackHeight: 2,
                                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                                      activeTrackColor: AppColors.sequencerText.withOpacity(0.6),
                                      inactiveTrackColor: AppColors.sequencerBorder.withOpacity(0.3),
                                      thumbColor: AppColors.sequencerText,
                                      overlayColor: AppColors.sequencerText.withOpacity(0.1),
                                    ),
                                    child: Slider(
                                      value: audioPlayer.duration.inMilliseconds > 0
                                          ? audioPlayer.position.inMilliseconds.toDouble()
                                          : 0.0,
                                      min: 0.0,
                                      max: audioPlayer.duration.inMilliseconds.toDouble().clamp(1.0, double.infinity),
                                      onChanged: (value) async {
                                        final player = context.read<AudioPlayerState>();
                                        await player.seek(Duration(milliseconds: value.toInt()));
                                      },
                                    ),
                                  )
                                : Container(
                                    height: 2,
                                    decoration: BoxDecoration(
                                      color: AppColors.sequencerBorder.withOpacity(0.3),
                                      borderRadius: BorderRadius.circular(1),
                                    ),
                                  ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: !isPlayable ? null : () => widget.onAddToLibrary(context, render),
                    child: Icon(
                      Icons.playlist_add,
                      color: !isPlayable
                          ? AppColors.sequencerLightText.withOpacity(0.3)
                          : AppColors.sequencerText,
                      size: 26,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(timestamp.year, timestamp.month, timestamp.day);
    
    final timeStr = '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    
    if (messageDate == today) {
      return timeStr;
    } else if (messageDate == yesterday) {
      return 'Yesterday at $timeStr';
    } else {
      return '${timestamp.day.toString().padLeft(2, '0')}/${timestamp.month.toString().padLeft(2, '0')}/${timestamp.year}, $timeStr';
    }
  }

  bool _needsDayDivider(DateTime previous, DateTime current) {
    final prevDate = DateTime(previous.year, previous.month, previous.day);
    final currDate = DateTime(current.year, current.month, current.day);
    return prevDate != currDate;
  }

  Widget _buildDayDivider(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(timestamp.year, timestamp.month, timestamp.day);
    
    String dateLabel;
    if (messageDate == today) {
      dateLabel = 'Today';
    } else if (messageDate == yesterday) {
      dateLabel = 'Yesterday';
    } else {
      final months = ['January', 'February', 'March', 'April', 'May', 'June', 
                     'July', 'August', 'September', 'October', 'November', 'December'];
      dateLabel = '${timestamp.day} ${months[timestamp.month - 1]} ${timestamp.year}';
    }
    
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1,
            color: AppColors.sequencerBorder.withOpacity(0.2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            dateLabel,
            style: GoogleFonts.sourceSans3(
              color: const Color.fromARGB(255, 240, 238, 230).withOpacity(0.6),
              fontSize: 11,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 1,
            color: AppColors.sequencerBorder.withOpacity(0.2),
          ),
        ),
      ],
    );
  }
}

