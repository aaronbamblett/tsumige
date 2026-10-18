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

import '../../../../core/launch/launch_modes.dart';
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
import '../../domain/runner_detection.dart';
import '../widgets/dialog_shell.dart';
import '../widgets/library_toolbar.dart';
import 'vn_result_widgets.dart';

/// How the import dialog ended. [back] returns to the Add dialog's search
/// step; [cancel] and [added] close the Add dialog too.
enum ImportFolderResult { back, cancel, added }

Future<ImportFolderResult?> showImportFolderDialog(BuildContext context) {
  return showDialog<ImportFolderResult>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (context) => const ImportFolderDialog(),
  );
}

const _chooseExeValue = '\u0000choose';

String _games(int count) => count == 1 ? '1 game' : '$count games';

typedef _Plan = ({List<bool> selected, List<bool> duplicate});

class _ImportRow {
  _ImportRow(this.folder);

  final ImportFolder folder;

  /// Null while the VNDB lookup is pending.
  ImportMatchState? state;
  VnSearchResult? vn;
  String? error;
  bool plain = false;
  String? exePath;
  bool exeFromUser = false;
  bool ticked = false;
  bool tickTouched = false;
}

class ImportFolderDialog extends ConsumerStatefulWidget {
  const ImportFolderDialog({super.key});

  @override
  ConsumerState<ImportFolderDialog> createState() => _ImportFolderDialogState();
}

class _ImportFolderDialogState extends ConsumerState<ImportFolderDialog> {
  String? _root;
  String _folderTag = '';
  bool _tagOn = true;
  bool _scanning = false;
  List<_ImportRow> _rows = const [];
  int _scanToken = 0;
  bool _saving = false;
  int _done = 0;
  int _total = 0;

