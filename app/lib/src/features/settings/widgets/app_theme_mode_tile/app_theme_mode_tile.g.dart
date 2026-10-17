// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_theme_mode_tile.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(AppThemeMode)
final appThemeModeProvider = AppThemeModeProvider._();

final class AppThemeModeProvider
    extends $NotifierProvider<AppThemeMode, ThemeMode?> {
  AppThemeModeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appThemeModeProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appThemeModeHash();

  @$internal
  @override
  AppThemeMode create() => AppThemeMode();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ThemeMode? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ThemeMode?>(value),
    );
  }
}

String _$appThemeModeHash() => r'881fccbc93fb315f3cc7bc5d2e2cd0b47c3564a8';

abstract class _$AppThemeMode extends $Notifier<ThemeMode?> {
  ThemeMode? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ThemeMode?, ThemeMode?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ThemeMode?, ThemeMode?>,
              ThemeMode?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
