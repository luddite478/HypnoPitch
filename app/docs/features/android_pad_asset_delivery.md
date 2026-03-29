# Android Play Asset Delivery (PAD)

This project now uses an Android install-time asset pack for built-in samples so the Play base module stays below size limits.

## What changed

- `samples/` is packaged into `android/samples_pack` (asset pack name: `samples_pack`).
- Android release builds should use `build-android-pad-release.sh`.
- iOS behavior is unchanged and still uses bundled Flutter assets from `pubspec.yaml`.
- Dart sample loading now goes through `SampleAssetResolver`.

## Files involved

- `android/settings.gradle.kts`
- `android/app/build.gradle.kts`
- `android/samples_pack/build.gradle.kts`
- `android/app/src/main/kotlin/com/hypnopitch/app/MainActivity.kt`
- `lib/services/sample_asset_resolver.dart`
- `build-android-pad-release.sh`

## Build workflow (Android production)

Run from `app/`:

```bash
./build-android-pad-release.sh
```

The script does this:

1. Syncs `samples/` into `android/samples_pack/src/main/assets/samples/`.
2. Creates a temporary Android-only pubspec by removing `- samples/...` Flutter asset lines.
3. Runs `flutter pub get`.
4. Builds `flutter build appbundle --flavor prod --release`.
5. Restores the original `pubspec.yaml`.

Output:

- `build/app/outputs/bundle/prodRelease/app-prod-release.aab`

## Verification checklist

After each release build:

1. Confirm the app bundle exists.
2. Confirm `samples_pack` entries exist in the AAB.
3. Confirm `base/assets/flutter_assets` no longer contains `samples/...`.
4. Upload to Play Console and verify base module warning is gone.

## Runtime behavior

- On Android, sample file reads prefer the PAD path from `AssetPackManager.getPackLocation("samples_pack")`.
- If the install-time pack is not ready yet, sample browser UI shows a retry message.
- If PAD file resolution fails, resolver falls back to `rootBundle` (useful for local/dev scenarios).

## Troubleshooting

### PAD path is null

- Ensure the app is installed from an AAB with the asset pack.
- Ensure the pack name is exactly `samples_pack` in both Gradle and Dart.

### Samples not found on Android release

- Re-run `./build-android-pad-release.sh` so the pack assets are refreshed.
- Check `android/samples_pack/src/main/assets/samples/` contains audio files.
- Verify `MainActivity` channel name is `hypnopitch/pad`.

### iOS regression

- iOS still relies on `pubspec.yaml` sample asset entries.
- If iOS cannot load samples, verify `pubspec.yaml` was restored after Android build.
