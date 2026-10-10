# NOIR Poker Native

Native offline Texas Hold’em practice apps in one independent repository.

- **Android:** Kotlin + Jetpack Compose, Android 8.0+.
- **iOS:** Swift + SwiftUI, iOS 17+.
- **Language:** English throughout the product, source comments, and documentation.
- **Development:** GitHub Codespaces for Android and editing; GitHub Actions macOS runners for iOS builds and simulator tests.

## Status

Both apps are playable offline practice tables with virtual chips and 5–9 seats: a native rules engine (legal actions, side pots, short all-ins, refunds, odd chips, replay), the nine bot styles with synthetic emotions and thinking time, Finish Hand and practice runouts, public-information decision review with counterfactual simulation, Opponent Styles, saved preferences, and the NOIR table layout. The Kotlin (`android/core`) and Swift (`ios/Packages/PokerCore`) domain layers are checked against the same reference-derived fixtures. Parity with the reference is not complete: [`docs/PARITY.md`](docs/PARITY.md) lists the status of every feature, the deliberate deviations, and the remaining gaps, such as release-build profiling and some UI test coverage.

The migration reference is pinned to [`JessieZJZ/noir-poker@03c7823`](https://github.com/JessieZJZ/noir-poker/tree/03c78233f9454de54e378c5c81ba1dd25fa9b14e). Its browser implementation is fetched into an ignored reference directory for analysis and parity tests, and is never bundled into the native apps. This repository has no GitHub fork relationship.

## Start in the cloud

1. Open **Code → Codespaces → Create codespace on main**. The dev container prepares Android and fetches the reference.
2. Run `bash scripts/doctor.sh` and `./gradlew :android:app:testDebugUnitTest :android:app:assembleDebug`.
3. Open **Actions → Native CI** to see both-platform builds and download artifacts. Android APKs install on Android; iOS simulator archives are for simulators only.
4. Read [the environment guide](docs/ENVIRONMENT.md), [the migration contract](docs/MIGRATION.md), and [the Claude Code handoff](docs/HANDOFF.md).

## Layout

```text
android/core/             Kotlin domain layer (pure JVM)
android/app/              Compose UI and Android platform adapters
ios/NoirPoker/            SwiftUI UI
ios/Packages/PokerCore/   Native Swift domain package
ios/project.yml          Reproducible Xcode project definition
fixtures/                Shared reference contracts
scripts/                 Setup, diagnostics, and reference-fixture tools
.devcontainer/           Browser-based Android development environment
.github/workflows/       Linux/Android and macOS/iOS validation
AGENTS.md                Project instructions
CLAUDE.md -> AGENTS.md   One instruction source for both coding agents
```

Only virtual chips are used. Full development must preserve the original offline, no-login behavior and the explicit rules/review privacy boundaries in the migration contract.
