#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
git config user.name August-Z
git config user.email zoushicheng0911@gmail.com
chmod +x gradlew scripts/*.sh
# The pinned reference is no longer public; fetch it only when access exists.
bash scripts/fetch-reference.sh || echo 'Reference unavailable; the committed fixtures are the source of truth.'
bash scripts/doctor.sh
./gradlew -p android/core test
./gradlew :android:app:testDebugUnitTest :android:app:assembleDebug
printf '\nAndroid development is ready. iOS builds run on GitHub macOS runners.\n'
