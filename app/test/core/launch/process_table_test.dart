// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tsumige/src/core/launch/process_table.dart';

void writeEnviron(String procRoot, String pid, List<String> entries) {
  final dir = Directory(p.join(procRoot, pid))..createSync(recursive: true);
  final bytes = <int>[];
  for (final entry in entries) {
    bytes.addAll(entry.codeUnits);
    bytes.add(0);
  }
  File(p.join(dir.path, 'environ')).writeAsBytesSync(bytes);
}

void main() {
  late Directory proc;
  setUp(() {
    proc = Directory.systemTemp.createTempSync('tsumige_proc_test_');
  });
  tearDown(() {
    proc.deleteSync(recursive: true);
  });

  test('finds the pid whose environ holds SteamAppId=<id>', () async {
    writeEnviron(proc.path, '123', ['FOO=1', 'SteamAppId=999']);
    writeEnviron(proc.path, '456', ['FOO=1']);
    writeEnviron(proc.path, '777', ['SteamAppId=9999']);
    Directory(p.join(proc.path, 'self')).createSync();
    Directory(p.join(proc.path, '789')).createSync();
    final table = ProcProcessTable(procRoot: proc.path);
    expect(await table.pidsWithEnv('SteamAppId', '999'), [123]);
  });

  test('a missing proc root finds nothing', () async {
    final table = ProcProcessTable(
      procRoot: p.join(proc.path, 'does-not-exist'),
    );
    expect(await table.pidsWithEnv('SteamAppId', '999'), isEmpty);
  });

  test('flatpak scan runs on the host with key and value as args', () async {
    String? seenExe;
    List<String>? seenArgs;
    Future<ProcessResult> runner(String exe, List<String> args) async {
      seenExe = exe;
      seenArgs = args;
      return ProcessResult(0, 0, '/proc/123/environ\n/proc/456/environ\n', '');
    }

    final table = FlatpakHostProcessTable(runner);
    expect(await table.pidsWithEnv('SteamAppId', '999'), [123, 456]);
    expect(seenExe, 'flatpak-spawn');
    expect(seenArgs!.take(3).toList(), ['--host', 'sh', '-c']);
    expect(seenArgs!.sublist(seenArgs!.length - 3), [
      'scan',
      'SteamAppId',
      '999',
    ]);
    expect(seenArgs, contains('sh'));
  });

  test('flatpak scan non-zero exit finds nothing', () async {
    final table = FlatpakHostProcessTable(
      (exe, args) async => ProcessResult(0, 1, '/proc/123/environ\n', ''),
    );
    expect(await table.pidsWithEnv('SteamAppId', '999'), isEmpty);
  });

  test('flatpak scan skips junk output lines', () async {
    final table = FlatpakHostProcessTable(
      (exe, args) async => ProcessResult(
        0,
        0,
        'abc\n\n 9 \n/proc/77/environ\n/proc/77/environ\n',
        '',
      ),
    );
    expect(await table.pidsWithEnv('SteamAppId', '999'), [77]);
  });

  test('flatpak scan throwing runner finds nothing', () async {
    final table = FlatpakHostProcessTable(
      (exe, args) async => throw ProcessException('flatpak-spawn', []),
    );
    expect(await table.pidsWithEnv('SteamAppId', '999'), isEmpty);
  });

  test('flatpak scan keeps key and value out of the script', () async {
    List<String>? seenArgs;
    final table = FlatpakHostProcessTable((exe, args) async {
      seenArgs = args;
      return ProcessResult(0, 0, '', '');
    });
    await table.pidsWithEnv('SteamAppId', '999');
    final scriptIndex = seenArgs!.indexOf('-c') + 1;
    final script = seenArgs![scriptIndex];
    expect(script.contains('SteamAppId'), isFalse);
    expect(script.contains('999'), isFalse);
  });

  test(
    'host grep finds a real process by its environment',
    skip: Platform.isLinux ? false : 'needs /proc',
    () async {
      final value = '${Random().nextInt(1 << 31)}';
      final child = await Process.start(
        'sleep',
        ['30'],
        environment: {'SteamAppId': value},
      );
      try {
        final table = FlatpakHostProcessTable(
          (exe, args) => Process.run(args[1], args.sublist(2)),
        );
        expect(
          await table.pidsWithEnv('SteamAppId', value),
          contains(child.pid),
        );
        expect(
          await table.pidsWithEnv('SteamAppId', '${Random().nextInt(1 << 31)}'),
          isEmpty,
        );
      } finally {
        child.kill();
        await child.exitCode;
      }
    },
  );
}
