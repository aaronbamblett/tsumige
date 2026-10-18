// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:path/path.dart' as p;

import 'host_platform.dart';

String xdgDataHome(Map<String, String> env) {
  final xdg = env['XDG_DATA_HOME'];
  if (xdg != null && xdg.isNotEmpty) return xdg;
  return p.join(env['HOME'] ?? '', '.local', 'share');
}

class DataDir {
  final String root;

  DataDir(this.root);

  static DataDir resolve(Map<String, String> env, {HostPlatform? platform}) {
    final override = env['TSUMIGE_DATA_DIR'];
    if (override != null && override.isNotEmpty) return DataDir(override);
    switch (platform?.os ?? HostOs.linux) {
      case HostOs.linux:
        return DataDir(p.join(xdgDataHome(env), 'tsumige'));
      case HostOs.macos:
        return DataDir(
            p.join(env['HOME'] ?? '', 'Library', 'Application Support', 'Tsumige'));
      case HostOs.windows:
        return DataDir(p.windows.join(env['APPDATA'] ?? '', 'Tsumige'));
    }
  }

  File get libraryJson => File(p.join(root, 'library.json'));

  Directory get backups => Directory(p.join(root, 'backups'));

  Directory get coversOriginal => Directory(p.join(root, 'covers', 'original'));

  Directory get coversBackground =>
      Directory(p.join(root, 'covers', 'background'));

  Directory get trash => Directory(p.join(root, 'trash'));

  Directory get logs => Directory(p.join(root, 'logs'));
}
