// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vnl/main.dart';
import 'package:vnl/src/core/launch/game_runner.dart';
import 'package:vnl/src/core/launch/launch_command.dart';
import 'package:vnl/src/core/launch/process_table.dart';
import 'package:vnl/src/core/covers.dart' as core;
import 'package:vnl/src/core/launch/session_recorder.dart';
import 'package:vnl/src/core/model.dart' as core;
import 'package:vnl/src/core/paths.dart' as core;
import 'package:vnl/src/core/vndb.dart' as core;
import 'package:vnl/src/features/library/data/library_repository.dart';
import 'package:vnl/src/features/library/domain/cover_source.dart';
import 'package:vnl/src/features/library/domain/launch_actions.dart';
import 'package:vnl/src/utils/prefs/prefs_mixin.dart';

class FakeRepository implements LibraryRepository {
  FakeRepository(this.games);

  final List<core.Game> games;
  var loads = 0;

  @override
  Future<core.LoadedLibrary> load() async {
    loads++;
    return core.LoadedLibrary(library: core.Library(games: games));
  }

  @override
  Future<void> save(core.LoadedLibrary loaded) async {}

  @override
  Future<core.VndbRefreshReport> refreshVndbData(core.LoadedLibrary loaded) async =>
      const core.VndbRefreshReport();

  @override
  Future<core.ThumbReport> ensureThumbnails(core.Library library) async =>
      core.ThumbReport();
}

class _FakeStore implements SessionStore {
  @override
  Future<core.LoadedLibrary> load() async =>
      core.LoadedLibrary(library: core.Library(games: []));

  @override
  Future<void> save(core.LoadedLibrary loaded) async {}
}

class _NeverStarter implements ProcessStarter {
  @override
  Future<StartedProcess> start(LaunchCommand command, File log) =>
      throw StateError('must not start a real process');
}

class _EmptyTable implements ProcessTable {
  @override
  Future<List<int>> pidsWithEnv(String key, String value) async => [];
}

class FakeRunner extends GameRunner {
  FakeRunner()
      : super(
          dir: core.DataDir('fake'),
          store: _FakeStore(),
          starter: _NeverStarter(),
          processTable: _EmptyTable(),
        );

  final calls = <({core.Game game, String? overrideExe})>[];
  Completer<void>? gate;
  Future<void> Function(void Function(LaunchPhase) emit)? script;
  LaunchResult nextResult = LaunchResult(
    logFile: File('fake.log'),
    exitCode: 0,
    quickFailure: false,
  );

  @override
  Future<LaunchResult> launch(
    core.Game game,
    LaunchDefaults defaults, {
    String? overrideExe,
    String? umuRunPath,
    void Function(LaunchPhase)? onPhase,
  }) async {
    calls.add((game: game, overrideExe: overrideExe));
    void emit(LaunchPhase phase) => onPhase?.call(phase);
    if (script != null) {
      await script!(emit);
    } else {
      emit(LaunchPhase.starting);
      emit(LaunchPhase.running);
      final pending = gate;
      if (pending != null) await pending.future;
    }
    return nextResult;
  }
}

Future<String?> noPick(core.Game _) async => null;
Future<String?> pickPatch(core.Game _) async => '/games/g/patch.exe';

Future<Directory> pumpLaunch(
  WidgetTester tester,
  List<core.Game> games, {
  String? umu,
  Future<String?> Function(core.Game)? picker,
  FakeRunner? runner,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('window_manager'),
    (call) async {
      if (call.method == 'isMaximized') return false;
      return null;
    },
  );
  final temp = Directory.systemTemp.createTempSync('vnl_launch_test_');
  addTearDown(() => temp.deleteSync(recursive: true));
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider
          .overrideWithValue(await SharedPreferences.getInstance()),
      dataDirProvider.overrideWithValue(core.DataDir(temp.path)),
      libraryRepositoryProvider
          .overrideWithValue(FakeRepository(games)),
      coverExistsProvider.overrideWithValue((_) => false),
      gameRunnerProvider.overrideWithValue(runner ?? FakeRunner()),
      umuRunPathProvider.overrideWithValue(umu),
      exePickerProvider.overrideWithValue(picker ?? noPick),
    ],
    child: const VnlApp(),
  ));
  await tester.pump();
  await tester.pump();
  return temp;
}

