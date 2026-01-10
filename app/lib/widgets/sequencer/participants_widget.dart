import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../utils/app_colors.dart';
import '../../models/thread/thread.dart';
import '../../models/thread/thread_user.dart';
import '../../state/user_state.dart';
import '../../state/threads_state.dart';

/// Widget displaying participants in the sequencer header
/// Shows first participant with online status, stacked chips for multiple participants
/// Click to show participants overflow menu
/// 
/// Online status comes directly from ThreadUser.isOnline field, which is updated via:
/// - HTTP API responses (GET /threads)
/// - WebSocket notifications (user_status_changed, invitation_accepted, etc)
/// 
/// The participants menu dialog uses Consumer<ThreadsState> for real-time updates,
/// so online status changes are reflected immediately without reopening the dialog
class ParticipantsWidget extends StatelessWidget {
  final Thread? thread;
  final VoidCallback onTap;
  
  const ParticipantsWidget({
    super.key,
    required this.thread,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (thread == null || thread!.users.isEmpty) {
      return const SizedBox.shrink();
    }
    
    // Get current user to filter out self
    final userState = context.read<UserState>();
    final currentUserId = userState.currentUser?.id ?? '';
    
    // Get other participants (exclude current user)
    final otherParticipants = thread!.users
        .where((u) => u.id != currentUserId)
        .toList();
    
    if (otherParticipants.isEmpty) {
      return const SizedBox.shrink();
    }
    
    final firstParticipant = otherParticipants.first;
    final hasMore = otherParticipants.length > 1;
    
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Main chip (first participant)
          _buildParticipantChip(firstParticipant),
          
          // Stacked chips indicator (if more than one participant)
          if (hasMore)
            Positioned(
              right: -4,
              bottom: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.sequencerAccent,
                  borderRadius: BorderRadius.circular(0), // Squared corners
                  border: Border.all(
                    color: AppColors.sequencerPageBackground,
                    width: 1,
                  ),
                ),
                child: Text(
                  '+${otherParticipants.length - 1}',
                  style: GoogleFonts.sourceSans3(
                    color: AppColors.sequencerText,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
  
  Widget _buildParticipantChip(ThreadUser user) {
    // Online status comes directly from ThreadUser.isOnline
    // This is updated via:
    // - HTTP API responses (includes is_online computed from WebSocket clients)
    // - WebSocket notifications (invitation_accepted includes all participants with is_online)
    final isOnline = user.isOnline;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.sequencerSurfaceRaised.withOpacity(0.9),
        borderRadius: BorderRadius.circular(0), // Squared corners
        border: Border.all(
          color: AppColors.sequencerBorder,
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Online status dot
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isOnline 
                  ? AppColors.menuOnlineIndicator 
                  : AppColors.sequencerLightText.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          
          // Username
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 80),
            child: Text(
              user.username,
              style: GoogleFonts.sourceSans3(
                color: AppColors.sequencerText,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Participants overflow menu dialog
/// Shows all participants with their online status
/// Online status comes directly from ThreadUser.isOnline field
class ParticipantsMenuDialog extends StatelessWidget {
  final Thread thread;
  
  const ParticipantsMenuDialog({
    super.key,
    required this.thread,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final dialogWidth = (size.width * 0.6).clamp(240.0, 400.0);
    
    // Get current user to show them separately
    final userState = context.read<UserState>();
    final currentUserId = userState.currentUser?.id ?? '';
    
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: dialogWidth,
            maxWidth: dialogWidth,
            maxHeight: size.height * 0.7,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.sequencerSurfaceRaised,
              borderRadius: BorderRadius.circular(0), // Squared corners
              border: Border.all(color: AppColors.sequencerBorder, width: 0.5),
            ),
            clipBehavior: Clip.hardEdge,
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: Row(
                      children: [
                        Text(
                          'Participants',
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
                  ),
                  
                  // Participants list - wrapped in Consumer for real-time updates
                  Flexible(
                    child: Consumer<ThreadsState>(
                      builder: (context, threadsState, _) {
                        // Get the latest thread data from state
                        final latestThread = threadsState.threads.firstWhere(
                          (t) => t.id == thread.id,
                          orElse: () => thread, // Fallback to initial thread if not found
                        );
                        final allParticipants = latestThread.users;
                        
                        return ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: allParticipants.length,
                          itemBuilder: (context, index) {
                            final participant = allParticipants[index];
                            final isMe = participant.id == currentUserId;
                            final isOnline = participant.isOnline;
                            
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: isMe 
                                    ? AppColors.sequencerAccent.withOpacity(0.15)
                                    : AppColors.sequencerSurfaceBase,
                                borderRadius: BorderRadius.circular(0), // Squared corners
                                border: Border.all(
                                  color: isMe 
                                      ? AppColors.sequencerAccent.withOpacity(0.3)
                                      : AppColors.sequencerBorder,
                                  width: 0.5,
                                ),
                              ),
                              child: Row(
                                children: [
                                  // Online status dot
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: isOnline 
                                          ? AppColors.menuOnlineIndicator 
                                          : AppColors.sequencerLightText.withOpacity(0.3),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  
                                  // Username
                                  Expanded(
                                    child: Text(
                                      participant.username,
                                      style: GoogleFonts.sourceSans3(
                                        color: AppColors.sequencerText,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  
                                  // "You" badge
                                  if (isMe)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppColors.sequencerAccent.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(0), // Squared corners
                                      ),
                                      child: Text(
                                        'You',
                                        style: GoogleFonts.sourceSans3(
                                          color: AppColors.sequencerAccent,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  
                                  // Online status text
                                  if (!isMe)
                                    Text(
                                      isOnline ? 'Online' : 'Offline',
                                      style: GoogleFonts.sourceSans3(
                                        color: isOnline 
                                            ? AppColors.menuOnlineIndicator 
                                            : AppColors.sequencerLightText,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        );
                      },
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
}

