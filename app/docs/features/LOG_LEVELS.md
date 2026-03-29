# Log Level System

This document describes the log level filtering system implemented in the Rehorsed app to reduce log spam and improve debugging experience.

## Overview

The app now has a configurable log level system that works on both Flutter (Dart) and Native (C++/Objective-C) sides. You can control the verbosity of logs via the `.env` file.

## Configuration

### Environment Variable

Add `LOG_LEVEL` to your `.env` file:

```env
# Log Levels: none, error, warning, info, debug
LOG_LEVEL=info
```

### Available Log Levels

| Level   | Value | Description                                          |
|---------|-------|------------------------------------------------------|
| `none`    | 0     | No logs at all                                       |
| `error`   | 1     | Only critical errors                                 |
| `warning` | 2     | Errors and warnings                                  |
| `info`    | 3     | Errors, warnings, and important info (recommended)   |
| `debug`   | 4     | All logs including verbose debug info (development)  |

### Recommended Settings

- **Development**: `LOG_LEVEL=debug` or `LOG_LEVEL=info`
- **Staging**: `LOG_LEVEL=info` (default in `.stage.env`)
- **Production**: `LOG_LEVEL=warning` or `LOG_LEVEL=error` (set in `.prod.env`)

## Usage

### Flutter/Dart Code

Use the `Log` utility class from `lib/utils/log.dart`:

```dart
import 'package:hypnopitch/utils/log.dart';

// Debug logs (only shown at debug level)
Log.d('Detailed debug information', 'TAG');

// Info logs (shown at info and debug levels)
Log.i('Important information', 'TAG');

// Warning logs (shown at warning, info, and debug levels)
Log.w('Something might be wrong', 'TAG');

// Error logs (always shown except at none level)
Log.e('Critical error occurred', 'TAG', error);

// Success logs (shown at info level)
Log.s('Operation completed successfully', 'TAG');
```

The tag parameter is optional but recommended for filtering logs by component.

### Native C++/Objective-C Code

Use the macros from `native/log.h`:

```cpp
#include "log.h"

// Define your log tag
#undef LOG_TAG
#define LOG_TAG "MY_MODULE"

// Debug logs (only shown at debug level)
prnt_debug("🔍 Detailed debug info: %d", value);

// Info logs (shown at info and debug levels)
prnt_info("ℹ️ Important info: %s", message);

// Warning logs (shown at warning, info, and debug levels)
prnt_warn("Something might be wrong: %d", code);

// Error logs (always shown except at none level)
prnt_err("❌ Critical error: %s", error);

// Legacy: prnt() maps to prnt_info()
prnt("This is an info log");
```

### Compile-Time Configuration (Native)

For native code, you can also set the log level at compile time by defining `NATIVE_LOG_LEVEL`:

```cmake
# In CMakeLists.txt
add_definitions(-DNATIVE_LOG_LEVEL=3)  # INFO level
```

Default is `3` (INFO) if not specified.

## Migration Guide

### Converting Existing Logs

**Before:**
```dart
debugPrint('🎵 [TABLE_STATE] Initializing table');
debugPrint('❌ [TABLE_STATE] Failed to load: $e');
```

**After:**
```dart
Log.d('Initializing table', 'TABLE_STATE');
Log.e('Failed to load', 'TABLE_STATE', e);
```

**Native Before:**
```cpp
prnt("🎵 [TABLE] Set cell [%d, %d]", row, col);
prnt_err("❌ [TABLE] Invalid cell: %d", cell);
```

**Native After:**
```cpp
prnt_debug("🎵 [TABLE] Set cell [%d, %d]", row, col);
prnt_err("❌ [TABLE] Invalid cell: %d", cell);
```

## Log Level Guidelines

### When to Use Each Level

- **Debug (`prnt_debug` / `Log.d`)**: 
  - Verbose operational logs
  - State changes during normal operation
  - Function entry/exit traces
  - Data dumps

- **Info (`prnt_info` / `Log.i` / `Log.s`)**:
  - Initialization completion
  - Configuration changes
  - Major state transitions
  - Connection status

- **Warning (`prnt_warn` / `Log.w`)**:
  - Recoverable errors
  - Deprecated API usage
  - Performance issues
  - Unexpected but handled conditions

- **Error (`prnt_err` / `Log.e`)**:
  - Unrecoverable errors
  - Failed operations
  - Invalid parameters
  - System failures

## Examples

### Reduced Log Output

With `LOG_LEVEL=info`, verbose logs are hidden:

**Before (all logs shown):**
```
TABLE: 🎵 [TABLE] Set cell [0, 0]: slot=0
TABLE: 🎵 [TABLE] Set cell [0, 1]: slot=1
TABLE: 🎵 [TABLE] Set cell [0, 2]: slot=2
SUNVOX: 📝 [SUNVOX] Set pattern event [section=0, line=0, col=0]
SUNVOX: 📝 [SUNVOX] Set pattern event [section=0, line=1, col=0]
...
```

**After (only info+ shown):**
```
TABLE: ✅ [TABLE] Table initialized successfully
SUNVOX: ✅ [SUNVOX] Created pattern 0 for section 0
PLAYBACK: ✅ [PLAYBACK] Playback system initialized
```

### Debug Mode

With `LOG_LEVEL=debug`, all logs are shown including verbose operational details.

## Benefits

1. **Reduced Noise**: Production builds can hide verbose logs
2. **Better Performance**: Fewer logs = less overhead
3. **Easier Debugging**: Focus on relevant logs by adjusting level
4. **Consistent Filtering**: Same system works across Flutter and Native code
5. **Easy Configuration**: Change one variable to control all logs

## Implementation Details

- **Flutter**: Uses `flutter_dotenv` to read `LOG_LEVEL` from `.env`
- **Native**: Uses preprocessor macros with compile-time level checking
- **Backward Compatible**: Old `prnt()` calls still work (mapped to info level)
- **Zero Overhead**: Disabled logs are compile-time removed in native code






