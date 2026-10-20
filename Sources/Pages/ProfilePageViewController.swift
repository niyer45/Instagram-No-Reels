import UIKit

/// The Profile tab root (own profile). Replaces the generic page header with Instagram's own-profile
/// header (`ProfileHeaderView`): username with the account-switcher chevron, New post and the menu,
/// which opens a native action sheet (Settings and activity, Content filters, Sign out). The header
/// hides over login content like other tab roots. The profile itself is skinned in the page by kind
/// (NativeSkin.css `Profile`), so pushed profiles look the same.
@MainActor
final class ProfilePageViewController: WebPageViewController {
    /// m-web's settings entry. `/accounts/settings/` also exists signed in (it redirects to login
    /// when signed out) but its contents are unverified, so the known Edit profile page is used.
    static let settingsURL = URL(string: "https://www.instagram.com/accounts/edit/")
    private let profileHeader = ProfileHeaderView()

    override func installHeader() {
        guard placement == .tabRoot(.profile) else { super.installHeader(); return }
        profileHeader.onSwitchAccount = { [weak self] in self?.switchAccount() }
        profileHeader.onCreate = { [weak self] in self?.environment.router.alert("Creating posts isn’t available in this app.") }
        profileHeader.onMenu = { [weak self] in self?.showMenu() }
        view.addSubview(profileHeader)
        updateTitle()
    }

    override var headerHeight: CGFloat {
        guard placement == .tabRoot(.profile) else { return super.headerHeight }
        return isLoginContent ? 0 : ProfileHeaderView.height
    }

    override func layoutPage() {
        super.layoutPage()
        guard profileHeader.superview != nil else { return }
        profileHeader.frame = CGRect(x: 0, y: view.safeAreaInsets.top, width: view.bounds.width, height: ProfileHeaderView.height)
        profileHeader.isHidden = headerHeight == 0
        view.bringSubviewToFront(profileHeader)
    }

    override func applyTheme() {
        super.applyTheme()
        profileHeader.apply(background: environment.theme.background)
    }

    override func updateTitle() {
        super.updateTitle()
        profileHeader.username = route.identity.isEmpty ? (environment.account.username ?? "") : route.identity
    }

    // MARK: Actions

    /// Opens Instagram's own account switcher when the page has one; otherwise does nothing.
    private func switchAccount() {
        webView.evaluateJavaScript("window.__instagramTabs?window.__instagramTabs.switchAccount():false") { result, _ in
            if result as? Bool == true { Haptics.selection() }
        }
    }

    /// The hamburger menu: a native action sheet.
    func showMenu() {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Settings and activity", style: .default) { [weak self] _ in
            guard let self, let url = Self.settingsURL else { return }
            self.environment.router.open(url, from: self)
        })
        sheet.addAction(UIAlertAction(title: "Content filters", style: .default) { [weak self] _ in
            self?.environment.router.presentSettings()
        })
        sheet.addAction(UIAlertAction(title: "Sign out", style: .destructive) { [weak self] _ in
            self?.confirmSignOut()
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = profileHeader.menuButton
            popover.sourceRect = profileHeader.menuButton.bounds
        }
        present(sheet, animated: true)
    }

    private func confirmSignOut() {
        let alert = UIAlertController(title: "Sign out of Instagram on this device?", message: "This clears Instagram’s website data stored by this app.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Sign out", style: .destructive) { [weak self] _ in
            guard let environment = self?.environment else { return }
            environment.signOut { [weak environment] in environment?.router.shell?.resetTabs() }
        })
        present(alert, animated: true)
    }
}
