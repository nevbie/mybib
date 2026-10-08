#!/usr/bin/env bash
# Bereitet das Android-Projekt vor (wird vom GitHub-Workflow aufgerufen).
# Ohne Argument: Release mit festem Signaturschlüssel aus den GitHub-Secrets.
# Mit "--debug": ohne Secrets (für den CI-Test-Build).
set -e
MODE="${1:-release}"
APP_NAME=$(cat ci/app_name.txt | tr -d '\r\n')

if [ "$MODE" = "release" ]; then
  # Build-Nummer (versionCode) = Anzahl der Commits auf dem Branch; steigt mit jedem Merge.
  # Braucht die volle Git-History (actions/checkout mit fetch-depth: 0).
  if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
    echo "::error::Shallow clone – die Build-Nummer braucht die volle History (fetch-depth: 0)."
    exit 1
  fi
  BUILD_NUMBER=$(git rev-list --count HEAD)
  APP_VERSION="$(cat ci/version.txt | tr -d '\r\n').$BUILD_NUMBER"
  echo "App-Name: $APP_NAME, Version: $APP_VERSION, Build: $BUILD_NUMBER"
  if [ -n "$GITHUB_ENV" ]; then
    echo "APP_NAME=$APP_NAME" >> "$GITHUB_ENV"
    echo "APP_VERSION=$APP_VERSION" >> "$GITHUB_ENV"
    echo "BUILD_NUMBER=$BUILD_NUMBER" >> "$GITHUB_ENV"
  fi

  # Signaturschlüssel aus GitHub-Secrets (nie im Repository!)
  if [ -z "$KEYSTORE_BASE64" ] || [ -z "$KEYSTORE_PASSWORD" ]; then
    echo "::error::GitHub-Secrets KEYSTORE_BASE64 und KEYSTORE_PASSWORD fehlen (Settings > Secrets and variables > Actions). Anleitung: app/README.md"
    exit 1
  fi
  KS="${RUNNER_TEMP:-/tmp}/mybib.keystore"
  echo "$KEYSTORE_BASE64" | tr -d ' \r\n' | base64 -d > "$KS"
  [ -n "$GITHUB_ENV" ] && echo "KEYSTORE_FILE=$KS" >> "$GITHUB_ENV"
fi

# App-ID im Play Store: app.mybib (darf sich nie mehr ändern!)
flutter create --platforms=android --org app --project-name mybib .
rm -f test/widget_test.dart.orig

MANIFEST=android/app/src/main/AndroidManifest.xml
# App-Name
sed -i "s/android:label=\"[^\"]*\"/android:label=\"$APP_NAME\"/" "$MANIFEST"
# Internet (Cover, Online-Suche, Claude) – flutter create setzt es nur für Debug-Builds
grep -q 'android.permission.INTERNET' "$MANIFEST" || sed -i 's#<manifest xmlns:android="http://schemas.android.com/apk/res/android"[^>]*>#&\n    <uses-permission android:name="android.permission.INTERNET"/>#' "$MANIFEST"
grep -q 'android.permission.INTERNET' "$MANIFEST" || { echo "::error::INTERNET-Berechtigung konnte nicht eingetragen werden"; exit 1; }

# App-Icon
for d in icon/mipmap-*; do
  cp "$d/ic_launcher.png" "android/app/src/main/res/$(basename "$d")/ic_launcher.png"
done

[ "$MODE" = "release" ] || exit 0

# Fester Signaturschlüssel (Release-Builds werden mit dem "debug"-Eintrag signiert, wie bei cheesychess)
python3 - <<'PY'
import os, re
kts = 'android/app/build.gradle.kts'
groovy = 'android/app/build.gradle'
if os.path.exists(kts):
    path = kts
    block = ('    signingConfigs {\n'
             '        getByName("debug") {\n'
             '            storeFile = file(System.getenv("KEYSTORE_FILE") ?: "missing.keystore")\n'
             '            storePassword = System.getenv("KEYSTORE_PASSWORD")\n'
             '            keyAlias = System.getenv("KEYSTORE_ALIAS") ?: "androiddebugkey"\n'
             '            keyPassword = System.getenv("KEYSTORE_PASSWORD")\n'
             '        }\n'
             '    }\n')
else:
    path = groovy
    block = ('    signingConfigs {\n'
             '        debug {\n'
             "            storeFile file(System.getenv('KEYSTORE_FILE') ?: 'missing.keystore')\n"
             "            storePassword System.getenv('KEYSTORE_PASSWORD')\n"
             "            keyAlias System.getenv('KEYSTORE_ALIAS') ?: 'androiddebugkey'\n"
             "            keyPassword System.getenv('KEYSTORE_PASSWORD')\n"
             '        }\n'
             '    }\n')
src = open(path).read()
if 'KEYSTORE_FILE' not in src:
    src = re.sub(r'(?m)^android \{\n', lambda m: m.group(0) + block, src, count=1)
    open(path, 'w').write(src)
print(src)
PY
