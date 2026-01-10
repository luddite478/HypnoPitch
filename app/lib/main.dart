import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:app_links/app_links.dart';

import 'screens/main_navigation_screen.dart';
import 'screens/sequencer_screen.dart';
import 'widgets/username_creation_dialog.dart';
import 'services/threads_service.dart';
import 'services/users_service.dart';
import 'services/notifications.dart';
import 'utils/app_colors.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/http_client.dart';
import 'models/thread/thread.dart';
import 'models/thread/thread_user.dart';
import 'utils/thread_name_generator.dart';

import 'state/user_state.dart';
import 'state/threads_state.dart';
import 'state/audio_player_state.dart';
import 'state/library_state.dart';
import 'state/followed_state.dart';
import 'services/ws_client.dart';
import 'state/sequencer/table.dart';
import 'state/sequencer/playback.dart';
import 'state/sequencer/sample_bank.dart';
import 'state/sequencer_version_state.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  
  // Apply DevHttpOverrides for stage environment to trust self-signed certificates
  final env = dotenv.env['ENV'] ?? '';
  if (env == 'stage') {
    HttpOverrides.global = DevHttpOverrides();
  }
  
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => UserState()),
        ChangeNotifierProvider(create: (context) => AudioPlayerState()),
        ChangeNotifierProvider(create: (context) => LibraryState()),
        ChangeNotifierProvider(create: (context) => FollowedState()),
        ChangeNotifierProvider(create: (context) => SequencerVersionState()),
        Provider(create: (context) => WebSocketClient()),
        ChangeNotifierProvider(create: (context) => TableState()),
        ChangeNotifierProvider(create: (context) => PlaybackState(Provider.of<TableState>(context, listen: false))),
        ChangeNotifierProvider(create: (context) => SampleBankState()),
        ChangeNotifierProvider(
          create: (context) => ThreadsState(
            wsClient: Provider.of<WebSocketClient>(context, listen: false),
            tableState: Provider.of<TableState>(context, listen: false),
            playbackState: Provider.of<PlaybackState>(context, listen: false),
            sampleBankState: Provider.of<SampleBankState>(context, listen: false),
          ),
        ),
        Provider(
          create: (context) => ThreadsService(
            wsClient: Provider.of<WebSocketClient>(context, listen: false),
          ),
        ),
        Provider(
          create: (context) => UsersService(
            wsClient: Provider.of<WebSocketClient>(context, listen: false),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'App',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: const MainPage(),
      ),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  bool _hasInitializedUser = false;
  StreamSubscription? _notifSub;
  NotificationsService? _notificationsService;
  final List<OverlayEntry> _notifOverlays = [];
  final Map<OverlayEntry, Timer> _notifOverlayTimers = {};
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSub;
  bool _isProcessingInvite = false;
  
  @override
  void initState() {
    super.initState();
    _initDeepLinks();
    // Remove the immediate call to _syncCurrentUser() since it will be called
    // reactively when UserState completes loading
    
    // Set up callback for syncing library when render uploads complete
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupLibrarySyncCallback();
    });
  }
  
  void _setupLibrarySyncCallback() {
    final threadsState = context.read<ThreadsState>();
    final libraryState = context.read<LibraryState>();
    final userState = context.read<UserState>();
    
    // Set callback to update library when renders complete uploading
    threadsState.setOnRenderUploadComplete((renderId, url) async {
      final userId = userState.currentUser?.id;
      if (userId != null) {
        await libraryState.updateItemAfterUpload(
          userId: userId,
          renderId: renderId,
          url: url,
        );
      }
    });
    
    debugPrint('📚 [MAIN] Set up library sync callback for render uploads');
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();

    // Handle initial link if app was opened from a deep link (cold start)
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        debugPrint('Got initial deep link: $initialUri');
        if (initialUri.path.startsWith('/join/')) {
          final threadId = initialUri.pathSegments.last;
          // Delay showing confirmation until after build completes
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showJoinConfirmation(threadId);
          });
        }
      }
    } catch (e) {
      debugPrint('Error getting initial link: $e');
    }

    // Listen for incoming app links while app is running
    _linkSub = _appLinks.uriLinkStream.listen((uri) {
      debugPrint('Got deep link: $uri');
      if (uri.path.startsWith('/join/')) {
        final threadId = uri.pathSegments.last;
        _showJoinConfirmation(threadId);
      }
    });
  }

  void _showJoinConfirmation(String threadId) {
    // Ensure we have a valid context that can show a dialog
    if (!mounted) return;
    
    // Prevent showing dialog if already processing an invite
    if (_isProcessingInvite) {
      debugPrint('⚠️ [MAIN] Already processing invite, ignoring duplicate deeplink trigger');
      return;
    }

    // Check if user needs to create username first
    final userState = context.read<UserState>();
    final currentUsername = userState.currentUser?.username ?? '';
    
    if (currentUsername.isEmpty) {
      // Show username creation dialog first
      _showUsernameCreationForInvite(threadId);
    } else {
      // Show regular join confirmation
      _showJoinDialog(threadId);
    }
  }
  
  void _showUsernameCreationForInvite(String threadId) {
    if (!mounted) return;
    
    // Set flag to indicate we're processing an invite
    setState(() {
      _isProcessingInvite = true;
    });
    
    final userState = context.read<UserState>();
    final wsClient = context.read<WebSocketClient>();
    bool usernameSubmittedSuccessfully = false;
    
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: AppColors.menuPageBackground.withOpacity(0.8),
      builder: (context) => UsernameCreationDialog(
        title: 'Join Project',
        message: 'Create a username to join this collaborative project.',
        onSubmit: (username) async {
          // Update username via UserState
          final success = await userState.updateUsername(username);
          if (success) {
            usernameSubmittedSuccessfully = true;
            // Close dialog
            if (context.mounted) {
              Navigator.pop(context);
              
              // CRITICAL: Ensure WebSocket is connected before joining
              debugPrint('🔌 [MAIN] Checking WebSocket connection before join...');
              if (!wsClient.isConnected && userState.currentUser != null) {
                debugPrint('🔌 [MAIN] WebSocket not connected, connecting now...');
                final threadsService = context.read<ThreadsService>();
                await threadsService.connectRealtime(userState.currentUser!.id);
                // Wait a moment for connection to stabilize
                await Future.delayed(const Duration(milliseconds: 500));
              }
              debugPrint('✅ [MAIN] WebSocket ready, proceeding to join');
              
              await _acceptInviteAndNavigate(threadId);
            }
          } else {
            throw Exception('Failed to create username. Please try again.');
          }
        },
      ),
    ).then((_) {
      // Reset flag only if user cancelled (didn't submit successfully)
      // If submitted successfully, flag will be reset in _acceptInviteAndNavigate
      if (!usernameSubmittedSuccessfully && mounted) {
        setState(() {
          _isProcessingInvite = false;
        });
      }
    });
  }
  
  void _showJoinDialog(String threadId) {
    // Set flag to indicate we're processing an invite
    setState(() {
      _isProcessingInvite = true;
    });
    
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: AppColors.sequencerPageBackground.withOpacity(0.8),
      builder: (BuildContext context) {
        final size = MediaQuery.of(context).size;
        final dialogWidth = (size.width * 0.8).clamp(280.0, size.width);
        final dialogHeight = (size.height * 0.35).clamp(220.0, size.height);

        return Material(
          type: MaterialType.transparency,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints.tightFor(width: dialogWidth, height: dialogHeight),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.sequencerSurfaceRaised,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.sequencerBorder, width: 0.5),
                ),
                clipBehavior: Clip.hardEdge,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Join Pattern Project',
                              style: GoogleFonts.sourceSans3(
                                color: AppColors.sequencerText,
                                fontSize: 24,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: Icon(Icons.close, color: AppColors.sequencerLightText, size: 28),
                              splashRadius: 22,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'You have been invited to join a pattern project. Do you want to accept?',
                          textAlign: TextAlign.left,
                          style: GoogleFonts.sourceSans3(
                            color: AppColors.sequencerLightText,
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(context).pop(),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.sequencerText,
                                  side: BorderSide(color: AppColors.sequencerBorder, width: 0.5),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  minimumSize: const Size(0, 48),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: Text(
                                  'Decline',
                                  style: GoogleFonts.sourceSans3(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () async {
                                  Navigator.of(context).pop();
                                  await _acceptInviteAndNavigate(threadId);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.sequencerAccent,
                                  foregroundColor: AppColors.sequencerText,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  minimumSize: const Size(0, 48),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  elevation: 0,
                                ),
                                child: Text(
                                  'Accept',
                                  style: GoogleFonts.sourceSans3(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ).then((_) {
      // Reset flag when dialog is dismissed (user cancels)
      if (mounted) {
        setState(() {
          _isProcessingInvite = false;
        });
      }
    });
  }
  
  Future<void> _acceptInviteAndNavigate(String threadId) async {
    try {
      final threadsState = context.read<ThreadsState>();
      final success = await threadsState.joinThread(threadId: threadId);
      if (success && mounted) {
        await threadsState.ensureThreadSummary(threadId);
        
        // Set active thread and load project into sequencer
        final thread = threadsState.threads.firstWhere(
          (t) => t.id == threadId,
          orElse: () => throw Exception('Thread not found'),
        );
        threadsState.setActiveThread(thread);
        
        // Load project into sequencer
        await threadsState.loadProjectIntoSequencer(threadId);
        
        // Navigate to PatternScreen (sequencer)
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const PatternScreen(initialSnapshot: null),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to join project.'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('An error occurred: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      // Always reset the processing flag
      if (mounted) {
        setState(() {
          _isProcessingInvite = false;
        });
      }
    }
  }

  void _syncCurrentUser() {
    final userState = Provider.of<UserState>(context, listen: false);
    final threadsState = Provider.of<ThreadsState>(context, listen: false);
    final threadsService = Provider.of<ThreadsService>(context, listen: false);
    final wsClient = Provider.of<WebSocketClient>(context, listen: false);
    final libraryState = Provider.of<LibraryState>(context, listen: false);
    final followedState = Provider.of<FollowedState>(context, listen: false);
    
    if (userState.currentUser != null) {
      threadsState.setCurrentUser(
        userState.currentUser!.id,
        userState.currentUser!.username,  // Fixed: Use username instead of name
      );
      
      // Add listener to keep ThreadsState in sync when username changes
      userState.addListener(() {
        if (userState.currentUser != null) {
          threadsState.setCurrentUser(
            userState.currentUser!.id,
            userState.currentUser!.username,
          );
        }
      });
      
      // Load data on startup (cached for session)
      libraryState.loadPlaylist(userId: userState.currentUser!.id);
      threadsState.loadThreads();
      followedState.loadFollowedUsers(userId: userState.currentUser!.id);
      
      // Initialize single WebSocket connection for this user
      _initializeThreadsService(threadsService, userState.currentUser!.id, context);
      
      // Setup auto-sync on reconnection
      _setupReconnectionHandler(wsClient, userState, threadsState, libraryState, followedState);
      _setupNotifications(wsClient);
    }
  }

  void _initializeThreadsService(ThreadsService threadsService, String userId, BuildContext context) async {
    try {
      debugPrint('🔌 [MAIN] Connecting WebSocket for user: $userId');
      final success = await threadsService.connectRealtime(userId);
      if (success) {
        debugPrint('✅ [MAIN] WebSocket connected successfully');
        
        // Refresh threads to get accurate online status (now that WebSocket is connected)
        final threadsState = Provider.of<ThreadsState>(context, listen: false);
        await threadsState.refreshThreadsInBackground();
        debugPrint('✅ [MAIN] Threads refreshed with online status');
        
        // Get UsersService and request online users
        final usersService = Provider.of<UsersService>(context, listen: false);
        usersService.requestOnlineUsers();
        debugPrint('✅ [MAIN] Online users list requested');
      } else {
        debugPrint('❌ [MAIN] WebSocket connection failed');
      }
    } catch (e) {
      debugPrint('❌ [MAIN] Error initializing WebSocket: $e');
    }
  }
  
  void _setupReconnectionHandler(
    WebSocketClient wsClient,
    UserState userState,
    ThreadsState threadsState,
    LibraryState libraryState,
    FollowedState followedState,
  ) {
    // Listen for connection status changes
    wsClient.connectionStream.listen((isConnected) {
      if (isConnected) {
        debugPrint('✅ [MAIN] WebSocket reconnected - syncing data...');
        _syncDataAfterReconnect(userState, threadsState, libraryState, followedState);
      } else {
        debugPrint('❌ [MAIN] WebSocket disconnected');
      }
    });
  }
  
  Future<void> _syncDataAfterReconnect(
    UserState userState,
    ThreadsState threadsState,
    LibraryState libraryState,
    FollowedState followedState,
  ) async {
    try {
      final userId = userState.currentUser?.id;
      if (userId == null) return;
      
      debugPrint('🔄 [MAIN] Starting data sync after reconnection...');
      
      // 1. Refresh user profile (might have new invites)
      await userState.refreshCurrentUserFromServer();
      debugPrint('✅ [MAIN] User profile refreshed');
      
      // 2. Refresh thread list (new threads, new participants, new messages)
      await threadsState.refreshThreadsInBackground();
      debugPrint('✅ [MAIN] Threads refreshed');
      
      // 3. Refresh playlist (new items might have been added)
      await libraryState.refreshPlaylistInBackground(userId: userId);
      debugPrint('✅ [MAIN] Playlist refreshed');
      
      // 4. Refresh followed users
      await followedState.refreshFollowedUsersInBackground(userId);
      debugPrint('✅ [MAIN] Followed users refreshed');
      
      // 5. Request fresh online users list
      if (mounted) {
        final usersService = Provider.of<UsersService>(context, listen: false);
        usersService.requestOnlineUsers();
        debugPrint('✅ [MAIN] Online users requested');
      }
      
      debugPrint('✅ [MAIN] Data sync complete after reconnection');
    } catch (e) {
      debugPrint('❌ [MAIN] Data sync failed after reconnection: $e');
    }
  }

  void _setupNotifications(WebSocketClient wsClient) {
    // Initialize lightweight notifications stream and show snackbars globally
    _notificationsService?.dispose();
    final notifications = NotificationsService(wsClient: wsClient);
    _notificationsService = notifications;
    _notifSub?.cancel();
    _notifSub = notifications.stream.listen((event) async {
      debugPrint('🔔 [NOTIFICATION] Received event: ${event.type} for thread ${event.threadId}');
      
      // Do not show messageCreated banner if already on same thread screen
      bool suppress = false;
      if (event.type == AppNotificationType.messageCreated) {
        try {
          final threadsState = Provider.of<ThreadsState>(context, listen: false);
          // Suppress only when user is actively viewing the same thread screen
          if (threadsState.isThreadViewActive && threadsState.activeThread?.id == event.threadId) {
            suppress = true;
            debugPrint('🔕 [NOTIFICATION] Suppressed - already viewing thread ${event.threadId}');
          }
        } catch (e) {
          debugPrint('⚠️ [NOTIFICATION] Error checking suppress: $e');
        }
      }
      // If an invitation arrives while on Projects, refresh user + load that thread summary so INVITES appears instantly
      if (event.type == AppNotificationType.invitationReceived) {
        try {
          // Re-sync user state to get new invites
          final userState = Provider.of<UserState>(context, listen: false);
          // This will re-trigger a sync and update the user object
          await userState.refreshCurrentUserFromServer();

          if (event.threadId != null) {
            final threadsState = Provider.of<ThreadsState>(context, listen: false);
            await threadsState.ensureThreadSummary(event.threadId!);
          }
        } catch (_) {}
      }

      if (!suppress) {
        String body = event.body;
        VoidCallback? onTap;
        if (event.type == AppNotificationType.messageCreated) {
          String senderName = 'Someone';
          try {
            final threadsState = Provider.of<ThreadsState>(context, listen: false);
            final userId = event.raw['user_id'] as String?;
            if (event.threadId != null && userId != null) {
              final thread = threadsState.threads.firstWhere(
                (t) => t.id == event.threadId,
                orElse: () => threadsState.activeThread ?? Thread(id: event.threadId!, name: ThreadNameGenerator.generate(event.threadId!), createdAt: DateTime.now(), updatedAt: DateTime.now(), users: const [], messageIds: const [], invites: const []),
              );
              final user = thread.users.firstWhere(
                (u) => u.id == userId,
                orElse: () => ThreadUser(
                  id: userId, 
                  username: 'user_${userId.substring(0, 6)}',
                  name: 'User ${userId.substring(0, 6)}', 
                  joinedAt: DateTime.now(),
                ),
              );
              senderName = user.name;
            }
          } catch (_) {}
          body = '$senderName updated the pattern';
          if (event.threadId != null) {
            onTap = () async {
              try {
                final threadsState = Provider.of<ThreadsState>(context, listen: false);
                final audioPlayerState = Provider.of<AudioPlayerState>(context, listen: false);
                
                // Ensure we have the thread summary
                await threadsState.ensureThreadSummary(event.threadId!);
                
                // Find the thread
                final thread = threadsState.threads.firstWhere(
                  (t) => t.id == event.threadId,
                  orElse: () => Thread(
                    id: event.threadId!, 
                    name: ThreadNameGenerator.generate(event.threadId!), 
                    createdAt: DateTime.now(), 
                    updatedAt: DateTime.now(), 
                    users: const [], 
                    messageIds: const [], 
                    invites: const [],
                  ),
                );
                
                // Set active thread context
                threadsState.setActiveThread(thread);
                
                // Stop any playing audio
                audioPlayerState.stop();
                
                // Load project into sequencer (handles initialization and import)
                debugPrint('📂 [NOTIFICATION] Loading project ${event.threadId} via unified loader');
                await threadsState.loadProjectIntoSequencer(event.threadId!);
                
                // Navigate to sequencer using PatternScreen (current version) - open to thread view
                if (!mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PatternScreen(
                      initialSnapshot: null,
                      openThreadView: true, // Open to thread view tab
                    ),
                  ),
                );
              } catch (e) {
                debugPrint('❌ [NOTIFICATION] Failed to open project: $e');
              }
            };
          }
        } else if (event.type == AppNotificationType.invitationReceived) {
          final inviter = (event.raw['from_user_name'] as String?) ?? 'Someone';
          body = '$inviter sent you an invitation';
          onTap = null; // stay on current screen
        } else if (event.type == AppNotificationType.invitationAccepted) {
          final userName = (event.raw['user_name'] as String?) ?? 'A collaborator';
          final acceptedUserId = event.raw['user_id'] as String?;
          try {
            final userState = Provider.of<UserState>(context, listen: false);
            if (acceptedUserId != null && userState.currentUser?.id == acceptedUserId) {
              // Suppress for the user who accepted their own invite
              return;
            }
          } catch (_) {}
          body = '$userName accepted invitation';
          onTap = null;
        }
        debugPrint('📢 [NOTIFICATION] Showing overlay: "$body"');
        _showOverlayNotification(
          title: event.title,
          body: body,
          onTap: onTap,
        );
      } else {
        debugPrint('🔕 [NOTIFICATION] Notification suppressed');
      }
    });
  }

  void _showOverlayNotification({required String title, required String body, VoidCallback? onTap}) {
    debugPrint('🎨 [NOTIFICATION] Creating overlay notification: "$body" (current count: ${_notifOverlays.length})');
    
    // Calculate vertical position based on number of existing notifications
    // Each notification is ~56px tall (10px padding top/bottom + ~36px content height) + 8px spacing
    const double notificationHeight = 56.0;
    const double notificationSpacing = 8.0;
    final double topPosition = 20.0 + (_notifOverlays.length * (notificationHeight + notificationSpacing));
    
    // Declare overlay as late so we can reference it in the builder
    late final OverlayEntry overlay;
    
    overlay = OverlayEntry(
      builder: (context) {
        return Positioned(
          top: topPosition,
          left: 12,
          right: 12,
          child: SafeArea(
            child: Material(
              color: Colors.transparent,
              child: Container
              (
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.sequencerSurfaceBase.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                  border: Border.all(color: AppColors.sequencerBorder, width: 0.5),
                ),
                child: InkWell(
                  onTap: () {
                    // Remove this specific notification when tapped
                    _removeSpecificNotification(overlay);
                    // Execute the original onTap callback
                    onTap?.call();
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: AppColors.sequencerAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          body,
                          style: GoogleFonts.crimsonPro(
                            color: AppColors.sequencerText,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    
    // Insert the overlay and track it
    Overlay.of(context).insert(overlay);
    _notifOverlays.add(overlay);
    
    // Create a timer that removes this specific overlay after 4 seconds
    final timer = Timer(const Duration(seconds: 4), () {
      _removeSpecificNotification(overlay);
    });
    _notifOverlayTimers[overlay] = timer;
  }

  void _removeSpecificNotification(OverlayEntry overlay) {
    debugPrint('🗑️ [NOTIFICATION] Removing notification (remaining: ${_notifOverlays.length - 1})');
    
    // Cancel and remove the timer for this specific overlay
    final timer = _notifOverlayTimers[overlay];
    timer?.cancel();
    _notifOverlayTimers.remove(overlay);
    
    // Remove the overlay from the screen
    overlay.remove();
    _notifOverlays.remove(overlay);
  }
  
  void _removeAllNotifications() {
    // Cancel all timers
    for (final timer in _notifOverlayTimers.values) {
      timer.cancel();
    }
    _notifOverlayTimers.clear();
    
    // Remove all overlays
    for (final overlay in _notifOverlays) {
      overlay.remove();
    }
    _notifOverlays.clear();
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    _notificationsService?.dispose();
    _removeAllNotifications();
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UserState>(
      builder: (context, userState, child) {
        if (!userState.isLoading && userState.isAuthenticated && userState.currentUser != null && !_hasInitializedUser) {
          _hasInitializedUser = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _syncCurrentUser();
          });
        }
        
        if (userState.isLoading) {
          return Scaffold(
            backgroundColor: Colors.white,
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(),
                    
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        backgroundColor: Colors.grey[200],
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF333333)),
                        minHeight: 3,
                      ),
                    ),
                    
                    const Spacer(),
                  ],
                ),
              ),
            ),
          );
        }

        return const MainNavigationScreen();
      },
    );
  }
}


