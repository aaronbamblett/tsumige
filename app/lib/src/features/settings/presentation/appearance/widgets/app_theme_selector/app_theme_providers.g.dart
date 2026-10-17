// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_theme_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(AppThemeKey)
final appThemeKeyProvider = AppThemeKeyProvider._();

final class AppThemeKeyProvider
    extends $NotifierProvider<AppThemeKey, AppTheme?> {
  AppThemeKeyProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appThemeKeyProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appThemeKeyHash();

  @$internal
  @override
  AppThemeKey create() => AppThemeKey();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppTheme? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppTheme?>(value),
    );
  }
}

String _$appThemeKeyHash() => r'4bbc86fd34826af436cacf45415a473a7775c691';

abstract class _$AppThemeKey extends $Notifier<AppTheme?> {
  AppTheme? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AppTheme?, AppTheme?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AppTheme?, AppTheme?>,
              AppTheme?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(CustomThemeColor)
final customThemeColorProvider = CustomThemeColorProvider._();

final class CustomThemeColorProvider
    extends $NotifierProvider<CustomThemeColor, int?> {
  CustomThemeColorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'customThemeColorProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$customThemeColorHash();

  @$internal
  @override
  CustomThemeColor create() => CustomThemeColor();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int?>(value),
    );
  }
}

String _$customThemeColorHash() => r'f4d7ea0d853190ff5e2bd2ebbdd750c749017d3c';

abstract class _$CustomThemeColor extends $Notifier<int?> {
  int? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<int?, int?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<int?, int?>,
              int?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
