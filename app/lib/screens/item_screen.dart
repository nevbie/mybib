import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import '../logic/items.dart';
import '../logic/lookup.dart';
import '../models.dart';
import '../widgets/common.dart';
import '../widgets/photos.dart';
import 'item_form.dart';
import 'search_screen.dart';

Future<void> openItem(BuildContext context, String id) => Navigator.push(context, MaterialPageRoute(builder: (_) => ItemScreen(id: id)));

String shareText(Item item, AppState s) {
  final lines = ['${item.title}${item.creators.isNotEmpty ? ' – ${item.creators.join(', ')}' : ''}'];
  if (item.rating > 0) lines.add('★' * item.rating + '☆' * (5 - item.rating));
  if (item.notes != null) lines.add(item.notes!);
  if (item.recommend) lines.add(s.t('share.recommend'));
  return lines.join('\n');
}

String? shareUrl(Item item) {
  if (item.isbn == null) return null;
  if (item.kind == 'book') return 'https://openlibrary.org/isbn/${item.isbn}';
  if (item.kind == 'cd') return 'https://musicbrainz.org/search?type=release&query=barcode:${item.isbn}';
  return null;
}

/// Look an item up online and fill its empty fields with the chosen result.
Future<void> enrichItem(BuildContext context, Item item) async {
  final s = AppScope.read(context);
  final c = await pickCandidate(context, kind: item.kind, title: item.title, creator: item.creators.firstOrNull ?? '');
  if (c == null) return;
  s.store.updateItem(item.id, {...enrichPatch(item.toJson(), c), 'needsCheck': false});
}

class ItemScreen extends StatefulWidget {
  const ItemScreen({super.key, required this.id});
  final String id;

  @override
  State<ItemScreen> createState() => _ItemScreenState();
}

class _ItemScreenState extends State<ItemScreen> {
  bool coverMenu = false, lending = false, moreInfo = false;
  final lendTo = TextEditingController();
  TextEditingController? notes;

