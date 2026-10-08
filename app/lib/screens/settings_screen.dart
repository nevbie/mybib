import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import '../logic/categories.dart';
import '../logic/items.dart';
import '../widgets/common.dart';
import 'add_screen.dart';

const _version = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');
const _models = [('claude-opus-5-5', 'Claude Opus 5.5'), ('claude-sonnet-5-5', 'Claude Sonnet 5.5')];

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool showKey = false;
  TextEditingController? claudeKey, googleKey;

  @override
  void dispose() {
    claudeKey?.dispose();
    googleKey?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final store = s.store;
    final st = store.settings;
    claudeKey ??= TextEditingController(text: st.claudeKey);
    googleKey ??= TextEditingController(text: st.googleBooksKey);
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final cats = store.categories();
    final catCount = <String, int>{};
    for (final i in store.items) {
      if (i.category != null) catCount[i.category!] = (catCount[i.category!] ?? 0) + 1;
    }
    void saveCats(List<String> list) => store.updateSettings(st.copyWith(categories: list.where((c) => c.isNotEmpty).toSet().toList()));

    Future<void> addCategory() async {
      final name = (await promptDialog(context, s.t('cat.new')))?.trim();
      if (name != null && name.isNotEmpty) saveCats([...cats, toCategory(name)!]);
    }

    Future<void> renameCategory(String c) async {
      final label = s.catLabel(c);
      final name = (await promptDialog(context, s.t('cat.rename', {'name': label}), initial: label))?.trim();
      if (name == null || name.isEmpty || name == label || !context.mounted) return;
      final to = toCategory(name)!;
      if (cats.contains(to) && !await confirmDialog(context, s.t('cat.mergeConfirm', {'from': label, 'to': s.catLabel(to)}))) return;
      store.moveCategory(c, to);
      saveCats([for (final x in cats) x == c ? to : x]);
    }

    Future<void> removeCategory(String c) async {
      if (!await confirmDialog(context, s.t('cat.removeConfirm', {'name': s.catLabel(c), 'n': catCount[c] ?? 0}))) return;
      store.moveCategory(c, '');
      saveCats(cats.where((x) => x != c).toList());
    }

    Future<void> saveFile(String name, String text, String mime) async {
      final bytes = Uint8List.fromList(utf8.encode(text));
      final uri = await FilePicker.saveFile(fileName: name, bytes: bytes, mimeType: mime);
      if (uri != null && context.mounted) toast(context, s.t('data.saved'));
    }

    Future<void> shareFile(String name, String text, String mime) async {
      await SharePlus.instance.share(ShareParams(files: [XFile.fromData(Uint8List.fromList(utf8.encode(text)), mimeType: mime, name: name)], fileNameOverrides: [name]));
    }

    Future<void> wipe() async {
      if (!await confirmDialog(context, s.t('data.wipeConfirm', {'n': store.items.length})) || !context.mounted) return;
      final typed = await promptDialog(context, s.t('data.wipeType'));
      if (typed?.trim() == 'OK') store.replaceAll([]);
    }

    Widget h(String t) => Padding(padding: const EdgeInsets.only(top: 22, bottom: 6), child: Text(t, style: Theme.of(context).textTheme.titleMedium));
    Widget small(String t) => Text(t, style: Theme.of(context).textTheme.bodySmall);
    String exportJson() => const JsonEncoder().convert(toExport(store.items));

    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(s.t('nav.settings'), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
      h(s.t('settings.lang')),
      SegmentedButton<String>(
        segments: const [ButtonSegment(value: 'de', label: Text('Deutsch')), ButtonSegment(value: 'en', label: Text('English'))],
        selected: {s.lang},
        showSelectedIcon: false,
        onSelectionChanged: (v) => store.updateSettings(st.copyWith(lang: v.first)),
      ),
      h(s.t('settings.ai')),
      small(s.t('settings.aiText')),
      TextField(
        controller: claudeKey,
        obscureText: !showKey,
        autocorrect: false,
        decoration: InputDecoration(
          labelText: s.t('settings.claudeKey'),
          hintText: 'sk-ant-…',
          suffixIcon: IconButton(icon: Icon(showKey ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => showKey = !showKey)),
        ),
        onChanged: (v) => store.updateSettings(store.settings.copyWith(claudeKey: v.trim())),
      ),
      DropdownButtonFormField<String>(
        initialValue: _models.any((m) => m.$1 == st.claudeModel) ? st.claudeModel : _models.first.$1,
        isExpanded: true,
        decoration: InputDecoration(labelText: s.t('settings.model')),
        items: [for (final (id, name) in _models) DropdownMenuItem(value: id, child: Text('$name – ${s.t('settings.model.$id')}', overflow: TextOverflow.ellipsis))],
        onChanged: (v) => store.updateSettings(st.copyWith(claudeModel: v)),
      ),
      const SizedBox(height: 6),
      small(s.t('settings.aiPrivacy')),
      h(s.t('settings.lookup')),
      small(s.t('settings.lookupText')),
      TextField(
        controller: googleKey,
        autocorrect: false,
        decoration: InputDecoration(labelText: s.t('settings.googleKey'), hintText: s.t('optional')),
        onChanged: (v) => store.updateSettings(store.settings.copyWith(googleBooksKey: v.trim())),
      ),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(s.t('settings.googleHow'), style: const TextStyle(fontSize: 14)),
        children: [for (var n = 1; n <= 4; n++) ListTile(dense: true, leading: Text('$n.'), title: Text(s.t('settings.googleHow$n')))],
      ),
      h(s.t('settings.categories')),
      small(s.t('settings.categoriesText')),
      Card(
        child: Column(children: [
          for (final c in cats)
            ListTile(
              dense: true,
              title: Text('${s.catLabel(c)}  (${catCount[c] ?? 0})'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(onPressed: () => renameCategory(c), icon: const Icon(Icons.edit_outlined, size: 20), tooltip: s.t('places.rename')),
                IconButton(onPressed: () => removeCategory(c), icon: const Icon(Icons.close, size: 20), tooltip: s.t('places.remove')),
              ]),
            ),
        ]),
      ),
      Wrap(spacing: 8, children: [
        OutlinedButton.icon(onPressed: addCategory, icon: const Icon(Icons.add), label: Text(s.t('cat.add'))),
        if (st.categories.isNotEmpty)
          TextButton(
            onPressed: () async {
              if (await confirmDialog(context, s.t('cat.resetConfirm'))) store.updateSettings(store.settings.copyWith(categories: const []));
            },
            child: Text(s.t('cat.reset')),
          ),
      ]),
      h(s.t('settings.data')),
      small(s.t('settings.dataText', {'n': store.items.length})),
      const SizedBox(height: 8),
      OutlinedButton.icon(onPressed: () => saveFile('mybib-$stamp.json', exportJson(), 'application/json'), icon: const Icon(Icons.save_alt), label: Text(s.t('data.exportJson'))),
      OutlinedButton.icon(onPressed: () => shareFile('mybib-$stamp.json', exportJson(), 'application/json'), icon: const Icon(Icons.share), label: Text(s.t('data.exportJsonShare'))),
      OutlinedButton.icon(onPressed: () => shareFile('mybib-$stamp.csv', toCSV(store.items), 'text/csv'), icon: const Icon(Icons.table_chart_outlined), label: Text(s.t('data.exportCsvShare'))),
      OutlinedButton.icon(onPressed: () => importFile(context), icon: const Icon(Icons.file_download), label: Text(s.t('data.import'))),
      TextButton.icon(
        onPressed: store.items.isEmpty ? null : wipe,
        icon: Icon(Icons.delete_forever, color: Theme.of(context).colorScheme.error),
        label: Text(s.t('data.wipe'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ),
      const SizedBox(height: 24),
      Center(child: small('mybib · ${s.t('settings.about')} · ${s.t('settings.version', {'v': _version})}')),
      const SizedBox(height: 24),
    ]);
  }
}
