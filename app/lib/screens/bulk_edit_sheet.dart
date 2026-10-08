import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../widgets/common.dart';

const _unchanged = '\u0000unchanged';
const _none = '\u0000none';
const _new = '\u0000new';

/// Change room, category, status, rating, kind, format, wishlist, recommendation or tags of
/// many items at once. Only what is changed here is applied.
Future<void> showBulkEditSheet(BuildContext context, List<String> ids) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => BulkEditSheet(ids: ids),
    );

class BulkEditSheet extends StatefulWidget {
  const BulkEditSheet({super.key, required this.ids});
  final List<String> ids;

  @override
  State<BulkEditSheet> createState() => _BulkEditSheetState();
}

class _BulkEditSheetState extends State<BulkEditSheet> {
  String room = _unchanged, category = _unchanged, status = _unchanged, kind = _unchanged, format = _unchanged, owned = _unchanged, recommend = _unchanged, rating = _unchanged, removeTag = '';
  final newRoom = TextEditingController();
  final addTag = TextEditingController();
  bool checked = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final live = widget.ids.where((id) => s.store.byId(id) != null).toList();
    final n = live.length;
    final items = live.map((id) => s.store.byId(id)!).toList();
    final kindsUsed = items.map((i) => i.kind).toSet();
    final labelKind = kindsUsed.length == 1 ? kindsUsed.first : 'book';
    final allTags = items.expand((i) => i.tags).toSet().toList()..sort();
    final un = (_unchanged, s.t('bulkEdit.unchanged'));
    final changes = [
      room != _unchanged && (room != _new || newRoom.text.trim().isNotEmpty),
      category != _unchanged,
      status != _unchanged,
      kind != _unchanged,
      format != _unchanged,
      owned != _unchanged,
      recommend != _unchanged,
      rating != _unchanged,
      addTag.text.trim().isNotEmpty,
      removeTag.isNotEmpty,
      checked,
    ].where((b) => b).length;

    Widget dd(String label, String value, List<(String, String)> opts, ValueChanged<String> on) => DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [for (final (v, l) in opts) DropdownMenuItem(value: v, child: Text(l, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => on(v!)),
        );

    void apply() {
      final patch = <String, dynamic>{};
      if (room != _unchanged) {
        final r = room == _new ? newRoom.text.trim() : (room == _none ? '' : room);
        if (room != _new || r.isNotEmpty) patch['room'] = r.isEmpty ? null : r;
      }
      if (category != _unchanged) patch['category'] = category == _none ? null : category;
      if (status != _unchanged) patch['status'] = status;
      if (kind != _unchanged) patch['kind'] = kind;
      if (format != _unchanged) patch['format'] = format;
      if (owned != _unchanged) patch['owned'] = owned == 'yes';
      if (recommend != _unchanged) patch['recommend'] = recommend == 'yes';
      if (rating != _unchanged) patch['rating'] = int.parse(rating);
      if (checked) patch['needsCheck'] = false;
      final tag = addTag.text.trim();
      s.store.updateItems(live, (i) => {
            ...patch,
            if (tag.isNotEmpty || removeTag.isNotEmpty) 'tags': {...i.tags.where((x) => x != removeTag), if (tag.isNotEmpty) tag}.toList(),
          });
      Navigator.pop(context);
    }

    Future<void> delete() async {
      if (!await confirmDialog(context, s.t('bulkEdit.deleteConfirm', {'n': n}))) return;
      s.store.removeItems(live);
      if (context.mounted) Navigator.pop(context);
    }

    final rooms = s.store.rooms(s.lang);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: Text(s.t('bulkEdit.title', {'n': n}), style: const TextStyle(fontWeight: FontWeight.bold)), trailing: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close))),
        Flexible(
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
            Text(s.t('bulkEdit.intro'), style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            dd(s.t('field.room'), room, [un, for (final r in rooms) (r, r), (_none, s.t('places.none')), (_new, s.t('bulkEdit.newRoom'))], (v) => room = v),
            if (room == _new) TextField(controller: newRoom, autofocus: true, decoration: InputDecoration(labelText: s.t('places.newRoom')), onChanged: (_) => setState(() {})),
            const SizedBox(height: 8),
            CategoryDropdown(value: category, noneValue: _none, extra: [un], onChanged: (v) => setState(() => category = v)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: dd(s.t('detail.status'), status, [un, for (final st in statuses) (st, st == 'none' ? s.t('bulkEdit.noStatus') : s.t('status.$labelKind.$st'))], (v) => status = v)),
              const SizedBox(width: 10),
              Expanded(child: dd(s.t('rating'), rating, [un, ('0', s.t('bulkEdit.noRating')), for (var r = 1; r <= 5; r++) ('$r', '★' * r)], (v) => rating = v)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: dd(s.t('field.kind'), kind, [un, for (final k in kinds) (k, s.t('kind.$k'))], (v) => kind = v)),
              const SizedBox(width: 10),
              Expanded(child: dd(s.t('field.format'), format, [un, for (final f in formats) (f, s.t('format.$f'))], (v) => format = v)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: dd(s.t('scope.wish'), owned, [un, ('yes', s.t('bulkEdit.owned')), ('no', s.t('scope.wish'))], (v) => owned = v)),
              const SizedBox(width: 10),
              Expanded(child: dd('👍 ${s.t('detail.recommend')}', recommend, [un, ('yes', s.t('bulkEdit.yes')), ('no', s.t('bulkEdit.no'))], (v) => recommend = v)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: addTag, decoration: InputDecoration(labelText: s.t('bulkEdit.addTag'), hintText: s.t('form.tagsHint')), onChanged: (_) => setState(() {}))),
              if (allTags.isNotEmpty) ...[
                const SizedBox(width: 10),
                Expanded(child: dd(s.t('bulkEdit.removeTag'), removeTag, [('', '–'), for (final t in allTags) (t, t)], (v) => removeTag = v)),
              ],
            ]),
            CheckboxListTile(contentPadding: EdgeInsets.zero, value: checked, onChanged: (v) => setState(() => checked = v!), title: Text(s.t('bulkEdit.checked'))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            Expanded(child: FilledButton(onPressed: changes > 0 && n > 0 ? apply : null, child: Text(s.t('bulkEdit.apply', {'n': n})))),
            const SizedBox(width: 8),
            IconButton(onPressed: n > 0 ? delete : null, icon: const Icon(Icons.delete_outline), color: Theme.of(context).colorScheme.error, tooltip: s.t('detail.delete')),
          ]),
        ),
      ]),
    );
  }
}
