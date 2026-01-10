# Collaborative Update Indicators

## Overview
This document describes strategies for showing when a project has been updated by someone else (a collaborator), covering both logic and UI implementation approaches.

---

## Logic Level Strategies

### 1. **Last Updater Tracking** (Recommended - Minimal Backend Change)

Track who made the last update to each thread.

#### Backend Schema Addition
```json
{
  "thread": {
    "id": "thread_123",
    "updated_at": "2025-01-15T10:30:00Z",
    "updated_by": "user_456",  // ← Add this field
    "updated_by_username": "Alice",  // ← Optional: cache username
    "users": [...]
  }
}
```

#### Flutter Model Update
```dart
class Thread {
  final String id;
  final DateTime updatedAt;
  final String? updatedBy;           // ← Add: User ID who made last update
  final String? updatedByUsername;   // ← Add: Cache of username
  // ... existing fields
  
  bool wasUpdatedByOtherUser(String currentUserId) {
    return updatedBy != null && updatedBy != currentUserId;
  }
}
```

**Pros:**
- Simple to implement
- Low data overhead
- Works with existing WebSocket notifications

**Cons:**
- Only shows most recent updater (not all collaborators since last visit)

---

### 2. **Last Seen Timestamp** (Full Feature)

Track when each user last viewed/opened each thread.

#### Backend Schema Addition
```json
{
  "user": {
    "id": "user_123",
    "thread_last_seen": {
      "thread_456": "2025-01-15T09:00:00Z",
      "thread_789": "2025-01-14T16:30:00Z"
    }
  }
}
```

#### Logic Implementation
```dart
class ThreadsState {
  final Map<String, DateTime> _threadLastSeen = {};
  
  /// Mark thread as seen (call when user opens project)
  Future<void> markThreadAsSeen(String threadId) async {
    final now = DateTime.now();
    _threadLastSeen[threadId] = now;
    
    // Persist to backend
    await ThreadsApi.updateLastSeen(
      userId: _currentUserId,
      threadId: threadId,
      timestamp: now,
    );
    
    notifyListeners();
  }
  
  /// Check if thread has unseen updates
  bool hasUnseenUpdates(Thread thread) {
    final lastSeen = _threadLastSeen[thread.id];
    if (lastSeen == null) return true; // Never seen
    return thread.updatedAt.isAfter(lastSeen);
  }
}
```

**Pros:**
- Accurate "unread" indicator
- Persists across sessions
- Can show count of unseen updates

**Cons:**
- More backend API calls
- Requires persistent storage
- More complex logic

---

### 3. **Real-Time WebSocket Notifications** (Already Available)

Your app already has WebSocket support! Enhance it for real-time indicators.

#### Current WebSocket Events
```dart
// In ThreadsState._registerWsHandlers()
_wsClient.onEvent('message_created', _onMessageCreated);
_wsClient.onEvent('thread_updated', _onThreadUpdated);  // ← Use this!
```

#### Enhanced Notification Handler
```dart
void _onThreadUpdated(Map<String, dynamic> payload) {
  try {
    final threadId = payload['thread_id'] as String;
    final updatedBy = payload['updated_by'] as String?;
    final updatedByUsername = payload['updated_by_username'] as String?;
    
    // Update local thread data
    final threadIndex = _threads.indexWhere((t) => t.id == threadId);
    if (threadIndex >= 0) {
      final oldThread = _threads[threadIndex];
      _threads[threadIndex] = oldThread.copyWith(
        updatedAt: DateTime.parse(payload['updated_at']),
        updatedBy: updatedBy,
        updatedByUsername: updatedByUsername,
      );
      
      // Show notification if updated by someone else and user is on projects screen
      if (updatedBy != _currentUserId && !_isThreadViewActive) {
        _showUpdateNotification(threadId, updatedByUsername);
      }
      
      notifyListeners();
    }
  } catch (e) {
    debugPrint('❌ [WS] Error handling thread_updated: $e');
  }
}

void _showUpdateNotification(String threadId, String? username) {
  // Trigger UI notification (see UI strategies below)
  _recentlyUpdatedThreadIds.add(threadId);
  
  // Remove after animation period (e.g., 5 seconds)
  Future.delayed(const Duration(seconds: 5), () {
    _recentlyUpdatedThreadIds.remove(threadId);
    notifyListeners();
  });
}
```

