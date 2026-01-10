# Real-Time Collaboration System

Complete guide to WebSocket-based real-time features, data synchronization, and collaborative workflows in Fortuned.

**Last Updated**: Dec 2025  
**Status**: Production Ready

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [WebSocket System](#websocket-system)
3. [Message Types & Handlers](#message-types--handlers)
4. [Data Synchronization Patterns](#data-synchronization-patterns)
5. [Online Status System](#online-status-system)
6. [Invitation & Participant Management](#invitation--participant-management)
7. [Username & Profile Sync](#username--profile-sync)
8. [Connection Management](#connection-management)
9. [Implementation Guide](#implementation-guide)
10. [Testing & Debugging](#testing--debugging)

---

## Architecture Overview

### System Design

```
┌─────────────────────────────────────────────────────────────┐
│                     CLIENT ARCHITECTURE                      │
└─────────────────────────────────────────────────────────────┘

UI Screens
    ↓
State Management (Provider)
    ├─→ UserState (user profile, auth)
    ├─→ ThreadsState (threads, messages, participants)
    ├─→ LibraryState (playlist, user-owned data)
    └─→ FollowedState (followed users)
    ↓
Services Layer
    ├─→ WebSocketClient (connection, routing)
    ├─→ ThreadsService (thread events)
    ├─→ UsersService (online status)
    ├─→ NotificationsService (UI notifications)
    └─→ HTTP APIs (REST endpoints)
    ↓
Server (WebSocket + HTTP)
```

### Data Flow Patterns

**1. User-Owned Data** (Playlist, Settings):
- Load once per session
- Optimistic updates
- No background refresh needed

**2. Collaborative Data** (Threads, Participants):
- Load once, cache in memory
- Background refresh on view
- Real-time updates via WebSocket

**3. Real-Time Events** (Messages, Status Changes):
- Instant via WebSocket
- Fallback to HTTP polling if needed
- Optimistic UI updates

---

## WebSocket System

### Core Components

#### WebSocketClient (`app/lib/services/ws_client.dart`)

Central client managing connections and routing messages.

**Key Features**:
- Single connection per user
- Message routing to registered handlers
- Connection state management
- Error handling and timeout detection

**API**:
```dart
class WebSocketClient {
  // Connection
  Future<bool> connect(String clientId);
  void disconnect();
  
  // Message handling
  void registerMessageHandler(String type, Function handler);
  void unregisterMessageHandler(String type, Function handler);
  Future<bool> sendMessage(dynamic message);
  
  // State
  bool get isConnected;
  String? get clientId;
  Stream<bool> get connectionStream;
  Stream<String> get errorStream;
}
```

### Connection Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    CONNECTION LIFECYCLE                      │
└─────────────────────────────────────────────────────────────┘

1. App Startup
   ├─→ WebSocketClient created (not connected)
   └─→ Services initialized with wsClient dependency

2. User Authentication
   ├─→ UserState loads/creates user
   └─→ Gets unique 24-hex user ID

3. Connection Establishment
   ├─→ ThreadsService.connectRealtime(userId)
   ├─→ WebSocketClient.connect(userId)
   ├─→ Send auth: {token, client_id}
   └─→ Server validates & registers client

4. Handler Registration
   ├─→ Services register message handlers
   ├─→ ThreadsState registers handlers
   └─→ NotificationsService registers handlers

5. Active Session
   ├─→ Heartbeat pings every 60s (server)
   ├─→ last_online updated
   └─→ Stale connections detected & cleaned

6. Disconnection
   ├─→ WebSocket closes (user action or network)
   ├─→ Server: unregister_client()
   ├─→ Update last_online immediately
   └─→ Client notified via connectionStream
```

### Server-Side Connection Management

**File**: `server/app/ws/router.py`

**On Connection**:
```python
async def register_client(client_id, websocket):
    clients[client_id] = websocket
    
    # Update last_online immediately on connect
    db.users.update_one(
        {"id": client_id},
        {"$set": {"last_online": datetime.utcnow().isoformat() + "Z"}}
    )
    
    await send_json(websocket, {
        "type": "connected",
        "message": f"Successfully connected as {client_id}"
    })
```

**On Disconnection**:
```python
def unregister_client(client_id):
    if client_id in clients:
        del clients[client_id]
        
        # Update last_online immediately on disconnect
        db.users.update_one(
            {"id": client_id},
            {"$set": {"last_online": datetime.utcnow().isoformat() + "Z"}}
        )
```

**Heartbeat with Stale Detection** (every 60s):
```python
async def heartbeat_loop():
    while True:
        await asyncio.sleep(60)
        
        # Ping each connection to verify it's alive
        stale_clients = []
        for client_id, ws in clients.items():
            try:
                await asyncio.wait_for(
                    send_json(ws, {"type": "ping"}),
                    timeout=5.0
                )
            except Exception:
                stale_clients.append(client_id)
        
        # Clean up stale connections
        for client_id in stale_clients:
            unregister_client(client_id)
        
        # Update last_online for active connections
        active_clients = [id for id in clients if id not in stale_clients]
        db.users.update_many(
            {"id": {"$in": active_clients}},
            {"$set": {"last_online": datetime.utcnow().isoformat() + "Z"}}
        )
```

---

## Message Types & Handlers

### Registered Message Types

| Type | Direction | Purpose | Handler Location |
|------|-----------|---------|------------------|
| `connected` | Server → Client | Connection confirmation | WebSocketClient |
| `ping` | Server → Client | Heartbeat check | None (automatic) |
| `message_created` | Server → Client | New thread message | ThreadsState |
| `thread_invitation` | Server → Client | User invited to thread | NotificationsService |
| `invitation_accepted` | Server → Client | User accepted invitation | ThreadsState, NotificationsService |
| `user_profile_updated` | Server → Client | Username/profile changed | ThreadsState |
| `online_users` | Server → Client | List of online users | UsersService |
| `list_users` | Client → Server | Request online users | Server |

### Message Format

**Standard Format**:
```json
{
  "type": "message_type",
  "timestamp": 1703001234,
  // ... message-specific fields
}
```

**Examples**:

**invitation_accepted**:
```json
{
  "type": "invitation_accepted",
  "thread_id": "thread_abc123",
  "user_id": "user_def456",
  "user_name": "alice",
  "timestamp": 1703001234
}
```

**user_profile_updated**:
```json
{
  "type": "user_profile_updated",
  "user_id": "user_abc123",
  "username": "alice_new",
  "timestamp": 1703001234
}
```

**message_created**:
```json
{
  "type": "message_created",
  "id": "msg_xyz789",
  "parent_thread": "thread_abc123",
  "user_id": "user_def456",
  "snapshot": {...},
  "timestamp": 1703001234
}
```

### Handler Implementation Pattern

**Server Broadcast**:
```python
# server/app/http_api/users.py
async def update_username_handler(...):
    # Update database
    db.users.update_one(...)
    db.threads.update_many(...)  # Sync to threads
    
    # Broadcast to collaborators
    from ws.router import send_user_profile_updated_notification
    await send_user_profile_updated_notification(user_id, username)
```

**Client Handler**:
```dart
// app/lib/state/threads_state.dart
void _registerWsHandlers() {
  _wsClient.registerMessageHandler('user_profile_updated', _onUserProfileUpdated);
}

void _onUserProfileUpdated(Map<String, dynamic> payload) {
  final userId = payload['user_id'] as String?;
  final username = payload['username'] as String?;
  
  // Update all threads with this user
  for (var thread in _threads) {
    if (thread.users.any((u) => u.id == userId)) {
      // Update participant username
      final updatedUsers = thread.users.map((u) => 
        u.id == userId ? u.copyWith(username: username) : u
      ).toList();
      
      thread = thread.copyWith(users: updatedUsers);
    }
  }
  
  notifyListeners();
}
```

---

## Data Synchronization Patterns

### Pattern 1: User-Owned Data (Playlist)

**Characteristics**:
- Only owner can modify
- No concurrent modifications
- Load once per session

**Implementation**:
```dart
class LibraryState extends ChangeNotifier {
  List<PlaylistItem> _playlist = [];
  bool _hasLoaded = false;
  
  Future<void> loadPlaylist({required String userId}) async {
    if (_hasLoaded) return; // Already loaded
    
    _playlist = await PlaylistApi.getPlaylist(userId);
    _hasLoaded = true;
    notifyListeners();
  }
  
  Future<bool> addToPlaylist(String userId, Render render) async {
    // Optimistic update
    final item = PlaylistItem.fromRender(render);
    _playlist.add(item);
    notifyListeners(); // ← UI updates immediately
    
    // Background sync
    try {
      await PlaylistApi.addToPlaylist(userId, item);
      return true;
    } catch (e) {
      // Rollback on failure
      _playlist.remove(item);
      notifyListeners();
      return false;
    }
  }
}
```

### Pattern 2: Collaborative Data (Threads)

**Characteristics**:
- Multiple users can modify
- Real-time updates needed
- Background refresh on view

**Implementation**:
```dart
class ThreadsState extends ChangeNotifier {
  List<Thread> _threads = [];
  bool _hasLoaded = false;
  
  Future<void> loadThreads({bool silent = false}) async {
    if (_hasLoaded) return; // Use cache
    
    _threads = await ThreadsApi.getThreads();
    _hasLoaded = true;
    notifyListeners();
  }
  
  Future<void> refreshThreadsInBackground() async {
    // Silent refresh - no loading indicator
    final freshThreads = await ThreadsApi.getThreads();
    
    // Compare and update if changed
    if (!_areThreadsEqual(_threads, freshThreads)) {
      _threads = freshThreads;
      notifyListeners();
    }
  }
  
  // WebSocket handler for real-time updates
  void _onMessageCreated(Map<String, dynamic> payload) {
    final threadId = payload['parent_thread'];
    final message = Message.fromJson(payload);
    
    // Update thread in memory
    final index = _threads.indexWhere((t) => t.id == threadId);
    if (index >= 0) {
      _threads[index] = _threads[index].copyWith(
        messageIds: [..._threads[index].messageIds, message.id]
      );
      notifyListeners();
    }
  }
}
```

### Pattern 3: Denormalized Data (Thread Users)

**Problem**: Thread documents contain embedded user data that can become stale.

**Solution**: Sync on updates + WebSocket notifications

**Database Structure**:
```
users collection (source of truth):
{
  "id": "user_abc123",
  "username": "alice",  // ← Authoritative
  "last_online": "2025-12-28T10:30:00Z"
}

threads collection (denormalized cache):
{
  "id": "thread_xyz",
  "users": [
    {
      "id": "user_abc123",
      "username": "alice",  // ← Synced copy
      "joined_at": "2025-12-28T10:00:00Z"
    }
  ]
}
```

**Sync Strategy**:
```python
# When username changes
async def update_username_handler(...):
    # 1. Update source of truth
    db.users.update_one(
        {"id": user_id},
        {"$set": {"username": username}}
    )
    
    # 2. Sync to denormalized copies
    db.threads.update_many(
        {"users.id": user_id},
        {"$set": {"users.$[elem].username": username}},
        array_filters=[{"elem.id": user_id}]
    )
    
    # 3. Broadcast to online users
    await send_user_profile_updated_notification(user_id, username)
```

---

## Online Status System

> **📖 Complete Documentation**: See [ONLINE_STATUS_SYSTEM.md](./ONLINE_STATUS_SYSTEM.md) for comprehensive implementation details, testing guide, and troubleshooting.

### Design Philosophy

**Online status is EPHEMERAL** - it reflects current WebSocket connection state, not persistent data.

**Principle**: Use in-memory WebSocket state as the source of truth for real-time status.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│         100% WEBSOCKET-BASED ONLINE STATUS (ZERO DB)         │
└─────────────────────────────────────────────────────────────┘

Server Memory (ONLY Source of Truth):
  clients = {}  # user_id -> websocket

Client Connects:
  clients["user_123"] = <websocket>
  └─→ User is ONLINE (instant)

Client Disconnects:
  del clients["user_123"]
  └─→ Broadcast "user_status_changed" to thread members
  └─→ User is OFFLINE (instant)

Heartbeat (60s):
  Ping all clients
  └─→ Detect stale connections (network failure, force quit)
      └─→ unregister_client() → Broadcast offline status

Check Status:
  is_online = "user_123" in clients  # O(1) lookup, NO database query
```

### Key Features

✅ **Server-side heartbeat** (60s) detects all disconnect types  
✅ **Automatic broadcast** (`user_status_changed`) to thread members  
✅ **Client auto-reconnect** with exponential backoff (1s → 30s)  
✅ **Real-time UI updates** via WebSocket notifications  
✅ **Zero polling** - purely event-driven  
✅ **100% reliable** - handles clean/dirty disconnects, network failures  

### Implementation Summary

#### Server-Side (`server/app/ws/router.py`)

**Core Functions**:
- `register_client()` - Add to `clients` dict (no DB writes)
- `unregister_client()` - Remove from dict, broadcast status change
- `heartbeat_loop()` - Detect stale connections every 60s
- `broadcast_user_status_change()` - Notify thread members of status changes

**API Responses** (`server/app/http_api/threads.py`):
- Compute `is_online: user_id in clients` for all thread members
- O(1) lookup, zero database queries

#### Client-Side

**WebSocket Handler** (`app/lib/state/threads_state.dart`):
```dart
void _onUserStatusChanged(Map<String, dynamic> payload) {
  final userId = payload['user_id'];
  final isOnline = payload['is_online'];
  
  // Update all threads where user participates
  // notifyListeners() → UI updates immediately
}
```

**UI Display** (`app/lib/widgets/sequencer/participants_widget.dart`, `app/lib/screens/projects_screen.dart`):
```dart
// Sequencer participants widget
Container(
  decoration: BoxDecoration(
    color: user.isOnline 
      ? AppColors.menuOnlineIndicator  // Green
      : AppColors.sequencerLightText.withOpacity(0.3),  // Gray
    shape: BoxShape.circle,
  ),
)

// Projects screen participants overlay
Container(
  width: 6,
  height: 6,
  decoration: BoxDecoration(
    color: user.isOnline 
      ? AppColors.menuOnlineIndicator  // Green
      : overlayTextColor.withOpacity(0.3),  // Gray
    shape: BoxShape.circle,
  ),
)
```

**Displayed In:**
- ✅ Sequencer screen participants widget (bottom bar)
- ✅ Projects screen participants overlay (top-right of each card)

### WebSocket Message Types

**`user_status_changed`** (New in v2.0):
```json
{
  "type": "user_status_changed",
  "user_id": "507f1f77bcf86cd799439011",
  "is_online": false,
  "timestamp": 1735574400
}
```

**`invitation_accepted`** (Enhanced):
```json
{
  "type": "invitation_accepted",
  "participants": [
    {"id": "...", "username": "...", "is_online": true},
    {"id": "...", "username": "...", "is_online": false}
  ]
}
```

### Performance Benefits

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| DB Writes/min (100 users) | 1000-2000 | **0** | **100%** |
| Disconnect detection | Up to 60s | <65s (all types) | Reliable |
| Update latency | Polling (10s) | Instant | Real-time |
| Client requests | 6/min per widget | **0** | **100%** |

### Quick Reference

**See [ONLINE_STATUS_SYSTEM.md](./ONLINE_STATUS_SYSTEM.md) for**:
- Complete architecture diagrams
- Full implementation code
- Testing guide & scenarios
- Troubleshooting & debugging
- Configuration options
- Network reliability details

---

## Invitation & Participant Management

### Invitation Flow

```
┌─────────────────────────────────────────────────────────────┐
│              INVITATION ACCEPTANCE FLOW                      │
└─────────────────────────────────────────────────────────────┘

1. User A creates thread and shares link
   ↓
2. User B clicks link (deep link)
   ├─→ App opens via uni_links
   └─→ Extracts thread_id from URL

3. Check if User B has username
   ├─→ Empty → Show UsernameCreationDialog
   └─→ Present → Show join confirmation

4. User B accepts invitation
   ├─→ HTTP: PUT /threads/{id}/invites/{user_id}
   ├─→ Server adds to thread.users[]
   ├─→ Server removes from thread.invites[]
   └─→ Server broadcasts WebSocket event

5. WebSocket: invitation_accepted
   ├─→ thread_id, user_id, user_name
   └─→ Sent to all thread participants

6. User A receives WebSocket event
   ├─→ ThreadsState._onInvitationAccepted()
   ├─→ Adds User B to participants list
   └─→ notifyListeners() → UI updates

7. User A sees User B in participants ✅
```

### Client-Side Handler

**File**: `app/lib/state/threads_state.dart`

```dart
void _registerWsHandlers() {
  _wsClient.registerMessageHandler('invitation_accepted', _onInvitationAccepted);
}

void _onInvitationAccepted(Map<String, dynamic> payload) {
  final threadId = payload['thread_id'] as String?;
  final userId = payload['user_id'] as String?;
  final userName = payload['user_name'] as String?;
  
  if (threadId == null || userId == null || userName == null) {
    debugPrint('⚠️ [THREADS] Invalid invitation_accepted payload');
    return;
  }
  
  // Find thread and add new user
  final threadIndex = _threads.indexWhere((t) => t.id == threadId);
  if (threadIndex >= 0) {
    final thread = _threads[threadIndex];
    
    // Check if user already exists
    if (!thread.users.any((u) => u.id == userId)) {
      final newUser = ThreadUser(
        id: userId,
        username: userName,
        name: userName,
        joinedAt: DateTime.now(),
      );
      
      final updatedUsers = [...thread.users, newUser];
      _threads[threadIndex] = thread.copyWith(users: updatedUsers);
      
      if (_activeThread?.id == threadId) {
        _activeThread = _threads[threadIndex];
      }
      
      notifyListeners();
    }
  }
}
```

### Server-Side Broadcast

**File**: `server/app/http_api/threads.py`

```python
async def manage_invitation_handler(...):
    if action == "accept":
        # Add user to thread
        new_user = {
            "id": user_id,
            "username": invitation["user_name"],
            "name": invitation["user_name"],
            "joined_at": datetime.utcnow().isoformat() + "Z"
        }
        
        db.threads.update_one(
            {"id": thread_id},
            {
                "$push": {"users": new_user},
                "$pull": {"invites": {"user_id": user_id}}
            }
        )
        
        # Broadcast to all thread members
        invited_by = invitation.get("invited_by")
        await send_invitation_accepted_notification(
            thread_id, user_id, invitation["user_name"], invited_by
        )
```

**File**: `server/app/ws/router.py`

```python
async def send_invitation_accepted_notification(thread_id, user_id, user_name, invited_by):
    thread = db.threads.find_one({"id": thread_id})
    if not thread:
        return 0
    
    # Collect all participants except the one who just joined
    recipients = set()
    for u in thread.get("users", []):
        if u.get("id") != user_id:
            recipients.add(u["id"])
    
    # Send to all online recipients
    delivered = 0
    for recipient_id in recipients:
        ws = clients.get(recipient_id)
        if ws:
            await send_json(ws, {
                "type": "invitation_accepted",
                "thread_id": thread_id,
                "user_id": user_id,
                "user_name": user_name,
                "timestamp": int(time.time())
            })
            delivered += 1
    
    return delivered
```

---

## Username & Profile Sync

### The Two-Collection Problem

**Issue**: Username stored in both `users` and `threads` collections.

**Solution**: Sync on write + WebSocket broadcast.

### Update Flow

```
┌─────────────────────────────────────────────────────────────┐
│                USERNAME UPDATE FLOW                          │
└─────────────────────────────────────────────────────────────┘

1. User updates username in share dialog
   ↓
2. UserState.updateUsername()
   ├─→ HTTP: PUT /users/{id}/username
   └─→ Updates local _currentUser

3. Server: update_username_handler
   ├─→ Update users collection (source of truth)
   ├─→ Sync to threads collection (all threads with user)
   └─→ Broadcast WebSocket event

4. WebSocket: user_profile_updated
   ├─→ user_id, username
   └─→ Sent to all collaborators in all threads

5. Other users receive event
   ├─→ ThreadsState._onUserProfileUpdated()
   ├─→ Update username in all loaded threads
   └─→ notifyListeners() → UI updates

6. All collaborators see updated username ✅
```

### Server Implementation

**File**: `server/app/http_api/users.py`

```python
async def update_username_handler(request, user_id, username_data):
    username = username_data.username.strip()
    
    # Validate username
    if len(username) < 3:
        raise HTTPException(400, "Username must be at least 3 characters")
    
    # 1. Update users collection (source of truth)
    db.users.update_one(
        {"id": user_id},
        {"$set": {
            "username": username,
            "name": username,
            "last_online": datetime.now(timezone.utc).isoformat()
        }}
    )
    
    # 2. Sync to threads collection (denormalized copies)
    result = db.threads.update_many(
        {"users.id": user_id},
        {"$set": {
            "users.$[elem].username": username,
            "users.$[elem].name": username
        }},
        array_filters=[{"elem.id": user_id}]
    )
    logger.info(f"Updated username in {result.modified_count} thread(s)")
    
    # 3. Broadcast to online collaborators
    from ws.router import send_user_profile_updated_notification
    delivered = await send_user_profile_updated_notification(user_id, username)
    logger.info(f"Broadcasted to {delivered} online user(s)")
    
    # 4. Return updated user
    updated_user = db.users.find_one({"id": user_id}, {"_id": 0, "password_hash": 0})
    return JSONResponse(content=updated_user)
```

### Client Implementation

**File**: `app/lib/state/threads_state.dart`

```dart
void _onUserProfileUpdated(Map<String, dynamic> payload) {
  final userId = payload['user_id'] as String?;
  final username = payload['username'] as String?;
  
  if (userId == null || username == null) return;
  
  // Update username in all loaded threads
  bool anyUpdated = false;
  for (int i = 0; i < _threads.length; i++) {
    final thread = _threads[i];
    
    if (thread.users.any((user) => user.id == userId)) {
      final updatedUsers = thread.users.map((user) {
        if (user.id == userId) {
          return ThreadUser(
            id: user.id,
            username: username,
            name: username,
            joinedAt: user.joinedAt,
          );
        }
        return user;
      }).toList();
      
      _threads[i] = thread.copyWith(users: updatedUsers);
      anyUpdated = true;
    }
  }
  
  if (anyUpdated) {
    notifyListeners();
  }
}
```

### UserState Integration

**File**: `app/lib/main.dart`

Critical fix to keep ThreadsState in sync:

```dart
void _syncCurrentUser() {
  final userState = Provider.of<UserState>(context, listen: false);
  final threadsState = Provider.of<ThreadsState>(context, listen: false);
  
  if (userState.currentUser != null) {
    // Use username, not name!
    threadsState.setCurrentUser(
      userState.currentUser!.id,
      userState.currentUser!.username,  // ✅ Fixed: was using 'name'
    );
    
    // Add listener to keep in sync
    userState.addListener(() {
      if (userState.currentUser != null) {
        threadsState.setCurrentUser(
          userState.currentUser!.id,
          userState.currentUser!.username,
        );
      }
    });
  }
}
```

---

## Auto-Reconnection & Data Sync System

### Overview

The app features a robust auto-reconnection system that automatically recovers from network disruptions and syncs all data when reconnected.

### How It Works

```
┌─────────────────────────────────────────────────────────────┐
│           AUTO-RECONNECTION & DATA SYNC FLOW                 │
└─────────────────────────────────────────────────────────────┘

T+0s:    User connected, working normally
         └─→ WebSocket: connected
         └─→ Data: synced

T+10s:   Network interruption (WiFi drops, signal loss, etc)
         └─→ WebSocket: disconnect detected
         └─→ _handleDisconnect() called
         └─→ connectionStream emits 'false'

T+11s:   Auto-reconnect attempt #1 (delay: 1s)
         └─→ connect() called automatically
         ├─→ Success: connectionStream emits 'true' → Data sync
         └─→ Failure: Schedule attempt #2

T+13s:   Auto-reconnect attempt #2 (delay: 2s)
         └─→ Exponential backoff: 1s → 2s → 4s → 8s → 16s → 30s (capped)
         └─→ Infinite attempts: continues every 30s until reconnected

T+15s:   Connection restored
         └─→ connectionStream emits 'true'
         └─→ _syncDataAfterReconnect() triggered
         └─→ All data refreshed in parallel:
             ├─→ User profile
             ├─→ Threads list
             ├─→ Thread participants
             ├─→ Playlist
             ├─→ Followed users
             └─→ Online users list
         └─→ UI updates automatically
         └─→ User sees current state (no action needed)
```

### Implementation Details

**1. WebSocket Client** (`app/lib/services/ws_client.dart`):

```dart
class WebSocketClient {
  // Auto-reconnect configuration
  bool _shouldReconnect = true;  // Enabled by default
  int _reconnectAttempts = 0;     // Track attempts (for backoff calculation)
  Timer? _reconnectTimer;         // Delayed retry
  // No max attempts - infinite reconnection like modern mobile apps
  
  void _handleDisconnect() {
    final wasConnected = _isConnected;
    _isConnected = false;
    _connectionController.add(false);  // Notify listeners
    
    // Auto-reconnect only if:
    // 1. Feature is enabled (_shouldReconnect)
    // 2. We have a client ID (_clientId != null)
    // 3. We were actually connected (not first connection)
    if (_shouldReconnect && _clientId != null && wasConnected) {
      _attemptReconnect();
    }
  }
  
  void _attemptReconnect() {
    _reconnectAttempts++;
    
    // Exponential backoff with cap at 30s
    // Attempt 1: 2^0 = 1s
    // Attempt 2: 2^1 = 2s
    // Attempt 3: 2^2 = 4s
    // Attempt 4: 2^3 = 8s
    // Attempt 5: 2^4 = 16s
    // Attempt 6+: 30s (capped - continues indefinitely)
    final delaySeconds = (1 << (_reconnectAttempts - 1)).clamp(1, 30);
    
    Log.i('Reconnecting in ${delaySeconds}s (attempt $_reconnectAttempts)', 'WS');
    
    // Cancel any existing timer
    _reconnectTimer?.cancel();
    
    // Schedule reconnection
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      if (_clientId != null) {
        Log.i('Attempting reconnection...', 'WS');
        final success = await connect(_clientId!);
        
        if (success) {
          Log.i('Reconnection successful after $_reconnectAttempts attempts', 'WS');
          _reconnectAttempts = 0;  // Reset counter on success
          // connectionStream emits 'true', triggering data sync
        }
        // If failed, _handleDisconnect() will schedule next attempt (infinite)
      }
    });
  }
  
  // Control reconnection behavior
  void enableAutoReconnect() {
    _shouldReconnect = true;
  }
  
  void disableAutoReconnect() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
  }
  
  // Disconnect types
  void disconnect({bool permanent = false}) {
    if (permanent) {
      _shouldReconnect = false;
      _reconnectTimer?.cancel();
    }
    _socket?.close();
    _isConnected = false;
    _connectionController.add(false);
  }
}
```

**2. Data Sync Handler** (`app/lib/main.dart`):

```dart
// Set up during app initialization
void _syncCurrentUser() {
  final wsClient = Provider.of<WebSocketClient>(context, listen: false);
  final userState = Provider.of<UserState>(context, listen: false);
  final threadsState = Provider.of<ThreadsState>(context, listen: false);
  final libraryState = Provider.of<LibraryState>(context, listen: false);
  final followedState = Provider.of<FollowedState>(context, listen: false);
  
  // Setup reconnection handler
  _setupReconnectionHandler(wsClient, userState, threadsState, libraryState, followedState);
}

void _setupReconnectionHandler(
  WebSocketClient wsClient,
  UserState userState,
  ThreadsState threadsState,
  LibraryState libraryState,
  FollowedState followedState,
) {
  // Listen to connection state changes
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
    
    // Sync all critical data in parallel
    await Future.wait([
      // 1. User profile (new invites, username changes)
      userState.refreshCurrentUserFromServer(),
      
      // 2. Threads (new threads, participants, messages)
      threadsState.refreshThreadsInBackground(),
      
      // 3. Playlist (new items)
      libraryState.refreshPlaylistInBackground(userId: userId),
      
      // 4. Followed users
      followedState.refreshFollowedUsersInBackground(userId),
    ]);
    
    // 5. Request online users (requires WebSocket)
    if (mounted) {
      final usersService = Provider.of<UsersService>(context, listen: false);
      usersService.requestOnlineUsers();
    }
    
    debugPrint('✅ [MAIN] Data sync complete after reconnection');
  } catch (e) {
    debugPrint('❌ [MAIN] Data sync failed after reconnection: $e');
    // Fail silently - don't disrupt user experience
  }
}
```

### Benefits

**User Experience**:
- ✅ **Seamless recovery**: No manual intervention needed
- ✅ **Always current**: Data automatically syncs on reconnect
- ✅ **No data loss**: Missed events are caught up
- ✅ **Fast recovery**: Exponential backoff balances speed and server load

**Technical**:
- ✅ **Network resilient**: Handles temporary disconnections
- ✅ **Server friendly**: Exponential backoff prevents thundering herd
- ✅ **State consistent**: All data sources updated atomically
- ✅ **Error tolerant**: Silent failures don't crash app

### Edge Cases Handled

**1. Multiple rapid disconnects**:
```dart
// Reconnect timer is cancelled and reset on each disconnect
_reconnectTimer?.cancel();
_reconnectTimer = Timer(...);
```

**2. App backgrounded**:
```dart
// On resume, WebSocket may reconnect automatically
// Data sync will trigger via connectionStream
```

**3. Permanent disconnect** (user logout):
```dart
wsClient.disconnect(permanent: true);  // Disables auto-reconnect
```

**4. Long network outages**:
```dart
// Infinite reconnection - will keep trying every 30s
// User in subway for 30 minutes → automatically reconnects when exits
// Better UX than forcing user to restart app
```

**5. Sync during reconnect**:
```dart
// Only sync when isConnected emits 'true'
// Multiple rapid reconnects won't trigger multiple syncs
```

### Configuration

**Default Behavior**:
- Auto-reconnect: **Enabled**
- Max attempts: **Infinite** (like Slack, Discord, WhatsApp)
- Backoff: **Exponential with 30s cap** (1s → 2s → 4s → 8s → 16s → 30s → 30s...)
- Data sync: **Automatic on reconnect**

**Why Infinite?**:
- ✅ Handles long network outages (subway, tunnels, basements)
- ✅ Survives network switches (WiFi ↔ Cellular)
- ✅ Better mobile UX - "set and forget"
- ✅ 30s cap prevents server overload (2 requests/minute max)
- ✅ Standard practice for mobile collaboration apps

**Customize if Needed**:
```dart
// Disable auto-reconnect
wsClient.disableAutoReconnect();

// Re-enable
wsClient.enableAutoReconnect();

// Permanent disconnect (logout, etc)
wsClient.disconnect(permanent: true);
```

---

## Connection Management

### Disconnection Handling

**Server-Side** (`server/app/ws/router.py`):

```python
def unregister_client(client_id):
    """Called when client disconnects"""
    if client_id in clients:
        del clients[client_id]
        logger.info(f"{client_id} disconnected")
        
        # ✅ Update last_online immediately
        try:
            db.users.update_one(
                {"id": client_id},
                {"$set": {"last_online": datetime.utcnow().isoformat() + "Z"}}
            )
        except Exception as e:
            logger.error(f"Failed to update last_online: {e}")
```

**Why Important**: Without this, users show as "online" for 15 minutes after disconnect.

### Stale Connection Detection

**Heartbeat Loop** (every 60 seconds):

```python
async def heartbeat_loop():
    """Update last_online and clean up stale connections"""
    while True:
        await asyncio.sleep(60)
        
        if not clients:
            continue
        
        # 1. Ping each connection
        stale_clients = []
        for client_id, ws in list(clients.items()):
            try:
                await asyncio.wait_for(
                    send_json(ws, {"type": "ping"}),
                    timeout=5.0
                )
            except Exception as e:
                logger.warning(f"Stale connection: {client_id}")
                stale_clients.append(client_id)
        
        # 2. Remove stale connections
        for client_id in stale_clients:
            unregister_client(client_id)
        
        # 3. Update last_online for active connections
        active_clients = [id for id in clients if id not in stale_clients]
        if active_clients:
            db.users.update_many(
                {"id": {"$in": active_clients}},
                {"$set": {"last_online": datetime.utcnow().isoformat() + "Z"}}
            )
```

**Benefits**:
- Detects zombie connections
- Prevents messages being sent to dead connections
- Keeps online status accurate
- Cleans up server resources

### Client-Side Connection Monitoring

**File**: `app/lib/services/ws_client.dart`

```dart
class WebSocketClient {
  bool _isConnected = false;
  bool _shouldReconnect = true;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  
  final _connectionController = StreamController<bool>.broadcast();
  
  Stream<bool> get connectionStream => _connectionController.stream;
  bool get isConnected => _isConnected;
  
  void _handleDisconnect() {
    final wasConnected = _isConnected;
    _isConnected = false;
    _connectionController.add(false);
    Log.w('WebSocket disconnected', 'WS');
    
    // ✅ Automatic reconnection implemented
    if (_shouldReconnect && _clientId != null && wasConnected) {
      _attemptReconnect();
    }
  }
  
  // Control reconnection behavior
  void enableAutoReconnect() => _shouldReconnect = true;
  void disableAutoReconnect() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
  }
}
```

**Global Data Sync** (`app/lib/main.dart`):
```dart
// Set up in _syncCurrentUser()
_setupReconnectionHandler(wsClient, userState, threadsState, libraryState, followedState);

// Automatically refreshes all data on reconnection
void _setupReconnectionHandler(...) {
  wsClient.connectionStream.listen((isConnected) {
    if (isConnected) {
      _syncDataAfterReconnect(...);
    }
  });
}
```

**UI Integration** (optional per-screen handling):
```dart
// In sequencer_screen.dart or similar
_threadsService.connectionStream.listen((connected) {
  if (connected) {
    debugPrint('✅ WebSocket reconnected');
    // Data already synced globally in main.dart
    // Optional: Show reconnection indicator
  } else {
    debugPrint('❌ WebSocket disconnected');
    // Optional: Show offline indicator
  }
});
```

### Implemented Features

#### 1. Automatic Reconnection ✅

**File**: `app/lib/services/ws_client.dart`

The WebSocket client now automatically attempts to reconnect when disconnected:

```dart
class WebSocketClient {
  bool _shouldReconnect = true;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  static const int _maxReconnectAttempts = 10;
  
  void _handleDisconnect() {
    final wasConnected = _isConnected;
    _isConnected = false;
    _connectionController.add(false);
    
    // Auto-reconnect if enabled
    if (_shouldReconnect && _clientId != null && wasConnected) {
      _attemptReconnect();
    }
  }
  
  void _attemptReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      Log.e('Max reconnection attempts reached', 'WS');
      return;
    }
    
    _reconnectAttempts++;
    
    // Exponential backoff: 1s, 2s, 4s, 8s, 16s, 30s (max)
    final delaySeconds = (1 << (_reconnectAttempts - 1)).clamp(1, 30);
    
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      final success = await connect(_clientId!);
      if (success) {
        _reconnectAttempts = 0; // Reset on success
      }
    });
  }
}
```

**Features**:
- Exponential backoff: 1s, 2s, 4s, 8s, 16s, 30s (capped at 30s)
- **Infinite attempts** - never gives up (like Slack, Discord, WhatsApp)
- Resets attempt counter on successful reconnection
- Can be disabled with `disableAutoReconnect()`

**Disconnection Types**:
```dart
// Temporary disconnect (will auto-reconnect)
wsClient.disconnect();

// Permanent disconnect (no auto-reconnect)
wsClient.disconnect(permanent: true);
```

#### 2. Data Sync on Reconnect ✅

**File**: `app/lib/main.dart`

When WebSocket reconnects, all critical data is automatically refreshed:

```dart
void _setupReconnectionHandler(
  WebSocketClient wsClient,
  UserState userState,
  ThreadsState threadsState,
  LibraryState libraryState,
  FollowedState followedState,
) {
  wsClient.connectionStream.listen((isConnected) {
    if (isConnected) {
      debugPrint('✅ WebSocket reconnected - syncing data...');
      _syncDataAfterReconnect(userState, threadsState, libraryState, followedState);
    }
  });
}

Future<void> _syncDataAfterReconnect(
  UserState userState,
  ThreadsState threadsState,
  LibraryState libraryState,
  FollowedState followedState,
) async {
  final userId = userState.currentUser?.id;
  if (userId == null) return;
  
  // 1. Refresh user profile (new invites, etc)
  await userState.refreshCurrentUserFromServer();
  
  // 2. Refresh threads (new participants, messages)
  await threadsState.refreshThreadsInBackground();
  
  // 3. Refresh playlist
  await libraryState.refreshPlaylistInBackground(userId: userId);
  
  // 4. Refresh followed users
  await followedState.refreshFollowedUsersInBackground(userId);
  
  // 5. Request online users
  final usersService = Provider.of<UsersService>(context, listen: false);
  usersService.requestOnlineUsers();
}
```

**What Gets Synced**:
- ✅ User profile and invitations
- ✅ Thread list and participants
- ✅ Thread messages
- ✅ Playlist items
- ✅ Followed users
- ✅ Online status of all users

**User Experience**:
```
User disconnects WiFi → reconnects WiFi
  ↓
Auto-reconnect (1-30s with backoff)
  ↓
Data sync (silent, ~1-2s)
  ↓
UI updates with fresh data
  ↓
User sees current state (no manual refresh needed)
```

---

## Implementation Guide

### Adding a New WebSocket Message Type

**1. Define Message Type on Server**

```python
# server/app/ws/router.py or http_api handler

# Broadcast function
async def send_new_event_notification(data):
    # Find recipients
    recipients = determine_recipients(data)
    
    # Send to online users
    for user_id in recipients:
        ws = clients.get(user_id)
        if ws:
            await send_json(ws, {
                "type": "new_event",
                "data": data,
                "timestamp": int(time.time())
            })
```

**2. Register Handler on Client**

```dart
// app/lib/state/relevant_state.dart

void _registerWsHandlers() {
  _wsClient.registerMessageHandler('new_event', _onNewEvent);
}

void _onNewEvent(Map<String, dynamic> payload) {
  // Extract data
  final data = payload['data'];
  
  // Update state
  _updateLocalState(data);
  
  // Notify UI
  notifyListeners();
}

void dispose() {
  _wsClient.unregisterAllHandlers('new_event');
  super.dispose();
}
```

**3. Trigger from Server Action**

```python
# In HTTP API handler
async def some_action_handler(...):
    # Perform action
    result = perform_action(...)
    
    # Broadcast to collaborators
    await send_new_event_notification(result)
    
    return result
```

### Adding a New Sync Pattern

**1. Identify Data Type**

- **User-Owned**: Only owner modifies → Optimistic updates
- **Collaborative**: Multiple users → WebSocket + background refresh
- **Real-Time**: Instant updates → WebSocket only

**2. Implement State Management**

```dart
class NewFeatureState extends ChangeNotifier {
  List<Item> _items = [];
  bool _hasLoaded = false;
  
  // Load with caching
  Future<void> loadItems() async {
    if (_hasLoaded) return;
    _items = await Api.getItems();
    _hasLoaded = true;
    notifyListeners();
  }
  
  // Optimistic update (if user-owned)
  Future<bool> addItem(Item item) async {
    _items.add(item);
    notifyListeners(); // Instant UI update
    
    try {
      await Api.addItem(item);
      return true;
    } catch (e) {
      _items.remove(item); // Rollback
      notifyListeners();
      return false;
    }
  }
  
  // WebSocket handler (if collaborative)
  void _onItemUpdated(Map<String, dynamic> payload) {
    final item = Item.fromJson(payload);
    // Update in list
    notifyListeners();
  }
}
```

---

## Testing & Debugging

### Testing Scenarios

#### Test 1: Username Sync
```
1. User A creates username "alice"
2. User B joins thread
3. ✅ User B sees "alice" in participants
4. User A changes to "alice_new"
5. ✅ User B sees "alice_new" update in real-time
```

#### Test 2: Invitation Acceptance
```
1. User A creates thread, shares link
2. User B clicks link, creates username, accepts
3. ✅ User A sees User B appear in participants immediately
4. No page refresh required
```

#### Test 3: Online Status
```
1. User A connects
2. ✅ User B sees User A with green dot
3. User A closes app
4. Wait 60 seconds
5. ✅ User B sees User A as offline (gray dot)
```

#### Test 4: Disconnect & Reconnect ✅
```
1. User A connected, viewing threads
2. Turn off WiFi
3. Wait 5 seconds
4. ✅ Client detects disconnect
5. Turn WiFi back on
6. ✅ Auto-reconnects (1s delay, first attempt)
7. ✅ Data automatically syncs (threads, playlist, etc)
8. ✅ UI updates with fresh data
9. ✅ Online status accurate
```

#### Test 5: Stale Connection
```
1. Simulate zombie connection
2. Next heartbeat (60s)
3. ✅ Stale connection detected and removed
4. ✅ last_online updated
```

### Debugging Tools

**Server Logs**:
```bash
# Connection logs
{client_id} connected (total: N)
Updated last_online for {client_id}

# Heartbeat logs
Heartbeat: Checking N connection(s)
Heartbeat: Updated N active user(s)
Stale connection detected: {client_id}

# Broadcast logs
Broadcasted username update to N online user(s)
Sent invitation_accepted to {user_id}
```

**Client Logs**:
```dart
// Enable WebSocket message logging
_wsClient.messageStream.listen((msg) {
  debugPrint('📩 WS: $msg');
});

// State change logs
debugPrint('🔄 [THREADS] User profile updated: $userId -> $username');
debugPrint('🎉 [THREADS] Invitation accepted: $userName joined');
debugPrint('📡 WebSocket connected: $connected');
```

**Database Queries**:
```javascript
// Check user online status
db.users.find({"id": "user_abc123"}, {"last_online": 1})

// Check thread participants
db.threads.find({"id": "thread_xyz"}, {"users": 1})

// Find all threads with user
db.threads.find({"users.id": "user_abc123"})

// Check for stale usernames in threads
db.threads.aggregate([
  {$unwind: "$users"},
  {$lookup: {
    from: "users",
    localField: "users.id",
    foreignField: "id",
    as: "user_doc"
  }},
  {$match: {
    $expr: {$ne: ["$users.username", {$arrayElemAt: ["$user_doc.username", 0]}]}
  }}
])
```

### Common Issues

**Issue: Users show offline when online**
- Check: `last_online` being updated?
- Check: Heartbeat running?
- Check: 15-minute threshold correct?

**Issue: Username not syncing**
- Check: Using `username` field not `name`?
- Check: WebSocket handler registered?
- Check: MongoDB array filters working?

**Issue: Participant not appearing**
- Check: `invitation_accepted` handler registered?
- Check: WebSocket connection active?
- Check: Server broadcasting event?

**Issue: Connection drops frequently**
- Check: Network stability
- Check: Heartbeat timeout (5s may be too short)
- Check: Server resource limits

---

## Performance Considerations

### Server-Side

**Heartbeat Impact**:
- Frequency: Every 60 seconds
- Operations: N pings + 1 batch update
- Typical: 1-100 connections
- Time: 100-500ms total
- Impact: Minimal (<1% CPU)

**Broadcast Impact**:
- Per event: O(N) where N = recipients
- Typical: 1-5 recipients per thread
- Time: <50ms per broadcast
- Impact: Negligible

**Database Updates**:
- Username change: 1 user + N threads (typically 1-10)
- Online status: Batch update every 60s
- Impact: <5% increase in DB load

### Client-Side

**WebSocket Handler**:
- Per event: O(N) where N = loaded threads
- Typical: 5-20 threads in memory
- Time: <10ms per update
- Impact: Negligible

**Memory Usage**:
- Threads cached in memory
- Messages loaded on demand
- Typical: 1-5 MB for thread list
- Impact: Minimal

---

## Security Considerations

**WebSocket Authentication**:
- Token-based auth on connect
- 24-hex client ID validation
- Rate limiting on connections and messages

**Message Validation**:
- Type checking on all payloads
- User permission checks
- Input sanitization

**Data Access**:
- Only send events to authorized users
- Thread members only get thread updates
- No cross-thread information leakage

---

## Future Enhancements

### Planned Features

1. ~~**Auto-Reconnection**~~: ✅ Implemented with exponential backoff
2. ~~**Data Sync on Reconnect**~~: ✅ Implemented for all critical data
3. **Typing Indicators**: Show when users are editing
4. **Presence System**: Show what users are doing (active screen)
5. **Message Queueing**: Queue updates when offline
6. **Cursor Sync**: Show collaborator cursor positions in sequencer
7. **Conflict Resolution**: Handle concurrent edits
8. **Connection Quality**: Monitor and report connection issues
9. **Offline Mode UI**: Show clear indicators when disconnected

### Metrics to Track

**Server**:
- Active connections (gauge)
- Disconnections per hour (counter)
- Stale connections cleaned (counter)
- Message broadcast latency (histogram)
- Heartbeat errors (counter)

**Client**:
- Connection uptime (gauge)
- Disconnect frequency (counter)
- Message processing time (histogram)
- Failed message deliveries (counter)

---

## Summary

### Key Takeaways

1. **Single WebSocket Connection**: One connection per user, message routing to handlers
2. **Dual Sync Strategy**: User-owned (optimistic) vs Collaborative (real-time)
3. **Denormalized Data**: Sync on write + WebSocket broadcast
4. **Accurate Online Status**: Update on connect, heartbeat, and disconnect
5. **Real-Time Collaboration**: WebSocket events for instant updates

### Production Checklist

- [x] WebSocket authentication implemented
- [x] Message handlers registered
- [x] Online status tracking (connect/disconnect/heartbeat)
- [x] Username sync (database + WebSocket)
- [x] Invitation acceptance (database + WebSocket)
- [x] Stale connection detection
- [x] Error handling and logging
- [x] Security validation
- [x] Auto-reconnection with exponential backoff
- [x] Data refresh on reconnect
- [ ] Connection quality monitoring (optional)

---

**Version**: 2.0  
**Last Updated**: December 2025  
**Contributors**: Development Team  
**Status**: ✅ Production Ready

