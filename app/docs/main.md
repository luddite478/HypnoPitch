# Rehorsed - Flutter FFI + Miniaudio Integration Project

**Grid Layout:**
- **4 columns × 16 rows** = 64 cells total (will be configurable in feature)
- **Column = Track**: Each column represents an independent audio track
- **Row = Step**: Each row represents a 1/16 note timing step
- **Visual feedback**: Current playing step highlighted with yellow border

**Timing & BPM:**
- **120 BPM default** with precise timing calculation (wil lbe configurable)
- **1/16 note resolution**: Each step = 125ms at 120 BPM
- **Formula**: `stepDuration = (60 * 1000) / (bpm * 4)` milliseconds
- **Automatic looping**: Continuously cycles through steps 1-16

**Sound Management:**
- **Simultaneous playback**: All sounds on current step play together
- **Column-based replacement**: Sound in column only stops when new sound appears in same column
- **Cross-step sustain**: Sounds continue playing until explicitly replaced
- **Loop continuation**: Sounds from step 16 continue into step 1 if no replacement

**Sequencer Controls:**
- **Play button** (green): Starts sequencer from step 1
- **Stop button** (red): Stops sequencer and all sounds completely
- **Real-time display**: Shows current step (X/16) and BPM
- **Status indicator**: "PLAYING" vs "STOPPED"

**Example Workflow:**
1. Load samples into slots A-H (memory-loaded instantly)
2. Select sample → tap grid cells to place in sequence
3. Press Play → sequencer loops through 16 steps at BPM tempo
4. Each step plays all placed samples simultaneously
5. Column sounds sustain until replaced by new sound in same column

**Native Implementation:**
- **UI Grid Merging**: Multiple UI sound grids are merged into a single unified table in native code
- **Grid Abstraction**: The Flutter UI manages multiple visual grids (e.g., 3 stacked cards), but the native audio engine sees one consolidated sequencer table
- **Simplified Audio Logic**: Native sequencer code operates on a single grid data structure, regardless of UI complexity
- **Efficient Data Transfer**: FFI calls pass the merged grid state to avoid multiple native calls per UI grid
- **Single Audio Timeline**: All UI grids contribute to one unified audio playback sequence in the native mixer

### **🎧 Bluetooth Audio Integration**
**Hybrid Framework Approach:**
- **AVFoundation** (iOS audio session management) 
- **CoreAudio** (miniaudio backend for performance)
- **No conflicts** - AVFoundation configures first, miniaudio respects the session

**Critical Configuration:**
```objective-c
// Prevent miniaudio from overriding our Bluetooth config
#define MA_NO_AVFOUNDATIONR

// Configure session with Bluetooth support (WITHOUT DefaultToSpeaker)
[session setCategory:AVAudioSessionCategoryPlayback
         withOptions:AVAudioSessionCategoryOptionAllowBluetooth |
                   AVAudioSessionCategoryOptionAllowBluetoothA2DP
               error:&error];
```

**Why This Works:**
- **Prevents Override**: `MA_NO_AVFOUNDATION` stops miniaudio from forcing `DefaultToSpeaker`
- **External Control**: Our AVFoundation setup configures Bluetooth routing before miniaudio init
- **Automatic Routing**: iOS handles device switching based on our session configuration

### **🎵 MP3 320kbps Audio Conversion**
**High-Quality MP3 Export**: Convert recorded WAV files to professional-grade 320kbps MP3 format using native LAME encoder integration.

**LAME Implementation Architecture:**
- **Manual Native Integration**: LAME 3.100 source code manually integrated alongside miniaudio
- **No Package Dependencies**: Avoids discontinued Flutter packages and licensing issues
- **Commercial-Friendly**: Uses LGPL-licensed LAME for commercial app compatibility
- **Cross-Platform Ready**: Native integration works on both iOS and Android

**Technical Implementation:**

**Native Integration Pattern:**
```c
// LAME wrapper follows same pattern as miniaudio integration
native/
├── lame_wrapper.h          // FFI function definitions
├── lame_wrapper.mm         // Implementation with proper format conversion
├── lame_prefix.h           // System headers for all LAME sources
└── lame/                   // LAME 3.100 source files
    ├── lame.c, bitstream.c, encoder.c, etc.
    └── config.h            // Platform-specific configuration
```

