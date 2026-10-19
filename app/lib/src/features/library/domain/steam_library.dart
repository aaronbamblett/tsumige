// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/host_platform.dart';
import '../../../core/launch/steam_registry.dart';
import '../../../core/paths.dart';
import '../../../core/vndb.dart';
import 'folder_import.dart';

/// A game Steam has installed on this computer.
class InstalledSteamGame {
  const InstalledSteamGame({
    required this.appId,
    required this.name,
    required this.installDir,
  });

  final int appId;
  final String name;
  final String installDir;
}

/// Steam's own tools, never games. Matched by app id or by name prefix, so
/// a renamed Proton build or a new runtime still filters out.
const steamToolAppIds = <int>{
  228980, // Steamworks Common Redistributables
};

const steamToolNamePrefixes = <String>[
  'Proton',
  'Steam Linux Runtime',
  'Steamworks Common',
];

bool isSteamTool({required int appId, required String name}) {
  if (steamToolAppIds.contains(appId)) return true;
  return steamToolNamePrefixes.any(name.startsWith);
}

/// Matches an installed Steam game on VNDB: first by its Steam App ID
/// through the release extlink, which maps exactly, then by its Steam name
/// with the same title matching the folder import uses (matched, check or
/// none). A failing App ID lookup falls through to the name search; a
/// failure with no check match rethrows from [lookupFolderMatch].
Future<FolderMatch> lookupSteamMatch({
  required InstalledSteamGame game,
  required Future<VnSearchResult?> Function(int appId) fetchByAppId,
  required Future<List<VnSearchResult>> Function(String query) search,
}) async {
  try {
    final vn = await fetchByAppId(game.appId);
    if (vn != null) return FolderMatch(ImportMatchState.matched, vn);
  } catch (_) {}
  return lookupFolderMatch(
    query: cleanFolderName(game.name),
    parentQueries: const [],
    search: search,
  );
}

p.Context _contextFor(HostPlatform platform) => p.Context(
  style: platform.isWindows ? p.Style.windows : p.Style.posix,
);

bool _dirExists(String path) {
  try {
    return Directory(path).existsSync();
  } catch (_) {
    return false;
  }
}

String? _readFile(String path) {
  try {
    return File(path).readAsStringSync();
  } catch (_) {
    return null;
  }
}

List<String> _listDir(String dir) {
  try {
    return [
      for (final entry in Directory(
        dir,
      ).listSync(followLinks: false))
        entry.path,
    ];
  } catch (_) {
    return const [];
  }
}

/// The Steam installs on this computer: the roots whose directory exists,
/// deduplicated by real path (on Linux `~/.steam/steam` is usually a link
/// to `~/.local/share/Steam`). Uses `$HOME`, never `~`.
Future<List<String>> steamRoots(
  HostPlatform platform, {
  Map<String, String>? env,
  bool Function(String path)? dirExists,
  String Function(String path)? resolvePath,
  Future<String?> Function()? readWindowsSteamPath,
}) async {
  final environment = env ?? Platform.environment;
  final exists = dirExists ?? _dirExists;
  final resolve = resolvePath ?? realPath;
  final context = _contextFor(platform);
  final candidates = <String>[];
  if (platform.isWindows) {
    final fromRegistry = await (readWindowsSteamPath ??
        readWindowsSteamPathFromRegistry)();
    candidates.add(
      fromRegistry != null && fromRegistry.isNotEmpty
          ? fromRegistry
          : r'C:\Program Files (x86)\Steam',
    );
  } else {
    final home = environment['HOME'] ?? '';
    if (home.isEmpty) return const [];
    if (platform.isMacOS) {
      candidates.add(
        context.join(home, 'Library', 'Application Support', 'Steam'),
      );
    } else {
      candidates.addAll([
        context.join(home, '.steam', 'steam'),
        context.join(home, '.local', 'share', 'Steam'),
        context.join(
          home,
          '.var',
          'app',
          'com.valvesoftware.Steam',
          '.local',
          'share',
          'Steam',
        ),
      ]);
    }
  }
  final roots = <String>[];
  final seen = <String>{};
  for (final candidate in candidates) {
    if (!exists(candidate)) continue;
    if (!seen.add(resolve(candidate))) continue;
    roots.add(candidate);
  }
  return roots;
}

