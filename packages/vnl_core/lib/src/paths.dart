// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:path/path.dart' as p;

class DataDir {
  final String root;

  DataDir(this.root);

  static DataDir resolve(Map<String, String> env) {
    final override = env['VNL_DATA_DIR'];
    if (override != null && override.isNotEmpty) return DataDir(override);
    final xdg = env['XDG_DATA_HOME'];
    if (xdg != null && xdg.isNotEmpty) return DataDir(p.join(xdg, 'vnl'));
    return DataDir(p.join(env['HOME'] ?? '', '.local', 'share', 'vnl'));
  }

  File get libraryJson => File(p.join(root, 'library.json'));

  File get settingsJson => File(p.join(root, 'settings.json'));

  Directory get backups => Directory(p.join(root, 'backups'));

  Directory get coversOriginal => Directory(p.join(root, 'covers', 'original'));

  Directory get trash => Directory(p.join(root, 'trash'));

  Directory get logs => Directory(p.join(root, 'logs'));

  String thumbDir(int width) => p.join(root, 'covers', 'thumb', 'v1', '$width');
}
