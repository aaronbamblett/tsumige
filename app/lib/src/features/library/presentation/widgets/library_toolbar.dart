// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/pref_keys.dart' as keys;
import '../../../../core/model.dart' show Developer;
import '../../data/library_repository.dart';
import '../../domain/cover_source.dart';
import '../../domain/library_query.dart';
import '../../../../utils/prefs/app_prefs.dart';
import '../../../../utils/theme/brand.dart';
import '../../../settings/presentation/settings_dialog.dart';
import '../add_game/add_game_dialog.dart';
import 'detail_tabs/info_tab.dart' show TagChip;
import 'library_grid.dart';

const Map<keys.SortField, String> sortFieldLabels = {
  keys.SortField.added: 'Added',
  keys.SortField.title: 'Title',
  keys.SortField.lastPlayed: 'Last played',
  keys.SortField.playtime: 'Playtime',
  keys.SortField.vndbRating: 'VNDB Rating',
};

const Map<keys.AdultFilter, String> adultFilterLabels = {
  keys.AdultFilter.all: 'All games',
  keys.AdultFilter.hide: 'Hide adult',
  keys.AdultFilter.only: 'Adult only',
};

const double _kControlHeight = 40;
const double _kGap = 10;
const double _kSortWidth = 180;
const double _kSegmentsWidth = 170;
const double _kFilterWidth = 180;
const double _kSearchMinWidth = 200;
const double _kAddWidth = 104;
const double _kRightInset = 12;
const double _kPanelWidth = 360;

/// Width of the right group: Add, a gap, then Settings.
const double _kRightGroupWidth = _kAddWidth + _kGap + _kControlHeight;

/// Width the left group needs with the search box at its minimum.
const double _kLeftGroupMinWidth =
    _kSearchMinWidth +
    _kSortWidth +
    _kSegmentsWidth +
    _kFilterWidth +
    3 * _kGap;

