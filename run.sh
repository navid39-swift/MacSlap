#!/bin/bash
# MacSlap launcher: checks your Mac, builds the app if needed, then starts it.
# Usage:  ./run.sh            (any extra options are passed through, e.g. ./run.sh -t 0.25)
set -e
cd "$(dirname "$0")"

# 1. Apple Silicon only
if [ "$(uname -m)" != "arm64" ]; then
  echo "❌ MacSlap needs an Apple Silicon MacBook (M2 or newer). This Mac is $(uname -m)."
  exit 1
fi

# 2. Swift compiler (comes with Xcode or the Command Line Tools)
if ! command -v swift >/dev/null 2>&1; then
  echo "❌ Swift isn't installed. Run this, accept the popup, then try ./run.sh again:"
  echo "   xcode-select --install"
  exit 1
fi

# 3. Build (only when the code changed)
BIN=".build/release/MacSlap"
if [ ! -f "$BIN" ] || [ -n "$(find Sources Package.swift -newer "$BIN" 2>/dev/null)" ]; then
  echo "🔨 Building MacSlap (first time takes ~30 s)..."
  swift build -c release
fi

# 4. Run (reading the motion sensor needs admin rights)
echo "🔑 macOS will ask for your Mac password (nothing shows while you type)."
sudo "$BIN" -s sounds "$@"
