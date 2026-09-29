#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Build and test ATCCore in the pinned official swift image (Linux, Docker).
# The package is mounted read-only; the build dir lives in .build/linux.
set -euo pipefail

IMAGE="swift:6.3.3-noble@sha256:8de8ea332a61e961ead4ef41029c2552b18e1a70dd5942d25ecf7d8de2eec5b5"

root="$(cd "$(dirname "$0")/.." && pwd)"
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
