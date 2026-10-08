import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mybib/logic/ai.dart';
import 'package:mybib/logic/lookup.dart';
import 'package:mybib/models.dart';

Map<String, dynamic> vol(String title, List<String> authors) => {
      'volumeInfo': {
        'title': title,
        'authors': authors,
        'publisher': 'Suhrkamp',
        'publishedDate': '2012-03-01',
        'industryIdentifiers': [{'type': 'ISBN_13', 'identifier': '9783518464547'}],
        'imageLinks': {'thumbnail': 'http://books.google.com/x&edge=curl'},
      },
    };

void mock(http.Response Function(Uri u) handler) {
  lookupClient = MockClient((req) async {
    if (req.method == 'HEAD') return http.Response('', 200, headers: {'content-type': 'image/jpeg', 'content-length': '5000'});
    return handler(req.url);
  });
}

http.Response json(Object o, [int status = 200]) => http.Response.bytes(utf8.encode(jsonEncode(o)), status);
Item item(Map<String, dynamic> p) => normalizeItem({'title': 'x', ...p});

void main() {
  test('takes a clear title + author match', () async {
    mock((u) => u.host.contains('googleapis') ? json({'items': [vol('Something else', ['X']), vol('Open City', ['Teju Cole'])]}) : json({'docs': []}));
    final c = await findBestMatch(item({'title': 'Open City', 'creators': ['Teju Cole']}));
    expect(c?.data['publisher'], 'Suhrkamp');
    expect(c?.coverUrl, 'https://books.google.com/x');
  });
  test('rejects a different author and loose titles without author', () async {
    mock((u) => u.host.contains('googleapis') ? json({'items': [vol('Open City', ['Someone Else'])]}) : json({'docs': []}));
    expect(await findBestMatch(item({'title': 'Open City', 'creators': ['Teju Cole']})), isNull);
    mock((u) => u.host.contains('googleapis') ? json({'items': [vol('Sahara Reiseführer Marokko', ['A'])]}) : json({'docs': []}));
    expect(await findBestMatch(item({'title': 'Sahara Marokko'})), isNull);
  });
  test('reports the Google quota', () async {
    mock((u) => u.host.contains('googleapis') ? json({}, 429) : json({'docs': []}));
    takeGoogleProblem();
    expect(await findBestMatch(item({'title': 'Open City', 'creators': ['Teju Cole']})), isNull);
    expect(takeGoogleProblem(), 'quota');
    expect(takeGoogleProblem(), '');
  });
  test('enrichPatch fills only empty fields', () {
    final c = Candidate({'title': 'Open City', 'creators': ['Teju Cole'], 'publisher': 'Suhrkamp', 'year': 2012, 'coverUrl': 'c'}, 'g');
    expect(enrichPatch({'title': 'Open City', 'creators': ['Teju Cole'], 'publisher': 'Mein Verlag'}, c), {'year': 2012, 'coverUrl': 'c'});
  });
  test('Claude photo recognition parses structured output and errors', () async {
    late Map<String, dynamic> sent;
    aiClient = MockClient((req) async {
      sent = jsonDecode(req.body) as Map<String, dynamic>;
      expect(req.headers['x-api-key'], 'k');
      return json({
        'stop_reason': 'end_turn',
        'content': [
          {'type': 'text', 'text': jsonEncode({'items': [{'kind': 'book', 'title': ' 金瓶梅词话 ', 'creators': ['兰陵笑笑生'], 'series': '', 'volume': '3', 'publisher': '', 'language': 'zh', 'confidence': 'medium', 'remark': 'blurry'}]})},
        ],
      });
    });
    final r = await recognizePhoto(apiKey: 'k', model: 'claude-opus-5-5', jpegBytes: [1, 2, 3]);
    expect(sent['model'], 'claude-opus-5-5');
    expect(r.single.toDraft(), {'kind': 'book', 'title': '金瓶梅词话', 'creators': ['兰陵笑笑生'], 'volume': '3', 'language': 'zh', 'needsCheck': true, 'source': 'ai'});
    aiClient = MockClient((req) async => json({'error': {}}, 401));
    expect(() => recognizePhoto(apiKey: 'bad', model: 'm', jpegBytes: [1]), throwsA(isA<RecognizeError>().having((e) => e.code, 'code', 'auth')));
  });
}
