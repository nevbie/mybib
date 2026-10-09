# mybib · Meine Bibliothek

A catalogue for books, board games, DVDs and CDs – installable app (PWA) for Android, German & English,
built like [whatsfordinner](https://github.com/nevbie/whatsfordinner).

## Features

- **Add things in six ways**
  - **Barcode scan** (ISBN / EAN) with the phone camera → title, authors, publisher, year and cover from
    Google Books + Open Library (books) or MusicBrainz + Cover Art Archive (CDs). Modes: *to shelf*,
    *wishlist*, *do I own this?* (handy in a bookshop).
  - **Shelf photo** → Claude reads all spines, you review/correct the list, details and covers are
    completed online. Needs your own Anthropic API key (Options), roughly 2–10 cents per photo.
  - **Cover photo** → the photo becomes the cover; with a key the title is recognised and completed online.
  - **Online search** by title / author.
  - **Manual entry** (games, DVDs, old or Chinese editions without barcode).
  - **Import file** – backups, or files made by Claude from shelf photos
    (skill [`regal-erfassen`](.claude/skills/regal-erfassen/SKILL.md)).
- **Per item**: rating (1–5 ★), status (want to read / reading / read – or play / watch / listen),
  print / e-book / audiobook, wishlist, 👍 recommendation, notes, tags, room,
  series & volume, language, age, players & playing time for games.
- **Lending**: lend to someone, mark as returned, loan history; "Lent out" filter.
- **Share** an item (title, author, your stars and note, link) via the Android share sheet.
- **Library**: search (title, author, ISBN, notes, room), filters (kind, wishlist, lent, recommended,
  to check, status, format, room, rating), sorting (title ignoring articles, surname, added, rating, year, room).
- **Categories**: one main category per entry from 17 defaults (picture book, children's, young adult, comics,
  novels, crime, fantasy & SF, classics, humour, non-fiction, advice, food & drink, travel & phrasebooks,
  sport & hobby, art & music, religion & philosophy, dictionaries) – rename, add or merge them under Options;
  filter by category, counts under Places.
- **Own cover photo**: tap the cover on an entry → take a photo or pick one from the gallery.
- **Bulk edit**: *Select* in the library (or *All* of the current filter) → set room, status, rating, kind,
  format, wishlist, recommendation, add/remove a tag, clear "to check", or delete – for many entries at once.
- **Places**: rooms (default Küche, Wohnzimmer, Kleines Zimmer) with counts; rename a room, or merge it
  into another by giving it that room's name; stats.
- **Fill in missing info** for all books at once: cover, publisher, year, ISBN and blurb from Google Books
  (+ Open Library) – by ISBN, otherwise title + author; only clear matches, only empty fields, stops
  cleanly at the Google daily limit and continues with the rest next time.
- **Duplicate warnings** when scanning, recognising or typing.
- **Data stays on the phone** (IndexedDB). Export/import JSON backups, export CSV for spreadsheets.

## Native apps (Android + iPhone)

The same app also exists natively, with the same data format – export a backup in one, import it in another:

| Folder | Platform | Builds |
| --- | --- | --- |
| [`android/`](android/README.md) | Android, Kotlin + Jetpack Compose | test APK on every push / pull request; signed **APK + AAB** release on every merge to `main` (needs the `KEYSTORE_BASE64` / `KEYSTORE_PASSWORD` secrets) |
| [`ios/`](ios/README.md) | iPhone, Swift + SwiftUI | simulator build + tests on every push / pull request; **TestFlight** upload by hand (*Actions → iOS release build*, needs the Apple secrets) |

Both apps read their German and English texts from [`shared/strings.json`](shared/strings.json).

## Development

```bash
npm install
npm run dev      # http://localhost:5173
npm test         # logic + translation checks
npm run build
```

## Deploy (GitHub Pages)

1. Repository → **Settings → Pages → Source: GitHub Actions**.
   GitHub Pages for *private* repositories needs a paid plan; otherwise make the repository public
   (the catalogue itself is never in the code – it lives on the phone).
2. Push to `main` – the workflow tests, builds and publishes to `https://<user>.github.io/mybib/`.
3. On the phone: open the page in **Chrome** → *Add to Home screen* / *Install app*.
   Barcode scanning uses Chrome's built-in barcode detector (Android); elsewhere type the number.

## Notes on the online services

| Service | Used for | Key |
| --- | --- | --- |
| Google Books | book details & covers | optional – keyless requests share a global daily quota and sometimes fail; a free key (Google Cloud Console → Books API) helps |
| Open Library | book details & covers | none |
| MusicBrainz / Cover Art Archive | CDs, music DVDs | none (max. 1 request/s) |
| UPCitemdb (trial) | other barcodes (DVDs, games) | none, 100 lookups/day |
| Anthropic Claude | reading shelf/cover photos | your own API key, stored only on the device |

Board games and films have no good free barcode database, so they are added by photo or by hand.
