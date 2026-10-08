import 'package:flutter/material.dart';

import '../app_state.dart';
import '../logic/lookup.dart';
import '../widgets/common.dart';

/// Search Google Books / Open Library / MusicBrainz and return the picked result (or null).
Future<Candidate?> pickCandidate(BuildContext context, {String kind = 'book', String title = '', String creator = ''}) =>
    Navigator.push<Candidate>(context, MaterialPageRoute(builder: (_) => SearchScreen(kind: kind, title: title, creator: creator)));

const _searchable = ['book', 'cd', 'dvd'];

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.kind, required this.title, required this.creator});
  final String kind, title, creator;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late String kind = _searchable.contains(widget.kind) ? widget.kind : 'book';
  late final title = TextEditingController(text: widget.title);
  late final creator = TextEditingController(text: widget.creator);
  bool busy = false;
  List<Candidate>? results;

  @override
  void initState() {
    super.initState();
    if (widget.title.trim().isNotEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (title.text.trim().isEmpty && creator.text.trim().isEmpty) return;
    final s = AppScope.read(context);
    setState(() {
      busy = true;
      results = null;
    });
    final r = await searchOnline(kind, title.text, creator.text, googleKey: s.store.settings.googleBooksKey);
    if (mounted) {
      setState(() {
        busy = false;
        results = r;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('search.title'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SegmentedButton<String>(
          segments: [for (final k in _searchable) ButtonSegment(value: k, label: Text(s.t('kind.$k')))],
          selected: {kind},
          showSelectedIcon: false,
          onSelectionChanged: (v) => setState(() => kind = v.first),
        ),
        TextField(controller: title, decoration: InputDecoration(labelText: s.t('field.title')), textInputAction: TextInputAction.search, onSubmitted: (_) => _run()),
        TextField(controller: creator, decoration: InputDecoration(labelText: s.t('creator.$kind')), textInputAction: TextInputAction.search, onSubmitted: (_) => _run()),
        const SizedBox(height: 10),
        FilledButton.icon(onPressed: busy ? null : _run, icon: const Icon(Icons.search), label: Text(busy ? s.t('search.busy') : s.t('search.go'))),
        if (busy) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
        if (results != null && results!.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(s.t('search.none'))),
        for (final c in results ?? const <Candidate>[])
          InkWell(
            onTap: () => Navigator.pop(context, c),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CoverImage(title: c.title, kind: c.kind, coverUrl: c.coverUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (c.data['subtitle'] != null) Text('${c.data['subtitle']}'),
                    Text(c.creators.join(', ')),
                    Text([c.data['publisher'], c.data['year'], c.data['language'], c.via].where((x) => x != null).join(' · '), style: Theme.of(context).textTheme.bodySmall),
                  ]),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}
