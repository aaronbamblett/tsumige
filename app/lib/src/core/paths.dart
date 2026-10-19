// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:path/path.dart' as p;

import 'host_platform.dart';

/// The canonical form of [path] with symlinks resolved, so the same file
/// picked through different links (such as `/mnt` versus `/var/mnt` on
/// Atomic Fedora and Bazzite) compares equal. Pure and synchronous. When
/// [path] does not exist, the nearest existing parent is resolved and the
/// rest joined back on, then normalised.
String realPath(String path) {
  if (path.isEmpty) return path;
  try {
    return File(path).resolveSymbolicLinksSync();
  } on FileSystemException {
    final rest = <String>[p.basename(path)];
    var parent = p.dirname(path);
    while (parent != p.dirname(parent)) {
      try {
        final resolved = Directory(parent).resolveSymbolicLinksSync();
        return p.normalize(p.joinAll([resolved, ...rest.reversed]));
      } on FileSystemException {
        rest.add(p.basename(parent));
        parent = p.dirname(parent);
      }
    }
    try {
      final resolved = Directory(parent).resolveSymbolicLinksSync();
      return p.normalize(p.joinAll([resolved, ...rest.reversed]));
    } on FileSystemException {
      return p.normalize(path);
    }
  }
}

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
        return DataDir(p.join(
          env['HOME'] ?? '',
          'Library',
          'Application Support',
          'Tsumige',
        ));
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
