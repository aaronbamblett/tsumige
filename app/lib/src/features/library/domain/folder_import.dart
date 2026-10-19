// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../../../core/host_platform.dart';
import '../../../core/model.dart';
import '../../../core/paths.dart';
import '../../../core/vndb.dart';

/// One .exe found under a candidate folder.
class ExeFile {
  const ExeFile({
    required this.path,
    required this.relative,
    required this.size,
    required this.topLevel,
  });

  final String path;
  final String relative;
  final int size;
  final bool topLevel;

  String get stem => p.basenameWithoutExtension(path);
}

/// A direct subfolder of the folder being imported: one candidate game.
class ImportFolder {
  const ImportFolder({
    required this.name,
    required this.path,
    required this.exes,
    this.skipped = const [],
  });

  final String name;
  final String path;

  /// Every candidate launchable, in scan order. Empty when none was found.
  final List<ExeFile> exes;

  /// Relative paths of launchables dropped as installers, uninstallers and
  /// other junk.
  final List<String> skipped;
}

enum ImportMatchState { matched, check, none, error }

class FolderMatch {
  const FolderMatch(this.state, this.vn);

  final ImportMatchState state;

  /// The VNDB entry to use: the match when [state] is matched, the best
  /// candidate for a check, and null when there is no match.
  final VnSearchResult? vn;
}

const _excludedDirs = {'_commonredist', 'redist', 'directx', '__macosx'};

const _excludedNamePatterns = [
  'unins*',
  'uninstall*',
  'setup*',
  'config*',
  'settings*',
  '*cfg*',
  'vcredist*',
  'dxsetup*',
  'dxwebsetup*',
  'directx*',
  '*crash*',
  '*update*',
  'notification_helper',
  'unitycrashhandler*',
  'lec*',
  'leproc*',
];

final _excludedNames = [
  for (final pattern in _excludedNamePatterns)
    RegExp('^${pattern.split('*').map(RegExp.escape).join('.*')}\$'),
];

/// The deepest folder level, below the picked folder, that is searched for
/// games. Direct subfolders are level 1.
const _maxGameDepth = 3;

/// The game in [path] as a single folder: its launch candidates and the
/// junk that was skipped.
Future<ImportFolder> scanGameFolder(String path, HostPlatform platform) =>
    _importFolder(path, platform);

/// Subfolders named like these hold a game's binaries or one language build,
/// so the game is the folder above them. `game` is not listed: a folder named
/// Game is itself a game, as in `Studio/Game/Game.exe`.
const _genericFolderNames = {
  'bin',
  'bin32',
  'bin64',
  'x64',
  'x86',
  'win32',
  'win64',
  'windows',
  'binaries',
  'binary',
  'exe',
  'program',
  'app',
  'data',
  'system',
  'release',
  'launcher',
  'jp',
  'ja',
  'en',
  'eng',
};

/// The games under [root]. When [root] itself holds a launchable it is the
/// only game. Otherwise each folder holding a launchable (an exe dir) is
/// walked up to its game folder: past generic subfolders, never above [root].
/// Exe dirs nested inside another exe dir belong to that game.
Future<List<ImportFolder>> scanImportFolder(
  String rootPath,
  HostPlatform platform,
) async {
  final root = p.normalize(rootPath);
  if (await _holdsLaunchable(root, platform)) {
    return [await _importFolder(root, platform)];
  }
  final exeDirs = await _launchableFolders(root, 0, platform);
  final exeDirSet = exeDirs.toSet();
  final games = <String>{
    for (final dir in exeDirs)
      if (!_hasExeDirAbove(dir, exeDirSet, root)) _gameFolder(dir, root),
  };
  final folders = <ImportFolder>[
    for (final game in games) await _importFolder(game, platform),
  ];
  folders.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return folders;
}

