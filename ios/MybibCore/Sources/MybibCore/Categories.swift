import Foundation

/// A default category: id, German, English.
public struct DefaultCategory: Sendable {
    public let id: String
    public let de: String
    public let en: String
}

/// Default categories, grouped for the picker.
public struct CategoryGroup: Sendable {
    public let de: String
    public let en: String
    public let items: [DefaultCategory]
}

private func c(_ id: String, _ de: String, _ en: String) -> DefaultCategory { DefaultCategory(id: id, de: de, en: en) }

public let defaultCategoryGroups: [CategoryGroup] = [
    CategoryGroup(de: "Kinder & Jugend", en: "Children & young adults", items: [
        c("picture", "Bilderbuch", "Picture book"),
        c("children", "Kinderbuch", "Children's book"),
        c("youth", "Jugendbuch", "Young adult"),
        c("comic", "Comic & Graphic Novel", "Comics & graphic novels"),
    ]),
    CategoryGroup(de: "Belletristik", en: "Fiction", items: [
        c("novel", "Roman & Erzählung", "Novels & stories"),
        c("crime", "Krimi & Thriller", "Crime & thriller"),
        c("fantasy", "Fantasy & Science-Fiction", "Fantasy & science fiction"),
        c("classic", "Klassiker, Drama & Lyrik", "Classics, drama & poetry"),
        c("humor", "Humor", "Humour"),
    ]),
    CategoryGroup(de: "Sachbuch", en: "Non-fiction", items: [
        c("nonfiction", "Sachbuch", "Non-fiction"),
        c("guide", "Ratgeber", "Self-help & advice"),
        c("cooking", "Kochen & Trinken", "Food & drink"),
        c("travel", "Reise & Sprachführer", "Travel & phrasebooks"),
        c("hobby", "Sport, Outdoor & Hobby", "Sport, outdoors & hobbies"),
        c("arts", "Kunst, Musik & Design", "Art, music & design"),
        c("religion", "Religion & Philosophie", "Religion & philosophy"),
        c("reference", "Wörterbuch & Lernen", "Dictionaries & learning"),
    ]),
]

private let allDefaults: [DefaultCategory] = defaultCategoryGroups.flatMap(\.items)
private let byId: [String: DefaultCategory] = Dictionary(uniqueKeysWithValues: allDefaults.map { ($0.id, $0) })

public let defaultCategoryIds: [String] = allDefaults.map(\.id)

/// Display name: default categories are translated, own categories are shown as typed.
public func categoryLabel(_ c: String, _ lang: String) -> String {
    guard let d = byId[c] else { return c }
    return lang == "de" ? d.de : d.en
}

/// Accept an id, a German/English default name (any case) or an own category name.
public func toCategory(_ v: String?) -> String? {
    guard let s = v?.trimmed, !s.isEmpty else { return nil }
    if byId[s] != nil { return s }
    let low = s.lowercased()
    for d in allDefaults where d.de.lowercased() == low || d.en.lowercased() == low {
        return d.id
    }
    return s
}

/// Categories offered: the configured list (or the defaults) plus any used by items.
public func allCategories(_ configured: [String], _ used: [String?]) -> [String] {
    var list = configured.isEmpty ? defaultCategoryIds : configured
    for c in used {
        if let c, !list.contains(c) { list.append(c) }
    }
    return list
}
