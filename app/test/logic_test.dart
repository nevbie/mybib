import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mybib/logic/categories.dart';
import 'package:mybib/logic/isbn.dart';
import 'package:mybib/logic/items.dart';
import 'package:mybib/models.dart';

Item item(Map<String, dynamic> p) => normalizeItem({'title': 'x', ...p}, now: '2026-01-01T00:00:00.000Z');

void main() {
  group('isbn', () {
    test('validates and converts', () {
      expect(isValidIsbn10('3446205799'), isTrue);
      expect(isValidIsbn10('344620579X'), isFalse);
      expect(isbn10to13('3446205799'), '9783446205796');
      expect(isValidEan13('9783446205796'), isTrue);
      expect(isValidEan13('9783446205797'), isFalse);
    });
    test('classifies codes', () {
      expect(classifyCode('978-3-446-20579-6'), (type: 'isbn', code: '9783446205796'));
      expect(classifyCode('3-446-20579-9'), (type: 'isbn', code: '9783446205796'));
      expect(classifyCode('4006381333931'), (type: 'ean', code: '4006381333931'));
      expect(classifyCode('724384260521'), (type: 'ean', code: '724384260521'));
      expect(classifyCode('12345'), isNull);
    });
  });

  group('normalizeItem', () {
    test('fills defaults and drops junk', () {
      final i = normalizeItem({'title': ' Open City ', 'author': 'Teju Cole', 'kind': 'spaceship', 'rating': 9, 'foo': 1});
      expect(i.title, 'Open City');
      expect(i.creators, ['Teju Cole']);
      expect(i.kind, 'book');
      expect(i.rating, 5);
      expect(i.owned, isTrue);
      expect(i.toJson().containsKey('foo'), isFalse);
      expect(i.toJson().values.contains(null), isFalse);
    });
    test('splits creator strings', () {
      expect(item({'creators': 'Mary Auld / Elisa Paganelli'}).creators, ['Mary Auld', 'Elisa Paganelli']);
      expect(item({'creators': 'Abouet & Sapin'}).creators, ['Abouet', 'Sapin']);
    });
    test('rejects non-image cover data', () {
      expect(item({'coverData': 'javascript:alert(1)'}).coverData, isNull);
      expect(item({'coverData': 'data:image/jpeg;base64,AAA'}).coverData, 'data:image/jpeg;base64,AAA');
    });
    test('turns old shelves into rooms', () {
      expect(item({'room': 'Foto-Import', 'shelf': 'Foto 4'}).room, 'Foto 4');
      expect(item({'shelf': 'Regal 2'}).room, 'Regal 2');
      expect(item({'room': 'Wohnzimmer', 'shelf': 'oben'}).room, 'Wohnzimmer');
    });
    test('round-trips through JSON and copyWith can clear', () {
      final i = item({'id': 'a', 'notes': 'n', 'loans': [{'to': 'Eric', 'since': '2026-01-02'}]});
      expect(normalizeItem(jsonDecode(jsonEncode(i.toJson()))).toJson(), i.toJson());
      expect(i.copyWith({'notes': null}).notes, isNull);
      expect(i.openLoan?.to, 'Eric');
    });
  });

  group('search, filter, sort', () {
    final lib = [
      item({'id': 'a', 'title': 'Der Koran', 'creators': ['Goodword'], 'room': 'Wohnzimmer', 'rating': 4, 'category': 'religion'}),
      item({'id': 'b', 'title': 'Kalle Blomquist', 'creators': ['Astrid Lindgren'], 'room': 'Kleines Zimmer', 'status': 'done'}),
      item({'id': 'c', 'title': 'Sind Dinos tot?', 'creators': ['Mai Thi Nguyen-Kim'], 'owned': false}),
      item({'id': 'd', 'title': 'Ginseng Wurzeln', 'creators': ['Craig Thompson'], 'room': 'Wohnzimmer', 'loans': [{'to': 'Eric', 'since': '2026-01-02'}]}),
      item({'id': 'e', 'title': 'Catan', 'kind': 'game', 'recommend': true}),
    ];
    List<String> ids(List<Item> l) => l.map((i) => i.id).toList();
    test('folds umlauts and case', () => expect(fold('Größe ÄRGER Café'), 'grosse arger cafe'));
    test('searches across fields', () {
      expect(ids(applyFilters(lib, const Filters(q: 'lindgren kalle'))), ['b']);
      expect(ids(applyFilters(lib, const Filters(q: 'wohnzimmer'))), ['a', 'd']);
    });
    test('filters by scope, kind, room, category, rating', () {
      expect(ids(applyFilters(lib, const Filters(scope: 'wish'))), ['c']);
      expect(ids(applyFilters(lib, const Filters(scope: 'lent'))), ['d']);
      expect(ids(applyFilters(lib, const Filters(scope: 'recommend'))), ['e']);
      expect(ids(applyFilters(lib, const Filters(kind: 'game'))), ['e']);
      expect(ids(applyFilters(lib, const Filters(room: ''))), ['c', 'e']);
      expect(ids(applyFilters(lib, const Filters(category: 'religion'))), ['a']);
      expect(ids(applyFilters(lib, const Filters(minRating: 3))), ['a']);
    });
    test('ignores articles when sorting by title', () {
      expect(titleKey('Der Koran'), 'koran');
      expect(ids(sortItems(lib, 'title')), ['e', 'd', 'b', 'a', 'c']);
    });
    test('sorts by surname', () {
      expect(ids(sortItems(lib, 'creator')), ['e', 'a', 'b', 'c', 'd']);
      final hg = [item({'id': 'x', 'title': 'B', 'creators': ['Laura Lamping (Hg.)']}), item({'id': 'y', 'title': 'A', 'creators': ['Schami, Rafik']})];
      expect(ids(sortItems(hg, 'creator')), ['x', 'y']);
    });
    test('natural order for volumes', () {
      final v = [item({'id': '10', 'title': 'Band', 'volume': '10'}), item({'id': '2', 'title': 'Band', 'volume': '2'})];
      expect(ids(sortItems(v, 'title')), ['2', '10']);
    });
    test('summarises rooms of owned physical items', () {
      expect(summarizePlaces(lib), [('Kleines Zimmer', 1), ('Wohnzimmer', 2), ('', 1)]);
    });
  });

  group('duplicates, import, merge', () {
    final lib = [item({'id': 'a', 'title': 'Open City', 'creators': ['Teju Cole'], 'isbn': '9783518466'}), item({'id': 'b', 'title': 'Kafka am Strand', 'creators': ['Haruki Murakami']})];
    test('finds duplicates', () {
      expect(findDuplicate(lib, title: 'anything', isbn: '9783518466')?.id, 'a');
      expect(findDuplicate(lib, title: 'kafka am strand!', creators: ['Haruki Murakami'])?.id, 'b');
      expect(findDuplicate(lib, title: 'Kafka am Strand', creators: ['Someone Else']), isNull);
      final set = [item({'title': '金瓶梅词话', 'creators': ['兰陵笑笑生'], 'volume': '1'})];
      expect(findDuplicate(set, title: '金瓶梅词话', creators: ['兰陵笑笑生'], volume: '2'), isNull);
    });
    test('round-trips an export', () {
      final back = parseImportFile(jsonEncode(toExport(lib))).items;
      expect(back.map((i) => i.toJson()).toList(), lib.map((i) => i.toJson()).toList());
    });
    test('reads the skill format with a top-level room', () {
      final r = parseImportFile(jsonEncode({'room': 'Küche', 'items': [{'title': 'Käferkolonne'}, {'title': 'Freddy', 'room': 'Wohnzimmer'}, {'nope': 1}]}));
      expect(r.items.map((i) => i.room).toList(), ['Küche', 'Wohnzimmer']);
      expect(r.items.first.source, 'import');
      expect(r.updateOnly, isFalse);
    });
    test('merges: newer wins, duplicates are completed, update-only adds nothing', () {
      final r = mergeItems(lib, [
        lib[0].copyWith({'notes': 'new', 'updatedAt': '2027-01-01T00:00:00.000Z'}),
        item({'title': 'Kafka am Strand', 'creators': ['Haruki Murakami'], 'year': 2006}),
        item({'title': 'Tremolo', 'creators': ['Tomi Ungerer']}),
      ]);
      expect([r.added, r.updated, r.skipped], [1, 2, 0]);
      expect(r.items.firstWhere((i) => i.id == 'b').year, 2006);
      final u = parseImportFile(jsonEncode({'updateOnly': true, 'items': [{'title': 'Open City', 'creators': ['Teju Cole'], 'category': 'Roman & Erzählung'}, {'title': 'New'}]}));
      final r2 = mergeItems(lib, u.items, updateOnly: u.updateOnly);
      expect([r2.added, r2.updated, r2.skipped], [0, 1, 1]);
      expect(r2.items.first.category, 'novel');
    });
    test('exports CSV with escaping', () {
      final csv = toCSV([item({'title': 'Wurzeln; "Ginseng"', 'creators': ['A', 'B']})]);
      expect(csv.split('\n')[1], contains('"Wurzeln; ""Ginseng"""'));
      expect(csv.split('\n')[1], contains(';A, B;'));
    });
  });

  group('categories and bulk', () {
    test('maps names to ids', () {
      expect(defaultCategoryIds.length, 17);
      expect(toCategory('Sachbuch'), 'nonfiction');
      expect(toCategory('picture book'), 'picture');
      expect(toCategory('Gleitschirm'), 'Gleitschirm');
      expect(categoryLabel('youth', 'en'), 'Young adult');
      expect(allCategories(['novel'], ['youth', null]), ['novel', 'youth']);
    });
    test('bulk targets', () {
      final full = item({'title': 'A', 'coverUrl': 'u', 'publisher': 'p', 'year': 2000, 'isbn': '9780000000000', 'description': 'd'});
      final bare = item({'title': 'B'});
      final tried = item({'title': 'C', 'lookedUp': '2026-10-01'});
      expect(missingInfo(full), isEmpty);
      expect(bulkTargets([full, bare, tried, item({'title': 'D', 'kind': 'game'})], false).map((i) => i.title), ['B']);
      expect(bulkTargets([full, bare, tried], true).map((i) => i.title), ['B', 'C']);
    });
  });
}
