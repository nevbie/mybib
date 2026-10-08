import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';
import 'items.dart';

/// An online search result: item fields plus the service it came from.
class Candidate {
  final Map<String, dynamic> data;
  final String via;
  const Candidate(this.data, this.via);

  String get title => data['title'] as String? ?? '';
  List<String> get creators => (data['creators'] as List?)?.cast<String>() ?? const [];
  String? get coverUrl => data['coverUrl'] as String?;
  String get kind => data['kind'] as String? ?? 'book';

  Candidate withData(Map<String, dynamic> patch) => Candidate({...data, ...patch}, via);
}

/// Swappable for tests.
http.Client lookupClient = http.Client();
const _timeout = Duration(seconds: 12);

Future<(int, dynamic)> _getJson(String url) async {
  try {
    final res = await lookupClient.get(Uri.parse(url), headers: {'User-Agent': 'mybib/1.0 (https://github.com/nevbie/mybib)'}).timeout(_timeout);
    if (res.statusCode != 200) return (res.statusCode, null);
    return (200, jsonDecode(utf8.decode(res.bodyBytes)));
  } catch (_) {
    return (0, null);
  }
}

/// True when the URL is a real image (Open Library / Cover Art Archive answer 404 for "no cover").
Future<bool> probeImage(String url) async {
  try {
    final res = await lookupClient.head(Uri.parse(url)).timeout(_timeout);
    final type = res.headers['content-type'] ?? '';
    final len = int.tryParse(res.headers['content-length'] ?? '') ?? 1000;
    return res.statusCode == 200 && type.startsWith('image/') && len > 200;
  } catch (_) {
    return false;
  }
}

int? _year(String? s) {
  final m = RegExp(r'\d{4}').firstMatch(s ?? '');
  return m == null ? null : int.parse(m.group(0)!);
}

/// Last problem Google Books reported: '' = fine, 'quota' = daily limit reached, 'key' = key rejected.
String _googleProblem = '';
String takeGoogleProblem() {
  final p = _googleProblem;
  _googleProblem = '';
  return p;
}

// ---------- Google Books ----------

Candidate? _fromGoogle(Map v) {
  final i = v['volumeInfo'];
  if (i is! Map || i['title'] is! String) return null;
  String? isbn;
  for (final x in (i['industryIdentifiers'] as List? ?? const [])) {
    if (x is Map && x['type'] == 'ISBN_13') isbn = x['identifier'] as String?;
  }
  final links = i['imageLinks'] as Map?;
  final thumb = (links?['thumbnail'] ?? links?['smallThumbnail']) as String?;
  return Candidate({
    'kind': 'book',
    'title': i['title'],
    'subtitle': i['subtitle'],
    'creators': (i['authors'] as List?)?.cast<String>() ?? <String>[],
    'publisher': i['publisher'],
    'year': _year(i['publishedDate'] as String?),
    'description': i['description'],
    'pages': (i['pageCount'] is int && i['pageCount'] > 0) ? i['pageCount'] : null,
    'language': i['language'],
    'isbn': isbn,
    'coverUrl': thumb?.replaceFirst('http:', 'https:').replaceAll('&edge=curl', ''),
  }..removeWhere((k, v) => v == null), 'Google Books');
}

Future<List<Candidate>> _google(String q, String key, {int max = 8}) async {
  final url = 'https://www.googleapis.com/books/v1/volumes?q=${Uri.encodeQueryComponent(q)}&maxResults=$max&printType=books${key.isNotEmpty ? '&key=${Uri.encodeQueryComponent(key)}' : ''}';
  final (status, data) = await _getJson(url);
  if (status == 429) _googleProblem = 'quota';
  if ((status == 400 || status == 403) && key.isNotEmpty) _googleProblem = 'key';
  final items = data is Map ? data['items'] as List? ?? const [] : const [];
  return items.whereType<Map>().map(_fromGoogle).whereType<Candidate>().toList();
}

