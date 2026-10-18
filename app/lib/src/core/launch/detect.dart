// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../host_platform.dart';

class WineRunner {
  const WineRunner({
    required this.name,
    required this.binary,
    required this.source,
  });

  final String name;
  final String binary;
  final String source;
}

class ProtonRunner {
  const ProtonRunner({required this.name, required this.path});

  final String name;
  final String path;
}

class SteamPrefix {
  const SteamPrefix({
    required this.appId,
    required this.gameName,
    required this.path,
  });

  final String appId;
  final String? gameName;
  final String path;
}

List<WineRunner> detectWineRunners(
  Map<String, String> hostEnv, {
  String fsRoot = '',
  HostPlatform? platform,
}) {
  if (!(platform ?? HostPlatform.fromEnvironment(hostEnv)).isLinux) {
    return <WineRunner>[];
  }
  final runners = <WineRunner>[];
  try {
    _addPathWineRunners(runners, hostEnv, fsRoot);
    final home = _hostHomeDir(hostEnv);
    if (home == null) return _sortedRunners(runners);
    const runnerDirs = [
      '.local/share/lutris/runners/wine',
      '.var/app/net.lutris.Lutris/data/lutris/runners/wine',
      '.local/share/bottles/runners',
      '.var/app/com.usebottles.bottles/data/bottles/runners',
    ];
    for (final dir in runnerDirs) {
      _addRunnersFromDirectory(
        runners,
        _under(fsRoot, home, dir),
        _isLutrisDir(dir) ? 'lutris' : 'bottles',
      );
    }
  } catch (_) {}
  return _sortedRunners(runners);
}

