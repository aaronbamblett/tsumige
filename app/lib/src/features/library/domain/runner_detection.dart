// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/launch/detect.dart';

part 'runner_detection.g.dart';

/// Detected Wine runners. Rescan with `ref.invalidate(wineRunnersProvider)`.
@Riverpod(keepAlive: true)
Future<List<WineRunner>> wineRunners(Ref ref) async =>
    detectWineRunners(Platform.environment);

/// Detected Proton runners. Rescan with `ref.invalidate(protonRunnersProvider)`.
@Riverpod(keepAlive: true)
Future<List<ProtonRunner>> protonRunners(Ref ref) async =>
    detectProtonRunners(Platform.environment);

/// Detected Steam prefixes. Rescan with `ref.invalidate(steamPrefixesProvider)`.
@Riverpod(keepAlive: true)
Future<List<SteamPrefix>> steamPrefixes(Ref ref) async =>
    detectSteamPrefixes(Platform.environment);

/// Locale presets shared by the launch tab and the settings defaults.
const List<String> localePresets = [
  'ja_JP.UTF-8',
  'zh_CN.UTF-8',
  'ko_KR.UTF-8',
  'en_US.UTF-8',
];

/// Toast shown when a picked path came through the Flatpak portal.
const String portalPathMessage =
    'That path came through the Flatpak portal. '
    'Pick it from its real location.';

bool isPortalPath(String path) => path.startsWith('/run/user/');
