import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mybib/models.dart';
import 'package:mybib/strings.dart';

void main() {
  final de = strings['de']!;
  final en = strings['en']!;

  test('same keys and placeholders in both languages', () {
    expect(en.keys.toSet(), de.keys.toSet());
    for (final k in de.keys) {
      Set<String> ph(String s) => RegExp(r'\{\w+\}').allMatches(s).map((m) => m.group(0)!).toSet();
      expect(ph(en[k]!), ph(de[k]!), reason: k);
    }
  });

  test('every literal key used in the code exists', () {
    final src = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')).map((f) => f.readAsStringSync()).join('\n');
    final keys = RegExp(r"\.t\(\s*'([a-zA-Z0-9.\-]+)'").allMatches(src).map((m) => m.group(1)!).toSet();
    expect(keys.where((k) => !de.containsKey(k)).toList(), isEmpty);
  });

  test('generated keys exist', () {
    final gen = [
      for (final k in kinds) ...['kind.$k', 'kind.$k.pl', 'creator.$k', for (final s in statuses) 'status.$k.$s'],
      for (final f in formats) 'format.$f',
      for (final s in ['all', 'wish', 'lent', 'recommend', 'check']) 'scope.$s',
      for (final s in ['title', 'creator', 'added', 'rating', 'year', 'place']) 'sort.$s',
      for (final s in ['cover', 'publisher', 'year', 'isbn', 'description']) 'bulk.field.$s',
      for (final s in ['auth', 'refusal', 'rate', 'network', 'parse', 'other']) 'ai.err.$s',
      for (final m in ['own', 'wish', 'check']) 'scan.mode.$m',
      'settings.googleHow1', 'settings.googleHow4', 'settings.model.claude-opus-5-5', 'settings.model.claude-sonnet-5-5', 'ai.conf.medium', 'ai.conf.low',
    ];
    expect(gen.where((k) => !de.containsKey(k)).toList(), isEmpty);
  });
}
