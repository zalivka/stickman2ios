import SwiftUI
import UIKit

enum BonePaperChrome {
    static let pad: CGFloat = 16
    static let leftRail: CGFloat = 75
    static let rightRail: CGFloat = 76
    static let tool: CGFloat = 44
    static let pane = Color(red: 0x24 / 255, green: 0x25 / 255, blue: 0x30 / 255)
    static let selected = Color(red: 0x45 / 255, green: 0x96 / 255, blue: 1)
    static let brushfillSelected = Color(red: 1, green: 0x59 / 255, blue: 0xB8 / 255)
    static let apply = Color(red: 0x37 / 255, green: 0xAB / 255, blue: 0x22 / 255)

    static var railIconInset: CGFloat { (leftRail - tool) / 2 }

    static func fitInsets(safe: EdgeInsets, topClearance: CGFloat) -> UIEdgeInsets {
        UIEdgeInsets(
            top: topClearance + pad,
            left: pad,
            bottom: safe.bottom + pad,
            right: safe.trailing + pad + rightRail
        )
    }

    static func chromeImage(_ name: String) -> UIImage {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "chrome")
            ?? Bundle.main.url(forResource: name, withExtension: "png")
        else {
            fatalError("BonePaper missing chrome/\(name).png")
        }
        guard let image = UIImage(contentsOfFile: url.path) else {
            fatalError("BonePaper could not read \(url.path)")
        }
        return image
    }
}

enum BonePaperHexToast {
    private static var label: UILabel?
    private static var hide: DispatchWorkItem?

    static func show(_ hex: String) {
        showMessage(hex)
    }

    static func showMessage(_ text: String) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) else {
            fatalError("BonePaperHexToast with no window")
        }
        let label = self.label ?? UILabel()
        label.text = text
        label.font = .monospacedSystemFont(ofSize: 15, weight: .semibold)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.82)
        label.textAlignment = .center
        label.layer.cornerRadius = 16
        label.clipsToBounds = true
        let textWidth = (text as NSString).size(withAttributes: [.font: label.font as Any]).width
        label.bounds = CGRect(x: 0, y: 0, width: textWidth + 28, height: 32)
        label.center = CGPoint(x: window.bounds.midX, y: window.safeAreaInsets.top + 88)
        label.alpha = 1
        if label.superview !== window {
            window.addSubview(label)
        }
        self.label = label
        hide?.cancel()
        let work = DispatchWorkItem { [weak label] in
            UIView.animate(withDuration: 0.2) { label?.alpha = 0 }
        }
        hide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }
}
