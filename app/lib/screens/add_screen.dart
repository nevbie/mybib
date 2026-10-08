import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../logic/items.dart';
import '../logic/lookup.dart';
import '../widgets/common.dart';
import 'bulk_screen.dart';
import 'item_form.dart';
import 'photo_screen.dart';
import 'scan_screen.dart';
import 'search_screen.dart';

/// Pick a JSON file (backup, Claude import or update file) and merge it into the catalogue.
Future<void> importFile(BuildContext context) async {
  final s = AppScope.read(context);
  final f = await FilePicker.pickFile(type: FileType.any);
  if (f == null) return;
  try {
    final (:items, :updateOnly) = parseImportFile(utf8.decode(await f.readAsBytes()));
    final r = s.store.importItems(items, updateOnly: updateOnly);
    if (context.mounted) await infoDialog(context, s.t('data.imported', {'added': r.added, 'updated': r.updated, 'skipped': r.skipped}));
  } catch (e) {
    if (context.mounted) await infoDialog(context, s.t('data.importError', {'e': e.toString()}));
  }
}

class AddScreen extends StatelessWidget {
  const AddScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    void push(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    final ways = <(IconData, String, String, VoidCallback)>[
      (Icons.qr_code_scanner, s.t('add.scan'), s.t('add.scanText'), () => push(const ScanScreen())),
      (Icons.photo_camera_back, s.t('add.shelf'), s.store.settings.claudeKey.isNotEmpty ? s.t('add.shelfText') : s.t('add.shelfTextNoKey'), () => push(const PhotoScreen(mode: 'shelf'))),
      (Icons.image, s.t('add.cover'), s.t('add.coverText'), () => push(const PhotoScreen(mode: 'cover'))),
      (Icons.search, s.t('add.search'), s.t('add.searchText'), () async {
        final c = await pickCandidate(context);
        if (c != null && context.mounted) openForm(context, draft: candidateDraft(c));
      }),
      (Icons.edit_note, s.t('add.manual'), s.t('add.manualText'), () => openForm(context)),
      (Icons.auto_awesome, s.t('bulk.title'), s.t('bulk.short'), () => push(const BulkScreen())),
      (Icons.file_download, s.t('add.import'), s.t('add.importText'), () => importFile(context)),
    ];
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(s.t('nav.add'), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      for (final (icon, title, text, onTap) in ways)
        Card(
          child: ListTile(
            leading: Icon(icon, size: 30, color: Theme.of(context).colorScheme.primary),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(text),
            onTap: onTap,
          ),
        ),
      const SizedBox(height: 8),
      Text(s.t('add.tip'), style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}
