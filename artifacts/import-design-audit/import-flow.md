# Import flow — implementation record

## Structural source of truth

`App/ImportView.swift` owns file selection, preview, options, commit actions and completion. Bytes flow through `read` into `ImportService.preview` in `Sources/LERNCore/Importers.swift`; importing commits through `LibraryStore` / `Persistence.swift`. The UI supports `txt`, `md`, `markdown`, `csv`, `tsv`, `json`, and `jsonl`.

## State map

1. **Initial** — privacy statement, Choose files, AI helper, Format help.
2. **Help / AI sheets** — format documentation; topic-specific prompt generation and clipboard confirmation.
3. **Preview** — one card per selected file. It reports detected format, valid entries, duplicates, malformed records, layout/delimiter/header, sections, shortening note, samples and issues.
4. **Options** — merge files; split into section/category topics; CSV delimiter/header overrides; New, Merge and Replace action; destination-topic gating.
5. **Commit** — import entries, then success summary, Start reading and Done.
6. **Attention** — empty, invalid encoding, malformed/partial records, unsupported input and capacity/size errors surface through the preview/attention UI.

## Data-quality evidence

The parser normalizes UTF-8 BOM, line endings and whitespace. TXT auto-detects lines or paragraphs; Markdown recognizes headings, lists and fenced code; CSV/TSV detects delimiters, headers and aliases; JSON/JSONL accepts text/content aliases and metadata. Normalized duplicates, malformed records, section/category splitting, notification shortening and persistence actions are asserted by the existing core/store tests. Visual status is in `coverage.md`; non-visual metadata and boundaries are deliberately labeled as such.

## Identity, themes and localization

The Import surface is a semantic SwiftUI `Form`. `ImportView` does not bind to LERN theme tokens/backgrounds, so the implemented reader themes produce no material visual delta there. English was the default capture language; no alternative locale/large-text state was added because the source review found no distinct Import layout branch.
