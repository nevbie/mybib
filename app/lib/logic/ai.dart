import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';

/// Recognise items on a shelf photo (or a single cover) with Claude's vision.
/// The API key is the user's own, stored only on this device and sent only to api.anthropic.com.

class Recognized {
  final String kind, title, series, volume, publisher, language, confidence, remark;
  final List<String> creators;
  const Recognized({required this.kind, required this.title, required this.creators, this.series = '', this.volume = '', this.publisher = '', this.language = '', this.confidence = 'high', this.remark = ''});

  factory Recognized.fromJson(Map j) => Recognized(
        kind: kinds.contains(j['kind']) ? j['kind'] as String : 'book',
        title: (j['title'] as String? ?? '').trim(),
        creators: [for (final c in (j['creators'] as List? ?? const [])) if (c is String && c.trim().isNotEmpty) c.trim()],
        series: j['series'] as String? ?? '',
        volume: j['volume'] as String? ?? '',
        publisher: j['publisher'] as String? ?? '',
        language: j['language'] as String? ?? '',
        confidence: j['confidence'] as String? ?? 'high',
        remark: j['remark'] as String? ?? '',
      );

  /// Item draft for normalizeItem / the form.
  Map<String, dynamic> toDraft() => {
        'kind': kind,
        'title': title,
        'creators': creators,
        if (series.isNotEmpty) 'series': series,
        if (volume.isNotEmpty) 'volume': volume,
        if (publisher.isNotEmpty) 'publisher': publisher,
        if (language.isNotEmpty) 'language': language,
        if (confidence != 'high') 'needsCheck': true,
        'source': 'ai',
      };
}

class RecognizeError implements Exception {
  /// auth, refusal, rate, network, parse, other
  final String code;
  final String message;
  const RecognizeError(this.code, this.message);
  @override
  String toString() => message;
}

const _schema = {
  'type': 'object',
  'additionalProperties': false,
  'required': ['items'],
  'properties': {
    'items': {
      'type': 'array',
      'items': {
        'type': 'object',
        'additionalProperties': false,
        'required': ['kind', 'title', 'creators', 'series', 'volume', 'publisher', 'language', 'confidence', 'remark'],
        'properties': {
          'kind': {'type': 'string', 'enum': kinds},
          'title': {'type': 'string'},
          'creators': {'type': 'array', 'items': {'type': 'string'}},
          'series': {'type': 'string'},
          'volume': {'type': 'string'},
          'publisher': {'type': 'string'},
          'language': {'type': 'string'},
          'confidence': {'type': 'string', 'enum': ['high', 'medium', 'low']},
          'remark': {'type': 'string'},
        },
      },
    },
  },
};

const _prompt = '''This photo shows part of a private home library: book spines (often vertical, sometimes upside down or lying flat), maybe also front covers, board game boxes, DVDs or CDs.

List every item whose spine or cover you can see, from left to right and top to bottom. For each item:
- kind: "book" (including comics, picture books, magazines-with-ISBN), "game" (board/card games), "dvd" (DVD/Blu-ray) or "cd" (music CDs, audio-book CDs count as "cd").
- title: exactly as printed, in the original script (keep Chinese characters as characters, German umlauts, etc.). Use the book's real title, not the series name, when both are visible.
- creators: authors / artists / directors / designers as printed (empty array if none visible). If you are confident who the author is from the title alone (a well-known book), you may add them and say so in remark.
- series and volume: e.g. "Asterix" / "36", "bpb Schriftenreihe" / "11128", Chinese multi-volume sets "金瓶梅词话" / "1".
- publisher: if visible on the spine (Reclam, dtv, Carlsen, Ravensburger, btb, Hanser …), else "".
- language: ISO 639-1 code of the item's language ("de", "en", "zh", "tr", "la", "fr" …), "" if unclear.
- confidence: "high" if clearly readable, "medium" if partly guessed, "low" if mostly guessed.
- remark: short note on what was unclear, else "".

Skip things that are not catalogue items (folders, loose papers, boxes of toys, stacks of newspapers, notebooks without a title). Do not invent items you cannot see. If a spine is too blurry to read at all, skip it rather than guessing wildly.''';

/// Swappable for tests.
http.Client aiClient = http.Client();

Future<List<Recognized>> recognizePhoto({required String apiKey, required String model, required List<int> jpegBytes, String hint = ''}) async {
  final body = {
    'model': model,
    'max_tokens': 16000,
    'fallbacks': 'default',
    'output_config': {
      'effort': 'medium',
      'format': {'type': 'json_schema', 'schema': _schema},
    },
    'messages': [
      {
        'role': 'user',
        'content': [
          {
            'type': 'image',
            'source': {'type': 'base64', 'media_type': 'image/jpeg', 'data': base64Encode(jpegBytes)},
          },
          {'type': 'text', 'text': _prompt + (hint.trim().isNotEmpty ? '\n\nHint from the owner: ${hint.trim()}' : '')},
        ],
      },
    ],
  };
  http.Response res;
  try {
    res = await aiClient
        .post(
          Uri.parse('https://api.anthropic.com/v1/messages'),
          headers: {
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
            'anthropic-beta': 'server-side-fallback-2026-07-01',
            'content-type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(minutes: 5));
  } catch (e) {
    throw RecognizeError('network', e.toString());
  }
  final text = utf8.decode(res.bodyBytes);
  if (res.statusCode == 401 || res.statusCode == 403) throw RecognizeError('auth', text);
  if (res.statusCode == 429 || res.statusCode == 529) throw RecognizeError('rate', text);
  if (res.statusCode != 200) throw RecognizeError('other', 'HTTP ${res.statusCode}');
  final msg = jsonDecode(text) as Map;
  if (msg['stop_reason'] == 'refusal') throw RecognizeError('refusal', (msg['stop_details'] as Map?)?['explanation'] as String? ?? 'refused');
  final out = StringBuffer();
  for (final b in (msg['content'] as List? ?? const [])) {
    if (b is Map && b['type'] == 'text') out.write(b['text']);
  }
  try {
    final parsed = jsonDecode(out.toString()) as Map;
    return [for (final i in parsed['items'] as List) Recognized.fromJson(i as Map)].where((r) => r.title.isNotEmpty).toList();
  } catch (_) {
    throw RecognizeError('parse', msg['stop_reason'] == 'max_tokens' ? 'too many items in one photo – try a closer photo' : 'unexpected answer');
  }
}
