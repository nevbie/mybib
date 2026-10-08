import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mybib/app_state.dart';
import 'package:mybib/main.dart';
import 'package:mybib/models.dart';
import 'package:mybib/store.dart';

void main() {
  testWidgets('library shows items, filters, opens an entry and switches tabs', (tester) async {
    final dir = Directory.systemTemp.createTempSync('mybib-w');
    final store = Store(dir: dir);
    await tester.runAsync(() async {
      await store.load();
      await store.updateSettings(const Settings(lang: 'de'));
    });
    store.addItems([
      {'title': 'Kalle Blomquist', 'creators': ['Astrid Lindgren'], 'room': 'Wohnzimmer', 'category': 'children', 'rating': 4},
      {'title': 'Catan', 'kind': 'game'},
    ]);
    await tester.pumpWidget(MybibApp(state: AppState(store)));
    await tester.pumpAndSettle();

    expect(find.text('Kalle Blomquist'), findsOneWidget);
    expect(find.text('Kinderbuch'), findsOneWidget);
    await tester.tap(find.text('Spiele'));
    await tester.pumpAndSettle();
    expect(find.text('Kalle Blomquist'), findsNothing);
    expect(find.text('Catan'), findsOneWidget);

    await tester.tap(find.text('Catan'));
    await tester.pumpAndSettle();
    expect(find.text('Will ich spielen'), findsOneWidget);
    Navigator.of(tester.element(find.text('Will ich spielen'))).pop();
    await tester.pumpAndSettle();

    for (final tab in ['Hinzufügen', 'Orte', 'Optionen']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
    }
    expect(find.text('Sprache'), findsOneWidget);
    await tester.runAsync(() async {
      await store.save();
      dir.deleteSync(recursive: true);
    });
  });
}
