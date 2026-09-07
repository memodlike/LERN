# Security Review: LERN - Daily quotes

## Scope

Registered Git baseline c9cd8f1 plus source-backed verification of fixes through 67ad647.

- Scan mode: repository
- Target kind: git_revision
- Target ID: target_sha256_6dece09e99c223655dde200fa45fff044524efb5d4edad94043617e023cbcf2c
- Revision: c9cd8f194b6101ad8955bf0cce18d549b574da9d
- Inventory strategy: repository
- Included paths: .
- Excluded paths: none
- Runtime or test status: Core regression suites passed on bcc0389 and 67ad647; Xcode 26.2 built iPhone with embedded Watch and all extensions; four hosted app integration tests passed. Final UI suite is ongoing.

Limitations and exclusions:
- Original targetRevision retained; findings describe pre-fix baseline and identify applied remediation commits.
- No physical-device signing, memory pressure or live Watch transport test.
- Some later asset/documentation changes have only packaging or implementation review, so repository-wide completeness is conservatively partial.

### Scan Summary

| Field | Value |
| --- | --- |
| Scan outcome | completed |
| Reportable findings | 2 |
| Severity mix | low: 2 |
| Confidence mix | high: 2 |
| Coverage | partial |
| Validation mode | Source audit, targeted tests and CI simulator verification |

Canonical artifacts: `scan-manifest.json`, `findings.json`, and `coverage.json`. This report is a deterministic projection of those files.

## Threat Model

LERN is a native local quote library with SwiftUI screens, a background SwiftData actor, independent selection cursors, a rolling local-notification queue, WidgetKit/App Intents, and a separate paired Watch snapshot. There is no backend, account, analytics SDK, web-rendered imported HTML or runtime third-party package.

### Assets

- User-authored/imported text, favorites, collections and history
- Local settings, reminder plans, photos and resource covers
- Application availability and backup integrity

### Trust Boundaries

- External Files/Photos data -\> parsing and validation -\> local SwiftData/photos
- Application -\> App Group container -\> entitled WidgetKit process
- iPhone -\> OS-authenticated WatchConnectivity -\> separately stored Watch snapshot
- Local quote -\> notification request -\> OS-controlled lock screen and mirroring
- Local rendered image/text -\> user-selected Photos, Files, share recipient or Shortcuts automation

### Attacker Capabilities

- Supply a content file, resource catalog, backup or photo that a user explicitly chooses
- Invoke the public lern URL scheme with arbitrary strings
- Supply App Intent parameters through system invocation

### Security Objectives

- Keep core operations local and preserve user content
- Bound imported representations before allocation/hashing
- Validate restored values before persistence or filesystem mutation
- Confine media paths to the application storage area
- Expose content externally only through requested system surfaces, explicit sharing or paired Watch synchronization

### Assumptions

- Apple sandbox, signing, App Group entitlements and Watch pairing enforce their documented boundaries
- SwiftData/JSONDecoder/ImageIO framework internals and the host OS are trusted
- No adversary with arbitrary write access to the app container or repository is assumed
- iOS notifications and widgets are scheduled opportunistically within system policy

## Findings

