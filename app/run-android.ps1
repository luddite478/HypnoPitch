param(
    [string]$deviceType = "simulator"  # Default to simulator if not provided
)

# Step 0: Set JAVA_HOME and update PATH
$env:JAVA_HOME = "C:\Program Files\Java\jdk-17"
$env:Path = "$env:JAVA_HOME\bin;$env:Path"

# Set adb device selector based on argument
$adbDeviceSelector = ""
if ($deviceType -eq "physical") {
    $adbDeviceSelector = "-s ec23c4f7"
}

Import-Module powershell-yaml

# Custom function for relative path calculation (PowerShell 5 compatible)
function Get-RelativePath {
    param (
        [Parameter(Mandatory)]
        [string]$FromPath,
        [Parameter(Mandatory)]
        [string]$ToPath
    )

    # Ensure paths end with backslash to treat as directories
    if (-not $FromPath.EndsWith('\')) { $FromPath += '\' }
    if (-not $ToPath.EndsWith('\')) { $ToPath += '\' }

    $fromUri = New-Object System.Uri($FromPath)
    $toUri = New-Object System.Uri($ToPath)

    if ($fromUri.Scheme -ne $toUri.Scheme) {
        # If schemes differ, cannot get relative path; return absolute
        return $ToPath
    }

    $relativeUri = $fromUri.MakeRelativeUri($toUri)
    $relativePath = [System.Uri]::UnescapeDataString($relativeUri.ToString())

    # Convert URI format path to Windows path format
    if ($toUri.Scheme -eq 'file') {
        $relativePath = $relativePath -replace '/', '\'
    }

    # Remove trailing backslash added earlier (optional)
    return $relativePath.TrimEnd('\')
}

# Load pubspec.yaml
$pubspecPath = "pubspec.yaml"
$pubspec = ConvertFrom-Yaml (Get-Content $pubspecPath -Raw)

# Reset flutter.assets
$pubspec.flutter.assets = @()

# Get all directories under samples (recursively)
$assetDirs = Get-ChildItem -Path "samples" -Recurse -Directory | Sort-Object FullName

foreach ($dir in $assetDirs) {
    $relativePath = Get-RelativePath -FromPath (Get-Location).Path -ToPath $dir.FullName
    $normalizedPath = ($relativePath -replace "\\", "/").TrimEnd('/') + "/"
    if ($normalizedPath -ne "samples/") {
        $pubspec.flutter.assets += $normalizedPath
    }
}

# Add .env if it exists
if (Test-Path ".env") {
    $pubspec.flutter.assets += ".env"
}

# Add icons if it exists
if (Test-Path "icons/") {
    $pubspec.flutter.assets += "icons/"
}
# Add samples_manifest.json
$pubspec.flutter.assets += "samples_manifest.json"

# Save back to pubspec.yaml
$pubspec | ConvertTo-Yaml | Set-Content $pubspecPath -Encoding UTF8

# Step 3: Change to android folder and build with Gradle
Set-Location android

Write-Output "Running gradlew clean..."
& .\gradlew clean

Write-Output "Building debug APK..."
& .\gradlew assembleDebug

# Step 4: Go back to root and install the APK with ADB
Set-Location ..

# adb uninstall com.hypnopitch.app

$apkPath = "android\app\build\outputs\apk\debug\app-debug.apk"
# Set adb argument arrays based on device type
$adbArgs = @()
if ($deviceType -eq "physical") {
    $adbArgs += "-s"
    $adbArgs += "ec23c4f7"
}
if ($deviceType -eq "simulator") {
    $emulatorId = (& adb devices | Select-String "^emulator-[0-9]+").ToString().Split("`t")[0]
    if ($emulatorId) {
        $adbArgs += "-s"
        $adbArgs += $emulatorId
    }
}
$adbArgsInstall = $adbArgs + @("install", "-r", $apkPath)
$adbArgsLogcat = $adbArgs + @("logcat", "-s", "flutter")

if (Test-Path $apkPath) {
    Write-Output "Installing APK via ADB..."
    & adb @adbArgsInstall
} else {
    Write-Error "APK not found at: $apkPath"
}

& adb @adbArgsLogcat