// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumige/src/core/host_platform.dart';

void main() {
  test('the operating system name maps to its HostOs', () {
    expect(
      HostPlatform.fromEnvironment({}, operatingSystem: 'linux').os,
      HostOs.linux,
    );
    expect(
      HostPlatform.fromEnvironment({}, operatingSystem: 'macos').os,
      HostOs.macos,
    );
    expect(
      HostPlatform.fromEnvironment({}, operatingSystem: 'windows').os,
      HostOs.windows,
    );
  });

  test('an unrecognised OS is treated as Linux', () {
    expect(HostPlatform.fromEnvironment({}).isLinux, isTrue);
  });

  test('APPIMAGE and FLATPAK_ID set the packaging flags', () {
    final appImage = HostPlatform.fromEnvironment({
      'APPIMAGE': '/x/Tsumige.AppImage',
    }, operatingSystem: 'linux');
    expect(appImage.inAppImage, isTrue);
    expect(appImage.inFlatpak, isFalse);

    final flatpak = HostPlatform.fromEnvironment({
      'FLATPAK_ID': 'io.github.tsumige',
    }, operatingSystem: 'linux');
    expect(flatpak.inFlatpak, isTrue);
    expect(flatpak.inAppImage, isFalse);
  });

  test('names are the OS names people read', () {
    expect(const HostPlatform(HostOs.linux).name, 'Linux');
    expect(const HostPlatform(HostOs.macos).name, 'macOS');
    expect(const HostPlatform(HostOs.windows).name, 'Windows');
  });
}
