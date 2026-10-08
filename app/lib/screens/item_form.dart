import 'package:flutter/material.dart';

import '../app_state.dart';
import '../logic/isbn.dart';
import '../logic/items.dart';
import '../logic/lookup.dart';
import '../models.dart';
import '../widgets/common.dart';
import '../widgets/photos.dart';
import 'item_screen.dart';
import 'search_screen.dart';

/// New entry (optionally prefilled from [draft]) or edit an existing one ([id]).
Future<void> openForm(BuildContext context, {String? id, Map<String, dynamic>? draft}) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => ItemForm(id: id, draft: draft)));

class ItemForm extends StatefulWidget {
  const ItemForm({super.key, this.id, this.draft});
  final String? id;
  final Map<String, dynamic>? draft;

  @override
  State<ItemForm> createState() => _ItemFormState();
}

const _textFields = ['title', 'subtitle', 'series', 'volume', 'publisher', 'year', 'isbn', 'language', 'pages', 'ageFrom', 'playersMin', 'playersMax', 'playMinutes', 'room', 'notes'];

class _ItemFormState extends State<ItemForm> {
  late Map<String, dynamic> d;
  final ctl = <String, TextEditingController>{};
  final creators = TextEditingController();
  final tags = TextEditingController();
  bool _init = false;

  void _load(Map<String, dynamic> m) {
    d = {...m};
    for (final k in _textFields) {
      (ctl[k] ??= TextEditingController()).text = m[k]?.toString() ?? '';
    }
    creators.text = ((m['creators'] as List?) ?? const []).join(', ');
    tags.text = ((m['tags'] as List?) ?? const []).join(', ');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final s = AppScope.read(context);
    final existing = widget.id == null ? null : s.store.byId(widget.id!);
    _load(existing?.toJson() ??
        {
          'kind': 'book',
          'format': 'physical',
          'owned': true,
          'status': 'none',
          if (s.store.settings.lastRoom.isNotEmpty) 'room': s.store.settings.lastRoom,
          ...?widget.draft,
        });
  }

  @override
  void dispose() {
    for (final c in ctl.values) {
      c.dispose();
    }
    creators.dispose();
    tags.dispose();
    super.dispose();
  }

  List<String> _split(String v) => v.split(RegExp(r'[,;]')).map((x) => x.trim()).where((x) => x.isNotEmpty).toList();

  Map<String, dynamic> _full() => {
        ...d,
        for (final k in _textFields) k: ctl[k]!.text.trim().isEmpty ? null : ctl[k]!.text.trim(),
        'creators': _split(creators.text),
        'tags': _split(tags.text),
      };

  Future<void> _fillOnline() async {
    final c = await pickCandidate(context, kind: d['kind'] as String, title: ctl['title']!.text, creator: _split(creators.text).firstOrNull ?? '');
    if (c == null) return;
    final cur = _full();
    final patch = ctl['title']!.text.trim().isEmpty ? {...c.data} : enrichPatch(cur, c);
    setState(() => _load({...cur, ...patch, 'kind': d['kind'], 'source': widget.id != null ? d['source'] : 'search'}));
  }

  Future<void> _photo(bool camera) async {
    final data = await pickCoverPhoto(camera: camera);
    if (data != null) setState(() => d['coverData'] = data);
  }