**Smart WAV Format Detection:**
```c
// Properly parses WAV headers instead of assuming format
typedef struct {
    char riff[4];           // "RIFF"
    uint32_t chunk_size;    // File size - 8
    char wave[4];           // "WAVE"
    // ... complete WAV header structure
    uint16_t audio_format;   // 1 = PCM, 3 = IEEE float
    uint16_t num_channels;   // 1 = mono, 2 = stereo
    uint32_t sample_rate;    // Actual sample rate
    uint16_t bits_per_sample; // 16-bit or 32-bit
} wav_header_t;
```

**Audio Format Conversion:**
```c
// Handles miniaudio's 32-bit float output correctly
if (header.audio_format == 3 && header.bits_per_sample == 32) {
    // IEEE float (32-bit) - what miniaudio outputs
    float* float_samples = (float*)wav_buffer;
    for (int i = 0; i < read_frames * header.num_channels; i++) {
        // Convert float (-1.0 to 1.0) to 16-bit signed int (-32768 to 32767)
        float sample = float_samples[i];
        if (sample > 1.0f) sample = 1.0f;
        if (sample < -1.0f) sample = -1.0f;
        pcm_buffer[i] = (short int)(sample * 32767.0f);
    }
}
```

**iOS Build Configuration:**
```
// Added to all iOS build configurations (Debug/Release/Profile)
GCC_PREFIX_HEADER = "$(SRCROOT)/../native/lame_prefix.h";
HEADER_SEARCH_PATHS = (
    "$(SRCROOT)/../native",
    "$(SRCROOT)/../native/lame_ios",
);
OTHER_CFLAGS = (
    "-DHAVE_CONFIG_H",  // Enable LAME configuration
);
```

**Android Build Configuration:**
```cmake
# native/CMakeLists.txt
set(SOURCES
  miniaudio_wrapper.mm
  lame_wrapper.mm
  # All LAME source files included
  lame/lame.c lame/bitstream.c lame/encoder.c
  # ... (19 total LAME source files)
)

add_definitions(-DHAVE_CONFIG_H)
include_directories(lame)
```

**FFI Integration:**
```dart
// lib/lame_library.dart - Same pattern as MiniaudioLibrary
class LameLibrary {
  static LameLibrary? _instance;
  late final LameBindingsGenerated _bindings;
  
  // Convert WAV to MP3 with error handling
  Future<ConversionResult> convertWavToMp3({
    required String wavPath,
    required String mp3Path,
    int bitrate = 320,
  }) async {
    // Run conversion in isolate to prevent UI blocking
    return await compute(_convertInIsolate, {
      'wavPath': wavPath,
      'mp3Path': mp3Path,
      'bitrate': bitrate,
    });
  }
}
```

**Conversion Service Integration:**
```dart
// lib/services/audio_conversion_service.dart
class AudioConversionService {
  static final _lameLibrary = LameLibrary.instance;
  
  static Future<String?> convertToMp3({
    required String wavFilePath,
    int bitrate = 320,
  }) async {
    // Initialize LAME if not already done
    if (!_lameLibrary.checkAvailability()) {
      await _lameLibrary.initialize();
    }
    
    // Convert with progress tracking
    final result = await _lameLibrary.convertWavToMp3(
      wavPath: wavFilePath,
      mp3Path: mp3FilePath,
      bitrate: bitrate,
    );
    
    return result.success ? mp3FilePath : null;
  }
}
```

**Usage Workflow:**
1. **Record Audio**: Create beats using the step sequencer and record to WAV
2. **Convert**: Tap MP3 export button to convert WAV to 320kbps MP3
3. **Share**: Export high-quality MP3 files for professional use
4. **Quality**: Maintains full dynamic range and frequency response of original recording

**Technical Resolution:**
✅ **Fixed Audio Noise**: Proper 32-bit float to 16-bit signed integer conversion  
✅ **No Build Issues**: Manual LAME integration with prefix headers  
✅ **Cross-Platform**: Works on both iOS and Android builds  
✅ **Commercial Ready**: LGPL licensing suitable for app store distribution

## 🔄 **Complete Step-by-Step Setup Guide**

