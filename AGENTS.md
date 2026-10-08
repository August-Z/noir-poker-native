# Development instructions

- Build Android with Kotlin and Jetpack Compose; build iOS with Swift and SwiftUI. Keep separate native domain layers and verify them against the same fixtures. Do not use a WebView, a JavaScript runtime, React Native, Expo, Flutter, or a shared cross-platform UI.
- This is a development starter. Full gameplay, bots, review, persistence, and the original table layout are not implemented yet. Read docs/HANDOFF.md before extending it.
- All application copy, comments, documentation, commit messages, and new test descriptions use English. Translate reference Chinese copy into idiomatic English and standard poker terminology.
- Preserve offline, no-account practice with virtual chips and 5–9 seats. Do not add real-money transactions or a server.
- Use the pinned read-only reference to reproduce behavior, then implement it natively. Never ship .reference or browser assets inside the apps.
- Keep legal actions, settlement, side pots, short all-ins, refunds, and replay rollback in domain code, outside the UI.
- Review only public information available before each decision. Hidden opponent cards, the future deck, and final winners must never grade decisions.
- Cancel stale bot and review work on next hand, replay, reset, and app background transitions.
- Add meaningful native rule regression tests and verify chip conservation. Use the same deterministic fixtures on both platforms.
- Validate native UI at compact and tablet sizes, six and nine seats, and large accessibility text. Preserve the NOIR palette and table hierarchy.
- Keep .github/workflows/native.yml and the Codespaces setup working. Never commit signing keys, provisioning profiles, access tokens, or local.properties.

- Use `zoushicheng0911@gmail.com` for every new commit. Set repository-local Git identity before committing and verify author and committer emails. Do not use a noreply address or bot identity.