  int? _pickIndex;
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
      if (mounted && _root == null) _chooseFolder();
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
    if (row.exeFromUser) return;
    final vn = row.vn;
    row.exePath = chooseExe(
      row.folder,
      vn == null ? const [] : vnTitles(vn),
    )?.path;
  }

  Future<void> _chooseFolder() async {
    final picked = await ref.read(pathPickerProvider)(
      mode: PathPickMode.folder,
    );
    if (!mounted) return;
    if (picked == null || picked.isEmpty) {
      if (_root == null) _pop(ImportFolderResult.back);
      return;
    }
    if (isPortalPath(picked)) {
      Toast(context).show(portalPathMessage);
      return;
    }
    await _scan(picked);
  }

  Future<void> _scan(String root) async {
    final token = ++_scanToken;
    setState(() {
      _root = root;
      _folderTag = p.basename(root);
      _rows = const [];
      _scanning = true;
    });
    final List<ImportFolder> folders;
    try {
      folders = await scanImportFolder(root, ref.read(hostPlatformProvider));
    } on FileSystemException catch (e) {
      if (!mounted || token != _scanToken) return;
      setState(() => _scanning = false);
      Toast(context).showError('$e');
      return;
    }
    if (!mounted || token != _scanToken) return;
    setState(() {
      _rows = [for (final folder in folders) _ImportRow(folder)];
      for (final row in _rows) {
        _applyExe(row);
      }
      _scanning = false;
    });
    for (var i = 0; i < _rows.length; i++) {
      if (!mounted || token != _scanToken) return;
      await _match(_rows[i], token);
      if (i + 1 < _rows.length) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
  }

  Future<void> _match(_ImportRow row, int token) async {
    var results = const <VnSearchResult>[];
    String? error;
    try {
      results = await lookupFolder(
        row.folder.name,
        ref.read(vndbSearchClientProvider).search,
      );
    } catch (e) {
      error = '$e';
    }
    if (!mounted || token != _scanToken) return;
    setState(() {
      final match = matchFolder(row.folder.name, results);
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

  Future<void> _chooseExe(_ImportRow row) async {
    final picked = await ref.read(pathPickerProvider)(
      initialDirectory: row.folder.path,
      mode: PathPickMode.file,
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    if (isPortalPath(picked)) {
      Toast(context).show(portalPathMessage);
      return;
    }
    setState(() {
      row.exePath = picked;
      row.exeFromUser = true;
    });
  }

  void _openPick(int index) {
    final name = _rows[index].folder.name;
    _pickQuery.text = name;
    setState(() {
      _pickIndex = index;
      _pickResults = const [];
      _pickError = null;
    });
    _runPickSearch(name);
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
    setState(() => _pickIndex = null);
  }

  void _pickResult(VnSearchResult vn) {
    final row = _rows[_pickIndex!];
    setState(() {
      row.vn = vn;
      row.state = ImportMatchState.matched;
      row.error = null;
      row.plain = false;
      _applyExe(row);
      row.ticked = row.exePath != null;
      _pickIndex = null;
    });
  }

  void _useFolderName() {
    final row = _rows[_pickIndex!];
    setState(() {
      row.vn = null;
      row.state = ImportMatchState.none;
      row.error = null;
      row.plain = true;
      _applyExe(row);
      row.ticked = row.exePath != null;
      _pickIndex = null;
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
    final tags = _tagOn ? [_folderTag] : const <String>[];
    final mode = defaultLaunchMode(ref.read(hostPlatformProvider));
    setState(() {
      _saving = true;
      _done = 0;
      _total = rows.length;
    });
    final built = <Game>[];
    var coverFailures = 0;
    for (final row in rows) {
      final exe = row.exePath!;
      final vn = row.vn;
      if (vn == null) {
        built.add(
          plainGame(title: row.folder.name, tags: tags, exe: exe, mode: mode),
        );
      } else {
        final result = await buildVnGame(
          result: vn,
          title: vn.title,
          description: vn.description,
          tags: tags,
          exe: exe,
          mode: mode,
          steamAppId: null,
          vndb: vndb,
          httpClient: httpClient,
          dataDir: dataDir,
        );
        built.add(result.game);
        if (result.coverFailed) coverFailures++;
      }
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
        eyebrow: 'Import a folder · ${_rows[pick].folder.name}',
        title: 'Pick the VNDB entry',
        onClose: _close,
        closeKey: const Key('import-close'),
        body: _pickBody(context, games, _rows[pick]),
        footer: _pickFooter(),
      );
    }
    return DialogShell(
      autofocus: false,
      size: dialogShellSize(context),
      eyebrow: 'Add games',
      title: 'Import a folder',
      onClose: _close,
      closeKey: const Key('import-close'),
      body: _listBody(context, games, plan),
      footer: _listFooter(games, plan),
    );
  }

  Widget _listBody(BuildContext context, List<Game> games, _Plan plan) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      fontSize: 13,
      color: scheme.onSurfaceVariant,
    );
    final selected = plan.selected.where((added) => added).length;
    final String emptyText;
    if (_root == null) {
      emptyText = 'Choose a folder to import';
    } else {
      emptyText = 'No subfolders in this folder';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: Row(
            children: [
              Expanded(
                child: ToolbarBox(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        Icon(
                          Icons.folder_outlined,
                          size: 18,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _root ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              BrandGlassButton(
                key: const Key('import-choose'),
                height: 40,
                expand: false,
                onPressed: _saving ? null : _chooseFolder,
                label: const Text('Choose…'),
              ),
            ],
          ),
        ),
        if (_root != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
            child: Row(
              children: [
                Text(
                  '${_rows.length} folders · $selected selected',
                  style: muted,
                ),
                const Spacer(),
                Text('Tag each game', style: muted),
                const SizedBox(width: 8),
                _tagChip(context),
              ],
            ),
          ),
        if (_scanning) const LinearProgressIndicator(),
        Expanded(
          child: _rows.isEmpty
              ? Center(child: Text(emptyText, style: muted))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                  itemCount: _rows.length,
                  itemBuilder: (context, index) =>
                      _rowWidget(context, index, games, plan),
                ),
        ),
      ],
    );
  }

  Widget _tagChip(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      key: const Key('import-tag-chip'),
      borderRadius: BorderRadius.circular(7),
      onTap: () => setState(() => _tagOn = !_tagOn),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _tagOn ? scheme.primaryContainer : null,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: _tagOn ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: Text(
          _folderTag,
          style: TextStyle(
            fontSize: 12.5,
            color: _tagOn ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
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
    final pending = row.state == null;
    final vn = row.vn;
    final unmatched = vn == null && !row.plain && !pending;
    final title = vn?.title ?? (unmatched ? 'No VNDB match' : row.folder.name);

    final (String label, Color background, Color foreground) = inLibrary
        ? (
            'In library',
            scheme.onSurface.withValues(alpha: 0.06),
            scheme.onSurfaceVariant,
          )
        : plan.duplicate[index]
        ? (
            'Duplicate',
            scheme.onSurface.withValues(alpha: 0.04),
            scheme.outline,
          )
        : pending
        ? (
            'Matching…',
            scheme.onSurface.withValues(alpha: 0.04),
            scheme.outline,
          )
        : row.plain
        ? ('No VNDB', scheme.onSurface.withValues(alpha: 0.04), scheme.outline)
        : switch (row.state!) {
            ImportMatchState.matched => (
              'Matched',
              scheme.onSurface.withValues(alpha: 0.06),
              scheme.onSurfaceVariant,
            ),
            ImportMatchState.check => (
              'Check match',
              scheme.primaryContainer,
              scheme.primary,
            ),
            ImportMatchState.none => (
              'No match',
              scheme.onSurface.withValues(alpha: 0.04),
              scheme.outline,
            ),
          };
    Widget pill = Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
    if (row.error != null) {
      pill = Tooltip(message: row.error!, child: pill);
    }

    return Opacity(
      opacity: inLibrary ? 0.55 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Checkbox(
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
            const SizedBox(width: 6),
            if (vn != null)
              VnCoverThumb(
                imageUrl: vn.imageUrl,
                sexual: vn.imageSexual,
                width: 42,
                height: 56,
                radius: 6,
              )
            else
              Container(
                width: 42,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: scheme.outline,
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: unmatched ? FontWeight.w500 : FontWeight.w600,
                      color: unmatched ? scheme.outline : null,
                    ),
                  ),
                  Row(
                    children: [
                      Icon(
                        Icons.folder_outlined,
                        size: 13,
                        color: scheme.outline,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          row.folder.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: scheme.outline),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            pill,
            const SizedBox(width: 10),
            SizedBox(
              width: 96,
              child: pending || inLibrary
                  ? null
                  : Align(
                      alignment: Alignment.centerRight,
                      child: BrandGlassButton(
                        key: Key('import-change-$index'),
                        height: 32,
                        expand: false,
                        onPressed: _saving ? null : () => _openPick(index),
                        label: Text(vn == null ? 'Find' : 'Change'),
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 220,
              child: SettingsDropdown<String>(
                key: Key('import-exe-$index'),
                value: row.exePath,
                hint: const Text("Pick the game file"),
                items: [
                  for (final exe in row.folder.exes)
                    DropdownMenuItem(
                      value: exe.path,
                      child: Text(
                        exe.relative,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (row.exePath != null &&
                      !row.folder.exes.any((e) => e.path == row.exePath))
                    DropdownMenuItem(
                      value: row.exePath,
                      child: Text(
                        p.relative(row.exePath!, from: row.folder.path),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  const DropdownMenuItem(
                    value: _chooseExeValue,
                    child: Text('Choose…'),
                  ),
                ],
                onChanged: (value) {
                  if (_saving) return;
                  if (value == _chooseExeValue) {
                    _chooseExe(row);
                    return;
                  }
                  setState(() {
                    row.exePath = value;
                    row.exeFromUser = true;
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _listFooter(List<Game> games, _Plan plan) {
    final count = plan.selected.where((added) => added).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: Row(
        children: [
          BrandGlassButton(
            key: const Key('import-back'),
            height: 40,
            expand: false,
            onPressed: _saving ? null : () => _pop(ImportFolderResult.back),
            label: const Text('Back'),
          ),
          const Spacer(),
          BrandGlassButton(
            key: const Key('import-cancel'),
            height: 40,
            expand: false,
            onPressed: _saving ? null : _close,
            label: const Text('Cancel'),
          ),
          const SizedBox(width: 10),
          BrandButton(
            key: const Key('import-add'),
            height: 40,
            expand: false,
            onPressed: _saving || count == 0 ? null : _add,
            label: Text(
              _saving ? 'Adding $_done of $_total…' : 'Add ${_games(count)}',
            ),
          ),
        ],
      ),
    );
  }

  Widget _pickBody(BuildContext context, List<Game> games, _ImportRow row) {
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
    final current = row.vn?.id;
    final String? emptyText;
    if (_pickError != null) {
      emptyText = _pickError;
    } else if (_pickResults.isEmpty && !_pickLoading) {
      emptyText = 'No matches on VNDB';
    } else {
      emptyText = null;
    }
    return Column(
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
                'Search by title, or paste a VNDB id or link (v12345).',
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
                    return VnResultRow(
                      result: result,
                      owned: isOwned,
                      current: result.id == current,
                      onPick: isOwned ? null : () => _pickResult(result),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _pickFooter() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
    child: Row(
      children: [
        BrandGlassButton(
          key: const Key('import-pick-back'),
          height: 40,
          expand: false,
          onPressed: _leavePick,
          label: const Text('Back'),
        ),
        const SizedBox(width: 10),
        BrandGlassButton(
          key: const Key('import-pick-plain'),
          height: 40,
          expand: false,
          onPressed: _useFolderName,
          label: const Text('Use folder name, no VNDB'),
        ),
        const Spacer(),
        BrandGlassButton(
          key: const Key('import-cancel'),
          height: 40,
          expand: false,
          onPressed: _close,
          label: const Text('Cancel'),
        ),
      ],
    ),
  );
}
