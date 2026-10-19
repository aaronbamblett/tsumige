// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:window_manager/window_manager.dart';

import '../../../../constants/pref_keys.dart' as keys;
import '../../../../core/model.dart' show Developer;
import '../../../../utils/platform/platform_runtime.dart';
import '../../../../widgets/desktop/desktop_title_bar.dart';
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
  keys.SortField.vndbRating: 'VNDB rating',
};

const Map<keys.AdultFilter, String> adultFilterLabels = {
  keys.AdultFilter.all: 'All games',
  keys.AdultFilter.hide: 'Hide adult',
  keys.AdultFilter.only: 'Adult only',
};

const double _kControlHeight = 40;
const double _kGap = 10;
const double _kSegmentsWidth = 170;
const double _kSearchMinWidth = 200;
const double _kAddWidth = 104;
const double _kRightInset = 12;
const double _kPanelWidth = 360;

/// Sort menu chrome: the left/right padding around its row.
const double _kSortPadLeft = 14;
const double _kSortPadRight = 10;

/// Filter box chrome: the left/right padding around its row, and the gap
/// between the badge and the chevron.
const double _kFilterPadLeft = 14;
const double _kFilterPadRight = 10;
const double _kFilterBadgeGap = 4;

/// Outline width [ToolbarBox] paints inside its box; the interior the row
/// lays out in is narrower by twice this.
const double _kToolbarBorder = 1;

/// Chrome sizes inside the sort and Filter boxes.
const double _kRowIconSize = 18;
const double _kChevronSize = 22;
const double _kDividerWidth = 1;
const double _kBadgeSize = 18;

/// Intrinsic width of [text] in the ambient style, including the text
/// scaler: the same style the toolbar labels render with.
double _labelWidth(BuildContext context, String text) {
  final style = DefaultTextStyle.of(context).style;
  final scaler = MediaQuery.textScalerOf(context);
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
  )..layout();
  return painter.width;
}

/// Width of the sort control: the smallest width fitting the longest label
/// in [sortFieldLabels], measured in the ambient text style. Fixed across
/// sort fields, so the control never jumps when the sort changes.
double sortBoxWidth(BuildContext context) {
  var widest = 0.0;
  for (final label in sortFieldLabels.values) {
    widest = math.max(widest, _labelWidth(context, label));
  }
  return (_kSortPadLeft +
          _kRowIconSize +
          _kGap +
          widest +
          _kChevronSize +
          _kSortPadRight +
          _kDividerWidth +
          _kControlHeight +
          2 * _kToolbarBorder)
      .ceilToDouble();
}

/// Width of the Filter control: icon, gap, "Filter", gap, badge, chevron
/// and the outer padding, measured at runtime. The badge slot is always
/// reserved (an empty box while no filter is set), so the width never
/// shifts when a filter turns on. The badge itself is a fixed 18 px circle;
/// the widest count the code can show is 3 (one each for tag, adult and
/// developer), formatted as '$count', so a single digit that always fits
/// the circle.
double filterBoxWidth(BuildContext context) {
  return (_kFilterPadLeft +
          _kRowIconSize +
          _kGap +
          _labelWidth(context, 'Filter') +
          _kGap +
          _kBadgeSize +
          _kFilterBadgeGap +
          _kChevronSize +
          _kFilterPadRight +
          2 * _kToolbarBorder)
      .ceilToDouble();
}

/// Width of the right group: Add, a gap, then Settings.
const double _kRightGroupWidth = _kAddWidth + _kGap + _kControlHeight;

/// Width the left group needs with the search box at its minimum.
double leftGroupMinWidth(BuildContext context) =>
    _kSearchMinWidth +
    sortBoxWidth(context) +
    _kSegmentsWidth +
    filterBoxWidth(context) +
    3 * _kGap;

/// Height of the merged title/toolbar bar: the toolbar's height.
const double kLibraryTopBarHeight = 64;

/// Width of the minimise / maximise-restore / close cluster: three buttons at
/// window_manager's 46 px minimum width each.
const double kWindowButtonsWidth = 3 * 46;

/// Left inset on macOS: clears the native traffic lights, which AppKit keeps
/// at the top-left of the window when the title bar is hidden. window_manager
/// 0.5.2 has no API to reposition them (its macOS `setTitleBarStyle` only
/// shows or hides the buttons), and the default position sits low in a 64 px
/// bar, so the merged bar starts its controls past them instead.
const double kMacOSTrafficLightsInset = 80;

