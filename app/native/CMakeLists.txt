cmake_minimum_required(VERSION 3.10)
project(hypnopitch_native LANGUAGES C CXX)

# Ensure modern C++ for header-only libraries like nlohmann/json
set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# LAME source files (shared between libraries)
set(LAME_SOURCES
  lame/lame.c
  lame/bitstream.c
  lame/encoder.c
  lame/fft.c
  lame/id3tag.c
  lame/newmdct.c
  lame/presets.c
  lame/psymodel.c
  lame/quantize.c
  lame/quantize_pvt.c
  lame/reservoir.c
  lame/set_get.c
  lame/tables.c
  lame/takehiro.c
  lame/util.c
  lame/vbrquantize.c
  lame/VbrTag.c
  lame/version.c
  lame/gain_analysis.c
)

# Sequencer library sources (includes conversion functionality)
set(SEQUENCER_SOURCES
  conversion.mm
  table.mm
  playback_sunvox.mm
  sunvox_wrapper.mm
  microphone_input.mm
  recording.mm
  wav_writer.mm
  miniaudio_impl.mm
  sample_bank.mm
  undo_redo.mm
  preview.mm
)

set_source_files_properties(
  conversion.mm
  table.mm
  playback_sunvox.mm
  sunvox_wrapper.mm
  microphone_input.mm
  recording.mm
  miniaudio_impl.mm
  sample_bank.mm
  undo_redo.mm
  preview.mm
  PROPERTIES
  LANGUAGE CXX
  COMPILE_FLAGS "-x c++"
)

# Define necessary macros
add_definitions(-DMA_NO_AAUDIO)
add_definitions(-DHAVE_CONFIG_H)

# Disable NASM and assembly optimizations for Android
if(ANDROID)
  add_definitions(-DHAVE_NASM=0)
  add_definitions(-UMMX_choose_table)
endif()

# Include directories
if(ANDROID)
  include_directories(lame_android)
  list(APPEND SEQUENCER_SOURCES
    lame_android/lame.c
    lame_android/bitstream.c
    lame_android/encoder.c
    lame_android/fft.c
    lame_android/id3tag.c
    lame_android/newmdct.c
    lame_android/presets.c
    lame_android/psymodel.c
    lame_android/quantize.c
    lame_android/quantize_pvt.c
    lame_android/reservoir.c
    lame_android/set_get.c
    lame_android/tables.c
    lame_android/takehiro.c
    lame_android/util.c
    lame_android/vbrquantize.c
    lame_android/VbrTag.c
    lame_android/version.c
    lame_android/gain_analysis.c
    lame_android/nasm_stubs.c
  )
else()
  include_directories(lame)
  list(APPEND SEQUENCER_SOURCES ${LAME_SOURCES})
endif()

include_directories(miniaudio)

# Add SunVox library header directory
include_directories(sunvox_lib/sunvox_lib/headers)

# Create sequencer library (includes both sequencer and conversion functionality)
add_library(sequencer SHARED ${SEQUENCER_SOURCES})

# Link SunVox static library
if(ANDROID)
  # Android: link prebuilt SunVox shared library for the active ABI.
  # We support a few common locations to keep local workflows flexible.
  set(SUNVOX_ANDROID_CANDIDATES
    ${CMAKE_CURRENT_SOURCE_DIR}/sunvox_lib/sunvox_lib/android/sample_project/SunVoxLib/src/main/jniLibs/${ANDROID_ABI}/libsunvox.so
    ${CMAKE_CURRENT_SOURCE_DIR}/sunvox_lib/sunvox_lib/android/sample_project/SunVoxLib/src/main/jniLibs/${ANDROID_ABI}/sunvox.so
    ${CMAKE_CURRENT_SOURCE_DIR}/sunvox_lib/sunvox_lib/android/libs/${ANDROID_ABI}/libsunvox.so
    ${CMAKE_CURRENT_SOURCE_DIR}/sunvox_lib/sunvox_lib/android/libs/${ANDROID_ABI}/sunvox.so
    ${CMAKE_CURRENT_SOURCE_DIR}/sunvox_lib/sunvox_lib/android/${ANDROID_ABI}/libsunvox.so
    ${CMAKE_CURRENT_SOURCE_DIR}/sunvox_lib/sunvox_lib/android/${ANDROID_ABI}/sunvox.so
    ${CMAKE_CURRENT_SOURCE_DIR}/${ANDROID_ABI}/libsunvox.so
    ${CMAKE_CURRENT_SOURCE_DIR}/${ANDROID_ABI}/sunvox.so
  )

  set(SUNVOX_ANDROID_LIB "")
  foreach(candidate ${SUNVOX_ANDROID_CANDIDATES})
    if(EXISTS "${candidate}")
      set(SUNVOX_ANDROID_LIB "${candidate}")
      break()
    endif()
  endforeach()

  if(SUNVOX_ANDROID_LIB STREQUAL "")
    message(FATAL_ERROR
      "SunVox Android library not found for ABI '${ANDROID_ABI}'. "
      "Build it with: cd native/sunvox_lib/sunvox_lib/make && bash MAKE_ANDROID, "
      "then place sunvox.so (or libsunvox.so) under one of:\n"
      "  1) native/sunvox_lib/sunvox_lib/android/sample_project/SunVoxLib/src/main/jniLibs/${ANDROID_ABI}/\n"
      "  2) native/sunvox_lib/sunvox_lib/android/libs/${ANDROID_ABI}/\n"
      "  3) native/sunvox_lib/sunvox_lib/android/${ANDROID_ABI}/\n"
      "  4) native/${ANDROID_ABI}/")
  endif()

  add_library(sunvox SHARED IMPORTED)
  set_target_properties(sunvox PROPERTIES IMPORTED_LOCATION "${SUNVOX_ANDROID_LIB}")

  target_link_libraries(sequencer
    sunvox
    OpenSLES
    log
    android
  )
elseif(APPLE)
  # iOS/macOS: Link iOS static library
  target_link_libraries(sequencer 
    ${CMAKE_CURRENT_SOURCE_DIR}/sunvox_lib/sunvox_lib/ios/libsunvox.a
  )
endif()