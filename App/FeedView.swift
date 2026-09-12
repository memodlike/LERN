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
                VStack {
                    Spacer()
                    Text(notice)
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .lernGlass(shape: RoundedRectangle(cornerRadius: 16, style: .continuous), appearance: glassAppearance, tint: glassTint, intensity: state.preferences.glassIntensity, elevation: .medium)
                        .padding(.bottom, 96)
                }
                .task(id: notice) {
                    AccessibilityNotification.Announcement(notice).post()
                    try? await Task.sleep(for: .seconds(3))
                    state.notice = nil
                }
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

    private var glassAppearance: GlassAppearance { GlassAppearance(rawValue: state.preferences.glassAppearance) ?? .automatic }
    private var glassTint: Color { Color(hex: state.preferences.glassTintColor.isEmpty ? state.activeTheme.secondary : state.preferences.glassTintColor) }

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 8) {
                LogoMark(
                    variant: LogoVariant(rawValue: state.preferences.logoVariantID) ?? .fallback,
                    primary: Color(hex: state.preferences.logoPrimaryColor.isEmpty ? state.activeTheme.foreground : state.preferences.logoPrimaryColor),
                    accent: Color(hex: state.preferences.logoAccentColor.isEmpty ? state.activeTheme.secondary : state.preferences.logoAccentColor)
                )
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)

                Text(Product.name)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .tracking(4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .lernGlassCapsule(appearance: glassAppearance, tint: glassTint, intensity: state.preferences.glassIntensity, elevation: .low)
            .accessibilityLabel(Product.name)

            Spacer(minLength: 16)

            HStack(spacing: 4) {
                Button { state.sheet = .streak } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text("\(state.preferences.streak.current)")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .padding(.horizontal, 10)
                    .frame(minWidth: 44, minHeight: 38)
                    .contentShape(Capsule())
                }
                .accessibilityLabel("Streak: \(state.preferences.streak.current) days")
                .accessibilityHint("Opens streak details")

                Divider().frame(height: 16).opacity(0.2)

                Button { state.sheet = .profile } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 19, weight: .medium))
                        .frame(width: 38, height: 38)
                        .contentShape(Circle())
                }
                .accessibilityLabel("Profile")
                .accessibilityHint("Opens your space and settings")
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .lernGlassCapsule(appearance: glassAppearance, tint: glassTint, intensity: state.preferences.glassIntensity, elevation: .low)
        }
    }

    private func quote(_ entry: EntryValue) -> some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 28) {
                    Text(entry.draft.text)
                        .font(.system(size: min(quoteSize, entry.draft.text.count > 400 ? quoteSize * 0.72 : quoteSize), weight: state.activeTheme.fontWeight, design: state.activeTheme.design))
                        .multilineTextAlignment(state.activeTheme.textAlignment)
                        .lineSpacing(max(6, quoteSize * 0.2))
                        .fixedSize(horizontal: false, vertical: true)
                        .shadow(color: .black.opacity(state.activeTheme.hasLowContrast ? 0.45 : 0.12), radius: 8, y: 2)
                        .accessibilityIdentifier("feed.quote")

                    if !entry.draft.author.isEmpty || !entry.draft.source.isEmpty {
                        VStack(spacing: 4) {
                            if !entry.draft.author.isEmpty {
                                Text("— " + entry.draft.author)
                                    .font(.callout.weight(.medium))
                                    .opacity(0.95)
                            }
                            if !entry.draft.source.isEmpty {
                                Text(entry.draft.source)
                                    .font(.caption)
                                    .opacity(0.85)
                            }
                        }
                    }
                }
                .frame(maxWidth: 680, minHeight: max(0, geometry.size.height - 32))
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .simultaneousGesture(DragGesture(minimumDistance: 40).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height), abs(value.translation.width) > 60 else { return }
                if value.translation.width < 0 { advance() } else { state.previous(); haptic() }
            })
            .contextMenu { contextActions(entry) }
        }
    }

    private func actions(_ entry: EntryValue) -> some View {
        HStack(spacing: 10) {
            Button { state.previous(); haptic() } label: {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(state.feedPosition <= 0)
            .opacity(state.feedPosition <= 0 ? 0.3 : 1.0)
            .accessibilityLabel("Previous thought")

            Divider().frame(height: 20).opacity(0.25)

            FeedFavoriteButton(entry: entry, foregroundColor: state.activeTheme.textColor) {
                await state.flag(entry, "favorite", !entry.favorite)
            }

            Button { state.sheet = .share } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 19, weight: .medium))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Share")

            Menu {
                contextActions(entry)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 19, weight: .medium))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More actions")

            Divider().frame(height: 20).opacity(0.25)

            Button { advance() } label: {
                Image(systemName: "chevron.forward")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(state.busy)
            .accessibilityIdentifier("feed.next")
            .accessibilityLabel("Next thought")
        }
        .foregroundStyle(state.activeTheme.textColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .lernGlassCapsule(appearance: glassAppearance, tint: glassTint, intensity: state.preferences.glassIntensity, elevation: .medium)
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 12) {
            Button { state.sheet = .library } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: state.activeTheme.secondary))

                    Text(sourceTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .opacity(0.65)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .contentShape(Capsule())
            }
            .lernGlassCapsule(appearance: glassAppearance, tint: glassTint, intensity: state.preferences.glassIntensity, elevation: .low)
            .accessibilityIdentifier("feed.library")
            .accessibilityLabel("Current source: \(sourceTitle). Tap to change source.")

            Spacer(minLength: 8)

            HStack(spacing: 2) {
                Button { state.sheet = .reminders } label: {
                    Image(systemName: "bell")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Reminders")

                Divider().frame(height: 16).opacity(0.2)

                Button { state.sheet = .themes } label: {
                    Image(systemName: "paintpalette")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Themes")
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .lernGlassCapsule(appearance: glassAppearance, tint: glassTint, intensity: state.preferences.glassIntensity, elevation: .low)
        }
        .padding(.top, 12)
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