/// Pixel width of the brand group (logo + gap + name) in [context]'s theme.
double brandGroupWidth(BuildContext context) {
  final text = TextPainter(
    text: TextSpan(text: 'Tsumige', style: brandNameStyle(context)),
    textDirection: TextDirection.ltr,
  )..layout();
  return kBrandLogoSize + kBrandGap + text.width;
}

/// Window width at and above which the title bar and the toolbar merge into
/// one 64 px bar. Below it the two rows stack as before. Built from the same
/// widths and gaps as the bars themselves: the left inset, the brand group
/// (or the macOS traffic-lights inset), the left group's minimum, the right
/// group, the window buttons (not macOS) and one [_kGap] between each part.
double oneBarBreakpoint(BuildContext context, {required bool isMacOS}) {
  final leftMin = leftGroupMinWidth(context);
  if (isMacOS) {
    return kMacOSTrafficLightsInset +
        _kGap * 2 +
        leftMin +
        _kGap +
        _kRightGroupWidth +
        _kRightInset;
  }
  return LibraryGrid.horizontalPadding +
      brandGroupWidth(context) +
      _kGap * 2 +
      leftMin +
      _kGap +
      _kRightGroupWidth +
      _kGap +
      kWindowButtonsWidth;
}

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
    return SizedBox(
      height: 64,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sortWidth = sortBoxWidth(context);
          final filterWidth = filterBoxWidth(context);
          final leftMin = leftGroupMinWidth(context);
          final leftEnd = math.min(
            gridRight,
            constraints.maxWidth - _kRightInset - _kRightGroupWidth - _kGap,
          );
          final leftWidth = math.max(
            leftEnd - LibraryGrid.horizontalPadding,
            leftMin,
          );
          return Stack(
            children: [
              Positioned(
                left: LibraryGrid.horizontalPadding,
                top: 0,
                bottom: 0,
                width: leftWidth,
                child: _LeftGroup(
                  sortWidth: sortWidth,
                  filterWidth: filterWidth,
                ),
              ),
              Positioned(
                right: _kRightInset,
                top: 0,
                bottom: 0,
                child: _RightGroup(),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The library screen's top: one 64 px bar merging the title bar and the
/// toolbar when the window is wide enough, otherwise today's two rows — the
/// plain title bar with the toolbar below it.
class LibraryTopBar extends ConsumerWidget {
  const LibraryTopBar({super.key, required this.gridRight});

  final double gridRight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMacOS = ref.watch(hostPlatformProvider).isMacOS;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >=
            oneBarBreakpoint(context, isMacOS: isMacOS)) {
          return _MergedLibraryBar(gridRight: gridRight, isMacOS: isMacOS);
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DesktopTitleBar(),
            LibraryToolbar(gridRight: gridRight),
          ],
        );
      },
    );
  }
}

/// The merged 64 px bar: the title bar's `surface` background with the brand,
/// the toolbar's left group (search absorbing the slack, ending at
/// [gridRight]), the Add/Settings group and the window buttons. A
/// [DragToMoveArea] sits behind the controls, so every empty part drags the
/// window and double-clicking it maximises/restores, as the title bar does.
class _MergedLibraryBar extends ConsumerWidget {
  const _MergedLibraryBar({required this.gridRight, required this.isMacOS});

