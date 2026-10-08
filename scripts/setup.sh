#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
chmod +x gradlew scripts/*.sh
bash scripts/fetch-reference.sh
bash scripts/doctor.sh
./gradlew :android:app:testDebugUnitTest :android:app:assembleDebug
printf '\nAndroid development is ready. iOS builds run on GitHub macOS runners.\n'