**Pros:**
- Real-time updates (no refresh needed)
- Best user experience
- Already implemented (just needs enhancement)

**Cons:**
- Requires active connection
- Doesn't work offline

---

### 4. **Optimistic Update Counter**

Track number of new updates since last visit.

#### Backend Addition
```json
{
  "thread": {
    "id": "thread_123",
    "message_count": 45,
    "user_last_seen_message_count": {
      "user_456": 42,  // User has seen 42 messages
      "user_789": 45   // User has seen all 45
    }
  }
}
```

#### Flutter Logic
```dart
int getUnseenMessageCount(Thread thread, String currentUserId) {
  final totalMessages = thread.messageIds.length;
  final lastSeenCount = thread.metadata?['user_last_seen_message_count']?[currentUserId] ?? 0;
  return totalMessages - lastSeenCount;
}
```

**Pros:**
- Shows exact count of new updates
- Works offline (with cached data)

**Cons:**
- More data to sync
- Complex to maintain consistency

---

## UI Level Strategies

### 1. **Badge with Count** (Most Common)

Show a numerical badge indicating unseen updates.

#### Implementation
```dart
Widget _buildProjectCard(Thread project) {
  final hasUpdates = _hasUnseenUpdates(project);
  final updateCount = _getUnseenUpdateCount(project);
  
  return Stack(
    children: [
      // Existing tile
      Container(
        height: _tileHeight,
        child: _buildTileContent(project),
      ),
      
      // Badge overlay (top-right)
      if (hasUpdates)
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              updateCount > 99 ? '99+' : '$updateCount',
              style: GoogleFonts.sourceSans3(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
    ],
  );
}
```

**Visual Example:**
```
┌─────────────────────────────────┐
│ [Pattern Grid]     ┌──────┐    │
│                    │  3   │← Badge
│                    └──────┘    │
│ LEN 45  HST 23                 │
└─────────────────────────────────┘
```

---

### 2. **Colored Border/Glow** (Subtle but Effective)

Highlight updated tiles with colored border.

#### Implementation
```dart
Widget _buildProjectCard(Thread project) {
  final hasUpdates = _hasUnseenUpdates(project);
  final updatedBy = _getUpdaterUsername(project);
  
  return Container(
    height: _tileHeight,
    decoration: BoxDecoration(
      color: _tileBackgroundColor,
      borderRadius: BorderRadius.circular(_tileBorderRadius),
      // Highlight border for updated tiles
      border: hasUpdates
          ? Border.all(
              color: AppColors.sequencerAccent,  // Accent color
              width: 2.0,
            )
          : null,
      boxShadow: [
        BoxShadow(
          color: hasUpdates 
              ? AppColors.sequencerAccent.withOpacity(0.3)  // Glow effect
              : Colors.black.withOpacity(0.1),
          blurRadius: hasUpdates ? 8 : 4,
          offset: Offset(0, _tileElevation),
        ),
      ],
    ),
    child: _buildTileContent(project),
  );
}
```

**Visual Example:**
```
Normal:   ┌────────────────┐
          │ Project        │
          └────────────────┘

Updated:  ┏━━━━━━━━━━━━━━━━┓  ← Blue glow
          ┃ Project (NEW)  ┃
          ┗━━━━━━━━━━━━━━━━┛
```

---

### 3. **"NEW" Label with Updater Info**

Show who made the update.