/// How many distinct games sit under [rootPath]: 0, 1, or 2, where 2 means
/// two or more. Used to decide whether a picked or dropped folder is one
/// game or an import root, without the full [scanImportFolder] pass.
///
/// Shares the full scan's rules: a root holding a launchable is the only
/// game, exe dirs walk up past generic subfolders via [_gameFolder], and
/// exe dirs nested inside another exe dir belong to that game. The walk is
/// top-down, so ancestors are always known before their children, and it
/// returns as soon as a second distinct game is found instead of reading
/// the rest of the tree. Async with one directory listing at a time, so it
/// never blocks on a synchronous recursive walk.
///
/// [listSubfolders] and [holdsLaunchable] are seams for tests; they default
/// to [_subfolders] and [_holdsLaunchable].
Future<int> countImportGames(
  String rootPath,
  HostPlatform platform, {
  Future<List<String>> Function(String dir)? listSubfolders,
  Future<bool> Function(String dir)? holdsLaunchable,
}) async {
  final root = p.normalize(rootPath);
  final subs = listSubfolders ?? _subfolders;
  final holds =
      holdsLaunchable ?? (String dir) => _holdsLaunchable(dir, platform);
  if (await holds(root)) return 1;
  final exeDirs = <String>{};
  final games = <String>{};
  var frontier = [root];
  for (var depth = 0; depth < _maxGameDepth; depth++) {
    final next = <String>[];
    for (final folder in frontier) {
      for (final sub in await subs(folder)) {
        if (await holds(sub)) {
          exeDirs.add(sub);
          if (!_hasExeDirAbove(sub, exeDirs, root)) {
            games.add(_gameFolder(sub, root));
            if (games.length >= 2) return 2;
          }
        }
        next.add(sub);
      }
    }
    frontier = next;
    if (frontier.isEmpty) return games.length;
  }
  return games.length;
}

String _gameFolder(String exeDir, String root) {
  var game = exeDir;
  while (game != root &&
      _genericFolderNames.contains(p.basename(game).toLowerCase())) {
    game = p.dirname(game);
  }
  return game;
}

bool _hasExeDirAbove(String dir, Set<String> exeDirs, String root) {
  for (
    var parent = p.dirname(dir);
    p.isWithin(root, parent);
    parent = p.dirname(parent)
  ) {
    if (exeDirs.contains(parent)) return true;
  }
  return false;
}

/// The folders beneath [dir], at most [_maxGameDepth] levels below the picked
/// folder, that directly hold a launchable.
Future<List<String>> _launchableFolders(
  String dir,
  int level,
  HostPlatform platform,
) async {
  final found = <String>[];
  var frontier = [dir];
  for (var depth = level; depth < _maxGameDepth; depth++) {
    final next = <String>[];
    for (final folder in frontier) {
      for (final sub in await _subfolders(folder)) {
        if (await _holdsLaunchable(sub, platform)) found.add(sub);
        next.add(sub);
      }
    }
    frontier = next;
  }
  return found;
}

Future<List<String>> _subfolders(String dir) async {
  final List<FileSystemEntity> entries;
  try {
    entries = await Directory(dir).list().toList();
  } on FileSystemException {
    return const [];
  }
  final names = <String>[
    for (final entry in entries)
      if (entry is Directory &&
          !p.basename(entry.path).startsWith('.') &&
          !_excludedDirs.contains(p.basename(entry.path).toLowerCase()))
        entry.path,
  ];
  names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return names;
}

/// Whether [dir] directly holds a launchable that isn't junk.
Future<bool> _holdsLaunchable(String dir, HostPlatform platform) async {
  final List<FileSystemEntity> entries;
  try {
    entries = await Directory(dir).list().toList();
  } on FileSystemException {
    return false;
  }
  for (final entry in entries) {
    final stem = p.basenameWithoutExtension(entry.path).toLowerCase();
    if (_excludedNames.any((re) => re.hasMatch(stem))) continue;
    if (await _isLaunchable(entry, platform)) return true;
  }
  return false;
}

Future<ImportFolder> _importFolder(String path, HostPlatform platform) async {
  final found = await _findExes(path, platform);
  return ImportFolder(
    name: p.basename(path),
    path: path,
    exes: found.exes,
    skipped: found.skipped,
  );
}

const _nativeExtensions = {'', '.x86', '.x86_64', '.bin', '.run'};

