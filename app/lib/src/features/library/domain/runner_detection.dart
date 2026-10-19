// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/launch/detect.dart';
import '../../../utils/platform/platform_runtime.dart';

part 'runner_detection.g.dart';

/// Detected Wine runners. Rescan with `ref.invalidate(wineRunnersProvider)`.
@Riverpod(keepAlive: true)
Future<List<WineRunner>> wineRunners(Ref ref) async => detectWineRunners(
      Platform.environment,
      platform: ref.watch(hostPlatformProvider),
    );

/// Detected Proton runners. Rescan with `ref.invalidate(protonRunnersProvider)`.
@Riverpod(keepAlive: true)
Future<List<ProtonRunner>> protonRunners(Ref ref) async => detectProtonRunners(
      Platform.environment,
      platform: ref.watch(hostPlatformProvider),
    );

/// Detected Steam prefixes. Rescan with `ref.invalidate(steamPrefixesProvider)`.
@Riverpod(keepAlive: true)
Future<List<SteamPrefix>> steamPrefixes(Ref ref) async => detectSteamPrefixes(
      Platform.environment,
      platform: ref.watch(hostPlatformProvider),
    );

/// Game language choices shared by the launch tab and the settings defaults:
/// stored value, option label, and a widget-key suffix.
const List<(String, String, String)> localeChoices = [
  ('', 'System', 'system'),
  ('ja_JP.UTF-8', 'Japanese', 'japanese'),
  ('zh_CN.UTF-8', 'Chinese', 'chinese'),
  ('ko_KR.UTF-8', 'Korean', 'korean'),
  ('en_US.UTF-8', 'English', 'english'),
];

/// Locale presets: the non-empty stored values of [localeChoices].
final List<String> localePresets = [
  for (final (value, _, _) in localeChoices)
    if (value.isNotEmpty) value,
];

/// The settings label for a stored locale, or the raw value when unknown.
String localeLabel(String locale) {
  for (final (value, label, _) in localeChoices) {
    if (value == locale) return label;
  }
  return locale;
}

/// Toast shown when a picked path came through the Flatpak portal.
const String portalPathMessage =
    "Can't use a Flatpak portal path. Choose it from its real location.";

bool isPortalPath(String path) => path.startsWith('/run/user/');
