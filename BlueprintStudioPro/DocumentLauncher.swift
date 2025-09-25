import SwiftUI
import UIKit

/// SwiftUI wrapper for UIDocumentInteractionController ("Open in…", Preview).
struct DocumentLauncher: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        DispatchQueue.main.async {
            present(from: vc.view, url: url)
        }
        return vc
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) { }
    
    private func present(from sourceView: UIView, url: URL) {
        let controller = UIDocumentInteractionController(url: url)
        controller.uti = (try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier) ?? nil
        controller.name = url.lastPathComponent
        controller.delegate = DocumentLauncherDelegate.shared
        controller.presentOptionsMenu(from: sourceView.bounds, in: sourceView, animated: true)
    }
}

private final class DocumentLauncherDelegate: NSObject, UIDocumentInteractionControllerDelegate {
    static let shared = DocumentLauncherDelegate()
    func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController ?? UIViewController()
    }
}

private extension UIWindowScene {
    var keyWindow: UIWindow? { windows.first { $0.isKeyWindow } }
}

