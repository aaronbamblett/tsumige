// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import '../host_platform.dart';
import '../model.dart';

String launchModeName(LaunchMode mode) => switch (mode) {
      LaunchMode.proton => 'Proton',
      LaunchMode.wine => 'Wine',
      LaunchMode.native => 'Native',
      LaunchMode.steam => 'Steam',
    };

/// The modes this platform can run. Proton and Wine need Linux.
List<LaunchMode> launchModesFor(HostPlatform platform) => switch (platform.os) {
      HostOs.linux => LaunchMode.values,
      HostOs.macos || HostOs.windows => const [
          LaunchMode.native,
          LaunchMode.steam,
        ],
    };

LaunchMode defaultLaunchMode(HostPlatform platform) =>
    platform.isLinux ? LaunchMode.proton : LaunchMode.native;

/// The refusal shown for a saved mode this platform can't run, or null when
/// the mode is available.
String? launchModeUnavailableMessage(LaunchMode mode, HostPlatform platform) {
  if (launchModesFor(platform).contains(mode)) return null;
  return "${launchModeName(mode)} isn't available on ${platform.name}.";
}
