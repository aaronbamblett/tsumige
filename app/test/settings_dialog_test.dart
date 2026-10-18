// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumige/src/core/covers.dart' as core;
import 'package:tsumige/src/core/launch/detect.dart' as detect;
import 'package:tsumige/src/core/model.dart' as core;
import 'package:tsumige/src/core/paths.dart' as core;
import 'package:tsumige/src/constants/pref_keys.dart' as keys;
import 'package:tsumige/src/core/store.dart' as core;
import 'package:tsumige/src/core/vndb.dart' as core;
import 'package:tsumige/src/features/library/data/library_repository.dart';
import 'package:tsumige/src/features/library/domain/game_editor.dart';
import 'package:tsumige/src/features/library/domain/runner_detection.dart';
import 'package:tsumige/src/features/library/presentation/widgets/library_toolbar.dart';
import 'package:tsumige/src/features/settings/presentation/sections/settings_widgets.dart';
import 'package:tsumige/src/features/settings/presentation/settings_dialog.dart';
import 'package:tsumige/src/features/settings/widgets/app_theme_mode_tile/app_theme_mode_tile.dart';
import 'package:tsumige/src/l10n/generated/app_localizations.dart';
import 'package:tsumige/src/utils/prefs/app_prefs.dart';
import 'package:tsumige/src/utils/prefs/prefs_mixin.dart';
import 'package:tsumige/src/utils/theme/brand.dart';

class SettingsFakeRepository implements LibraryRepository {
  SettingsFakeRepository({
    this.report = const core.VndbRefreshReport(),
    this.saveError,
    this.gate,
    this.skipped = const [],
  });

  core.VndbRefreshReport report;
  Object? saveError;
  Completer<core.VndbRefreshReport>? gate;
  List<core.SkippedEntry> skipped;
  int loadCount = 0;
  int refreshCount = 0;
  int saveCount = 0;

  @override
  Future<core.LoadedLibrary> load() async {
    loadCount++;
    return core.LoadedLibrary(
      library: core.Library(
        games: [core.Game(id: 'g1', title: 'Alpha', vndbId: 'v1')],
      ),
      skipped: skipped,
    );
  }

  @override
  Future<void> save(core.LoadedLibrary loaded) async {
    saveCount++;
    final error = saveError;
    if (error != null) throw error;
  }

  @override
  Future<core.VndbRefreshReport> refreshVndbData(
    core.LoadedLibrary loaded,
  ) async {
    refreshCount++;
    final pending = gate;
    if (pending != null) return pending.future;
    return report;
  }

  @override
  Future<core.ThumbReport> ensureThumbnails(core.Library library) async =>
      core.ThumbReport();
}

void setWindowSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<ProviderContainer> pumpSettings(
  WidgetTester tester,
  SettingsFakeRepository repo, {
  core.DataDir? dir,
  List<detect.ProtonRunner> protonRunners = const [],
  Future<String?> Function({String? initialDirectory, PathPickMode mode})?
  pathPicker,
  List<Uri>? openedUris,
  Size windowSize = const Size(1400, 980),
}) async {
  setWindowSize(tester, windowSize);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  SettingsDialog.lastSection = SettingsSection.appearance;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        dataDirProvider.overrideWithValue(dir ?? core.DataDir('/tmp/tsumige_test')),
        libraryRepositoryProvider.overrideWithValue(repo),
        protonRunnersProvider.overrideWith(
          (ref) => Future.value(protonRunners),
        ),
        if (pathPicker != null)
          pathPickerProvider.overrideWithValue(pathPicker),
        folderOpenerProvider.overrideWithValue((uri) async {
          openedUris?.add(uri);
          return true;
        }),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                key: const Key('open-settings'),
                onPressed: () => showSettingsDialog(context),
                child: const Text('Open settings'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.byKey(const Key('open-settings')));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(SettingsDialog)));
}

Future<void> openSection(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(Key('settings-nav-$name')));
  await tester.pumpAndSettle();
}

Finder refreshButton() => find.byKey(const Key('settings-refresh-ratings'));

