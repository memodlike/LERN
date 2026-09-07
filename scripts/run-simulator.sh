#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
xcodebuild -checkFirstLaunchStatus
SIMULATOR_ID="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); phones=[x for k,v in d["devices"].items() if "iOS" in k for x in v if "iPhone" in x["name"]]; print(next((x["udid"] for x in phones if x["state"]=="Booted"), phones[0]["udid"] if phones else ""))')"
if [ -z "$SIMULATOR_ID" ]; then
  echo 'Install an iOS Simulator runtime in Xcode Settings > Components.' >&2
  exit 1
fi
if [ "$#" -gt 0 ]; then
  APP_PATH="$1"
else
  xcodebuild -project "$ROOT_DIR/LERN.xcodeproj" -scheme LERN \
    -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
    -derivedDataPath "$ROOT_DIR/DerivedData" CODE_SIGNING_ALLOWED=NO build
  APP_PATH="$ROOT_DIR/DerivedData/Build/Products/Debug-iphonesimulator/LERN.app"
fi
if [ ! -d "$APP_PATH" ]; then echo "App bundle not found: $APP_PATH" >&2; exit 1; fi
BOOT_STATE="$(xcrun simctl list devices booted -j | python3 -c 'import json,sys; print(" ".join(x["udid"] for v in json.load(sys.stdin)["devices"].values() for x in v))')"
if [[ " $BOOT_STATE " != *" $SIMULATOR_ID "* ]]; then xcrun simctl boot "$SIMULATOR_ID"; fi
open -a Simulator
xcrun simctl bootstatus "$SIMULATOR_ID" -b
xcrun simctl install "$SIMULATOR_ID" "$APP_PATH"
xcrun simctl launch "$SIMULATOR_ID" app.lern.local
