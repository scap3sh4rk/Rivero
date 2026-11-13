#!/usr/bin/env bash
set -e

echo "=== 1. Checking Dart formatting ==="
dart format --output=none --set-exit-if-changed .

echo "=== 2. Running Flutter analyze ==="
flutter analyze

echo "=== 3. Executing Flutter test suite ==="
flutter test

echo "=== ALL QUALITY CHECKS PASSED ==="
