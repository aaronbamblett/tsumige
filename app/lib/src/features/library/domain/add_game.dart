// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/model.dart';
import '../../../core/vndb.dart';

part 'add_game.g.dart';

/// HTTP client for VNDB search and cover downloads. Tests override this with
/// a MockClient so the real VNDB API is never called.
@riverpod
http.Client addGameHttpClient(Ref ref) => http.Client();

/// VNDB client built on the overridable HTTP client above.
@riverpod
VndbClient vndbSearchClient(Ref ref) =>
    VndbClient(client: ref.watch(addGameHttpClientProvider));

Game gameFromVn(VnSearchResult r,
    {required String exe, LaunchMode? mode, DateTime? now}) {
  final at = (now ?? DateTime.now()).toUtc();
  return Game(
    id: const Uuid().v4(),
    title: r.title,
    description: r.description,
    tags: [...r.tags],
    addedAt: at,
    vndbId: r.id,
    released: r.released,
    vndbRating: r.rating,
    vndbVotecount: r.votecount,
    vndbFetchedAt: at,
    launch: LaunchOverrides(
      mode: mode,
      executable: exe.isEmpty ? null : exe,
    ),
  );
}

/// Orders VNDB search results: an exact title match first, then titles that
/// start with the query, keeping VNDB's order within each group.
List<VnSearchResult> rankSearchResults(
    List<VnSearchResult> results, String query) {
  final q = query.trim().toLowerCase();
  int rank(VnSearchResult result) {
    final title = result.title.trim().toLowerCase();
    if (title == q) return 0;
    return title.startsWith(q) ? 1 : 2;
  }

  final order = List<int>.generate(results.length, (i) => i)
    ..sort((a, b) {
      final byRank = rank(results[a]).compareTo(rank(results[b]));
      return byRank != 0 ? byRank : a.compareTo(b);
    });
  return [for (final i in order) results[i]];
}

/// Fills the VNDB data for a game just picked from search. A failed fetch
/// leaves the basic fields from the search result in place.
Future<void> fillVndbMetadata(Game game, VndbClient client,
    {DateTime? now}) async {
  final id = game.vndbId;
  if (id == null) return;
  final at = (now ?? DateTime.now()).toUtc();
  try {
    final vns = await client.fetchVnData([id]);
    final adult = await client.fetchAdultVnIds([id]);
    for (final vn in vns.where((v) => v.id == id)) {
      applyVnData(game, vn, adult: adult.contains(id), fetchedAt: at);
    }
  } catch (_) {}
}

List<String> parseTagsField(String raw) {
  final out = <String>[];
  final seen = <String>{};
  for (final part in raw.split(',')) {
    final tag = part.trim();
    if (tag.isEmpty || !seen.add(tag.toLowerCase())) continue;
    out.add(tag);
  }
  return out;
}