  final double gridRight;
  final bool isMacOS;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Container(
      height: kLibraryTopBarHeight,
      color: theme.colorScheme.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          // Where the left group starts: past the brand on Linux/Windows,
          // past the traffic-lights inset on macOS.
          final leftStart = isMacOS
              ? kMacOSTrafficLightsInset + _kGap * 2
              : LibraryGrid.horizontalPadding +
                    brandGroupWidth(context) +
                    _kGap * 2;
          // What the right side reserves: Add/Settings plus the window
          // buttons on Linux/Windows, Add/Settings plus the edge inset on
          // macOS.
          final sortWidth = sortBoxWidth(context);
          final filterWidth = filterBoxWidth(context);
          final leftMin = leftGroupMinWidth(context);
          final rightReserved = isMacOS
              ? _kRightInset + _kRightGroupWidth
              : kWindowButtonsWidth + _kGap + _kRightGroupWidth;
          final leftEnd = math.min(
            gridRight,
            maxWidth - rightReserved - _kGap,
          );
          final leftWidth = math.max(
            leftEnd - leftStart,
            leftMin,
          );
          return Stack(
            children: [
              const Positioned.fill(
                child: DragToMoveArea(child: SizedBox.expand()),
              ),
              if (!isMacOS)
                Positioned(
                  left: LibraryGrid.horizontalPadding,
                  top: 0,
                  bottom: 0,
                  child: const IgnorePointer(child: DesktopBrandTitle()),
                ),
              Positioned(
                left: leftStart,
                top: 0,
                bottom: 0,
                width: leftWidth,
                child: _LeftGroup(
                  sortWidth: sortWidth,
                  filterWidth: filterWidth,
                ),
              ),
              Positioned(
                right: isMacOS ? _kRightInset : kWindowButtonsWidth + _kGap,
                top: 0,
                bottom: 0,
                child: _RightGroup(),
              ),
              if (!isMacOS)
                Align(
                  alignment: Alignment.centerRight,
                  child: DesktopWindowButtons(brightness: theme.brightness),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Search, sort, All/Favourites and Filter in one row; the search box absorbs
/// any slack.
class _LeftGroup extends ConsumerWidget {
  const _LeftGroup({required this.sortWidth, required this.filterWidth});

  final double sortWidth;
  final double filterWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final field = ref.watch(sortFieldProvider);
    final ascending = ref.watch(sortAscendingProvider);
    final favouritesOnly = ref.watch(favouritesOnlyProvider);
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        const Expanded(child: _ToolbarSearchField()),
        const SizedBox(width: _kGap),
        ToolbarBox(
          width: sortWidth,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _SortMenu(
                  field: field,
                  menuMinWidth: sortWidth,
                  onSelected: (value) =>
                      ref.read(sortFieldProvider.notifier).set(value),
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
        _FilterButton(width: filterWidth),
      ],
    );
  }
}

/// Add and Settings, pinned right.
class _RightGroup extends StatelessWidget {
  const _RightGroup();

  @override
  Widget build(BuildContext context) {
    return Row(
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
            width: _kToolbarBorder,
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
  const _SortMenu(
      {required this.field, required this.menuMinWidth, required this.onSelected});

  final keys.SortField field;
  final double menuMinWidth;
  final ValueChanged<keys.SortField> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MenuAnchor(
      style: MenuStyle(
        minimumSize: WidgetStatePropertyAll(Size(menuMinWidth, 0)),
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
          padding: const EdgeInsets.only(
            left: _kSortPadLeft,
            right: _kSortPadRight,
          ),
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
  const _FilterButton({required this.width});

  final double width;

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
          width: widget.width,
          borderColor: count > 0 ? scheme.primary : null,
          child: InkWell(
            focusNode: _focus,
            onTap: () => _controller.isShowing ? _close() : _controller.show(),
            child: Padding(
              padding: const EdgeInsets.only(
                left: _kFilterPadLeft,
                right: _kFilterPadRight,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.filter_list_rounded,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: _kGap),
                  // Loose fit: the label keeps its intrinsic width, which
                  // the measured box fits; ellipsis is only a guard.
                  const Flexible(
                    child: Text(
                      'Filter',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: _kGap),
                  if (count > 0)
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
                    )
                  else
                    const SizedBox(width: 18),
                  const SizedBox(width: _kFilterBadgeGap),
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

void clearAllFilters(WidgetRef ref) {
  ref.read(tagFilterProvider.notifier).set(null);
  ref.read(adultFilterProvider.notifier).set(keys.AdultFilter.all);
  ref.read(developerFilterProvider.notifier).set(null);
}

class ActiveFilterChips extends ConsumerWidget {
  const ActiveFilterChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tag = ref.watch(tagFilterProvider);
    final adult = ref.watch(adultFilterProvider);
    final developer = ref.watch(developerFilterProvider);
    if (tag == null && adult == keys.AdultFilter.all && developer == null) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LibraryGrid.horizontalPadding,
        4,
        LibraryGrid.horizontalPadding,
        4,
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (developer != null)
            TagChip(
              label: 'Developer: ${developer.name}',
              onRemove: () =>
                  ref.read(developerFilterProvider.notifier).set(null),
            ),
          if (tag != null)
            TagChip(
              // Stored VNDB filters carry a `vndb:` prefix; show the bare name.
              label: tag.startsWith(vndbTagPrefix)
                  ? tag.substring(vndbTagPrefix.length)
                  : tag,
              onRemove: () => ref.read(tagFilterProvider.notifier).set(null),
            ),
          if (adult != keys.AdultFilter.all)
            TagChip(
              label: adultFilterLabels[adult]!,
              onRemove: () => ref
                  .read(adultFilterProvider.notifier)
                  .set(keys.AdultFilter.all),
            ),
          TextButton(
            key: const ValueKey('active-filters-clear'),
            style: TextButton.styleFrom(foregroundColor: scheme.primary),
            onPressed: () => clearAllFilters(ref),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
  }
}

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

  void _clearAll() => clearAllFilters(ref);

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
