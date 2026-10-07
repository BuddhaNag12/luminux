import SafariServices
import UIKit

extension UIApplication {
    /// The controller on top of the key window, for things UIKit has to present itself.
    var topViewController: UIViewController? {
        let window = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        var top = window?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }

    /// Opens a web page in Safari's in-app view, tinted with the accent.
    func openInApp(_ url: URL, tint: UIColor) {
        guard let presenter = topViewController else { return }
        let safari = SFSafariViewController(url: url)
        safari.preferredControlTintColor = tint
        presenter.present(safari, animated: true)
    }
}
