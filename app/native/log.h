#ifndef HYPNOPITCH_LOG_H
#define HYPNOPITCH_LOG_H

#ifdef prnt
#undef prnt
#endif
#ifdef prnt_err
#undef prnt_err
#endif
#ifdef prnt_warn
#undef prnt_warn
#endif
#ifdef prnt_info
#undef prnt_info
#endif
#ifdef prnt_debug
#undef prnt_debug
#endif

#ifndef LOG_TAG
#define LOG_TAG "NATIVE"
#endif

// Log levels: 0=NONE, 1=ERROR, 2=WARNING, 3=INFO, 4=DEBUG
// Set via NATIVE_LOG_LEVEL environment variable or default to INFO (3)
#ifndef NATIVE_LOG_LEVEL
#define NATIVE_LOG_LEVEL 4  // Default to INFO (can be overridden at compile time)
#endif

// Platform-specific logging implementations
#ifdef __APPLE__
    #include <os/log.h>
    #define LOG_IMPL(level, fmt, ...) do { \
        if (NATIVE_LOG_LEVEL >= level) { \
            os_log(OS_LOG_DEFAULT, "%{public}s: " fmt, LOG_TAG, ##__VA_ARGS__); \
        } \
    } while(0)
    #define LOG_ERR_IMPL(fmt, ...) do { \
        if (NATIVE_LOG_LEVEL >= 1) { \
            os_log_error(OS_LOG_DEFAULT, "%{public}s: " fmt, LOG_TAG, ##__VA_ARGS__); \
        } \
    } while(0)
#elif defined(__ANDROID__)
    #include <android/log.h>
    #define LOG_IMPL(level, fmt, ...) do { \
        if (NATIVE_LOG_LEVEL >= level) { \
            __android_log_print(ANDROID_LOG_INFO, LOG_TAG, fmt, ##__VA_ARGS__); \
        } \
    } while(0)
    #define LOG_ERR_IMPL(fmt, ...) do { \
        if (NATIVE_LOG_LEVEL >= 1) { \
            __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, fmt, ##__VA_ARGS__); \
        } \
    } while(0)
#else
    #include <stdio.h>
    #define LOG_IMPL(level, fmt, ...) do { \
        if (NATIVE_LOG_LEVEL >= level) { \
            printf("%s: " fmt "\n", LOG_TAG, ##__VA_ARGS__); \
        } \
    } while(0)
    #define LOG_ERR_IMPL(fmt, ...) do { \
        if (NATIVE_LOG_LEVEL >= 1) { \
            fprintf(stderr, "%s: " fmt "\n", LOG_TAG, ##__VA_ARGS__); \
        } \
    } while(0)
#endif

// Logging macros with level filtering
#define prnt_err(fmt, ...) LOG_ERR_IMPL(fmt, ##__VA_ARGS__)              // Level 1: ERROR
#define prnt_warn(fmt, ...) LOG_IMPL(2, "⚠️ " fmt, ##__VA_ARGS__)       // Level 2: WARNING
#define prnt_info(fmt, ...) LOG_IMPL(3, fmt, ##__VA_ARGS__)             // Level 3: INFO
#define prnt_debug(fmt, ...) LOG_IMPL(4, "🔍 " fmt, ##__VA_ARGS__)      // Level 4: DEBUG

// Backward compatibility: prnt() maps to INFO level
#define prnt(fmt, ...) prnt_info(fmt, ##__VA_ARGS__)

#endif


