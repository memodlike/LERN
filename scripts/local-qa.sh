#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
xcodebuild -version
LERN_LARGE_TEST=1 swift test
xcodebuild -project LERN.xcodeproj -scheme LERN -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
DEVICE=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for k,v in d["devices"].items() if "iOS" in k for x in v if "iPhone" in x["name"]))')
xcodebuild -project LERN.xcodeproj -scheme LERN -destination "platform=iOS Simulator,id=$DEVICE" -derivedDataPath DerivedData -resultBundlePath "qa-output/$(date +%Y%m%d-%H%M%S).xcresult" CODE_SIGNING_ALLOWED=NO test
