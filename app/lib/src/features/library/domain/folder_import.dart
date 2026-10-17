// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

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
  });

  final String name;
  final String path;

  /// Every candidate exe, in scan order. Empty when none was found.
  final List<ExeFile> exes;
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

/// Lists the direct, non-hidden subfolders of [root] with their exe
/// candidates, sorted by name.
Future<List<ImportFolder>> scanImportFolder(String root) async {
  final folders = <ImportFolder>[];
  await for (final entity in Directory(root).list()) {
    if (entity is! Directory) continue;
    final name = p.basename(entity.path);
    if (name.startsWith('.')) continue;
    folders.add(
      ImportFolder(
        name: name,
        path: entity.path,
        exes: await _findExes(entity.path),
      ),
    );
  }
  folders.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return folders;
}

Future<List<ExeFile>> _findExes(String folder) async {
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
      if (entry is Directory) {
        final name = p.basename(entry.path);
        if (depth < 3 && !_excludedDirs.contains(name.toLowerCase())) {
          subdirs.add(entry.path);
        }
      } else if (entry is File &&
          p.extension(entry.path).toLowerCase() == '.exe') {
        found.add(
          ExeFile(
            path: entry.path,
            relative: p.relative(entry.path, from: folder),
            size: await entry.length(),
            topLevel: dir == folder,
          ),
        );
      }
    }
    for (final subdir in subdirs) {
      await walk(subdir, depth + 1);
    }
  }

  await walk(folder, 0);
  return _candidates(found);
}

List<ExeFile> _candidates(List<ExeFile> found) {
  var candidates = [
    for (final exe in found)
      if (!_excludedNames.any((re) => re.hasMatch(exe.stem.toLowerCase()))) exe,
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

/// Lowercases, turns punctuation into spaces and collapses whitespace.
String normalise(String value) {
  final cleaned = value.toLowerCase().replaceAll(
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
].where((t) => t.isNotEmpty).toList();

/// Similarity of a folder name to a title, from 0 to 1. A substring match
/// scores at least 0.85.
double similarity(String folder, String title) {
  final a = normalise(folder);
  final b = normalise(title);
  if (a == b) return 1.0;
  var ratio = sequenceRatio(a, b);
  if (a.isNotEmpty && b.isNotEmpty && (a.contains(b) || b.contains(a))) {
    final shorter = math.min(a.runes.length, b.runes.length);
    final longer = math.max(a.runes.length, b.runes.length);
    ratio = math.max(ratio, 0.85 + 0.14 * shorter / longer);
  }
  return ratio;
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
