import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/app_colors.dart';
import '../widgets/library_header_widget.dart';
import '../widgets/bottom_audio_player.dart';
import '../models/playlist_item.dart';
import '../models/thread/message.dart';
import '../state/audio_player_state.dart';
import '../state/library_state.dart';
import '../state/user_state.dart';
import '../services/audio_cache_service.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({Key? key}) : super(key: key);
  
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with TickerProviderStateMixin, AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  late TabController _tabController;
  bool _isCallbackActive = false;
  
  @override
  bool get wantKeepAlive => true;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadPlaylist();
    _setupAudioPlayerCallback();
    WidgetsBinding.instance.addObserver(this);
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle app lifecycle changes
    if (state == AppLifecycleState.resumed && mounted) {
      _setupAudioPlayerCallback();
    } else if (state == AppLifecycleState.paused) {
      _clearAudioPlayerCallback();
    }
  }
  
  Future<void> _loadPlaylist() async {
    final userState = context.read<UserState>();
    final userId = userState.currentUser?.id;
    
    if (userId == null) return;
    
    final libraryState = context.read<LibraryState>();
    
    // Load playlist (only loads once on first call)
    await libraryState.loadPlaylist(userId: userId);
  }
  
  void _setupAudioPlayerCallback() {
    if (_isCallbackActive) return;
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final audioPlayer = context.read<AudioPlayerState>();
      
      // Track completion callback
      audioPlayer.setTrackCompletionCallback(() {
        if (mounted && _isCallbackActive) {
          _playNextTrack(autoAdvance: true);
        }
      });
      
      // Next track callback
      audioPlayer.setNextTrackCallback(() {
        if (mounted && _isCallbackActive) {
          _playNextTrack();
        }
      });
      
      // Previous track callback
      audioPlayer.setPreviousTrackCallback(() {
        if (mounted && _isCallbackActive) {
          _playPreviousTrack();
        }
      });
      
      _isCallbackActive = true;
    });
  }
  
  void _clearAudioPlayerCallback() {
    if (!_isCallbackActive) return;
    
    try {
      final audioPlayer = context.read<AudioPlayerState>();
      audioPlayer.setTrackCompletionCallback(null);
      audioPlayer.setNextTrackCallback(null);
      audioPlayer.setPreviousTrackCallback(null);
      _isCallbackActive = false;
    } catch (_) {}
  }
  
  void _playNextTrack({bool autoAdvance = false}) {
    final libraryState = context.read<LibraryState>();
    final audioPlayer = context.read<AudioPlayerState>();
    final playlist = libraryState.playlist;
    
    if (playlist.isEmpty) return;
    
    final currentRenderId = audioPlayer.currentlyPlayingRenderId;
    if (currentRenderId == null) return;
    
    final currentIndex = playlist.indexWhere((item) => item.id == currentRenderId);
    if (currentIndex == -1) return;
    
    int nextIndex;
    
    // If shuffle is enabled, pick a random track (excluding current)
    if (audioPlayer.shuffleEnabled && playlist.length > 1) {
      do {
        nextIndex = (DateTime.now().millisecondsSinceEpoch % playlist.length);
      } while (nextIndex == currentIndex);
    } else {
      // Normal sequential playback
      nextIndex = currentIndex + 1;
      
      // Handle end of playlist
      if (nextIndex >= playlist.length) {
        if (autoAdvance && audioPlayer.loopMode == LoopMode.playlist) {
          // Loop back to start
          nextIndex = 0;
        } else {
          // Just pause at the end
          audioPlayer.pause();
          return;
        }
      }
    }
    
    final nextItem = playlist[nextIndex];
    _playPlaylistItem(nextItem);
  }
  
  void _playPreviousTrack() {
    final libraryState = context.read<LibraryState>();
    final audioPlayer = context.read<AudioPlayerState>();
    final playlist = libraryState.playlist;
    
    if (playlist.isEmpty) return;
    
    final currentRenderId = audioPlayer.currentlyPlayingRenderId;
    if (currentRenderId == null) return;
    
    final currentIndex = playlist.indexWhere((item) => item.id == currentRenderId);
    if (currentIndex == -1) return;
    
    // If more than 3 seconds into track, restart current track
    if (audioPlayer.position.inSeconds > 3) {
      audioPlayer.seek(Duration.zero);
      return;
    }
    
    int prevIndex;
    
    // If shuffle is enabled, pick a random track (excluding current)
    if (audioPlayer.shuffleEnabled && playlist.length > 1) {
      do {
        prevIndex = (DateTime.now().millisecondsSinceEpoch % playlist.length);
      } while (prevIndex == currentIndex);
    } else {
      // Normal sequential playback
      prevIndex = currentIndex - 1;
      
      // Handle start of playlist
      if (prevIndex < 0) {
        if (audioPlayer.loopMode == LoopMode.playlist) {
          // Loop to end
          prevIndex = playlist.length - 1;
        } else {
          // Just restart current track
          audioPlayer.seek(Duration.zero);
          return;
        }
      }
    }
    
    final prevItem = playlist[prevIndex];
    _playPlaylistItem(prevItem);
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clearAudioPlayerCallback();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    
    return WillPopScope(
      onWillPop: () async {
        // Stop audio when navigating back to ProjectsScreen (handles system back button/swipe)
        try {
          context.read<AudioPlayerState>().stop();
        } catch (_) {}
        return true;
      },
      child: Scaffold(
        backgroundColor: AppColors.sequencerPageBackground,
        body: Column(
        children: [
          Expanded(
            child: SafeArea(
              child: Column(
                children: [
                  // Library header with back button
                  const LibraryHeaderWidget(),
                  
                  // Tab bar
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.sequencerSurfaceRaised,
                      border: Border(
                        bottom: BorderSide(
                          color: AppColors.sequencerBorder,
                          width: 1,
                        ),
                      ),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      tabs: const [
                        Tab(text: 'PLAYLIST'),
                        Tab(text: 'SAMPLES'),
                      ],
                      labelColor: AppColors.sequencerText,
                      unselectedLabelColor: AppColors.sequencerLightText,
                      labelStyle: GoogleFonts.sourceSans3(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                      unselectedLabelStyle: GoogleFonts.sourceSans3(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.5,
                      ),
                      indicatorColor: AppColors.sequencerText,
                      indicatorWeight: 2,
                    ),
                  ),
                  
                  // Tab content
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildPlaylistsTab(),
                        _buildSamplesTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Audio player at the bottom
          const BottomAudioPlayer(),
        ],
      ),
      ),
    );
  }



  Widget _buildPlaylistsTab() {
    return Consumer2<LibraryState, AudioPlayerState>(
      builder: (context, libraryState, audioPlayer, _) {
        // Show loading indicator only on initial load
        if (libraryState.isLoading && !libraryState.hasLoaded) {
          return const Center(child: CircularProgressIndicator());
        }
        
        // Show empty state
        if (libraryState.playlist.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon(
                //   Icons.library_music_outlined,
                //   color: AppColors.sequencerLightText,
                //   size: 48,
                // ),
                // const SizedBox(height: 12),
                Text(
                  'Your playlist is empty',
                  style: GoogleFonts.sourceSans3(
                    color: AppColors.sequencerLightText,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Add audio recordings from projects history',
                  style: GoogleFonts.sourceSans3(
                    color: AppColors.sequencerLightText,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          );
        }
        
        return ListView.builder(
          padding: const EdgeInsets.only(top: 2),
          itemCount: libraryState.playlist.length,
          itemBuilder: (context, index) {
            final item = libraryState.playlist[index];
            final isPlaying = audioPlayer.currentlyPlayingRenderId == item.id && audioPlayer.isPlaying;
        
            return Container(
              height: 60,
              margin: const EdgeInsets.only(bottom: 2),
              decoration: BoxDecoration(
                color: isPlaying 
                    ? AppColors.sequencerAccent.withOpacity(0.1)
                    : AppColors.sequencerSurfaceRaised,
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.sequencerBorder,
                    width: 0.5,
                  ),
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _playPlaylistItem(item),
                  onLongPress: () => _showRemoveDialog(item),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        // Static note icon (no circle background)
                        Icon(
                          Icons.music_note,
                          color: AppColors.sequencerText,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        
                        // Item info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.name,
                                      style: GoogleFonts.sourceSans3(
                                        color: AppColors.sequencerText,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  // Upload indicator
                                  if (item.uploadStatus == RenderUploadStatus.uploading) ...[
                                    const SizedBox(width: 4),
                                    SizedBox(
                                      width: 10,
                                      height: 10,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.5,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          AppColors.sequencerLightText.withOpacity(0.5),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (item.duration != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  _formatDuration(item.duration!),
                                  style: GoogleFonts.sourceSans3(
                                    color: AppColors.sequencerLightText,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        
                        const SizedBox(width: 8),
                        
                        // Share button (disabled if still uploading or invalid URL)
                        Builder(
                          builder: (buttonContext) => IconButton(
                            icon: Icon(
                              Icons.share,
                              color: (item.uploadStatus == RenderUploadStatus.uploading || 
                                     item.url.isEmpty || 
                                     !item.url.startsWith('http'))
                                  ? AppColors.sequencerLightText.withOpacity(0.3)
                                  : AppColors.sequencerLightText,
                              size: 20,
                            ),
                            onPressed: (item.uploadStatus == RenderUploadStatus.uploading || 
                                       item.url.isEmpty || 
                                       !item.url.startsWith('http'))
                                ? null
                                : () => _sharePlaylistItem(item, buttonContext),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 40,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
  
  String _formatDuration(double duration) {
    final minutes = (duration / 60).floor();
    final seconds = (duration % 60).floor();
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
  
  Future<void> _playPlaylistItem(PlaylistItem item) async {
    final audioPlayer = context.read<AudioPlayerState>();
    
    // Debug: Only log when ID issues detected
    if (item.id.isEmpty) {
      debugPrint('⚠️ [LIBRARY] Playing item "${item.name}" with EMPTY ID!');
    }
    
    // Create a minimal Render object for playback
    final render = Render(
      id: item.id,
      url: item.url,
      format: item.format,
      bitrate: item.bitrate,
      duration: item.duration,
      sizeBytes: item.sizeBytes,
      createdAt: item.createdAt,
      localPath: item.localPath, // For instant playback!
      uploadStatus: item.uploadStatus,
    );
    
    await audioPlayer.playRender(
      messageId: 'playlist', // Use 'playlist' as a special message ID
      render: render,
      localPathIfRecorded: item.localPath, // Use local file if available
    );
  }
  
  void _showRemoveDialog(PlaylistItem item) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.sequencerSurfaceRaised,
          title: Text(
            'Remove from Playlist',
            style: GoogleFonts.sourceSans3(
              color: AppColors.sequencerText,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            'Are you sure you want to remove "${item.name}" from your playlist?',
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
                _removeFromPlaylist(item);
              },
              child: Text(
                'Remove',
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
  
  Future<void> _removeFromPlaylist(PlaylistItem item) async {
    final userState = context.read<UserState>();
    final userId = userState.currentUser?.id;
    
    if (userId == null) return;
    
    final libraryState = context.read<LibraryState>();
    final success = await libraryState.removeFromPlaylist(
      userId: userId,
      renderId: item.id,
    );
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Removed from playlist' : 'Failed to remove'),
          backgroundColor: success ? AppColors.sequencerAccent : Colors.red.shade900,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }
  
  Future<void> _sharePlaylistItem(PlaylistItem item, BuildContext buttonContext) async {
    try {
      // Check if track is still uploading
      if (item.uploadStatus == RenderUploadStatus.uploading) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Track is still uploading. Please wait...'),
              backgroundColor: AppColors.sequencerAccent,
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return;
      }
      
      // Check if URL is valid
      if (item.url.isEmpty || !item.url.startsWith('http')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Track URL is not available'),
              backgroundColor: Colors.red.shade900,
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return;
      }
      
      // Get local file path - check cache first, download if needed
      String? localPath = item.localPath;
      
      // If not in localPath, check if it's cached
      if (localPath == null || !await File(localPath).exists()) {
        localPath = await AudioCacheService.getCachedPath(item.url);
      }
      
      // If still not available, download it with progress dialog
      if (localPath == null || !await File(localPath).exists()) {
        if (!mounted) return;
        
        // Show downloading dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext dialogContext) {
            return _DownloadingDialog(trackName: item.name);
          },
        );
        
        // Download from S3
        localPath = await AudioCacheService.downloadAndCache(item.url);
        
        // Close downloading dialog
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        
        if (localPath == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Failed to download track'),
                backgroundColor: Colors.red.shade900,
                duration: const Duration(seconds: 2),
              ),
            );
          }
          return;
        }
      }
      
      // Calculate the share button position for iOS
      final box = buttonContext.findRenderObject() as RenderBox?;
      final Rect sharePositionOrigin = box == null
          ? Rect.fromLTWH(0, 0, 100, 100) // Fallback position
          : box.localToGlobal(Offset.zero) & box.size;
      
      // Share the actual audio file (not just URL)
      final xFile = XFile(localPath);
      await Share.shareXFiles(
        [xFile],
        subject: item.name,
        text: item.name,
        sharePositionOrigin: sharePositionOrigin,
      );
      
      debugPrint('✅ [LIBRARY] Shared file: $localPath');
    } catch (e) {
      debugPrint('❌ Failed to share playlist item: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to share: $e'),
            backgroundColor: Colors.red.shade900,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Widget _buildSamplesTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon(
          //   Icons.music_note,
          //   color: AppColors.sequencerLightText,
          //   size: 48,
          // ),
          // const SizedBox(height: 12),
          Text(
            'Samples',
            style: GoogleFonts.sourceSans3(
              color: AppColors.sequencerLightText,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Coming soon',
            style: GoogleFonts.sourceSans3(
              color: AppColors.sequencerLightText,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// Downloading dialog widget
class _DownloadingDialog extends StatelessWidget {
  final String trackName;
  
  const _DownloadingDialog({required this.trackName});
  
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.sequencerSurfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Spinner
            SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                color: AppColors.sequencerText,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 20),
            // Message
            Text(
              'Downloading track',
              style: GoogleFonts.sourceSans3(
                color: AppColors.sequencerText,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              trackName,
              style: GoogleFonts.sourceSans3(
                color: AppColors.sequencerLightText,
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
} 