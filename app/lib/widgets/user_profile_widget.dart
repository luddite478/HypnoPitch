import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/users_service.dart';
import '../utils/app_colors.dart';
import '../models/playlist_item.dart';
import '../models/thread/message.dart';
import '../state/audio_player_state.dart';

class UserProfileWidget extends StatefulWidget {
  final String userId;
  final String userName;
  final bool isOnline;

  const UserProfileWidget({
    Key? key,
    required this.userId,
    required this.userName,
    this.isOnline = false,
  }) : super(key: key);

  @override
  State<UserProfileWidget> createState() => _UserProfileWidgetState();
}

class _UserProfileWidgetState extends State<UserProfileWidget> with TickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  UserProfile? _userProfile;
  bool _isLoading = true;
  String? _error;
  bool _isCallbackActive = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadUserProfile();
    _setupAudioPlayerCallback();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clearAudioPlayerCallback();
    _tabController.dispose();
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Clear callback when app goes to background
    if (state == AppLifecycleState.paused) {
      _clearAudioPlayerCallback();
    } else if (state == AppLifecycleState.resumed && mounted) {
      _setupAudioPlayerCallback();
    }
  }
  
  void _setupAudioPlayerCallback() {
    if (_isCallbackActive) return; // Don't set up if already active
    
    // Set up callback for auto-advance when track completes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final audioPlayer = context.read<AudioPlayerState>();
      audioPlayer.setTrackCompletionCallback(() {
        if (mounted && _isCallbackActive) {
          _playNextTrack();
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
      _isCallbackActive = false;
    } catch (_) {}
  }
  
  void _playNextTrack() {
    final audioPlayer = context.read<AudioPlayerState>();
    final playlist = _userProfile?.playlist ?? [];
    
    if (playlist.isEmpty) return;
    
    // Find current track index
    final currentRenderId = audioPlayer.currentlyPlayingRenderId;
    if (currentRenderId == null) return;
    
    final currentIndex = playlist.indexWhere((item) => item.id == currentRenderId);
    if (currentIndex == -1) return;
    
    // Move to next track (or just pause at the end, don't close player)
    final nextIndex = currentIndex + 1;
    if (nextIndex >= playlist.length) {
      // Just pause - keep the player visible
      audioPlayer.pause();
      return;
    }
    
    // Play next track
    final nextItem = playlist[nextIndex];
    _playPlaylistItem(nextItem);
  }

  Future<void> _loadUserProfile() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      // Load user profile
      final profile = await UsersService.getUserProfile(widget.userId);

      setState(() {
        _userProfile = profile;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Tab bar
        _buildTabBar(),
        
        // Tab content
        Expanded(
          child: _isLoading
              ? Center(
                  child: CircularProgressIndicator(color: AppColors.menuLightText),
                )
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, color: AppColors.menuLightText, size: 48),
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            style: TextStyle(
                              color: AppColors.menuLightText,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: _loadUserProfile,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.menuButtonBackground,
                            ),
                            child: Text(
                              'RETRY',
                              style: TextStyle(
                                color: AppColors.menuText,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildPlaylistsTab(),
                        _buildSamplesTab(),
                      ],
                    ),
        ),
      ],
    );
  }



  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.menuEntryBackground,
        border: Border(
          bottom: BorderSide(
            color: AppColors.menuBorder,
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
        labelColor: AppColors.menuText,
        unselectedLabelColor: AppColors.menuLightText,
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 1.5,
        ),
        indicatorColor: AppColors.menuText,
        indicatorWeight: 2,
      ),
    );
  }


  Widget _buildPlaylistsTab() {
    final playlist = _userProfile?.playlist ?? [];
    
    if (playlist.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.playlist_play_outlined, color: AppColors.menuLightText, size: 48),
            const SizedBox(height: 12),
            Text(
              'No tracks in playlist',
              style: TextStyle(
                color: AppColors.menuLightText,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return Consumer<AudioPlayerState>(
      builder: (context, audioPlayer, _) {
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: playlist.length,
          itemBuilder: (context, index) {
            final item = playlist[index];
            final isPlaying = audioPlayer.currentlyPlayingRenderId == item.id && audioPlayer.isPlaying;

            return Container(
              height: 60,
              margin: const EdgeInsets.only(bottom: 2),
              decoration: BoxDecoration(
                color: isPlaying 
                    ? AppColors.menuOnlineIndicator.withOpacity(0.1)
                    : AppColors.menuEntryBackground,
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.menuBorder,
                    width: 0.5,
                  ),
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _playPlaylistItem(item),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        // Static note icon (no circle background)
                        Icon(
                          Icons.music_note,
                          color: AppColors.menuText,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        
                        // Item info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                item.name,
                                style: TextStyle(
                                  color: AppColors.menuText,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (item.duration != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  _formatDuration(item.duration!),
                                  style: TextStyle(
                                    color: AppColors.menuLightText,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ],
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
    
    // Create a minimal Render object for playback
    final render = Render(
      id: item.id,
      url: item.url,
      format: item.format,
      bitrate: item.bitrate,
      duration: item.duration,
      sizeBytes: item.sizeBytes,
      createdAt: item.createdAt,
    );
    
    await audioPlayer.playRender(
      messageId: 'playlist_${item.id}',
      render: render,
    );
  }

  Widget _buildSamplesTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.library_music_outlined, color: AppColors.menuLightText, size: 48),
          const SizedBox(height: 12),
          Text(
            'Coming soon',
            style: TextStyle(
              color: AppColors.menuLightText,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

} 