List<ProtonRunner> detectProtonRunners(
  Map<String, String> hostEnv, {
  String fsRoot = '',
  HostPlatform? platform,
}) {
  if (!(platform ?? HostPlatform.fromEnvironment(hostEnv)).isLinux) {
    return <ProtonRunner>[];
  }
  final runners = <ProtonRunner>[];
  try {
    final home = _hostHomeDir(hostEnv);
    if (home == null) return runners;
    const protonDirs = [
      '.local/share/Steam/compatibilitytools.d',
      '.steam/root/compatibilitytools.d',
      '.var/app/com.valvesoftware.Steam/data/Steam/compatibilitytools.d',
      '.steam/debian-installation/compatibilitytools.d',
      '.local/share/Steam/steamapps/common',
      '.steam/root/steamapps/common',
      '.steam/debian-installation/steamapps/common',
      '.var/app/com.valvesoftware.Steam/data/Steam/steamapps/common',
    ];
    for (final dir in protonDirs) {
      _addProtonRunnersFromDirectory(runners, _under(fsRoot, home, dir));
    }
  } catch (_) {}
  runners.sort(
    (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
  );
  return runners;
}

List<SteamPrefix> detectSteamPrefixes(
  Map<String, String> hostEnv, {
  String fsRoot = '',
  HostPlatform? platform,
}) {
  if (!(platform ?? HostPlatform.fromEnvironment(hostEnv)).isLinux) {
    return <SteamPrefix>[];
  }
  final prefixes = <SteamPrefix>[];
  try {
    final home = _hostHomeDir(hostEnv);
    if (home == null) return prefixes;
    const compatdataDirs = [
      '.local/share/Steam/steamapps/compatdata',
      '.steam/root/steamapps/compatdata',
      '.steam/debian-installation/steamapps/compatdata',
      '.var/app/com.valvesoftware.Steam/data/Steam/steamapps/compatdata',
    ];
    for (final dir in compatdataDirs) {
      _addSteamPrefixesFromDirectory(prefixes, _under(fsRoot, home, dir));
    }
  } catch (_) {}
  prefixes.sort((a, b) {
    if (a.gameName == null && b.gameName == null) {
      return a.appId.compareTo(b.appId);
    }
    if (a.gameName == null) return 1;
    if (b.gameName == null) return -1;
    final byName =
        a.gameName!.toLowerCase().compareTo(b.gameName!.toLowerCase());
    if (byName != 0) return byName;
    return a.appId.compareTo(b.appId);
  });
  return prefixes;
}

bool _isLutrisDir(String relativeDir) => relativeDir.contains('lutris');

String _under(String fsRoot, String home, String relativeDir) {
  final absolute = p.join(home, relativeDir);
  if (fsRoot.isEmpty) return absolute;
  final relative = p.relative(absolute, from: '/');
  return p.join(fsRoot, relative);
}

String _rooted(String fsRoot, String absolutePath) {
  if (fsRoot.isEmpty) return absolutePath;
  return p.join(fsRoot, p.relative(absolutePath, from: '/'));
}

String _realKey(String path) {
  try {
    return File(path).resolveSymbolicLinksSync();
  } catch (_) {
    return p.normalize(path);
  }
}

String? _hostHomeDir(Map<String, String> hostEnv) {
  if (!hostEnv.containsKey('FLATPAK_ID')) {
    final home = hostEnv['HOME'];
    if (home == null || home.isEmpty) return null;
    return home;
  }
  try {
    final result = Process.runSync('flatpak-spawn', [
      '--host',
      'sh',
      '-c',
      'printf %s "\$HOME"',
    ]);
    if (result.exitCode != 0) return null;
    final home = (result.stdout as String).trim();
    if (home.isEmpty) return null;
    return home;
  } catch (_) {
    return null;
  }
}

void _addRunnersFromDirectory(
  List<WineRunner> runners,
  String directory,
  String source,
) {
  List<FileSystemEntity> entries;
  try {
    entries = Directory(directory).listSync(followLinks: false);
  } catch (_) {
    return;
  }
  for (final entry in entries) {
    try {
      final binary = p.join(entry.path, 'bin', 'wine');
      if (!File(binary).existsSync()) continue;
      final name = p.basename(entry.path);
      if (name.isEmpty) continue;
      final runner = WineRunner(name: name, binary: binary, source: source);
      if (_runnerMissing(runners, binary)) runners.add(runner);
    } catch (_) {}
  }
}

bool _runnerMissing(List<WineRunner> runners, String binary) {
  final key = _realKey(binary);
  return !runners.any((existing) => _realKey(existing.binary) == key);
}

void _addPathWineRunners(
  List<WineRunner> runners,
  Map<String, String> hostEnv,
  String fsRoot,
) {
  final pathValue = hostEnv['PATH'];
  if (pathValue == null || pathValue.isEmpty) return;
  for (final directory in pathValue.split(':')) {
    if (directory.isEmpty) continue;
    for (final binaryName in ['wine', 'wine64']) {
      try {
        final binary = _rooted(fsRoot, p.join(directory, binaryName));
        if (!File(binary).existsSync()) continue;
        if (_runnerMissing(runners, binary)) {
          runners.add(
            WineRunner(
              name: 'System $binaryName',
              binary: binary,
              source: 'path',
            ),
          );
        }
      } catch (_) {}
    }
  }
}

List<WineRunner> _sortedRunners(List<WineRunner> runners) {
  runners.sort(
    (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
  );
  return runners;
}

void _addProtonRunnersFromDirectory(
  List<ProtonRunner> runners,
  String directory,
) {
  List<FileSystemEntity> entries;
  try {
    entries = Directory(directory).listSync(followLinks: false);
  } catch (_) {
    return;
  }
  for (final entry in entries) {
    try {
      if (!File(p.join(entry.path, 'proton')).existsSync()) continue;
      final name = p.basename(entry.path);
      if (name.isEmpty) continue;
      final key = _realKey(entry.path);
      if (runners.any((existing) => _realKey(existing.path) == key)) continue;
      runners.add(ProtonRunner(name: name, path: entry.path));
    } catch (_) {}
  }
}

void _addSteamPrefixesFromDirectory(
  List<SteamPrefix> prefixes,
  String directory,
) {
  List<FileSystemEntity> entries;
  try {
    entries = Directory(directory).listSync(followLinks: false);
  } catch (_) {
    return;
  }
  for (final entry in entries) {
    try {
      final prefixPath = p.join(entry.path, 'pfx');
      if (!Directory(prefixPath).existsSync()) continue;
      final appId = p.basename(entry.path);
      if (appId.isEmpty) continue;
      if (prefixes.any((existing) => existing.appId == appId)) continue;
      final key = _realKey(prefixPath);
      if (prefixes.any((existing) => _realKey(existing.path) == key)) {
        continue;
      }
      prefixes.add(
        SteamPrefix(
          appId: appId,
          gameName: _steamGameName(entry.path, appId),
          path: prefixPath,
        ),
      );
    } catch (_) {}
  }
}

String? _steamGameName(String compatdataDir, String appId) {
  try {
    final grandparent = p.dirname(p.dirname(compatdataDir));
    final manifest = File(
      p.join(grandparent, 'appmanifest_$appId.acf'),
    ).readAsStringSync();
    for (final line in manifest.split('\n')) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('"name"')) continue;
      final parts = trimmed.split('"');
      if (parts.length > 3) return parts[3];
      return null;
    }
    return null;
  } catch (_) {
    return null;
  }
}
