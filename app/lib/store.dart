import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'logic/categories.dart';
import 'logic/items.dart';
import 'models.dart';

/// All data lives on this device: one JSON file for the catalogue, one for settings.
/// Writes are debounced so typing a note doesn't rewrite the file on every key.
class Store extends ChangeNotifier {
  Store({this.dir});

  /// Directory for the data files; the app documents directory when null (tests pass a temp dir).
  Directory? dir;
  List<Item> _items = [];
  Settings _settings = const Settings();
  bool ready = false;
  Timer? _saveTimer;

  List<Item> get items => _items;
  Settings get settings => _settings;
  Item? byId(String id) {
    for (final i in _items) {
      if (i.id == id) return i;
    }
    return null;
  }

  Future<File> _file(String name) async {
    dir ??= await getApplicationDocumentsDirectory();
    return File('${dir!.path}/$name');
  }

  Future<void> load() async {
    try {
      final f = await _file('items.json');
      if (await f.exists()) {
        final data = jsonDecode(await f.readAsString());
        _items = [for (final m in (data['items'] as List)) normalizeItem(Map<String, dynamic>.from(m as Map))];
      }
      final s = await _file('settings.json');
      if (await s.exists()) _settings = Settings.fromJson(Map<String, dynamic>.from(jsonDecode(await s.readAsString()) as Map));
    } catch (e) {
      debugPrint('loading failed: $e');
    }
    ready = true;
    notifyListeners();
  }

  void _changed() {
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), save);
  }

  /// Write the catalogue now (atomically: temp file, then rename).
  Future<void> save() async {
    _saveTimer?.cancel();
    final f = await _file('items.json');
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode({'version': 1, 'items': _items.map((i) => i.toJson()).toList()}), flush: true);
    await tmp.rename(f.path);
  }

  List<Item> addItems(List<Map<String, dynamic>> drafts) {
    final now = DateTime.now().toUtc().toIso8601String();
    final created = [for (final d in drafts) normalizeItem({...d, 'id': null, 'addedAt': now, 'updatedAt': now})];
    _items = [..._items, ...created];
    _changed();
    return created;
  }

  void updateItem(String id, Map<String, dynamic> patch) => updateItems([id], (_) => patch);

  /// Apply a (per-item) change to many items at once – bulk edit, room/category moves.
  void updateItems(List<String> ids, Map<String, dynamic> Function(Item i) patch) {
    final set = ids.toSet();
    final now = DateTime.now().toUtc().toIso8601String();
    _items = [for (final i in _items) set.contains(i.id) ? i.copyWith({...patch(i), 'id': i.id, 'updatedAt': now}) : i];
    _changed();
  }

  void removeItems(List<String> ids) {
    final set = ids.toSet();
    _items = _items.where((i) => !set.contains(i.id)).toList();
    _changed();
  }

  MergeResult importItems(List<Item> incoming, {bool updateOnly = false}) {
    final r = mergeItems(_items, incoming, updateOnly: updateOnly);
    _items = r.items;
    _changed();
    return r;
  }

  void replaceAll(List<Item> list) {
    _items = [...list];
    _changed();
  }

  void moveRoom(String from, String to) =>
      updateItems(_items.where((i) => (i.room ?? '') == from).map((i) => i.id).toList(), (_) => {'room': to.isEmpty ? null : to});

  void moveCategory(String from, String to) =>
      updateItems(_items.where((i) => i.category == from).map((i) => i.id).toList(), (_) => {'category': to.isEmpty ? null : to});

  Future<void> updateSettings(Settings s) async {
    _settings = s;
    notifyListeners();
    final f = await _file('settings.json');
    await f.writeAsString(jsonEncode(s.toJson()));
  }

  List<String> rooms(String lang) => allRooms(_items, _settings.rooms, [for (final r in defaultRooms) r[lang == 'de' ? 0 : 1]]);
  List<String> categories() => allCategories(_settings.categories, _items.map((i) => i.category));
}
