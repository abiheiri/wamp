#!/bin/bash
# Build Wamp for macOS ARM
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="Wamp"
CONFIG="Debug"
RUN=false
CLEAN=false

usage() {
  echo "Usage: ./build.sh [--release] [--run] [--clean]"
  echo "  --release   Build Release configuration (default: Debug)"
  echo "  --run       Launch the app after building"
  echo "  --clean     Clean before building"
  exit 0
}

for arg in "$@"; do
  case $arg in
    --release) CONFIG="Release" ;;
    --run)     RUN=true ;;
    --clean)   CLEAN=true ;;
    --help)    usage ;;
    *)         echo "Unknown option: $arg"; usage ;;
  esac
done

DERIVED="$PROJECT_DIR/.build/DerivedData"
APP="$DERIVED/Build/Products/$CONFIG/$PROJECT.app"

if $CLEAN; then
  echo "🧹 Cleaning…"
  xcodebuild -project "$PROJECT_DIR/$PROJECT.xcodeproj" \
    -scheme "$PROJECT" -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED" clean
fi

echo "🔨 Building $CONFIG…"
xcodebuild -project "$PROJECT_DIR/$PROJECT.xcodeproj" \
  -scheme "$PROJECT" \
  -configuration "$CONFIG" \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  build

echo "✅ Built: $APP"

if $RUN; then
  open "$APP"
fi
