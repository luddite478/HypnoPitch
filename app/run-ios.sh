#!/bin/bash

set -e

ENVIRONMENT="$1"
DEVICE_TYPE="$2"
IPHONE_MODEL="$3"
DEV_USER_ID_ARG=""
CLEAR_STORAGE=""

# Parse optional args (from position 4 onward):
# - first non-empty token becomes DEV_USER_ID_ARG
# - token "clear" enables CLEAR_STORAGE regardless of position
for arg in "${@:4}"; do
  if [[ -z "$arg" ]]; then
    continue
  fi
  if [[ "$arg" == "clear" ]]; then
    CLEAR_STORAGE="clear"
    continue
  fi
  if [[ -z "$DEV_USER_ID_ARG" ]]; then
    DEV_USER_ID_ARG="$arg"
  fi
done

# Validate arguments
if [[ -z "$ENVIRONMENT" ]]; then
  echo "Usage: $0 <environment> <device_type> [iphone_model] [dev_user_id] [clear]"
  echo "  environment: stage or prod"
  echo "  device_type: simulator or device"
  echo "  iphone_model: e.g., 'iPhone 15' (optional, defaults to 'iPhone 15' for simulator)"
  echo "  dev_user_id: Developer user ID (optional)"
  echo "  clear: 'clear' to clear storage (optional)"
  exit 1
fi

if [[ "$ENVIRONMENT" != "stage" && "$ENVIRONMENT" != "prod" ]]; then
  echo "❌ Error: Environment must be 'stage' or 'prod', got: $ENVIRONMENT"
  exit 1
fi

if [[ -z "$DEVICE_TYPE" ]]; then
  echo "❌ Error: Device type must be 'simulator' or 'device'"
  exit 1
fi

if [[ "$DEVICE_TYPE" != "simulator" && "$DEVICE_TYPE" != "device" ]]; then
  echo "❌ Error: Device type must be 'simulator' or 'device', got: $DEVICE_TYPE"
  exit 1
fi

# Ensure system toolchain is used (avoid ccache)
export CC="/usr/bin/clang"
export CXX="/usr/bin/clang++"

# Set default iPhone model if not provided for simulator
if [[ "$DEVICE_TYPE" == "simulator" && -z "$IPHONE_MODEL" ]]; then
  IPHONE_MODEL="iPhone 15"
  echo "No iPhone model specified, using default: $IPHONE_MODEL"
fi

# Copy appropriate environment file
if [[ "$ENVIRONMENT" == "stage" ]]; then
  cp .stage.env .env
  echo "Using stage environment (.stage.env)"
  cp ios/Runner/Runner.entitlements.stage ios/Runner/Runner.entitlements
  echo "Using stage entitlements (devtest.4tnd.link)"
elif [[ "$ENVIRONMENT" == "prod" ]]; then
  cp .prod.env .env
  echo "Using production environment (.prod.env)"
  cp ios/Runner/Runner.entitlements.prod ios/Runner/Runner.entitlements
  echo "Using production entitlements (4tnd.link)"
fi

# Step 1: Find all directories (including empty ones) in samples folder
ASSET_DIRS=$(find samples/ -type d | sort)

# Step 2: Create temporary file with directory list
TEMP_ASSETS=$(mktemp)
echo "$ASSET_DIRS" > "$TEMP_ASSETS"

# Step 3: Use yq to update pubspec.yaml with proper array format
yq eval '.flutter.assets = []' -i pubspec.yaml

# Step 4: Add each directory individually with trailing slash
while IFS= read -r asset_dir; do
  if [[ -n "$asset_dir" && "$asset_dir" != "samples/" ]]; then
    # Normalize path by removing double slashes and add trailing slash
    normalized_path=$(echo "$asset_dir" | sed 's|//|/|g')
    yq eval ".flutter.assets += [\"$normalized_path/\"]" -i pubspec.yaml
  fi
done < "$TEMP_ASSETS"