#### Implementation
```dart
Widget _buildTileMetadata(Thread project) {
  final hasUpdates = _hasUnseenUpdates(project);
  final updatedBy = project.updatedByUsername;
  
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      // "NEW" indicator at top
      if (hasUpdates) ...[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.sequencerAccent,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fiber_new, size: 14, color: Colors.white),
              const SizedBox(width: 4),
              Text(
                updatedBy != null ? 'by $updatedBy' : 'NEW',
                style: GoogleFonts.sourceSans3(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
      
      // Rest of metadata...
      _buildParticipants(project),
      _buildCounters(project),
      // ...
    ],
  );
}
```

**Visual Example:**
```
┌─────────────────────────────────┐
│ [Pattern]  │ ┌──────────────┐  │
│            │ │ 🆕 by Alice  │  │
│            │ └──────────────┘  │
│            │ 👥 Bob, Charlie   │
│            │ LEN 45  HST 23    │
└─────────────────────────────────┘
```

---

### 4. **Pulsing Animation** (Attention-Grabbing)

Animate newly updated tiles.

#### Implementation
```dart
class _ProjectCardState extends State<_ProjectCard> 
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;
  
  @override
  void initState() {
    super.initState();
    
    if (widget.hasUpdates) {
      _controller = AnimationController(
        duration: const Duration(milliseconds: 1500),
        vsync: this,
      )..repeat(reverse: true);
      
      _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (!widget.hasUpdates) {
      return _buildStaticTile();
    }
    
    return ScaleTransition(
      scale: _pulseAnimation,
      child: _buildStaticTile(),
    );
  }
  
  @override
  void dispose() {
    if (widget.hasUpdates) {
      _controller.dispose();
    }
    super.dispose();
  }
}
```

---

### 5. **Dot Indicator** (Minimal)

Simple dot indicator (like iOS/Android notifications).

#### Implementation
```dart
Widget _buildProjectCard(Thread project) {
  final hasUpdates = _hasUnseenUpdates(project);
  
  return Stack(
    children: [
      _buildTileContent(project),
      
      // Notification dot (top-left)
      if (hasUpdates)
        Positioned(
          top: 6,
          left: 6,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
            ),
          ),
        ),
    ],
  );
}
```

**Visual Example:**
```
┌─────────────────────────────────┐
│●                                │ ← Red dot
│ [Pattern Grid]                  │
│                                 │
│ LEN 45  HST 23                  │
└─────────────────────────────────┘
```

---

### 6. **Background Color Tint** (Subtle)

Slightly tint the background of updated tiles.

#### Implementation
```dart
Container(
  decoration: BoxDecoration(
    color: hasUpdates 
        ? AppColors.sequencerAccent.withOpacity(0.05)  // Very subtle tint
        : _tileBackgroundColor,
    // ...
  ),
)
```

---

### 7. **Sort/Filter Options**

Add sorting to show recently updated tiles first.

#### Implementation
```dart
Widget _buildProjectsHeader() {
  return Row(
    children: [
      Text('PROJECTS'),
      const Spacer(),
      // Filter button
      IconButton(
        icon: Icon(Icons.filter_list),
        onPressed: () {
          setState(() {
            _showOnlyUpdated = !_showOnlyUpdated;
          });
        },
      ),
      // Sort buttons
      _buildSortButton('UPDATED', 'updated'),  // ← New sort option
      _buildSortButton('CREATED', 'created'),
    ],
  );
}

List<Thread> _getFilteredProjects(List<Thread> projects) {
  var filtered = projects;
  
  // Filter to show only updated projects
  if (_showOnlyUpdated) {
    filtered = filtered.where((p) => _hasUnseenUpdates(p)).toList();
  }
  
  // Sort by update status (updated first)
  if (_sortBy == 'updated') {
    filtered.sort((a, b) {
      final aHasUpdates = _hasUnseenUpdates(a);
      final bHasUpdates = _hasUnseenUpdates(b);
      
      if (aHasUpdates && !bHasUpdates) return -1;
      if (!aHasUpdates && bHasUpdates) return 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
  }
  
  return filtered;
}
```

---

