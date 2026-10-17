// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../core/model.dart';
import '../../../../core/vndb.dart';
import '../../../../utils/theme/brand.dart';
import '../../../../utils/toast.dart';
import '../../../settings/presentation/sections/settings_widgets.dart';
import '../../data/library_repository.dart';
import '../../domain/add_game.dart';
import '../../domain/game_editor.dart';
import '../../domain/runner_detection.dart';
import '../../domain/selection.dart';
import '../widgets/dialog_shell.dart';
import '../widgets/detail_tabs/info_tab.dart';
import '../widgets/detail_tabs/launch_tab.dart';
import '../widgets/library_toolbar.dart';
import 'import_folder_dialog.dart';
import 'vn_result_widgets.dart';

Future<void> showAddGameDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (context) => const AddGameDialog(),
  );
}

class AddGameDialog extends ConsumerStatefulWidget {
  const AddGameDialog({super.key});

  @override
  ConsumerState<AddGameDialog> createState() => _AddGameDialogState();
}

class _AddGameDialogState extends ConsumerState<AddGameDialog> {
  int _step = 0;
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
    _mode = LaunchMode.proton;
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

  Future<void> _runSearch(String query) async {
    if (query.isEmpty) return;
    final token = ++_searchToken;
    final client = ref.read(vndbSearchClientProvider);
    setState(() {
      _loading = true;
      _searchError = null;
    });
    List<VnSearchResult> results;
    try {
      results = rankSearchResults(await client.search(query), query);
    } catch (e) {
      if (!mounted || token != _searchToken) return;
      setState(() {
        _loading = false;
        _searchError = '$e';
      });
      return;
    }
    if (!mounted || token != _searchToken) return;
    setState(() {
      _loading = false;
      _searched = true;
      _results = results;
    });
  }

  void _pick(VnSearchResult result) {
    _title.text = result.title;
    _description.text = result.description;
    setState(() {
      _picked = result;
      _tagList = parseTagsField(result.tags.join(', '));
      _manual = false;
      _formError = null;
      _step = 1;
    });
  }

  void _startManual() {
    _title.text = '';
    _description.text = '';
    setState(() {
      _tagList = [];
      _picked = null;
      _manual = true;
      _formError = null;
      _step = 1;
    });
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
    final picked = await ref.read(pathPickerProvider)(mode: PathPickMode.file);
    if (picked == null || picked.isEmpty || !mounted) return;
    if (isPortalPath(picked)) {
      Toast(context).show(portalPathMessage);
      return;
    }
    _exe.text = picked;
  }

  Future<void> _importFolder() async {
    final result = await showImportFolderDialog(context);
    if (!mounted || result == null || result == ImportFolderResult.back) return;
    Navigator.of(context).pop();
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
      setState(() => _formError = 'Executable is required');
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
    final searching = _step == 0;
    return DialogShell(
      frameKey: const Key('add-game-frame'),
      autofocus: false,
      size: dialogShellSize(context),
      eyebrow: 'Add game',
      title: searching ? 'Find on VNDB' : 'Set it up',
      onClose: _close,
      closeKey: const Key('add-game-close'),
      body: searching ? _searchStep(context) : _setupStep(context),
      footer: searching ? _searchFooter() : _setupFooter(),
    );
  }

  Widget _searchStep(BuildContext context) {
    final inLibrary = _libraryVndbIds();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: _searchBox(context),
        ),
        if (_loading) const LinearProgressIndicator(),
        Expanded(child: _resultsBody(context, inLibrary)),
      ],
    );
  }

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
          onPick: owned ? null : () => _pick(result),
        );
      },
    );
  }

  Widget _searchFooter() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
    child: Row(
      children: [
        BrandGlassButton(
          key: const Key('add-game-manual'),
          height: 40,
          expand: false,
          onPressed: _startManual,
          label: const Text('Add without VNDB'),
        ),
        const SizedBox(width: 10),
        BrandGlassButton(
          key: const Key('add-game-import'),
          height: 40,
          expand: false,
          onPressed: _importFolder,
          icon: const Icon(Icons.folder_outlined),
          label: const Text('Import a folder…'),
        ),
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

  Widget _setupFooter() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
    child: Row(
      children: [
        BrandGlassButton(
          key: const Key('add-game-back'),
          height: 40,
          expand: false,
          onPressed: _saving ? null : () => setState(() => _step = 0),
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
                launchFieldLabel(context, 'Executable', false),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: SettingsTextField(
                        key: const Key('add-game-exe'),
                        controller: _exe,
                        hint: "Pick the game's .exe",
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
                const SizedBox(height: 14),
                launchFieldLabel(context, 'Mode', false),
                const SizedBox(height: 6),
                LaunchModeSegment(
                  key: const Key('add-game-mode'),
                  mode: _mode,
                  onChanged: (mode) => setState(() => _mode = mode),
                ),
                if (_mode == LaunchMode.steam) ...[
                  const SizedBox(height: 14),
                  launchFieldLabel(context, 'Steam App ID', false),
                  const SizedBox(height: 6),
                  SettingsTextBox(
                    key: const Key('add-game-steam-app-id'),
                    controller: _steamAppId,
                    keyboardType: TextInputType.number,
                  ),
                ],
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