# Step 5: Add .env file to assets if it exists
yq eval '.flutter.assets += [".env"]' -i pubspec.yaml

yq eval '.flutter.assets += ["icons/"]' -i pubspec.yaml
# Step 6: Add samples_manifest.json to assets
yq eval '.flutter.assets += ["samples_manifest.json"]' -i pubspec.yaml

# Clean up temp file
rm "$TEMP_ASSETS"

# Select appropriate SunVox library based on target
echo "Selecting appropriate SunVox library..."
cd native/sunvox_lib/sunvox_lib/ios
./select_library.sh "$DEVICE_TYPE"
cd ../../../..

# Prepare Flutter command
FLUTTER_ARGS=()
if [[ -n "$DEV_USER_ID_ARG" ]]; then
  FLUTTER_ARGS+=(--dart-define="DEV_USER_ID=$DEV_USER_ID_ARG")
  echo "🔧 Running with developer user ID: $DEV_USER_ID_ARG"
fi

if [[ "$CLEAR_STORAGE" == "clear" ]]; then
  FLUTTER_ARGS+=(--dart-define=CLEAR_STORAGE=true)
  echo "🗑️ Clearing storage on next app launch."
fi

# Step 6:   Generate launcher icons
dart run flutter_launcher_icons 

# Step 7: Run based on target
if [[ "$DEVICE_TYPE" == "simulator" ]]; then
  echo "Running on iPhone Simulator ($IPHONE_MODEL)..."
  # Properly quote the device name to handle spaces
  flutter run "${FLUTTER_ARGS[@]}" -d "$IPHONE_MODEL" --debug
else
  echo "Building for physical device..."
  flutter build ios "${FLUTTER_ARGS[@]}" --release

  echo "Detecting first connected physical iPhone..."
  DEVICE_ID="00008030-001564DA14F9802E"
  # Try to auto-detect device if not hardcoded
  # DEVICE_ID=$(ios-deploy --detect 2>/dev/null | grep -oE '[0-9A-Fa-f-]{25,}' | head -n 1)

  if [[ -z "$DEVICE_ID" ]]; then
    echo "❌ No physical device detected. Please connect your iPhone via USB."
    exit 1
  fi

  echo "Deploying to device: $DEVICE_ID"
  
  # Check if device is paired/trusted
  if ! ios-deploy --detect 2>/dev/null | grep -q "$DEVICE_ID"; then
    echo ""
    echo "⚠️  Device pairing issue detected!"
    echo ""
    echo "To fix device pairing:"
    echo "  1. Unlock your iPhone"
    echo "  2. Connect iPhone to Mac via USB"
    echo "  3. On iPhone: Tap 'Trust This Computer' when prompted"
    echo "  4. On Mac: Open Xcode → Window → Devices and Simulators"
    echo "  5. Verify your device appears and shows 'Connected'"
    echo "  6. If device shows 'Unpaired', click 'Use for Development'"
    echo ""
    echo "Alternatively, deploy via Xcode:"
    echo "  - Open ios/Runner.xcworkspace in Xcode"
    echo "  - Select your device from the device menu"
    echo "  - Click Run (▶️)"
    echo ""
    exit 1
  fi
  
  # Attempt deployment
  if ! ios-deploy --bundle build/ios/iphoneos/Runner.app --id "$DEVICE_ID"; then
    echo ""
    echo "❌ Deployment failed!"
    echo ""
    echo "Common issues:"
    echo "  1. Device not trusted: Unlock iPhone and tap 'Trust This Computer'"
    echo "  2. Device not paired: Open Xcode → Window → Devices and Simulators"
    echo "  3. Developer mode disabled: Settings → Privacy & Security → Developer Mode (iOS 16+)"
    echo "  4. Code signing: Ensure your Apple ID is added in Xcode → Settings → Accounts"
    echo ""
    echo "Try deploying via Xcode instead:"
    echo "  open ios/Runner.xcworkspace"
    echo ""
    exit 1
  fi
fi