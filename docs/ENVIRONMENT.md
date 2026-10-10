# Cloud development and build environment

## Codespaces

Open the repository, select **Code → Codespaces → Create codespace on main**. The dev container installs JDK 17, Node.js 22, Python 3, Android command-line tools, SDK platform 36, and build-tools 35.0.0. Gradle 8.13 is provided through the checked-in wrapper and verified with its distribution SHA-256. `scripts/setup.sh` fetches the pinned reference, checks tools, runs Kotlin unit tests, and generates a debug APK.

If a codespace was created before this configuration was committed, use **Codespaces: Rebuild Container** from the command palette, or create a fresh codespace from the current main branch.

```bash
bash scripts/doctor.sh
./gradlew :android:app:testDebugUnitTest :android:app:assembleDebug
node scripts/check-fixtures.mjs
```

The reference repository is no longer public (2026-10-10). The committed fixtures in `fixtures/` are now the source of truth; CI verifies them with `node scripts/check-fixtures.mjs`, and `generate-reference-fixtures.mjs` runs only where a local checkout of the pinned commit still exists. With a local checkout, `node scripts/generate-reference-fixtures.mjs --check` and the reference's own unit tests still work.

The Android APK is `android/app/build/outputs/apk/debug/app-debug.apk`. It is a debug build of the practice app; see `docs/PARITY.md` for what is complete. An emulator is not required for compilation; UI tests run on GitHub's Android emulator job. Use a real Android device for ongoing interaction and performance checks.

## GitHub Actions

**Native CI** runs on pushes, pull requests, and manual dispatch. It checks the symlink, original reference tests and fixtures, builds Android, runs Kotlin tests, and tests native UI on an Android emulator. Its macOS job runs Swift package tests, generates the Xcode project from `ios/project.yml`, builds and launches the iOS app in a simulator, runs a UI smoke test, and uploads the simulator app and screenshot.

No user-provided secrets are required for these development checks. Android APKs and iOS simulator apps are available in each workflow run's **Artifacts** section. A simulator app is not an iPhone IPA and cannot be installed on a physical iPhone.

## iOS on a Mac or macOS runner

```bash
brew install xcodegen
swift test --package-path ios/Packages/PokerCore
xcodegen generate --spec ios/project.yml
xcodebuild -project ios/NoirPoker.xcodeproj -scheme NoirPoker \
  -sdk iphonesimulator -configuration Debug \
  -derivedDataPath .build/ios CODE_SIGNING_ALLOWED=NO build
```

For interactive iOS simulator work, use a Mac or remote Mac. Codespaces and most Claude Code cloud containers run Linux; they can edit both codebases and build Android with the dev container, while GitHub macOS runners compile/test iOS. Linux `swift test` can test the pure Swift package if a compatible Swift toolchain is installed; it does not validate SwiftUI or an iOS build.

Connect Claude Code Cloud to this repository using your own account's repository access. The Claude runtime may not automatically apply the dev container: use the checked-in scripts or reproduce the Dockerfile toolchain in that environment, and rely on Native CI for both-platform evidence.

## Signing and distribution

Development debug APKs use Android's generated debug key. Store distribution later needs a dedicated signing key configured through secrets. iPhone device builds, TestFlight, and App Store distribution later need the owner's Apple Developer team, bundle registration, signing certificates, and provisioning setup. This starter deliberately does not configure or store those credentials.

## Instruction symlink

`CLAUDE.md` points to `AGENTS.md` and is stored as Git mode `120000`. Linux and macOS preserve it as a real symbolic link. Windows checkouts need symlink support; use the dev container if the Windows checkout materializes the link as a text file. Check with:

```bash
test -L CLAUDE.md
test "$(readlink CLAUDE.md)" = AGENTS.md
git ls-files --stage CLAUDE.md
```
