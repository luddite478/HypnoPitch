# HypnoPitch

## Description
A music mobile application made to be as simple as possible.

## Platforms
Supports iOS and Android.

## Tech Stack
- **App:** Flutter/Dart
- **Bridge:** Dart FFI (generated or hand-written bindings)
- **Native:** C/Objective-C++ layer integrating [sunvox_lib](https://warmplace.ru/soft/sunvox/sunvox_lib.php) and [miniaudio](https://miniaud.io/)

## Acknowledgements
This project uses the [SunVox library](https://warmplace.ru/soft/sunvox/sunvox_lib.php) by Alexander Zolotov, with modifications listed in [MODIFICATIONS.md](app/native/sunvox_lib/MODIFICATIONS.md).

It also uses [miniaudio](https://miniaud.io/) by David Reid ([GitHub](https://github.com/mackron/miniaudio)).

For MP3 encoding, this project includes [LAME](https://lame.sourceforge.io/) (LGPL). The vendored sources under [`app/native/lame_ios`](app/native/lame_ios) and [`app/native/lame_android`](app/native/lame_android) include local changes for iOS and Android builds.
