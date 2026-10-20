// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumige/src/core/host_platform.dart';
import 'package:tsumige/src/core/launch/launch_command.dart';
import 'package:tsumige/src/features/library/domain/launch_actions.dart';
import 'package:tsumige/src/utils/platform/platform_runtime.dart';

void main() {
  test('umuRunPath outside a Flatpak searches PATH as before', () {
    const platform = HostPlatform(HostOs.linux);
    final container = ProviderContainer(
      overrides: [hostPlatformProvider.overrideWithValue(platform)],
    );
    addTearDown(container.dispose);
    expect(
      container.read(umuRunPathProvider),
      findOnPath('umu-run', Platform.environment, platform: platform),
    );
  });
}