// ---------- Open Library ----------

Future<Candidate?> _openLibraryIsbn(String isbn) async {
  final (_, data) = await _getJson('https://openlibrary.org/api/books?bibkeys=ISBN:$isbn&format=json&jscmd=data');
  final b = data is Map ? data['ISBN:$isbn'] : null;
  if (b is! Map || b['title'] is! String) return null;
  final cover = b['cover'] as Map?;
  return Candidate({
    'kind': 'book',
    'title': b['title'],
    'subtitle': b['subtitle'],
    'creators': [for (final a in (b['authors'] as List? ?? const [])) if (a is Map && a['name'] is String) a['name'] as String],
    'publisher': (b['publishers'] as List?)?.whereType<Map>().firstOrNull?['name'],
    'year': _year(b['publish_date'] as String?),
    'pages': b['number_of_pages'],
    'isbn': isbn,
    'coverUrl': cover?['medium'] ?? cover?['large'],
  }..removeWhere((k, v) => v == null), 'Open Library');
}

Future<List<Candidate>> _openLibrarySearch(String params) async {
  const fields = 'title,subtitle,author_name,first_publish_year,publisher,isbn,cover_i,language,number_of_pages_median';
  final (_, data) = await _getJson('https://openlibrary.org/search.json?$params&limit=8&fields=$fields');
  final docs = data is Map ? data['docs'] as List? ?? const [] : const [];
  return docs.whereType<Map>().where((d) => d['title'] is String).map((d) {
    final isbns = (d['isbn'] as List?)?.cast<String>() ?? const <String>[];
    return Candidate({
      'kind': 'book',
      'title': d['title'],
      'subtitle': d['subtitle'],
      'creators': (d['author_name'] as List?)?.cast<String>() ?? <String>[],
      'year': d['first_publish_year'],
      'publisher': (d['publisher'] as List?)?.firstOrNull,
      'isbn': isbns.where((x) => x.length == 13 && x.startsWith('97')).firstOrNull,
      'pages': d['number_of_pages_median'],
      'language': (d['language'] as List?)?.firstOrNull,
      'coverUrl': d['cover_i'] != null ? 'https://covers.openlibrary.org/b/id/${d['cover_i']}-M.jpg' : null,
    }..removeWhere((k, v) => v == null), 'Open Library');
  }).toList();
}

// ---------- MusicBrainz ----------

Future<List<Candidate>> _musicbrainz(String query) async {
  final (_, data) = await _getJson('https://musicbrainz.org/ws/2/release/?query=${Uri.encodeQueryComponent(query)}&fmt=json&limit=8');
  final releases = data is Map ? data['releases'] as List? ?? const [] : const [];
  return releases.whereType<Map>().map((r) {
    final fmt = ((r['media'] as List?)?.whereType<Map>().firstOrNull?['format'] as String?) ?? '';
    return Candidate({
      'kind': RegExp('dvd|blu-ray', caseSensitive: false).hasMatch(fmt) ? 'dvd' : 'cd',
      'title': r['title'],
      'creators': [for (final a in (r['artist-credit'] as List? ?? const [])) if (a is Map && a['name'] is String) a['name'] as String],
      'publisher': ((r['label-info'] as List?)?.whereType<Map>().firstOrNull?['label'] as Map?)?['name'],
      'year': _year(r['date'] as String?),
      'isbn': (r['barcode'] as String?)?.isNotEmpty == true ? r['barcode'] : null,
      'coverUrl': 'https://coverartarchive.org/release/${r['id']}/front-250',
    }..removeWhere((k, v) => v == null), 'MusicBrainz');
  }).toList();
}

