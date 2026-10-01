#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Build and test ATCCore in the pinned official swift image (Linux, Docker).
# The package is mounted read-only; the build dir lives in .build/linux.
set -euo pipefail

IMAGE="swift:6.3.3-noble@sha256:8de8ea332a61e961ead4ef41029c2552b18e1a70dd5942d25ecf7d8de2eec5b5"

root="$(cd "$(dirname "$0")/.." && pwd)"

# The app target is never compiled on Linux, so this is the only early warning.
# SwiftUI macros need Xcode's plugin and fail with Command Line Tools only.
# Keep the list here, one ERE alternative per macro.
FORBIDDEN_MACROS='@State\b|#Preview\b'
if hits=$(grep -rnE "$FORBIDDEN_MACROS" "$root/Sources/Annunciator" --include='*.swift'); then
  echo "test-linux: Sources/Annunciator uses a SwiftUI macro that needs Xcode's plugin (Command Line Tools cannot build it):" >&2
  echo "$hits" >&2
  echo "Use ObservableObject + @Published + @ObservedObject instead (see README 'Build and run')." >&2
  exit 1
fi
# Sign-in code (ATC-246) must not log: a token could ride along in any string. Errors go through Redact.
if hits=$(grep -rnE 'print\(|NSLog|os_log|Logger\(|debugPrint|dump\(' "$root/Sources/Annunciator/Work" --include='*.swift'); then
  echo "test-linux: Sources/Annunciator/Work logs; sign-in code must not print or log (design 11.7):" >&2
  echo "$hits" >&2
  exit 1
fi
mkdir -p "$root/.build/linux"

start=$(date +%s)
docker run --rm \
  --user "$(id -u):$(id -g)" \
  -e HOME=/build/home \
  -v "$root:/pkg:ro" \
  -v "$root/.build/linux:/build" \
  -w /pkg \
  "$IMAGE" \
  bash -c 'mkdir -p /build/home && swift build --scratch-path /build/out && swift test --scratch-path /build/out'
echo "test-linux: ok in $(($(date +%s) - start)) s ($IMAGE)"
