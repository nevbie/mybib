import 'dart:convert';

import '../models.dart';

const _accents = {
  'àáâãäåāăą': 'a', 'çćĉċč': 'c', 'ďđ': 'd', 'èéêëēĕėęě': 'e', 'ĝğġģ': 'g', 'ĥħ': 'h', 'ìíîïĩīĭįı': 'i', 'ĵ': 'j', 'ķ': 'k',
  'ĺļľŀł': 'l', 'ñńņňŉ': 'n', 'òóôõöøōŏő': 'o', 'ŕŗř': 'r', 'śŝşšș': 's', 'ţťŧț': 't', 'ùúûüũūŭůűų': 'u', 'ŵ': 'w', 'ýÿŷ': 'y', 'źżž': 'z',
};
final Map<String, String> _accentMap = {
  for (final e in _accents.entries)
    for (final ch in e.key.split('')) ch: e.value,
};
final _nonWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// Lower-case, strip accents and punctuation – for search and duplicate detection.
String fold(String s) {
  final low = s.toLowerCase().replaceAll('ß', 'ss').replaceAll('æ', 'ae').replaceAll('œ', 'oe');
  final buf = StringBuffer();
  for (final ch in low.split('')) {
    buf.write(_accentMap[ch] ?? ch);
  }
  return buf.toString().replaceAll(_nonWord, ' ').trim();
}

/// Probable duplicate: same ISBN, or same title + first creator (or both unknown) + volume.
Item? findDuplicate(List<Item> items, {required String title, String? isbn, List<String> creators = const [], String? volume, String? kind, String? format}) {
  if (isbn != null && isbn.isNotEmpty) {
    for (final i in items) {
      if (i.isbn == isbn) return i;
    }
  }
  final t = fold(title);
  if (t.isEmpty) return null;
  final c = creators.isNotEmpty ? fold(creators.first) : '';
  final v = volume != null ? fold(volume) : '';
  for (final i in items) {
    if (fold(i.title) == t &&
        (i.creators.isNotEmpty ? fold(i.creators.first) : '') == c &&
        (i.volume != null ? fold(i.volume!) : '') == v &&
        (kind == null || i.kind == kind) &&
        (format == null || i.format == format)) {
      return i;
    }
  }
  return null;
}

Item? findDuplicateOf(List<Item> items, Item d) =>
    findDuplicate(items, title: d.title, isbn: d.isbn, creators: d.creators, volume: d.volume, kind: d.kind, format: d.format);

class Filters {
  final String q;
  final String kind; // 'all' or a kind
  final String status;
  /// all / owned / wish / lent / recommend / check
  final String scope;
  final String format;
  /// 'all', '' = no room, or a room
  final String room;
  /// 'all', '' = no category, or a category
  final String category;
  final int minRating;

  const Filters({this.q = '', this.kind = 'all', this.status = 'all', this.scope = 'all', this.format = 'all', this.room = 'all', this.category = 'all', this.minRating = 0});

  Filters copyWith({String? q, String? kind, String? status, String? scope, String? format, String? room, String? category, int? minRating}) => Filters(
        q: q ?? this.q,
        kind: kind ?? this.kind,
        status: status ?? this.status,
        scope: scope ?? this.scope,
        format: format ?? this.format,
        room: room ?? this.room,
        category: category ?? this.category,
        minRating: minRating ?? this.minRating,
      );

  int get extraActive => [status != 'all', format != 'all', room != 'all', category != 'all', minRating > 0].where((b) => b).length;
}

String searchText(Item i) =>
    fold([i.title, i.subtitle, ...i.creators, i.series, i.publisher, i.isbn, i.notes, ...i.tags, i.room].whereType<String>().join(' '));

List<Item> applyFilters(List<Item> items, Filters f) {
  final words = fold(f.q).split(' ').where((w) => w.isNotEmpty).toList();
  return items.where((i) {
    if (f.kind != 'all' && i.kind != f.kind) return false;
    if (f.status != 'all' && i.status != f.status) return false;
    if (f.format != 'all' && i.format != f.format) return false;
    if (f.room != 'all' && (i.room ?? '') != f.room) return false;
    if (f.category != 'all' && (i.category ?? '') != f.category) return false;
    if (f.minRating > 0 && i.rating < f.minRating) return false;
    switch (f.scope) {
      case 'owned':
        if (!i.owned) return false;
      case 'wish':
        if (i.owned) return false;
      case 'lent':
        if (i.openLoan == null) return false;
      case 'recommend':
        if (!i.recommend) return false;
      case 'check':
        if (!i.needsCheck) return false;
    }
    if (words.isNotEmpty) {
      final hay = searchText(i);
      if (!words.every(hay.contains)) return false;
    }
    return true;
  }).toList();
}