/// Whether [entity] is something a game launches from on [platform]: an
/// .exe on Linux and Windows, a .app bundle on macOS, a .sh on Linux and
/// macOS, an .AppImage on Linux, a .command on macOS, or a native binary
/// recognised by its magic bytes.
Future<bool> _isLaunchable(
  FileSystemEntity entity,
  HostPlatform platform,
) async {
  final ext = p.extension(entity.path).toLowerCase();
  if (entity is Directory) return platform.isMacOS && ext == '.app';
  if (entity is! File) return false;
  if (ext == '.exe') return !platform.isMacOS;
  if (ext == '.sh') return !platform.isWindows;
  if (ext == '.appimage') return platform.isLinux;
  if (ext == '.command') return platform.isMacOS;
  if (!_nativeExtensions.contains(ext)) return false;
  return isNativeBinary(entity.path, platform);
}

/// Whether the file at [path] is an ELF binary on Linux or a Mach-O binary on
/// macOS, by its first four bytes.
Future<bool> isNativeBinary(String path, HostPlatform platform) async {
  final List<int> head;
  try {
    final file = await File(path).open();
    try {
      head = await file.read(4);
    } finally {
      await file.close();
    }
  } on FileSystemException {
    return false;
  }
  if (platform.isLinux) {
    return _startsWith(head, const [0x7f, 0x45, 0x4c, 0x46]);
  }
  if (platform.isMacOS) {
    return _startsWith(head, const [0xfe, 0xed, 0xfa, 0xce]) ||
        _startsWith(head, const [0xfe, 0xed, 0xfa, 0xcf]) ||
        _startsWith(head, const [0xce, 0xfa, 0xed, 0xfe]) ||
        _startsWith(head, const [0xcf, 0xfa, 0xed, 0xfe]) ||
        _startsWith(head, const [0xca, 0xfe, 0xba, 0xbe]);
  }
  return false;
}

bool _startsWith(List<int> head, List<int> magic) =>
    head.length >= magic.length &&
    [for (var i = 0; i < magic.length; i++) head[i] == magic[i]]
        .every((same) => same);

Future<({List<ExeFile> exes, List<String> skipped})> _findExes(
  String folder,
  HostPlatform platform,
) async {
  final found = <ExeFile>[];

  Future<void> walk(String dir, int depth) async {
    final List<FileSystemEntity> entries;
    try {
      entries = await Directory(dir).list().toList();
    } on FileSystemException {
      return;
    }
    entries.sort((a, b) => a.path.compareTo(b.path));
    final subdirs = <String>[];
    for (final entry in entries) {
      final name = p.basename(entry.path);
      if (entry is Directory && !_isBundle(entry, platform)) {
        if (depth < _maxGameDepth &&
            !_excludedDirs.contains(name.toLowerCase())) {
          subdirs.add(entry.path);
        }
        continue;
      }
      if (!await _isLaunchable(entry, platform)) continue;
      found.add(
        ExeFile(
          path: entry.path,
          relative: p.relative(entry.path, from: folder),
          size: entry is File ? await entry.length() : 0,
          topLevel: dir == folder,
        ),
      );
    }
    for (final subdir in subdirs) {
      await walk(subdir, depth + 1);
    }
  }

  await walk(folder, 0);
  final skipped = [
    for (final exe in found)
      if (_isJunk(exe.path)) exe.relative,
  ];
  return (exes: _candidates(found), skipped: skipped);
}

bool _isBundle(FileSystemEntity entry, HostPlatform platform) =>
    entry is Directory &&
    platform.isMacOS &&
    p.extension(entry.path).toLowerCase() == '.app';

bool _isJunk(String path) {
  final stem = p.basenameWithoutExtension(path).toLowerCase();
  return _excludedNames.any((re) => re.hasMatch(stem));
}

List<ExeFile> _candidates(List<ExeFile> found) {
  var candidates = [
    for (final exe in found)
      if (!_isJunk(exe.path)) exe,
  ];
  final nonpatch = [
    for (final exe in candidates)
      if (!exe.stem.toLowerCase().contains('patch')) exe,
  ];
  candidates = nonpatch.isNotEmpty
      ? nonpatch
      : (found.length == 1 ? candidates : const <ExeFile>[]);
  final nonlauncher = [
    for (final exe in candidates)
      if (!exe.stem.toLowerCase().contains('launcher')) exe,
  ];
  return nonlauncher.isNotEmpty ? nonlauncher : candidates;
}

