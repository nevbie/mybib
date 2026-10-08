import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_state.dart';
import 'screens/add_screen.dart';
import 'screens/library_screen.dart';
import 'screens/places_screen.dart';
import 'screens/settings_screen.dart';
import 'store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final store = Store();
  store.load();
  runApp(MybibApp(state: AppState(store)));
}

const seed = Color(0xFF0F766E);

class MybibApp extends StatelessWidget {
  const MybibApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: Builder(builder: (context) {
        final s = AppScope.of(context);
        return MaterialApp(
          title: 'mybib',
          debugShowCheckedModeBanner: false,
          locale: Locale(s.lang),
          supportedLocales: const [Locale('de'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true, brightness: Brightness.light),
          darkTheme: ThemeData(colorSchemeSeed: seed, useMaterial3: true, brightness: Brightness.dark),
          home: const HomeScreen(),
        );
      }),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    if (!s.store.ready) return Scaffold(body: Center(child: Text(s.t('app.loading'))));
    final toCheck = s.store.items.any((i) => i.needsCheck);
    const pages = [LibraryScreen(), AddScreen(), PlacesScreen(), SettingsScreen()];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: s.tab, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: s.tab,
        onDestinationSelected: s.setTab,
        destinations: [
          NavigationDestination(icon: Badge(isLabelVisible: toCheck, smallSize: 8, child: const Icon(Icons.menu_book_outlined)), selectedIcon: const Icon(Icons.menu_book), label: s.t('nav.library')),
          NavigationDestination(icon: const Icon(Icons.add_circle_outline), selectedIcon: const Icon(Icons.add_circle), label: s.t('nav.add')),
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: s.t('nav.places')),
          NavigationDestination(icon: const Icon(Icons.settings_outlined), selectedIcon: const Icon(Icons.settings), label: s.t('nav.settingsShort')),
        ],
      ),
    );
  }
}