final _articles = RegExp(r'^(der|die|das|ein|eine|the|a|an|le|la|les|el|los|las)\s+', caseSensitive: false);

/// Sort key for titles: ignore leading articles so "Der Koran" sorts under K.
String titleKey(String t) => fold(t.replaceFirst(_articles, ''));

/// Surname key: "Mai Thi Nguyen-Kim" → "nguyen kim", "Laura Lamping (Hg.)" → "lamping", "Schami, Rafik" → "schami".
String creatorKey(Item i) {
  final c = (i.creators.isNotEmpty ? i.creators.first : '').replaceAll(RegExp(r'\([^)]*\)'), '').trim();
  final surname = c.contains(',') ? c.split(',').first : (c.split(RegExp(r'\s+')).last);
  return '${fold(surname)} ${titleKey(i.title)}';
}

int _natural(String a, String b) {
  // numbers inside strings compare by value ("Band 2" < "Band 10")
  final re = RegExp(r'(\d+)|(\D+)');
  final ma = re.allMatches(a).toList();
  final mb = re.allMatches(b).toList();
  for (var k = 0; k < ma.length && k < mb.length; k++) {
    final x = ma[k].group(0)!;
    final y = mb[k].group(0)!;
    final nx = int.tryParse(x);
    final ny = int.tryParse(y);
    final c = nx != null && ny != null ? nx.compareTo(ny) : x.compareTo(y);
    if (c != 0) return c;
  }
  return ma.length.compareTo(mb.length);
}

const sortKeys = ['title', 'creator', 'added', 'rating', 'year', 'place'];

List<Item> sortItems(List<Item> items, String key) {
  final arr = [...items];
  int byTitle(Item a, Item b) {
    final c = _natural(titleKey(a.title), titleKey(b.title));
    return c != 0 ? c : _natural(a.volume ?? '', b.volume ?? '');
  }

  switch (key) {
    case 'creator':
      arr.sort((a, b) => _natural(creatorKey(a), creatorKey(b)));
    case 'added':
      arr.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    case 'rating':
      arr.sort((a, b) => b.rating != a.rating ? b.rating - a.rating : byTitle(a, b));
    case 'year':
      arr.sort((a, b) => (b.year ?? 0) - (a.year ?? 0));
    case 'place':
      arr.sort((a, b) {
        final c = _natural(fold(a.room ?? '\u{ffff}'), fold(b.room ?? '\u{ffff}'));
        return c != 0 ? c : byTitle(a, b);
      });
    default:
      arr.sort(byTitle);
  }
  return arr;
}

/// Rooms with item counts ('' = not set); only owned physical items have a place.
List<(String, int)> summarizePlaces(List<Item> items) {
  final map = <String, int>{};
  for (final i in items) {
    if (!i.owned || i.format != 'physical') continue;
    map[i.room ?? ''] = (map[i.room ?? ''] ?? 0) + 1;
  }
  final list = map.entries.map((e) => (e.key, e.value)).toList();
  list.sort((a, b) => a.$1.isEmpty ? 1 : (b.$1.isEmpty ? -1 : _natural(fold(a.$1), fold(b.$1))));
  return list;
}

/// Rooms to offer: the configured ones (or defaults) plus any used by items.
List<String> allRooms(List<Item> items, List<String> configured, List<String> defaults) {
  final list = configured.isNotEmpty ? [...configured] : [...defaults];
  for (final i in items) {
    if (i.room != null && !list.contains(i.room)) list.add(i.room!);
  }
  return list;
}

/// Names used in earlier loans, most recent first.
List<String> knownPeople(List<Item> items) {
  final loans = items.expand((i) => i.loans).toList()..sort((a, b) => b.since.compareTo(a.since));
  return loans.map((l) => l.to).toSet().toList();
}

// ---------- import / export ----------

Map<String, dynamic> toExport(List<Item> items) => {
      'app': 'mybib',
      'version': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'items': items.map((i) => i.toJson()).toList(),
    };

