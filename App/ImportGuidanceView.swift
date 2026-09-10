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
                    Text("Markdown headings make sections. Markdown lists make entries. Backtick and tilde fenced code stays literal and never becomes a heading.")
                    Text("TXT can use one entry per line or blank-separated paragraphs. CSV and TSV recognize text, quote, body, content, author, source, tags, section, and category columns. When detection is ambiguous, choose the delimiter and header mode in the preview.")
                    Text("Matching entries use normalized text, author and source. Tags and sections do not create a separate entry identity.")
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
    @State private var topic = ""
    @State private var copied = false
    private var isRussian: Bool {
        state.preferences.language == "ru" || (state.preferences.language == "system" && Locale.current.language.languageCode?.identifier == "ru")
    }
    private var prompt: String {
        let cleanTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        return isRussian ? """
Создай личную библиотеку коротких мыслей для LERN на тему «\(cleanTopic)».

Пиши простым, понятным языком. Сделай 20–30 коротких мыслей, которые помогают изучать тему. Раздели их на несколько понятных тем с заголовками #–######. Под каждым заголовком ставь одну мысль в строке списка: - Текст мысли. Не выдумывай авторов, цитаты известных людей или ссылки. Не повторяй мысли. Верни только Markdown в UTF-8, без вступления и пояснений.
""" : """
Create a personal LERN library of short thoughts about “\(cleanTopic)”.

Use clear, everyday language. Write 20–30 short thoughts that help someone learn the topic. Group them under simple #–###### headings. Under each heading, put one thought on each list line: - Thought text. Do not invent authors, famous quotes, or links. Do not repeat ideas. Return only UTF-8 Markdown, with no introduction or explanation.
"""
    }
    var body: some View {
        NavigationStack {
            Form {
                Section(isRussian ? "Что вы хотите изучить?" : "What do you want to explore?") {
                    TextField(isRussian ? "Например: управление продуктом" : "For example: product management", text: $topic, axis: .vertical)
                        .lineLimit(1...3)
                    Text(isRussian ? "Тема станет основой для готового промпта." : "Your topic becomes the basis of the ready-to-copy prompt.").font(.caption).foregroundStyle(.secondary)
                }
                if !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section(isRussian ? "Готовый промпт" : "Ready prompt") { Text(prompt).textSelection(.enabled).font(.footnote) }
                }
                Section { Button(copied ? (isRussian ? "Скопировано" : "Copied") : (isRussian ? "Скопировать промпт" : "Copy prompt"), systemImage: copied ? "checkmark" : "doc.on.doc") { UIPasteboard.general.string = prompt; copied = true }.disabled(topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                Section { Text(isRussian ? "Вставьте ответ AI в файл .md, затем выберите его в разделе импорта. LERN не отправляет ваши данные в AI-сервис." : "Paste the AI response into a .md file, then select it from Import files. LERN does not send your content to an AI service.").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle(isRussian ? "Создать с AI" : "Create with AI")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