/// The library game that picking [exe] would duplicate: one whose resolved
/// executable is the same file, or — when [folder] (the game folder the
/// pick belongs to) holds one — the first such game. Null when it is new.
Game? duplicateLibraryGame({
  required String exe,
  required String? folder,
  required Iterable<Game> games,
}) {
  if (exe.isEmpty) return null;
  final realExe = realPath(exe);
  final realFolder = folder == null || folder.isEmpty ? null : realPath(folder);
  Game? folderHit;
  for (final game in games) {
    final stored = game.launch.executable;
    if (stored == null || stored.isEmpty) continue;
    final realStored = realPath(stored);
    if (p.equals(realStored, realExe)) return game;
    if (folderHit == null &&
        realFolder != null &&
        (p.equals(realStored, realFolder) ||
            p.isWithin(realFolder, realStored))) {
      folderHit = game;
    }
  }
  return folderHit;
}

/// The exe to launch for [folder]: top-level first, then the best title
/// similarity to the folder name or [titles], then the largest file.
ExeFile? chooseExe(ImportFolder folder, Iterable<String> titles) {
  final names = [folder.name, ...titles];
  ExeFile? best;
  (bool, double, int)? bestKey;
  for (final exe in folder.exes) {
    final key = (
      exe.topLevel,
      names.map((n) => similarity(exe.stem, n)).fold(0.0, math.max),
      exe.size,
    );
    if (bestKey == null || _keyBeats(key, bestKey)) {
      best = exe;
      bestKey = key;
    }
  }
  return best;
}

bool _keyBeats((bool, double, int) a, (bool, double, int) b) {
  if (a.$1 != b.$1) return a.$1;
  if (a.$2 != b.$2) return a.$2 > b.$2;
  return a.$3 > b.$3;
}

/// The resolved executable paths of [games], skipping empty ones. Computed
/// once per scan so import rows each compare against the set.
Set<String> libraryRealExePaths(Iterable<Game> games) => {
  for (final game in games)
    if (game.launch.executable != null &&
        game.launch.executable!.isNotEmpty)
      realPath(game.launch.executable!),
};

/// Whether the import row for a folder whose resolved path is [realFolder] is
/// already in the library: a library game's resolved executable is that
/// folder or inside it (so the same game picked through a different link, or
/// through a different `.exe` in the same folder, still matches). A matching
/// VNDB id alone only warns, it doesn't count as imported.
bool importRowInLibrary({
  required String realFolder,
  required Set<String> libraryExes,
}) {
  if (libraryExes.isEmpty) return false;
  return libraryExes.any(
    (exe) => p.equals(exe, realFolder) || p.isWithin(realFolder, exe),
  );
}

const _accentFolds = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'ç': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ñ': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ø': 'o',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ý': 'y',
  'ÿ': 'y',
};

final _accentPattern = RegExp('[${_accentFolds.keys.join()}]');

/// Lowercases, folds Latin-1 accents, turns punctuation into spaces and
/// collapses whitespace.
String normalise(String value) {
  final folded = value.toLowerCase().replaceAllMapped(
    _accentPattern,
    (m) => _accentFolds[m[0]]!,
  );
  final cleaned = folded.replaceAll(
    RegExp(r'[^\p{L}\p{N}\s]', unicode: true),
    ' ',
  );
  return cleaned.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).join(' ');
}

/// Every title a VNDB entry is known by, skipping empty ones.
List<String> vnTitles(VnSearchResult vn) => [
  vn.title,
  if (vn.alttitle != null) vn.alttitle!,
  ...vn.titles,
  ...vn.aliases,
].where((t) => t.isNotEmpty).toList();

