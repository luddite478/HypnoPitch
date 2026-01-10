# Invitation via Shareable Link

This document describes the implementation of the invite-via-link feature, which replaces the previous search-based user invitation system.

## Overview

The system allows a user within a thread to generate a unique, permanent link that they can share with others. When another user clicks this link on a device with the app installed, the app opens directly and prompts them to join the thread.

The invite link follows the format: `https://<your-domain>/join/<thread_id>`

## Client-Side Implementation (Flutter)

The majority of the work was done in the Flutter application.

1.  **UI Overhaul:** The `_InviteCollaboratorsModalBottomSheet` widget in `app/lib/screens/thread_screen.dart`, which previously contained a user search interface, was removed. It was replaced by a new, simpler stateless widget, `_InviteLinkModalBottomSheet`.

2.  **Link Generation:** The new modal constructs the shareable link at run-time. It retrieves the server's base URL from the `ApiHttpClient` service, which reads the `SERVER_HOST` and `HTTPS_API_PORT` from the `.env` file. This ensures the link always points to the correct environment (`stage` or `prod`).

3.  **Deep Link Handling:**
    *   The `uni_links` package was added to the project to listen for incoming deep links.
    *   Logic was added to `app/lib/main.dart` to handle app startup from a link. When a valid invite link is detected, the app parses the `thread_id`.
    *   The user is presented with a confirmation dialog. If they accept, the app calls the `threadsState.joinThread()` method, which uses the existing `/threads/{thread_id}/join` API endpoint to add the user to the thread. The user is then navigated directly to the joined thread.

## Server-Side Implementation

The simplified approach reuses existing server functionality, requiring minimal changes.

1.  **No Database Changes:** We opted to use the `thread_id` directly as the unique token for the invite, so no new database collections for invite codes were necessary.

2.  **Domain Verification:** To allow the mobile OS to open the app directly from a link, the server must prove ownership of the domain. This is handled by the Python FastAPI application itself, not the Nginx proxy.
    *   Two new endpoints were added in `server/app/http_api/deep_links.py`:
        *   `/.well-known/apple-app-site-association` (for iOS)
        *   `/.well-known/assetlinks.json` (for Android)
    *   These endpoints dynamically generate the required JSON content.

### Environment-Based Keys

The server does **not** contain any hardcoded developer keys. The content for the verification files is generated using environment variables that must be provided to the server container at runtime.

*   **For iOS:** The server uses the `APPLE_TEAM_ID` and `APPLE_BUNDLE_ID` environment variables to construct the `appID`.
*   **For Android:** The server uses the `ANDROID_SHA256_FINGERPRINT` environment variable.

This approach keeps all secrets and environment-specific configuration out of the source code.

## Native Project Configuration

The iOS and Android projects were configured to recognize and handle the deep link domains (`4tnd.link` and `devtest.4tnd.link`). The setup for this is detailed in the `docs/build.md` document.