Future<List<Candidate>> _upcitemdb(String ean) async {
  final (_, data) = await _getJson('https://api.upcitemdb.com/prod/trial/lookup?upc=$ean');
  final items = data is Map ? data['items'] as List? ?? const [] : const [];
  return items.whereType<Map>().where((x) => x['title'] is String).map((x) {
    final cat = (x['category'] as String?) ?? '';
    final kind = RegExp('game|spiel', caseSensitive: false).hasMatch(cat) ? 'game' : (RegExp('music|cd', caseSensitive: false).hasMatch(cat) ? 'cd' : 'dvd');
    return Candidate({
      'kind': kind,
      'title': x['title'],
      'creators': <String>[],
      'publisher': x['brand'],
      'isbn': ean,
      'coverUrl': (x['images'] as List?)?.whereType<String>().where((u) => u.startsWith('https:')).firstOrNull,
    }..removeWhere((k, v) => v == null), 'UPCitemdb');
  }).toList();
}

// ---------- public API ----------

bool _empty(Object? v) => v == null || v == '' || (v is List && v.isEmpty);

/// Fill gaps in [a] with values from [b] (same book from a second service).
Candidate mergeCandidate(Candidate a, Candidate b) {
  final out = {...a.data};
  b.data.forEach((k, v) {
    if (_empty(out[k])) out[k] = v;
  });
  return Candidate(out, a.via == b.via ? a.via : '${a.via} + ${b.via}');
}

Future<Candidate> withWorkingCover(Candidate c) async {
  final url = c.coverUrl;
  if (url != null && !await probeImage(url)) return Candidate({...c.data}..remove('coverUrl'), c.via);
  return c;
}

/// Look up an ISBN in Google Books and Open Library, merged into one result.
Future<Candidate?> lookupIsbn(String isbn, {String googleKey = ''}) async {
  final results = await Future.wait([_google('isbn:$isbn', googleKey, max: 1), _openLibraryIsbn(isbn).then((c) => c == null ? <Candidate>[] : [c])]);
  final g = results[0].firstOrNull;
  final ol = results[1].firstOrNull;
  Candidate? c;
  if (g != null && ol != null) {
    // Open Library covers are larger and have no "preview" banner; Google usually has the better text.
    c = mergeCandidate(g.withData({if (ol.coverUrl != null) 'coverUrl': ol.coverUrl}), ol);
  } else {
    c = g ?? ol;
  }
  if (c == null) return null;
  c = c.withData({'isbn': isbn});
  if (c.coverUrl == null) {
    final fallback = 'https://covers.openlibrary.org/b/isbn/$isbn-M.jpg?default=false';
    return await probeImage(fallback) ? c.withData({'coverUrl': fallback}) : c;
  }
  return withWorkingCover(c);
}

/// Look up a non-ISBN barcode (CD, DVD, game).
Future<List<Candidate>> lookupEan(String ean) async {
  final mb = await _musicbrainz('barcode:$ean');
  final list = mb.isNotEmpty ? mb : await _upcitemdb(ean);
  return Future.wait(list.take(5).map(withWorkingCover));
}

/// Google Books + Open Library by title / author, merged; covers not checked yet.
Future<List<Candidate>> searchBooks(String title, String creator, {String googleKey = ''}) async {
  final gq = [if (title.isNotEmpty) 'intitle:$title', if (creator.isNotEmpty) 'inauthor:$creator'].join(' ');
  final olq = [if (title.isNotEmpty) 'title=${Uri.encodeQueryComponent(title)}', if (creator.isNotEmpty) 'author=${Uri.encodeQueryComponent(creator)}'].join('&');
  final r = await Future.wait([_google(gq, googleKey), _openLibrarySearch(olq)]);
  return _dedupe([...r[0], ...r[1]]);
}

