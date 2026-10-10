# mybib – Android-App (Kotlin + Jetpack Compose)

Die native Android-Version von mybib: Bücher, Spiele, DVDs und CDs katalogisieren – Deutsch & Englisch.
Löst die frühere Flutter-App ab, mit gleichem Funktionsumfang und **gleichem Datenformat** wie die
Web-Version im Hauptordner: dort *Sicherung exportieren*, hier *Datei importieren* – fertig.

- Hinzufügen per Barcode-Scan (ISBN/EAN, CameraX + ML Kit), Regalfoto (Claude, eigener API-Schlüssel),
  Cover-Foto, Online-Suche (Google Books, Open Library, MusicBrainz + Cover Art Archive, UPCitemdb),
  von Hand oder per Import-Datei
- Fehlende Infos (Cover, Verlag, Jahr, ISBN, Klappentext) gesammelt über Google Books ergänzen
- Bewertung, Status, Format, Wunschliste, Empfehlung, Kategorie, Raum, Verleihen, Notizen, eigenes Cover, Teilen
- Bibliothek mit Suche, Filtern, Sortierung und Mehrfach-Bearbeitung; Orte & Kategorien
- Daten nur auf dem Gerät, Sicherung als JSON speichern/teilen, Tabelle (CSV) teilen
- Play Store: App-ID **app.mybib** (darf sich nie mehr ändern) – gleiche ID und gleicher Schlüssel wie
  die Flutter-App, die Android-App installiert sich also als Update darüber.
  Die Daten liegen im selben Ordner wie bei Flutter (`app_flutter/items.json`, `settings.json`) und bleiben erhalten.

## Aufbau

| Ordner | Inhalt |
| --- | --- |
| `core/` | reines Kotlin/JVM-Modul ohne Android: Datenmodell, `normalizeItem`, Suche/Filter/Sortierung, Import/Export/CSV, ISBN, Kategorien, Texte (i18n), Online-Suche und Claude-Client (über eine kleine `Http`-Schnittstelle, Standard: `HttpURLConnection`), Speicher (`Store`, JSON-Dateien). Mit JUnit-Tests. |
| `app/` | die Android-App: Compose Material 3, ein `AppViewModel` mit eigenem Bildschirm-Stapel (`Screen.kt`), Screens in `ui/`. Coil für Cover, CameraX + ML Kit (gebündeltes Modell) für den Scanner, Fotoauswahl/Kamera über ActivityResult + FileProvider, Speichern/Öffnen über das Storage Access Framework. |
| `gradle/libs.versions.toml` | alle Versionen |
| `version.txt` | Versionsanfang; `versionName` = `<version.txt>.<Anzahl Commits>`, `versionCode` = Anzahl Commits |
| `store/` | 512-px-Icon für die Play Console |

Texte: einzige Quelle ist `../shared/strings.json` (de/en mit `{platzhalter}`). Der Gradle-Task
`sharedStrings` legt sie beim Bauen als Asset in die App; nicht ins Projekt kopieren.

## Builds (GitHub Actions)

- `.github/workflows/android-ci.yml` – bei jedem Pull Request und Push (Änderungen in `android/` oder `shared/`):
  Tests, Lint und eine Test-APK (Debug, ohne Signaturschlüssel) als Artefakt.
- `.github/workflows/android-build.yml` – bei jedem Merge nach `main`: signierte **APK** (zum direkten
  Installieren) und **AAB** (für die Play Console) als GitHub-Release `android-build-N`.

### Signaturschlüssel einrichten (einmalig)

Die Release-Builds brauchen zwei GitHub-Secrets (*Settings → Secrets and variables → Actions*) –
dieselben wie für die frühere Flutter-App:

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

Gradle liest den Schlüssel aus den Umgebungsvariablen `KEYSTORE_FILE`, `KEYSTORE_PASSWORD` und
`KEYSTORE_ALIAS`. Fehlen sie, wird auch der Release-Build mit dem Debug-Schlüssel signiert.

## Entwicklung

Voraussetzungen: JDK 17 und das Android SDK (z. B. über Android Studio; `local.properties` mit `sdk.dir`).

```bash
cd android
./gradlew :core:test                    # Logik-Tests
./gradlew :app:assembleDebug            # Debug-APK: app/build/outputs/apk/debug/
./gradlew :app:installDebug             # auf ein angeschlossenes Handy
MYBIB_CORE_ONLY=1 ./gradlew :core:test  # nur das Kotlin-Modul, ohne Android SDK / Google Maven
```

Versionsnummer lokal setzen: `./gradlew :app:assembleRelease -PversionCode=$(git rev-list --count HEAD)`
(ohne Angabe: 1).
