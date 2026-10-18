// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../core/host_platform.dart';

/// Native desktop OS (not web, not mobile). `!kIsWeb` must be first — dart:io
/// `Platform` throws on web.
bool get isDesktopPlatform =>
    !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

/// The running OS and packaging, read once from the process environment.
/// Tests override it to pick a platform.
final hostPlatformProvider = Provider<HostPlatform>(
  (ref) => HostPlatform.fromEnvironment(
    Platform.environment,
    operatingSystem: Platform.operatingSystem,
  ),
);
