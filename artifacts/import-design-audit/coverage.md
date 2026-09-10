# LERN Import UX coverage

Capture device: iPhone 17 Pro Max simulator, portrait (440 × 956 pt / 1320 × 2868 px), English. Capture method: temporary DEBUG-only XCTest seam injecting bytes into the existing `ImportView.read → ImportService.preview → LibraryStore` path. The seam and test were restored before this bundle was written.

| ID | User step | Trigger / fixture | Expected state | Actual result | Screenshot | Figma frame | Status |
|---|---|---|---|---|---|---|---|
| 001 | Enter Import | Launch, no files | Initial form | Matched | 001-import-empty.png | 3:2 | PASS |
| 002 | Format help | Tap Format help | Supported-format guidance | Matched | 002-format-help.png | 3:20 | PASS |
| 003 | AI helper empty | Open helper | Empty topic guidance | Matched | 003-ai-helper-empty.png | 3:41 | PASS |
| 004 | AI helper topic | Topic `Leadership` | Generated localized prompt | Matched | 004-ai-helper-filled.png | 3:59 | PASS |
| 005 | AI copy | Tap Copy prompt | Copy confirmation | Matched | 005-ai-helper-copied.png | 3:77 | PASS |
| 010 | TXT lines | valid/lines.txt | Auto layout: Lines | Matched | 010-preview-txt-lines.png | 3:95 | PASS |
| 011 | TXT paragraphs | valid/paragraphs.txt | Auto layout: Paragraphs | Matched | 011-preview-txt-paragraphs.png | 3:116 | PASS |
| 012 | Markdown | valid/thoughts.md | Sections and valid entries | Matched | 012-preview-markdown.png | 3:137 | PASS |
| 020 | CSV comma | valid/thoughts.csv | Comma, header, aliases | Matched | 020-preview-csv-comma.png | 3:158 | PASS |
| 021 | CSV semicolon | valid/thoughts-semicolon.csv | Semicolon detected | Matched | 021-preview-csv-semicolon.png | 3:179 | PASS |
| 022 | CSV ambiguity | edge/csv-headerless-alias.csv | Needs delimiter/header choice | Matched | 022-preview-csv-ambiguous.png | 3:200 | PASS |
| 023 | TSV | valid/thoughts.tsv | TSV preview | Matched | 023-preview-tsv.png | — | BLOCKED: Figma MCP limit |
| 030 | JSON | valid/thoughts.json | JSON preview and metadata | Matched | 030-preview-json.png | — | BLOCKED: Figma MCP limit |
| 031 | JSONL | valid/thoughts.jsonl | JSONL preview | Matched | 031-preview-jsonl.png | — | BLOCKED: Figma MCP limit |
| 032 | Duplicate normalization | deterministic duplicate bytes | Duplicate count | Matched | 032-preview-duplicates.png | — | BLOCKED: Figma MCP limit |
| 033 | Long entry | edge/long-section.md | Notification-shortening note | Matched | 033-preview-notification-shortening.png | — | BLOCKED: Figma MCP limit |
| 050 | Invalid encoding | deterministic invalid UTF-8 | Needs attention | Matched | 050-error-invalid-encoding.png | — | BLOCKED: Figma MCP limit |
| 051 | Malformed CSV | edge/csv-ragged.csv | Needs attention | Matched | 051-error-malformed-csv.png | — | BLOCKED: Figma MCP limit |
| 052 | Empty input | deterministic whitespace bytes | Needs attention | Matched | 052-error-empty.png | — | BLOCKED: Figma MCP limit |
| 060 | Multi-file preview | TXT + JSON in one selection | Both cards and options | Matched | 060-multi-file-options.png | — | BLOCKED: Figma MCP limit |
| C01 | System selection | Choose files | Native Files picker | Not automated; platform-owned UI | — | — | BLOCKED |
| C02 | Progress/cancel | File reading | Stable processing/cancel state | Processing label not discoverable before stable render | Rejected | — | BLOCKED |
| C03 | CSV controls | Preview | Manual delimiter and header pickers | Parser branch proven by core tests; control not captured | — | — | BLOCKED |
| C04 | Multi-file options | Multi preview | Merge/split-section toggles | Preview captured; controls not exposed deterministically by harness | — | — | BLOCKED |
| C05 | Destination actions | Preview | New / merge / replace, disabled/enabled picker | Store path covered by tests; sheet closed before commit in harness | — | — | BLOCKED |
| C06 | Commit/success | Import entries | Completion, Start reading, Done | Store persistence covered by tests; no accepted UI frame | — | — | BLOCKED |
| C07 | Post-import result | Library/feed | Unique fixture marker visible | Store persistence covered; no accepted UI frame | — | — | BLOCKED |
| D01 | BOM/CRLF/whitespace | core fixtures/tests | Normalized parsing | Current core suite evidence | — | — | PASS (non-visual) |
| D02 | Metadata | JSON/MD fixtures | text/content, author, source, tags, section | Parser/store tests; only author is row-visible | — | — | PASS (non-visual) |
| D03 | Limits | core boundary tests | size, entry, capacity errors | Current core suite evidence | — | — | PASS (non-visual) |
| T01 | Themes | ImportView + ThemeView inspection | Import visual delta only if implemented | No theme binding on Import system Form | 001-import-empty.png | 3:2 | PASS: no visual delta |
