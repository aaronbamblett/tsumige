// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/pref_keys.dart' as keys;
import '../../data/library_repository.dart';
import '../../domain/cover_source.dart';
import '../../domain/library_query.dart';
import '../../../../utils/prefs/app_prefs.dart';
import '../../../../widgets/search_field.dart';

const Map<keys.SortField, String> sortFieldLabels = {
  keys.SortField.added: 'Added',
  keys.SortField.title: 'Title',
  keys.SortField.lastPlayed: 'Last played',
  keys.SortField.playtime: 'Playtime',
  keys.SortField.vndbRating: 'VNDB Rating',
};

/// Search, sort, filters, entry count and the cover-size slider in one row.
class LibraryToolbar extends ConsumerWidget {
  const LibraryToolbar({
    super.key,
    required this.shown,
    required this.total,
  });

  final int shown;
  final int total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final games = ref.watch(libraryProvider).value?.library.games ?? [];
    final tags = allTags(games);
    final field = ref.watch(sortFieldProvider);
    final ascending = ref.watch(sortAscendingProvider);
    final favouritesOnly = ref.watch(favouritesOnlyProvider);
    final tagFilter = ref.watch(tagFilterProvider);
    final coverWidth = ref.watch(coverWidthProvider);
    final countText =
        shown == total ? _count(total) : '$shown of $total';
    final width = MediaQuery.sizeOf(context).width;
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          spacing: 8,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: SearchField(
                    autofocus: false,
                    onClose: () {},
                    onChanged: (value) => ref
                        .read(librarySearchProvider.notifier)
                        .set(value ?? ''),
                  ),
                ),
              ),
            ),
            Expanded(
              // Scrolls only when too narrow to fit; shows all at desktop widths.
              flex: 4,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  spacing: 8,
                  children: [
                    PopupMenuButton<keys.SortField>(
                      initialValue: field,
                      onSelected: (value) => ref
                          .read(sortFieldProvider.notifier)
                          .set(value),
                      itemBuilder: (context) => [
                        for (final entry in sortFieldLabels.entries)
                          CheckedPopupMenuItem(
                            value: entry.key,
                            checked: entry.key == field,
                            child: Text(entry.value),
                          ),
                      ],
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(sortFieldLabels[field]!),
                          const Icon(Icons.arrow_drop_down_rounded),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: ascending ? 'Ascending' : 'Descending',
                      icon: Icon(ascending
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded),
                      onPressed: () => ref
                          .read(sortAscendingProvider.notifier)
                          .set(!ascending),
                    ),
                    if (width < 600)
                      IconButton(
                        tooltip: 'Favourites only',
                        icon: Icon(favouritesOnly
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded),
                        onPressed: () => ref
                            .read(favouritesOnlyProvider.notifier)
                            .set(!favouritesOnly),
                      )
                    else
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('All')),
                          ButtonSegment(
                              value: true, label: Text('Favourites')),
                        ],
                        selected: {favouritesOnly},
                        onSelectionChanged: (selected) => ref
                            .read(favouritesOnlyProvider.notifier)
                            .set(selected.first),
                      ),
                    PopupMenuButton<String?>(
                      onSelected: (value) => ref
                          .read(tagFilterProvider.notifier)
                          .set(value),
                      itemBuilder: (context) => [
                        CheckedPopupMenuItem(
                          value: null,
                          checked: tagFilter == null,
                          child: const Text('All tags'),
                        ),
                        for (final tag in tags)
                          CheckedPopupMenuItem(
                            value: tag,
                            checked: tagFilter == tag,
                            child: Text(tag),
                          ),
                      ],
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(tagFilter ?? 'Tags'),
                          const Icon(Icons.arrow_drop_down_rounded),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            if (width >= 900) ...[
              const Tooltip(
                message: 'Cover size',
                child: Icon(Icons.photo_size_select_large_rounded),
              ),
              SizedBox(
                width: 200,
                child: Slider(
                  value: coverWidth.toDouble(),
                  min: keys.coverWidthMin.toDouble(),
                  max: keys.coverWidthMax.toDouble(),
                  label: '$coverWidth',
                  onChanged: (value) => ref
                      .read(coverWidthProvider.notifier)
                      .set(value.round()),
                ),
              ),
            ],
            Text(countText),
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_rounded),
              onPressed: () => context.go('/settings'),
            ),
          ],
        ),
      ),
    );
  }
}

String _count(int total) => total == 1 ? '1 game' : '$total games';
