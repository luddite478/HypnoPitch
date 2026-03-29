import os
from fastapi import APIRouter

router = APIRouter()

@router.get("/.well-known/apple-app-site-association")
def apple_app_site_association():
    team_id = os.getenv("APPLE_TEAM_ID", "")
    bundle_id = os.getenv("APPLE_BUNDLE_ID", "")
    return {
        "applinks": {
            "apps": [],
            "details": [{
                "appID": f"{team_id}.{bundle_id}",
                "paths": ["/join/*"]
            }]
        }
    }

@router.get("/.well-known/assetlinks.json")
def assetlinks_json():
    fingerprint = os.getenv("ANDROID_SHA256_FINGERPRINT", "")
    return [{
        "relation": ["delegate_permission/common.handle_all_urls"],
        "target": {
            "namespace": "android_app",
            "package_name": "com.hypnopitch.app",
            "sha256_cert_fingerprints": [fingerprint]
        }
    }]