/// Similarity of a folder name to a title, from 0 to 1. Equal once spaces
/// are removed scores 1. A whole-word run of one inside the other, or one
/// space-stripped form a prefix of the other, scores at least 0.85.
double similarity(String folder, String title) {
  final a = normalise(folder);
  final b = normalise(title);
  if (a == b) return 1.0;
  final sa = a.replaceAll(' ', '');
  final sb = b.replaceAll(' ', '');
  if (sa.isNotEmpty && sa == sb) return 1.0;
  var ratio = sequenceRatio(a, b);
  if (a.isNotEmpty && b.isNotEmpty) {
    if ((' $b ').contains(' $a ') || (' $a ').contains(' $b ')) {
      ratio = math.max(ratio, _containmentScore(a, b));
    } else if (sa.isNotEmpty &&
        sa.length < sb.length &&
        sb.startsWith(sa) &&
        _endsAtWordBoundary(b, sa.length)) {
      ratio = math.max(ratio, _containmentScore(sa, sb));
    }
  }
  return ratio;
}

/// Whether the first [length] non-space characters of [spaced] end a word,
/// so that `GameB` does not count as the start of `GameBook`.
bool _endsAtWordBoundary(String spaced, int length) {
  var seen = 0;
  for (var i = 0; i < spaced.length; i++) {
    if (spaced[i] == ' ') continue;
    seen++;
    if (seen == length) {
      return i + 1 == spaced.length || spaced[i + 1] == ' ';
    }
  }
  return false;
}

double _containmentScore(String x, String y) {
  final shorter = math.min(x.runes.length, y.runes.length);
  final longer = math.max(x.runes.length, y.runes.length);
  return 0.85 + 0.14 * shorter / longer;
}

/// Ratcliff/Obershelp similarity, as Python's `difflib.SequenceMatcher`
/// `ratio()` without junk heuristics: 2 * matched characters / total.
double sequenceRatio(String a, String b) {
  final x = a.runes.toList();
  final y = b.runes.toList();
  final total = x.length + y.length;
  if (total == 0) return 1.0;
  return 2 * _matchedCount(x, y, 0, x.length, 0, y.length) / total;
}

int _matchedCount(
  List<int> a,
  List<int> b,
  int alo,
  int ahi,
  int blo,
  int bhi,
) {
  final m = _longestMatch(a, b, alo, ahi, blo, bhi);
  if (m.size == 0) return 0;
  return m.size +
      _matchedCount(a, b, alo, m.i, blo, m.j) +
      _matchedCount(a, b, m.i + m.size, ahi, m.j + m.size, bhi);
}

({int i, int j, int size}) _longestMatch(
  List<int> a,
  List<int> b,
  int alo,
  int ahi,
  int blo,
  int bhi,
) {
  var bestI = alo;
  var bestJ = blo;
  var bestSize = 0;
  var previous = <int, int>{};
  for (var i = alo; i < ahi; i++) {
    final current = <int, int>{};
    for (var j = blo; j < bhi; j++) {
      if (a[i] != b[j]) continue;
      final size = current[j] = (previous[j - 1] ?? 0) + 1;
      if (size > bestSize) {
        bestI = i - size + 1;
        bestJ = j - size + 1;
        bestSize = size;
      }
    }
    previous = current;
  }
  return (i: bestI, j: bestJ, size: bestSize);
}

/// Picks the VNDB entry for [folder] from its search [results]. A unique
/// exact title, or a clear lead of 0.10 at 0.78 or better, is a match. A
/// score of 0.65 or better, or a tie at 1.0, is a check.
FolderMatch matchFolder(String folder, List<VnSearchResult> results) {
  if (results.isEmpty) return const FolderMatch(ImportMatchState.none, null);
  final ranked =
      <({double score, VnSearchResult vn, int index})>[
        for (var i = 0; i < results.length; i++)
          (
            score: vnTitles(results[i])
                .map((t) => similarity(folder, t))
                .fold(0.0, math.max),
            vn: results[i],
            index: i,
          ),
      ]..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        return byScore != 0 ? byScore : a.index.compareTo(b.index);
      });
  final top = ranked.first;
  final second = ranked.length > 1 ? ranked[1].score : 0.0;
  if (top.score == 1) {
    return FolderMatch(
      second == 1 ? ImportMatchState.check : ImportMatchState.matched,
      top.vn,
    );
  }
  if (top.score >= 0.78 && top.score - second >= 0.10) {
    return FolderMatch(ImportMatchState.matched, top.vn);
  }
  if (top.score >= 0.65) return FolderMatch(ImportMatchState.check, top.vn);
  return const FolderMatch(ImportMatchState.none, null);
}

