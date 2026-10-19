// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../core/model.dart';
import '../../../../core/paths.dart';
import '../../../../core/vndb.dart';
import '../../../../utils/platform/platform_runtime.dart';
import '../../../../utils/theme/brand.dart';
import '../../../../utils/toast.dart';
import '../../../settings/presentation/sections/settings_widgets.dart';
import '../../data/library_repository.dart';
import '../../domain/add_game.dart';
import '../../domain/folder_import.dart';
import '../../domain/game_editor.dart';
import '../../domain/launch_detection.dart';
import '../../domain/runner_detection.dart';
import '../widgets/dialog_shell.dart';
import '../widgets/library_toolbar.dart';
import 'vn_result_widgets.dart';

/// How the import dialog ended. [back] returns to the Add dialog's start
/// step; [cancel] and [added] close the Add dialog too.
enum ImportFolderResult { back, cancel, added }

Future<ImportFolderResult?> showImportFolderDialog(
  BuildContext context, {
  List<String> roots = const [],
}) {
  return showDialog<ImportFolderResult>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (context) => ImportFolderDialog(roots: roots),
  );
}

String _games(int count) => count == 1 ? '1 game' : '$count games';

/// The gap between VNDB requests from one import. Overridden with zero
/// in tests so matching runs without real waiting.
final importVndbGapProvider = Provider<Duration>(
  (_) => const Duration(milliseconds: 1600),
);

/// How long a throttled (429) request waits before its retry.
final importVndbRetryWaitProvider = Provider<Duration>(
  (_) => const Duration(seconds: 60),
);

typedef _Plan = ({List<bool> selected, List<bool> duplicate});

class _ImportRow {
  _ImportRow(this.folder);

  final ImportFolder folder;

  /// Null while the VNDB lookup is pending.
  ImportMatchState? state;
  VnSearchResult? vn;
  String? error;
  String? exePath;
  bool ticked = false;
  bool tickTouched = false;
}

class ImportFolderDialog extends ConsumerStatefulWidget {
  const ImportFolderDialog({super.key, this.roots = const []});

  /// Folders to scan straight away instead of asking for one.
  final List<String> roots;

  @override
  ConsumerState<ImportFolderDialog> createState() => _ImportFolderDialogState();
}

class _ImportFolderDialogState extends ConsumerState<ImportFolderDialog> {
  final List<String> _roots = [];
  bool _hideImported = true;
  bool _scanning = false;
  List<_ImportRow> _rows = const [];
  int _scanToken = 0;
  bool _saving = false;
  int _done = 0;
  int _total = 0;

  VndbRequestQueue? _queue;

  /// Every VNDB request from this dialog, paced through one queue.
  VndbRequestQueue get _vndb {
    final queue = _queue;
    if (queue != null) return queue;
    return _queue = VndbRequestQueue(
      search: ref.read(vndbSearchClientProvider).search,
      gap: ref.read(importVndbGapProvider),
      retryWait: ref.read(importVndbRetryWaitProvider),
    );
  }

  int? _hoveredRow;

  /// The resolved library exe paths for the current library value,
  /// recomputed only when the games list instance changes so a rebuild
  /// per matched row stays cheap.
  List<Game>? _cachedGames;
  Set<String> _cachedLibraryExes = const {};

  Set<String> _libraryExes(List<Game> games) {
    if (!identical(games, _cachedGames)) {
      _cachedGames = games;
      _cachedLibraryExes = libraryRealExePaths(games);
    }
    return _cachedLibraryExes;
  }

  int? _pickIndex;
  VnSearchResult? _pickSelected;
  late final TextEditingController _pickQuery;
  Timer? _pickDebounce;
  int _pickToken = 0;
  bool _pickLoading = false;
  String? _pickError;
  List<VnSearchResult> _pickResults = const [];