/// Search, sort, favourites and the Filter panel on the left; Add and Settings
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
    final field = ref.watch(sortFieldProvider);
    final ascending = ref.watch(sortAscendingProvider);
    final favouritesOnly = ref.watch(favouritesOnlyProvider);
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
                    ToolbarBox(
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
                    ToolbarBox(
                      width: _kSegmentsWidth,
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Row(
                          children: [
                            Expanded(
                              child: ToolbarSegment(
                                label: 'All',
                                selected: !favouritesOnly,
                                onTap: () => ref
                                    .read(favouritesOnlyProvider.notifier)
                                    .set(false),
                              ),
                            ),
                            const SizedBox(width: 2),
                            Expanded(
                              child: ToolbarSegment(
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
                    const _FilterButton(),
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
                    Tooltip(
                      message: 'Add game',
                      child: BrandGlassButton(
                        height: 40,
                        expand: false,
                        onPressed: () => showAddGameDialog(context),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add'),
                      ),
                    ),
                    const SizedBox(width: _kGap),
                    ToolbarBox(
                      key: const ValueKey('toolbar-settings'),
                      width: _kControlHeight,
                      child: Tooltip(
                        message: 'Settings',
                        child: InkWell(
                          onTap: () => showSettingsDialog(context),
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
/// fill and an `outlineVariant` border that brightens on hover. A
/// [borderColor] replaces the border while it is set.
class ToolbarBox extends StatefulWidget {
  const ToolbarBox({
    super.key,
    this.width,
    this.borderColor,
    required this.child,
  });

  final double? width;
  final Color? borderColor;
  final Widget child;

  @override
  State<ToolbarBox> createState() => _ToolbarBoxState();
}

class _ToolbarBoxState extends State<ToolbarBox> {
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
            color:
                widget.borderColor ??
                (_hovered
                    ? scheme.onSurface.withValues(alpha: 0.18)
                    : scheme.outlineVariant),
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

/// The Filter box: a count badge and accent outline while any filter is set.
/// Opens [_FilterPanel] under itself, with no scrim.
class _FilterButton extends ConsumerStatefulWidget {
  const _FilterButton();

  @override
  ConsumerState<_FilterButton> createState() => _FilterButtonState();
}

class _FilterButtonState extends ConsumerState<_FilterButton> {
  final _controller = OverlayPortalController();
  final _link = LayerLink();
  final _focus = FocusNode(debugLabel: 'filter');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _close() {
    _controller.hide();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = activeFilterCount(
      ref.watch(tagFilterProvider),
      ref.watch(adultFilterProvider),
      ref.watch(developerFilterProvider),
    );
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _controller,
        overlayChildBuilder: (context) =>
            _FilterPanelOverlay(link: _link, onClose: _close),
        child: ToolbarBox(
          key: const ValueKey('toolbar-filter'),
          width: _kFilterWidth,
          borderColor: count > 0 ? scheme.primary : null,
          child: InkWell(
            focusNode: _focus,
            onTap: () => _controller.isShowing ? _close() : _controller.show(),
            child: Padding(
              padding: const EdgeInsets.only(left: 14, right: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.filter_list_rounded,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: _kGap),
                  const Expanded(child: Text('Filter', maxLines: 1)),
                  if (count > 0) ...[
                    Container(
                      width: 18,
                      height: 18,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: scheme.primary,
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: scheme.onPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  const Icon(Icons.arrow_drop_down_rounded, size: 22),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Number of filters in use: a tag, a non-All adult setting and a developer.
int activeFilterCount(
  String? tag,
  keys.AdultFilter adult,
  Developer? developer,
) =>
    (tag != null ? 1 : 0) +
    (adult != keys.AdultFilter.all ? 1 : 0) +
    (developer != null ? 1 : 0);

class _FilterPanelOverlay extends StatelessWidget {
  const _FilterPanelOverlay({required this.link, required this.onClose});

  final LayerLink link;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return Stack(
      children: [
        // Invisible and opaque: an outside click closes the panel and never
        // reaches the widget underneath.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
          ),
        ),
        CompositedTransformFollower(
          link: link,
          targetAnchor: Alignment.bottomRight,
          followerAnchor: Alignment.topRight,
          offset: const Offset(0, 6),
          child: _FilterPanel(maxHeight: height * 0.7, onClose: onClose),
        ),
      ],
    );
  }
}

class _FilterPanel extends ConsumerStatefulWidget {
  const _FilterPanel({required this.maxHeight, required this.onClose});

  final double maxHeight;
  final VoidCallback onClose;

  @override
  ConsumerState<_FilterPanel> createState() => _FilterPanelState();
}

class _FilterPanelState extends ConsumerState<_FilterPanel> {
  /// VNDB tags listed before a search narrows the list.
  static const _vndbListLimit = 40;

  final _scroll = ScrollController();
  final _focus = FocusNode(debugLabel: 'filter panel');
  var _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _clearAll() {
    ref.read(tagFilterProvider.notifier).set(null);
    ref.read(adultFilterProvider.notifier).set(keys.AdultFilter.all);
    ref.read(developerFilterProvider.notifier).set(null);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final games = ref.watch(libraryProvider).value?.library.games ?? [];
    final tagFilter = ref.watch(tagFilterProvider);
    final adult = ref.watch(adultFilterProvider);
    final developer = ref.watch(developerFilterProvider);
    final needle = _query.trim().toLowerCase();
    final userTags = [
      for (final tag in allTags(games))
        if (needle.isEmpty || tag.toLowerCase().contains(needle)) tag,
    ];
    final allVndb = vndbTagCounts(games);
    final vndbTags = needle.isEmpty
        ? allVndb.take(_vndbListLimit).toList()
        : [
            for (final t in allVndb)
              if (t.$1.toLowerCase().contains(needle)) t,
          ];
    final activeCount = activeFilterCount(tagFilter, adult, developer);
    return Material(
      color: scheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Focus(
        focusNode: _focus,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            widget.onClose();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: SizedBox(
          width: _kPanelWidth,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: widget.maxHeight),
            child: Scrollbar(
              controller: _scroll,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PanelSection(
                      title: 'Adult',
                      child: ToolbarBox(
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: Row(
                            children: [
                              for (final entry
                                  in adultFilterLabels.entries) ...[
                                if (entry.key != keys.AdultFilter.all)
                                  const SizedBox(width: 2),
                                Expanded(
                                  child: ToolbarSegment(
                                    label: entry.value,
                                    selected: adult == entry.key,
                                    onTap: () => ref
                                        .read(adultFilterProvider.notifier)
                                        .set(entry.key),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (developer != null) ...[
                      const _PanelDivider(),
                      _PanelSection(
                        title: 'Developer',
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TagChip(
                            label: developer.name,
                            onRemove: () => ref
                                .read(developerFilterProvider.notifier)
                                .set(null),
                          ),
                        ),
                      ),
                    ],
                    const _PanelDivider(),
                    _PanelSection(
                      title: 'Tags',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ToolbarBox(
                            child: Padding(
                              padding: const EdgeInsets.only(
                                left: 14,
                                right: 6,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.search_rounded,
                                    size: 18,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: _kGap),
                                  Expanded(
                                    child: TextField(
                                      onChanged: (text) =>
                                          setState(() => _query = text),
                                      style: const TextStyle(fontSize: 14),
                                      decoration: InputDecoration.collapsed(
                                        hintText: 'Search tags…',
                                        hintStyle: TextStyle(
                                          color: scheme.outline,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _TagOption(
                            label: 'All tags',
                            selected: tagFilter == null,
                            onTap: () =>
                                ref.read(tagFilterProvider.notifier).set(null),
                          ),
                          for (final tag in userTags)
                            _TagOption(
                              label: tag,
                              selected: tag == tagFilter,
                              onTap: () =>
                                  ref.read(tagFilterProvider.notifier).set(tag),
                            ),
                          if (vndbTags.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
                              child: Text(
                                'VNDB tags',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            for (final (name, count) in vndbTags)
                              _TagOption(
                                label: name,
                                count: count,
                                selected: vndbTagFilter(name) == tagFilter,
                                onTap: () => ref
                                    .read(tagFilterProvider.notifier)
                                    .set(vndbTagFilter(name)),
                              ),
                          ],
                        ],
                      ),
                    ),
                    if (activeCount > 0) ...[
                      const _PanelDivider(),
                      Align(
                        alignment: Alignment.centerRight,
                        child: BrandGlassButton(
                          height: 36,
                          expand: false,
                          onPressed: _clearAll,
                          label: const Text('Clear all'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelSection extends StatelessWidget {
  const _PanelSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _PanelDivider extends StatelessWidget {
  const _PanelDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Divider(
        height: 1,
        thickness: 1,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }
}

/// One row of the Tags list: a check for the selected tag, its name and an
/// optional game count.
class _TagOption extends StatelessWidget {
  const _TagOption({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              child: selected
                  ? Icon(Icons.check_rounded, size: 18, color: scheme.primary)
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  color: selected ? scheme.primary : scheme.onSurface,
                ),
              ),
            ),
            if (count != null)
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ToolbarSegment extends StatelessWidget {
  const ToolbarSegment({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: enabled ? onTap : null,
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
            color: !enabled
                ? scheme.outline
                : selected
                ? scheme.primary
                : scheme.onSurfaceVariant,
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
    return ToolbarBox(
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
