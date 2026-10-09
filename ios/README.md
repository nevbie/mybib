# mybib – iPhone-App (Swift / SwiftUI)

Die native iPhone-Version von mybib: Bücher, Spiele, DVDs und CDs katalogisieren – Deutsch & Englisch.
Gleicher Funktionsumfang und **gleiches Datenformat** wie die Web- und die Android-Version:
dort *Sicherung exportieren*, hier *Datei importieren* – fertig.

- Hinzufügen per Barcode-Scan (ISBN/EAN), Regalfoto (Claude, eigener API-Schlüssel), Cover-Foto,
  Online-Suche, von Hand oder per Import-Datei
- Fehlende Infos (Cover, Verlag, Jahr, ISBN, Klappentext) gesammelt über Google Books ergänzen
- Bewertung, Status, Format, Wunschliste, Empfehlung, Kategorie, Raum, Verleihen, Notizen, Teilen
- Bibliothek mit Suche, Filtern, Sortierung und Mehrfach-Bearbeitung; Orte & Kategorien
- Daten nur auf dem Gerät (`items.json` / `settings.json` im Dokumente-Ordner der App),
  Sicherung als JSON/CSV speichern oder teilen
- App Store: Bundle-ID **app.mybib**, iOS 17+, nur iPhone, Hochformat

## Aufbau

| Pfad | Inhalt |
| --- | --- |
| `MybibCore/` | Swift-Package ohne UI: Datenmodell, `normalizeItem`, Suche/Filter/Sortierung, Import/Export/CSV, ISBN, Kategorien, Online-Suche (Google Books, Open Library, MusicBrainz + Cover Art Archive, UPCitemdb), Claude-Client, Texte, `Store` (Dateien) |
| `MybibCore/Tests/` | XCTest-Tests (Logik, Online-Suche mit Mock-HTTP, Store, Texte) |
| `Mybib/` | SwiftUI-App: vier Tabs (Bibliothek, Hinzufügen, Orte, Optionen), Scanner (AVFoundation), Kamera/Fotos, Dialoge |
| `project.yml` | XcodeGen-Beschreibung des Xcode-Projekts (das `.xcodeproj` wird erzeugt und ist nicht im Repository) |
| `version.txt` | Versionsnummer; die App-Version wird `<version.txt>.<Anzahl Commits>` |
| `../shared/strings.json` | alle Texte (de/en) – die einzige Quelle, auch für die Android-App |

Die Texte werden nicht kopiert: das Xcode-Projekt nimmt `../shared/strings.json` als Ressource ins App-Bundle,
die Tests lesen die Datei direkt aus dem Repository.

## Auf dem Mac bauen

```bash
brew install xcodegen
cd ios
xcodegen generate        # erzeugt mybib.xcodeproj (nach jeder Änderung an project.yml oder neuen Dateien)
open mybib.xcodeproj     # in Xcode: Team unter Signing & Capabilities wählen, dann Run
```

Nur die Tests (ohne Xcode-Projekt): `cd ios/MybibCore && swift test`.

## Builds (GitHub Actions)

- `.github/workflows/ios-ci.yml` – bei jedem Push und Pull Request mit Änderungen in `ios/` oder `shared/`:
  `swift test` und ein Simulator-Build ohne Signatur.
- `.github/workflows/ios-build.yml` – nur von Hand (*Actions → Release build (iOS) → Run workflow*, macOS-Minuten
  zählen zehnfach): signiertes Archiv, IPA als Artefakt und Upload zu TestFlight.
  Ohne Apple-Secrets wird nur ein unsignierter Test-Build gemacht.

Version: `CFBundleShortVersionString` = `<version.txt>.<git rev-list --count HEAD>`, `CFBundleVersion` = Anzahl Commits
(im Workflow über `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`; lokal 1.0 / 1).

### Apple einrichten (einmalig)

1. Im [Developer-Portal](https://developer.apple.com/account/resources/identifiers/list) die App-ID **app.mybib** anlegen.
2. Dafür ein eigenes Provisioning-Profil vom Typ **App Store** (Distribution) erstellen – mit dem vorhandenen
   *Apple Distribution*-Zertifikat von cheesychess (kann wiederverwendet werden).
3. In App Store Connect eine neue App mit der Bundle-ID app.mybib anlegen.
4. GitHub-Secrets eintragen (*Settings → Secrets and variables → Actions*), gleiche Namen wie bei cheesychess:

| Secret | Inhalt |
| --- | --- |
| `IOS_CERT_P12_BASE64` | Distribution-Zertifikat mit privatem Schlüssel (.p12), base64 – wie bei cheesychess |
| `IOS_CERT_PASSWORD` | Passwort der .p12-Datei |
| `IOS_PROFILE_BASE64` | das **neue** Profil für app.mybib (.mobileprovision), base64 |
| `APPSTORE_API_KEY_ID` | App-Store-Connect-API-Schlüssel: Key ID |
| `APPSTORE_API_ISSUER_ID` | Issuer ID |
| `APPSTORE_API_KEY_P8` | Inhalt der .p8-Datei |

```bash
base64 -i mybib_AppStore.mobileprovision | pbcopy   # als IOS_PROFILE_BASE64 einfügen
```

Team-ID und Profilname liest der Workflow aus dem Profil; signiert wird nur das App-Target (manuell, „Apple Distribution“).
