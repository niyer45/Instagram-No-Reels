import SwiftUI
import UniformTypeIdentifiers

/// The Content filters sheet, styled like Instagram's settings: inset grouped rows on Instagram's
/// surface, regular-weight outline SF Symbols, sentence-case grey section headers. Shows filter
/// status, the optional following-list import and account actions. Presented from the web
/// settings-menu entry (`openControls`) or the Profile menu.
struct ContentFilterSettingsView: View {
    @ObservedObject var status: FilterStatus
    @ObservedObject var following: FollowingStore
    @ObservedObject var messages: MessageNotifications
    let actions: Actions

    /// Shell actions the sheet triggers; each dismisses the sheet first where appropriate.
    struct Actions {
        let reload: () -> Void
        let importFile: (URL) -> Void
        let clearImport: () -> Void
        let signIn: () -> Void
        let signOut: () -> Void
        let dismiss: () -> Void
    }

    @State private var importing = false
    @State private var confirmingSignOut = false
    @Environment(\.colorScheme) private var colorScheme

    /// Instagram's surfaces: #0C1014 / white page, slightly raised grouped rows.
    private var pageBackground: Color { colorScheme == .dark ? Color(red: 12 / 255, green: 16 / 255, blue: 20 / 255) : Color(white: 0.97) }
    private var rowBackground: Color { colorScheme == .dark ? Color(red: 37 / 255, green: 41 / 255, blue: 46 / 255) : .white }
    private static let secondary = Color(white: 168 / 255)
    private static let link = Color(red: 0, green: 149 / 255, blue: 246 / 255)
    private static let destructive = Color(red: 237 / 255, green: 73 / 255, blue: 86 / 255)

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row("Reels disabled", "film")
                    row("Ads and suggested posts hidden", "eye.slash")
                    row("Posts require followed-account evidence", "person.crop.circle.badge.checkmark")
                } header: { header("Content") }

                Section {
                    Text(status.message)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                        .listRowBackground(rowBackground)
                    value("Visible posts", "\(status.shown)", "photo.on.rectangle")
                    value("Hidden posts", "\(status.hidden)", "rectangle.slash")
                    value("Post records recognized", "\(status.metadataRecords)", "doc.text.magnifyingglass")
                    button("Reload Home", "arrow.clockwise", color: Self.link) { actions.reload() }
                } header: { header("Feed status") } footer: {
                    footer("Instagram’s page can provide follow status for its loaded posts. When it does not, those posts stay hidden until you import your following list. The rest of Instagram’s interface stays available.")
                }

                Section {
                    value("Imported accounts", "\(following.snapshot.handles.count)", "person.2")
                    if !following.snapshot.handles.isEmpty {
                        value("Imported", following.snapshot.importedAt.formatted(date: .abbreviated, time: .omitted), "calendar")
                    }
                    button("Import following.json", "square.and.arrow.down", color: Self.link) { importing = true }
                    if !following.snapshot.handles.isEmpty {
                        button("Remove imported list", "trash", color: Self.destructive) { actions.clearImport() }
                    }
                } header: { header("Optional following-list fallback") } footer: {
                    footer("Use the JSON following list from your Instagram information export. Reimport it after following or unfollowing accounts. Fresh negative follow status from Instagram takes priority over an older imported list.")
                }

                Section {
                    Toggle(isOn: Binding(get: { messages.enabled }, set: { on in Task { await messages.setEnabled(on) } })) {
                        HStack(spacing: 12) {
                            icon("bell")
                            Text("Message notifications").font(.system(size: 15))
                        }
                    }
                    .tint(Self.link)
                    .listRowBackground(rowBackground)
                } header: { header("Message notifications") } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        footer("iOS checks for new messages in the background every so often, usually within an hour. Notifications are not instant.")
                        if messages.permissionDenied {
                            footer("Notifications are turned off for this app. Allow them in the Settings app, then try again.")
                        }
                    }
                }

                Section {
                    button("Sign in to Instagram", "person.crop.circle", color: Self.link) { actions.signIn() }
                    button("Sign out on this device", "rectangle.portrait.and.arrow.right", color: Self.destructive) { confirmingSignOut = true }
                } header: { header("Account") }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(pageBackground)
            .environment(\.defaultMinListRowHeight, 48)
            .navigationTitle("Content filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(pageBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { actions.dismiss() }.fontWeight(.semibold).tint(.primary)
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first { actions.importFile(url) }
            }
            .confirmationDialog("Sign out of Instagram on this device?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { actions.signOut() }
            } message: {
                Text("This clears Instagram’s website data stored by this app.")
            }
        }
    }

    // MARK: Rows in Instagram's settings style

    private func icon(_ symbol: String, color: Color = .primary) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 20, weight: .regular))
            .foregroundStyle(color)
            .frame(width: 28)
    }

    private func row(_ title: String, _ symbol: String) -> some View {
        HStack(spacing: 12) {
            icon(symbol)
            Text(title).font(.system(size: 15))
        }
        .listRowBackground(rowBackground)
    }

    private func value(_ title: String, _ value: String, _ symbol: String) -> some View {
        HStack(spacing: 12) {
            icon(symbol)
            Text(title).font(.system(size: 15))
            Spacer()
            Text(value).font(.system(size: 15)).foregroundStyle(Self.secondary).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .listRowBackground(rowBackground)
    }

    private func button(_ title: String, _ symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                icon(symbol, color: color)
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(color)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(rowBackground)
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Self.secondary)
            .textCase(nil)
    }

    private func footer(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(Self.secondary)
    }
}
