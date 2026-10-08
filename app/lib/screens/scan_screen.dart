import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../app_state.dart';
import '../logic/isbn.dart';
import '../logic/items.dart';
import '../logic/lookup.dart';
import '../models.dart';
import '../widgets/common.dart';
import 'item_form.dart';
import 'item_screen.dart';

/// Barcode scanning: add to shelf, add to wishlist, or just check "do I own this?".
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final controller = MobileScannerController(formats: const [BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcA, BarcodeFormat.upcE]);
  final manual = TextEditingController();
  String mode = 'own';
  String phase = 'scan'; // scan / busy / found / none
  String code = '';
  List<Candidate> found = [];
  Item? dup;
  final added = <Item>[];
  String? room;
  String last = '';

  @override
  void dispose() {
    controller.dispose();
    manual.dispose();
    super.dispose();
  }

  Future<void> _handle(String raw) async {
    final s = AppScope.read(context);
    final c = classifyCode(raw);
    if (c == null) {
      toast(context, s.t('scan.invalid'));
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      phase = 'busy';
      code = c.code;
    });
    final items = s.store.items;
    final d0 = items.where((i) => i.isbn == c.code).firstOrNull;
    final list = c.type == 'isbn'
        ? [?await lookupIsbn(c.code, googleKey: s.store.settings.googleBooksKey)]
        : await lookupEan(c.code);
    if (!mounted) return;
    final d1 = d0 ?? (list.isNotEmpty ? findDuplicate(items, title: list.first.title, creators: list.first.creators) : null);
    setState(() {
      found = list;
      dup = d1;
      phase = list.isNotEmpty ? 'found' : 'none';
    });
  }

  void _add(Candidate c) {
    final s = AppScope.read(context);
    final r = room ?? s.store.settings.lastRoom;
    final item = s.store.addItems([
      {...c.data, 'owned': mode != 'wish', 'room': mode == 'wish' || r.isEmpty ? null : r, 'source': 'isbn'},
    ]).first;
    s.store.updateSettings(s.store.settings.copyWith(lastRoom: r));
    setState(() {
      added.insert(0, item);
      phase = 'scan';
    });
  }

  void _edit(Map<String, dynamic> data) {
    final s = AppScope.read(context);
    final r = room ?? s.store.settings.lastRoom;
    openForm(context, draft: {...data, 'owned': mode != 'wish', 'room': r.isEmpty ? null : r, 'source': 'isbn'});
    setState(() => phase = 'scan');
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final showResult = phase == 'found' || phase == 'none';
    return Scaffold(
      appBar: AppBar(title: Text(s.t('scan.title'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SegmentedButton<String>(
          segments: [for (final m in ['own', 'wish', 'check']) ButtonSegment(value: m, label: Text(s.t('scan.mode.$m')))],
          selected: {mode},
          showSelectedIcon: false,
          onSelectionChanged: (v) => setState(() => mode = v.first),
        ),
        if (mode == 'own') SuggestField(value: room ?? s.store.settings.lastRoom, options: s.store.rooms(s.lang), label: s.t('field.room'), onChanged: (v) => room = v.trim()),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: Stack(fit: StackFit.expand, children: [
              MobileScanner(
                controller: controller,
                errorBuilder: (context, error) => Container(color: Colors.black, alignment: Alignment.center, padding: const EdgeInsets.all(16), child: Text(s.t('scan.unsupported'), style: const TextStyle(color: Colors.white), textAlign: TextAlign.center)),
                onDetect: (capture) {
                  if (phase != 'scan') return;
                  final v = capture.barcodes.firstOrNull?.rawValue;
                  if (v == null || classifyCode(v) == null) return;
                  // need the same reading twice in a row to avoid misreads
                  if (v == last) {
                    last = '';
                    _handle(v);
                  } else {
                    last = v;
                  }
                },
              ),
              Center(child: Container(height: 2, margin: const EdgeInsets.symmetric(horizontal: 40), color: Colors.redAccent)),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(controller: manual, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: s.t('scan.manual')), onSubmitted: (v) => _handle(v))),
          const SizedBox(width: 8),
          FilledButton(onPressed: () => _handle(manual.text), child: Text(s.t('ok'))),
        ]),
        if (phase == 'busy') Padding(padding: const EdgeInsets.all(12), child: Text(s.t('scan.looking', {'code': code}))),
        if (showResult && dup != null)
          Card(
            color: Colors.amber.shade100,
            child: ListTile(
              title: Text('${mode == 'check' ? '✅ ' : '⚠︎ '}${s.t('scan.have', {'title': dup!.title, 'place': dup!.room ?? '–'})}', style: const TextStyle(color: Colors.black87)),
              trailing: TextButton(onPressed: () => openItem(context, dup!.id), child: Text(s.t('scan.open'))),
            ),
          ),
        if (showResult && mode == 'check' && dup == null) Card(child: ListTile(title: Text('❌ ${s.t('scan.notHave')}'))),
        if (phase == 'found')
          for (final c in found)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  CoverImage(title: c.title, kind: c.kind, coverUrl: c.coverUrl, large: true),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(c.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (c.data['subtitle'] != null) Text('${c.data['subtitle']}'),
                      Text(c.creators.join(', ')),
                      Text([c.data['publisher'], c.data['year'], c.via].where((x) => x != null).join(' · '), style: Theme.of(context).textTheme.bodySmall),
                      if (mode != 'check')
                        Wrap(spacing: 8, children: [
                          FilledButton(onPressed: () => _add(c), child: Text('＋ ${mode == 'wish' ? s.t('scan.addWish') : s.t('scan.add')}')),
                          OutlinedButton(onPressed: () => _edit(c.data), child: Text(s.t('scan.edit'))),
                        ]),
                    ]),
                  ),
                ]),
              ),
            ),
        if (phase == 'none')
          Card(
            child: ListTile(
              title: Text(s.t('scan.notFound', {'code': code})),
              subtitle: mode == 'check' ? null : Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: () => _edit({'title': '', 'isbn': code, 'kind': code.startsWith('97') ? 'book' : 'dvd'}), child: Text(s.t('scan.manualAdd')))),
            ),
          ),
        if (showResult) TextButton(onPressed: () => setState(() => phase = 'scan'), child: Text(s.t('scan.next'))),
        if (added.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(s.t('scan.added', {'n': added.length}), style: const TextStyle(fontWeight: FontWeight.bold)),
          for (final i in added) Text('• ${i.title}'),
        ],
      ]),
    );
  }
}
