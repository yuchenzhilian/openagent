# Flutter helper script — bypasses flutter.bat which may hang on engine
# version checks. Runs the dart snapshot directly instead.
#
# Also sets up build environment variables (JAVA_HOME, ANDROID_SDK_ROOT)
# to avoid Chinese-character path issues with the NDK.
#
# Usage:
#   .\tools\flutter.ps1 test
#   .\tools\flutter.ps1 analyze
#   .\tools\flutter.ps1 build apk --release
#
# If flutter.bat works for you, there's no need to use this script.

param([Parameter(ValueFromRemainingArguments=$true)] [string[]]$Args)

$projectRoot = Split-Path -Parent $PSScriptRoot

# --- Flutter SDK ---
$flutterRoot = "C:\flutter"
$snapshot = "$flutterRoot\bin\cache\flutter_tools.snapshot"
$packages = "$flutterRoot\packages\flutter_tools\.dart_tool\package_config.json"
$dart = "$flutterRoot\bin\cache\dart-sdk\bin\dart.exe"

if (-not (Test-Path $snapshot)) {
    Write-Error "Flutter tools snapshot not found at $snapshot"
    Write-Error "Run flutter.bat once to initialize the cache, then use this script."
    exit 1
}

# --- Build environment (avoids Chinese-character path issues) ---
# Local JDK (avoids system Java path issues)
$jdkPath = "$projectRoot\tools\jdk\jdk-17.0.20+8"
if (Test-Path $jdkPath) {
    $env:JAVA_HOME = $jdkPath
    $env:PATH = "$jdkPath\bin;$env:PATH"
}

# Android SDK via junction (avoids C:\Users\<中文名>\... path in NDK)
if (Test-Path "D:\AndroidSDK") {
    $env:ANDROID_SDK_ROOT = "D:\AndroidSDK"
    $env:ANDROID_HOME = "D:\AndroidSDK"
}

& $dart --packages="$packages" $snapshot @Args
exit $LASTEXITCODE
