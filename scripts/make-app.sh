#!/bin/sh
# Builds a standalone "Claude Usage.app" with an ad-hoc signature.
set -eu

cd "$(dirname "$0")/.."

swift build -c release

APP="build/Claude Usage.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp .build/release/ClaudeUsage "$APP/Contents/MacOS/ClaudeUsage"
cp packaging/Info.plist "$APP/Contents/Info.plist"

codesign --force --sign - "$APP"

echo "Built $APP"
