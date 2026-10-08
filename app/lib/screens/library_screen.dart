import 'package:flutter/material.dart';

import '../app_state.dart';
import '../logic/items.dart';
import '../models.dart';
import '../widgets/common.dart';
import 'bulk_edit_sheet.dart';
import 'item_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _search = TextEditingController();
  bool _more = false;

  /// bulk edit: null = normal mode, otherwise the selected ids
  Set<String>? _sel;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final f = s.filters;
    if (_search.text != f.q) _search.text = f.q;
    final items = s.store.items;
    final list = sortItems(applyFilters(items, f), s.sort);
    final counts = {
      'wish': items.where((i) => !i.owned).length,
      'lent': items.where((i) => i.openLoan != null).length,
      'recommend': items.where((i) => i.recommend).length,
      'check': items.where((i) => i.needsCheck).length,
    };
    final selected = _sel == null ? <String>[] : list.where((i) => _sel!.contains(i.id)).map((i) => i.id).toList();
    void set(Filters nf) => s.setFilters(nf);

    Widget chip(String label, bool on, VoidCallback tap, {int? n}) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: FilterChip(label: Text(n == null ? label : '$label  $n'), selected: on, onSelected: (_) => tap(), showCheckmark: false),
        );

    final header = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text.rich(TextSpan(children: [
          const TextSpan(text: 'mybib ', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          TextSpan(text: '${items.length}', style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ])),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: TextField(
          controller: _search,
          decoration: InputDecoration(
            hintText: s.t('lib.search'),
            prefixIcon: const Icon(Icons.search),
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: f.q.isEmpty ? null : IconButton(icon: const Icon(Icons.clear), onPressed: () => set(f.copyWith(q: ''))),
          ),
          onChanged: (q) => set(f.copyWith(q: q)),
        ),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          chip(s.t('kind.all'), f.kind == 'all', () => set(f.copyWith(kind: 'all'))),
          for (final k in kinds) chip(s.t('kind.$k.pl'), f.kind == k, () => set(f.copyWith(kind: f.kind == k ? 'all' : k))),
        ]),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          chip(s.t('scope.all'), f.scope == 'all', () => set(f.copyWith(scope: 'all'))),
          for (final sc in ['wish', 'lent', 'recommend', 'check'])
            if (counts[sc]! > 0 || f.scope == sc) chip(s.t('scope.$sc'), f.scope == sc, () => set(f.copyWith(scope: f.scope == sc ? 'all' : sc)), n: counts[sc]),
          chip('⚙︎ ${s.t('lib.more')}', _more || f.extraActive > 0, () => setState(() => _more = !_more), n: f.extraActive > 0 ? f.extraActive : null),
        ]),
      ),
      if (_more) _filterPanel(context, s, f),
      if (s.store.ready && items.isEmpty)
        Padding(
          padding: const EdgeInsets.all(32),
          child: Column(children: [
            Text(s.t('lib.empty'), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: () => s.setTab(1), icon: const Icon(Icons.add), label: Text(s.t('nav.add'))),
          ]),
        )
      else if (_sel != null)
        Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Expanded(child: Text(s.t('sel.count', {'n': selected.length}), style: const TextStyle(fontWeight: FontWeight.w600))),
            TextButton(
              onPressed: () => setState(() => _sel = selected.length == list.length ? <String>{} : list.map((i) => i.id).toSet()),
              child: Text(selected.length == list.length ? s.t('ai.none') : s.t('sel.all', {'n': list.length})),
            ),
            FilledButton.icon(
              onPressed: selected.isEmpty ? null : () => showBulkEditSheet(context, selected),
              icon: const Icon(Icons.edit, size: 18),
              label: Text(s.t('sel.edit')),
            ),
            IconButton(onPressed: () => setState(() => _sel = null), icon: const Icon(Icons.close)),
          ]),
        )
      else
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
          child: Row(children: [
            Expanded(child: Text(list.length != items.length ? s.t('lib.shown', {'n': list.length}) : '', style: Theme.of(context).textTheme.bodySmall)),
            if (list.isNotEmpty) TextButton.icon(onPressed: () => setState(() => _sel = {}), icon: const Icon(Icons.checklist, size: 18), label: Text(s.t('sel.start'))),
          ]),
        ),
      if (items.isNotEmpty && list.isEmpty) Padding(padding: const EdgeInsets.all(32), child: Text(s.t('lib.noMatch'), textAlign: TextAlign.center)),
    ];

    return ListView.builder(
      itemCount: header.length + list.length,
      itemBuilder: (context, n) {
        if (n < header.length) return header[n];
        final item = list[n - header.length];
        return ItemTile(
          key: ValueKey(item.id),
          item: item,
          selected: _sel?.contains(item.id),
          onTap: () {
            if (_sel != null) {
              setState(() => _sel!.contains(item.id) ? _sel!.remove(item.id) : _sel!.add(item.id));
            } else {
              openItem(context, item.id);
            }
          },
          onLongPress: _sel == null ? () => setState(() => _sel = {item.id}) : null,
        );
      },
    );
  }

  Widget _filterPanel(BuildContext context, AppState s, Filters f) {
    void set(Filters nf) => s.setFilters(nf);
    final rooms = s.store.rooms(s.lang);
    Widget dd<T>(String label, T value, List<(T, String)> opts, ValueChanged<T> on) => DropdownButtonFormField<T>(
          key: ValueKey('$label|$value'),
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, isDense: true),
          items: [for (final (v, l) in opts) DropdownMenuItem(value: v, child: Text(l, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => v != null ? on(v) : null,
        );
    final any = s.t('any');
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Row(children: [
            Expanded(child: dd(s.t('lib.status'), f.status, [('all', any), for (final st in statuses) (st, s.t('status.${f.kind == 'all' ? 'book' : f.kind}.$st'))], (v) => set(f.copyWith(status: v)))),
            const SizedBox(width: 10),
            Expanded(child: dd(s.t('field.format'), f.format, [('all', any), for (final fm in formats) (fm, s.t('format.$fm'))], (v) => set(f.copyWith(format: v)))),
          ]),
          const SizedBox(height: 8),
          CategoryDropdown(key: ValueKey('cat-${f.category}'), value: f.category, extra: [('all', any)], onChanged: (v) => set(f.copyWith(category: v))),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: dd(s.t('field.room'), rooms.contains(f.room) || f.room == 'all' || f.room == '' ? f.room : 'all', [('all', any), for (final r in rooms) (r, r), ('', s.t('places.none'))], (v) => set(f.copyWith(room: v)))),
            const SizedBox(width: 10),
            Expanded(child: dd(s.t('lib.minRating'), f.minRating, [(0, any), for (var n = 1; n <= 5; n++) (n, '★' * n)], (v) => set(f.copyWith(minRating: v)))),
          ]),
          const SizedBox(height: 8),
          dd(s.t('lib.sort'), s.sort, [for (final k in sortKeys) (k, s.t('sort.$k'))], s.setSort),
          Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => set(const Filters()), child: Text(s.t('lib.reset')))),
        ]),
      ),
    );
  }
}
