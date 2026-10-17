// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/pref_keys.dart' as keys;
import '../../data/library_repository.dart';
import '../../domain/cover_source.dart';
import '../../domain/library_query.dart';
import '../../../../utils/prefs/app_prefs.dart';
import '../add_game/add_game_dialog.dart';
import 'library_grid.dart';

const Map<keys.SortField, String> sortFieldLabels = {
  keys.SortField.added: 'Added',
  keys.SortField.title: 'Title',
  keys.SortField.lastPlayed: 'Last played',
  keys.SortField.playtime: 'Playtime',
  keys.SortField.vndbRating: 'VNDB Rating',
};

const double _kControlHeight = 40;
const double _kGap = 10;
const double _kSortWidth = 180;
const double _kSegmentsWidth = 170;
const double _kTagWidth = 180;
const double _kSearchMinWidth = 200;
const double _kAddWidth = 104;
const double _kRightInset = 12;

/// Width of the right group: Add, a gap, then Settings.
const double _kRightGroupWidth = _kAddWidth + _kGap + _kControlHeight;

/// Width the left group needs with the search box at its minimum.
const double _kLeftGroupMinWidth =
    _kSearchMinWidth + _kSortWidth + _kSegmentsWidth + _kTagWidth + 3 * _kGap;

/// Search, sort, favourites and tag controls on the left; Add and Settings
/// pinned right. [gridRight] is where the grid's last cover column ends, so
/// the left group lines up with the covers. The left group stops short of
/// the right group when the two would meet. The search box absorbs any
/// slack and stops at its minimum; past that the left group can run past
/// [gridRight].
class LibraryToolbar extends ConsumerWidget {
  const LibraryToolbar({super.key, required this.gridRight});

