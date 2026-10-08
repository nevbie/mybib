import 'dart:convert';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../logic/categories.dart';
import '../models.dart';

const kindIcon = {'book': '📖', 'game': '🎲', 'dvd': '📀', 'cd': '💿'};

final Map<int, Uint8List> _dataCache = {};

/// Decoded bytes of an own cover photo (data URL), cached so lists scroll smoothly.
Uint8List? coverBytes(String? dataUrl) {
  if (dataUrl == null) return null;
  return _dataCache.putIfAbsent(dataUrl.hashCode, () => base64Decode(dataUrl.substring(dataUrl.indexOf(',') + 1)));
}

/// Cover image with a coloured placeholder showing the kind (and title when large).
class CoverImage extends StatelessWidget {
  const CoverImage({super.key, required this.title, required this.kind, this.coverUrl, this.coverData, this.large = false});

  CoverImage.item(Item i, {super.key, this.large = false})
      : title = i.title,
        kind = i.kind,
        coverUrl = i.coverUrl,
        coverData = i.coverData;

  final String title, kind;
  final String? coverUrl, coverData;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final w = large ? 110.0 : 44.0;
    final h = large ? 160.0 : 64.0;
    Widget ph() {
      var hue = 0;
      for (final c in title.codeUnits) {
        hue = (hue * 31 + c) % 360;
      }
      return Container(
        color: HSLColor.fromAHSL(1, hue.toDouble(), 0.45, 0.55).toColor(),
        padding: const EdgeInsets.all(6),
        alignment: Alignment.center,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(kindIcon[kind] ?? '📖', style: TextStyle(fontSize: large ? 20 : 16)),
          if (large) ...[
            const SizedBox(height: 6),
            Text(title, maxLines: 5, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ]),
      );
    }

    final bytes = coverBytes(coverData);
    final Widget img = bytes != null
        ? Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => ph())
        : coverUrl != null
            ? CachedNetworkImage(imageUrl: coverUrl!, fit: BoxFit.cover, placeholder: (_, _) => ph(), errorWidget: (_, _, _) => ph())
            : ph();
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(width: w, height: h, child: img),
    );
  }
}

class Stars extends StatelessWidget {
  const Stars({super.key, required this.value, this.onChanged, this.small = false});
  final int value;
  final ValueChanged<int>? onChanged;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final on = Colors.amber.shade700;
    final off = Theme.of(context).dividerColor;
    if (onChanged == null) {
      if (value == 0) return const SizedBox.shrink();
      return Text.rich(TextSpan(children: [
        TextSpan(text: '★' * value, style: TextStyle(color: on)),
        TextSpan(text: '★' * (5 - value), style: TextStyle(color: off)),
      ]), style: TextStyle(fontSize: small ? 12 : 16));
    }
    final s = AppScope.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var n = 1; n <= 5; n++)
        Semantics(
          label: s.t('rating.n', {'n': n}),
          button: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => onChanged!(value == n ? 0 : n),
            child: Padding(padding: const EdgeInsets.all(2), child: Text('★', style: TextStyle(fontSize: 30, color: n <= value ? on : off))),
          ),
        ),
    ]);
  }
}

class Badge2 extends StatelessWidget {
  const Badge2(this.text, {super.key, this.color, this.outlined = false});
  final String text;
  final Color? color;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: outlined ? null : (color ?? cs.surfaceContainerHighest),
        border: outlined ? Border.all(color: Theme.of(context).dividerColor) : null,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, color: outlined ? cs.onSurfaceVariant : null)),
    );
  }
}

