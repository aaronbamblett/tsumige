// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumige/src/constants/pref_keys.dart';
import 'package:tsumige/src/core/legacy_migration.dart';

void main() {
  late Directory temp;
  late String share;
  late String home;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('tsumige_migration_test_');
    share = p.join(temp.path, 'share');
    home = p.join(temp.path, 'home');
    Directory(share).createSync(recursive: true);
    Directory(home).createSync(recursive: true);
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  Map<String, String> env({String? xdg}) => {
    'HOME': home,
    'XDG_DATA_HOME': ?xdg,
  };

  void writeLegacyData(String root) {
    Directory(p.join(root, 'covers')).createSync(recursive: true);
    File(p.join(root, 'library.json')).writeAsStringSync('{"games":[]}');
    File(p.join(root, 'covers', 'a.png')).writeAsStringSync('png');
  }

  group('data folder', () {
    test('moves the XDG legacy folder and logs one line', () async {
      final legacy = p.join(share, 'vnl');
      writeLegacyData(legacy);

      await migrateLegacyDataDir(env(xdg: share));

      final target = p.join(share, 'tsumige');
      expect(
        File(p.join(target, 'library.json')).readAsStringSync(),
        '{"games":[]}',
      );
      expect(File(p.join(target, 'covers', 'a.png')).existsSync(), isTrue);
      expect(Directory(legacy).existsSync(), isFalse);
      final log = File(p.join(target, 'logs', 'migration.log'));
      expect(log.readAsLinesSync(), hasLength(1));
      expect(log.readAsStringSync(), contains('(moved)'));
    });

    test(
      'falls back to HOME/.local/share when XDG_DATA_HOME is unset',
      () async {
        final shareDir = p.join(home, '.local', 'share');
        Directory(shareDir).createSync(recursive: true);
        writeLegacyData(p.join(shareDir, 'vnl'));

        await migrateLegacyDataDir(env());

        expect(
          File(p.join(shareDir, 'tsumige', 'library.json')).existsSync(),
          isTrue,
        );
        expect(Directory(p.join(shareDir, 'vnl')).existsSync(), isFalse);
      },
    );

    test(
      'uses the new folder and leaves the legacy one when both exist',
      () async {
        final legacy = p.join(share, 'vnl');
        final target = p.join(share, 'tsumige');
        writeLegacyData(legacy);
        Directory(target).createSync();
        File(p.join(target, 'library.json')).writeAsStringSync('new');

        await migrateLegacyDataDir(env(xdg: share));

        expect(File(p.join(target, 'library.json')).readAsStringSync(), 'new');
        expect(
          File(p.join(legacy, 'library.json')).readAsStringSync(),
          '{"games":[]}',
        );
        expect(
          File(p.join(target, 'logs', 'migration.log')).existsSync(),
          isFalse,
        );
      },
    );

    test('does nothing when there is no legacy folder', () async {
      await migrateLegacyDataDir(env(xdg: share));

      expect(Directory(p.join(share, 'tsumige')).existsSync(), isFalse);
      expect(Directory(p.join(share, 'vnl')).existsSync(), isFalse);
    });

    test('skips migration when TSUMIGE_DATA_DIR is set', () async {
      final legacy = p.join(share, 'vnl');
      writeLegacyData(legacy);
      final override = p.join(temp.path, 'custom');

      await migrateLegacyDataDir({
        ...env(xdg: share),
        'TSUMIGE_DATA_DIR': override,
      });

      expect(Directory(legacy).existsSync(), isTrue);
      expect(Directory(p.join(share, 'tsumige')).existsSync(), isFalse);
      expect(Directory(override).existsSync(), isFalse);
    });

    test('copies and keeps the legacy folder when a rename fails', () async {
      final legacy = p.join(share, 'vnl');
      writeLegacyData(legacy);

      await migrateLegacyDataDir(
        env(xdg: share),
        rename: (from, to) async {
          throw const FileSystemException('cross-device link');
        },
      );

      final target = p.join(share, 'tsumige');
      expect(
        File(p.join(target, 'library.json')).readAsStringSync(),
        '{"games":[]}',
      );
      expect(File(p.join(target, 'covers', 'a.png')).existsSync(), isTrue);
      expect(File(p.join(legacy, 'library.json')).existsSync(), isTrue);
      expect(Directory('$target.migrating').existsSync(), isFalse);
      expect(
        File(p.join(target, 'logs', 'migration.log')).readAsStringSync(),
        contains('(copied)'),
      );
    });
  });

  group('preferences file', () {
    const legacyRel = 'dev.vnl.vnl/shared_preferences.json';
    const newRel = 'app.tsumige.Tsumige/shared_preferences.json';

    test('copies the old file into the new app-id folder', () async {
      File(p.join(share, legacyRel))
        ..createSync(recursive: true)
        ..writeAsStringSync('{"launch.prefix":"x"}');

      await migrateLegacyPrefsFile(env(xdg: share));

      expect(
        File(p.join(share, newRel)).readAsStringSync(),
        '{"launch.prefix":"x"}',
      );
      expect(File(p.join(share, legacyRel)).existsSync(), isTrue);
    });

    test('leaves an existing new file untouched', () async {
      File(p.join(share, legacyRel))
        ..createSync(recursive: true)
        ..writeAsStringSync('old');
      File(p.join(share, newRel))
        ..createSync(recursive: true)
        ..writeAsStringSync('new');

      await migrateLegacyPrefsFile(env(xdg: share));

      expect(File(p.join(share, newRel)).readAsStringSync(), 'new');
    });

    test('creates the new app-id folder when there is no old file', () async {
      await migrateLegacyPrefsFile(env(xdg: share));

      expect(
        Directory(p.join(share, 'app.tsumige.Tsumige')).existsSync(),
        isTrue,
      );
      expect(File(p.join(share, newRel)).existsSync(), isFalse);
    });
  });

  group('launch prefix', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('keeps the old prefix for an install that already has one', () async {
      Directory(p.join(home, 'Games', 'vnl', 'prefix'))
          .createSync(recursive: true);
      final prefs = await SharedPreferences.getInstance();

      await migrateLaunchPrefix(prefs, env());

      expect(prefs.getString(PrefKey.launchPrefix.key), '~/Games/vnl/prefix');
    });

    test('leaves the default for a new install', () async {
      final prefs = await SharedPreferences.getInstance();

      await migrateLaunchPrefix(prefs, env());

      expect(prefs.containsKey(PrefKey.launchPrefix.key), isFalse);
    });

    test('does not overwrite a prefix the user already set', () async {
      Directory(p.join(home, 'Games', 'vnl', 'prefix'))
          .createSync(recursive: true);
      SharedPreferences.setMockInitialValues({
        PrefKey.launchPrefix.key: '~/Games/mine',
      });
      final prefs = await SharedPreferences.getInstance();

      await migrateLaunchPrefix(prefs, env());

      expect(prefs.getString(PrefKey.launchPrefix.key), '~/Games/mine');
    });
  });
}
