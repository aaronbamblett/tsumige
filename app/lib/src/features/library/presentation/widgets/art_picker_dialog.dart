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
import '../../../../core/steamgriddb.dart';
import '../../../../core/vndb.dart';
import '../../../../utils/prefs/app_prefs.dart';
import '../../../../utils/theme/brand.dart';
import '../../../../utils/toast.dart';
import '../../../../widgets/tsumige_logo.dart';
import '../../data/library_repository.dart';
import '../../domain/cover_source.dart';
import '../../domain/add_game.dart';
import '../../domain/game_editor.dart';
import 'art_image.dart';
import 'art_overlay.dart';
import 'art_store.dart';
import 'detail_tabs/related_tab.dart';
import 'dialog_shell.dart';
import 'library_toolbar.dart';

/// Opens the Cover and Background picker over the current screen.
Future<void> showArtPickerDialog(BuildContext context, Game game) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (context) =>
        ArtPickerDialog(game: game, size: dialogShellSize(context)),
  );
}

enum _ArtTab { cover, background }

/// A pending choice, applied only by Save.
sealed class _Pick {
  const _Pick();
}

final class _RemotePick extends _Pick {
  const _RemotePick(this.art);

  final ArtCandidate art;
}

final class _FilePick extends _Pick {
  const _FilePick(this.path);

  final String path;
}

/// Background only: drop the background and fall back to the cover.
final class _ClearPick extends _Pick {
  const _ClearPick();
}

class ArtPickerDialog extends ConsumerStatefulWidget {
  const ArtPickerDialog({super.key, required this.game, required this.size});

  final Game game;
  final Size size;

  @override
  ConsumerState<ArtPickerDialog> createState() => _ArtPickerDialogState();
}