### 1. **iOS Configuration**
- Update `ios/Podfile` with Flutter CocoaPods setup
- Add files to Xcode project (native/*.c and native/*.h)  
- Configure Build Settings: Strip Style → "Non-Global Symbols"
- Add permissions to `ios/Runner/Info.plist`:
```xml
<key>NSDocumentPickerUsageDescription</key>
<string>This app needs access to files to select audio files for playback.</string>
<key>LSSupportsOpeningDocumentsInPlace</key>
<true/>
<key>UIFileSharingEnabled</key>
<true/>
```

### 2. **Building and Running**

### **Android: Building and Running**

**1. Build the APK (Debug):**
```bash
cd android
./gradlew assembleDebug
or 
flutter build apk --flavor stage --debug
```

**2. Install on Emulator or Device:**
```bash
adb -s DEVICE_ID  install -r build/app/outputs/flutter-apk/app-stage-debug.apk
```
- The `-r` flag reinstalls the app if it already exists.
- Make sure your emulator or device is running and visible to `adb devices`.

### **Important Notes on CMake and Gradle Configuration (Android Native Builds)**

- **CMake Configuration:**
  - The main CMake file is at `native/CMakeLists.txt`.
  - It configures the native build, sets up sources (e.g., `miniaudio_wrapper.mm`), and applies C++ flags for Objective-C++ files.
  - For Android, it links against `OpenSLES` and `log` libraries for audio and logging support.
  - Edit this file to add or remove native sources or change build flags.

- **Gradle Configuration:**
  - The Android Gradle config is in `android/app/build.gradle.kts`.
  - Uses `externalNativeBuild` to point to the CMake file (`../../native/CMakeLists.txt`).
  - Sets the NDK version (`ndkVersion`), ABI filters (armeabi-v7a, arm64-v8a, x86, x86_64), and JNI source directory.
  - Requires the Android NDK and CMake to be installed (install via Android Studio > SDK Manager > SDK Tools).

- **gradle.properties and local.properties:**
  - `local.properties` must have `sdk.dir` (Android SDK path) and `flutter.sdk` (Flutter SDK path).
  - `gradle.properties` can be tuned for JVM memory and other Gradle options.

- **Gradle Wrapper:**
  - The project uses Gradle 8.12 (see `android/gradle/wrapper/gradle-wrapper.properties`).
  - The wrapper ensures consistent Gradle version for all developers.

- **Native Header/Sources:**
  - Native APIs are defined in `native/miniaudio_wrapper.h` and implemented in `native/miniaudio_wrapper.mm`.
  - Platform-specific flags and logging are handled in the source files for Android/iOS/other.

---

### **iOS: Building and Running**

#### **Simulator Setup**
```bash
# Install pods
cd ios && pod install && cd ..

# Run on simulator
flutter run
```

#### **Simulator Testing Guide**

**Step 1: Find Your Simulator Device ID**
```bash
xcrun simctl list devices
```
Look for your running simulator (e.g., "iPhone 15 (E84AFBA4-AB0D-4EEE-9C13-5D7F0004BFFF) (Booted)")

**Step 2: Launch Simulator**
```bash
rm -rf ~/Library/Developer/CoreSimulator/Caches/*
xcrun simctl boot "iPhone SE (3rd generation)" 
open -a Simulator
./run-ios.sh stage simulator 'iPhone SE (3rd generation)' "" ""
cd ios && flutter run --debug
xcrun simctl addmedia E84AFBA4-AB0D-4EEE-9C13-5D7F0004BFFF ~/path/to/your/audio.wav
```

#### **Physical Device Deployment**

1. **Build Release Version**:
```bash
flutter build ios --release
```

2. **Install ios-deploy** (if not already installed):
```bash
npm install -g ios-deploy
```

3. **List Connected Devices**:
```bash
ios-deploy -c
```
This will show your connected iPhone with its ID (e.g., `00008110-000251422E02601E`)

4. **Deploy the Release Build**:
```bash
ios-deploy --bundle build/ios/iphoneos/Runner.app --id <YOUR_DEVICE_ID>
```
Replace `<YOUR_DEVICE_ID>` with your actual device ID from step 3.

5. **IOS physical device logs**
Xcode -> Window -> Devices and Simulators -> Open Console -> filter "flutter" or "Runner"


**Note**: Make sure your iPhone is:
- Connected via USB
- Unlocked
- Trusts your development computer
- Has developer mode enabled in Settings → Privacy & Security → Developer Mode

