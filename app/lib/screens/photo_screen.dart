import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../logic/ai.dart';
import '../logic/items.dart';
import '../logic/lookup.dart';
import '../models.dart';
import '../widgets/common.dart';
import '../widgets/photos.dart';
import 'item_form.dart';

class _Row {
  _Row(this.draft, this.confidence, this.remark, this.selected, this.dupTitle);
  Map<String, dynamic> draft;
  final String confidence, remark;
  bool selected;
  final String? dupTitle;
}

/// Add by photo.
/// - shelf: one or more shelf photos → Claude reads all spines → review list → add.
/// - cover: one front cover → (with key) recognise title → online details → form; own photo becomes the cover.
class PhotoScreen extends StatefulWidget {
  const PhotoScreen({super.key, required this.mode});
  final String mode;

  @override
  State<PhotoScreen> createState() => _PhotoScreenState();
}

class _PhotoScreenState extends State<PhotoScreen> {
  final hint = TextEditingController();
  final rows = <_Row>[];
  String status = '';
  bool busy = false, enrich = true;
  String? room;

  String _err(Object e) {
    final s = AppScope.read(context);
    if (e is RecognizeError) return s.t('ai.err.${e.code}') + (e.code == 'other' || e.code == 'parse' ? ' (${e.message})' : '');
    return e.toString();
  }

  Future<List<Recognized>> _recognize(Uint8List jpeg) {
    final st = AppScope.read(context).store.settings;
    return recognizePhoto(apiKey: st.claudeKey, model: st.claudeModel, jpegBytes: jpeg, hint: hint.text);
  }

  Future<void> _shelf(List<Uint8List> photos) async {
    final s = AppScope.read(context);
    setState(() => busy = true);
    for (var n = 0; n < photos.length; n++) {
      setState(() => status = s.t('ai.reading', {'i': n + 1, 'n': photos.length}));
      try {
        final found = await _recognize(photos[n]);
        if (!mounted) return;
        setState(() {
          for (final f in found) {
            final draft = f.toDraft();
            final item = normalizeItem(draft);
            final dup = findDuplicateOf(s.store.items, item)?.title ??
                rows.where((r) => r.draft['title'] == draft['title'] && r.draft['volume'] == draft['volume']).firstOrNull?.draft['title'] as String?;
            rows.add(_Row(draft, f.confidence, f.remark, dup == null, dup));
          }
        });
      } catch (e) {
        if (!mounted) return;
        await infoDialog(context, _err(e));
        if (e is RecognizeError && e.code == 'auth') break;
      }
    }
    if (mounted) {
      setState(() {
        busy = false;
        status = '';
      });
    }
  }

  Future<void> _cover(Uint8List photo) async {
    final s = AppScope.read(context);
    final coverData = 'data:image/jpeg;base64,${base64Encode(photo)}';
    var draft = <String, dynamic>{'title': '', 'coverData': coverData, 'room': (room ?? s.store.settings.lastRoom).ifEmpty};
    if (s.store.settings.claudeKey.isNotEmpty) {
      setState(() {
        busy = true;
        status = s.t('ai.readingCover');
      });
      try {
        final first = (await _recognize(photo)).firstOrNull;
        if (first != null) {
          draft = {...draft, ...first.toDraft(), 'coverData': coverData, 'source': 'search'};
          if (mounted) setState(() => status = s.t('ai.enriching'));
          final found = await searchOnline(first.kind, first.title, first.creators.firstOrNull ?? '', googleKey: s.store.settings.googleBooksKey);
          final best = found.where((c) => matchScore(first.title, first.creators, c) >= 0.75).firstOrNull;
          if (best != null) draft = {...draft, ...enrichPatch(draft, best), 'needsCheck': false}..remove('coverUrl');
        }
      } catch (e) {
        if (mounted) await infoDialog(context, _err(e));
      }
    }
    if (!mounted) return;
    setState(() {
      busy = false;
      status = '';
    });
    Navigator.pop(context);
    openForm(context, draft: draft);
  }

  Future<void> _take(bool camera) async {
    if (widget.mode == 'cover') {
      // one photo, large enough to read the title and small enough to keep as the cover
      final photo = await pickPhoto(camera: camera, maxEdge: 1000, quality: 80);
      if (photo != null) await _cover(photo);
    } else if (camera) {
      final p = await pickPhoto(camera: true, maxEdge: 2400, quality: 88);
      if (p != null) await _shelf([p]);
    } else {
      final ps = await pickPhotos(maxEdge: 2400);
      if (ps.isNotEmpty) await _shelf(ps);
    }
  }

