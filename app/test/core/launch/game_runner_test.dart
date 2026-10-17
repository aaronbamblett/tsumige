// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vnl/src/core/launch/game_runner.dart';
import 'package:vnl/src/core/launch/launch_command.dart';
import 'package:vnl/src/core/launch/process_table.dart';
import 'package:vnl/src/core/launch/session_recorder.dart';
import 'package:vnl/src/core/model.dart';
import 'package:vnl/src/core/paths.dart';

class FakeStore implements SessionStore {
  FakeStore(this.current, {this.onSave});

  final void Function()? onSave;

  LoadedLibrary current;

  @override
  Future<LoadedLibrary> load() async {
    final games = [
      for (final game in current.library.games) Game.fromJson(game.toJson()),
    ];
    return LoadedLibrary(
        library: Library(games: games), stamp: current.stamp);
  }

  @override
  Future<void> save(LoadedLibrary loaded) async {
    current = loaded;
    onSave?.call();
  }
}

class FakeStartedProcess implements StartedProcess {
  FakeStartedProcess({
    required this.pid,
    required this.exitCode,
    Future<void>? logClosed,
  }) : logClosed = logClosed ?? Future.value();

  @override
  final int pid;

  @override
  final Future<int> exitCode;

  @override
  final Future<void> logClosed;
}

class FakeStarter implements ProcessStarter {
  FakeStarter(this.onStart);

  final Future<StartedProcess> Function(LaunchCommand, File) onStart;
  final started = <LaunchCommand>[];

  @override
  Future<StartedProcess> start(LaunchCommand command, File log) async {
    started.add(command);
    return onStart(command, log);
  }
}

class FakeTable implements ProcessTable {
  FakeTable(this.present);

  final bool Function() present;

  @override
  Future<List<int>> pidsWithEnv(String key, String value) async =>
      present() ? [4242] : [];
}

const defaults = LaunchDefaults(
  mode: LaunchMode.native,
  prefix: '/p',
  locale: '',
  umuGameId: 'umu-default',
);

Game nativeGame() => Game(
      id: 'g1',
      title: 'Test Game',
      launch: LaunchOverrides(
        mode: LaunchMode.native,
        executable: '/games/g/start.sh',
      ),
    );

Game protonGame() => Game(
      id: 'g1',
      title: 'Test Game',
      launch: LaunchOverrides(
        mode: LaunchMode.proton,
        executable: '/games/g/game.exe',
      ),
    );

Game steamGame() => Game(
      id: 'g1',
      title: 'Test Game',
      launch: LaunchOverrides(mode: LaunchMode.steam, steamAppId: 4242),
    );

