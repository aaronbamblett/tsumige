// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'router.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Whether the scaffold shows its plain title bar: false on the library
/// route, which draws its own top bar (merged or stacked), true everywhere
/// else. Starts false because the app always opens on the library.

@ProviderFor(ScaffoldTitleBar)
final scaffoldTitleBarProvider = ScaffoldTitleBarProvider._();

/// Whether the scaffold shows its plain title bar: false on the library
/// route, which draws its own top bar (merged or stacked), true everywhere
/// else. Starts false because the app always opens on the library.
final class ScaffoldTitleBarProvider
    extends $NotifierProvider<ScaffoldTitleBar, bool> {
  /// Whether the scaffold shows its plain title bar: false on the library
  /// route, which draws its own top bar (merged or stacked), true everywhere
  /// else. Starts false because the app always opens on the library.
  ScaffoldTitleBarProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'scaffoldTitleBarProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$scaffoldTitleBarHash();

  @$internal
  @override
  ScaffoldTitleBar create() => ScaffoldTitleBar();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$scaffoldTitleBarHash() => r'3f4976824196a4c14022ae3e06ff65922cc4df5a';

/// Whether the scaffold shows its plain title bar: false on the library
/// route, which draws its own top bar (merged or stacked), true everywhere
/// else. Starts false because the app always opens on the library.

abstract class _$ScaffoldTitleBar extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