/// The folder name as a VNDB search: bracketed tags, a version number and
/// punctuation removed, and hyphens and underscores read as spaces.
String cleanFolderName(String folder) {
  final unbracketed = folder.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
  final spaced = unbracketed.replaceAll(RegExp(r'[_-]'), ' ');
  final unversioned = spaced.replaceAll(
    RegExp(r'\b(ver\.?\s*)?v?\d+(\.\d+)+[a-z]?\b', caseSensitive: false),
    ' ',
  );
  final unpunctuated = unversioned.replaceAll(
    RegExp(r'[^\p{L}\p{N}\s]', unicode: true),
    '',
  );
  return unpunctuated
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .join(' ');
}

/// The folder name with any subtitle or trailing words dropped, for a retry
/// when the full name finds nothing. Null when there is nothing shorter.
String? shortenedQuery(String folder) {
  var shortened = folder.trim().split(RegExp(r' - |:')).first.trim();
  if (shortened == folder) {
    final words = folder.trim().split(RegExp(r'\s+'));
    final keep = words.length > 3
        ? words.length - 2
        : math.max(words.length - 1, 0);
    shortened = words.take(keep).join(' ');
  }
  return shortened.isNotEmpty && shortened != folder ? shortened : null;
}

/// Searches VNDB for [folder], retrying once with [shortenedQuery] only when
/// the first search returns nothing.
Future<List<VnSearchResult>> lookupFolder(
  String folder,
  Future<List<VnSearchResult>> Function(String query) search,
) async {
  final results = await search(folder);
  if (results.isNotEmpty) return results;
  final shortened = shortenedQuery(folder);
  return shortened == null ? results : search(shortened);
}

/// Splits CamelCase at lower-to-Upper boundaries: `MakingLovers` becomes
/// `Making Lovers`. Null when there is no such boundary, so `KANADE`
/// stays whole.
String? splitCamelQuery(String query) {
  final split = query
      .replaceAllMapped(RegExp('(?<=[a-z])(?=[A-Z])'), (_) => ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .join(' ');
  return split == query || split.isEmpty ? null : split;
}

const _languageTags = {
  'japanese',
  'english',
  'eng',
  'jpn',
  'jp',
  'en',
};

/// Drops a trailing language tag (`ENG`, `EN`, `JP`, `JPN`, `English` or
/// `Japanese`): as a separate word, or as a CamelCase suffix as in
/// `PhantomENG`, which becomes `Phantom`. Null when there is none.
String? stripLanguageTag(String query) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return null;
  final words = trimmed.split(RegExp(r'\s+'));
  if (words.length > 1) {
    if (_languageTags.contains(words.last.toLowerCase())) {
      return words.sublist(0, words.length - 1).join(' ');
    }
    return null;
  }
  final word = words.single;
  final lower = word.toLowerCase();
  for (final tag in _languageTags) {
    if (word.length > tag.length &&
        lower.endsWith(tag) &&
        _isAsciiLower(word[word.length - tag.length - 1]) &&
        _isAsciiUpper(word[word.length - tag.length])) {
      return word.substring(0, word.length - tag.length);
    }
  }
  return null;
}

bool _isAsciiLower(String char) {
  final code = char.codeUnitAt(0);
  return code >= 0x61 && code <= 0x7a;
}

bool _isAsciiUpper(String char) {
  final code = char.codeUnitAt(0);
  return code >= 0x41 && code <= 0x5a;
}

/// The queries to try for a cleaned folder name, in order: the name
/// itself, its CamelCase split, and each of those with a trailing
/// language tag dropped.
List<String> folderQueryVariants(String cleaned) {
  final out = <String>[cleaned];
  final split = splitCamelQuery(cleaned);
  if (split != null) out.add(split);
  for (final base in [...out]) {
    final stripped = stripLanguageTag(base);
    if (stripped != null &&
        stripped.isNotEmpty &&
        !out.contains(stripped)) {
      out.add(stripped);
    }
  }
  return out;
}