/// Free-text search by title / creator for the chosen kind.
Future<List<Candidate>> searchOnline(String kind, String title, String creator, {String googleKey = ''}) async {
  title = title.trim();
  creator = creator.trim();
  if (title.isEmpty && creator.isEmpty) return [];
  var list = <Candidate>[];
  if (kind == 'book') {
    list = await searchBooks(title, creator, googleKey: googleKey);
  } else if (kind == 'cd' || kind == 'dvd') {
    final q = [if (title.isNotEmpty) 'release:"${title.replaceAll('"', '')}"', if (creator.isNotEmpty) 'artist:"${creator.replaceAll('"', '')}"'].join(' AND ');
    list = await _musicbrainz(q);
    if (kind == 'dvd') list = [...list.where((c) => c.kind == 'dvd'), ...list.where((c) => c.kind != 'dvd')];
  }
  return Future.wait(list.take(10).map(withWorkingCover));
}

List<Candidate> _dedupe(List<Candidate> list) {
  final out = <Candidate>[];
  String key(Candidate c) => '${fold(c.title)}|${fold(c.creators.firstOrNull ?? '')}';
  for (final c in list) {
    final i = out.indexWhere((o) => key(o) == key(c));
    if (i >= 0) {
      out[i] = mergeCandidate(out[i], c);
    } else {
      out.add(c);
    }
  }
  return out;
}

Set<String> _words(String s) => fold(s).split(' ').where((w) => w.length > 1).toSet();

/// How well does an online result match what we know (e.g. from a spine photo)? 0…1
double matchScore(String title, List<String> creators, Candidate c) {
  final a = _words(title);
  final b = _words('${c.title} ${c.data['subtitle'] ?? ''}');
  if (a.isEmpty) return 0;
  var score = a.where(b.contains).length / a.length;
  if (creators.isNotEmpty) {
    final last = fold(creators.first).split(' ').last;
    final has = c.creators.any((x) => fold(x).contains(last));
    score = score * 0.7 + (has ? 0.3 : 0);
  }
  return score;
}

/// Share of words the two titles have in common (Jaccard), 0…1.
double titleOverlap(String a, String b) {
  final x = fold(a).split(' ').where((w) => w.isNotEmpty).toSet();
  final y = fold(b).split(' ').where((w) => w.isNotEmpty).toSet();
  if (x.isEmpty || y.isEmpty) return 0;
  final common = x.where(y.contains).length;
  return common / (x.length + y.length - common);
}

/// Fill only the fields the item doesn't have yet from an online result.
Map<String, dynamic> enrichPatch(Map<String, dynamic> item, Candidate c) {
  final patch = <String, dynamic>{};
  for (final k in ['subtitle', 'publisher', 'year', 'isbn', 'pages', 'description', 'coverUrl', 'language']) {
    if (_empty(item[k]) && !_empty(c.data[k])) patch[k] = c.data[k];
  }
  if (_empty(item['creators']) && c.creators.isNotEmpty) patch['creators'] = c.creators;
  return patch;
}

/// Best online match for a catalogued item: by ISBN if it has one, otherwise by title + author;
/// accepted only when the title (and author, if known) clearly match.
Future<Candidate?> findBestMatch(Item item, {String googleKey = ''}) async {
  if (item.isbn != null && RegExp(r'^97[89]\d{10}$').hasMatch(item.isbn!)) {
    final c = await lookupIsbn(item.isbn!, googleKey: googleKey);
    if (c != null) return c;
  }
  final list = await searchBooks(item.title, item.creators.firstOrNull ?? '', googleKey: googleKey);
  // without a known author only an (almost) identical title counts – in both directions
  final min = item.creators.isNotEmpty ? 0.75 : 0.95;
  Candidate? best;
  var bestScore = 0.0;
  for (final c in list) {
    final s = item.creators.isNotEmpty ? matchScore(item.title, item.creators, c) : titleOverlap(item.title, c.title);
    if (s > bestScore) {
      best = c;
      bestScore = s;
    }
  }
  return best != null && bestScore >= min ? withWorkingCover(best) : null;
}

/// Item draft (JSON map) from a candidate, ready for normalizeItem / the form.
Map<String, dynamic> candidateDraft(Candidate c, {String source = 'search'}) => {...c.data, 'source': source};