/// The `"path"` values in a `libraryfolders.vdf`, backslash escapes undone.
List<String> parseLibraryFoldersVdf(String text) {
  final paths = <String>[];
  for (final match in RegExp(
    r'"path"\s+"((?:[^"\\]|\\.)*)"',
  ).allMatches(text)) {
    paths.add(_unescapeVdf(match.group(1)!));
  }
  return paths;
}

String _unescapeVdf(String value) =>
    value.replaceAllMapped(RegExp(r'\\(.)'), (m) => m.group(1)!);

/// The fields an `appmanifest_<appid>.acf` holds: the app id, the display
/// name, the folder under `steamapps/common` (empty when the manifest has
/// none) and the StateFlags (0 when the manifest has none). Null when the
/// app id or the name is missing.
({int appId, String name, String installDir, int stateFlags})?
parseAppManifest(String text) {
  final values = <String, String>{};
  for (final match in RegExp(
    r'"([^"]+)"\s+"((?:[^"\\]|\\.)*)"',
  ).allMatches(text)) {
    values[match.group(1)!] = _unescapeVdf(match.group(2)!);
  }
  final appId = int.tryParse(values['appid'] ?? '');
  final name = values['name'] ?? '';
  if (appId == null || name.isEmpty) return null;
  return (
    appId: appId,
    name: name,
    installDir: values['installdir'] ?? '',
    stateFlags: int.tryParse(values['StateFlags'] ?? '') ?? 0,
  );
}

/// Every installed game under every Steam root: each root itself is a
/// library, plus the libraries its `libraryfolders.vdf` lists. Tools are
/// skipped, manifests that are not fully installed (StateFlags without the
/// installed bit) are skipped, and games are deduplicated by app id.
Future<List<InstalledSteamGame>> installedSteamGames(
  HostPlatform platform, {
  Map<String, String>? env,
  bool Function(String path)? dirExists,
  String Function(String path)? resolvePath,
  Future<String?> Function()? readWindowsSteamPath,
  String? Function(String path)? readFile,
  List<String> Function(String dir)? listDir,
}) async {
  final read = readFile ?? _readFile;
  final list = listDir ?? _listDir;
  final context = _contextFor(platform);
  final roots = await steamRoots(
    platform,
    env: env,
    dirExists: dirExists,
    resolvePath: resolvePath,
    readWindowsSteamPath: readWindowsSteamPath,
  );
  final games = <InstalledSteamGame>[];
  final seen = <int>{};
  for (final root in roots) {
    final libraries = <String>[root];
    final foldersText = read(
      context.join(root, 'steamapps', 'libraryfolders.vdf'),
    );
    if (foldersText != null) {
      libraries.addAll(parseLibraryFoldersVdf(foldersText));
    }
    for (final library in libraries) {
      for (final entry in list(context.join(library, 'steamapps'))) {
        final fileName = context.basename(entry);
        final manifest = RegExp(r'^appmanifest_(\d+)\.acf$').firstMatch(
          fileName,
        );
        if (manifest == null) continue;
        final text = read(entry);
        if (text == null) continue;
        final parsed = parseAppManifest(text);
        if (parsed == null || parsed.installDir.isEmpty) continue;
        if (parsed.stateFlags != 0 && (parsed.stateFlags & 4) == 0) continue;
        if (isSteamTool(appId: parsed.appId, name: parsed.name)) continue;
        if (!seen.add(parsed.appId)) continue;
        games.add(
          InstalledSteamGame(
            appId: parsed.appId,
            name: parsed.name,
            installDir: context.join(
              library,
              'steamapps',
              'common',
              parsed.installDir,
            ),
          ),
        );
      }
    }
  }
  games.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return games;
}
