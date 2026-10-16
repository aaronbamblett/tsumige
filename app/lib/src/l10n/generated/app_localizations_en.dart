// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'vn-launcher';

  @override
  String get library => 'Library';

  @override
  String get settings => 'Settings';

  @override
  String get search => 'Search';

  @override
  String get errorTitle => 'Could not open library';

  @override
  String get retry => 'Retry';
}
