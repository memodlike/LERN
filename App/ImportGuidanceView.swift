import SwiftUI
import UIKit

struct ImportFormatHelpView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("Supported files") {
                    Label("Markdown (.md)", systemImage: "text.document")
                    Label("Plain text (.txt)", systemImage: "doc.plaintext")
                    Label("CSV and TSV", systemImage: "tablecells")
                    Label("JSON and JSONL", systemImage: "curlybraces")
                }
                Section("How LERN reads them") {
                    Text("Markdown headings make sections. Markdown lists make entries. Fenced code stays literal and never becomes a heading.")
                    Text("TXT can use one entry per line or blank-separated paragraphs. CSV accepts comma, semicolon, or tab delimiters and recognizes text, quote, body, content, author, source, tags, section, and category columns.")
                    Text("Imported text stays on this device. Review the preview before importing.")
                }
            }
            .navigationTitle("Import formats")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct ImportAIHelperView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    private var prompt: String {
        state.preferences.language == "ru" ? """
Собери локальную библиотеку LERN из моих материалов. Верни только Markdown в UTF-8: заголовки #–###### для разделов, один элемент списка на цитату, автора после длинного тире, теги через запятую. Не выдумывай цитаты и не добавляй ссылки, которых нет в исходном тексте. Сохрани дословный текст, дубликаты убери.
""" : """
Create a LERN-ready local library from my source material. Return UTF-8 Markdown only: #–###### headings for sections, one list item per quote, author after an em dash, and comma-separated tags. Do not invent quotes or sources. Preserve original wording and remove duplicates.
"""
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Copy this prompt") { Text(prompt).textSelection(.enabled).font(.footnote) }
                Section { Button(copied ? "Copied" : "Copy prompt", systemImage: copied ? "checkmark" : "doc.on.doc") { UIPasteboard.general.string = prompt; copied = true } }
                Section { Text("Paste the response into a .md file, then choose it from Import files. LERN does not send your content to an AI service.").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("Create with AI")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
