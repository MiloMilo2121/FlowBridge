#!/usr/bin/env bash
# One-command setup on a fresh Mac: checks the toolchain, fetches the
# git-ignored Whisper model, regenerates the Xcode project, runs the
# cross-platform checks. Safe to re-run.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "== FlowBridge bootstrap =="
echo "macOS $(sw_vers -productVersion) · $(uname -m) · free: $(df -h /System/Volumes/Data | tail -1 | awk '{print $4}')"

XCODE_OK=0
if xcode-select -p 2>/dev/null | grep -q "Xcode"; then
  echo "OK Xcode: $(xcodebuild -version | head -1)"
  echo "   SDK iOS: $(xcrun --sdk iphoneos --show-sdk-version 2>/dev/null || echo '?') (required: >= 26.0)"
  XCODE_OK=1
else
  echo "!! Xcode not active. Install Xcode 26 from the App Store, then:"
  echo "     sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  echo "     sudo xcodebuild -license accept && sudo xcodebuild -runFirstLaunch"
fi

if ! command -v xcodegen >/dev/null; then
  command -v brew >/dev/null || { echo "!! Homebrew missing: install from https://brew.sh first"; exit 1; }
  echo "-> Installing xcodegen..."
  brew install xcodegen
fi
echo "OK xcodegen $(xcodegen --version)"

if [ -f Resources/WhisperModels/WhisperSmall/tokenizer.json ]; then
  echo "OK Whisper model already staged"
else
  echo "-> Fetching Whisper Small (~600MB, git-ignored so per-machine)..."
  ./scripts/fetch-whisper-small.sh
fi

xcodegen generate
echo "OK project generated"

swift build
swift run FlowBridgeSharedCheck
echo "OK FlowBridgeShared green"

if [ "$XCODE_OK" = "1" ]; then
  cat <<'NEXT'

Ready. After signing into Xcode (Settings > Accounts > Apple ID >
Manage Certificates > + Apple Development), the compile loop is:

  xcodebuild -resolvePackageDependencies -project FlowBridge.xcodeproj -scheme FlowBridgeApp
  xcodebuild build -project FlowBridge.xcodeproj -scheme FlowBridgeApp \
    -destination 'generic/platform=iOS' -derivedDataPath .derived \
    CODE_SIGNING_ALLOWED=NO -quiet

Full plan: Docs/HANDOFF_NEXT_STEPS.md · Device sign-off: Docs/DEVICE_VALIDATION.md
NEXT
fi
