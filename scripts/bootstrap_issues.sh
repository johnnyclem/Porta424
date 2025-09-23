#!/usr/bin/env bash
set -euo pipefail

# Create the standard PortaDSPKit issues via GitHub CLI.
# Usage:
#   bash bootstrap_issues.sh                # uses current repo (gh context)
#   bash bootstrap_issues.sh -R owner/repo  # explicit repo

REPO_SLUG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -R|--repo)
      REPO_SLUG="$2"
      shift 2
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "${REPO_SLUG}" ]]; then
  # auto-detect current repo from gh context
  if ! command -v gh >/dev/null 2>&1; then
    echo "ERROR: GitHub CLI 'gh' not found. Install from https://cli.github.com/" >&2
    exit 1
  fi
  REPO_SLUG="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
  if [[ -z "${REPO_SLUG}" ]]; then
    echo "ERROR: Could not auto-detect repo. Pass -R owner/repo." >&2
    exit 1
  fi
fi

echo "Using repository: ${REPO_SLUG}"
gh auth status || true

create_issue() {
  local title="$1"; shift
  local labels_csv="$1"; shift
  local body="$1"; shift || true

  # If an open issue with identical title already exists, skip.
  if gh issue list -R "$REPO_SLUG" --state open --search "in:title \"$title\"" --json title | jq -e --arg t "$title" '.[] | select(.title == $t)' >/dev/null; then
    echo "⏭️  Skipping (already exists): $title"
    return 0
  fi

  # Convert comma-separated labels to multiple -l flags
  IFS=',' read -r -a labels_arr <<< "$labels_csv"
  local label_flags=()
  for l in "${labels_arr[@]}"; do
    # trim spaces
    l="$(echo "$l" | sed -e 's/^ *//' -e 's/ *$//')"
    [[ -n "$l" ]] && label_flags+=( -l "$l" )
  done

  echo "➕ Creating issue: $title"
  gh issue create -R "$REPO_SLUG" -t "$title" -b "$body" "${label_flags[@]}" >/dev/null
}

ISSUE_1_TITLE="Add cross-platform guards for AudioToolbox"
ISSUE_1_LABELS="platform, infra, good first issue"
read -r -d '' ISSUE_1_BODY <<'EOF'
**Goal**  
Make the package compile on non-Apple platforms by gating AU/AudioToolbox code and shipping minimal Linux stubs.

### Tasks
- [ ] Add `Platform.swift` with `PORTA_DARWIN` (`#if canImport(AudioToolbox)`).
- [ ] Wrap all `AudioToolbox`/`AUAudioUnit` imports and usages.
- [ ] Provide Linux stubs for AU-dependent types/APIs that throw `.unsupportedPlatform`.
- [ ] Ensure public API surface compiles on Linux.

### Acceptance Criteria
- [ ] `swift build` succeeds on **Linux** (CI).
- [ ] Darwin builds unchanged; local/macOS build is green.
- [ ] Clear runtime error surfaced if AU paths invoked on Linux.

### Test Plan
- Linux: `swift build` only.
- macOS: local build for AU target (no sample yet).
EOF

ISSUE_2_TITLE="Add DSP passthrough C stub for testing"
ISSUE_2_LABELS="audio, testing, bridge"
read -r -d '' ISSUE_2_BODY <<'EOF'
**Goal**  
Add a trivial DSP entry point to validate buffer flow and the Swift↔C bridge.

### Tasks
- [ ] Add `Sources/PortaDSPKit/C/dsp_passthrough.c`:
  ```c
  void porta_dsp_passthrough(const float *in, float *out, int frames, int channels) {
      int n = frames * channels;
      for (int i = 0; i < n; ++i) out[i] = in[i];
  }
```

* [ ] Expose header + modulemap so Swift can call it.
* [ ] Optional Swift shim for ergonomic invocation in tests.

### Acceptance Criteria

* [ ] Stub compiles and links on Linux & macOS.
* [ ] Calling it with test buffers yields identical output.

### Test Plan

* Temporary unit test or playground to call stub directly.
  EOF

ISSUE\_3\_TITLE="Implement XCTest for passthrough processing"
ISSUE\_3\_LABELS="testing, audio"
read -r -d '' ISSUE\_3\_BODY <<'EOF'
**Goal**
Prove buffer flow correctness with deterministic tests.

### Tasks

* [ ] Add `PortaDSPKitTests/PassthroughTests.swift`.
* [ ] Generate mono/stereo buffers of sizes 32, 128, 512 with seed data.
* [ ] Invoke `porta_dsp_passthrough` (Linux) or AU path (Darwin).
* [ ] Assert `abs(out[i] - in[i]) <= 1e-6`.

