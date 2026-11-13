#!/usr/bin/env bash
set -e

# Ensure Flutter and Dart are in PATH
export PATH="$HOME/flutter/bin:$PATH"

echo "=== 1. Checking Dart formatting ==="
dart format --output=none --set-exit-if-changed .

echo "=== 2. Running Flutter analyze ==="
flutter analyze

echo "=== 3. Executing Flutter test suite ==="
flutter test

echo "=== ALL QUALITY CHECKS PASSED ==="
