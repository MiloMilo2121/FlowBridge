#!/usr/bin/env bash
#
# FlowBridge pre-Xcode preflight.
#
# Run this on a Mac BEFORE opening Xcode. It does every check that can be
# automated so the first Xcode session has no surprises:
#   1. Verifies the toolchain (xcodegen, xcodebuild).
#   2. Builds + tests the shared framework (fast, cross-platform).
#   3. Regenerates the Xcode project from project.yml.
#   4. Compiles ALL iOS targets (app + keyboard + share + widgets) for the
#      simulator — the real validation of the iOS-only code.
#   5. Runs the iOS unit-test bundle on an available simulator.
#
# It never touches signing or a device: everything targets the simulator.
# Exit code is non-zero if any step fails.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }

STATUS=0
step() { bold ""; bold "▶ $1"; }

# 1 — toolchain -------------------------------------------------------------
step "1/5  Toolchain"
if command -v xcodebuild >/dev/null 2>&1 && xcodebuild -version >/tmp/fb_xcode_version.log 2>&1; then
  XCODE_MAJOR=$(awk 'NR == 1 { split($2, parts, "."); print parts[1] }' /tmp/fb_xcode_version.log)
  if [[ "$XCODE_MAJOR" =~ ^[0-9]+$ ]] && [ "$XCODE_MAJOR" -ge 26 ]; then
    pass "$(head -1 /tmp/fb_xcode_version.log) ($(xcode-select -p))"
  else
    fail "Xcode 26 or newer is required (found: $(head -1 /tmp/fb_xcode_version.log))."; STATUS=1
  fi
else
  fail "Full Xcode is not active — install it, then select /Applications/Xcode.app/Contents/Developer."; STATUS=1
fi
if command -v xcodegen >/dev/null 2>&1; then
  pass "xcodegen: $(xcodegen --version 2>&1 | head -1)"
else
  fail "xcodegen not found — run: brew install xcodegen"; STATUS=1
fi
FREE_KIB=$(df -Pk . | awk 'NR == 2 { print $4 }')
if [ "${FREE_KIB:-0}" -ge 10485760 ]; then
  pass "At least 10 GiB free for simulator build and tests"
else
  fail "Less than 10 GiB free — make space before building; allow more for a signed archive."; STATUS=1
fi
if [ "$STATUS" -ne 0 ]; then
  bold ""; fail "Fix the toolchain before continuing."; exit 1
fi

# 2 — shared framework build + tests (SwiftPM, no simulator needed) --------
step "2/5  Shared framework (swift build + swift test)"
if swift build >/tmp/fb_build.log 2>&1; then
  pass "swift build"
else
  fail "swift build failed:"; tail -20 /tmp/fb_build.log; STATUS=1
fi
if swift test >/tmp/fb_test.log 2>&1; then
  pass "swift test — $(grep -oE 'Executed [0-9]+ tests' /tmp/fb_test.log | tail -1)"
else
  fail "swift test failed:"; tail -25 /tmp/fb_test.log; STATUS=1
fi
if swift run FlowBridgeSharedCheck >/tmp/fb_shared_check.log 2>&1; then
  pass "FlowBridgeSharedCheck"
else
  fail "FlowBridgeSharedCheck failed:"; tail -20 /tmp/fb_shared_check.log; STATUS=1
fi

# 3 — regenerate the Xcode project -----------------------------------------
step "3/5  Regenerate Xcode project (xcodegen)"
if xcodegen generate >/tmp/fb_xcodegen.log 2>&1; then
  pass "xcodegen generate — widgets/app-intents targets materialized"
else
  fail "xcodegen generate failed:"; tail -20 /tmp/fb_xcodegen.log; STATUS=1
fi

# Whisper model is required at RUNTIME (app fails closed) but not to compile.
if [ -d "Resources/WhisperModels/WhisperSmall" ]; then
  pass "Whisper model present"
else
  warn "Whisper model missing — run ./scripts/fetch-whisper-small.sh before running on device (compiles fine without it)."
fi

# 4 — compile all iOS targets for the simulator ----------------------------
step "4/5  Compile all iOS targets (xcodebuild, simulator)"
DEST="generic/platform=iOS Simulator"
if xcodebuild \
    -project FlowBridge.xcodeproj \
    -scheme FlowBridgeApp \
    -destination "$DEST" \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO \
    build >/tmp/fb_xcodebuild.log 2>&1; then
  pass "xcodebuild build (app + keyboard + share + widgets)"
else
  fail "xcodebuild build failed — full log at /tmp/fb_xcodebuild.log:"
  grep -E "error:|warning:" /tmp/fb_xcodebuild.log | head -30
  STATUS=1
fi

# 5 — iOS unit-test bundle on an available simulator -----------------------
step "5/5  iOS unit tests on a simulator"
SIM=$(xcrun simctl list devices available 2>/dev/null | grep -m1 -oE "iPhone [0-9]+[^(]*" | sed 's/ *$//')
if [ -n "${SIM:-}" ]; then
  if xcodebuild \
      -project FlowBridge.xcodeproj \
      -scheme FlowBridgeApp \
      -destination "platform=iOS Simulator,name=$SIM" \
      CODE_SIGNING_ALLOWED=NO \
      test >/tmp/fb_xctest.log 2>&1; then
    pass "xcodebuild test on $SIM — $(grep -oE 'Executed [0-9]+ tests' /tmp/fb_xctest.log | tail -1)"
  else
    fail "iOS test run failed (see /tmp/fb_xctest.log)."; STATUS=1
  fi
else
  fail "No iPhone simulator runtime available; install one in Xcode before beta validation."; STATUS=1
fi

# Summary -------------------------------------------------------------------
bold ""
if [ "$STATUS" -eq 0 ]; then
  bold "✅ Preflight passed. Set your team, App Group, and iCloud container, then run on the iPhone 17 Air."
else
  bold "❌ Preflight found problems above. Fix them, then re-run ./scripts/preflight.sh"
fi
exit "$STATUS"
