// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/pref_keys.dart';
import 'paths.dart';

const _legacyDataName = 'vnl';
const _legacyAppId = 'dev.vnl.vnl';
const _appId = 'app.tsumige.Tsumige';
const _legacyPrefixRelative = 'Games/vnl/prefix';

typedef RenameDir = Future<void> Function(Directory from, String to);

/// Moves the pre-rename data folder to the new location when the new folder
/// is missing. Nothing is deleted: a cross-device move is copied and the old
/// folder stays in place.
Future<void> migrateLegacyDataDir(
  Map<String, String> env, {
  RenameDir? rename,
}) async {
  final override = env['TSUMIGE_DATA_DIR'];
  if (override != null && override.isNotEmpty) return;
  final target = DataDir.resolve(env);
  final legacy = Directory(p.join(xdgDataHome(env), _legacyDataName));
  if (await Directory(target.root).exists() || !await legacy.exists()) return;
  await Directory(xdgDataHome(env)).create(recursive: true);
  var how = 'moved';
  try {
    await (rename ?? _renameDir)(legacy, target.root);
  } on FileSystemException {
    final staging = Directory('${target.root}.migrating');
    await _copyTree(legacy, staging);
    await staging.rename(target.root);
    how = 'copied';
  }
  await _appendLog(
    target,
    'migrated data folder ($how) from ${legacy.path} to ${target.root}',
  );
}

/// Copies the old Linux preferences file into the new app-id folder before
/// shared_preferences reads it. The new folder is created either way so
/// path_provider picks it over the legacy executable-name folder.
Future<void> migrateLegacyPrefsFile(Map<String, String> env) async {
  final target = File(
    p.join(xdgDataHome(env), _appId, 'shared_preferences.json'),
  );
  await target.parent.create(recursive: true);
  if (await target.exists()) return;
  final legacy = File(
    p.join(xdgDataHome(env), _legacyAppId, 'shared_preferences.json'),
  );
  if (!await legacy.exists()) return;
  final staging = File('${target.path}.migrating');
  await legacy.copy(staging.path);
  await staging.rename(target.path);
}

/// Keeps an existing install on its old prefix: a new default must not point
/// users at an empty prefix while their games sit in the old one.
Future<void> migrateLaunchPrefix(
  SharedPreferences prefs,
  Map<String, String> env,
) async {
  final key = PrefKey.launchPrefix.key;
  if (prefs.containsKey(key)) return;
  final legacy = Directory(p.join(env['HOME'] ?? '', _legacyPrefixRelative));
  if (!await legacy.exists()) return;
  await prefs.setString(key, '~/$_legacyPrefixRelative');
}

Future<void> _renameDir(Directory from, String to) async {
  await from.rename(to);
}

Future<void> _copyTree(Directory from, Directory to) async {
  await to.create(recursive: true);
  await for (final entry in from.list(followLinks: false)) {
    final name = p.basename(entry.path);
    if (entry is Directory) {
      await _copyTree(entry, Directory(p.join(to.path, name)));
    } else if (entry is File) {
      await entry.copy(p.join(to.path, name));
    }
  }
}

Future<void> _appendLog(DataDir dir, String line) async {
  await dir.logs.create(recursive: true);
  await File(p.join(dir.logs.path, 'migration.log'))
      .writeAsString('$line\n', mode: FileMode.append);
}
