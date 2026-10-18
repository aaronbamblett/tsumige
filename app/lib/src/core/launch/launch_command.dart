// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../host_platform.dart';
import '../model.dart';
import 'args.dart';
import 'env.dart';
import 'launch_modes.dart';

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

const _appImageVars = ['APPIMAGE', 'APPDIR', 'ARGV0', 'OWD'];

const _appDirPathVars = [
  'LD_LIBRARY_PATH',
  'LD_PRELOAD',
  'PATH',
  'XDG_DATA_DIRS',
  'GSETTINGS_SCHEMA_DIR',
  'QT_PLUGIN_PATH',
  'GDK_PIXBUF_MODULE_FILE',
  'PYTHONPATH',
];

/// The environment a launched game gets: the host's, minus the AppImage's own
/// variables when running from one, then the game's own variables.
Map<String, String> gameEnvironment(
  Map<String, String> hostEnv,
  Map<String, String> gameEnv, {
  required HostPlatform platform,
}) {
  final base = platform.inAppImage ? cleanAppImageEnv(hostEnv) : hostEnv;
  return {...base, ...gameEnv};
}

/// Drops the AppImage's variables and every path entry inside `$APPDIR`. A
/// path variable left with no entries is removed.
Map<String, String> cleanAppImageEnv(Map<String, String> hostEnv) {
  final cleaned = {...hostEnv}
    ..removeWhere((key, _) => _appImageVars.contains(key));
  final appDir = hostEnv['APPDIR'];
  if (appDir == null || appDir.isEmpty) return cleaned;
  final root = appDir.endsWith('/')
      ? appDir.substring(0, appDir.length - 1)
      : appDir;
  if (root.isEmpty) return cleaned;
  bool inside(String entry) => entry == root || entry.startsWith('$root/');
  for (final key in _appDirPathVars) {
    final value = cleaned[key];
    if (value == null) continue;
    final entries = value.split(':');
    final kept = entries.where((entry) => !inside(entry)).toList();
    if (kept.length == entries.length) continue;
    if (kept.isEmpty) {
      cleaned.remove(key);
    } else {
      cleaned[key] = kept.join(':');
    }
  }
  return cleaned;
}

String? _parentDir(String exe) {
  final dir = p.dirname(exe);
  if (dir == '.' || dir.isEmpty) return null;
  return dir;
}

/// Expands a leading `~/` with `HOME` so the default prefix pref
/// (`~/Games/tsumige/prefix`) resolves without a shell.
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
  HostPlatform? platform,
}) {
  final host = platform ?? HostPlatform.fromEnvironment(hostEnv);
  final mode = game.launch.mode ?? defaults.mode;
  final unavailable = launchModeUnavailableMessage(mode, host);
  if (unavailable != null) throw LaunchConfigError(unavailable);
  final extraEnv = parseEnv(game.launch.environment ?? '');
  final inFlatpak = host.inFlatpak;
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
    command = host.isMacOS
        ? LaunchCommand(
            executable: 'open',
            args: ['steam://rungameid/$appId'],
            env: extraEnv,
            workingDirectory: null,
          )
        : LaunchCommand(
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
        final isAppBundle = host.isMacOS && exe.endsWith('.app');
        command = LaunchCommand(
          executable: isAppBundle ? 'open' : exe,
          args: isAppBundle
              ? ['-W', '-n', exe, '--args', ...extraArgs]
              : extraArgs,
          env: extraEnv,
          workingDirectory: isAppBundle ? null : workingDirectory,
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
  HostPlatform? platform,
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
