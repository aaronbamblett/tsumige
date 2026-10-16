// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/covers.dart';
import '../../../core/model.dart';
import '../../../core/paths.dart';
import '../../../utils/prefs/app_prefs.dart';
import '../data/library_repository.dart';
import 'library_query.dart';

part 'cover_source.g.dart';

class CoverSource {
  const CoverSource({required this.path, required this.isThumbnail});

  final String path;
  final bool isThumbnail;
}

CoverSource? coverSourceFor(
  Game game,
  DataDir dir,
  double settledPhysicalWidth,
  bool Function(String path) exists,
) {
  final cover = game.cover;
  if (cover == null || cover.isEmpty) return null;
  for (final width in thumbWidths) {
    if (width < settledPhysicalWidth) continue;
    final path = thumbPath(dir, game.id, width);
    if (exists(path)) {
      return CoverSource(path: path, isThumbnail: true);
    }
  }
  return CoverSource(
    path: p.join(dir.coversOriginal.path, cover),
    isThumbnail: false,
  );
}

/// Memoised cover-file existence check: each path hits the disk once, so
/// scrolling and slider drags never re-stat files every frame.
@Riverpod(keepAlive: true)
bool Function(String path) coverExists(Ref ref) {
  final cache = <String, bool>{};
  return (String path) =>
      cache.putIfAbsent(path, () => File(path).existsSync());
}

/// The cover width the grid decodes from. It follows [coverWidthProvider]
/// 250 ms after the slider stops, so during a drag tiles keep their current
/// image and scale it instead of re-decoding every step.
@Riverpod(keepAlive: true)
class SettledCoverWidth extends _$SettledCoverWidth {
  Timer? _timer;

  @override
  int build() {
    ref.onDispose(() => _timer?.cancel());
    ref.listen<int>(coverWidthProvider, (_, next) {
      _timer?.cancel();
      if (next == state) return;
      _timer = Timer(const Duration(milliseconds: 250), () => state = next);
    });
    return ref.read(coverWidthProvider);
  }
}

/// Search text for the library grid. Local state, not persisted.
@Riverpod(keepAlive: true)
class LibrarySearch extends _$LibrarySearch {
  @override
  String build() => '';

  void set(String value) => state = value;
}

/// `applyQuery` over the loaded library and every toolbar preference.
@riverpod
List<Game> visibleGames(Ref ref) {
  final loaded = ref.watch(libraryProvider).value;
  final query = LibraryQuery(
    search: ref.watch(librarySearchProvider),
    favouritesOnly: ref.watch(favouritesOnlyProvider),
    tag: ref.watch(tagFilterProvider),
    field: ref.watch(sortFieldProvider),
    ascending: ref.watch(sortAscendingProvider),
  );
  if (loaded == null) return const [];
  return applyQuery(loaded.library.games, query);
}
