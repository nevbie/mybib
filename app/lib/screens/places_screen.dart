import 'package:flutter/material.dart';

import '../app_state.dart';
import '../logic/items.dart';
import '../models.dart';
import '../widgets/common.dart';

class PlacesScreen extends StatelessWidget {
  const PlacesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final store = s.store;
    final items = store.items;
    final rooms = store.rooms(s.lang);
    final byRoom = {for (final (r, n) in summarizePlaces(items)) r: n};
    final configured = store.settings.rooms.isNotEmpty ? store.settings.rooms : [for (final r in defaultRooms) r[s.lang == 'de' ? 0 : 1]];
    void saveRooms(List<String> list) => store.updateSettings(store.settings.copyWith(rooms: list.where((r) => r.isNotEmpty).toSet().toList()));

    Future<void> addRoom() async {
      final name = (await promptDialog(context, s.t('places.newRoom')))?.trim();
      if (name != null && name.isNotEmpty && !rooms.contains(name)) saveRooms([...configured, name]);
    }

    Future<void> renameRoom(String room) async {
      final name = (await promptDialog(context, s.t('places.renameRoom', {'room': room}), initial: room))?.trim();
      if (name == null || name.isEmpty || name == room || !context.mounted) return;
      if (rooms.contains(name) && !await confirmDialog(context, s.t('places.mergeConfirm', {'room': room, 'name': name}))) return;
      store.moveRoom(room, name);
      saveRooms(configured.contains(room) ? [for (final r in configured) r == room ? name : r] : configured);
    }

    Future<void> removeRoom(String room) async {
      final n = byRoom[room] ?? 0;
      if (n > 0 && !await confirmDialog(context, s.t('places.removeRoomConfirm', {'room': room, 'n': n}))) return;
      if (n > 0) store.moveRoom(room, '');
      saveRooms(configured.where((r) => r != room).toList());
    }

    final owned = items.where((i) => i.owned).toList();
    final stats = <(String, int)>[
      for (final k in kinds) (s.t('kind.$k.pl'), owned.where((i) => i.kind == k).length),
      (s.t('places.digital'), owned.where((i) => i.format != 'physical').length),
      (s.t('places.done'), items.where((i) => i.status == 'done').length),
      (s.t('places.want'), items.where((i) => i.status == 'want').length),
      (s.t('scope.lent'), items.where((i) => i.openLoan != null).length),
      (s.t('scope.wish'), items.length - owned.length),
    ].where((x) => x.$2 > 0).toList();

    final catCount = <String, int>{};
    for (final i in items) {
      catCount[i.category ?? ''] = (catCount[i.category ?? ''] ?? 0) + 1;
    }
    final cats = [...store.categories(), ''].where((c) => (catCount[c] ?? 0) > 0).toList();

    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(s.t('nav.places'), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (label, n) in stats)
          Container(
            width: 104,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$n', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
      ]),
      if (!(cats.length == 1 && cats.first.isEmpty) && cats.isNotEmpty) ...[
        const SizedBox(height: 18),
        Text(s.t('field.category'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final c in cats)
            ActionChip(
              label: Text('${c.isEmpty ? s.t('cat.none') : s.catLabel(c)}  ${catCount[c]}'),
              onPressed: () => s.showInLibrary(Filters(category: c)),
            ),
        ]),
      ],
      const SizedBox(height: 18),
      Text(s.t('nav.places'), style: Theme.of(context).textTheme.titleMedium),
      for (final room in rooms)
        Card(
          child: ListTile(
            leading: const Text('🏠', style: TextStyle(fontSize: 20)),
            title: Text(room),
            subtitle: Text('${byRoom[room] ?? 0}'),
            onTap: () => s.showInLibrary(Filters(room: room, scope: 'owned', format: 'physical'), sortBy: 'place'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(onPressed: () => renameRoom(room), icon: const Icon(Icons.edit_outlined), tooltip: s.t('places.rename')),
              IconButton(onPressed: () => removeRoom(room), icon: const Icon(Icons.close), tooltip: s.t('places.remove')),
            ]),
          ),
        ),
      if ((byRoom[''] ?? 0) > 0)
        Card(
          child: ListTile(
            leading: const Text('❔', style: TextStyle(fontSize: 20)),
            title: Text(s.t('places.none')),
            subtitle: Text('${byRoom['']}'),
            onTap: () => s.showInLibrary(const Filters(room: '', scope: 'owned', format: 'physical')),
          ),
        ),
      const SizedBox(height: 8),
      Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(onPressed: addRoom, icon: const Icon(Icons.add), label: Text(s.t('places.addRoom')))),
      const SizedBox(height: 8),
      Text(s.t('places.tip'), style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}
