# Repository Guidelines

## Project Structure & Module Organization
- `porta424_UI/` holds the SwiftUI app target; `Porta424App` in `ContentView.swift` wires the primary `TapeDeckView`.
- `porta424_UI/Components/` contains reusable UI pieces (`ReelAssemblyView`, `TransportBar`, `VUMeter`, `WaveformView`) built for composition.
- `porta424_UI/Audio/` wraps the Dolby B signal chain and timecode helpers; keep DSP-facing code here to simplify future integration with PortaDSP.
- `porta424_UI/Design/` centralizes `PortaColor` and `PortaFont`, so add new design tokens alongside them before use in views.
- `porta424_UI/Assets.xcassets` manages imagery and color assets; prefer PDF vector assets and named colors that match `PortaColor`.

## Build, Test, and Development Commands
- `open porta424_UI.xcodeproj` launches the project in Xcode for simulator or device runs.
- `xcodebuild -project porta424_UI.xcodeproj -scheme porta424_UI -configuration Debug build` performs a CI-friendly build.
- `xcodebuild -project porta424_UI.xcodeproj -scheme porta424_UI -destination 'platform=iOS Simulator,name=iPhone 15' test` runs XCTest bundles once they exist; use this form for automation.

## Coding Style & Naming Conventions
Follow Swift 5.9 defaults: four-space indentation, trailing commas for multiline SwiftUI modifiers, and `camelCase` for properties/functions. Use `PascalCase` for view structs (`TapeDeckView`) and enums, and prefix colors/fonts with `Porta` inside `Design/`. Group view extensions with `// MARK:` sections when files exceed ~150 lines. Run Xcode’s “Editor → Re-Indent” on touched scopes before committing; consistency matters more than tooling right now.

## Testing Guidelines
Add new XCTest targets under `porta424_UI` as `porta424_UITests` for UI assertions and `porta424_UIAudioTests` for DSP validation. Mirror feature modules with test files named `{Type}Tests.swift`, and seed view models with deterministic fixtures from `Audio/`. Execute `xcodebuild … test` locally before opening a PR, and aim for coverage on parameter edge cases and animation timing where feasible.

## Commit & Pull Request Guidelines
Recent history favors short, present-tense subjects (“adds readme”, “initial commit”). Continue that style, keeping body text optional but focused on rationale or follow-up tasks. Open PRs should include: summary of user-facing changes, simulator screenshots when UI shifts, references to PortaDSP issues, and a checklist of manual validation (simulator model, iOS version, audio routing). Squash commits when merging unless reviewers request otherwise.

## Asset & Audio Handling
Keep large reference audio files out of the repository; rely on small loops under `Audio/` for demos and document any external downloads. When adding new assets, note licensing in the PR and ensure filenames stay lowercase with hyphens (`play-button.pdf`) to avoid asset catalog merge conflicts.
