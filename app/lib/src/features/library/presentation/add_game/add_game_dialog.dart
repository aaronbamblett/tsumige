// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../domain/drop_routing.dart';
import '../../domain/game_editor.dart';
import '../../domain/launch_detection.dart';
import '../../domain/runner_detection.dart';
import '../../domain/selection.dart';
import '../widgets/dialog_shell.dart';
import '../widgets/detail_tabs/info_tab.dart';
import '../widgets/detail_tabs/launch_tab.dart';
import '../widgets/library_toolbar.dart';
import 'import_folder_dialog.dart';
import 'vn_result_widgets.dart';

Future<void> showAddGameDialog(
  BuildContext context, {
  String? folder,
  String? file,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (context) => AddGameDialog(folder: folder, file: file),
  );
}

/// Starts adding the items dropped on the library window. Ignored while a
/// dialog is open over it.
Future<void> dropOntoLibrary(BuildContext context, List<String> paths) async {
  if (ModalRoute.of(context)?.isCurrent == false) return;
  if (paths.any(isPortalPath)) {
    Toast(context).show(portalPathMessage);
    return;
  }
  final route = routeDrop(paths, isDirectory: FileSystemEntity.isDirectorySync);
  switch (route) {
    case DropMatch(:final folder, :final file):
      await showAddGameDialog(context, folder: folder, file: file);
    case DropImport(:final roots):
      await showImportFolderDialog(context, roots: roots);
    case null:
  }
}

enum _AddStep { start, match, setup }

class AddGameDialog extends ConsumerStatefulWidget {
  const AddGameDialog({super.key, this.folder, this.file});

  /// A folder, or a game file in it, to match straight away.
  final String? folder;
  final String? file;

  @override
  ConsumerState<AddGameDialog> createState() => _AddGameDialogState();
}

class _AddGameDialogState extends ConsumerState<AddGameDialog> {
  _AddStep _step = _AddStep.start;
  _AddStep _setupBack = _AddStep.start;
  bool _matchReturnsToSetup = false;
  String? _folder;
  String _folderName = '';
  List<ExeFile> _candidates = const [];
  List<String> _skipped = const [];
  String? _bestId;
  bool _manual = false;
  late final TextEditingController _query;
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _tagInput;
  late final TextEditingController _exe;
  late final TextEditingController _steamAppId;
  late final FocusNode _tagFocus;
  List<String> _tagList = [];
  bool _addingTag = false;
  late LaunchMode _mode;
  Timer? _debounce;
  int _searchToken = 0;
  bool _loading = false;
  bool _searched = false;
  String? _searchError;
  List<VnSearchResult> _results = const [];
  VnSearchResult? _picked;
  bool _saving = false;
  String? _formError;