### Acceptance Criteria

* [ ] Tests pass on macOS CI.
* [ ] Linux path executes via direct C call (no AU).

### Test Plan

* Run in CI with both runners; ensure consistent results.
  EOF

ISSUE\_4\_TITLE="Verify Swift→C parameter bridging"
ISSUE\_4\_LABELS="bridge, testing"
read -r -d '' ISSUE\_4\_BODY <<'EOF'
**Goal**
Guarantee `PortaDSP.Params.makeCParams()` mirrors Swift values in the C struct.

### Tasks

* [ ] Add randomized table-driven tests (≥100 cases).
* [ ] Include boundary values (0.0/1.0/min/max per field).
* [ ] Field-by-field equality checks, including optional/default handling.

### Acceptance Criteria

* [ ] All parameter cases pass on macOS CI.
* [ ] Tests do not rely on AudioToolbox (Linux-safe).

### Test Plan

* Pure Swift unit tests invoking `makeCParams()` only.
  EOF

ISSUE\_5\_TITLE="AVAudioEngine helper + minimal example app"
ISSUE\_5\_LABELS="feature, audio, docs, example"
read -r -d '' ISSUE\_5\_BODY <<'EOF'
**Goal**
One-liner helper to attach the AU to `AVAudioEngine`, plus a runnable demo.

### Tasks

* [ ] Add `PortaDSPAudioUnit.makeEngineNode() throws -> AVAudioUnit`.
* [ ] Add `/Examples/AVEngineDemo` (macOS or iOS):

  * Route `inputNode → PortaDSP → mainMixer`.
  * Simple UI: start/stop; optional gain param.
* [ ] README quick-start snippet.

### Acceptance Criteria

* [ ] Example builds and plays through on Darwin.
* [ ] With passthrough DSP, output == input (audibly unchanged).

### Test Plan

* Manual verification (headphones), basic console logs for render callbacks.
  EOF

ISSUE\_6\_TITLE="Add macOS CI job (keep Linux job green)"
ISSUE\_6\_LABELS="infra, ci, platform"
read -r -d '' ISSUE\_6\_BODY <<'EOF'
**Goal**
Run full build+tests on macOS; keep Linux compile for cross-platform coverage.

### Tasks

* [ ] Add `.github/workflows/ci.yml` with:

  * **linux** job: `swift build` (no AU).
  * **macos** job: `xcodebuild ... build test` or `swift test` if SPM-only.
* [ ] Cache artifacts where sensible.
* [ ] Badge in README for both jobs.

### Acceptance Criteria

* [ ] Both jobs run on PRs and pass.
* [ ] Darwin job executes unit tests from Issues #3–4.

### Test Plan

* Open a draft PR to trigger both runners.
  EOF

ISSUE\_7\_TITLE="Developer docs pass (Quick-start + Platform notes)"
ISSUE\_7\_LABELS="docs"
read -r -d '' ISSUE\_7\_BODY <<'EOF'
**Goal**
Ensure a new contributor can build, run tests, and try the example in <10 minutes.

### Tasks

* [ ] README updates:

  * Installation & requirements.
  * Quick-start `AVAudioEngine` snippet.
  * Running tests on macOS.
  * Linux stubs and limitations.
* [ ] `/Docs/` page with deeper notes on Params bridging and render flow.
* [ ] Link CI badges.

### Acceptance Criteria

* [ ] Fresh-clone dry run follows README successfully.
* [ ] Example app launches and routes audio.

### Test Plan

* Have a teammate follow the steps verbatim.
  EOF

create\_issue "\$ISSUE\_1\_TITLE" "\$ISSUE\_1\_LABELS" "\$ISSUE\_1\_BODY"
create\_issue "\$ISSUE\_2\_TITLE" "\$ISSUE\_2\_LABELS" "\$ISSUE\_2\_BODY"
create\_issue "\$ISSUE\_3\_TITLE" "\$ISSUE\_3\_LABELS" "\$ISSUE\_3\_BODY"
create\_issue "\$ISSUE\_4\_TITLE" "\$ISSUE\_4\_LABELS" "\$ISSUE\_4\_BODY"
create\_issue "\$ISSUE\_5\_TITLE" "\$ISSUE\_5\_LABELS" "\$ISSUE\_5\_BODY"
create\_issue "\$ISSUE\_6\_TITLE" "\$ISSUE\_6\_LABELS" "\$ISSUE\_6\_BODY"
create\_issue "\$ISSUE\_7\_TITLE" "\$ISSUE\_7\_LABELS" "\$ISSUE\_7\_BODY"

echo "✅ Done. Created (or skipped existing) issues in \${REPO\_SLUG}."
