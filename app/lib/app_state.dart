import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'i18n.dart';
import 'logic/categories.dart';
import 'logic/items.dart';
import 'store.dart';

/// App-wide state: the store plus UI state that outlives a screen (language, tab, filters).
class AppState extends ChangeNotifier {
  AppState(this.store) {
    store.addListener(notifyListeners);
  }

  final Store store;
  int tab = 0;
  Filters filters = const Filters();
  String sort = 'title';

  String get lang {
    final l = store.settings.lang;
    if (l == 'de' || l == 'en') return l!;
    return ui.PlatformDispatcher.instance.locale.languageCode == 'en' ? 'en' : 'de';
  }

  String t(String key, [Map<String, Object?> vars = const {}]) => tr(lang, key, vars);
  String catLabel(String c) => categoryLabel(c, lang);

  void setTab(int i) {
    tab = i;
    notifyListeners();
  }

  void setFilters(Filters f) {
    filters = f;
    notifyListeners();
  }

  void setSort(String s) {
    sort = s;
    notifyListeners();
  }

  /// Jump to the library showing only what matches [f].
  void showInLibrary(Filters f, {String? sortBy}) {
    filters = f;
    if (sortBy != null) sort = sortBy;
    tab = 0;
    notifyListeners();
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Access without subscribing to changes (for callbacks).
  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
