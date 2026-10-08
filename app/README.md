# mybib – Android app (Flutter)

Die Android-Version von mybib: Bücher, Spiele, DVDs und CDs katalogisieren – Deutsch & Englisch.
Gleicher Funktionsumfang und **gleiches Datenformat** wie die Web-Version im Hauptordner:
dort *Sicherung exportieren*, hier *Datei importieren* – fertig.

- Hinzufügen per Barcode-Scan (ISBN/EAN), Regalfoto (Claude, eigener API-Schlüssel), Cover-Foto,
  Online-Suche, von Hand oder per Import-Datei
- Fehlende Infos (Cover, Verlag, Jahr, ISBN, Klappentext) gesammelt über Google Books ergänzen
- Bewertung, Status, Format, Wunschliste, Empfehlung, Kategorie, Raum, Verleihen, Notizen, Teilen
- Bibliothek mit Suche, Filtern, Sortierung und Mehrfach-Bearbeitung; Orte & Kategorien
- Daten nur auf dem Gerät (JSON im App-Speicher), Sicherung als JSON/CSV speichern oder teilen
- Play Store: App-ID **app.mybib** (darf sich nie mehr ändern)

## Builds (GitHub Actions)

- `.github/workflows/app-ci.yml` – bei jedem Pull Request: Analyse, Tests und eine Test-APK
  (Debug, ohne Signaturschlüssel) als Artefakt.
- `.github/workflows/app-build.yml` – bei jedem Merge nach `main` (Änderungen in `app/`):
  signierte **APK** (zum direkten Installieren) und **AAB** (für die Play Console) als GitHub-Release.

Der Android-Ordner wird im Build mit `flutter create` erzeugt (`ci/prepare.sh`) und ist nicht im Repository.

### Signaturschlüssel einrichten (einmalig)

Die Release-Builds brauchen zwei GitHub-Secrets (*Settings → Secrets and variables → Actions*):

| Secret | Inhalt |
| --- | --- |
| `KEYSTORE_BASE64` | der Keystore, base64-kodiert |
| `KEYSTORE_PASSWORD` | sein Passwort (Store- und Schlüsselpasswort gleich) |

Entweder den Keystore von cheesychess wiederverwenden (gleiche Datei, gleiches Passwort) oder einen neuen anlegen:

```bash
keytool -genkeypair -v -keystore mybib.keystore -alias androiddebugkey \
  -keyalg RSA -keysize 2048 -validity 10000 -storepass DEIN_PASSWORT -keypass DEIN_PASSWORT \
  -dname "CN=mybib"
base64 -w0 mybib.keystore   # Ausgabe als KEYSTORE_BASE64 eintragen
```

Den Keystore gut aufheben (z. B. im Passwort-Manager): ohne ihn lassen sich keine Updates mehr installieren.
Ein anderer Alias als `androiddebugkey` geht über ein drittes Secret `KEYSTORE_ALIAS`.

## Entwicklung

```bash
flutter pub get
flutter test
bash ci/prepare.sh --debug && flutter run    # Android-Projekt erzeugen und starten
```

Texte: `lib/strings.dart` (erzeugt aus den Web-Texten `ci/strings_web.json` + `ci/strings_extra.json`
mit `python3 ci/gen_strings.py ci/strings_web.json ci/strings_extra.json lib/strings.dart`).
