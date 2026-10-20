import SwiftUI
import UniformTypeIdentifiers

/// The Content filters sheet: filter status, the optional following-list import, and account
/// actions. Presented from the web settings-menu entry (`openControls`) or the Profile menu.
struct ContentFilterSettingsView: View {
    @ObservedObject var status: FilterStatus
    @ObservedObject var following: FollowingStore
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

    var body: some View {
        NavigationStack {
            List {
                Section("Content") {
                    Label("Reels disabled", systemImage: "video.slash")
                    Label("Ads and suggested posts hidden", systemImage: "line.3.horizontal.decrease")
                    Label("Posts require followed-account evidence", systemImage: "person.crop.circle.badge.checkmark")
                }
                Section {
                    Text(status.message).font(.subheadline)
                    LabeledContent("Visible posts", value: "\(status.shown)")
                    LabeledContent("Hidden posts", value: "\(status.hidden)")
                    LabeledContent("Post records recognized", value: "\(status.metadataRecords)")
                    Button("Reload Home") { actions.reload() }
                } header: { Text("Feed status") } footer: {
                    Text("Instagram’s page can provide follow status for its loaded posts. When it does not, those posts stay hidden until you import your following list. The rest of Instagram’s interface stays available.")
                }
                Section {
                    LabeledContent("Imported accounts", value: "\(following.snapshot.handles.count)")
                    if !following.snapshot.handles.isEmpty {
                        LabeledContent("Imported", value: following.snapshot.importedAt.formatted(date: .abbreviated, time: .omitted))
                    }
                    Button("Import following.json") { importing = true }
                    if !following.snapshot.handles.isEmpty {
                        Button("Remove imported list", role: .destructive) { actions.clearImport() }
                    }
                } header: { Text("Optional following-list fallback") } footer: {
                    Text("Use the JSON following list from your Instagram information export. Reimport it after following or unfollowing accounts. Fresh negative follow status from Instagram takes priority over an older imported list.")
                }
                Section("Account") {
                    Button("Sign in to Instagram") { actions.signIn() }
                    Button("Sign out on this device", role: .destructive) { confirmingSignOut = true }
                }
            }
            .navigationTitle("Content filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { actions.dismiss() } } }
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
}
