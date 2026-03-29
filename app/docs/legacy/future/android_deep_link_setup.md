# Android Deep Link Setup Guide

This guide explains how to set up deep link verification for Android using App Links.

## Overview

Android App Links require a SHA256 certificate fingerprint to verify that your app is authorized to open links from your domain. This fingerprint must be added to the `assetlinks.json` file hosted on your server.

## Getting Your SHA256 Fingerprint

### For Debug Builds

1. Navigate to your Android project directory:
   ```bash
   cd app/android
   ```

2. Run the signing report command:
   ```bash
   ./gradlew signingReport
   ```

3. Look for the output under **"Variant: debug"** and find the SHA256 line:
   ```
   Variant: debug
   Config: debug
   Store: /Users/yourname/.android/debug.keystore
   Alias: AndroidDebugKey
   MD5: XX:XX:XX:...
   SHA1: XX:XX:XX:...
   SHA-256: AB:CD:EF:12:34:56:78:90:AB:CD:EF:12:34:56:78:90:AB:CD:EF:12:34:56:78:90:AB:CD:EF:12:34:56
   Valid until: ...
   ```

4. Copy the SHA256 value (remove the colons):
   ```
   ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890
   ```

### For Release Builds

For production apps, you'll need the SHA256 from your release keystore:

1. If using a custom keystore:
   ```bash
   keytool -list -v -keystore /path/to/your-release-key.keystore -alias your-key-alias
   ```

2. Enter your keystore password when prompted

3. Copy the SHA256 certificate fingerprint

## Configuring the Server

Add the SHA256 fingerprint as an environment variable in your server configuration:

### Docker Compose

Edit your `docker-compose.yaml` or `.env` file:

```yaml
services:
  server:
    environment:
      - ANDROID_SHA256_FINGERPRINT=ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890
```

### Direct Environment Variable

```bash
export ANDROID_SHA256_FINGERPRINT="ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890"
```

## Verifying the Setup

1. **Check the assetlinks.json endpoint:**
   ```bash
   curl https://yourdomain.com/.well-known/assetlinks.json
   ```

   Expected output:
   ```json
   [{
     "relation": ["delegate_permission/common.handle_all_urls"],
     "target": {
       "namespace": "android_app",
       "package_name": "com.example.rehorsed",
       "sha256_cert_fingerprints": ["AB:CD:EF:12:34:56:..."]
     }
   }]
   ```

2. **Test with Google's Digital Asset Links tester:**
   - Visit: https://developers.google.com/digital-asset-links/tools/generator
   - Enter your domain and package name
   - Verify the relationship is detected

3. **Test on device:**
   ```bash
   # Install the app on device or emulator
   flutter run
   
   # Then open a deep link
   adb shell am start -W -a android.intent.action.VIEW \
     -d "https://yourdomain.com/join/thread123" \
     com.example.rehorsed
   ```

## Troubleshooting

### Link opens in browser instead of app

- Ensure the `assetlinks.json` file is accessible without redirects
- Check that the SHA256 fingerprint matches exactly
- Android caches the assetlinks.json file - you may need to:
  - Uninstall and reinstall the app
  - Clear the app's data
  - Wait up to 24 hours for cache to expire

### "Unable to verify app" in Android Studio

- Make sure `android:autoVerify="true"` is set in your `AndroidManifest.xml`
- Verify the server is serving the file over HTTPS (not HTTP)
- Check that the package name in `assetlinks.json` matches your app

### Multiple Environments (Stage/Prod)

For different environments, you'll need:
- Different domains (e.g., `devtest.4tnd.link` and `4tnd.link`)
- The same SHA256 fingerprint works for both if using the same signing key
- Separate `assetlinks.json` files on each domain

## Current Implementation

The server automatically generates the `assetlinks.json` file at runtime using:
- `ANDROID_SHA256_FINGERPRINT` environment variable
- Package name: `com.example.rehorsed` (hardcoded in `server/app/http_api/deep_links.py`)

See `server/app/http_api/deep_links.py` for the implementation.

## References

- [Android App Links Documentation](https://developer.android.com/training/app-links)
- [Digital Asset Links](https://developers.google.com/digital-asset-links)
- [App Links Testing Guide](https://developer.android.com/training/app-links/verify-android-applinks)


