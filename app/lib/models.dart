import 'dart:math';

import 'logic/categories.dart';

/// What kind of thing sits on the shelf.
const kinds = ['book', 'game', 'dvd', 'cd'];

/// Physical copy, e-book or audiobook (only meaningful for books).
const formats = ['physical', 'ebook', 'audio'];

/// Reading (playing, watching, listening) status. `want` = want to read, `done` = read.
const statuses = ['none', 'want', 'active', 'done'];

const sources = ['manual', 'isbn', 'search', 'ai', 'import'];

class Loan {
  final String to;

  /// ISO date YYYY-MM-DD
  final String since;

  /// ISO date when it came back; null while it is still lent out
  final String? returned;

  const Loan({required this.to, required this.since, this.returned});

  Map<String, dynamic> toJson() => {'to': to, 'since': since, if (returned != null) 'returned': returned};
}

String today() => DateTime.now().toIso8601String().substring(0, 10);

String newId() {
  final r = Random();
  return DateTime.now().millisecondsSinceEpoch.toRadixString(36) + List.generate(6, (_) => r.nextInt(36).toRadixString(36)).join();
}

/// One catalogue entry. Same JSON format as the web app, so backups move between both.
class Item {
  final String id;
  final String kind;
  final String title;
  final String? subtitle;

  /// authors, artists, directors or game designers
  final List<String> creators;
  final String? publisher;
  final int? year;

  /// ISBN-13 for books, EAN / UPC for everything else
  final String? isbn;
  final String? language;
  final String? series;
  final String? volume;
  final int? pages;
  final String? description;

  /// remote cover (Open Library, Google Books, Cover Art Archive)
  final String? coverUrl;

  /// own photo, downscaled JPEG data URL – wins over coverUrl
  final String? coverData;
  final List<String> tags;

  /// one main category: a default id (see logic/categories.dart) or an own name
  final String? category;

  final String format;

  /// false = wishlist (not owned yet)
  final bool owned;
  final String status;

  /// 0 = not rated, 1–5 stars
  final int rating;
  final bool recommend;
  final String? notes;
  final String? room;

  final int? playersMin;
  final int? playersMax;
  final int? playMinutes;
  final int? ageFrom;

  /// all loans, newest last; the open one has no `returned`
  final List<Loan> loans;

  /// set by the photo recognition when it is unsure – shown as "please check"
  final bool needsCheck;

  /// date of the last automatic online lookup, so bulk completion doesn't retry every time
  final String? lookedUp;
  final String source;
  final String addedAt;
  final String updatedAt;

  const Item({
    required this.id,
    required this.kind,
    required this.title,
    this.subtitle,
    this.creators = const [],
    this.publisher,
    this.year,
    this.isbn,
    this.language,
    this.series,
    this.volume,
    this.pages,
    this.description,
    this.coverUrl,
    this.coverData,
    this.tags = const [],
    this.category,
    this.format = 'physical',
    this.owned = true,
    this.status = 'none',
    this.rating = 0,
    this.recommend = false,
    this.notes,
    this.room,
    this.playersMin,
    this.playersMax,
    this.playMinutes,
    this.ageFrom,
    this.loans = const [],
    this.needsCheck = false,
    this.lookedUp,
    this.source = 'manual',
    required this.addedAt,
    required this.updatedAt,
  });

  Loan? get openLoan {
    for (final l in loans) {
      if (l.returned == null) return l;
    }
    return null;
  }

  bool get hasCover => coverData != null || coverUrl != null;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'id': id,
      'kind': kind,
      'title': title,
      'subtitle': subtitle,
      'creators': creators,
      'publisher': publisher,
      'year': year,
      'isbn': isbn,
      'language': language,
      'series': series,
      'volume': volume,
      'pages': pages,
      'description': description,
      'coverUrl': coverUrl,
      'coverData': coverData,
      'tags': tags,
      'category': category,
      'format': format,
      'owned': owned,
      'status': status,
      'rating': rating,
      'recommend': recommend,
      'notes': notes,
      'room': room,
      'playersMin': playersMin,
      'playersMax': playersMax,
      'playMinutes': playMinutes,
      'ageFrom': ageFrom,
      'loans': loans.map((l) => l.toJson()).toList(),
      if (needsCheck) 'needsCheck': true,
      'lookedUp': lookedUp,
      'source': source,
      'addedAt': addedAt,
      'updatedAt': updatedAt,
    };
    m.removeWhere((k, v) => v == null);
    return m;
  }

  /// Change some fields; a key with value null removes that optional value.
  Item copyWith(Map<String, dynamic> patch) => normalizeItem({...toJson(), ...patch});
}

String? _str(Object? v) {
  if (v is String) {
    final s = v.trim();
    return s.isEmpty ? null : s;
  }
  if (v is num) return v.toString();
  return null;
}

int? _int(Object? v) {
  if (v is int) return v;
  if (v is double) return v.isFinite ? v.round() : null;
  if (v is String) return int.tryParse(v.trim());
  return null;
}

