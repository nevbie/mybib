import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app_state.dart';
import '../logic/items.dart';
import '../logic/lookup.dart';
import '../models.dart';
import 'item_screen.dart';

/// Complete covers, publisher, year, ISBN and blurb of all books via Google Books (+ Open Library).
class BulkScreen extends StatefulWidget {
  const BulkScreen({super.key});

  @override
  State<BulkScreen> createState() => _BulkScreenState();
}

class _BulkScreenState extends State<BulkScreen> {
  bool retry = false, stop = false;
  String phase = 'idle'; // idle / running / done / stopped / quota / key
  int done = 0, total = 0;
  String current = '';
  final found = <Item>[];
  final missed = <Item>[];

  @override
  void dispose() {
    stop = true;
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _run(List<Item> targets) async {
    final s = AppScope.read(context);
    stop = false;
    takeGoogleProblem();
    setState(() {
      phase = 'running';
      total = targets.length;
      done = 0;
      found.clear();
      missed.clear();
    });
    // don't let the phone sleep while it works through hundreds of books
    WakelockPlus.enable();
    try {
      for (var n = 0; n < targets.length; n++) {
        if (stop || !mounted) {
          if (mounted) setState(() => phase = 'stopped');
          return;
        }
        final item = targets[n];
        setState(() => current = item.title);
        final best = await findBestMatch(item, googleKey: s.store.settings.googleBooksKey).catchError((_) => null);
        final problem = takeGoogleProblem();
        if (!mounted) return;
        if (problem.isNotEmpty && best == null) {
          // leave this item untried so the next run picks it up again
          setState(() => phase = problem);
          return;
        }
        if (best != null) {
          final patch = enrichPatch(item.toJson(), best);
          // without a known author a title-only match may be a different book – ask to check
          s.store.updateItem(item.id, {...patch, 'lookedUp': today(), if (item.creators.isEmpty) 'needsCheck': true});
          (patch.isNotEmpty ? found : missed).add(item);
        } else {
          s.store.updateItem(item.id, {'lookedUp': today()});
          missed.add(item);
        }
        setState(() => done = n + 1);
        if (problem.isNotEmpty) {
          setState(() => phase = problem);
          return;
        }
        // stay well below Google's per-minute limit
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
      if (mounted) setState(() => phase = 'done');
    } finally {
      WakelockPlus.disable();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final items = s.store.items;
    final targets = bulkTargets(items, retry);
    final triedBefore = bulkTargets(items, true).length - bulkTargets(items, false).length;
    final running = phase == 'running';
    Widget list(List<Item> l, {bool withMissing = false}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final i in l.take(withMissing ? 500 : 30))
            InkWell(
              onTap: () => openItem(context, i.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: i.title, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                  if (withMissing) TextSpan(text: '  (${missingInfo(i).map((f) => s.t('bulk.field.$f')).join(', ')})', style: Theme.of(context).textTheme.bodySmall),
                ])),
              ),
            ),
        ]);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('bulk.title'))),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: running
              ? OutlinedButton(onPressed: () => stop = true, child: Text('■ ${s.t('bulk.stop')}'))
              : FilledButton(onPressed: targets.isEmpty ? null : () => _run(targets), child: Text(s.t('bulk.start', {'n': targets.length}))),
        ),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(s.t('bulk.intro'), style: Theme.of(context).textTheme.bodySmall),
        if (s.store.settings.googleBooksKey.isEmpty)
          Card(
            color: Colors.amber.shade100,
            margin: const EdgeInsets.symmetric(vertical: 10),
            child: ListTile(
              title: Text(s.t('bulk.noKey'), style: const TextStyle(color: Colors.black87, fontSize: 14)),
              trailing: TextButton(onPressed: () {
                Navigator.pop(context);
                s.setTab(3);
              }, child: Text(s.t('nav.settings'))),
            ),
          ),
        if (phase == 'idle') ...[
          Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(targets.isNotEmpty ? s.t('bulk.count', {'n': targets.length}) : s.t('bulk.nothing'))),
          if (triedBefore > 0) CheckboxListTile(contentPadding: EdgeInsets.zero, value: retry, onChanged: (v) => setState(() => retry = v!), title: Text(s.t('bulk.retry', {'n': triedBefore}))),
        ] else ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(value: total == 0 ? 0 : done / total),
          const SizedBox(height: 6),
          Text('$done / $total · ✓ ${found.length} · – ${missed.length}'),
          if (running && current.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(current, style: Theme.of(context).textTheme.bodySmall)),
          if (phase == 'done') Padding(padding: const EdgeInsets.only(top: 8), child: Text(s.t('bulk.done', {'found': found.length, 'missed': missed.length}))),
          if (phase == 'stopped') Padding(padding: const EdgeInsets.only(top: 8), child: Text(s.t('bulk.stopped'))),
          if (phase == 'quota' || phase == 'key')
            Card(color: Colors.amber.shade100, child: Padding(padding: const EdgeInsets.all(12), child: Text(s.t(phase == 'quota' ? 'bulk.quota' : 'bulk.badKey'), style: const TextStyle(color: Colors.black87)))),
        ],
        if (found.isNotEmpty) ...[
          Padding(padding: const EdgeInsets.only(top: 16, bottom: 4), child: Text(s.t('bulk.found', {'n': found.length}), style: const TextStyle(fontWeight: FontWeight.bold))),
          list(found.reversed.toList()),
        ],
        if (missed.isNotEmpty && !running) ...[
          Padding(padding: const EdgeInsets.only(top: 16, bottom: 4), child: Text(s.t('bulk.missed', {'n': missed.length}), style: const TextStyle(fontWeight: FontWeight.bold))),
          Text(s.t('bulk.missedHint'), style: Theme.of(context).textTheme.bodySmall),
          list(missed, withMissing: true),
        ],
      ]),
    );
  }
}
