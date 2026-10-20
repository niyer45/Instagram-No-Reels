import UIKit
import Combine

/// The signed-in account as observed from Instagram's own page: the username (for the
/// Profile tab route) and avatar (for its icon). Never touches credentials or cookies.
///
/// The avatar image is cached on disk so the Profile tab shows it at launch, before any page
/// reports it and after its signed CDN URL has expired; `clear()` (Sign out) removes it.
@MainActor
final class AccountStore: ObservableObject {
    /// What the shell currently believes about the web session.
    enum Session { case unknown, signedIn, signedOut }

    private static let usernameKey = "account.username.v1"
    private static let avatarKey = "account.avatarURL.v1"

    @Published private(set) var username: String?
    @Published private(set) var avatar: UIImage?
    @Published private(set) var session: Session = .unknown
    private var avatarURL: URL?
    private var avatarTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private let imageSession = URLSession(configuration: .ephemeral)
    private let avatarFile: URL?

    init(defaults: UserDefaults = .standard, cacheDirectory: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first) {
        self.defaults = defaults
        avatarFile = cacheDirectory?.appendingPathComponent("account-avatar.v1")
        username = defaults.string(forKey: Self.usernameKey).flatMap(FollowingImport.username)
        if username != nil, let file = avatarFile, let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
            avatar = image
        }
        if let raw = defaults.string(forKey: Self.avatarKey), let url = URL(string: raw), BridgeMessage.isAvatarHost(url) {
            loadAvatar(url)
        }
    }

    var profileURL: URL? { username.flatMap(Self.profileURL(for:)) }

    static func profileURL(for username: String) -> URL? {
        URL(string: "https://www.instagram.com/\(username)/")
    }

    func update(username: String, avatarURL url: URL) {
        session = .signedIn
        if self.username != username {
            self.username = username
            defaults.set(username, forKey: Self.usernameKey)
        }
        if avatarURL != url {
            defaults.set(url.absoluteString, forKey: Self.avatarKey)
            loadAvatar(url)
        }
    }

    func markSignedIn() { if session != .signedIn { session = .signedIn } }
    func markSignedOut() { if session != .signedOut { session = .signedOut } }

    func clear() {
        avatarTask?.cancel()
        username = nil
        avatar = nil
        avatarURL = nil
        session = .signedOut
        defaults.removeObject(forKey: Self.usernameKey)
        defaults.removeObject(forKey: Self.avatarKey)
        if let file = avatarFile { try? FileManager.default.removeItem(at: file) }
    }

    private func loadAvatar(_ url: URL) {
        avatarURL = url
        avatarTask?.cancel()
        avatarTask = Task { [weak self, imageSession] in
            guard let (data, response) = try? await imageSession.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 2 * 1024 * 1024,
                  let image = UIImage(data: data), !Task.isCancelled else { return }
            guard let self, self.avatarURL == url else { return }
            self.avatar = image
            if let file = self.avatarFile { try? data.write(to: file, options: [.atomic]) }
        }
    }
}