void main() {
  late Directory temp;
  late DataDir dir;
  late DateTime now;
  final t0 = DateTime.utc(2026, 10, 17, 12);

  setUp(() {
    temp = Directory.systemTemp.createTempSync('vnl_runner_test_');
    dir = DataDir(temp.path);
    now = t0;
  });
  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  FakeStore storeWith(Game game) =>
      FakeStore(LoadedLibrary(library: Library(games: [game])));

  GameRunner runner({
    required FakeStore store,
    required FakeStarter starter,
    bool Function()? present,
    Duration heartbeatInterval = const Duration(seconds: 60),
  }) {
    return GameRunner(
      dir: dir,
      store: store,
      starter: starter,
      processTable: FakeTable(present ?? () => false),
      hostEnv: const {},
      clock: () => now,
      sleep: (d) async {
        now = now.add(d);
      },
      heartbeatInterval: heartbeatInterval,
    );
  }

  File markerFile() => File(p.join(temp.path, 'running', 'g1.json'));
  File latestFile() => File(p.join(temp.path, 'logs', 'latest.log'));

  test('a 90s run records one 90s session and cleans up', () async {
    final store = storeWith(nativeGame());
    final starter = FakeStarter((command, log) async {
      await log.writeAsString('hello\n');
      Future<int> exit() async {
        now = now.add(const Duration(seconds: 90));
        return 0;
      }

      return FakeStartedProcess(pid: 7, exitCode: exit());
    });
    final result = await runner(store: store, starter: starter)
        .launch(nativeGame(), defaults);
    expect(result.exitCode, 0);
    expect(result.quickFailure, isFalse);
    expect(result.sessionSeconds, 90);
    final sessions = store.current.library.games.single.playSessions;
    expect(sessions, hasLength(1));
    expect(sessions.single.startedAt, t0);
    expect(sessions.single.durationSeconds, 90);
    expect(await latestFile().readAsString(), 'hello\n');
    expect(markerFile().existsSync(), isFalse);
    expect(starter.started, hasLength(1));
  });

  test('a quick non-zero exit records no session', () async {
    final store = storeWith(nativeGame());
    final starter = FakeStarter((command, log) async {
      Future<int> exit() async {
        now = now.add(const Duration(seconds: 2));
        return 1;
      }

      return FakeStartedProcess(pid: 7, exitCode: exit());
    });
    final result = await runner(store: store, starter: starter)
        .launch(nativeGame(), defaults);
    expect(result.exitCode, 1);
    expect(result.quickFailure, isTrue);
    expect(result.sessionSeconds, isNull);
    expect(result.logFile.path, endsWith('.log'));
    expect(result.logFile.path, contains('Test-Game'));
    expect(store.current.library.games.single.playSessions, isEmpty);
    expect(markerFile().existsSync(), isFalse);
    expect(latestFile().existsSync(), isTrue);
  });

  test('a clean 2s exit still records a 2s session', () async {
    final store = storeWith(nativeGame());
    final starter = FakeStarter((command, log) async {
      Future<int> exit() async {
        now = now.add(const Duration(seconds: 2));
        return 0;
      }

      return FakeStartedProcess(pid: 7, exitCode: exit());
    });
    final result = await runner(store: store, starter: starter)
        .launch(nativeGame(), defaults);
    expect(result.exitCode, 0);
    expect(result.quickFailure, isFalse);
    expect(result.sessionSeconds, 2);
    final sessions = store.current.library.games.single.playSessions;
    expect(sessions, hasLength(1));
    expect(sessions.single.durationSeconds, 2);
  });

  test('stuck log streams do not stretch the session', () async {
    // Gated on the session write: the launch reads the end time before
    // recording, and only then awaits the drain, so the drain's 5 s may
    // not run first. Mirrors production, where the 5 s timeout is real
    // time and cannot move the fake clock early.
    final sessionSaved = Completer<void>();
    final store = FakeStore(
      LoadedLibrary(library: Library(games: [nativeGame()])),
      onSave: () {
        if (!sessionSaved.isCompleted) sessionSaved.complete();
      },
    );
    final starter = FakeStarter((command, log) async {
      final exit = () async {
        now = now.add(const Duration(seconds: 90));
        return 0;
      }();
      // Streams stay open: the drain only finishes 5 s after exit, on the
      // fake clock, with no real waiting.
      final closed = () async {
        await exit;
        await sessionSaved.future;
        now = now.add(const Duration(seconds: 5));
      }();
      return FakeStartedProcess(pid: 7, exitCode: exit, logClosed: closed);
    });
    final result = await runner(store: store, starter: starter)
        .launch(nativeGame(), defaults);
    expect(result.exitCode, 0);
    expect(result.quickFailure, isFalse);
    expect(result.sessionSeconds, 90);
    final sessions = store.current.library.games.single.playSessions;
    expect(sessions, hasLength(1));
    expect(sessions.single.startedAt, t0);
    expect(sessions.single.durationSeconds, 90);
    // The launch waited for the drain: the fake clock ran 5 s past exit.
    expect(now, t0.add(const Duration(seconds: 95)));
    expect(markerFile().existsSync(), isFalse);
    expect(latestFile().existsSync(), isTrue);
  });

  test('run-exe-in-prefix records no session', () async {
    final store = storeWith(protonGame());
    final starter = FakeStarter((command, log) async {
      Future<int> exit() async {
        now = now.add(const Duration(seconds: 30));
        return 0;
      }

      return FakeStartedProcess(pid: 7, exitCode: exit());
    });
    final result = await runner(store: store, starter: starter).launch(
      protonGame(),
      defaults,
      overrideExe: '/games/g/patch.exe',
      umuRunPath: '/usr/bin/umu-run',
    );
    expect(result.quickFailure, isFalse);
    expect(result.sessionSeconds, isNull);
    expect(store.current.library.games.single.playSessions, isEmpty);
    expect(markerFile().existsSync(), isFalse);
    expect(latestFile().existsSync(), isTrue);
    expect(starter.started.single.args.first, '/games/g/patch.exe');
  });

  test('steam times the game process, not the launcher', () async {
    final store = storeWith(steamGame());
    final starter = FakeStarter((command, log) async =>
        FakeStartedProcess(pid: 7, exitCode: Future.value(0)));
    bool present() =>
        !now.isBefore(t0.add(const Duration(seconds: 10))) &&
        now.isBefore(t0.add(const Duration(seconds: 130)));
    final result = await runner(store: store, starter: starter, present: present)
        .launch(steamGame(), defaults);
    expect(result.quickFailure, isFalse);
    expect(result.sessionSeconds, 120);
    final sessions = store.current.library.games.single.playSessions;
    expect(sessions, hasLength(1));
    expect(sessions.single.startedAt, t0.add(const Duration(seconds: 10)));
    expect(sessions.single.durationSeconds, 120);
    expect(markerFile().existsSync(), isFalse);
    expect(latestFile().existsSync(), isTrue);
  });

  test('steam that never appears records no session', () async {
    final store = storeWith(steamGame());
    final starter = FakeStarter((command, log) async =>
        FakeStartedProcess(pid: 7, exitCode: Future.value(0)));
    final result =
        await runner(store: store, starter: starter).launch(steamGame(), defaults);
    expect(result.quickFailure, isFalse);
    expect(result.sessionSeconds, isNull);
    expect(store.current.library.games.single.playSessions, isEmpty);
    expect(markerFile().existsSync(), isFalse);
    expect(latestFile().existsSync(), isTrue);
  });

  test('the heartbeat refreshes last_seen while the game runs', () async {
    final store = storeWith(nativeGame());
    final exit = Completer<int>();
    final gameRunner = GameRunner(
      dir: dir,
      store: store,
      starter: FakeStarter((command, log) async =>
          FakeStartedProcess(pid: 7, exitCode: exit.future)),
      processTable: FakeTable(() => false),
      hostEnv: const {},
      clock: () => now,
      heartbeatInterval: const Duration(milliseconds: 20),
    );
    final future = gameRunner.launch(nativeGame(), defaults);
    for (var i = 0; i < 200 && !markerFile().existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(markerFile().existsSync(), isTrue);
    now = now.add(const Duration(seconds: 120));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final data = await markerFile().readAsString();
    expect(data, contains('started_at'));
    final seen = (await logStartedAndSeen(markerFile())).$2;
    expect(seen, now);
    now = now.add(const Duration(seconds: 10));
    exit.complete(0);
    final result = await future;
    expect(result.sessionSeconds, 130);
    expect(markerFile().existsSync(), isFalse);
  });
}

Future<(DateTime, DateTime)> logStartedAndSeen(File marker) async {
  final data = jsonDecode(await marker.readAsString()) as Map;
  return (
    DateTime.parse(data['started_at'] as String),
    DateTime.parse(data['last_seen'] as String),
  );
}
