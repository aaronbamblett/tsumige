// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:io';

import '../model.dart';
import '../paths.dart';
import 'launch_command.dart';
import 'log_files.dart';
import 'process_table.dart';
import 'session_recorder.dart';

/// A started game process. `exitCode` completes only after all output has
/// been appended to the log, so copying `latest.log` right after is safe.
abstract class StartedProcess {
  int get pid;
  Future<int> get exitCode;
}

/// Starts a [LaunchCommand] with its output appended to [log].
abstract class ProcessStarter {
  Future<StartedProcess> start(LaunchCommand command, File log);
}

class _IoStartedProcess implements StartedProcess {
  _IoStartedProcess(this.pid, this.exitCode);

  @override
  final int pid;

  @override
  final Future<int> exitCode;
}

class IoProcessStarter implements ProcessStarter {
  IoProcessStarter({Map<String, String>? hostEnv})
      : hostEnv = hostEnv ?? Platform.environment;

  final Map<String, String> hostEnv;

  @override
  Future<StartedProcess> start(LaunchCommand command, File log) async {
    final process = await Process.start(
      command.executable,
      command.args,
      workingDirectory: command.workingDirectory,
      environment: {...hostEnv, ...command.env},
      includeParentEnvironment: false,
      mode: ProcessStartMode.normal,
    );
    await log.parent.create(recursive: true);
    final sink = log.openWrite(mode: FileMode.append);
    final stdoutSub =
        process.stdout.listen(sink.add, onError: (_) {}, cancelOnError: false);
    final stderrSub =
        process.stderr.listen(sink.add, onError: (_) {}, cancelOnError: false);
    final done = () async {
      final code = await process.exitCode;
      try {
        await stdoutSub.asFuture<void>();
      } catch (_) {}
      try {
        await stderrSub.asFuture<void>();
      } catch (_) {}
      try {
        await sink.flush();
        await sink.close();
      } catch (_) {}
      return code;
    }();
    return _IoStartedProcess(process.pid, done);
  }
}

class LaunchResult {
  const LaunchResult({
    required this.logFile,
    required this.exitCode,
    required this.quickFailure,
    this.sessionSeconds,
  });

  final File logFile;
  final int exitCode;
  final bool quickFailure;
  final int? sessionSeconds;
}

class _SteamSession {
  _SteamSession(this.start, this.seconds);

  final DateTime start;
  final int seconds;
}

/// Runs games, logs every launch, and records a play session when the game
/// closes. Run-exe-in-prefix launches (`overrideExe != null`) never record
/// a session.
class GameRunner {
  GameRunner({
    required this.dir,
    required this.store,
    required this.starter,
    required this.processTable,
    Map<String, String>? hostEnv,
    DateTime Function()? clock,
    Future<void> Function(Duration)? sleep,
    this.steamPollInterval = const Duration(seconds: 5),
    this.steamAppearTimeout = const Duration(minutes: 3),
    this.quickFailWindow = const Duration(seconds: 5),
    this.heartbeatInterval = const Duration(seconds: 60),
  })  : hostEnv = hostEnv ?? Platform.environment,
        clock = clock ?? (() => DateTime.now().toUtc()),
        sleep = sleep ?? Future.delayed;

  final DataDir dir;
  final SessionStore store;
  final ProcessStarter starter;
  final ProcessTable processTable;
  final Map<String, String> hostEnv;
  final DateTime Function() clock;
  final Future<void> Function(Duration) sleep;
  final Duration steamPollInterval;
  final Duration steamAppearTimeout;
  final Duration quickFailWindow;
  final Duration heartbeatInterval;

  Future<LaunchResult> launch(
    Game game,
    LaunchDefaults defaults, {
    String? overrideExe,
    String? umuRunPath,
  }) async {
    final command = buildLaunchCommand(
      game,
      defaults,
      overrideExe: overrideExe,
      hostEnv: hostEnv,
      umuRunPath: umuRunPath,
    );
    final startedAt = clock();
    final logFile = newLaunchLog(dir, game, startedAt);
    final process = await starter.start(command, logFile);
    await writeRunningMarker(dir, game.id, startedAt, startedAt);
    final heartbeat =
        _RunningHeartbeat(dir, game.id, startedAt, clock, heartbeatInterval);
    try {
      if ((game.launch.mode ?? defaults.mode) == LaunchMode.steam) {
        // Timing `steam -applaunch` itself would be wrong: it exits at once.
        process.exitCode.then((_) {}, onError: (_) {});
        final session = await _steamSession(game.launch.steamAppId!);
        if (session != null) {
          await recordSession(store, game.id, session.start, session.seconds);
        }
        await updateLatestLog(dir, logFile);
        await deleteRunningMarker(dir, game.id);
        return LaunchResult(
          logFile: logFile,
          exitCode: 0,
          quickFailure: false,
          sessionSeconds: session?.seconds,
        );
      }
      final code = await process.exitCode;
      final elapsed = clock().difference(startedAt);
      var seconds = elapsed.inSeconds;
      if (seconds < 0) seconds = 0;
      int? recorded;
      if (overrideExe == null) {
        await recordSession(store, game.id, startedAt, seconds);
        recorded = seconds;
      }
      await updateLatestLog(dir, logFile);
      await deleteRunningMarker(dir, game.id);
      return LaunchResult(
        logFile: logFile,
        exitCode: code,
        quickFailure: code != 0 && elapsed < quickFailWindow,
        sessionSeconds: recorded,
      );
    } finally {
      await heartbeat.stop();
    }
  }

  /// Polls for a process with `SteamAppId=<id>`: the session starts when one
  /// first appears (up to 3 minutes) and ends when none remains.
  Future<_SteamSession?> _steamSession(int appId) async {
    DateTime? firstSeen;
    final deadline = clock().add(steamAppearTimeout);
    while (firstSeen == null) {
      final pids = await processTable.pidsWithEnv('SteamAppId', '$appId');
      if (pids.isNotEmpty) {
        firstSeen = clock();
        break;
      }
      if (!clock().isBefore(deadline)) return null;
      await sleep(steamPollInterval);
    }
    final start = firstSeen;
    while (true) {
      await sleep(steamPollInterval);
      final pids = await processTable.pidsWithEnv('SteamAppId', '$appId');
      if (pids.isEmpty) {
        var seconds = clock().difference(start).inSeconds;
        if (seconds < 0) seconds = 0;
        return _SteamSession(start, seconds);
      }
    }
  }

}

/// Refreshes the running marker's `last_seen` on a real-time [Timer], so a
/// fake test clock advancing the launch sleeps never perturbs it. Stopping
/// drains the in-flight write before the marker is deleted, so no late
/// heartbeat can resurrect it. If the app closes, the marker keeps the last
/// heartbeat and recovery turns it into a session on the next start.
class _RunningHeartbeat {
  _RunningHeartbeat(
      this.dir, this.gameId, this.startedAt, this.clock, this.interval) {
    _timer = Timer.periodic(interval, (_) => unawaited(_tick()));
  }

  final DataDir dir;
  final String gameId;
  final DateTime startedAt;
  final DateTime Function() clock;
  final Duration interval;
  late final Timer _timer;
  var _inFlight = 0;

  Future<void> _tick() async {
    _inFlight++;
    try {
      await writeRunningMarker(dir, gameId, startedAt, clock());
    } catch (_) {
    } finally {
      _inFlight--;
    }
  }

  Future<void> stop() async {
    _timer.cancel();
    while (_inFlight > 0) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }
}
