import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mybib/models.dart';
import 'package:mybib/store.dart';

void main() {
  test('saves and loads the catalogue and settings', () async {
    final dir = await Directory.systemTemp.createTemp('mybib');
    final a = Store(dir: dir);
    await a.load();
    final [x, _] = a.addItems([{'title': 'Open City', 'room': 'Wohnzimmer'}, {'title': 'Kafka am Strand', 'category': 'novel'}]);
    a.updateItem(x.id, {'rating': 4});
    a.moveRoom('Wohnzimmer', 'Küche');
    await a.save();
    await a.updateSettings(const Settings(lang: 'en', googleBooksKey: 'g'));

    final b = Store(dir: dir);
    await b.load();
    expect(b.items.length, 2);
    expect(b.byId(x.id)?.rating, 4);
    expect(b.byId(x.id)?.room, 'Küche');
    expect(b.settings.lang, 'en');
    expect(b.settings.googleBooksKey, 'g');
    b.moveCategory('novel', '');
    expect(b.items.where((i) => i.category != null), isEmpty);
    await dir.delete(recursive: true);
  });
}