  Future<void> _addAll() async {
    final s = AppScope.read(context);
    final sel = rows.where((r) => r.selected).toList();
    final r0 = room ?? s.store.settings.lastRoom;
    setState(() => busy = true);
    final drafts = <Map<String, dynamic>>[];
    for (var n = 0; n < sel.length; n++) {
      var d = {...sel[n].draft, 'room': r0.ifEmpty};
      final kind = d['kind'] as String;
      if (enrich && (kind == 'book' || kind == 'cd')) {
        setState(() => status = s.t('ai.enrichingN', {'i': n + 1, 'n': sel.length}));
        final title = d['title'] as String;
        final creators = (d['creators'] as List).cast<String>();
        final found = await searchOnline(kind, title, creators.firstOrNull ?? '', googleKey: s.store.settings.googleBooksKey).catchError((_) => <Candidate>[]);
        final best = found.where((c) => matchScore(title, creators, c) >= 0.75).firstOrNull;
        // keep the title as printed on the spine, only fill gaps
        if (best != null) d = {...d, ...enrichPatch(d, best)};
        // MusicBrainz asks for max. 1 request per second
        if (kind == 'cd') await Future<void>.delayed(const Duration(seconds: 1));
      }
      drafts.add(d);
    }
    s.store.addItems(drafts);
    s.store.updateSettings(s.store.settings.copyWith(lastRoom: r0));
    if (!mounted) return;
    await infoDialog(context, s.t('ai.added', {'n': drafts.length}));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final hasKey = s.store.settings.claudeKey.isNotEmpty;
    final shelf = widget.mode == 'shelf';
    final selected = rows.where((r) => r.selected).length;
    return Scaffold(
      appBar: AppBar(title: Text(shelf ? s.t('add.shelf') : s.t('add.cover'))),
      bottomNavigationBar: rows.isEmpty
          ? null
          : SafeArea(child: Padding(padding: const EdgeInsets.all(12), child: FilledButton(onPressed: busy || selected == 0 ? null : _addAll, child: Text(s.t('ai.addN', {'n': selected}))))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (shelf && !hasKey)
          Card(color: Colors.amber.shade100, child: Padding(padding: const EdgeInsets.all(12), child: Text(s.t('ai.noKey'), style: const TextStyle(color: Colors.black87)))),
        if (!shelf) Text(hasKey ? s.t('ai.coverHint') : s.t('ai.coverNoKey'), style: Theme.of(context).textTheme.bodySmall),
        if (shelf && hasKey) Text(s.t('ai.shelfHint'), style: Theme.of(context).textTheme.bodySmall),
        SuggestField(value: room ?? s.store.settings.lastRoom, options: s.store.rooms(s.lang), label: s.t('field.room'), onChanged: (v) => room = v.trim()),
        if (hasKey) TextField(controller: hint, decoration: InputDecoration(labelText: s.t('ai.hintPh'))),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: FilledButton.icon(onPressed: busy || (shelf && !hasKey) ? null : () => _take(true), icon: const Icon(Icons.photo_camera), label: Text(s.t('ai.camera')))),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton.icon(onPressed: busy || (shelf && !hasKey) ? null : () => _take(false), icon: const Icon(Icons.photo_library), label: Text(s.t('ai.gallery')))),
        ]),
        if (status.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(children: [const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)), const SizedBox(width: 12), Expanded(child: Text(status))]),
          ),
        if (rows.isNotEmpty) ...[
          Row(children: [
            Expanded(child: Text(s.t('ai.found', {'n': rows.length}), style: const TextStyle(fontWeight: FontWeight.bold))),
            TextButton(onPressed: () => setState(() => [for (final r in rows) r.selected = selected == 0]), child: Text(selected > 0 ? s.t('ai.none') : s.t('ai.all'))),
          ]),
          SwitchListTile(contentPadding: EdgeInsets.zero, value: enrich, onChanged: (v) => setState(() => enrich = v), title: Text(s.t('ai.enrich'))),
          for (final r in rows)
            Opacity(
              opacity: r.selected ? 1 : 0.5,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 12, 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Checkbox(value: r.selected, onChanged: (v) => setState(() => r.selected = v!)),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        TextFormField(initialValue: r.draft['title'] as String, style: const TextStyle(fontWeight: FontWeight.w600), decoration: const InputDecoration(isDense: true, border: InputBorder.none), onChanged: (v) => r.draft['title'] = v),
                        TextFormField(
                          initialValue: (r.draft['creators'] as List).join(', '),
                          decoration: InputDecoration(isDense: true, border: InputBorder.none, hintText: s.t('creator.${r.draft['kind']}')),
                          onChanged: (v) => r.draft['creators'] = v.split(',').map((x) => x.trim()).where((x) => x.isNotEmpty).toList(),
                        ),
                        Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          DropdownButton<String>(
                            value: r.draft['kind'] as String,
                            isDense: true,
                            items: [for (final k in kinds) DropdownMenuItem(value: k, child: Text('${kindIcon[k]} ${s.t('kind.$k')}'))],
                            onChanged: (v) => setState(() => r.draft['kind'] = v),
                          ),
                          if (r.draft['series'] != null || r.draft['volume'] != null) Text([r.draft['series'], r.draft['volume']].whereType<String>().join(' ')),
                          if (r.confidence != 'high') Badge2(s.t('ai.conf.${r.confidence}'), color: Colors.amber.shade200),
                          if (r.dupTitle != null) Badge2(s.t('ai.dup'), color: Colors.pink.shade100),
                        ]),
                        if (r.remark.isNotEmpty) Text(r.remark, style: Theme.of(context).textTheme.bodySmall),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
        ],
      ]),
    );
  }
}

extension on String {
  String? get ifEmpty => isEmpty ? null : this;
}
