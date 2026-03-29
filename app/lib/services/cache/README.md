# Cache Services

## ✅ Fully Implemented and Ready to Use

This folder contains the complete offline-first caching system:

- **Threads caching** - cache-first with background sync
- **Messages caching** - incremental sync + optimistic updates  
- **Snapshots caching** - on-demand with LRU eviction
- **Audio caching** - size-based LRU (1GB limit)
- **Audio deduplication** - content-based addressing on server
- **Offline support** - queue operations, process when online

## 📚 Documentation

**Read**: [`CACHING_SYSTEM.md`](./CACHING_SYSTEM.md) - Complete guide with examples and API reference

## 🚀 Quick Start

```dart
import 'package:hypnopitch/services/cache/threads_cache_service.dart';
import 'package:hypnopitch/services/cache/messages_cache_service.dart';

// Load threads (instant from cache, syncs in background)
final threads = await ThreadsCacheService.loadThreads(userId: userId);

// Load messages (cached + new since last sync)
final messages = await MessagesCacheService.loadMessages(threadId: threadId);

// Create message (optimistic update)
await MessagesCacheService.createMessage(
  threadId: threadId,
  message: message,
);
```

Everything works automatically - just use the services!

## 📁 Services

| File | Purpose | Status |
|------|---------|--------|
| `local_cache_service.dart` | Base file I/O operations | ✅ Ready |
| `sync_state_service.dart` | Track last sync times | ✅ Ready |
| `threads_cache_service.dart` | Thread metadata caching | ✅ Ready |
| `messages_cache_service.dart` | Message caching + sync | ✅ Ready |
| `snapshots_cache_service.dart` | Snapshot caching + LRU | ✅ Ready |
| `offline_sync_service.dart` | Offline operations queue | ✅ Ready |

**Note**: `audio_cache_service.dart` is in parent `/services` folder (already existed, enhanced for deduplication)

## 🎯 Next Steps

1. ✅ All services implemented
2. ✅ Audio deduplication on server
3. ✅ Documentation complete
4. 🚀 **Ready to deploy!**

See [`CACHING_SYSTEM.md`](./CACHING_SYSTEM.md) for complete documentation.