/// The cleaned names of the folders between [exeDir] (the folder holding
/// the row's exe) and the scanned [root], nearest first. Empty when
/// [root] is unknown: without it there is no scope to search upwards in.
List<String> parentFolderQueries({
  required String exeDir,
  required String? root,
}) {
  if (root == null || root.isEmpty) return const [];
  final stop = p.normalize(root);
  final out = <String>[];
  var dir = p.dirname(p.normalize(exeDir));
  while (!p.equals(dir, stop) && p.isWithin(stop, dir)) {
    final cleaned = cleanFolderName(p.basename(dir));
    if (cleaned.isNotEmpty && !out.contains(cleaned)) out.add(cleaned);
    final parent = p.dirname(dir);
    if (parent == dir) break;
    dir = parent;
  }
  return out;
}

/// Every VNDB request from one import, through one queue: at most one
/// request starts per [gap] (200 requests per 5 minutes is one per
/// 1.5 s), and a 429 waits [retryWait] and retries the same request, up
/// to [maxRetries] times. [now] and [delay] are injectable for tests.
class VndbRequestQueue {
  VndbRequestQueue({
    required this.search,
    this.gap = const Duration(milliseconds: 1600),
    this.maxRetries = 3,
    this.retryWait = const Duration(seconds: 60),
    DateTime Function()? now,
    Future<void> Function(Duration)? delay,
  }) : _now = now ?? DateTime.now,
       _delay = delay ?? Future.delayed;

  final Future<List<VnSearchResult>> Function(String query) search;
  final Duration gap;
  final int maxRetries;
  final Duration retryWait;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _delay;

  Future<void> _tail = Future<void>.value();
  DateTime? _lastStart;
  bool _cancelled = false;

  /// Stops this queue: requests not yet sent, and any retry not yet
  /// waited out, complete with [VndbCancelled]. Requests made afterwards
  /// fail the same way.
  void cancel() => _cancelled = true;

  /// Runs [query] through the queue, serialized with the other queued
  /// requests.
  Future<List<VnSearchResult>> run(String query) {
    final done = Completer<List<VnSearchResult>>();
    _tail = _tail
        .then((_) => _execute(query))
        .then(done.complete, onError: done.completeError);
    return done.future;
  }

  Future<List<VnSearchResult>> _execute(String query) async {
    if (_cancelled) throw const VndbCancelled();
    final last = _lastStart;
    if (last != null) {
      final wait = last.add(gap).difference(_now());
      if (!wait.isNegative) await _delay(wait);
    }
    var retries = 0;
    for (;;) {
      if (_cancelled) throw const VndbCancelled();
      _lastStart = _now();
      try {
        return await search(query);
      } on VndbException catch (e) {
        if (e.statusCode != 429 || retries >= maxRetries) rethrow;
        retries++;
        if (_cancelled) throw const VndbCancelled();
        await _delay(retryWait);
      }
    }
  }
}

class VndbCancelled implements Exception {
  const VndbCancelled();
}

/// Searches VNDB for each query variant in order (the cleaned name, its
/// CamelCase split, language tags dropped, then the parent folders
/// nearest first), each with its [shortenedQuery] retry. Stops at the
/// first matched; otherwise keeps the first check. A variant that fails
/// is skipped; the first failure is rethrown only when no check was found.
Future<FolderMatch> lookupFolderMatch({
  required String query,
  required List<String> parentQueries,
  required Future<List<VnSearchResult>> Function(String query) search,
}) async {
  FolderMatch? check;
  ({Object error, StackTrace stack})? failure;
  final tried = <String>{};
  for (final candidate in [...folderQueryVariants(query), ...parentQueries]) {
    if (candidate.isEmpty || !tried.add(candidate)) continue;
    var match = const FolderMatch(ImportMatchState.none, null);
    try {
      final results = await lookupFolder(candidate, search);
      match = matchFolder(candidate, results);
    } catch (error, stack) {
      failure ??= (error: error, stack: stack);
      continue;
    }
    if (match.state == ImportMatchState.matched) return match;
    if (check == null && match.state == ImportMatchState.check) {
      check = match;
    }
  }
  if (check != null) return check;
  if (failure != null) Error.throwWithStackTrace(failure.error, failure.stack);
  return const FolderMatch(ImportMatchState.none, null);
}
