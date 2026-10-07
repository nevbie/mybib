---
name: regal-erfassen
description: Liest Fotos von Bücherregalen, Spielen, DVDs und CDs aus und erzeugt eine Import-Datei für die App „mybib“. Verwenden, wenn Regal- oder Cover-Fotos katalogisiert, „Bücher abtippen“, „Regal erfassen“ oder „für mybib vorbereiten“ gesagt wird.
---

# Regalfotos für mybib erfassen

Ziel: eine JSON-Datei, die in mybib unter **Hinzufügen → Datei importieren** geladen wird.
Das ist die kostenlose Alternative zur Regalfoto-Erkennung in der App (die einen eigenen API-Schlüssel braucht).

## Vorgehen

1. Fotos aufrecht drehen (EXIF beachten) und bei vielen schmalen Buchrücken in Ausschnitte zoomen –
   nicht aus der verkleinerten Vorschau raten.
2. Jedes sichtbare Objekt von links nach rechts, oben nach unten erfassen. Überspringen: Ordner,
   lose Hefte/Arbeitshefte ohne Titel, Zeitungsstapel, Spielzeug.
3. Titel **wie gedruckt** übernehmen (Originalschrift: chinesische Zeichen bleiben Zeichen, Umlaute bleiben).
   Reihe und Band getrennt (`Asterix` / `36`, `bpb Schriftenreihe` / `11128`, mehrbändige chinesische Ausgaben je Band ein Eintrag).
4. Unsicheres mit `"needsCheck": true` markieren statt es wegzulassen – in der App erscheint es unter „Zu prüfen“.
   Nichts erfinden, was nicht zu sehen oder allgemein bekannt ist.
5. Nach dem Raum fragen, falls nicht genannt (es gibt nur Räume, keine Regale). Unbekannt → `"room": "Foto N"`;
   in der App unter **Orte → ✎** umbenennen (gleicher Name wie ein vorhandener Raum = zusammenlegen)
   oder in der Bibliothek mit **Auswählen → Bearbeiten** verschieben.
6. Datei unter `imports/` speichern (ist per `.gitignore` vom Repo ausgeschlossen – der Katalog ist privat)
   und der Nutzerin schicken. Nicht committen.

## Format

```json
{
  "room": "Wohnzimmer",
  "items": [
    {
      "kind": "book",
      "title": "Kafka am Strand",
      "creators": ["Haruki Murakami"],
      "publisher": "btb",
      "language": "de"
    },
    { "kind": "book", "title": "金瓶梅词话", "creators": ["兰陵笑笑生"], "series": "全本金瓶梅词话", "volume": "3", "language": "zh" },
    { "kind": "game", "title": "Catan", "room": "Kleines Zimmer" },
    { "kind": "cd", "title": "Murmeln meiner Kindheit", "creators": ["Rafik Schami"], "needsCheck": true }
  ]
}
```

- `kind`: `book` | `game` | `dvd` | `cd` (Hörbuch-CDs = `cd`, Comics/Bilderbücher = `book`)
- `room` oben gilt für alle Einträge ohne eigene Angabe.
- Weitere erlaubte Felder: `subtitle`, `year`, `isbn`, `pages`, `tags`, `status` (`none|want|active|done`),
  `rating` (0–5), `owned` (false = Wunschliste), `format` (`physical|ebook|audio`), `notes`, `ageFrom`,
  `playersMin`, `playersMax`, `playMinutes`.
- Beim Import werden Duplikate (gleiche ISBN oder gleicher Titel + Autor:in) übersprungen,
  die Datei kann also gefahrlos mehrfach importiert werden.
- Cover und fehlende Details holt man danach in der App pro Eintrag mit „Online ergänzen“.
