#!/bin/sh
# Copyright (c) 2026 Aaron Bamblett
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# Release build for Linux. Icon tree-shaking stays off: desktop ships the
# full Material Icons font, and a stale subset has broken icons twice.
set -eu
cd "$(dirname "$0")/.."
rm -rf .dart_tool/flutter_build build/linux
fvm flutter build linux --release --no-tree-shake-icons
