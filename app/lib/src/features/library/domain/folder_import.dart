// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../../../core/host_platform.dart';
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

enum ImportMatchState { matched, check, none }

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

/// The game folders under [root]. When [root] itself holds a launchable it is
/// the only game. Otherwise each subfolder is classified by [_collectGames].
/// Folders with no launchable within [_maxGameDepth] levels are never listed.
Future<List<ImportFolder>> scanImportFolder(
  String root,
  HostPlatform platform,
) async {
  if (await _holdsLaunchable(root, platform)) {
    return [await _importFolder(root, platform)];
  }
  final folders = <ImportFolder>[];
  for (final sub in await _subfolders(root)) {
    await _collectGames(sub, 1, platform, folders);
  }
  folders.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return folders;
}

/// Classifies [dir], which sits [level] folders below the picked folder. A
/// folder that holds a launchable is one game. Otherwise, when every
/// launchable beneath it sits under one immediate child, it is one game with
/// its exes beneath. When they sit under two or more children, it is a
/// collection, and each child is classified the same way.
Future<void> _collectGames(
  String dir,
  int level,
  HostPlatform platform,
  List<ImportFolder> out,
) async {
  if (level > _maxGameDepth) return;
  if (await _holdsLaunchable(dir, platform)) {
    out.add(await _importFolder(dir, platform));
    return;
  }
  final hits = await _launchableFolders(dir, level, platform);
  if (hits.isEmpty) return;
  final children = {
    for (final hit in hits) p.split(p.relative(hit, from: dir)).first,
  };
  if (children.length == 1) {
    out.add(await _importFolder(dir, platform));
    return;
  }
  for (final sub in await _subfolders(dir)) {
    await _collectGames(sub, level + 1, platform, out);
  }
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
    } else if (sa.isNotEmpty && sa.length < sb.length && sb.startsWith(sa)) {
      ratio = math.max(ratio, _containmentScore(sa, sb));
    }
  }
  return ratio;
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
