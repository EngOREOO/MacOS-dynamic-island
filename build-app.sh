#!/bin/sh
# Build the release binary and refresh Dynamic Island.app
set -e
cd "$(dirname "$0")"
swift build -c release
cp .build/release/DynamicIsland "Dynamic Island.app/Contents/MacOS/DynamicIsland"
echo "Built. Run with: open \"Dynamic Island.app\""
