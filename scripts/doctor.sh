#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
java -version
node --version
python3 --version
test -n "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}" || { printf 'Android SDK is not configured. Use the dev container.\n' >&2; exit 1; }
./gradlew --version
printf 'Toolchain checks passed.\n'