  @override
  void initState() {
    super.initState();
    _pickQuery = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _roots.isNotEmpty) return;
      if (widget.roots.isEmpty) {
        _browse();
      } else {
        _scanRoots(widget.roots, append: false);
      }
    });
  }

  @override
  void dispose() {
    _scanToken++;
    _pickDebounce?.cancel();
    _pickQuery.dispose();
    super.dispose();
  }

  void _pop(ImportFolderResult result) => Navigator.of(context).pop(result);

  void _close() {
    if (_saving) return;
    _pop(ImportFolderResult.cancel);
  }

  bool _inLibrary(_ImportRow row, Set<String> libraryExes) =>
      importRowInLibrary(folder: row.folder.path, libraryExes: libraryExes);

  bool _eligible(_ImportRow row, Set<String> libraryExes) =>
      row.state != null &&
      row.exePath != null &&
      !_inLibrary(row, libraryExes);

  /// Two rows with the same real exe path stay deduplicated. A repeated
  /// VNDB id only warns, it doesn't deduplicate.
  bool _sameGame(_ImportRow a, _ImportRow b) {
    final ae = a.exePath;
    final be = b.exePath;
    return ae != null &&
        be != null &&
        p.equals(realPath(ae), realPath(be));
  }

  /// The warning when a row repeats a VNDB entry: the library game's
  /// title, or the earlier row's folder name. Null when it repeats
  /// nothing.
  String? _repeatWarning(int index, List<Game> games) {
    final id = _rows[index].vn?.id;
    if (id == null) return null;
    for (final game in games) {
      if (game.vndbId == id) return 'Same VNDB entry as ${game.title}';
    }
    for (var j = 0; j < index; j++) {
      if (_rows[j].vn?.id == id) {
        return 'Same VNDB entry as ${_rows[j].folder.name}';
      }
    }
    return null;
  }

  /// Whether [id] already names a library game or an earlier row's entry.
  /// Such rows are unticked by default, but still tickable.
  bool _vndbRepeats(String id, _ImportRow? except, List<Game> games) {
    if (games.any((game) => game.vndbId == id)) return true;
    for (final other in _rows) {
      if (identical(other, except)) break;
      if (other.vn?.id == id) return true;
    }
    return false;
  }

  /// Which rows are added, and which are duplicates of an earlier added row.
  /// The first ticked row for an exe wins.
  _Plan _plan(Set<String> libraryExes) {
    final selected = List.filled(_rows.length, false);
    final duplicate = List.filled(_rows.length, false);
    for (var i = 0; i < _rows.length; i++) {
      final row = _rows[i];
      if (!_eligible(row, libraryExes)) continue;
      for (var j = 0; j < i; j++) {
        if (selected[j] && _sameGame(_rows[j], row)) {
          duplicate[i] = true;
          break;
        }
      }
      selected[i] = row.ticked && !duplicate[i];
    }
    return (selected: selected, duplicate: duplicate);
  }

  void _applyExe(_ImportRow row) {
    final vn = row.vn;
    row.exePath = chooseExe(
      row.folder,
      vn == null ? const [] : vnTitles(vn),
    )?.path;
  }

  Future<void> _browse({bool append = false}) async {
    final picked = await ref.read(pathPickerProvider)(
      mode: PathPickMode.folder,
    );
    if (!mounted) return;
    if (picked == null || picked.isEmpty) {
      if (_roots.isEmpty) _pop(ImportFolderResult.back);
      return;
    }
    if (isPortalPath(picked)) {
      Toast(context).show(portalPathMessage);
      return;
    }
    await _scanRoots([picked], append: append);
  }

  Future<void> _scanRoots(List<String> roots, {required bool append}) async {
    final token = ++_scanToken;
    final platform = ref.read(hostPlatformProvider);
    setState(() {
      _scanning = true;
      if (!append) {
        _roots.clear();
        _rows = const [];
      }
    });
    final found = <ImportFolder>[];
    try {
      for (final root in roots) {
        found.addAll(await scanImportFolder(root, platform));
      }
    } on FileSystemException catch (e) {
      if (!mounted || token != _scanToken) return;
      setState(() => _scanning = false);
      Toast(context).showError('$e');
      return;
    }
    if (!mounted || token != _scanToken) return;
    final known = {for (final row in _rows) row.folder.path};
    final fresh = <_ImportRow>[
      for (final folder in found)
        if (known.add(folder.path)) _ImportRow(folder),
    ];
    setState(() {
      _roots.addAll(roots);
      _rows = [..._rows, ...fresh];
      for (final row in fresh) {
        _applyExe(row);
      }
      _scanning = false;
    });
    for (var i = 0; i < fresh.length; i++) {
      if (!mounted || token != _scanToken) return;
      await _match(fresh[i], token);
    }
  }

  String? _rootFor(String path) {
    for (final root in _roots) {
      if (p.equals(root, path) || p.isWithin(root, path)) return root;
    }
    return null;
  }

  Future<void> _match(_ImportRow row, int token) async {
    final query = cleanFolderName(row.folder.name);
    final exeDir = row.exePath == null
        ? row.folder.path
        : p.dirname(row.exePath!);
    final parents = parentFolderQueries(
      exeDir: exeDir,
      root: _rootFor(row.folder.path),
    );
    var match = const FolderMatch(ImportMatchState.none, null);
    String? error;
    try {
      match = await lookupFolderMatch(
        query: query,
        parentQueries: parents,
        search: _vndb.run,
      );
    } catch (e) {
      error = '$e';
      match = const FolderMatch(ImportMatchState.error, null);
    }
    if (!mounted || token != _scanToken) return;
    final games = ref.read(libraryProvider).value?.library.games ?? const [];
    setState(() {
      row.state = match.state;
      row.vn = match.vn;
      row.error = error;
      _applyExe(row);
      if (!row.tickTouched) {
        final vn = match.vn;
        row.ticked =
            match.state == ImportMatchState.matched &&
            row.exePath != null &&
            (vn == null || !_vndbRepeats(vn.id, row, games));
      }
    });
  }

  void _retryRow(_ImportRow row) {
    setState(() {
      row.state = null;
      row.error = null;
    });
    unawaited(_match(row, _scanToken));
  }

  void _openPick(int index) {
    final row = _rows[index];
    final query = cleanFolderName(row.folder.name);
    _pickQuery.text = query;
    setState(() {
      _pickIndex = index;
      _pickSelected = row.vn;
      _pickResults = const [];
      _pickError = null;
    });
    _runPickSearch(query);
  }

  void _onPickQueryChanged(String value) {
    _pickDebounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      _pickToken++;
      setState(() {
        _pickLoading = false;
        _pickError = null;
        _pickResults = const [];
      });
      return;
    }
    _pickDebounce = Timer(
      const Duration(milliseconds: 400),
      () => _runPickSearch(query),
    );
  }

  Future<void> _runPickSearch(String query) async {
    final token = ++_pickToken;
    setState(() {
      _pickLoading = true;
      _pickError = null;
    });
    List<VnSearchResult> results;
    try {
      results = rankSearchResults(await _vndb.run(query), query);
    } catch (e) {
      if (!mounted || token != _pickToken) return;
      setState(() {
        _pickLoading = false;
        _pickError = '$e';
      });
      return;
    }
    if (!mounted || token != _pickToken) return;
    setState(() {
      _pickLoading = false;
      _pickResults = results;
    });
  }

  void _leavePick() {
    _pickDebounce?.cancel();
    _pickToken++;
    setState(() {
      _pickIndex = null;
      _pickSelected = null;
    });
  }

  void _pickSelect(VnSearchResult vn) => setState(() => _pickSelected = vn);

  void _pickApply() {
    final vn = _pickSelected;
    final index = _pickIndex;
    if (vn == null || index == null) return;
    final row = _rows[index];
    final games = ref.read(libraryProvider).value?.library.games ?? const [];
    setState(() {
      row.vn = vn;
      row.state = ImportMatchState.matched;
      row.error = null;
      _applyExe(row);
      row.ticked =
          row.exePath != null && !_vndbRepeats(vn.id, row, games);
      _pickIndex = null;
      _pickSelected = null;
    });
  }

  Future<void> _add() async {
    final games = ref.read(libraryProvider).value?.library.games ?? const [];
    final plan = _plan(libraryRealExePaths(games));
    final rows = [
      for (var i = 0; i < _rows.length; i++)
        if (plan.selected[i]) _rows[i],
    ];
    if (rows.isEmpty) return;
    if (rows.any((row) => isPortalPath(row.exePath!))) {
      Toast(context).show(portalPathMessage);
      return;
    }
    final vndb = ref.read(vndbSearchClientProvider);
    final httpClient = ref.read(addGameHttpClientProvider);
    final dataDir = ref.read(dataDirProvider);
    final platform = ref.read(hostPlatformProvider);
    setState(() {
      _saving = true;
      _done = 0;
      _total = rows.length;
    });
    final built = <Game>[];
    var coverFailures = 0;
    for (final row in rows) {
      final exe = row.exePath!;
      final detected = await detectLaunchMode(exe, platform);
      final vn = row.vn;
      final Game game;
      if (vn == null) {
        game = plainGame(title: row.folder.name, exe: exe, mode: detected.mode);
        game.launch.steamAppId = detected.steamAppId;
      } else {
        final result = await buildVnGame(
          result: vn,
          title: vn.title,
          description: vn.description,
          tags: const [],
          exe: exe,
          mode: detected.mode,
          steamAppId: detected.steamAppId,
          vndb: vndb,
          httpClient: httpClient,
          dataDir: dataDir,
        );
        game = result.game;
        if (result.coverFailed) coverFailures++;
      }
      game.needsReview = row.state != ImportMatchState.matched;
      built.add(game);
      if (mounted) setState(() => _done++);
    }
    if (!mounted) return;
    await ref.read(gameEditorProvider).addAll(built, context: context);
    if (!mounted) return;
    final count = _games(built.length);
    Toast(context).show(
      coverFailures == 0
          ? 'Added $count'
          : 'Added $count ($coverFailures covers failed)',
    );
    _pop(ImportFolderResult.added);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(canPop: !_saving, child: _content(context));
  }

  Widget _content(BuildContext context) {
    final games =
        ref.watch(libraryProvider).value?.library.games ?? const <Game>[];
    final pick = _pickIndex;
    // Resolved once per library value so every row compares against the
    // same set without re-resolving symlinks on every rebuild.
    final libraryExes = _libraryExes(games);
    final plan = _plan(libraryExes);
    if (pick != null) {
      return DialogShell(
        autofocus: false,
        size: dialogShellSize(context),
        eyebrow: _rows[pick].folder.name,
        title: 'Search VNDB',
        onClose: _close,
        closeKey: const Key('import-close'),
        body: _pickBody(context, games),
        footer: _pickFooter(),
      );
    }
    return DialogShell(
      autofocus: false,
      size: dialogShellSize(context),
      eyebrow: 'Add games',
      title: 'Select games to import',
      onClose: _close,
      closeKey: const Key('import-close'),
      body: _listBody(context, games, plan, libraryExes),
      footer: _listFooter(games, plan),
    );
  }

  bool _hidden(int index, _Plan plan, Set<String> libraryExes) =>
      _hideImported &&
      (plan.duplicate[index] ||
          _inLibrary(_rows[index], libraryExes));

  Widget _listBody(
    BuildContext context,
    List<Game> games,
    _Plan plan,
    Set<String> libraryExes,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      fontSize: 13,
      color: scheme.onSurfaceVariant,
    );
    final visible = [
      for (var i = 0; i < _rows.length; i++)
        if (!_hidden(i, plan, libraryExes)) i,
    ];
    final eligible = [
      for (final i in visible)
        if (_eligible(_rows[i], libraryExes) && !plan.duplicate[i]) i,
    ];
    final allChecked =
        eligible.isNotEmpty && eligible.every((i) => plan.selected[i]);
    final headerStyle = muted?.copyWith(fontWeight: FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 40,
                      child: Checkbox(
                        key: const Key('import-check-all'),
                        value: allChecked,
                        onChanged: eligible.isEmpty || _saving
                            ? null
                            : (value) =>
                                  _setAllTicked(eligible, value ?? false),
                      ),
                    ),
                    const SizedBox(width: 48),
                    Expanded(flex: 5, child: Text('Name', style: headerStyle)),
                    const SizedBox(width: 12),
                    Expanded(flex: 6, child: Text('Path', style: headerStyle)),
                  ],
                ),
              ),
              if (_scanning) const LinearProgressIndicator(),
              if (_matching case (done: final done, total: final total))
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LinearProgressIndicator(value: done / total),
                      const SizedBox(height: 4),
                      Text(
                        'Matching with VNDB… $done of $total',
                        style: muted,
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: visible.isEmpty
                    ? Center(
                        child: Text(
                          _roots.isEmpty
                              ? 'Choose a folder to import'
                              : 'No games in this folder',
                          style: muted,
                        ),
                      )
                    : ListView.builder(
                        itemCount: visible.length,
                        itemBuilder: (context, position) => _rowWidget(
                          context,
                          visible[position],
                          games,
                          plan,
                          libraryExes,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Finished and total rows while matching runs. Null once every row
  /// has a result (or there is nothing to match), which hides the bar.
  ({int done, int total})? get _matching {
    if (_rows.isEmpty) return null;
    final done = _rows.where((row) => row.state != null).length;
    return done < _rows.length ? (done: done, total: _rows.length) : null;
  }

  void _setAllTicked(List<int> indices, bool ticked) {
    setState(() {
      for (final i in indices) {
        _rows[i]
          ..ticked = ticked
          ..tickTouched = true;
      }
    });
  }

  Widget _rowWidget(
    BuildContext context,
    int index,
    List<Game> games,
    _Plan plan,
    Set<String> libraryExes,
  ) {
    final row = _rows[index];
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final inLibrary = _inLibrary(row, libraryExes);
    final vn =
        row.state == ImportMatchState.matched ||
            (!inLibrary && row.state == ImportMatchState.check)
        ? row.vn
        : null;
    final canPick = !inLibrary && !_saving;
    final unmatched = vn == null;
    final nameText = Text(
      vn?.title ?? row.folder.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 14.5,
        fontWeight: unmatched ? FontWeight.w500 : FontWeight.w600,
        color: unmatched ? scheme.onSurfaceVariant : null,
      ),
    );
    Widget cover;
    if (row.state == null) {
      cover = Container(
        width: 36,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else if (vn != null) {
      cover = VnCoverThumb(
        imageUrl: vn.imageUrl,
        sexual: vn.imageSexual,
        width: 36,
        height: 48,
        radius: 4,
      );
    } else {
      cover = Container(
        width: 36,
        height: 48,
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: scheme.outlineVariant),
        ),
      );
    }
    return Opacity(
      opacity: inLibrary || plan.duplicate[index] ? 0.55 : 1,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hoveredRow = index),
        onExit: (_) => setState(() => _hoveredRow = null),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: Checkbox(
                  key: Key('import-check-$index'),
                  value: plan.selected[index],
                  onChanged:
                      _eligible(row, libraryExes) &&
                              !plan.duplicate[index] &&
                              !_saving
                      ? (value) => setState(() {
                          row.ticked = value ?? false;
                          row.tickTouched = true;
                        })
                      : null,
                ),
              ),
              cover,
              const SizedBox(width: 12),
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      key: Key('import-name-$index'),
                      borderRadius: BorderRadius.circular(6),
                      onTap: canPick ? () => _openPick(index) : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: nameText,
                      ),
                    ),
                    _statusRow(
                      context,
                      index,
                      row,
                      inLibrary,
                      _repeatWarning(index, games),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 6,
                child: MiddleEllipsisText(
                  text: row.exePath ?? '',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: scheme.outline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The muted status line under a row's name, with its small text button.
  /// Library rows keep their old look and show nothing here. A repeated
  /// VNDB entry reads in place of the other status text, with the badge
  /// and button staying as for the row's state.
  Widget _statusRow(
    BuildContext context,
    int index,
    _ImportRow row,
    bool inLibrary,
    String? repeatWarning,
  ) {
    if (inLibrary) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      fontSize: 12.5,
      color: scheme.onSurfaceVariant,
    );
    Widget statusText(String text) => Flexible(
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: muted,
      ),
    );
    switch (row.state) {
      case null:
        return const SizedBox.shrink();
      case ImportMatchState.none:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            statusText(repeatWarning ?? 'No matches on VNDB'),
            _statusButton(
              key: Key('import-choose-$index'),
              label: 'Choose…',
              onPressed: _saving ? null : () => _openPick(index),
            ),
          ],
        );
      case ImportMatchState.check:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _bestMatchBadge(context),
            if (repeatWarning != null) statusText(repeatWarning),
            _statusButton(
              key: Key('import-change-$index'),
              label: 'Change…',
              onPressed: _saving ? null : () => _openPick(index),
            ),
          ],
        );
      case ImportMatchState.error:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            statusText(repeatWarning ?? 'VNDB search failed'),
            _statusButton(
              key: Key('import-retry-$index'),
              label: 'Try again',
              onPressed: _saving ? null : () => _retryRow(row),
            ),
          ],
        );
      case ImportMatchState.matched:
        if (repeatWarning == null && _hoveredRow != index) {
          return const SizedBox.shrink();
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (repeatWarning != null) statusText(repeatWarning),
            if (_hoveredRow == index)
              _statusButton(
                key: Key('import-change-$index'),
                label: 'Change…',
                onPressed: _saving ? null : () => _openPick(index),
              ),
          ],
        );
    }
  }

  Widget _bestMatchBadge(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Best match',
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _statusButton({
    required Key key,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return TextButton(
      key: key,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      onPressed: onPressed,
      child: Text(label, style: const TextStyle(fontSize: 12.5)),
    );
  }

  Widget _listFooter(List<Game> games, _Plan plan) {
    final count = plan.selected.where((added) => added).length;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IntrinsicWidth(
                  child: BrandGlassButton(
                    key: const Key('import-browse'),
                    height: 40,
                    expand: false,
                    onPressed: _saving ? null : () => _browse(),
                    label: const Text('Browse…'),
                  ),
                ),
                IntrinsicWidth(
                  child: BrandGlassButton(
                    key: const Key('import-scan'),
                    height: 40,
                    expand: false,
                    onPressed: _saving ? null : () => _browse(append: true),
                    label: const Text('Scan Folder…'),
                  ),
                ),
                InkWell(
                  key: const Key('import-hide-imported'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: _saving
                      ? null
                      : () => setState(() => _hideImported = !_hideImported),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IgnorePointer(
                          child: Checkbox(
                            value: _hideImported,
                            onChanged: (_) {},
                          ),
                        ),
                        Text(
                          'Hide imported',
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          BrandButton(
            key: const Key('import-add'),
            height: 40,
            expand: false,
            onPressed: _saving || count == 0 ? null : _add,
            label: Text(_saving ? 'Adding $_done of $_total…' : 'Add Games'),
          ),
          const SizedBox(width: 10),
          BrandGlassButton(
            key: const Key('import-cancel'),
            height: 40,
            expand: false,
            onPressed: _saving ? null : _close,
            label: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _pickBody(BuildContext context, List<Game> games) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      fontSize: 13,
      color: scheme.onSurfaceVariant,
    );
    final owned = {
      for (final game in games)
        if (game.vndbId != null) game.vndbId!,
    };
    final selected = _pickSelected;
    final String? emptyText;
    if (_pickError != null) {
      emptyText = _pickError;
    } else if (_pickResults.isEmpty && !_pickLoading) {
      emptyText = 'No matches on VNDB';
    } else {
      emptyText = null;
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ToolbarBox(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 14, right: 6),
                        child: Row(
                          children: [
                            Icon(
                              Icons.search_rounded,
                              size: 20,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                key: const Key('import-pick-search'),
                                controller: _pickQuery,
                                autofocus: true,
                                textInputAction: TextInputAction.search,
                                style: const TextStyle(fontSize: 14),
                                onChanged: _onPickQueryChanged,
                                onSubmitted: (value) {
                                  _pickDebounce?.cancel();
                                  _runPickSearch(value.trim());
                                },
                                decoration: InputDecoration.collapsed(
                                  hintText: 'Search VNDB',
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
                    const SizedBox(height: 6),
                    Text(
                      'Search by title, or paste a VNDB link or ID (v12345).',
                      style: muted,
                    ),
                  ],
                ),
              ),
              if (_pickLoading) const LinearProgressIndicator(),
              Expanded(
                child: emptyText != null
                    ? Center(
                        child: Text(
                          emptyText,
                          style: muted,
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 12, 12),
                        itemCount: _pickResults.length,
                        itemBuilder: (context, index) {
                          final result = _pickResults[index];
                          final isOwned = owned.contains(result.id);
                          return GestureDetector(
                            onDoubleTap: isOwned
                                ? null
                                : () {
                                    _pickSelect(result);
                                    _pickApply();
                                  },
                            child: VnResultRow(
                              result: result,
                              owned: isOwned,
                              selected: selected?.id == result.id,
                              onPick: isOwned
                                  ? null
                                  : () => _pickSelect(result),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        Container(
          width: 260,
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: scheme.outlineVariant)),
          ),
          child: selected == null
              ? const SizedBox.shrink()
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                  child: VnDetailPanel(result: selected),
                ),
        ),
      ],
    );
  }

  Widget _pickFooter() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
    child: Row(
      children: [
        const Spacer(),
        BrandGlassButton(
          key: const Key('import-pick-cancel'),
          height: 40,
          expand: false,
          onPressed: _leavePick,
          label: const Text('Cancel'),
        ),
        const SizedBox(width: 10),
        BrandButton(
          key: const Key('import-pick-select'),
          height: 40,
          expand: false,
          onPressed: _pickSelected == null ? null : _pickApply,
          label: const Text('Select'),
        ),
      ],
    ),
  );
}