  @override
  void dispose() {
    lendTo.dispose();
    notes?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final item = s.store.byId(widget.id);
    if (item == null) return const Scaffold();
    final cs = Theme.of(context).colorScheme;
    void up(Map<String, dynamic> p) => s.store.updateItem(item.id, p);
    notes ??= TextEditingController(text: item.notes ?? '');
    final loan = item.openLoan;
    String fmtDate(String d) {
      final p = d.split('-');
      return p.length == 3 ? (s.lang == 'de' ? '${int.parse(p[2])}.${int.parse(p[1])}.${p[0]}' : d) : d;
    }

    Future<void> setCover(bool camera) async {
      final data = await pickCoverPhoto(camera: camera);
      if (data != null) up({'coverData': data});
      setState(() => coverMenu = false);
    }

    Future<void> share() async {
      final url = shareUrl(item);
      await SharePlus.instance.share(ShareParams(text: url == null ? shareText(item, s) : '${shareText(item, s)}\n$url', subject: item.title));
    }

    Future<void> delete() async {
      if (!await confirmDialog(context, s.t('detail.deleteConfirm', {'title': item.title}))) return;
      s.store.removeItems([item.id]);
      if (context.mounted) Navigator.pop(context);
    }

    final facts = <(String, String?)>[
      (s.t('field.series'), [item.series, item.volume].whereType<String>().join(' · ').ifEmpty),
      (s.t('field.publisher'), item.publisher),
      (s.t('field.year'), item.year?.toString()),
      (s.t('field.pages'), item.pages?.toString()),
      (s.t('field.language'), item.language),
      (s.t('field.isbn'), item.isbn),
      (s.t('field.players'), item.playersMin == null ? null : '${item.playersMin}${item.playersMax != null && item.playersMax != item.playersMin ? '–${item.playersMax}' : ''}'),
      (s.t('field.playMinutes'), item.playMinutes?.toString()),
      (s.t('field.ageFrom'), item.ageFrom == null ? null : '${item.ageFrom}+'),
      (s.t('field.tags'), item.tags.join(', ').ifEmpty),
    ].where((f) => f.$2 != null).toList();

    Widget h(String text) => Padding(padding: const EdgeInsets.only(top: 18, bottom: 6), child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)));

    return Scaffold(
      appBar: AppBar(title: Text('${kindIcon[item.kind]} ${s.t('kind.${item.kind}')}'), actions: [
        IconButton(onPressed: share, icon: const Icon(Icons.share), tooltip: s.t('detail.share')),
        IconButton(onPressed: () => openForm(context, id: item.id), icon: const Icon(Icons.edit), tooltip: s.t('detail.edit')),
        IconButton(onPressed: delete, icon: const Icon(Icons.delete_outline), tooltip: s.t('detail.delete')),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(
            button: true,
            label: s.t('cover.change'),
            child: GestureDetector(
              onTap: () => setState(() => coverMenu = !coverMenu),
              child: Stack(clipBehavior: Clip.none, children: [
                CoverImage.item(item, large: true),
                Positioned(right: -6, bottom: -6, child: CircleAvatar(radius: 15, backgroundColor: cs.surface, child: const Text('📷', style: TextStyle(fontSize: 14)))),
              ]),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.title, style: Theme.of(context).textTheme.titleLarge),
              if (item.subtitle != null) Text(item.subtitle!, style: TextStyle(color: cs.onSurfaceVariant)),
              if (item.creators.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(item.creators.join(', '), style: const TextStyle(fontWeight: FontWeight.w600))),
              const SizedBox(height: 6),
              Stars(value: item.rating, onChanged: (r) => up({'rating': r})),
            ]),
          ),
        ]),
        if (coverMenu)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(onPressed: () => setCover(true), icon: const Icon(Icons.photo_camera), label: Text(s.t('cover.camera'))),
              OutlinedButton.icon(onPressed: () => setCover(false), icon: const Icon(Icons.photo_library), label: Text(s.t('cover.gallery'))),
              if (item.coverData != null)
                TextButton(onPressed: () => setState(() {
                      up({'coverData': null});
                      coverMenu = false;
                    }), child: Text(item.coverUrl != null ? s.t('cover.useOnline') : s.t('form.coverRemove'))),
            ]),
          ),
        if (item.needsCheck)
          Card(
            color: Colors.amber.shade100,
            margin: const EdgeInsets.only(top: 14),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.t('detail.needsCheck'), style: const TextStyle(color: Colors.black87)),
                Wrap(spacing: 8, children: [
                  TextButton(onPressed: () => up({'needsCheck': false}), child: Text('✓ ${s.t('detail.checked')}')),
                  TextButton(onPressed: () => enrichItem(context, item), child: Text('🔎 ${s.t('detail.enrich')}')),
                ]),
              ]),
            ),
          ),
        h(s.t('detail.status')),
        SegmentedButton<String>(
          segments: [for (final st in statuses) ButtonSegment(value: st, label: Text(s.t('status.${item.kind}.$st'), textAlign: TextAlign.center))],
          selected: {item.status},
          showSelectedIcon: false,
          onSelectionChanged: (v) => up({'status': v.first}),
        ),
        const SizedBox(height: 14),
        CategoryDropdown(key: ValueKey('cat-${item.category}'), value: item.category ?? '', onChanged: (v) => up({'category': v.isEmpty ? null : v})),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: !item.owned, onChanged: (v) => up({'owned': !v}), title: Text(s.t('detail.wishlist'))),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: item.recommend, onChanged: (v) => up({'recommend': v}), title: Text('👍 ${s.t('detail.recommend')}')),
        if (item.kind == 'book')
          DropdownButtonFormField<String>(
            key: ValueKey('fmt-${item.format}'),
            initialValue: item.format,
            decoration: InputDecoration(labelText: s.t('field.format')),
            items: [for (final f in formats) DropdownMenuItem(value: f, child: Text(s.t('format.$f')))],
            onChanged: (v) => up({'format': v}),
          ),
        if (item.owned && item.format == 'physical') ...[
          h(s.t('detail.place')),
          SuggestField(key: ValueKey('room-${item.id}'), value: item.room ?? '', options: s.store.rooms(s.lang), label: s.t('field.room'), onChanged: (v) => up({'room': v.trim().isEmpty ? null : v.trim()})),
          h(s.t('detail.loan')),
          if (loan != null)
            Row(children: [
              Expanded(child: Text(s.t('detail.lentTo', {'name': loan.to, 'date': fmtDate(loan.since)}))),
              OutlinedButton(
                onPressed: () => up({'loans': [for (final l in item.loans) l == loan ? Loan(to: l.to, since: l.since, returned: today()) : l]}),
                child: Text('↩ ${s.t('detail.returned')}'),
              ),
            ])
          else if (lending)
            Row(children: [
              Expanded(child: SuggestField(value: '', options: knownPeople(s.store.items), label: s.t('detail.lendWho'), onChanged: (v) => lendTo.text = v)),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  final to = lendTo.text.trim();
                  if (to.isEmpty) return;
                  up({'loans': [...item.loans, Loan(to: to, since: today())]});
                  setState(() => lending = false);
                },
                child: Text(s.t('ok')),
              ),
            ])
          else
            Align(alignment: Alignment.centerLeft, child: OutlinedButton(onPressed: () => setState(() => lending = true), child: Text('↗ ${s.t('detail.lend')}'))),
          for (final l in item.loans.where((l) => l.returned != null))
            Text(s.t('detail.loanPast', {'name': l.to, 'from': fmtDate(l.since), 'to': fmtDate(l.returned!)}), style: Theme.of(context).textTheme.bodySmall),
        ],
        h(s.t('field.notes')),
        TextField(controller: notes, maxLines: null, minLines: 2, onChanged: (v) => up({'notes': v}), decoration: InputDecoration(hintText: s.t('detail.notesPh'), border: const OutlineInputBorder())),
        const SizedBox(height: 14),
        Wrap(spacing: 24, runSpacing: 10, children: [
          for (final (k, v) in facts)
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(k, style: Theme.of(context).textTheme.labelSmall),
              Text(v!),
            ]),
        ]),
        if (item.description != null) ...[
          const SizedBox(height: 10),
          Text(item.description!, maxLines: moreInfo ? null : 4, overflow: moreInfo ? null : TextOverflow.ellipsis),
          Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: () => setState(() => moreInfo = !moreInfo), child: Text(moreInfo ? s.t('less') : s.t('more')))),
        ],
        if (!item.needsCheck && (!item.hasCover || item.publisher == null))
          Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: () => enrichItem(context, item), child: Text('🔎 ${s.t('detail.enrich')}'))),
        const SizedBox(height: 40),
      ]),
    );
  }
}

extension on String {
  String? get ifEmpty => isEmpty ? null : this;
}
