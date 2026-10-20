import UIKit

/// Startup-only splash (the shipped logo and branding) shown over the shell until Home is
/// ready, then cross-faded away. Never shown again during navigation.
final class SplashView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        let logo = UIImageView(image: UIImage(named: "InstagramLaunchLogo"))
        let branding = UIImageView(image: UIImage(named: "InstagramLaunchBranding"))
        for image in [logo, branding] {
            image.contentMode = .scaleAspectFit
            image.translatesAutoresizingMaskIntoConstraints = false
            addSubview(image)
        }
        NSLayoutConstraint.activate([
            logo.centerXAnchor.constraint(equalTo: centerXAnchor),
            logo.centerYAnchor.constraint(equalTo: centerYAnchor),
            logo.widthAnchor.constraint(equalToConstant: 100),
            logo.heightAnchor.constraint(equalToConstant: 100),
            branding.centerXAnchor.constraint(equalTo: centerXAnchor),
            branding.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -24),
            branding.widthAnchor.constraint(equalToConstant: 76),
            branding.heightAnchor.constraint(equalToConstant: 38),
        ])
        isAccessibilityElement = true
        accessibilityLabel = "Instagram"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func dismiss() {
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut], animations: { self.alpha = 0 }) { _ in
            self.removeFromSuperview()
        }
    }
}
