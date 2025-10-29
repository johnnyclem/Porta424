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



## Other branches to reference that need to be reviewed and merged in if appropriate:
 * [new branch]      codex/add-auparametertree-for-portadspaudiounit      -> origin/codex/add-auparametertree-for-portadspaudiounit
 * [new branch]      codex/add-avaudioengine-helper-and-example           -> origin/codex/add-avaudioengine-helper-and-example
 * [new branch]      codex/add-continuous-fuzz-testing-support            -> origin/codex/add-continuous-fuzz-testing-support
 * [new branch]      codex/add-cross-platform-guards-for-audiotoolbox     -> origin/codex/add-cross-platform-guards-for-audiotoolbox
 * [new branch]      codex/add-crosstalk-and-azimuth-jitter-simulation    -> origin/codex/add-crosstalk-and-azimuth-jitter-simulation
 * [new branch]      codex/add-dropout-and-compander-features             -> origin/codex/add-dropout-and-compander-features
 * [new branch]      codex/add-dsp-passthrough-c-stub                     -> origin/codex/add-dsp-passthrough-c-stub
 * [new branch]      codex/add-factory-presets-feature                    -> origin/codex/add-factory-presets-feature
 * [new branch]      codex/add-macos-latest-job-to-ci-pipeline            -> origin/codex/add-macos-latest-job-to-ci-pipeline
 * [new branch]      codex/add-parameter-sliders-in-contentview           -> origin/codex/add-parameter-sliders-in-contentview
 * [new branch]      codex/add-performance-benchmarking-target            -> origin/codex/add-performance-benchmarking-target
 * [new branch]      codex/add-real-time-audio-level-visualization        -> origin/codex/add-real-time-audio-level-visualization
 * [new branch]      codex/add-shaped-noise-floor-with-lpf-control        -> origin/codex/add-shaped-noise-floor-with-lpf-control
 * [new branch]      codex/add-tests-for-audio-buffer-formats             -> origin/codex/add-tests-for-audio-buffer-formats
 * [new branch]      codex/add-unit-tests-for-internalrenderblock         -> origin/codex/add-unit-tests-for-internalrenderblock
 * [new branch]      codex/add-user-preset-saving-and-factory-defaults    -> origin/codex/add-user-preset-saving-and-factory-defaults
 * [new branch]      codex/add-wow/flutter-modulation-feature             -> origin/codex/add-wow/flutter-modulation-feature
 * [new branch]      codex/add-xctest-for-passthrough-functionality       -> origin/codex/add-xctest-for-passthrough-functionality
 * [new branch]      codex/create-auaudiounit-node-backed-by-c-bridge     -> origin/codex/create-auaudiounit-node-backed-by-c-bridge
 * [new branch]      codex/create-porta424audioengine-package             -> origin/codex/create-porta424audioengine-package
 * [new branch]      codex/create-refactor-branch-and-fix-build-errors    -> origin/codex/create-refactor-branch-and-fix-build-errors
 * [new branch]      codex/expand-test-coverage-for-portadspwrapper       -> origin/codex/expand-test-coverage-for-portadspwrapper
 * [new branch]      codex/expose-per-channel-dbfs-in-swiftui-demo        -> origin/codex/expose-per-channel-dbfs-in-swiftui-demo
 * [new branch]      codex/implement-dsp-module-processing-methods        -> origin/codex/implement-dsp-module-processing-methods
 * [new branch]      codex/implement-head-bump-eq-feature                 -> origin/codex/implement-head-bump-eq-feature
 * [new branch]      codex/implement-preset-serialization-in-params       -> origin/codex/implement-preset-serialization-in-params
 * [new branch]      codex/implement-saturation-stage-with-drive-in-db    -> origin/codex/implement-saturation-stage-with-drive-in-db
 * [new branch]      codex/integrate-dspcore-in-portadsp_bridge.cpp       -> origin/codex/integrate-dspcore-in-portadsp_bridge.cpp
 * [new branch]      codex/update-developer-documentation-for-quick-start -> origin/codex/update-developer-documentation-for-quick-start
 * [new branch]      codex/update-dropout-handling-logic                  -> origin/codex/update-dropout-handling-logic
 * [new branch]      codex/update-eq-helper-calculations                  -> origin/codex/update-eq-helper-calculations
 * [new branch]      codex/update-package.swift-for-testing               -> origin/codex/update-package.swift-for-testing
 * [new branch]      codex/verify-swift-to-c-parameter-bridging           -> origin/codex/verify-swift-to-c-parameter-bridging
