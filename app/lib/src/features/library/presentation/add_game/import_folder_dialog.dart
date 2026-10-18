// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../core/model.dart';
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

  bool _inLibrary(_ImportRow row, List<Game> games) {
    final exe = row.exePath;
    final id = row.vn?.id;
    return games.any(
      (g) =>
          (exe != null && g.launch.executable == exe) ||
          (id != null && g.vndbId == id),
    );
  }

  bool _eligible(_ImportRow row, List<Game> games) =>
      row.state != null && row.exePath != null && !_inLibrary(row, games);

  bool _sameGame(_ImportRow a, _ImportRow b) =>
      a.exePath == b.exePath || (a.vn != null && a.vn!.id == b.vn?.id);

  /// Which rows are added, and which are duplicates of an earlier added row.
  /// The first ticked row for a VNDB id or exe wins.
  _Plan _plan(List<Game> games) {
    final selected = List.filled(_rows.length, false);
    final duplicate = List.filled(_rows.length, false);
    for (var i = 0; i < _rows.length; i++) {
      final row = _rows[i];
      if (!_eligible(row, games)) continue;
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
      if (i + 1 < fresh.length) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
  }

  Future<void> _match(_ImportRow row, int token) async {
    final query = cleanFolderName(row.folder.name);
    var results = const <VnSearchResult>[];
    String? error;
    try {
      results = await lookupFolder(
        query,
        ref.read(vndbSearchClientProvider).search,
      );
    } catch (e) {
      error = '$e';
    }
    if (!mounted || token != _scanToken) return;
    setState(() {
      final match = matchFolder(query, results);
      row.state = match.state;
      row.vn = match.vn;
      row.error = error;
      _applyExe(row);
      if (!row.tickTouched) {
        row.ticked =
            match.state == ImportMatchState.matched && row.exePath != null;
      }
    });
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
      results = rankSearchResults(
        await ref.read(vndbSearchClientProvider).search(query),
        query,
      );
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
    setState(() {
      row.vn = vn;
      row.state = ImportMatchState.matched;
      row.error = null;
      _applyExe(row);
      row.ticked = row.exePath != null;
      _pickIndex = null;
      _pickSelected = null;
    });
  }

  Future<void> _add() async {
    final games = ref.read(libraryProvider).value?.library.games ?? const [];
    final plan = _plan(games);
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
    final plan = _plan(games);
    if (pick != null) {
      return DialogShell(
        autofocus: false,
        size: dialogShellSize(context),
        eyebrow: _rows[pick].folder.name,
        title: 'Select item',
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
      body: _listBody(context, games, plan),
      footer: _listFooter(games, plan),
    );
  }

  bool _hidden(int index, List<Game> games, _Plan plan) =>
      _hideImported &&
      (plan.duplicate[index] || _inLibrary(_rows[index], games));

  Widget _listBody(BuildContext context, List<Game> games, _Plan plan) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      fontSize: 13,
      color: scheme.onSurfaceVariant,
    );
    final visible = [
      for (var i = 0; i < _rows.length; i++)
        if (!_hidden(i, games, plan)) i,
    ];
    final eligible = [
      for (final i in visible)
        if (_eligible(_rows[i], games) && !plan.duplicate[i]) i,
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
                        itemBuilder: (context, position) =>
                            _rowWidget(context, visible[position], games, plan),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
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
  ) {
    final row = _rows[index];
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final inLibrary = _inLibrary(row, games);
    final vn = row.state == ImportMatchState.matched ? row.vn : null;
    final canPick = !inLibrary && !_saving;
    final unmatched = vn == null;
    Widget nameText = Text(
      vn?.title ?? row.folder.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 14.5,
        fontWeight: unmatched ? FontWeight.w500 : FontWeight.w600,
        color: unmatched ? scheme.onSurfaceVariant : null,
      ),
    );
    if (row.error != null) {
      nameText = Tooltip(message: row.error!, child: nameText);
    }
    return Opacity(
      opacity: inLibrary || plan.duplicate[index] ? 0.55 : 1,
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
                    _eligible(row, games) && !plan.duplicate[index] && !_saving
                    ? (value) => setState(() {
                        row.ticked = value ?? false;
                        row.tickTouched = true;
                      })
                    : null,
              ),
            ),
            if (vn != null)
              VnCoverThumb(
                imageUrl: vn.imageUrl,
                sexual: vn.imageSexual,
                width: 36,
                height: 48,
                radius: 4,
              )
            else
              Container(
                width: 36,
                height: 48,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: scheme.outlineVariant),
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              flex: 5,
              child: InkWell(
                key: Key('import-name-$index'),
                borderRadius: BorderRadius.circular(6),
                onTap: canPick ? () => _openPick(index) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: nameText,
                ),
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
    );
  }

  Widget _listFooter(List<Game> games, _Plan plan) {
    final count = plan.selected.where((added) => added).length;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: IntrinsicWidth(
              child: Row(
                children: [
                  BrandGlassButton(
                    key: const Key('import-browse'),
                    height: 40,
                    expand: false,
                    onPressed: _saving ? null : () => _browse(),
                    label: const Text('Browse…'),
                  ),
                  const SizedBox(width: 10),
                  BrandGlassButton(
                    key: const Key('import-scan'),
                    height: 40,
                    expand: false,
                    onPressed: _saving ? null : () => _browse(append: true),
                    label: const Text('Scan Folder…'),
                  ),
                  const SizedBox(width: 16),
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
                  const Spacer(),
                  BrandButton(
                    key: const Key('import-add'),
                    height: 40,
                    expand: false,
                    onPressed: _saving || count == 0 ? null : _add,
                    label: Text(
                      _saving ? 'Adding $_done of $_total…' : 'Add Games',
                    ),
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
            ),
          ),
        ),
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