  final double gridRight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final games = ref.watch(libraryProvider).value?.library.games ?? [];
    final tags = allTags(games);
    final field = ref.watch(sortFieldProvider);
    final ascending = ref.watch(sortAscendingProvider);
    final favouritesOnly = ref.watch(favouritesOnlyProvider);
    final tagFilter = ref.watch(tagFilterProvider);
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 64,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final leftEnd = math.min(
            gridRight,
            constraints.maxWidth - _kRightInset - _kRightGroupWidth - _kGap,
          );
          final leftWidth = math.max(
            leftEnd - LibraryGrid.horizontalPadding,
            _kLeftGroupMinWidth,
          );
          return Stack(
            children: [
              Positioned(
                left: LibraryGrid.horizontalPadding,
                top: 0,
                bottom: 0,
                width: leftWidth,
                child: Row(
                  children: [
                    const Expanded(child: _ToolbarSearchField()),
                    const SizedBox(width: _kGap),
                    _ToolbarBox(
                      width: _kSortWidth,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _SortMenu(
                              field: field,
                              onSelected: (value) => ref
                                  .read(sortFieldProvider.notifier)
                                  .set(value),
                            ),
                          ),
                          Center(
                            child: Container(
                              width: 1,
                              height: 22,
                              color: scheme.outlineVariant,
                            ),
                          ),
                          Tooltip(
                            message: ascending ? 'Ascending' : 'Descending',
                            child: InkWell(
                              onTap: () => ref
                                  .read(sortAscendingProvider.notifier)
                                  .set(!ascending),
                              child: SizedBox(
                                width: _kControlHeight,
                                child: Icon(
                                  ascending
                                      ? Icons.arrow_upward_rounded
                                      : Icons.arrow_downward_rounded,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: _kGap),
                    _ToolbarBox(
                      width: _kSegmentsWidth,
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Row(
                          children: [
                            Expanded(
                              child: _Segment(
                                label: 'All',
                                selected: !favouritesOnly,
                                onTap: () => ref
                                    .read(favouritesOnlyProvider.notifier)
                                    .set(false),
                              ),
                            ),
                            const SizedBox(width: 2),
                            Expanded(
                              child: _Segment(
                                label: 'Favourites',
                                selected: favouritesOnly,
                                onTap: () => ref
                                    .read(favouritesOnlyProvider.notifier)
                                    .set(true),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: _kGap),
                    _ToolbarBox(
                      key: const ValueKey('toolbar-tag'),
                      width: _kTagWidth,
                      child: _TagMenu(
                        tags: tags,
                        value: tagFilter,
                        onSelected: (value) =>
                            ref.read(tagFilterProvider.notifier).set(value),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: _kRightInset,
                top: 0,
                bottom: 0,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ToolbarBox(
                      width: _kAddWidth,
                      child: Tooltip(
                        message: 'Add game',
                        child: InkWell(
                          onTap: () => showAddGameDialog(context),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.add_rounded, size: 18),
                                SizedBox(width: 8),
                                Text('Add'),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: _kGap),
                    _ToolbarBox(
                      key: const ValueKey('toolbar-settings'),
                      width: _kControlHeight,
                      child: Tooltip(
                        message: 'Settings',
                        child: InkWell(
                          onTap: () => context.push('/settings'),
                          child: const Icon(Icons.settings_rounded, size: 20),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The shared control chrome: a 40 px box, 10 px radius, `surfaceContainer`
/// fill and an `outlineVariant` border that brightens on hover.
class _ToolbarBox extends StatefulWidget {
  const _ToolbarBox({super.key, this.width, required this.child});

  final double? width;
  final Widget child;

  @override
  State<_ToolbarBox> createState() => _ToolbarBoxState();
}

class _ToolbarBoxState extends State<_ToolbarBox> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        width: widget.width,
        height: _kControlHeight,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _hovered
                ? scheme.onSurface.withValues(alpha: 0.18)
                : scheme.outlineVariant,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}

class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.field, required this.onSelected});

  final keys.SortField field;
  final ValueChanged<keys.SortField> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MenuAnchor(
      style: const MenuStyle(
        minimumSize: WidgetStatePropertyAll(Size(_kSortWidth, 0)),
      ),
      menuChildren: [
        for (final entry in sortFieldLabels.entries)
          MenuItemButton(
            leadingIcon: entry.key == field
                ? const Icon(Icons.check_rounded, size: 18)
                : null,
            onPressed: () => onSelected(entry.key),
            child: Text(entry.value),
          ),
      ],
      builder: (context, controller, _) => InkWell(
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        child: Padding(
          padding: const EdgeInsets.only(left: 14, right: 10),
          child: Row(
            children: [
              Icon(
                Icons.sort_rounded,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: _kGap),
              Expanded(
                child: Text(
                  sortFieldLabels[field]!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.arrow_drop_down_rounded, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _TagMenu extends StatelessWidget {
  const _TagMenu({
    required this.tags,
    required this.value,
    required this.onSelected,
  });

  final List<String> tags;
  final String? value;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MenuAnchor(
      style: const MenuStyle(
        minimumSize: WidgetStatePropertyAll(Size(_kTagWidth, 0)),
        maximumSize: WidgetStatePropertyAll(Size(double.infinity, 360)),
      ),
      menuChildren: [
        MenuItemButton(
          leadingIcon: value == null
              ? const Icon(Icons.check_rounded, size: 18)
              : null,
          onPressed: () => onSelected(null),
          child: const Text('All tags'),
        ),
        for (final tag in tags)
          MenuItemButton(
            leadingIcon: tag == value
                ? const Icon(Icons.check_rounded, size: 18)
                : null,
            onPressed: () => onSelected(tag),
            child: Text(tag),
          ),
      ],
      builder: (context, controller, _) => InkWell(
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        child: Padding(
          padding: const EdgeInsets.only(left: 14, right: 10),
          child: Row(
            children: [
              Icon(
                Icons.local_offer_rounded,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: _kGap),
              Expanded(
                child: Text(
                  value ?? 'All tags',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.arrow_drop_down_rounded, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: onTap,
      child: Container(
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : null,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Plain search field: a search icon and hint text, no floating label.
class _ToolbarSearchField extends ConsumerStatefulWidget {
  const _ToolbarSearchField();

  @override
  ConsumerState<_ToolbarSearchField> createState() =>
      _ToolbarSearchFieldState();
}

class _ToolbarSearchFieldState extends ConsumerState<_ToolbarSearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _ToolbarBox(
      key: const ValueKey('toolbar-search'),
      child: Padding(
        padding: const EdgeInsets.only(left: 14, right: 6),
        child: Row(
          children: [
            Icon(
              Icons.search_rounded,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: _kGap),
            Expanded(
              child: TextField(
                controller: _controller,
                onChanged: (value) =>
                    ref.read(librarySearchProvider.notifier).set(value),
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration.collapsed(
                  hintText: 'Search visual novels…',
                  hintStyle: TextStyle(color: scheme.outline, fontSize: 14),
                ),
              ),
            ),
            if (_controller.text.isNotEmpty)
              IconButton(
                tooltip: 'Clear search',
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                icon: const Icon(Icons.clear_rounded),
                onPressed: () {
                  _controller.clear();
                  ref.read(librarySearchProvider.notifier).set('');
                },
              ),
          ],
        ),
      ),
    );
  }
}
