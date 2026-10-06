#!/bin/zsh
# Builds PastelFocus (Release) and installs it to ~/Applications, then relaunches it.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --quiet
xcodebuild -project PastelFocus.xcodeproj -scheme PastelFocus -configuration Release \
  -derivedDataPath build -allowProvisioningUpdates build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | grep -v "DVTPlugIn|CoreSimulator" || true

APP="build/Build/Products/Release/PastelFocus.app"
[[ -d "$APP" ]] || { echo "Build failed"; exit 1; }

pkill -f "PastelFocus.app/Contents/MacOS/PastelFocus" 2>/dev/null || true
mkdir -p ~/Applications
rm -rf ~/Applications/PastelFocus.app
cp -R "$APP" ~/Applications/
open ~/Applications/PastelFocus.app
echo "Installed ~/Applications/PastelFocus.app"
