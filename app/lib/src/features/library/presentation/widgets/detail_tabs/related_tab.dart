// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../../core/model.dart';
import '../../../../../core/similar.dart';
import '../../../../../utils/theme/brand.dart';
import '../../../data/library_repository.dart';
import '../../../domain/cover_source.dart';
import '../../../domain/selection.dart';
import '../art_image.dart';
import '../art_overlay.dart';
import 'info_tab.dart';

/// Opens a VNDB page in the browser. Overridden in tests so no browser opens.
final vndbUrlOpenerProvider = Provider<Future<bool> Function(Uri)>(
  (ref) => launchUrl,
);

/// The pane's Related tab: VNDB relations, then games like this one.
class RelatedTab extends ConsumerWidget {
  const RelatedTab({super.key, required this.game});

  final Game game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider).value?.library.games ?? const [];
    final owned = {
      for (final g in library)
        if (g.vndbId != null) g.vndbId!: g,
    };
    final relations = [
      for (final rank in const [0, 1, 2])
        for (final r in game.relations)
          if (_relationRank(r.relation) == rank) r,
    ];
    final similar = similarGames(game, library, limit: 6);
    final blocks = <Widget>[
      if (relations.isNotEmpty)
        DetailSection(
          label: 'Related',
          child: _Grid(
            children: [
              for (final r in relations)
                _RelationTile(
                  title: r.title,
                  game: owned[r.vndbId],
                  imageUrl: r.imageUrl,
                  vndbId: r.vndbId,
                ),
            ],
          ),
        ),
      if (similar.isNotEmpty)
        DetailSection(
          label: 'More like this',
          child: _Grid(
            children: [
              for (final (other, _) in similar)
                _RelationTile(title: other.title, game: other),
            ],
          ),
        ),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < blocks.length; i++) ...[
            if (i > 0) detailSectionDivider(context),
            blocks[i],
          ],
        ],
      ),
    );
  }
}

int _relationRank(String relation) => switch (relation) {
  'seq' || 'preq' => 0,
  'ser' || 'side' => 1,
  _ => 2,
};

/// Three tiles per row: 14 px across, 16 px down.
class _Grid extends StatelessWidget {
  const _Grid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var start = 0; start < children.length; start += 3) {
      final cells = <Widget>[];
      for (var col = 0; col < 3; col++) {
        if (col > 0) cells.add(const SizedBox(width: 14));
        final index = start + col;
        cells.add(
          Expanded(
            child: index < children.length ? children[index] : const SizedBox(),
          ),
        );
      }
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 16));
      rows.add(
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: cells),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

/// A related game. Owned games select the library tile; other VNDB entries
/// open their VNDB page.
class _RelationTile extends ConsumerStatefulWidget {
  const _RelationTile({
    required this.title,
    this.game,
    this.imageUrl,
    this.vndbId,
  });

  final String title;
  final Game? game;
  final String? imageUrl;
  final String? vndbId;

  @override
  ConsumerState<_RelationTile> createState() => _RelationTileState();
}

class _RelationTileState extends ConsumerState<_RelationTile> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final game = widget.game;
    final id = widget.vndbId;
    const coverRadius = BorderRadius.all(Radius.circular(10));
    return InkWell(
      borderRadius: coverRadius,
      onHover: (hovered) => setState(() => _hovered = hovered),
      onTap: () {
        if (game != null) {
          ref.read(selectedGameIdProvider.notifier).select(game.id);
        } else if (id != null) {
          ref.read(vndbUrlOpenerProvider)(Uri.parse('https://vndb.org/$id'));
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 3 / 4,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(borderRadius: coverRadius),
              foregroundDecoration: _hovered
                  ? BoxDecoration(
                      borderRadius: coverRadius,
                      border: Border.all(color: scheme.primary, width: 2),
                    )
                  : null,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  game != null
                      ? _OwnedCover(game: game)
                      : _RemoteCover(url: widget.imageUrl),
                  if (game == null)
                    const Positioned(top: 6, right: 6, child: _ExternalBadge()),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _OwnedCover extends ConsumerWidget {
  const _OwnedCover({required this.game});

  final Game game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dir = ref.watch(dataDirProvider);
    final exists = ref.watch(coverExistsProvider);
    final version = ref.watch(artVersionProvider);
    final settled =
        ref.watch(settledCoverWidthProvider) *
        MediaQuery.devicePixelRatioOf(context);
    final source = coverSourceFor(game, dir, settled, exists);
    if (source == null) return const _NoCover();
    return Image(
      image: artFileImage(File(source.path), version: version(source.path)),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => const _NoCover(),
    );
  }
}

class _RemoteCover extends StatelessWidget {
  const _RemoteCover({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    if (url == null || url.isEmpty) return const _NoCover();
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const _NoCover(),
    );
  }
}

class _NoCover extends StatelessWidget {
  const _NoCover();

  @override
  Widget build(BuildContext context) => const Center(child: Text('No cover'));
}

class _ExternalBadge extends StatelessWidget {
  const _ExternalBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ArtOverlay.button,
        border: Border.all(color: ArtOverlay.buttonRing),
      ),
      child: const Icon(
        Icons.north_east_rounded,
        size: 14,
        color: OnImage.text,
      ),
    );
  }
}