/// Read an import file: a mybib export, a bare list of items, or `{ items: [...] }` (the format
/// the Claude skill produces). A top-level room applies to items without their own.
/// `"updateOnly": true` only completes books already in the catalogue.
({List<Item> items, bool updateOnly}) parseImportFile(String text) {
  final data = jsonDecode(text);
  final List list = data is List ? data : (data is Map && data['items'] is List ? data['items'] as List : const []);
  if (list.isEmpty) throw const FormatException('no items');
  final top = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  final isExport = top['app'] == 'mybib';
  final items = list.whereType<Map>().where((x) => x['title'] is String).map((raw) {
    final x = Map<String, dynamic>.from(raw);
    return normalizeItem({
      ...x,
      'room': x['room'] ?? top['room'],
      'shelf': x['shelf'] ?? (x['room'] != null ? null : top['shelf']),
      'source': isExport ? x['source'] : 'import',
    });
  }).toList();
  return (items: items, updateOnly: top['updateOnly'] == true);
}

const _fillable = ['subtitle', 'publisher', 'year', 'isbn', 'language', 'series', 'volume', 'pages', 'description', 'coverUrl', 'category', 'room', 'ageFrom', 'needsCheck'];

/// Copy of [old] with its empty fields filled from [inc], or null when nothing changes.
Item? fillEmpty(Item old, Item inc) {
  final o = old.toJson();
  final n = inc.toJson();
  final patch = <String, dynamic>{};
  for (final k in _fillable) {
    final ov = o[k];
    final nv = n[k];
    if ((ov == null || ov == '') && nv != null && nv != '') patch[k] = nv;
  }
  if (old.tags.isEmpty && inc.tags.isNotEmpty) patch['tags'] = inc.tags;
  if (patch.isEmpty) return null;
  return old.copyWith({...patch, 'updatedAt': DateTime.now().toUtc().toIso8601String()});
}

class MergeResult {
  final List<Item> items;
  final int added, updated, skipped;
  const MergeResult(this.items, this.added, this.updated, this.skipped);
}

/// Merge imported items: same id → newer `updatedAt` wins; obvious duplicate → its empty fields
/// are filled in; otherwise added (unless [updateOnly]).
MergeResult mergeItems(List<Item> existing, List<Item> incoming, {bool updateOnly = false}) {
  final all = [...existing];
  final idx = {for (var k = 0; k < all.length; k++) all[k].id: k};
  var added = 0, updated = 0, skipped = 0;
  for (final inc in incoming) {
    final k = idx[inc.id];
    if (k != null) {
      if (inc.updatedAt.compareTo(all[k].updatedAt) > 0) {
        all[k] = inc;
        updated++;
      } else {
        skipped++;
      }
      continue;
    }
    final dup = findDuplicateOf(all, inc);
    if (dup != null) {
      final filled = fillEmpty(dup, inc);
      if (filled != null) {
        all[idx[dup.id]!] = filled;
        updated++;
      } else {
        skipped++;
      }
      continue;
    }
    if (updateOnly) {
      skipped++;
      continue;
    }
    idx[inc.id] = all.length;
    all.add(inc);
    added++;
  }
  return MergeResult(all, added, updated, skipped);
}

const _csvColumns = ['kind', 'title', 'subtitle', 'creators', 'publisher', 'year', 'isbn', 'language', 'series', 'volume', 'format', 'owned', 'status', 'rating', 'recommend', 'category', 'room', 'lentTo', 'tags', 'notes', 'addedAt'];

/// Spreadsheet-friendly export (semicolon separated, as Excel in German locale expects).
String toCSV(List<Item> items) {
  String esc(Object? v) {
    final s = v == null ? '' : (v is List ? v.join(', ') : v.toString());
    return RegExp(r'[";\n]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  final rows = items.map((i) {
    final j = i.toJson();
    return _csvColumns.map((c) => esc(c == 'lentTo' ? i.openLoan?.to : j[c])).join(';');
  });
  return '\u{FEFF}${[_csvColumns.join(';'), ...rows].join('\n')}';
}

// ---------- bulk completion ----------

/// Details online sources can deliver that are still missing.
List<String> missingInfo(Item i) => [
      if (!i.hasCover) 'cover',
      if (i.publisher == null) 'publisher',
      if (i.year == null) 'year',
      if (i.isbn == null) 'isbn',
      if (i.description == null) 'description',
    ];

/// Books that could still gain details; [retry] includes those already looked up.
List<Item> bulkTargets(List<Item> items, bool retry) =>
    items.where((i) => i.kind == 'book' && missingInfo(i).isNotEmpty && (retry || i.lookedUp == null)).toList();
