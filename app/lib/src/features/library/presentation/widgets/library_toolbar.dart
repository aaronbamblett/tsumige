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

const double _kFieldHeight = 40;
const double _kDropdownWidth = 170;

/// Search, sort, filters, entry count and the cover-size slider in one row.
/// Scrolls horizontally only when too narrow to fit; at desktop widths every
/// control is visible, with the count and settings pinned to the right.
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
    final searchWidth = (width * 0.25).clamp(160.0, 360.0);
    final decoration =
        Theme.of(context).inputDecorationTheme.copyWith(
      filled: true,
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      constraints: const BoxConstraints.tightFor(height: _kFieldHeight),
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    );
    return SizedBox(
      height: 64,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: width - 24),
            child: Row(
              spacing: 12,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  spacing: 12,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: searchWidth,
                      child: Theme(
                        data: Theme.of(context)
                            .copyWith(inputDecorationTheme: decoration),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
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
                    DropdownMenu<keys.SortField>(
                      width: _kDropdownWidth,
                      label: const Text('Sort by'),
                      inputDecorationTheme: decoration,
                      initialSelection: field,
                      onSelected: (value) {
                        if (value != null) {
                          ref.read(sortFieldProvider.notifier).set(value);
                        }
                      },
                      dropdownMenuEntries: [
                        for (final entry in sortFieldLabels.entries)
                          DropdownMenuEntry(
                            value: entry.key,
                            label: entry.value,
                          ),
                      ],
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
                    SegmentedButton<bool>(
                      showSelectedIcon: false,
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
                    DropdownMenu<String?>(
                      width: _kDropdownWidth,
                      label: const Text('Tag'),
                      inputDecorationTheme: decoration,
                      initialSelection: tagFilter,
                      onSelected: (value) => ref
                          .read(tagFilterProvider.notifier)
                          .set(value),
                      dropdownMenuEntries: [
                        const DropdownMenuEntry(
                          value: null,
                          label: 'All tags',
                        ),
                        for (final tag in tags)
                          DropdownMenuEntry(
                            value: tag,
                            label: tag,
                          ),
                      ],
                    ),
                  ],
                ),
                Row(
                  spacing: 12,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (width >= 900)
                      SizedBox(
                        width: 160,
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
                    Text(countText),
                    IconButton(
                      tooltip: 'Settings',
                      icon: const Icon(Icons.settings_rounded),
                      onPressed: () => context.push('/settings'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _count(int total) => total == 1 ? '1 game' : '$total games';
