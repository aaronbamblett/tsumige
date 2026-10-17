// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/launch/game_runner.dart';
import '../../../core/launch/launch_command.dart';
import '../../../core/launch/process_table.dart';
import '../../../core/launch/session_recorder.dart';
import '../../../core/model.dart' as core;
import '../../../utils/prefs/app_prefs.dart';
import '../../../utils/toast.dart';
import '../data/library_repository.dart';
import 'running_games.dart';

part 'launch_actions.g.dart';

/// `umu-run` resolved from PATH. A seam so tests can force it missing.
@riverpod
String? umuRunPath(Ref ref) => findOnPath('umu-run', Platform.environment);

/// The real game runner, wired to the data folder and the repository.
/// Tests override this with a fake that never starts a process.
@riverpod
GameRunner gameRunner(Ref ref) {
  return GameRunner(
    dir: ref.watch(dataDirProvider),
    store: ref.watch(sessionStoreProvider),
    starter: IoProcessStarter(),
    processTable: ProcProcessTable(),
  );
}

/// The session store behind [gameRunnerProvider], shared with startup
/// recovery so both write through the repository.
@riverpod
SessionStore sessionStore(Ref ref) =>
    _RepositorySessionStore(ref.watch(libraryRepositoryProvider));

class _RepositorySessionStore implements SessionStore {
  _RepositorySessionStore(this.repository);

  final LibraryRepository repository;

  @override
  Future<core.LoadedLibrary> load() => repository.load();

  @override
  Future<void> save(core.LoadedLibrary loaded) => repository.save(loaded);
}

/// Picks an exe to run inside the game's prefix, starting in the game exe's
/// folder when one exists. Null means the dialog was cancelled.
@riverpod
Future<String?> Function(core.Game game) exePicker(Ref ref) => pickExe;

Future<String?> pickExe(core.Game game) async {
  String? initialDirectory;
  final exe = game.launch.executable;
  if (exe != null && exe.isNotEmpty) {
    final folder = p.dirname(exe);
    if (folder != '.' &&
        folder.isNotEmpty &&
        Directory(folder).existsSync()) {
      initialDirectory = folder;
    }
  }
  final files = await FilePicker.pickFiles(
    dialogTitle: 'Run .exe inside prefix',
    initialDirectory: initialDirectory,
    type: FileType.any,
  );
  if (files.isEmpty) return null;
  return files.first.path;
}

class LaunchActions {
  LaunchActions(this._ref);

  final Ref _ref;

  LaunchDefaults _defaults() => LaunchDefaults(
        mode: _ref.read(launchModeProvider),
        prefix: _ref.read(launchPrefixProvider),
        runner: _ref.read(launchRunnerProvider),
        locale: _ref.read(launchLocaleProvider),
        umuGameId: _ref.read(launchUmuGameIdProvider),
      );

  Future<void> launch(BuildContext context, core.Game game) =>
      _run(context, game);

  Future<void> runExeInPrefix(BuildContext context, core.Game game) async {
    final picked = await _ref.read(exePickerProvider)(game);
    if (picked == null || !context.mounted) return;
    await _run(context, game, overrideExe: picked);
  }

  Future<void> _run(BuildContext context, core.Game game,
      {String? overrideExe}) async {
    final running = _ref.read(runningGamesProvider.notifier);
    running.add(game.id);
    try {
      final result = await _ref.read(gameRunnerProvider).launch(
            game,
            _defaults(),
            overrideExe: overrideExe,
            umuRunPath: _ref.read(umuRunPathProvider),
          );
      if (result.sessionSeconds != null) {
        _ref.invalidate(libraryProvider);
      }
      if (!context.mounted) return;
      if (result.quickFailure) {
        Toast(context).showError(
          '${game.title} exited right away. Log: ${result.logFile.path}',
        );
      }
    } on LaunchConfigError catch (e) {
      if (context.mounted) Toast(context).showError(e.message);
    } catch (e) {
      if (context.mounted) {
        Toast(context).showError('Failed to launch ${game.title}: $e');
      }
    } finally {
      running.remove(game.id);
    }
  }
}

@riverpod
LaunchActions launchActions(Ref ref) => LaunchActions(ref);