Future<ProviderContainer> pumpLibrarySection(
  WidgetTester tester,
  SettingsFakeRepository repo, {
  core.DataDir? dir,
  List<Uri>? openedUris,
  Size windowSize = const Size(1400, 980),
}) async {
  final container = await pumpSettings(
    tester,
    repo,
    dir: dir,
    openedUris: openedUris,
    windowSize: windowSize,
  );
  await openSection(tester, 'library');
  await tester.pump();
  return container;
}

void main() {
  testWidgets('toolbar button opens the dialog, Esc and close close it', (
    tester,
  ) async {
    setWindowSize(tester, const Size(1600, 980));
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          dataDirProvider.overrideWithValue(core.DataDir('/tmp/tsumige_test')),
          libraryRepositoryProvider.overrideWithValue(SettingsFakeRepository()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: LibraryToolbar(gridRight: 800)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsDialog), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsDialog), findsNothing);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsDialog), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-close')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsDialog), findsNothing);
  });

  testWidgets('nav switches sections and marks the selected item', (
    tester,
  ) async {
    await pumpSettings(tester, SettingsFakeRepository());
    expect(
      find.byKey(const Key('settings-nav-selected-appearance')),
      findsOneWidget,
    );
    expect(find.text('Theme mode'), findsOneWidget);

    await openSection(tester, 'library');
    expect(find.text('Data folder'), findsOneWidget);
    expect(
      find.byKey(const Key('settings-nav-selected-library')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('settings-nav-selected-appearance')),
      findsNothing,
    );

    await openSection(tester, 'launching');
    expect(find.byKey(const Key('launch-mode-card-proton')), findsNothing);
    await openSection(tester, 'advanced');
    expect(find.text('UMU game id'), findsOneWidget);
    await openSection(tester, 'about');
    expect(find.text('Version 0.1.0'), findsOneWidget);
    expect(find.text('MPL-2.0'), findsOneWidget);
  });

  testWidgets('dialog size follows the window', (tester) async {
    await pumpSettings(tester, SettingsFakeRepository());
    expect(
      tester.getSize(find.byKey(const Key('settings-dialog'))),
      const Size(960, 720),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(1000, 700);
    await tester.pump();
    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('settings-dialog'))),
      const Size(900, 630),
    );
  });

  testWidgets('theme mode radios write the pref', (tester) async {
    final container = await pumpSettings(tester, SettingsFakeRepository());
    await tester.tap(find.byKey(const Key('settings-theme-mode-light')));
    await tester.pump();
    expect(container.read(appThemeModeProvider), ThemeMode.light);
    expect(find.byKey(const Key('settings-true-black')), findsNothing);
    await tester.tap(find.byKey(const Key('settings-theme-mode-dark')));
    await tester.pump();
    expect(container.read(appThemeModeProvider), ThemeMode.dark);
  });

  testWidgets('details panel fields list four checked boxes', (tester) async {
    final container = await pumpSettings(tester, SettingsFakeRepository());
    expect(
      find.text('Game fields to be displayed on details panel:'),
      findsOneWidget,
    );
    const labels = ['Description', 'Tags', 'VNDB tags', 'Notes'];
    for (final label in labels) {
      expect(find.text(label), findsOneWidget);
    }
    expect(
      container.read(detailFieldsProvider),
      keys.detailFieldsAll,
    );
    for (final id in ['description', 'tags', 'vndbTags', 'notes']) {
      final checkbox = find.descendant(
        of: find.byKey(Key('settings-detail-field-$id')),
        matching: find.byType(Checkbox),
      );
      expect(checkbox, findsOneWidget);
      expect(tester.widget<Checkbox>(checkbox).value, isTrue);
    }
  });

  testWidgets('detail field row toggles with the keyboard', (tester) async {
    final container = await pumpSettings(tester, SettingsFakeRepository());
    const rowKey = Key('settings-detail-field-notes');
    await tester.ensureVisible(find.byKey(rowKey));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(rowKey),
        matching: find.byType(ExcludeFocus),
      ),
      findsOneWidget,
    );

    bool rowFocused() {
      final context = FocusManager.instance.primaryFocus?.context;
      if (context == null) return false;
      var found = false;
      (context as Element).visitAncestorElements((el) {
        if (el.widget.key == rowKey) found = true;
        return true;
      });
      return found;
    }

    var reached = false;
    for (var i = 0; i < 120 && !reached; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      reached = rowFocused();
    }
    expect(reached, isTrue);
    expect(
      container.read(detailFieldsProvider).contains(keys.detailFieldNotes),
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(
      container.read(detailFieldsProvider).contains(keys.detailFieldNotes),
      isFalse,
    );
  });

  testWidgets('unticking VNDB tags updates the pref', (tester) async {
    final container = await pumpSettings(tester, SettingsFakeRepository());
    await tester.ensureVisible(
        find.byKey(const Key('settings-detail-field-vndbTags')));
    await tester.tap(
        find.byKey(const Key('settings-detail-field-vndbTags')));
    await tester.pump();
    expect(
      container.read(detailFieldsProvider),
      {keys.detailFieldDescription, keys.detailFieldTags, keys.detailFieldNotes},
    );
    final checkbox = find.descendant(
      of: find.byKey(const Key('settings-detail-field-vndbTags')),
      matching: find.byType(Checkbox),
    );
    expect(tester.widget<Checkbox>(checkbox).value, isFalse);
    await tester.tap(
        find.byKey(const Key('settings-detail-field-vndbTags')));
    await tester.pump();
    expect(container.read(detailFieldsProvider), keys.detailFieldsAll);
  });

  testWidgets('cover slider writes the pref', (tester) async {
    final container = await pumpSettings(tester, SettingsFakeRepository());
    expect(container.read(coverWidthProvider), 192);
    final slider = find.byKey(const Key('cover-size-slider'));
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    await tester.drag(slider, const Offset(120, 0));
    await tester.pump();
    expect(container.read(coverWidthProvider), greaterThan(192));
  });

  testWidgets('refresh disabled while running', (tester) async {
    final gate = Completer<core.VndbRefreshReport>();
    final repo = SettingsFakeRepository(
      gate: gate,
      report: const core.VndbRefreshReport(updated: 1),
    );
    await pumpLibrarySection(tester, repo);
    await tester.tap(refreshButton());
    await tester.pump();
    expect(tester.widget<BrandButton>(refreshButton()).onPressed, isNull);
    expect(tester.widget<BrandButton>(refreshButton()).loading, isTrue);
    expect(repo.refreshCount, 1);
    await tester.tap(refreshButton());
    await tester.pump();
    expect(repo.refreshCount, 1);
    gate.complete(const core.VndbRefreshReport(updated: 1));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(tester.widget<BrandButton>(refreshButton()).onPressed, isNotNull);
    expect(tester.widget<BrandButton>(refreshButton()).loading, isFalse);
    expect(repo.refreshCount, 1);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('changed on disk reloads', (tester) async {
    final repo = SettingsFakeRepository(
      report: const core.VndbRefreshReport(updated: 2),
      saveError: core.ChangedOnDisk('x'),
    );
    await pumpLibrarySection(tester, repo);
    expect(repo.loadCount, 1);
    await tester.tap(refreshButton());
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(repo.saveCount, 1);
    expect(repo.loadCount, 2);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('skipped entries never fetch ratings', (tester) async {
    final repo = SettingsFakeRepository(
      report: const core.VndbRefreshReport(updated: 2),
      skipped: const [core.SkippedEntry(index: 0, reason: 'bad id')],
    );
    await pumpLibrarySection(tester, repo);
    expect(repo.loadCount, 1);
    await tester.tap(refreshButton());
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(repo.refreshCount, 0);
    expect(repo.saveCount, 0);
    expect(repo.loadCount, 1);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('generic save failure reloads', (tester) async {
    final repo = SettingsFakeRepository(
      report: const core.VndbRefreshReport(updated: 2),
      saveError: const FileSystemException('disk gone'),
    );
    await pumpLibrarySection(tester, repo);
    expect(repo.loadCount, 1);
    await tester.tap(refreshButton());
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(repo.saveCount, 1);
    expect(repo.loadCount, 2);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('zero updates skips save', (tester) async {
    final repo = SettingsFakeRepository(
      report: const core.VndbRefreshReport(updated: 0),
    );
    await pumpLibrarySection(tester, repo);
    await tester.tap(refreshButton());
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(repo.saveCount, 0);
    expect(repo.loadCount, 2);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('prefix field is 40 px tall', (tester) async {
    await pumpSettings(tester, SettingsFakeRepository());
    await openSection(tester, 'launching');
    final size = tester.getSize(find.byKey(const Key('settings-prefix')));
    expect(size.height, closeTo(40, 1));
    final field = find.byKey(const Key('settings-prefix'));
    expect(
      tester
          .getSize(find.descendant(
            of: field,
            matching: find.byType(InputDecorator),
          ))
          .height,
      closeTo(40, 1),
    );
    expect(
      tester
          .getSize(find.descendant(
            of: field,
            matching: find.byType(SettingsTextBox),
          ))
          .height,
      closeTo(40, 1),
    );
    final decorator = tester.getCenter(find.descendant(
      of: field,
      matching: find.byType(SettingsTextBox),
    ));
    final choose = tester.getCenter(
      find.byKey(const Key('settings-prefix-choose')),
    );
    expect(decorator.dy, closeTo(choose.dy, 1));
  });

  testWidgets('action buttons use the brand styles', (tester) async {
    await pumpSettings(tester, SettingsFakeRepository());
    await openSection(tester, 'library');
    expect(tester.widget<BrandButton>(refreshButton()).height, 40);
    for (final key in ['settings-open-data', 'settings-open-logs']) {
      expect(
        tester.widget(find.byKey(Key(key))),
        isA<BrandGlassButton>(),
        reason: key,
      );
      expect(
        tester.widget<BrandGlassButton>(find.byKey(Key(key))).height,
        40,
        reason: key,
      );
    }
    await openSection(tester, 'launching');
    expect(
      tester.widget(find.byKey(const Key('settings-prefix-choose'))),
      isA<BrandGlassButton>(),
    );
  });

  testWidgets('setting rows stay one line at 1400x980', (tester) async {
    await pumpSettings(tester, SettingsFakeRepository());
    await openSection(tester, 'library');
    final vndbSize = tester.getSize(find.byKey(const Key('settings-row-vndb')));
    expect(vndbSize.height, lessThanOrEqualTo(80), reason: 'vndb');
    for (final key in ['data-folder', 'launch-logs']) {
      final size = tester.getSize(find.byKey(Key('settings-row-$key')));
      expect(size.height, lessThanOrEqualTo(72), reason: key);
    }
    await openSection(tester, 'launching');
    for (final key in ['prefix', 'proton']) {
      final size = tester.getSize(find.byKey(Key('settings-row-$key')));
      expect(size.height, lessThanOrEqualTo(72), reason: key);
    }
    final localeSize =
        tester.getSize(find.byKey(const Key('settings-row-locale')));
    expect(localeSize.height, lessThanOrEqualTo(80), reason: 'locale');
  });

  testWidgets('library section heading reads VNDB data', (tester) async {
    await pumpSettings(tester, SettingsFakeRepository());
    await openSection(tester, 'library');
    expect(find.text('VNDB data'), findsOneWidget);
    expect(find.text('VNDB ratings'), findsNothing);
  });

  testWidgets('game language dropdown is as wide as the proton dropdown', (
    tester,
  ) async {
    await pumpSettings(tester, SettingsFakeRepository());
    await openSection(tester, 'launching');
    expect(
      tester.getSize(find.byKey(const Key('settings-locale'))).width,
      tester.getSize(find.byKey(const Key('settings-proton-version'))).width,
    );
  });

  testWidgets('game language dropdown stores presets and custom text', (
    tester,
  ) async {
    final container = await pumpSettings(tester, SettingsFakeRepository());
    await openSection(tester, 'launching');
    final dropdown = find.byKey(const Key('settings-locale'));
    expect(dropdown, findsOneWidget);
    expect(
      find.descendant(
        of: dropdown,
        matching: find.byType(DropdownButton<String>),
      ),
      findsOneWidget,
    );

    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Japanese').last);
    await tester.pumpAndSettle();
    expect(container.read(launchLocaleProvider), 'ja_JP.UTF-8');

    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom…').last);
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('settings-locale-custom-field'));
    expect(field, findsOneWidget);
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, 'fr_FR.UTF-8');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(container.read(launchLocaleProvider), 'fr_FR.UTF-8');
  });

  testWidgets('prefix field and controls share one centre and right edge', (
    tester,
  ) async {
    await pumpSettings(tester, SettingsFakeRepository());
    await openSection(tester, 'launching');
    final field = tester.getRect(find.byKey(const Key('settings-prefix')));
    final choose = tester.getRect(
      find.byKey(const Key('settings-prefix-choose')),
    );
    expect(field.center.dy, closeTo(choose.center.dy, 1));
    final proton = tester.getRect(
      find.byKey(const Key('settings-proton-version')),
    );
    final locale = tester.getRect(find.byKey(const Key('settings-locale')));
    expect(choose.right, closeTo(proton.right, 1));
    expect(choose.right, closeTo(locale.right, 1));
  });

  testWidgets('portal prefix is rejected', (tester) async {
    final container = await pumpSettings(tester, SettingsFakeRepository());
    await openSection(tester, 'launching');
    final field = find.byKey(const Key('settings-prefix'));
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, '/run/user/1000/prefix');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(container.read(launchPrefixProvider), '~/Games/tsumige/prefix');
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('open folder buttons call the injected launcher', (tester) async {
    final temp = Directory.systemTemp.createTempSync('tsumige_settings_test_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final opened = <Uri>[];
    await pumpLibrarySection(
      tester,
      SettingsFakeRepository(),
      dir: core.DataDir(temp.path),
      openedUris: opened,
    );
    await tester.tap(find.byKey(const Key('settings-open-data')));
    await tester.pump();
    await tester.pump();
    expect(opened, [Uri.file(temp.path)]);

    await tester.tap(find.byKey(const Key('settings-open-logs')));
    await tester.pump();
    await tester.pump();
    expect(opened, [Uri.file(temp.path), Uri.file(p.join(temp.path, 'logs'))]);
    expect(Directory(p.join(temp.path, 'logs')).existsSync(), isTrue);
  });

  testWidgets('no overflow at 1000x700', (tester) async {
    await pumpSettings(
      tester,
      SettingsFakeRepository(),
      windowSize: const Size(1000, 700),
    );
    for (final section in [
      'appearance',
      'library',
      'launching',
      'advanced',
      'about',
    ]) {
      await openSection(tester, section);
      expect(tester.takeException(), isNull, reason: section);
    }
  });

  testWidgets('prefix text is centred in its box, unfocused and focused', (
    tester,
  ) async {
    await pumpSettings(tester, SettingsFakeRepository());
    await openSection(tester, 'launching');
    final field = find.byKey(const Key('settings-prefix'));
    final box = tester.getCenter(
      find.descendant(of: field, matching: find.byType(SettingsTextBox)),
    );
    final editable = find.descendant(
      of: field,
      matching: find.byType(EditableText),
    );
    expect(tester.getCenter(editable).dy, closeTo(box.dy + 4, 2));
    await tester.tap(editable);
    await tester.pump();
    expect(tester.getCenter(editable).dy, closeTo(box.dy + 4, 2));
  });

  testWidgets('prefix text baseline matches a dropdown value', (tester) async {
    await pumpSettings(tester, SettingsFakeRepository());
    await openSection(tester, 'launching');
    await tester.pumpAndSettle();
    double baselineInBox(Finder text, Finder box) {
      final r = tester.renderObject<RenderBox>(text);
      final b = tester.renderObject<RenderBox>(box);
      final baseline = r
          .localToGlobal(
            Offset(
              0,
              r.getDryBaseline(
                BoxConstraints.tight(r.size),
                TextBaseline.alphabetic,
              )!,
            ),
          )
          .dy;
      return baseline - b.localToGlobal(Offset.zero).dy;
    }

    final field = baselineInBox(
      find.descendant(
        of: find.byKey(const Key('settings-prefix')),
        matching: find.byType(EditableText),
      ),
      find.byKey(const Key('settings-prefix')),
    );
    final dropdown = baselineInBox(
      find
          .descendant(
            of: find.byKey(const Key('settings-locale')),
            matching: find.byType(Text),
          )
          .first,
      find.byKey(const Key('settings-locale')),
    );
    expect(field, closeTo(dropdown + 4, 1));
  });
}
