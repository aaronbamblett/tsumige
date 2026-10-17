// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../model.dart';
import 'args.dart';
import 'env.dart';

class LaunchConfigError implements Exception {
  final String message;

  const LaunchConfigError(this.message);

  @override
  String toString() => 'LaunchConfigError: $message';
}

class LaunchDefaults {
  final LaunchMode mode;
  final String prefix;
  final String? runner;
  final String locale;
  final String umuGameId;

  const LaunchDefaults({
    required this.mode,
    required this.prefix,
    this.runner,
    required this.locale,
    required this.umuGameId,
  });
}

class LaunchCommand {
  final String executable;
  final List<String> args;
  final Map<String, String> env;
  final String? workingDirectory;

  const LaunchCommand({
    required this.executable,
    required this.args,
    required this.env,
    this.workingDirectory,
  });

  @override
  bool operator ==(Object other) =>
      other is LaunchCommand &&
      other.executable == executable &&
      other.workingDirectory == workingDirectory &&
      _listsEqual(other.args, args) &&
      _mapsEqual(other.env, env);

  @override
  int get hashCode => Object.hash(
        executable,
        Object.hashAll(args),
        Object.hashAllUnordered(
            [for (final e in env.entries) Object.hash(e.key, e.value)]),
        workingDirectory,
      );

  @override
  String toString() =>
      'LaunchCommand($executable, args: $args, env: $env, wd: $workingDirectory)';
}

bool _listsEqual(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _mapsEqual(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    if (b[key] != a[key]) return false;
  }
  return true;
}

String? _parentDir(String exe) {
  final dir = p.dirname(exe);
  if (dir == '.' || dir.isEmpty) return null;
  return dir;
}

/// Expands a leading `~/` with `HOME` so the default prefix pref
/// (`~/Games/vnl/prefix`) resolves without a shell.
String expandTilde(String value, Map<String, String> hostEnv) {
  if (!value.startsWith('~/')) return value;
  final home = hostEnv['HOME'];
  if (home == null || home.isEmpty) return value;
  return '$home/${value.substring(2)}';
}

LaunchCommand buildLaunchCommand(
  Game game,
  LaunchDefaults defaults, {
  String? overrideExe,
  required Map<String, String> hostEnv,
  String? umuRunPath,
}) {
  final mode = game.launch.mode ?? defaults.mode;
  final extraEnv = parseEnv(game.launch.environment ?? '');
  final inFlatpak = hostEnv.containsKey('FLATPAK_ID');
  LaunchCommand command;
  if (mode == LaunchMode.steam) {
    if (overrideExe != null) {
      throw const LaunchConfigError(
          'Run .exe inside prefix needs Proton or Wine');
    }
    final appId = game.launch.steamAppId;
    if (appId == null) {
      throw const LaunchConfigError('Steam App ID is not set');
    }
    command = LaunchCommand(
      executable: 'steam',
      args: ['-applaunch', '$appId'],
      env: extraEnv,
      workingDirectory: null,
    );
  } else {
    if (overrideExe != null && mode == LaunchMode.native) {
      throw const LaunchConfigError(
          'Run .exe inside prefix needs Proton or Wine');
    }
    final rawExe = overrideExe ?? game.launch.executable;
    if (rawExe == null || rawExe.isEmpty) {
      throw const LaunchConfigError('No executable set');
    }
    final exe = expandTilde(rawExe, hostEnv);
    final extraArgs = splitArgs(game.launch.arguments ?? '');
    final workingDirectory = _parentDir(exe);
    switch (mode) {
      case LaunchMode.native:
        command = LaunchCommand(
          executable: exe,
          args: extraArgs,
          env: extraEnv,
          workingDirectory: workingDirectory,
        );
      case LaunchMode.wine:
        final runner = expandTilde(
            game.launch.runner ?? defaults.runner ?? 'wine', hostEnv);
        final locale = game.launch.locale ?? defaults.locale;
        final env = <String, String>{
          'WINEPREFIX': expandTilde(
              game.launch.prefix ?? defaults.prefix, hostEnv),
        };
        if (locale.isNotEmpty) {
          env['LANG'] = locale;
          env['LC_ALL'] = locale;
        }
        env.addAll(extraEnv);
        command = LaunchCommand(
          executable: runner,
          args: [exe, ...extraArgs],
          env: env,
          workingDirectory: workingDirectory,
        );
      case LaunchMode.proton:
        if (umuRunPath == null) {
          throw const LaunchConfigError('umu-run not found on PATH');
        }
        final rawRunner = game.launch.runner ?? defaults.runner;
        final runner =
            rawRunner == null ? null : expandTilde(rawRunner, hostEnv);
        final locale = game.launch.locale ?? defaults.locale;
        final env = <String, String>{
          'WINEPREFIX': expandTilde(
              game.launch.prefix ?? defaults.prefix, hostEnv),
          'GAMEID': game.launch.umuGameId ?? defaults.umuGameId,
        };
        if (runner != null) env['PROTONPATH'] = runner;
        if (locale.isNotEmpty) {
          env['LANG'] = locale;
          env['LC_ALL'] = locale;
        }
        env.addAll(extraEnv);
        command = LaunchCommand(
          executable: inFlatpak ? 'umu-run' : umuRunPath,
          args: [exe, ...extraArgs],
          env: env,
          workingDirectory: workingDirectory,
        );
      case LaunchMode.steam:
        throw StateError('unreachable');
    }
  }
  if (!inFlatpak) return command;
  final wrapped = <String>['--host'];
  final display = hostEnv['DISPLAY'];
  if (display != null) wrapped.add('--env=DISPLAY=$display');
  if (command.workingDirectory != null) {
    wrapped.add('--directory=${command.workingDirectory}');
  }
  for (final entry in command.env.entries) {
    wrapped.add('--env=${entry.key}=${entry.value}');
  }
  wrapped.add(command.executable);
  wrapped.addAll(command.args);
  return LaunchCommand(
    executable: 'flatpak-spawn',
    args: wrapped,
    env: const {},
    workingDirectory: null,
  );
}

String? findOnPath(
  String name,
  Map<String, String> hostEnv, {
  bool Function(String path)? isExecutable,
}) {
  final check = isExecutable ?? ((path) => File(path).existsSync());
  final pathVar = hostEnv['PATH'];
  if (pathVar == null || pathVar.isEmpty) return null;
  for (final dir in pathVar.split(':')) {
    if (dir.isEmpty) continue;
    final candidate = p.join(dir, name);
    if (check(candidate)) return candidate;
  }
  return null;
}
