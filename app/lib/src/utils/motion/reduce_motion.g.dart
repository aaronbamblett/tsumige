// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reduce_motion.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// App-requested reduced motion, in addition to the OS "Remove animations" flag.

@ProviderFor(AppReduceMotion)
final appReduceMotionProvider = AppReduceMotionProvider._();

/// App-requested reduced motion, in addition to the OS "Remove animations" flag.
final class AppReduceMotionProvider
    extends $NotifierProvider<AppReduceMotion, bool> {
  /// App-requested reduced motion, in addition to the OS "Remove animations" flag.
  AppReduceMotionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appReduceMotionProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appReduceMotionHash();

  @$internal
  @override
  AppReduceMotion create() => AppReduceMotion();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$appReduceMotionHash() => r'bb096a7566400f4a2224d3d49c1f07b8700d4a9a';

/// App-requested reduced motion, in addition to the OS "Remove animations" flag.

abstract class _$AppReduceMotion extends $Notifier<bool> {
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
