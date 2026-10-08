/// Default categories, grouped for the picker: id, German, English.
class CategoryGroup {
  final String de;
  final String en;
  final List<List<String>> items;
  const CategoryGroup(this.de, this.en, this.items);
}

const defaultCategoryGroups = [
  CategoryGroup('Kinder & Jugend', 'Children & young adults', [
    ['picture', 'Bilderbuch', 'Picture book'],
    ['children', 'Kinderbuch', "Children's book"],
    ['youth', 'Jugendbuch', 'Young adult'],
    ['comic', 'Comic & Graphic Novel', 'Comics & graphic novels'],
  ]),
  CategoryGroup('Belletristik', 'Fiction', [
    ['novel', 'Roman & Erzählung', 'Novels & stories'],
    ['crime', 'Krimi & Thriller', 'Crime & thriller'],
    ['fantasy', 'Fantasy & Science-Fiction', 'Fantasy & science fiction'],
    ['classic', 'Klassiker, Drama & Lyrik', 'Classics, drama & poetry'],
    ['humor', 'Humor', 'Humour'],
  ]),
  CategoryGroup('Sachbuch', 'Non-fiction', [
    ['nonfiction', 'Sachbuch', 'Non-fiction'],
    ['guide', 'Ratgeber', 'Self-help & advice'],
    ['cooking', 'Kochen & Trinken', 'Food & drink'],
    ['travel', 'Reise & Sprachführer', 'Travel & phrasebooks'],
    ['hobby', 'Sport, Outdoor & Hobby', 'Sport, outdoors & hobbies'],
    ['arts', 'Kunst, Musik & Design', 'Art, music & design'],
    ['religion', 'Religion & Philosophie', 'Religion & philosophy'],
    ['reference', 'Wörterbuch & Lernen', 'Dictionaries & learning'],
  ]),
];

final Map<String, List<String>> _byId = {
  for (final g in defaultCategoryGroups)
    for (final i in g.items) i[0]: [i[1], i[2]],
};

final List<String> defaultCategoryIds = _byId.keys.toList();

/// Display name: default categories are translated, own categories are shown as typed.
String categoryLabel(String c, String lang) {
  final d = _byId[c];
  return d == null ? c : d[lang == 'de' ? 0 : 1];
}

/// Accept an id, a German/English default name (any case) or an own category name.
String? toCategory(String? v) {
  final s = v?.trim();
  if (s == null || s.isEmpty) return null;
  if (_byId.containsKey(s)) return s;
  final low = s.toLowerCase();
  for (final e in _byId.entries) {
    if (e.value[0].toLowerCase() == low || e.value[1].toLowerCase() == low) return e.key;
  }
  return s;
}

/// Categories offered: the configured list (or the defaults) plus any used by items.
List<String> allCategories(List<String> configured, Iterable<String?> used) {
  final list = configured.isNotEmpty ? [...configured] : [...defaultCategoryIds];
  for (final c in used) {
    if (c != null && !list.contains(c)) list.add(c);
  }
  return list;
}