List<String> _strList(Object? v) {
  if (v is List) return v.map(_str).whereType<String>().toList();
  if (v is String && v.trim().isNotEmpty) {
    return v.split(RegExp(r'\s*[;/]\s*|\s+&\s+')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }
  return [];
}

String _oneOf(List<String> list, Object? v, String fallback) => v is String && list.contains(v) ? v : fallback;

/// Only rooms are kept. Older data may still carry a shelf: the photo import put everything
/// in room "Foto-Import" with shelves "Foto 1" … – those shelves become rooms.
String? _roomOf(Map<String, dynamic> r) {
  final room = _str(r['room']);
  final shelf = _str(r['shelf']);
  if (shelf != null && (room == null || room == 'Foto-Import')) return shelf;
  return room;
}

/// Turn anything that looks roughly like an item (form draft, AI result, imported JSON)
/// into a complete, valid Item. Unknown fields are dropped.
Item normalizeItem(Map<String, dynamic> r, {String? now}) {
  now ??= DateTime.now().toUtc().toIso8601String();
  final loans = <Loan>[];
  if (r['loans'] is List) {
    for (final l in r['loans'] as List) {
      if (l is Map) {
        final to = _str(l['to']);
        if (to == null) continue;
        loans.add(Loan(to: to, since: _str(l['since']) ?? today(), returned: _str(l['returned'])));
      } else if (l is Loan) {
        loans.add(l);
      }
    }
  }
  final coverData = r['coverData'];
  final isbn = _str(r['isbn'])?.replaceAll(RegExp(r'[^0-9Xx]'), '');
  return Item(
    id: _str(r['id']) ?? newId(),
    kind: _oneOf(kinds, r['kind'], 'book'),
    title: _str(r['title']) ?? '?',
    subtitle: _str(r['subtitle']),
    creators: _strList(r['creators'] ?? r['authors'] ?? r['author']),
    publisher: _str(r['publisher']),
    year: _int(r['year']),
    isbn: isbn == null || isbn.isEmpty ? null : isbn,
    language: _str(r['language']),
    series: _str(r['series']),
    volume: _str(r['volume']),
    pages: _int(r['pages']),
    description: _str(r['description']),
    coverUrl: _str(r['coverUrl']),
    coverData: coverData is String && coverData.startsWith('data:image/') ? coverData : null,
    tags: _strList(r['tags']),
    category: toCategory(_str(r['category'])),
    format: _oneOf(formats, r['format'], 'physical'),
    owned: r['owned'] != false,
    status: _oneOf(statuses, r['status'], 'none'),
    rating: (_int(r['rating']) ?? 0).clamp(0, 5),
    recommend: r['recommend'] == true,
    notes: _str(r['notes']),
    room: _roomOf(r),
    playersMin: _int(r['playersMin']),
    playersMax: _int(r['playersMax']),
    playMinutes: _int(r['playMinutes']),
    ageFrom: _int(r['ageFrom']),
    loans: loans,
    needsCheck: r['needsCheck'] == true,
    lookedUp: _str(r['lookedUp']),
    source: _oneOf(sources, r['source'], 'manual'),
    addedAt: _str(r['addedAt']) ?? now,
    updatedAt: _str(r['updatedAt']) ?? now,
  );
}

class Settings {
  final String claudeKey;
  final String claudeModel;
  final String googleBooksKey;
  final String lastRoom;

  /// rooms shown even when empty; [] = the default rooms
  final List<String> rooms;

  /// category list in display order; [] = the default categories
  final List<String> categories;

  /// 'de' or 'en'; null = phone language
  final String? lang;

  const Settings({
    this.claudeKey = '',
    this.claudeModel = 'claude-opus-5-5',
    this.googleBooksKey = '',
    this.lastRoom = '',
    this.rooms = const [],
    this.categories = const [],
    this.lang,
  });

  Map<String, dynamic> toJson() => {
        'claudeKey': claudeKey,
        'claudeModel': claudeModel,
        'googleBooksKey': googleBooksKey,
        'lastRoom': lastRoom,
        'rooms': rooms,
        'categories': categories,
        if (lang != null) 'lang': lang,
      };

  factory Settings.fromJson(Map<String, dynamic> j) => Settings(
        claudeKey: _str(j['claudeKey']) ?? '',
        claudeModel: _str(j['claudeModel']) ?? 'claude-opus-5-5',
        googleBooksKey: _str(j['googleBooksKey']) ?? '',
        lastRoom: _str(j['lastRoom']) ?? '',
        rooms: _strList(j['rooms']),
        categories: _strList(j['categories']),
        lang: _str(j['lang']),
      );

  Settings copyWith({String? claudeKey, String? claudeModel, String? googleBooksKey, String? lastRoom, List<String>? rooms, List<String>? categories, String? lang}) => Settings(
        claudeKey: claudeKey ?? this.claudeKey,
        claudeModel: claudeModel ?? this.claudeModel,
        googleBooksKey: googleBooksKey ?? this.googleBooksKey,
        lastRoom: lastRoom ?? this.lastRoom,
        rooms: rooms ?? this.rooms,
        categories: categories ?? this.categories,
        lang: lang ?? this.lang,
      );
}

const defaultRooms = [
  ['Küche', 'Kitchen'],
  ['Wohnzimmer', 'Living room'],
  ['Kleines Zimmer', 'Small room'],
];