Future<void> openPane(WidgetTester tester, String title) async {
  await tester.tap(find.text(title).first);
  await tester.pump();
  await tester.pump();
}

Finder launchButton() => find.widgetWithText(FilledButton, 'Play');
Finder runningButton() => find.widgetWithText(FilledButton, 'Running');

String launchTooltip(WidgetTester tester) {
  final tip = find.ancestor(of: launchButton(), matching: find.byType(Tooltip));
  return tester.widget<Tooltip>(tip).message ?? '';
}

core.Game nativeGame(String id, String title, {String? exe}) => core.Game(
      id: id,
      title: title,
      launch: core.LaunchOverrides(
          mode: core.LaunchMode.native, executable: exe),
    );

core.Game protonGame(String id, String title) => core.Game(
      id: id,
      title: title,
      launch: core.LaunchOverrides(
        mode: core.LaunchMode.proton,
        executable: '/games/g/game.exe',
      ),
    );

core.Game steamGame(String id, String title) => core.Game(
      id: id,
      title: title,
      launch: core.LaunchOverrides(
          mode: core.LaunchMode.steam, steamAppId: 1230140),
    );

Finder launchingButton() => find.widgetWithText(FilledButton, 'Launching…');

void main() {
  testWidgets('launch is disabled with no executable set', (tester) async {
    await pumpLaunch(tester, [nativeGame('g1', 'Alpha')]);
    await openPane(tester, 'Alpha');
    expect(tester.widget<FilledButton>(launchButton()).onPressed, isNull);
    expect(launchTooltip(tester), 'No executable set');
    expect(find.text('Run .exe inside prefix…'), findsNothing);
  });

  testWidgets('launch is disabled when the steam app id is missing',
      (tester) async {
    await pumpLaunch(tester, [
      core.Game(
        id: 'g1',
        title: 'Alpha',
        launch: core.LaunchOverrides(mode: core.LaunchMode.steam),
      ),
    ]);
    await openPane(tester, 'Alpha');
    expect(tester.widget<FilledButton>(launchButton()).onPressed, isNull);
    expect(launchTooltip(tester), 'Steam App ID is not set');
  });

  testWidgets('proton launch is disabled without umu-run', (tester) async {
    await pumpLaunch(tester, [protonGame('g1', 'Alpha')], umu: null);
    await openPane(tester, 'Alpha');
    expect(tester.widget<FilledButton>(launchButton()).onPressed, isNull);
    expect(launchTooltip(tester), 'umu-run not found on PATH');
    expect(find.text('Run .exe inside prefix…'), findsOneWidget);
  });

  testWidgets('proton launch is enabled with umu-run', (tester) async {
    await pumpLaunch(tester, [protonGame('g1', 'Alpha')],
        umu: '/usr/bin/umu-run');
    await openPane(tester, 'Alpha');
    expect(
        tester.widget<FilledButton>(launchButton()).onPressed, isNotNull);
  });

  testWidgets('pressing launch calls the runner once', (tester) async {
    final runner = FakeRunner();
    await pumpLaunch(tester, [protonGame('g1', 'Alpha')],
        umu: '/usr/bin/umu-run', runner: runner);
    await openPane(tester, 'Alpha');
    await tester.tap(launchButton());
    await tester.pump();
    await tester.pump();
    expect(runner.calls, hasLength(1));
    expect(runner.calls.single.game.id, 'g1');
    expect(runner.calls.single.overrideExe, isNull);
  });

  testWidgets('a recorded session reloads the library', (tester) async {
    final runner = FakeRunner()
      ..nextResult = LaunchResult(
        logFile: File('fake.log'),
        exitCode: 0,
        quickFailure: false,
        sessionSeconds: 90,
      );
    FakeRepository? repo;
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async {
        if (call.method == 'isMaximized') return false;
        return null;
      },
    );
    final temp = Directory.systemTemp.createTempSync('vnl_launch_test_');
    addTearDown(() => temp.deleteSync(recursive: true));
    SharedPreferences.setMockInitialValues({});
    repo = FakeRepository([protonGame('g1', 'Alpha')]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider
            .overrideWithValue(await SharedPreferences.getInstance()),
        dataDirProvider.overrideWithValue(core.DataDir(temp.path)),
        libraryRepositoryProvider.overrideWithValue(repo),
        coverExistsProvider.overrideWithValue((_) => false),
        gameRunnerProvider.overrideWithValue(runner),
        umuRunPathProvider.overrideWithValue('/usr/bin/umu-run'),
        exePickerProvider.overrideWithValue(noPick),
      ],
      child: const VnlApp(),
    ));
    await tester.pump();
    await tester.pump();
    final before = repo.loads;
    await tester.tap(find.text('Alpha').first);
    await tester.pump();
    await tester.pump();
    await tester.tap(launchButton());
    await tester.pump();
    await tester.pump();
    expect(repo.loads, greaterThan(before));
  });

  testWidgets('a quick failure toasts the log path', (tester) async {
    final runner = FakeRunner()
      ..nextResult = LaunchResult(
        logFile: File('/tmp/x/Test-Game.log'),
        exitCode: 1,
        quickFailure: true,
      );
    await pumpLaunch(tester, [protonGame('g1', 'Alpha')],
        umu: '/usr/bin/umu-run', runner: runner);
    await openPane(tester, 'Alpha');
    await tester.tap(launchButton());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('exited right away'), findsOneWidget);
    expect(find.textContaining('/tmp/x/Test-Game.log'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('while running, the button reads Running', (tester) async {
    final runner = FakeRunner()..gate = Completer<void>();
    await pumpLaunch(tester, [protonGame('g1', 'Alpha')],
        umu: '/usr/bin/umu-run', runner: runner);
    await openPane(tester, 'Alpha');
    await tester.tap(launchButton());
    await tester.pump();
    await tester.pump();
    expect(runningButton(), findsOneWidget);
    final tip = find.ancestor(of: runningButton(), matching: find.byType(Tooltip));
    expect(tester.widget<Tooltip>(tip).message, 'Running');
    expect(tester.widget<FilledButton>(runningButton()).onPressed, isNull);
    runner.gate!.complete();
    await tester.pump();
    await tester.pump();
    expect(launchButton(), findsOneWidget);
  });

  testWidgets('native shows Running while the process lives', (tester) async {
    final runner = FakeRunner()..gate = Completer<void>();
    await pumpLaunch(
        tester,
        [nativeGame('g1', 'Alpha', exe: '/games/g/start.sh')],
        runner: runner);
    await openPane(tester, 'Alpha');
    await tester.tap(launchButton());
    await tester.pump();
    await tester.pump();
    expect(runningButton(), findsOneWidget);
    runner.gate!.complete();
    await tester.pump();
    await tester.pump();
    expect(launchButton(), findsOneWidget);
  });

  testWidgets(
      'a launch that ends after the pane was closed and reopened ends as Play',
      (tester) async {
    final runner = FakeRunner()..gate = Completer<void>();
    await pumpLaunch(tester, [protonGame('g1', 'Alpha')],
        umu: '/usr/bin/umu-run', runner: runner);
    await openPane(tester, 'Alpha');
    await tester.tap(launchButton());
    await tester.pump();
    await tester.pump();
    expect(runningButton(), findsOneWidget);
    // Closing the pane drops every listener on the launch providers. The
    // game keeps running; reopening must still show it as running, and the
    // exit must clear it back to Launch.
    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(FilledButton), findsNothing);
    await openPane(tester, 'Alpha');
    await tester.pump();
    expect(runningButton(), findsOneWidget);
    runner.gate!.complete();
    await tester.pump();
    await tester.pump();
    expect(launchButton(), findsOneWidget);
  });

  testWidgets(
      'steam shows Launching… until the process appears, then Running',
      (tester) async {
    final runner = FakeRunner();
    final appear = Completer<void>();
    final exit = Completer<void>();
    runner.script = (emit) async {
      emit(LaunchPhase.starting);
      await appear.future;
      emit(LaunchPhase.running);
      await exit.future;
    };
    await pumpLaunch(tester, [steamGame('g1', 'Demo')],
        umu: '/usr/bin/umu-run', runner: runner);
    await openPane(tester, 'Demo');
    await tester.tap(launchButton());
    await tester.pump();
    await tester.pump();
    expect(launchingButton(), findsOneWidget);
    expect(
        tester.widget<FilledButton>(launchingButton()).onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(runningButton(), findsNothing);
    appear.complete();
    await tester.pump();
    await tester.pump();
    expect(runningButton(), findsOneWidget);
    expect(launchingButton(), findsNothing);
    exit.complete();
    await tester.pump();
    await tester.pump();
    expect(launchButton(), findsOneWidget);
  });

  testWidgets('a runner error returns the button to Play', (tester) async {
    final runner = FakeRunner();
    runner.script = (_) async => throw StateError('boom');
    await pumpLaunch(tester, [protonGame('g1', 'Alpha')],
        umu: '/usr/bin/umu-run', runner: runner);
    await openPane(tester, 'Alpha');
    await tester.tap(launchButton());
    await tester.pump();
    await tester.pump();
    expect(launchButton(), findsOneWidget);
    expect(find.textContaining('Failed to launch'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('run-exe with a cancelled picker does nothing', (tester) async {
    final runner = FakeRunner();
    await pumpLaunch(tester, [protonGame('g1', 'Alpha')],
        umu: '/usr/bin/umu-run', runner: runner, picker: noPick);
    await openPane(tester, 'Alpha');
    await tester.tap(find.text('Run .exe inside prefix…'));
    await tester.pump();
    await tester.pump();
    expect(runner.calls, isEmpty);
  });

  testWidgets('run-exe launches the picked file as an override',
      (tester) async {
    final runner = FakeRunner();
    await pumpLaunch(tester, [protonGame('g1', 'Alpha')],
        umu: '/usr/bin/umu-run', runner: runner, picker: pickPatch);
    await openPane(tester, 'Alpha');
    await tester.tap(find.text('Run .exe inside prefix…'));
    await tester.pump();
    await tester.pump();
    expect(runner.calls, hasLength(1));
    expect(runner.calls.single.overrideExe, '/games/g/patch.exe');
  });

  testWidgets('the umu banner shows when proton is used and umu is missing',
      (tester) async {
    await pumpLaunch(tester, [protonGame('g1', 'Alpha')], umu: null);
    expect(
      find.text(
          "umu-run was not found on PATH, so Proton games can't launch."),
      findsOneWidget,
    );
  });

  testWidgets('no umu banner when umu-run is present', (tester) async {
    await pumpLaunch(tester, [protonGame('g1', 'Alpha')],
        umu: '/usr/bin/umu-run');
    expect(
      find.text(
          "umu-run was not found on PATH, so Proton games can't launch."),
      findsNothing,
    );
  });

  testWidgets('leftover markers recover with a toast on startup',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async {
        if (call.method == 'isMaximized') return false;
        return null;
      },
    );
    final temp = Directory.systemTemp.createTempSync('vnl_launch_test_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final running =
        Directory('${temp.path}/running')..createSync(recursive: true);
    final started = DateTime.utc(2026, 10, 17, 12).toIso8601String();
    final seen = DateTime.utc(2026, 10, 17, 12, 5).toIso8601String();
    File('${running.path}/g1.json').writeAsStringSync(
        '{"started_at":"$started","last_seen":"$seen"}');
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider
            .overrideWithValue(await SharedPreferences.getInstance()),
        dataDirProvider.overrideWithValue(core.DataDir(temp.path)),
        libraryRepositoryProvider.overrideWithValue(
            FakeRepository([core.Game(id: 'g1', title: 'Alpha')])),
        coverExistsProvider.overrideWithValue((_) => false),
        gameRunnerProvider.overrideWithValue(FakeRunner()),
        umuRunPathProvider.overrideWithValue('/usr/bin/umu-run'),
        exePickerProvider.overrideWithValue(noPick),
      ],
      child: const VnlApp(),
    ));
    await tester.pump();
    await tester.pump();
    // Recovery does real file IO, which only completes while the real event
    // loop runs; alternate frames with short real-async windows.
    for (var i = 0;
        i < 50 &&
            find.text('Recovered 1 play session(s)').evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    expect(find.text('Recovered 1 play session(s)'), findsOneWidget);
    expect(File('${running.path}/g1.json').existsSync(), isFalse);
    await tester.pump(const Duration(seconds: 6));
  });
}