| Finding | Severity | Confidence | Detailed write-up |
| --- | --- | --- | --- |
| [Import limits are enforced after unbounded representation expansion](#finding-1) | low | high | inline below |
| [Backup replacement accepts state that can trap on startup](#finding-2) | low | high | inline below |

### Confidence Scale

| Label | Meaning |
| --- | --- |
| high | Direct evidence supports the finding with no material unresolved blocker. |
| medium | Evidence supports a plausible issue, but material runtime or reachability proof remains. |
| low | Evidence is incomplete and the item is retained only for explicit follow-up. |

<a id="finding-1"></a>

### [1] Import limits are enforced after unbounded representation expansion

| Field | Value |
| --- | --- |
| Severity | low |
| Confidence | high |
| Confidence rationale | Source shows materialization before the entry guard. Patched over-limit TXT/CSV, JSON nesting/token and Markdown metadata regressions passed on macOS and iOS. |
| Category | resource-exhaustion |
| CWE | CWE-400 |
| Affected lines | Sources/LERNCore/Importers.swift:36-54, Sources/LERNCore/Importers.swift:64-67, Sources/LERNCore/Importers.swift:75-109, Sources/LERNCore/Importers.swift:119 |

#### Summary

At the c9cd8f1 baseline, files below the byte cap can create far more rows, nested JSON values or repeated Markdown metadata than the intended entry limit before validation runs. The affected parsers share the missing pre-expansion resource budget. Later commits add incremental and cumulative bounds.

#### Root Cause

A byte-size check is used as a substitute for limits on decoded rows, nested tokens and repeated metadata, while entry count is checked after expansion.

**Entry budget runs after parsing** — `Sources/LERNCore/Importers.swift:46-47`

The caller rejects a large result only after the parser has allocated it.

```swift
else { output = try parser.parse(text, mode: mode) }
guard output.entries.count <= Self.entryLimit else { throw ImportFailure.tooLarge }
```

**Full TXT component and entry arrays** — `Sources/LERNCore/Importers.swift:66-67`

A compact newline-heavy file can allocate a large intermediate array and EntryDraft array.

```swift
let parts = paragraphs ? text.components(separatedBy: "\n\n") : text.components(separatedBy: "\n")
return (parts.map { EntryDraft(text: $0) }.filter { !$0.text.isEmpty }, [])
```

**Unbounded inherited metadata** — `Sources/LERNCore/Importers.swift:93`

Front matter values are inherited without per-field or expanded-byte bounds and are then repeatedly normalized and hashed.

```swift
if !value.isEmpty { entries.append(EntryDraft(text: value, author: author, source: source, tags: tags, section: section)) }
```

#### Validation

TXT/CSV now stop during iteration, JSON counts nesting, strings, containers and total tokens before decoding, JSONL shares the cumulative budget, and Markdown checks metadata before hashing with an expanded-byte cap. All 39 core tests passed on bcc0389 in run 34119790937; local 50k parser and CSV boundary smoke tests also passed.

Validation method: Source trace and regression execution

- **Status:** validated

Counterevidence and remaining uncertainty:
- 100 MiB input cap and explicit selection already limit the attack.
- Memory termination itself was not deliberately reproduced on a physical device.

Limitations:
- Peak memory/energy profiling on physical hardware remains unperformed.

#### Dataflow

Attacker-crafted supported file -\> native Files picker -\> UTF-8 normalization -\> parser expansion -\> EntryDraft arrays, Foundation JSON objects and repeated hashes -\> resource exhaustion before postparse rejection.

#### Reachability

User can import supplied local text or JSON libraries; attacker controls structural density and metadata.

- **Attacker:** Author of an imported content file

Preconditions:
- The user chooses the crafted file in the import screen.

#### Severity

**Low** — A crafted file can consume the local process memory or CPU; selection by the user is required, and restarting without importing the file recovers the app.

Additional runtime or deployment evidence could raise or lower this severity.

**Impact assessment:** Local process memory exhaustion or prolonged processing.

**Likelihood assessment:** Low with explicit import selection; no unattended network ingress.

#### Remediation

Applied in 07da795 and abfbf1d: streaming TXT/CSV iteration; cumulative JSONResourceBudget; metadata and paragraph limits before EntryDraft creation; incremental JSONL; total inherited metadata budget. BOM whitespace regression fixed in bcc0389.

Tests:
- Tests/LERNCoreTests/ResourceBudgetTests.swift
- Tests/LERNCoreTests/StorageTests.swift: parsersRejectOverLimit

<a id="finding-2"></a>

### [2] Backup replacement accepts state that can trap on startup

| Field | Value |
| --- | --- |
| Severity | low |
| Confidence | high |
| Confidence rationale | The baseline validator returns the supplied settings without domain checks; the startup consumers use those settings directly. Patched rejection tests passed in CI on bcc0389. |
| Category | improper-input-validation |
| CWE | CWE-20, CWE-190 |
| Affected lines | Sources/LERNCore/Engines.swift:85-91, App/BackupView.swift:56-74, Sources/LERNCore/Models.swift:172 |

#### Summary

At the registered c9cd8f1 baseline, a supplied backup can persist an overflowing streak counter, negative selection cursor, empty theme list or invalid membership ordinal. Opening the restored library then reaches unchecked arithmetic or indexing. These conditions were repaired in later commits.

#### Root Cause

Untrusted persisted settings are treated as valid after shape and content checks, without checking the domains assumed by their use sites.

**Baseline validator returns unchecked settings** — `Sources/LERNCore/Engines.swift:90-91`

These checks cover entries, links and file names but omit restored counters, ordinals, selection positions and nonempty themes.

```swift
guard entries.allSatisfy({ $0.id == $0.draft.id && !$0.draft.text.isEmpty && $0.draft.text.count <= ImportService.textLimit }), memberships.allSatisfy({ ids.contains($0.entryID) && topicIDs.contains($0.topicID) }), photos.allSatisfy({ Self.safeAssetName($0.key) && $0.value.count <= 20_000_000 }) else { throw ImportFailure.malformed("Invalid entries, links or photo names.") }
return self
```

#### Validation

Original c9cd8f1 source admits the supplied invalid state. BackupSafetyTests rejects Int.max streak regeneration, negative cursor, empty themes and Int.max ordinal after the fix; the 39-test core suite passed on bcc0389 in run 34119790937.

Validation method: Source trace plus patched regression tests

- **Status:** validated

Counterevidence and remaining uncertainty:
- Requires an explicitly chosen backup and replacement action.
- No exploit was run on a physical iPhone.

Limitations:
- Report target remains the original baseline; the latest source is a remediated implementation, not a retargeted scan.

#### Dataflow

Attacker-provided JSON -\> Files selection -\> JSONDecoder -\> LibraryBackup.validated -\> LibraryStore.restore -\> persisted preferences -\> AppState.load and selection/streak consumers.

#### Reachability

Reachable through local backup replacement when the user chooses a crafted file.

- **Attacker:** Author of an imported backup

Preconditions:
- User explicitly selects and replaces from the crafted backup.

#### Severity

**Low** — Availability impact is limited to the local app and requires the user to select and replace with an attacker-supplied backup; no code execution or data disclosure is established.

Additional runtime or deployment evidence could raise or lower this severity.

**Impact assessment:** Local application availability; repeated startup failures may require restoring or clearing its data.

**Likelihood assessment:** Low because the attacker must induce explicit backup replacement.

#### Remediation

Applied: validate all settings domains before restore, guard counters at use sites and use fallback themes. Numeric/state fix is in 07da795; predecode structure and transactional photo staging are in abfbf1d; entry metadata validation is strengthened in 67ad647.

Tests:
- Tests/LERNCoreTests/StorageTests.swift: BackupSafetyTests

## Reviewed Surfaces

| Surface | Risk Area | Outcome | Notes |
| --- | --- | --- | --- |
| Backup trust boundary and persisted state | not recorded | Reported | backup-invariants validated against registered baseline; later domain guards and safe photo staging checked with passing regressions. |
| Content parser representation budgets | not recorded | Reported | import-resource-limit and nested-import-resource-limit merged because both concern decoded representation limits before materialization; all original parser routes retained. Later fixes tested. |
| Explicit export, links and photos | not recorded | No issue found | SwiftUI renders imported text inertly. Resource URLs permit only http/https on explicit tap; photo names are contained, fresh UUID images are staged and decoded into thumbnails. |
| App Group, widget intents and paired Watch | not recorded | No issue found | No unauthenticated network listener or arbitrary filesystem path. App Group relies on entitlements and Apple pairing; Watch snapshot is bounded and favorite IDs validated in remediated source. |
| Build and dependencies | not recorded | No issue found | Local Swift package only, no third-party runtime dependency, no embedded service credentials, read-only CI permissions; native extensions compile. |

## Open Questions And Follow Up

- Physical-device memory/energy behavior and signed App Group/Watch runtime enforcement have not been exercised.
- Fix applied; regression execution pending
  - Follow-up prompt: Review deferred unit nested-import-resource-limit and close its stated proof gap.
