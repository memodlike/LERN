import SwiftUI
import LERNCore

struct FeedView: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var mutePhrase = ""
    @State private var showMute = false
    @State private var editingEntry: EntryValue?
    @ScaledMetric(relativeTo: .largeTitle) private var quoteSize = 34
    var body: some View {
        @Bindable var state = state
        ZStack {
            ThemeBackground(theme: state.activeTheme)
            VStack(spacing: 12) {
                header
                if let entry = state.current {
                    quote(entry).id(entry.id).transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .offset(y: 18)), removal: .opacity))
                    actions(entry)
                } else if state.loaded { empty }
                else { Spacer(); ProgressView().tint(state.activeTheme.textColor); Spacer() }
                footer
            }.padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 16)
            if let notice = state.notice {
                VStack { Spacer(); Text(notice).font(.callout).padding().background(.regularMaterial, in: Capsule()).padding(.bottom, 100) }
                    .task(id: notice) { try? await Task.sleep(for: .seconds(3)); state.notice = nil }
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .foregroundStyle(state.activeTheme.textColor)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: state.current?.id)
        .sheet(item: $state.sheet) { sheet in
            NavigationStack {
                switch sheet {
                case .library: LibraryView()
                case .themes: ThemesView()
                case .profile: ProfileView()
                case .reminders: RemindersView()
                case .importFiles: ImportView()
                case .compose: EntryEditor()
                case .share: if let entry = state.current { ShareImageView(entry: entry) }
                case .collections: if let entry = state.current { CollectionPicker(entry: entry) }
                case .streak: StreakView()
                }
            }.environment(state).tint(Color(hex: "276A99")).foregroundStyle(.primary)
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingEntry) { entry in NavigationStack { EntryEditor(existing: entry) }.environment(state) }
        .alert("Mute a word or phrase", isPresented: $showMute) {
            TextField("Word or phrase", text: $mutePhrase)
            Button("Cancel", role: .cancel) {}
            Button("Mute") { let phrase = mutePhrase.trimmingCharacters(in: .whitespacesAndNewlines); if !phrase.isEmpty { state.preferences.mutedWords.append(phrase); Task { await state.savePreferences(); state.feedPast = []; state.feedPosition = -1; await state.next(); await state.contentChanged() } } }
        } message: { Text("Matching entries will be hidden from the feed, reminders, widgets and Watch.") }
    }
    private var header: some View {
        HStack {
            Text(Product.name).font(.system(size: 20, weight: .semibold, design: .rounded)).tracking(5).accessibilityLabel(Product.name)
            Spacer()
            Button { state.sheet = .streak } label: { Label("\(state.preferences.streak.current)", systemImage: "flame").font(.system(size: 16)).padding(.horizontal, 12).frame(minHeight: 44) }.accessibilityLabel("Streak: \(state.preferences.streak.current) days")
            icon("Profile", "person.crop.circle") { state.sheet = .profile }
        }
    }
    private func quote(_ entry: EntryValue) -> some View {
        return GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    Text(entry.draft.text)
                        .font(.system(size: min(quoteSize, entry.draft.text.count > 400 ? quoteSize * 0.72 : quoteSize), weight: state.activeTheme.fontWeight, design: state.activeTheme.design))
                        .multilineTextAlignment(state.activeTheme.textAlignment).lineSpacing(7).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("feed.quote")
                    if !entry.draft.author.isEmpty { Text(entry.draft.author).font(.subheadline).opacity(0.85) }
                    if !entry.draft.source.isEmpty { Text(entry.draft.source).font(.caption).opacity(0.85) }
                }.frame(maxWidth: 680, minHeight: max(0, geometry.size.height - 32)).padding(.vertical, 16).frame(maxWidth: .infinity)
            }.scrollIndicators(.hidden)
            .simultaneousGesture(DragGesture(minimumDistance: 40).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height), abs(value.translation.width) > 60 else { return }
                if value.translation.width < 0 { advance() } else { state.previous(); haptic() }
            })
            .contextMenu { contextActions(entry) }
        }
    }
    private func actions(_ entry: EntryValue) -> some View {
        HStack(spacing: 20) {
            icon("Previous", "chevron.left") { state.previous(); haptic() }.disabled(state.feedPosition <= 0).opacity(state.feedPosition <= 0 ? 0.35 : 1)
            Spacer()
            icon(entry.favorite ? "Remove favorite" : "Favorite", entry.favorite ? "heart.fill" : "heart") { Task { await state.flag(entry, "favorite", !entry.favorite) }; haptic() }
                .accessibilityIdentifier("feed.favorite")
            icon("Share", "square.and.arrow.up") { state.sheet = .share }
            Menu { contextActions(entry) } label: { Image(systemName: "ellipsis").font(.system(size: 22)).frame(width: 48, height: 48) }.accessibilityLabel("More actions")
            Spacer()
            icon("Next", "chevron.right") { advance() }.disabled(state.busy).accessibilityIdentifier("feed.next")
        }.font(.title3)
    }
    private var footer: some View {
        HStack {
            Button { state.sheet = .library } label: {
                Label(sourceTitle, systemImage: "square.stack").font(.subheadline.weight(.medium)).dynamicTypeSize(...DynamicTypeSize.xxxLarge).lineLimit(1).frame(minHeight: 48)
            }.accessibilityIdentifier("feed.library")
            Spacer(minLength: 16)
            icon("Reminders", "bell") { state.sheet = .reminders }
            icon("Themes", "paintpalette") { state.sheet = .themes }
        }.padding(.top, 12)
    }
    private var sourceTitle: String {
        if state.preferences.feedSource.favoritesOnly { return String(localized: "Favorites") }
        if state.preferences.feedSource.myContentOnly { return String(localized: "My Content") }
        if let id = state.preferences.feedSource.topicIDs.first { return state.topics.first { $0.id == id }?.name ?? String(localized: "Topics") }
        return String(localized: "Your library")
    }
    private var empty: some View {
        let compact = verticalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize
        return GeometryReader { geometry in
            ScrollView {
                VStack(spacing: compact ? 14 : 24) {
                    Spacer(minLength: compact ? 0 : 12)
                    if !compact { Image(systemName: "text.book.closed").font(.system(size: 48, weight: .ultraLight)) }
                    Text(state.total == 0 ? "Keep your own words close." : "No matching entries")
                        .font(.system(.largeTitle, design: .rounded)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    Text(state.total == 0 ? (compact ? "Import a file or write a thought to begin." : "Bring a text file, a collection of ideas, or a thought you want to return to.") : "Choose another topic or review muted content in your profile.")
                        .font(.body).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).opacity(0.85)
                    Button("Import files") { state.sheet = .importFiles }.buttonStyle(.borderedProminent).tint(state.activeTheme.textColor).foregroundStyle(Color(hex: state.activeTheme.background)).controlSize(.large).fixedSize(horizontal: false, vertical: true)
                    Button("Write a thought") { state.sheet = .compose }.frame(minHeight: 44).fixedSize(horizontal: false, vertical: true)
                    if state.total == 0 { Button("Try original sample thoughts") { Task { await samples() } }.font(.footnote).frame(minHeight: 44).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true) }
                    Spacer(minLength: 12)
                    Text("Private. Offline. Yours.").font(.footnote).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).opacity(0.8)
                }.frame(maxWidth: 420, minHeight: compact ? 0 : geometry.size.height).frame(maxWidth: .infinity)
            }.scrollIndicators(.hidden)
        }
    }
    @ViewBuilder private func contextActions(_ entry: EntryValue) -> some View {
        Button("Add to collection", systemImage: "folder.badge.plus") { state.sheet = .collections }
        Button("Save or share image", systemImage: "photo") { state.sheet = .share }
        Button("Copy text", systemImage: "doc.on.doc") { UIPasteboard.general.string = entry.draft.text; state.notice = String(localized: "Copied") }
        Button("Edit", systemImage: "pencil") { editingEntry = entry }
        Button("Dislike", systemImage: "hand.thumbsdown") { Task { await state.flag(entry, "disliked", true) } }
        Button("Mute this entry", systemImage: "speaker.slash") { Task { await state.flag(entry, "muted", true) } }
        Button("Mute a word or phrase", systemImage: "text.badge.minus") { showMute = true }
    }
    private func icon(_ label: LocalizedStringKey, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 22)).frame(width: 44, height: 48).contentShape(Rectangle()) }.accessibilityLabel(label)
    }
    private func advance() { Task { await state.next() }; haptic() }
    private func haptic() { if state.preferences.haptics { UIImpactFeedbackGenerator(style: .soft).impactOccurred() } }
    private func samples() async {
        let drafts = ["A small step still changes where you stand.", "Leave enough quiet to hear your own thinking.", "You can begin before you feel ready.", "Make room for the work that matters to you.", "Progress can be gentle and still be real.", "Let today be a place to practice, not a test to pass."].map { EntryDraft(text: $0, source: "Original LERN sample") }
        do { _ = try await state.store.importEntries(ImportPreview(name: "First thoughts", format: "sample", entries: drafts, duplicates: 0, malformed: 0, issues: [])); await state.contentChanged(); await state.next() }
        catch { state.error = error.localizedDescription }
    }
}