### 8. **Toast/Snackbar Notification** (Real-Time)

Show notification when project updates arrive via WebSocket.

#### Implementation
```dart
// In ThreadsState
void _showUpdateNotification(String threadId, String? username) {
  // Find the thread
  final thread = _threads.firstWhere((t) => t.id == threadId, orElse: () => null);
  if (thread == null) return;
  
  // Trigger notification callback
  _onCollaborativeUpdate?.call(thread, username);
}

// In ProjectsScreen
@override
void initState() {
  super.initState();
  
  final threadsState = context.read<ThreadsState>();
  threadsState.setCollaborativeUpdateCallback((thread, username) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            username != null
                ? '$username updated "${thread.name}"'
                : 'Project "${thread.name}" was updated',
          ),
          action: SnackBarAction(
            label: 'VIEW',
            onPressed: () => _openProject(thread),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  });
}
```

---

## Recommended Implementation Strategy

### Phase 1: Basic (Quick Win)
1. Add `updated_by` field to Thread model
2. Implement colored border for updated tiles
3. Add "NEW" label with updater name
4. Sort updated tiles to top

**Estimated effort:** 2-4 hours

### Phase 2: Enhanced (Better UX)
1. Add `last_seen` tracking per user
2. Implement badge with unseen count
3. Add real-time toast notifications
4. Add filter to show only updated projects

**Estimated effort:** 1-2 days

### Phase 3: Advanced (Full Feature)
1. Implement pulsing animation
2. Add per-message unseen indicators
3. Implement mark-as-read functionality
4. Add notification history/panel

**Estimated effort:** 2-3 days

---

## Code Example: Complete Basic Implementation

```dart
// 1. Update Thread model
class Thread {
  final String? updatedBy;
  final String? updatedByUsername;
  
  bool wasUpdatedByOtherUser(String currentUserId) {
    return updatedBy != null && updatedBy != currentUserId;
  }
}

// 2. Update ProjectsScreen
class _ProjectsScreenState extends State<ProjectsScreen> {
  
  bool _hasUnseenUpdates(Thread project) {
    final userState = context.read<UserState>();
    final currentUserId = userState.currentUser?.id;
    if (currentUserId == null) return false;
    
    return project.wasUpdatedByOtherUser(currentUserId);
  }
  
  Widget _buildProjectCard(Thread project) {
    final hasUpdates = _hasUnseenUpdates(project);
    
    return Container(
      height: _tileHeight,
      decoration: BoxDecoration(
        color: _tileBackgroundColor,
        borderRadius: BorderRadius.circular(_tileBorderRadius),
        border: hasUpdates
            ? Border.all(color: AppColors.sequencerAccent, width: 2.0)
            : null,
        boxShadow: [
          BoxShadow(
            color: hasUpdates 
                ? AppColors.sequencerAccent.withOpacity(0.3)
                : Colors.black.withOpacity(0.1),
            blurRadius: hasUpdates ? 8 : 4,
            offset: Offset(0, _tileElevation),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openProject(project),
          child: Row(
            children: [
              // Pattern preview
              Expanded(
                flex: 60,
                child: PatternPreviewWidget(project: project),
              ),
              
              // Metadata with NEW indicator
              Expanded(
                flex: 40,
                child: _buildTileMetadata(project, hasUpdates),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildTileMetadata(Thread project, bool hasUpdates) {
    return Column(
      children: [
        // NEW badge
        if (hasUpdates)
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.sequencerAccent,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              '🆕 ${project.updatedByUsername ?? "Updated"}',
              style: GoogleFonts.sourceSans3(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        
        // Rest of metadata...
      ],
    );
  }
}
```

---

## Summary

**Recommended Combo for Best UX:**
1. **Logic:** Track `updated_by` + real-time WebSocket notifications
2. **UI:** Colored border + "NEW by [username]" label + sort updated first
3. **Optional:** Badge with count if implementing `last_seen` tracking

This provides clear visual feedback while maintaining clean design and good performance.


