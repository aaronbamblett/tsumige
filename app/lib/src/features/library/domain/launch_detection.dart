// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/host_platform.dart';
import '../../../core/launch/launch_modes.dart';
import '../../../core/model.dart';
import 'folder_import.dart';

/// The launch mode for the game at [path], a game file or a game folder,
/// with the Steam app id when the game sits in a Steam library.
Future<({LaunchMode mode, int? steamAppId})> detectLaunchMode(
  String path,
  HostPlatform platform,
) async {
  final steamAppId = await _steamAppId(path);
  if (steamAppId != null) {
    return (mode: LaunchMode.steam, steamAppId: steamAppId);
  }
  final ext = p.extension(path).toLowerCase();
  if (ext == '.exe') {
    if (platform.isLinux) return (mode: LaunchMode.proton, steamAppId: null);
    if (platform.isWindows) return (mode: LaunchMode.native, steamAppId: null);
  }
  final native = switch (ext) {
    '.app' || '.command' => platform.isMacOS,
    '.appimage' => platform.isLinux,
    '.sh' => !platform.isWindows,
    _ => await isNativeBinary(path, platform),
  };
  return (
    mode: native ? LaunchMode.native : defaultLaunchMode(platform),
    steamAppId: null,
  );
}

/// The app id of the Steam manifest whose installdir is the folder directly
/// under `steamapps/common` that [path] is in, or null.
Future<int?> _steamAppId(String path) async {
  final common = _steamCommon(path);
  if (common == null) return null;
  final (:installDir, :steamapps) = common;
  final List<FileSystemEntity> entries;
  try {
    entries = await Directory(steamapps).list().toList();
  } on FileSystemException {
    return null;
  }
  final manifest = RegExp(r'^appmanifest_\d+\.acf$');
  for (final entry in entries) {
    if (entry is! File || !manifest.hasMatch(p.basename(entry.path))) continue;
    final String text;
    try {
      text = await entry.readAsString();
    } on FileSystemException {
      continue;
    }
    final dir = RegExp(r'"installdir"\s+"([^"]*)"').firstMatch(text)?.group(1);
    if (dir != installDir) continue;
    final id = RegExp(r'"appid"\s+"(\d+)"').firstMatch(text)?.group(1);
    if (id != null) return int.parse(id);
  }
  return null;
}

({String installDir, String steamapps})? _steamCommon(String path) {
  var current = p.normalize(path);
  while (true) {
    final parent = p.dirname(current);
    if (p.basename(parent) == 'common' &&
        p.basename(p.dirname(parent)) == 'steamapps') {
      return (installDir: p.basename(current), steamapps: p.dirname(parent));
    }
    if (parent == current) return null;
    current = parent;
  }
}
