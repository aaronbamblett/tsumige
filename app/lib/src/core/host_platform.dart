// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

enum HostOs { linux, macos, windows }

/// The desktop OS and the packaging the app runs in. Built once from
/// `Platform` and the environment, and passed to the code that varies by
/// platform, so tests can choose a platform without touching `dart:io`.
class HostPlatform {
  const HostPlatform(
    this.os, {
    this.inAppImage = false,
    this.inFlatpak = false,
  });

  factory HostPlatform.fromEnvironment(
    Map<String, String> env, {
    String operatingSystem = 'linux',
  }) {
    final os = switch (operatingSystem) {
      'macos' => HostOs.macos,
      'windows' => HostOs.windows,
      _ => HostOs.linux,
    };
    return HostPlatform(
      os,
      inAppImage: env.containsKey('APPIMAGE'),
      inFlatpak: env.containsKey('FLATPAK_ID'),
    );
  }

  final HostOs os;
  final bool inAppImage;
  final bool inFlatpak;

  bool get isLinux => os == HostOs.linux;
  bool get isMacOS => os == HostOs.macos;
  bool get isWindows => os == HostOs.windows;

  String get name => switch (os) {
        HostOs.linux => 'Linux',
        HostOs.macos => 'macOS',
        HostOs.windows => 'Windows',
      };
}