  void _save() {
    final s = AppScope.read(context);
    final v = _full();
    if ((v['title'] as String?)?.isEmpty ?? true) return;
    final code = v['isbn'] is String ? classifyCode(v['isbn'] as String) : null;
    if (code != null) v['isbn'] = code.code;
    if (widget.id != null) {
      s.store.updateItem(widget.id!, v);
    } else {
      s.store.addItems([v]);
      s.store.updateSettings(s.store.settings.copyWith(lastRoom: (v['room'] as String?) ?? ''));
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final kind = d['kind'] as String;
    final isBook = kind == 'book';
    final full = _full();
    final dup = widget.id == null && ctl['title']!.text.trim().isNotEmpty ? findDuplicateOf(s.store.items, normalizeItem(full)) : null;

    Widget field(String k, String label, {bool number = false, String? hint}) => TextField(
          controller: ctl[k],
          keyboardType: number ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(labelText: label, hintText: hint),
          onChanged: k == 'title' ? (_) => setState(() {}) : null,
        );
    Widget two(Widget a, Widget b) => Row(children: [Expanded(child: a), const SizedBox(width: 10), Expanded(child: b)]);

    return Scaffold(
      appBar: AppBar(title: Text(widget.id != null ? s.t('form.edit') : s.t('form.new'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SegmentedButton<String>(
          segments: [for (final k in kinds) ButtonSegment(value: k, label: Text(s.t('kind.$k')))],
          selected: {kind},
          showSelectedIcon: false,
          onSelectionChanged: (v) => setState(() {
            d['kind'] = v.first;
            if (v.first != 'book') d['format'] = 'physical';
          }),
        ),
        const SizedBox(height: 10),
        CategoryDropdown(key: ValueKey('cat-${d['category']}'), value: (d['category'] as String?) ?? '', onChanged: (v) => setState(() => d['category'] = v.isEmpty ? null : v)),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CoverImage(title: ctl['title']!.text.isEmpty ? '?' : ctl['title']!.text, kind: kind, coverUrl: d['coverUrl'] as String?, coverData: d['coverData'] as String?, large: true),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              OutlinedButton.icon(onPressed: () => _photo(true), icon: const Icon(Icons.photo_camera), label: Text(s.t('cover.camera'))),
              OutlinedButton.icon(onPressed: () => _photo(false), icon: const Icon(Icons.photo_library), label: Text(s.t('cover.gallery'))),
              if (d['coverData'] != null || d['coverUrl'] != null)
                TextButton(onPressed: () => setState(() => d..remove('coverData')..remove('coverUrl')), child: Text(s.t('form.coverRemove'))),
              OutlinedButton.icon(onPressed: kind == 'game' ? null : _fillOnline, icon: const Icon(Icons.search), label: Text(s.t('form.fillOnline'), textAlign: TextAlign.center)),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        field('title', '${s.t('field.title')} *'),
        if (dup != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: InkWell(onTap: () => openItem(context, dup.id), child: Text('⚠︎ ${s.t('form.duplicate')} ${dup.title}', style: TextStyle(color: Colors.amber.shade900))),
          ),
        TextField(controller: creators, decoration: InputDecoration(labelText: s.t('creator.$kind'), hintText: s.t('form.commaHint'))),
        if (isBook) field('subtitle', s.t('field.subtitle')),
        two(field('series', s.t('field.seriesOnly')), field('volume', s.t('field.volume'))),
        two(field('publisher', s.t(kind == 'cd' ? 'field.label' : 'field.publisher')), field('year', s.t('field.year'), number: true)),
        two(field('isbn', s.t(isBook ? 'field.isbn' : 'field.ean'), number: true), field('language', s.t('field.language'), hint: 'de, en, zh …')),
        two(isBook ? field('pages', s.t('field.pages'), number: true) : const SizedBox(), field('ageFrom', s.t('field.ageFrom'), number: true)),
        if (kind == 'game') ...[
          two(field('playersMin', s.t('field.playersMin'), number: true), field('playersMax', s.t('field.playersMax'), number: true)),
          field('playMinutes', s.t('field.playMinutes'), number: true),
        ],
        const SizedBox(height: 14),
        if (isBook)
          SegmentedButton<String>(
            segments: [for (final f in formats) ButtonSegment(value: f, label: Text(s.t('format.$f')))],
            selected: {d['format'] as String? ?? 'physical'},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() => d['format'] = v.first),
          ),
        DropdownButtonFormField<String>(
          initialValue: d['status'] as String? ?? 'none',
          decoration: InputDecoration(labelText: s.t('detail.status')),
          items: [for (final st in statuses) DropdownMenuItem(value: st, child: Text(s.t('status.$kind.$st')))],
          onChanged: (v) => setState(() => d['status'] = v),
        ),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: d['owned'] == false, onChanged: (v) => setState(() => d['owned'] = !v), title: Text(s.t('detail.wishlist'))),
        if (d['owned'] != false && (d['format'] ?? 'physical') == 'physical')
          SuggestField(value: ctl['room']!.text, options: s.store.rooms(s.lang), label: s.t('field.room'), onChanged: (v) => ctl['room']!.text = v),
        TextField(controller: tags, decoration: InputDecoration(labelText: s.t('field.tags'), hintText: s.t('form.tagsHint'))),
        TextField(controller: ctl['notes'], maxLines: null, minLines: 2, decoration: InputDecoration(labelText: s.t('field.notes'))),
        const SizedBox(height: 20),
        FilledButton(onPressed: ctl['title']!.text.trim().isEmpty ? null : _save, child: Text(s.t('save'))),
        const SizedBox(height: 30),
      ]),
    );
  }
}
