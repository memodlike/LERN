# LERN Import UX E2E audit report

- **Local implementation inspected:** ImportView, ImportGuidanceView, Importers, Persistence, Library/Theme surfaces, fixtures, core/app/UI tests, QA/design docs and simulator runner.
- **Accepted visual evidence:** 20 inspected iPhone 17 Pro Max portrait screenshots in `screenshots/accepted`.
- **Formats visually exercised:** TXT lines/paragraphs, Markdown, CSV comma/semicolon/ambiguous, TSV, JSON, JSONL, duplicate, long-entry shortening, empty, malformed CSV and invalid UTF-8, plus multi-file preview.
- **Figma:** https://www.figma.com/design/C9qgxr8nVRGg48j33w7x9J — 11 editable iPhone frames with adjacent uploaded references on Import Flow. The audit pages/tokens are in the file.
- **Figma limitation:** the Starter plan allows three pages, one variable mode and hit its MCP call cap after the first 11 frames. The remaining 9 accepted screenshots have explicit frame blockers in `coverage.md`.
- **Uncovered visual states:** native Files picker, stable processing/cancel, CSV override controls, merge/split options, destination picker gating, commit success and post-import marker. The underlying parser/store branches are covered by the existing test suite; no production behavior was changed for capture.
