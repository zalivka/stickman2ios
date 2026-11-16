import FlexColorPicker
import SwiftUI
import UIKit

struct BonePaperPlainScroll<Content: View>: UIViewRepresentable {
    var onScroll: () -> Void
    var content: Content

    init(onScroll: @escaping () -> Void = {}, @ViewBuilder content: () -> Content) {
        self.onScroll = onScroll
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScroll: onScroll)
    }

    func makeUIView(context: Context) -> BonePaperFillScrollView {
        let scroll = BonePaperFillScrollView()
        scroll.bounces = false
        scroll.alwaysBounceVertical = false
        scroll.showsVerticalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.automaticallyAdjustsScrollIndicatorInsets = false
        scroll.backgroundColor = .clear
        scroll.delegate = context.coordinator
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        scroll.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        let host = UIHostingController(rootView: AnyView(content.ignoresSafeArea()))
        host.sizingOptions = .intrinsicContentSize
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        host.view.insetsLayoutMarginsFromSafeArea = false
        host.view.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            host.view.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])
        context.coordinator.host = host
        return scroll
    }

    func updateUIView(_ scroll: BonePaperFillScrollView, context: Context) {
        context.coordinator.onScroll = onScroll
        guard let host = context.coordinator.host else {
            fatalError("BonePaperPlainScroll missing host")
        }
        host.rootView = AnyView(content.ignoresSafeArea())
        host.view.invalidateIntrinsicContentSize()
        host.view.setNeedsLayout()
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var host: UIHostingController<AnyView>?
        var onScroll: () -> Void

        init(onScroll: @escaping () -> Void) {
            self.onScroll = onScroll
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            onScroll()
        }
    }
}

final class BonePaperFillScrollView: UIScrollView {
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }
}

struct BonePaperFlexColorPickerSheet: UIViewControllerRepresentable {
    var initial: UIColor
    var onApply: (UIColor) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onApply: onApply)
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let picker = DefaultColorPickerViewController()
        picker.selectedColor = initial
        picker.delegate = context.coordinator
        picker.title = "Color"
        picker.navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: context.coordinator,
            action: #selector(Coordinator.cancel)
        )
        let applyItem = UIBarButtonItem(
            title: "Apply",
            style: .done,
            target: context.coordinator,
            action: #selector(Coordinator.apply)
        )
        picker.navigationItem.rightBarButtonItem = applyItem
        picker.colorPreview.onHexValidityChanged = { [weak applyItem] valid in
            applyItem?.isEnabled = valid
        }
        context.coordinator.picker = picker
        let nav = UINavigationController(rootViewController: picker)
        context.coordinator.navigation = nav
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        context.coordinator.onApply = onApply
        context.coordinator.navigation = uiViewController
        if let picker = uiViewController.viewControllers.first as? DefaultColorPickerViewController {
            context.coordinator.picker = picker
            picker.delegate = context.coordinator
            let applyItem = picker.navigationItem.rightBarButtonItem
            picker.colorPreview.onHexValidityChanged = { [weak applyItem] valid in
                applyItem?.isEnabled = valid
            }
        }
    }

    final class Coordinator: NSObject, ColorPickerDelegate {
        var onApply: (UIColor) -> Void
        weak var picker: DefaultColorPickerViewController?
        weak var navigation: UINavigationController?

        init(onApply: @escaping (UIColor) -> Void) {
            self.onApply = onApply
        }

        func colorPicker(
            _ colorPicker: ColorPickerController,
            confirmedColor: UIColor,
            usingControl: ColorControl
        ) {
            if let picker, !picker.colorPreview.isHexValid {
                return
            }
            picker?.colorPreview.hexTextField.resignFirstResponder()
            let finalColor = picker?.colorPreview.parsedHexColor() ?? confirmedColor
            let hex = BonePaperColorStore.hex(from: finalColor)
            UIPasteboard.general.string = hex
            onApply(finalColor)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                BonePaperHexToast.showMessage("Color \(hex) copied")
            }
        }

        @objc func apply() {
            guard let picker else {
                fatalError("BonePaperFlexColorPickerSheet Apply with no picker")
            }
            guard picker.colorPreview.isHexValid else {
                return
            }
            picker.colorPreview.hexTextField.resignFirstResponder()
            let finalColor = picker.colorPreview.parsedHexColor() ?? picker.selectedColor
            onApply(finalColor)
        }

        @objc func cancel() {
            navigation?.dismiss(animated: true)
        }
    }
}