  @override
  void initState() {
    super.initState();
    _query = TextEditingController();
    _title = TextEditingController();
    _description = TextEditingController();
    _tagInput = TextEditingController();
    _exe = TextEditingController();
    _steamAppId = TextEditingController();
    _tagFocus = FocusNode();
    _mode = defaultLaunchMode(ref.read(hostPlatformProvider));
    final folder = widget.folder;
    if (folder != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _enterMatch(folder, file: widget.file);
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _title.dispose();
    _description.dispose();
    _tagInput.dispose();
    _exe.dispose();
    _steamAppId.dispose();
    _tagFocus.dispose();
    super.dispose();
  }

  Set<String> _libraryVndbIds() {
    final games = ref.watch(libraryProvider).value?.library.games;
    if (games == null) return const {};
    return {
      for (final game in games)
        if (game.vndbId != null) game.vndbId!,
    };
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _loading = false;
        _searched = false;
        _searchError = null;
        _results = const [];
      });
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _runSearch(query),
    );
  }

  Future<void> _runSearch(String query, {bool folderSearch = false}) async {
    if (query.isEmpty) return;
    final token = ++_searchToken;
    final client = ref.read(vndbSearchClientProvider);
    setState(() {
      _loading = true;
      _searchError = null;
    });
    List<VnSearchResult> results;
    try {
      final found = folderSearch
          ? await lookupFolder(query, client.search)
          : await client.search(query);
      results = rankSearchResults(found, query);
    } catch (e) {
      if (!mounted || token != _searchToken) return;
      setState(() {
        _loading = false;
        _searchError = '$e';
      });
      return;
    }
    if (!mounted || token != _searchToken) return;
    final best = folderSearch ? matchFolder(query, results) : null;
    final owned = {
      for (final game
          in ref.read(libraryProvider).value?.library.games ?? const <Game>[])
        if (game.vndbId != null) game.vndbId!,
    };
    final bestVn =
        best?.state == ImportMatchState.matched && !owned.contains(best!.vn?.id)
        ? best.vn
        : null;
    setState(() {
      _loading = false;
      _searched = true;
      _results = results;
      _bestId = bestVn?.id;
      if (bestVn != null) _picked = bestVn;
    });
  }

  void _pick(VnSearchResult result) => setState(() => _picked = result);

  Future<String?> _pickGameFile() async {
    final picked = await ref.read(pathPickerProvider)(mode: PathPickMode.file);
    if (picked == null || picked.isEmpty || !mounted) return null;
    if (isPortalPath(picked)) {
      Toast(context).show(portalPathMessage);
      return null;
    }
    return picked;
  }

  Future<void> _chooseFolder() async {
    final picked = await ref.read(pathPickerProvider)(
      mode: PathPickMode.folder,
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    if (isPortalPath(picked)) {
      Toast(context).show(portalPathMessage);
      return;
    }
    await _enterMatch(picked);
  }

  Future<void> _chooseGameFile() async {
    final picked = await _pickGameFile();
    if (picked == null) return;
    await _enterMatch(p.dirname(picked), file: picked);
  }

  Future<void> _enterMatch(String folder, {String? file}) async {
    final found = await scanGameFolder(folder, ref.read(hostPlatformProvider));
    if (!mounted) return;
    final name = p.basename(folder);
    final query = cleanFolderName(name);
    _exe.text = file ?? chooseExe(found, const [])?.path ?? '';
    setState(() {
      _folder = folder;
      _folderName = name;
      _candidates = found.exes;
      _skipped = found.skipped;
      _query.text = query;
      _results = const [];
      _searched = false;
      _searchError = null;
      _picked = null;
      _bestId = null;
      _manual = false;
      _matchReturnsToSetup = false;
      _formError = null;
      _step = _AddStep.match;
    });
    await _runSearch(query, folderSearch: true);
  }

  Future<void> _next() async {
    final picked = _picked;
    if (picked == null) return;
    _title.text = picked.title;
    _description.text = picked.description;
    setState(() {
      _tagList = [];
      _manual = false;
      _formError = null;
      if (!_matchReturnsToSetup) _setupBack = _AddStep.match;
      _step = _AddStep.setup;
    });
    if (!_matchReturnsToSetup) await _detectMode();
  }

  void _addWithoutVndb() {
    if (_matchReturnsToSetup) {
      setState(() => _step = _AddStep.setup);
      return;
    }
    _title.text = _folderName;
    _description.text = '';
    setState(() {
      _tagList = [];
      _picked = null;
      _manual = true;
      _formError = null;
      _setupBack = _AddStep.match;
      _step = _AddStep.setup;
    });
    _detectMode();
  }

  void _matchBack() {
    setState(() {
      _step = _matchReturnsToSetup ? _AddStep.setup : _AddStep.start;
    });
  }

  /// Sets the mode and Steam app id from the game's files, which the user
  /// can then change in the setup step.
  Future<void> _detectMode() async {
    final path = _exe.text.trim().isNotEmpty ? _exe.text.trim() : _folder;
    if (path == null) return;
    final detected = await detectLaunchMode(
      path,
      ref.read(hostPlatformProvider),
    );
    if (!mounted) return;
    setState(() {
      _mode = detected.mode;
      if (detected.steamAppId != null) {
        _steamAppId.text = '${detected.steamAppId}';
      }
    });
  }

  void _startSteam() {
    _title.text = '';
    _description.text = '';
    _exe.text = '';
    _steamAppId.text = '';
    setState(() {
      _tagList = [];
      _picked = null;
      _manual = true;
      _mode = LaunchMode.steam;
      _formError = null;
      _setupBack = _AddStep.start;
      _step = _AddStep.setup;
    });
  }

  void _findOnVndb() {
    final title = _title.text.trim();
    _query.text = title;
    setState(() {
      _matchReturnsToSetup = true;
      _picked = null;
      _bestId = null;
      _results = const [];
      _searched = false;
      _searchError = null;
      _step = _AddStep.match;
    });
    _runSearch(title);
  }

  void _addTag(String raw) {
    _tagInput.clear();
    final merged = [..._tagList];
    for (final tag in parseTagsField(raw)) {
      if (!merged.any((t) => t.toLowerCase() == tag.toLowerCase())) {
        merged.add(tag);
      }
    }
    if (merged.length != _tagList.length) {
      setState(() => _tagList = merged);
    }
    _tagFocus.requestFocus();
  }

  void _close() {
    if (_saving) return;
    Navigator.of(context).pop();
  }

  Future<void> _chooseExe() async {
    final picked = await _pickGameFile();
    if (picked == null) return;
    _exe.text = picked;
  }

  Future<void> _openImport({List<String> roots = const []}) async {
    final result = await showImportFolderDialog(context, roots: roots);
    if (!mounted || result == null || result == ImportFolderResult.back) return;
    Navigator.of(context).pop();
  }

  Future<void> _dropped(List<String> paths) async {
    if (paths.any(isPortalPath)) {
      Toast(context).show(portalPathMessage);
      return;
    }
    final route = routeDrop(
      paths,
      isDirectory: FileSystemEntity.isDirectorySync,
    );
    switch (route) {
      case DropMatch(:final folder, :final file):
        await _enterMatch(folder, file: file);
      case DropImport(:final roots):
        await _openImport(roots: roots);
      case null:
    }
  }

  Future<void> _add() async {
    if (_tagInput.text.trim().isNotEmpty) _addTag(_tagInput.text);
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _formError = 'Title is required');
      return;
    }
    final exe = _exe.text.trim();
    if (_mode != LaunchMode.steam && exe.isEmpty) {
      setState(() => _formError = 'Pick the game file');
      return;
    }
    if (exe.isNotEmpty && isPortalPath(exe)) {
      if (mounted) {
        Toast(context).show(portalPathMessage);
        setState(() => _formError = portalPathMessage);
      }
      return;
    }
    int? steamAppId;
    final steamRaw = _steamAppId.text.trim();
    if (_mode == LaunchMode.steam && steamRaw.isNotEmpty) {
      steamAppId = int.tryParse(steamRaw);
      if (steamAppId == null) {
        setState(() => _formError = 'Steam App ID must be digits.');
        return;
      }
    }
    setState(() {
      _saving = true;
      _formError = null;
    });
    final picked = _manual ? null : _picked;
    final Game game;
    var coverFailed = false;
    if (picked != null) {
      final built = await buildVnGame(
        result: picked,
        title: title,
        description: _description.text,
        tags: _tagList,
        exe: exe,
        mode: _mode,
        steamAppId: steamAppId,
        vndb: ref.read(vndbSearchClientProvider),
        httpClient: ref.read(addGameHttpClientProvider),
        dataDir: ref.read(dataDirProvider),
      );
      game = built.game;
      coverFailed = built.coverFailed;
    } else {
      game = plainGame(
        title: title,
        description: _description.text,
        tags: _tagList,
        exe: exe,
        mode: _mode,
      );
      game.launch.steamAppId = steamAppId;
    }
    if (!mounted) return;
    await ref.read(gameEditorProvider).add(game, context: context);
    ref.read(selectedGameIdProvider.notifier).select(game.id);
    if (!mounted) return;
    Toast(context).show(
      coverFailed ? 'Added $title (cover download failed)' : 'Added $title',
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(canPop: !_saving, child: _shell(context));
  }

  Widget _shell(BuildContext context) {
    return DialogShell(
      frameKey: const Key('add-game-frame'),
      autofocus: false,
      size: dialogShellSize(context),
      eyebrow: 'Add game',
      title: switch (_step) {
        _AddStep.start => 'Add a game',
        _AddStep.match => 'Match on VNDB',
        _AddStep.setup => 'Set it up',
      },
      onClose: _close,
      closeKey: const Key('add-game-close'),
      body: switch (_step) {
        _AddStep.start => _startStep(context),
        _AddStep.match => _matchStep(context),
        _AddStep.setup => _setupStep(context),
      },
      footer: switch (_step) {
        _AddStep.start => _startFooter(),
        _AddStep.match => _matchFooter(),
        _AddStep.setup => _setupFooter(),
      },
    );
  }

  Widget _startStep(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropTarget(
            onDragDone: (details) =>
                _dropped([for (final file in details.files) file.path]),
            child: Container(
              key: const Key('add-game-drop'),
              height: 220,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.folder_outlined,
                    size: 44,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Drop a game folder or game file here',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      BrandGlassButton(
                        key: const Key('add-game-choose-folder'),
                        height: 40,
                        expand: false,
                        onPressed: _chooseFolder,
                        icon: const Icon(Icons.folder_outlined),
                        label: const Text('Choose folder…'),
                      ),
                      const SizedBox(width: 10),
                      BrandGlassButton(
                        key: const Key('add-game-choose-file'),
                        height: 40,
                        expand: false,
                        onPressed: _chooseGameFile,
                        label: const Text('Choose game file…'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _startCard(
                  context,
                  key: const Key('add-game-steam'),
                  icon: Icons.sports_esports_outlined,
                  title: 'Add a Steam game',
                  subtitle: 'By Steam app ID, no folder needed',
                  onTap: _startSteam,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _startCard(
                  context,
                  key: const Key('add-game-import'),
                  icon: Icons.folder_copy_outlined,
                  title: 'Import a folder',
                  subtitle: 'Add every game in a folder',
                  onTap: () => _openImport(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _startCard(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _startFooter() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
    child: Row(
      children: [
        const Spacer(),
        BrandGlassButton(
          key: const Key('add-game-cancel'),
          height: 40,
          expand: false,
          onPressed: _close,
          label: const Text('Cancel'),
        ),
      ],
    ),
  );

  Widget _matchStep(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final inLibrary = _libraryVndbIds();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 300,
          decoration: BoxDecoration(
            border: Border(right: BorderSide(color: scheme.outlineVariant)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            child: _matchFiles(context),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _searchBox(context),
                    const SizedBox(height: 6),
                    Text(
                      'Search by title, or paste a VNDB link or ID (v12345).',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (_loading) const LinearProgressIndicator(),
              Expanded(child: _resultsBody(context, inLibrary)),
            ],
          ),
        ),
        if (_picked != null)
          Container(
            width: 260,
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: scheme.outlineVariant)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: VnDetailPanel(result: _picked!),
            ),
          ),
      ],
    );
  }

  Widget _matchFiles(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      fontSize: 13,
      color: scheme.onSurfaceVariant,
    );
    final folder = _folder ?? '';
    final exe = _exe.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        launchFieldLabel(context, 'Game folder', false),
        const SizedBox(height: 6),
        ToolbarBox(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    folder,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: launchFieldLabel(context, 'Game file', false)),
            if (_candidates.length > 1)
              Text('${_candidates.length} found', style: muted),
          ],
        ),
        const SizedBox(height: 6),
        SettingsDropdown<String>(
          key: const Key('add-game-exe-dropdown'),
          value: exe.isEmpty ? null : exe,
          hint: const Text('Pick the game file'),
          items: [
            for (final candidate in _candidates)
              DropdownMenuItem(
                value: candidate.path,
                child: Text(
                  candidate.relative,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (exe.isNotEmpty && !_candidates.any((c) => c.path == exe))
              DropdownMenuItem(
                value: exe,
                child: Text(
                  p.relative(exe, from: folder),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) => setState(() => _exe.text = value ?? ''),
        ),
        if (_skipped.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Skipped: ${_skipped.join(', ')}', style: muted),
        ],
      ],
    );
  }

  Widget _matchFooter() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
    child: Row(
      children: [
        BrandGlassButton(
          key: const Key('add-game-back'),
          height: 40,
          expand: false,
          onPressed: _matchBack,
          label: const Text('Back'),
        ),
        const SizedBox(width: 10),
        BrandGlassButton(
          key: const Key('add-game-manual'),
          height: 40,
          expand: false,
          onPressed: _addWithoutVndb,
          label: const Text('Add without VNDB'),
        ),
        const Spacer(),
        BrandGlassButton(
          key: const Key('add-game-cancel'),
          height: 40,
          expand: false,
          onPressed: _close,
          label: const Text('Cancel'),
        ),
        const SizedBox(width: 10),
        BrandButton(
          key: const Key('add-game-next'),
          height: 40,
          expand: false,
          onPressed: _picked == null ? null : _next,
          label: const Text('Next'),
        ),
      ],
    ),
  );

  Widget _searchBox(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ToolbarBox(
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
                key: const Key('add-game-search'),
                controller: _query,
                autofocus: true,
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: 14),
                onChanged: _onQueryChanged,
                onSubmitted: (value) {
                  _debounce?.cancel();
                  _runSearch(value.trim());
                },
                decoration: InputDecoration.collapsed(
                  hintText: 'Search VNDB',
                  hintStyle: TextStyle(color: scheme.outline, fontSize: 14),
                ),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _query,
              builder: (context, value, _) => value.text.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      key: const Key('add-game-search-clear'),
                      tooltip: 'Clear search',
                      visualDensity: VisualDensity.compact,
                      iconSize: 18,
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _debounce?.cancel();
                        _query.clear();
                        _onQueryChanged('');
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultsBody(BuildContext context, Set<String> inLibrary) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    if (_searchError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_searchError!, style: muted, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            BrandGlassButton(
              key: const Key('add-game-retry'),
              height: 40,
              expand: false,
              onPressed: () {
                _debounce?.cancel();
                _runSearch(_query.text.trim());
              },
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (!_searched) {
      return Center(child: Text('Type to search VNDB', style: muted));
    }
    if (_results.isEmpty && !_loading) {
      return Center(child: Text('No matches on VNDB', style: muted));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 12),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final result = _results[index];
        final owned = inLibrary.contains(result.id);
        return VnResultRow(
          result: result,
          owned: owned,
          selected: _picked?.id == result.id,
          badge: result.id == _bestId ? 'Best match' : null,
          onPick: owned ? null : () => _pick(result),
        );
      },
    );
  }

  Widget _setupFooter() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
    child: Row(
      children: [
        BrandGlassButton(
          key: const Key('add-game-back'),
          height: 40,
          expand: false,
          onPressed: _saving ? null : () => setState(() => _step = _setupBack),
          label: const Text('Back'),
        ),
        const Spacer(),
        BrandGlassButton(
          key: const Key('add-game-cancel'),
          height: 40,
          expand: false,
          onPressed: _saving ? null : _close,
          label: const Text('Cancel'),
        ),
        const SizedBox(width: 10),
        BrandButton(
          key: const Key('add-game-add'),
          height: 40,
          expand: false,
          onPressed: _saving ? null : _add,
          label: const Text('Add'),
        ),
      ],
    ),
  );

  Widget _setupStep(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final picked = _manual ? null : _picked;
    final rating = picked?.rating == null
        ? null
        : '★ ${(picked!.rating! / 10).toStringAsFixed(1)}';
    final meta = [
      if (picked != null && vnYear(picked.released).isNotEmpty)
        vnYear(picked.released),
      if (picked != null && picked.developers.isNotEmpty)
        picked.developers.join(', '),
      ?rating,
    ].join(' · ');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 300,
          decoration: BoxDecoration(
            border: Border(right: BorderSide(color: scheme.outlineVariant)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                launchFieldLabel(context, 'Cover', false),
                const SizedBox(height: 10),
                VnCoverThumb(
                  imageUrl: picked?.imageUrl,
                  sexual: picked?.imageSexual ?? 0,
                  width: 220,
                  height: 293,
                  radius: 10,
                ),
                const SizedBox(height: 12),
                Text(
                  picked?.title ?? 'New game',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (meta.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      meta,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                launchFieldLabel(context, 'Title', false),
                const SizedBox(height: 6),
                SettingsTextField(
                  key: const Key('add-game-title'),
                  controller: _title,
                ),
                const SizedBox(height: 14),
                if (_mode == LaunchMode.steam) ...[
                  launchFieldLabel(context, 'Steam app ID', false),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: SettingsTextBox(
                          key: const Key('add-game-steam-app-id'),
                          controller: _steamAppId,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 8),
                      BrandGlassButton(
                        key: const Key('add-game-find-vndb'),
                        height: 40,
                        expand: false,
                        onPressed: _findOnVndb,
                        label: const Text('Find on VNDB'),
                      ),
                    ],
                  ),
                ] else ...[
                  launchFieldLabel(context, 'Game file', false),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: SettingsTextField(
                          key: const Key('add-game-exe'),
                          controller: _exe,
                          hint: 'Pick the game file',
                        ),
                      ),
                      const SizedBox(width: 8),
                      BrandGlassButton(
                        key: const Key('add-game-exe-choose'),
                        height: 40,
                        expand: false,
                        onPressed: _chooseExe,
                        label: const Text('Choose…'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                launchFieldLabel(context, 'Mode', false),
                const SizedBox(height: 6),
                LaunchModeSegment(
                  key: const Key('add-game-mode'),
                  mode: _mode,
                  onChanged: (mode) => setState(() => _mode = mode),
                ),
                const SizedBox(height: 14),
                launchFieldLabel(context, 'Tags', false),
                const SizedBox(height: 6),
                _tagChips(context),
                if (_manual) ...[
                  const SizedBox(height: 14),
                  launchFieldLabel(context, 'Description', false),
                  const SizedBox(height: 6),
                  SettingsTextBox(
                    key: const Key('add-game-description'),
                    controller: _description,
                    minLines: 3,
                    maxLines: 5,
                    minHeight: 96,
                  ),
                ],
                if (!_manual) ...[
                  const SizedBox(height: 14),
                  Text(
                    'Description, VNDB tags and art come from VNDB. Launch '
                    'settings can be changed later in the Launch tab.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.outline,
                    ),
                  ),
                ],
                if (_formError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _formError!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _tagChips(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chipRadius = BorderRadius.circular(7);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final tag in _tagList)
          TagChip(
            label: tag,
            onRemove: () => setState(
              () => _tagList = [
                for (final t in _tagList)
                  if (t != tag) t,
              ],
            ),
          ),
        if (_addingTag)
          SizedBox(
            width: 140,
            child: Focus(
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.escape) {
                  setState(() => _addingTag = false);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: SettingsTextBox(
                key: const Key('add-game-tag-input'),
                controller: _tagInput,
                focusNode: _tagFocus,
                autofocus: true,
                hint: 'New tag',
                height: 28,
                onSubmitted: _addTag,
              ),
            ),
          )
        else
          InkWell(
            key: const Key('add-game-tag-add'),
            borderRadius: chipRadius,
            onTap: () => setState(() => _addingTag = true),
            child: Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: chipRadius,
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Text(
                '+',
                style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
              ),
            ),
          ),
      ],
    );
  }
}
