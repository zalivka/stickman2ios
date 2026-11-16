import SwiftUI
import UIKit

/// iPad-safe `UIActivityViewController` sheet. The popover is anchored to the
/// key window so iPad does not crash without a source view. Android
/// `SavedFragment.share` copies to `DIR_TO_SHARE` and sends the zip; on iOS
/// the saved `.ats` file is already a zip, so the file URL is shared directly.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = UIApplication.shared.keyWindow?.rootViewController?.view
        controller.popoverPresentationController?.sourceRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        return controller
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