/// One row in the library list.
class ItemTile extends StatelessWidget {
  const ItemTile({super.key, required this.item, required this.onTap, this.selected, this.onLongPress});
  final Item item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// non-null in selection mode
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final i = item;
    final loan = i.openLoan;
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        color: selected == true ? cs.primaryContainer.withValues(alpha: 0.4) : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (selected != null) Padding(padding: const EdgeInsets.only(top: 18, right: 4), child: Icon(selected! ? Icons.check_box : Icons.check_box_outline_blank, color: cs.primary)),
          CoverImage.item(i),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(TextSpan(children: [
                TextSpan(text: i.title),
                if (i.volume != null) TextSpan(text: ' · ${i.volume}', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.normal)),
              ]), style: const TextStyle(fontWeight: FontWeight.w600)),
              if (i.creators.isNotEmpty) Text(i.creators.join(', '), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
              const SizedBox(height: 3),
              Wrap(spacing: 6, runSpacing: 3, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (i.rating > 0) Stars(value: i.rating, small: true),
                if (i.status != 'none') Badge2(s.t('status.${i.kind}.${i.status}'), color: i.status == 'done' ? cs.secondaryContainer : cs.tertiaryContainer),
                if (i.format != 'physical') Badge2(s.t('format.${i.format}')),
                if (!i.owned) Badge2(s.t('scope.wish'), color: Colors.pink.shade100.withValues(alpha: 0.6)),
                if (i.category != null) Badge2(s.catLabel(i.category!), outlined: true),
                if (i.recommend) const Text('👍', style: TextStyle(fontSize: 12)),
                if (loan != null) Badge2('↗ ${loan.to}', color: Colors.deepPurple.shade100.withValues(alpha: 0.6)),
                if (i.needsCheck) Badge2('?', color: Colors.amber.shade200),
                if (i.room != null) Text(i.room!, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Category picker grouped like the default list; own categories come last.
/// [extra] adds entries before the list (e.g. "unchanged" / "all").
class CategoryDropdown extends StatelessWidget {
  const CategoryDropdown({super.key, required this.value, required this.onChanged, this.extra = const [], this.noneValue = '', this.label});
  final String value;
  final ValueChanged<String> onChanged;
  final List<(String, String)> extra;
  final String noneValue;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final cats = s.store.categories();
    final grouped = {for (final g in defaultCategoryGroups) for (final i in g.items) i[0]};
    final items = <DropdownMenuItem<String>>[
      for (final (v, l) in extra) DropdownMenuItem(value: v, child: Text(l)),
      DropdownMenuItem(value: noneValue, child: Text(s.t('cat.none'))),
    ];
    for (final g in defaultCategoryGroups) {
      final ids = g.items.map((i) => i[0]).where(cats.contains).toList();
      if (ids.isEmpty) continue;
      items.add(DropdownMenuItem(enabled: false, value: '\u0000${g.de}', child: Text(s.lang == 'de' ? g.de : g.en, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary))));
      for (final id in ids) {
        items.add(DropdownMenuItem(value: id, child: Padding(padding: const EdgeInsets.only(left: 10), child: Text(s.catLabel(id)))));
      }
    }
    final own = cats.where((c) => !grouped.contains(c)).toList();
    if (own.isNotEmpty) {
      items.add(DropdownMenuItem(enabled: false, value: '\u0000own', child: Text(s.t('cat.own'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary))));
      for (final c in own) {
        items.add(DropdownMenuItem(value: c, child: Padding(padding: const EdgeInsets.only(left: 10), child: Text(c))));
      }
    }
    final known = items.any((m) => m.value == value);
    return DropdownButtonFormField<String>(
      initialValue: known ? value : noneValue,
      isExpanded: true,
      decoration: InputDecoration(labelText: label ?? s.t('field.category')),
      items: items,
      onChanged: (v) => v != null ? onChanged(v) : null,
    );
  }
}

/// Text field with suggestions (rooms, people).
class SuggestField extends StatelessWidget {
  const SuggestField({super.key, required this.value, required this.options, required this.onChanged, required this.label});
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: value),
      optionsBuilder: (v) {
        final q = v.text.toLowerCase();
        return options.where((o) => o.toLowerCase().contains(q) && o != v.text);
      },
      onSelected: onChanged,
      fieldViewBuilder: (context, ctl, focus, onSubmit) => TextField(
        controller: ctl,
        focusNode: focus,
        decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.arrow_drop_down)),
        onChanged: onChanged,
        onSubmitted: (_) => onSubmit(),
      ),
    );
  }
}

Future<bool> confirmDialog(BuildContext context, String text) async {
  final s = AppScope.read(context);
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(content: Text(text), actions: [
      TextButton(onPressed: () => Navigator.pop(c, false), child: Text(s.lang == 'de' ? 'Abbrechen' : 'Cancel')),
      FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(s.t('ok'))),
    ]),
  );
  return r == true;
}

Future<String?> promptDialog(BuildContext context, String text, {String initial = ''}) {
  final s = AppScope.read(context);
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      content: TextField(controller: ctl, autofocus: true, decoration: InputDecoration(labelText: text), onSubmitted: (v) => Navigator.pop(c, v)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(s.lang == 'de' ? 'Abbrechen' : 'Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: Text(s.t('ok'))),
      ],
    ),
  );
}

void toast(BuildContext context, String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

Future<void> infoDialog(BuildContext context, String text) => showDialog(
      context: context,
      builder: (c) => AlertDialog(content: Text(text), actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))]),
    );