class _ArtPickerDialogState extends ConsumerState<ArtPickerDialog> {
  var _tab = _ArtTab.cover;
  _Pick? _coverPick;
  _Pick? _backgroundPick;
  ArtCandidates? _candidates;
  Future<ArtCandidates>? _art;
  var _saving = false;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.game.vndbId != null) _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _load() {
    final future = ref
        .read(vndbSearchClientProvider)
        .fetchArtCandidates(widget.game.vndbId!);
    _candidates = null;
    _art = future;
    future.then((art) {
      if (mounted) setState(() => _candidates = art);
    }, onError: (_) {});
  }

  bool get _hasBackground => widget.game.background?.isNotEmpty ?? false;

  _Pick? get _activePick =>
      _tab == _ArtTab.cover ? _coverPick : _backgroundPick;

  void _setActivePick(_Pick pick) => setState(() {
    if (_tab == _ArtTab.cover) {
      _coverPick = pick;
    } else {
      _backgroundPick = pick;
    }
  });

  void _close() => Navigator.of(context).pop();

  Future<void> _pickFile() async {
    final picked = await ref.read(coverPickerProvider)();
    if (picked == null || picked.isEmpty || !mounted) return;
    if (picked.startsWith('/run/user/')) {
      Toast(context).show(
        'That file came through the Flatpak portal. '
        'Pick it from its real location.',
      );
      return;
    }
    _setActivePick(_FilePick(picked));
  }

  Future<List<int>> _download(String url) async {
    final response = await ref
        .read(addGameHttpClientProvider)
        .get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
    }
    return response.bodyBytes;
  }

  Future<List<int>> _bytesFor(_Pick pick) => switch (pick) {
    _RemotePick(:final art) => _download(art.url),
    _FilePick(:final path) => File(path).readAsBytes(),
    _ClearPick() => throw StateError('a cleared background has no bytes'),
  };

  /// The VNDB url a pick came from, or `file` for a local file.
  String _sourceOf(_Pick pick) => switch (pick) {
    _RemotePick(:final art) => art.url,
    _FilePick() => 'file',
    _ClearPick() => throw StateError('a cleared background has no source'),
  };

  Future<void> _save() async {
    final cover = _coverPick;
    final background = _backgroundPick;
    final game = widget.game;
    if (cover == null && background == null) {
      _close();
      return;
    }
    setState(() => _saving = true);
    try {
      final coverBytes = cover == null ? null : await _bytesFor(cover);
      final backgroundBytes = background == null || background is _ClearPick
          ? null
          : await _bytesFor(background);
      if (!mounted) return;
      if (cover != null && coverBytes != null) {
        await storeCoverBytes(context, ref, game, coverBytes, _sourceOf(cover));
        if (!mounted) return;
        setState(() => _coverPick = null);
      }
      if (!mounted) return;
      if (background is _ClearPick) {
        await clearBackground(context, ref, game);
      } else if (background != null && backgroundBytes != null) {
        await storeBackgroundBytes(
          context,
          ref,
          game,
          backgroundBytes,
          _sourceOf(background),
        );
      }
      if (mounted) _close();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      Toast(context).showError("Couldn't use that image: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return DialogShell(
      frameKey: const Key('art-picker'),
      size: widget.size,
      eyebrow: 'Change art',
      title: widget.game.title,
      onClose: _close,
      closeKey: const Key('art-picker-close'),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _left()),
          _preview(context),
        ],
      ),
      footer: _footer(),
    );
  }

  Widget _left() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 0, 0),
          child: ToolbarBox(
            width: 200,
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Row(
                children: [
                  Expanded(
                    child: ToolbarSegment(
                      label: 'Cover',
                      selected: _tab == _ArtTab.cover,
                      onTap: () => setState(() => _tab = _ArtTab.cover),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: ToolbarSegment(
                      label: 'Background',
                      selected: _tab == _ArtTab.background,
                      onTap: () => setState(() => _tab = _ArtTab.background),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: Scrollbar(
            controller: _scroll,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(24, 4, 12, 20),
              child: _body(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _body() {
    if (_tab == _ArtTab.background && widget.game.vndbId == null) {
      return _note('No VNDB id, so pick a file.');
    }
    if (_tab == _ArtTab.cover && widget.game.vndbId == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _note('No VNDB id, so pick a file.'),
          _steamGridDbSection(),
        ],
      );
    }
    // One FutureBuilder for both tabs, so a tab switch keeps the snapshot.
    return FutureBuilder<ArtCandidates>(
      future: _art,
      builder: (context, snapshot) {
        final vndb = _vndbSnapshot(
          snapshot,
          background: _tab == _ArtTab.background,
        );
        if (_tab == _ArtTab.background) return vndb;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [vndb, _steamGridDbSection()],
        );
      },
    );
  }

  Widget _steamGridDbSection() => _SteamGridDbSection(
    game: widget.game,
    selectedUrl: _coverPick is _RemotePick
        ? (_coverPick as _RemotePick).art.url
        : null,
    isCurrent: _isCurrentCover,
    onPick: (art) => setState(() => _coverPick = _RemotePick(art)),
  );

  Widget _vndbSnapshot(
    AsyncSnapshot<ArtCandidates> snapshot, {
    required bool background,
  }) {
    if (snapshot.hasError) {
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Couldn't reach VNDB."),
            const SizedBox(height: 12),
            BrandGlassButton(
              height: 40,
              expand: false,
              onPressed: () => setState(_load),
              label: const Text('Try again'),
            ),
          ],
        ),
      );
    }
    final art = snapshot.data;
    if (art == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 48),
        child: Center(child: TsumigeLogoShimmer(size: 48)),
      );
    }
    return background ? _backgroundSections(art) : _coverSections(art);
  }

  Widget _note(String text) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Text(text, style: TextStyle(color: scheme.onSurfaceVariant)),
    );
  }

  Widget _coverSections(ArtCandidates art) {
    final main = art.main;
    return _section(
      'VNDB covers and packages',
      [
        ?main,
        ...art.releaseImages.where((i) => i.portrait),
        ...art.releaseImages.where((i) => !i.portrait),
      ],
      columns: 5,
      aspectRatio: 3 / 4,
      isCurrent: _isCurrentCover,
    );
  }

  Widget _backgroundSections(ArtCandidates art) {
    final main = art.main;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section(
          'VNDB screenshots',
          art.screenshots,
          columns: 3,
          aspectRatio: 440 / 340,
          isCurrent: _isCurrentBackground,
        ),
        _section(
          'VNDB artwork',
          [?main, ...art.releaseImages.where((i) => !i.portrait)],
          columns: 3,
          aspectRatio: 440 / 340,
          isCurrent: _isCurrentBackground,
        ),
      ],
    );
  }

  /// Whether [art] is the cover or background the game uses now. A game with
  /// a cover and no recorded source predates source tracking: its cover came
  /// from VNDB's main image.
  bool _isCurrentCover(ArtCandidate art) {
    final source = widget.game.coverSource;
    if (source != null) return art.url == source;
    final hasCover = widget.game.cover?.isNotEmpty ?? false;
    return hasCover && art.url == _candidates?.main?.url;
  }

  /// The pane shows the cover when no background is set.
  bool _isCurrentBackground(ArtCandidate art) => _hasBackground
      ? art.url == widget.game.backgroundSource
      : _isCurrentCover(art);

  Widget _section(
    String label,
    List<ArtCandidate> items, {
    required int columns,
    required double aspectRatio,
    required bool Function(ArtCandidate) isCurrent,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final active = _activePick;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                '${items.length}',
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: columns,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: aspectRatio,
          children: [
            for (final art in items)
              _ArtTile(
                key: ValueKey('art-${art.url}'),
                art: art,
                selected: active is _RemotePick && active.art.url == art.url,
                current: isCurrent(art),
                onTap: () => _setActivePick(_RemotePick(art)),
              ),
          ],
        ),
      ],
    );
  }

  Widget _preview(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dir = ref.watch(dataDirProvider);
    return Container(
      width: 300,
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        child: _tab == _ArtTab.cover
            ? _coverPreview(context, dir)
            : _backgroundPreview(context, dir),
      ),
    );
  }

  Widget _coverPreview(BuildContext context, DataDir dir) {
    final scheme = Theme.of(context).colorScheme;
    final pick = _coverPick;
    final cover = widget.game.cover;
    final Widget image;
    if (pick != null) {
      image = _pickImage(pick);
    } else if (cover != null && cover.isNotEmpty) {
      image = _storedImage(p.join(dir.coversOriginal.path, cover));
    } else {
      image = ColoredBox(color: scheme.surface);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'In the library',
          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: 220,
          child: AspectRatio(
            aspectRatio: 3 / 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: image,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.game.title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        Text(
          'Covers are cropped to 3:4 in the grid.',
          style: TextStyle(fontSize: 12, color: scheme.outline),
        ),
      ],
    );
  }

  Widget _backgroundPreview(BuildContext context, DataDir dir) {
    final scheme = Theme.of(context).colorScheme;
    final game = widget.game;
    final pick = _backgroundPick;
    final Widget image;
    if (pick != null && pick is! _ClearPick) {
      image = _pickImage(pick);
    } else if (pick == null && _hasBackground) {
      image = _storedImage(p.join(dir.coversBackground.path, game.background!));
    } else if (game.cover != null && game.cover!.isNotEmpty) {
      image = _storedImage(p.join(dir.coversOriginal.path, game.cover!));
    } else {
      image = ColoredBox(color: scheme.surface);
    }
    final picked =
        (pick != null && pick is! _ClearPick) ||
        (pick == null && _hasBackground);
    final original = game.vndbOriginalTitle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'In the details pane',
          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        Container(
          width: 252,
          height: 195,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              image,
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      scheme.surfaceContainer.withValues(alpha: 0),
                      scheme.surfaceContainer.withValues(alpha: 0.55),
                      scheme.surfaceContainer,
                    ],
                    stops: const [0.35, 0.62, 1.0],
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      game.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: OnImage.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        shadows: [
                          Shadow(
                            offset: Offset(0, 2),
                            blurRadius: 10,
                            color: Color(0xB3000000),
                          ),
                        ],
                      ),
                    ),
                    if (original != null &&
                        original.isNotEmpty &&
                        original != game.title)
                      Text(
                        original,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!picked) ...[
          const SizedBox(height: 10),
          Text(
            'No background picked, so the pane uses the cover.',
            style: TextStyle(fontSize: 12, color: scheme.outline),
          ),
        ],
      ],
    );
  }

  Widget _pickImage(_Pick pick) => switch (pick) {
    _RemotePick(:final art) => Image.network(
      art.thumbnail,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    ),
    _FilePick(:final path) => _storedImage(path),
    _ClearPick() => const SizedBox.shrink(),
  };

  Widget _storedImage(String path) => Image(
    image: artFileImage(
      File(path),
      version: ref.watch(artVersionProvider)(path),
    ),
    fit: BoxFit.cover,
    alignment: Alignment.topCenter,
    gaplessPlayback: true,
    errorBuilder: (_, _, _) => const SizedBox.shrink(),
  );

  Widget _footer() {
    final candidates = _candidates;
    final main = candidates?.main;
    final Widget? reset;
    if (_tab == _ArtTab.cover) {
      reset = widget.game.vndbId == null
          ? null
          : BrandGlassButton(
              height: 40,
              expand: false,
              onPressed: main == null
                  ? null
                  : () => _setActivePick(_RemotePick(main)),
              icon: const Icon(Icons.restore_rounded),
              label: const Text('Use VNDB cover'),
            );
    } else {
      reset = _hasBackground || _backgroundPick != null
          ? BrandGlassButton(
              height: 40,
              expand: false,
              onPressed: () =>
                  setState(() => _backgroundPick = const _ClearPick()),
              icon: const Icon(Icons.restore_rounded),
              label: const Text('Use the cover'),
            )
          : null;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: Row(
        children: [
          BrandGlassButton(
            height: 40,
            expand: false,
            onPressed: _pickFile,
            icon: const Icon(Icons.folder_outlined),
            label: const Text('From file…'),
          ),
          if (reset != null) ...[const SizedBox(width: 10), reset],
          const Spacer(),
          BrandGlassButton(
            height: 40,
            expand: false,
            onPressed: _close,
            label: const Text('Cancel'),
          ),
          const SizedBox(width: 10),
          BrandButton(
            height: 40,
            expand: false,
            loading: _saving,
            onPressed: _save,
            label: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

/// SteamGridDB covers on the Cover tab. Loads independently of VNDB so one
/// source never blocks the other.
class _SteamGridDbSection extends ConsumerStatefulWidget {
  const _SteamGridDbSection({
    required this.game,
    required this.selectedUrl,
    required this.isCurrent,
    required this.onPick,
  });

  final Game game;
  final String? selectedUrl;
  final bool Function(ArtCandidate) isCurrent;
  final void Function(ArtCandidate) onPick;

  @override
  ConsumerState<_SteamGridDbSection> createState() =>
      _SteamGridDbSectionState();
}

class _SteamGridDbSectionState extends ConsumerState<_SteamGridDbSection> {
  var _editingKey = false;
  late final TextEditingController _keyController;
  var _loading = false;
  String? _error;
  List<int>? _steamIds;
  List<SteamGridDbGame>? _search;
  int? _selectedSearchId;
  var _grids = const <ArtCandidate>[];
  var _loadedFor = '';

  @override
  void initState() {
    super.initState();
    _keyController = TextEditingController();
    _keyController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_SteamGridDbSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.game.id != widget.game.id) _reset();
  }

  void _reset() {
    _editingKey = false;
    _loading = false;
    _error = null;
    _steamIds = null;
    _search = null;
    _selectedSearchId = null;
    _grids = const [];
    _loadedFor = '';
  }

  Future<void> _load() async {
    final client = ref.read(steamGridDbClientProvider);
    if (client == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final game = widget.game;
      final List<int> ids;
      if (game.launch.steamAppId != null) {
        ids = [game.launch.steamAppId!];
      } else if (game.vndbId != null) {
        ids = await ref
            .read(vndbSearchClientProvider)
            .fetchSteamAppIds(game.vndbId!);
      } else {
        ids = const [];
      }
      if (!mounted) return;
      if (ids.isNotEmpty) {
        final merged = <ArtCandidate>[];
        final seen = <String>{};
        for (final id in ids) {
          for (final art in await client.gridsForSteamApp(id)) {
            if (seen.add(art.url)) merged.add(art);
          }
        }
        if (!mounted) return;
        setState(() {
          _loading = false;
          _steamIds = ids;
          _search = null;
          _grids = merged;
        });
      } else {
        final results = await client.searchGames(game.title);
        if (!mounted) return;
        final folded = normalizeGridTitle(game.title);
        int? selected;
        for (final result in results) {
          if (normalizeGridTitle(result.name) == folded) {
            selected = result.id;
            break;
          }
        }
        setState(() {
          _steamIds = const [];
          _search = results;
          _selectedSearchId = selected;
        });
        if (selected != null) {
          await _loadSearchGrids(client, selected);
        } else {
          if (mounted) {
            setState(() {
              _loading = false;
              _grids = const [];
            });
          }
        }
      }
    } on SteamGridDbBadKeyException {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'badKey';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'network';
        });
      }
    }
  }

  Future<void> _loadSearchGrids(SteamGridDbClient client, int gameId) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final grids = await client.gridsForGame(gameId);
      if (!mounted) return;
      final seen = <String>{};
      setState(() {
        _loading = false;
        _grids = [
          for (final art in grids)
            if (seen.add(art.url)) art,
        ];
      });
    } on SteamGridDbBadKeyException {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'badKey';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'network';
        });
      }
    }
  }

  void _selectSearch(int id) {
    final client = ref.read(steamGridDbClientProvider);
    if (client == null) return;
    setState(() => _selectedSearchId = id);
    unawaited(_loadSearchGrids(client, id));
  }

  void _saveKey() {
    ref.read(steamGridDbKeyProvider.notifier).set(_keyController.text);
    setState(() {
      _editingKey = false;
      _loadedFor = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final key = ref.watch(steamGridDbKeyProvider);
    final hasKey = key.trim().isNotEmpty;
    if (!hasKey && _loadedFor.isNotEmpty) {
      Future.microtask(() {
        if (mounted) setState(_reset);
      });
    }
    if (hasKey && !_editingKey) {
      final token = '${widget.game.id}|${key.trim()}';
      if (_loadedFor != token && !_loading) {
        _loadedFor = token;
        Future.microtask(_load);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'SteamGridDB',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (_gridCount() != null)
                Text(
                  '${_gridCount()}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        if (_editingKey) _keyForm(scheme),
        if (!_editingKey && !hasKey) _noKeyNote(scheme),
        if (!_editingKey && hasKey) ..._keyedBody(scheme),
      ],
    );
  }

  int? _gridCount() {
    if (_error != null || _steamIds == null && _search == null) return null;
    if (_search != null && _selectedSearchId == null) return null;
    return _grids.length;
  }

  Widget _noKeyNote(ColorScheme scheme) {
    return _DashedOutline(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Covers from SteamGridDB need your own free API key. '
              'Get one in your SteamGridDB preferences.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            BrandGlassButton(
              key: const Key('sgdb-set-key'),
              height: 40,
              expand: false,
              onPressed: () => setState(() => _editingKey = true),
              label: const Text('Set API key'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _keyForm(ColorScheme scheme) {
    return _DashedOutline(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('sgdb-key-field'),
              controller: _keyController,
              obscureText: true,
              decoration: InputDecoration(
                hintText: 'Paste your SteamGridDB API key',
                hintStyle: TextStyle(color: scheme.onSurfaceVariant),
                border: InputBorder.none,
                isDense: true,
              ),
              onSubmitted: (_) {
                if (_keyController.text.trim().isNotEmpty) _saveKey();
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  onPressed: () => ref
                      .read(vndbUrlOpenerProvider)(
                        Uri.parse(steamGridDbPreferencesUrl),
                      ),
                  child: const Text('Get a key'),
                ),
                const Spacer(),
                BrandButton(
                  key: const Key('sgdb-key-save'),
                  height: 40,
                  expand: false,
                  onPressed: _keyController.text.trim().isEmpty
                      ? null
                      : _saveKey,
                  label: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _keyedBody(ColorScheme scheme) {
    if (_error == 'badKey') {
      return [
        const Text("SteamGridDB didn't accept the key."),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: BrandGlassButton(
            key: const Key('sgdb-set-key'),
            height: 40,
            expand: false,
            onPressed: () => setState(() => _editingKey = true),
            label: const Text('Set API key'),
          ),
        ),
      ];
    }
    if (_error != null) {
      return [
        const Text("Couldn't reach SteamGridDB."),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: BrandGlassButton(
            key: const Key('sgdb-retry'),
            height: 40,
            expand: false,
            onPressed: _load,
            label: const Text('Try again'),
          ),
        ),
      ];
    }
    if (_steamIds == null && _search == null) {
      return const [
        Padding(
          padding: EdgeInsets.only(top: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TsumigeLogoShimmer(size: 32),
          ),
        ),
      ];
    }
    if (_steamIds != null && _steamIds!.isNotEmpty) {
      if (!_loading && _grids.isEmpty) {
        return const [Text('No SteamGridDB covers for this game.')];
      }
      return [_grid(scheme)];
    }
    final search = _search ?? const <SteamGridDbGame>[];
    if (search.isEmpty) {
      return const [Text('No SteamGridDB covers for this game.')];
    }
    return [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final result in search) _chip(scheme, result),
        ],
      ),
      const SizedBox(height: 10),
      if (_selectedSearchId == null)
        const Text('Pick the matching game.')
      else if (!_loading && _grids.isEmpty)
        const Text('No SteamGridDB covers for this game.')
      else
        _grid(scheme),
      if (_loading && _selectedSearchId != null && _grids.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TsumigeLogoShimmer(size: 32),
          ),
        ),
    ];
  }

  Widget _chip(ColorScheme scheme, SteamGridDbGame result) {
    final selected = result.id == _selectedSearchId;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _selectSearch(result.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Text(
          result.name,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _grid(ColorScheme scheme) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 5,
      crossAxisSpacing: 14,
      mainAxisSpacing: 14,
      childAspectRatio: 2 / 3,
      children: [
        for (final art in _grids)
          _ArtTile(
            key: ValueKey('art-${art.url}'),
            art: art,
            selected: widget.selectedUrl == art.url,
            current: widget.isCurrent(art),
            onTap: () => widget.onPick(art),
          ),
      ],
    );
  }
}

/// Dashed rounded outline for the SteamGridDB key note and key form.
class _DashedOutline extends StatelessWidget {
  const _DashedOutline({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomPaint(
      painter: _DashPainter(scheme.outlineVariant),
      child: child,
    );
  }
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(10),
        ),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const dash = 6.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var start = 0.0;
      while (start < metric.length) {
        final end = (start + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(start, end), paint);
        start += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter old) => old.color != color;
}

/// One VNDB image in a picker grid, with the grid ring and a size badge.
class _ArtTile extends StatefulWidget {
  const _ArtTile({
    super.key,
    required this.art,
    required this.selected,
    required this.current,
    required this.onTap,
  });

  final ArtCandidate art;
  final bool selected;
  final bool current;
  final VoidCallback onTap;

  @override
  State<_ArtTile> createState() => _ArtTileState();
}

class _ArtTileState extends State<_ArtTile> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final art = widget.art;
    const radius = BorderRadius.all(Radius.circular(10));
    final lit = widget.selected || _hovered;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: radius,
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: lit
                  ? scheme.primary
                  : scheme.onSurface.withValues(alpha: 0.06),
              width: widget.selected ? 3 : (_hovered ? 2 : 1),
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                art.thumbnail,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : const SizedBox.shrink(),
                errorBuilder: (_, _, _) => Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (widget.current)
                Positioned(
                  left: 6,
                  top: 6,
                  child: Container(
                    height: 22,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: ArtOverlay.button,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: ArtOverlay.buttonRing),
                    ),
                    child: const Text(
                      'Current',
                      style: TextStyle(fontSize: 11, color: OnImage.text),
                    ),
                  ),
                ),
              if (art.width > 0 && art.height > 0)
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: ArtOverlay.badge,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      child: Text(
                        '${art.width}×${art.height}',
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: OnImage.text,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
