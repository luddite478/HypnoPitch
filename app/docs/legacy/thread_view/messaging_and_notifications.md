## Messaging and Notifications (Current Implementation)

> ℹ️ **For complete real-time system documentation**, see [REALTIME_COLLABORATION_SYSTEM.md](../REALTIME_COLLABORATION_SYSTEM.md)

This document summarizes how the app handles thread messages (snapshots) and real-time notifications using both HTTP API and WebSockets.

### Components
- HTTP API (FastAPI):
  - Threads
    - `GET /threads` – list threads (optionally filtered by user_id)
    - `GET /threads/{id}` – fetch a single thread document
    - `POST /threads` – create thread
    - Invites
      - `POST /threads/{thread_id}/invites` – send invite (adds `invites[]`, sets status=pending, updates user `pending_invites_to_threads`)
      - `PUT /threads/{thread_id}/invites/{user_id}` – accept/decline (updates `users[]`, removes from `invites[]`, updates user `pending_invites_to_threads`)
  - Messages
    - `GET /messages?thread_id=...` – list messages for a thread (ascending by `timestamp`)
    - `POST /messages` – create a message (snapshot)
    - `DELETE /messages/{message_id}` – delete a message and pull id from thread

- WebSocket server:
  - Auth handshake: client sends `{ token, client_id }` (client_id must be 24-hex).
  - Real-time events delivered to online users:
    - `thread_invitation` – emitted to invited user when an invitation is created
    - `invitation_accepted` – emitted to inviter and thread members on acceptance
    - `message_created` – emitted to all online thread members when a message is created

### App wiring
- Single `WebSocketClient` service shared via Provider.
- `ThreadsService` and `NotificationsService` register WS handlers:
  - `thread_invitation` → shows top overlay; triggers a quick refresh of the current user and loads the invited thread summary so Projects shows INVITES immediately.
  - `invitation_accepted` → shows overlay; UI removes the thread id from `pending_invites_to_threads` and updates the thread participants when present in memory.
  - `message_created` → shows overlay unless user is already viewing that thread; reconciliation replaces any local pending item.

### UI patterns
- Projects screen:
  - Shows `INVITES` above `RECENT` when `pending_invites_to_threads` is non-empty.
  - Invite rows are visually identical to project rows, except the right side shows `ACCEPT` and `DENY` actions instead of timestamp/chevron.
  - Participant chips are rendered on the right of the second line, consistent with project rows.

- Thread screen:
  - Loads full message list for the active thread (for now) and renders messages with snapshot previews.

- Global notification surface:
  - Non-blocking top overlay (OverlayEntry) with small padding and a black-square icon (same as row icon). It does not shift layout.
  - Message text uses the bold style; auto-dismisses after ~4s.

### Data rules and storage
- Threads:
  - Fields: `id`, `users[] { id, name, joined_at }`, `messages[]` (message ids), `invites[]`, `created_at`, `updated_at`.
- Messages:
  - Fields: `id`, `created_at`, `timestamp`, `user_id`, `parent_thread`, `snapshot`, optional `snapshot_metadata`.
- Users:
  - Includes `pending_invites_to_threads[]` and `threads[]` (membership).

### Notes on duplication and guards
- Multiple call sites might request the same thread around invite receipt; client-side guards were added in `ThreadsState.loadThread(...)` (in‑flight lock and short debounce).
- For optimal behavior, prefer:
  - Summaries on list/INVITES screens
  - Full messages only on Thread screen
  - Latest-only fetch for Sequencer resume (see optimization proposal)




