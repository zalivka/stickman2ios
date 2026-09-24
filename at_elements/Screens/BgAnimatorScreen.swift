import FlexColorPicker
import SwiftUI
import UIKit

enum SolidBackgrounds {
    /// Android BgAnimatorActivity2 default solid suggestions.
    static let presets = [
        "#FFFFFF",
        "#18574A",
        "#F5BE67",
        "#DA9EE6",
        "#5899A6",
        "#F79779",
        "#486641"
    ]

    static let reset = "#FFFFFF"
}

struct BgAnimatorScreen: View {
    @Binding var scene: StickmanScene
    var assets: UnitAssets
    var backgrounds: BackgroundAssets

    @State private var navMode: DualNavigation.Mode = .frames
    @State private var range: ClosedRange<Int>
    @State private var showingPreview = false
    @State private var showingColorPicker = false
    @State private var extraColors: [String] = []
    /// Android `mTempBgs`: every background applied in this session, kept in the strip.
    @State private var tempBackgrounds: [String] = []
    @State private var showingChooser = false
    @State private var pendingRangeBg: String?

    init(scene: Binding<StickmanScene>, assets: UnitAssets, backgrounds: BackgroundAssets) {
        if scene.wrappedValue.frames.isEmpty {
            fatalError("BgAnimatorScreen has no frames")
        }
        _scene = scene
        self.assets = assets
        self.backgrounds = backgrounds
        _range = State(
            initialValue: DualNavigation.defaultRange(
                current: scene.wrappedValue.currentIndex,
                frameCount: scene.wrappedValue.frames.count
            )
        )
        _extraColors = State(initialValue: Self.nonStandardSolids(in: scene.wrappedValue))
    }

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                MainPanel(
                    onPlay: { showingPreview = true },
                    playEnabled: scene.frames.count >= 2,
                    onDraw: {},
                    onAdd: { showingChooser = true },
                    onReset: resetBackground
                )
                ZStack(alignment: .leading) {
                    workArea
                    BackgroundStrip(
                        names: stripNames,
                        pictureMode: pictureStrip,
                        backgrounds: backgrounds,
                        selected: scene.currentFrame.bgName,
                        onPick: applyBackground,
                        onLongPress: beginRangePick,
                        onAdd: { showingColorPicker = true }
                    )
                }
            }
        }
        .overlay(alignment: .trailing) {
            DualNavigationChrome(
                    frameCount: scene.frames.count,
                    currentIndex: currentIndexBinding,
                    range: $range,
                    mode: $navMode,
                    onNextAtEnd: { scene.addFrame() }
                )
        }
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) {
            FullscreenBackButton(
                extraLeading: BackgroundStrip.width(pictureMode: pictureStrip)
            )
        }
        .overlay {
            if let bgName = pendingRangeBg {
                RangePicker(
                    title: "Apply the background to a range of frames",
                    frameCount: scene.frames.count,
                    initialRange: rangePickInitial,
                    preview: { index in
                        AnyView(
                            RangeFramePreview(
                                scene: scene,
                                index: index,
                                assets: assets,
                                backgrounds: backgrounds
                            )
                        )
                    },
                    onCancel: { pendingRangeBg = nil },
                    onApply: { span in
                        applyBackground(bgName, to: span)
                        range = span
                        navMode = .range
                        pendingRangeBg = nil
                    }
                )
                .ignoresSafeArea()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .fullScreenCover(isPresented: $showingPreview) {
            FullscreenPreviewScreen(source: scene, assets: assets, backgrounds: backgrounds)
        }
        .sheet(isPresented: $showingColorPicker) {
            FlexColorPickerSheet(initial: pickerInitialColor) { color in
                applyBackground(Self.hexRGB(from: color))
                showingColorPicker = false
            }
        }
        .sheet(isPresented: $showingChooser) {
            BgChooserSheet(
                sceneWidth: scene.width,
                sceneHeight: scene.height,
                backgrounds: backgrounds,
                onPick: { bgName in
                    showingChooser = false
                    applyBackground(bgName)
                },
                onCancel: { showingChooser = false }
            )
        }
    }

    private var workArea: some View {
        SkeletonCanvas(
                unit: scene.currentFrame.units.isEmpty ? nil : unitBinding,
                frameUnits: scene.currentFrame.units,
                assets: assets,
                backgrounds: backgrounds,
                bgName: scene.currentFrame.bgName,
                bgMove: scene.currentFrame.bgMove,
                cameraMove: scene.currentFrame.cameraMove,
                sceneWidth: scene.width,
                sceneHeight: scene.height,
                currentIndex: scene.currentIndex,
                mode: .background,
                showSkeleton: false,
                onBackgroundChange: applyBgMove
            )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SkeletonCanvas.pane)
    }

    private var pickerInitialColor: UIColor {
        guard let name = scene.currentFrame.bgName, name.hasPrefix("#") else {
            return UIColor.white
        }
        let rgba = HexRGB.parse(name)
        return UIColor(red: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
    }

    private static func hexRGB(from color: UIColor) -> String {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        if !color.getRed(&r, green: &g, blue: &b, alpha: &a) {
            guard let converted = color.cgColor.converted(
                to: CGColorSpaceCreateDeviceRGB(),
                intent: .defaultIntent,
                options: nil
            ) else {
                fatalError("BgAnimatorScreen color is not RGB")
            }
            if !UIColor(cgColor: converted).getRed(&r, green: &g, blue: &b, alpha: &a) {
                fatalError("BgAnimatorScreen converted color is not RGB")
            }
        }
        let ri = min(max(Int((r * 255).rounded()), 0), 255)
        let gi = min(max(Int((g * 255).rounded()), 0), 255)
        let bi = min(max(Int((b * 255).rounded()), 0), 255)
        return String(format: "#%02X%02X%02X", ri, gi, bi)
    }

    /// Picture backgrounds use the large swatches. An all-solid strip stays at the color size.
    private var pictureStrip: Bool {
        !stripNames.allSatisfy { $0.hasPrefix("#") }
    }

    /// Android `BgAdapter.reset`: once any non-solid background is in play, the strip lists the
    /// scene's backgrounds (solids included) plus this session's picks, instead of color suggestions.
    private var stripNames: [String] {
        var seen = Set<String>()
        var used: [String] = []
        for name in scene.frames.compactMap(\.bgName) + tempBackgrounds where !seen.contains(name) {
            seen.insert(name)
            used.append(name)
        }
        if used.allSatisfy({ $0.hasPrefix("#") }) {
            return thumbColors
        }
        return used
    }

    private var thumbColors: [String] {
        var seen = Set<String>()
        var list: [String] = []
        func add(_ hex: String) {
            if !hex.hasPrefix("#") {
                return
            }
            _ = HexRGB.parse(hex)
            let key = hex.uppercased()
            if seen.contains(key) {
                return
            }
            seen.insert(key)
            list.append(hex)
        }
        for preset in SolidBackgrounds.presets {
            add(preset)
        }
        for hex in extraColors {
            add(hex)
        }
        return list
    }

    private static func nonStandardSolids(in scene: StickmanScene) -> [String] {
        var seen = Set<String>()
        var list: [String] = []
        for frame in scene.frames {
            guard let name = frame.bgName, name.hasPrefix("#") else {
                continue
            }
            _ = HexRGB.parse(name)
            let key = name.uppercased()
            if seen.contains(key) {
                continue
            }
            if SolidBackgrounds.presets.contains(where: { $0.uppercased() == key }) {
                continue
            }
            seen.insert(key)
            list.append(name)
        }
        return list
    }

    private func rememberColor(_ hex: String) {
        _ = HexRGB.parse(hex)
        let key = hex.uppercased()
        if SolidBackgrounds.presets.contains(where: { $0.uppercased() == key }) {
            return
        }
        if extraColors.contains(where: { $0.uppercased() == key }) {
            return
        }
        extraColors.append(hex)
    }

    private var rangePickInitial: ClosedRange<Int> {
        switch navMode {
        case .range:
            if range.lowerBound < 0 || range.upperBound >= scene.frames.count {
                fatalError("BgAnimatorScreen range \(range) out of \(scene.frames.count)")
            }
            return range
        case .frames:
            return 0...(scene.frames.count - 1)
        }
    }

    private func beginRangePick(_ bgName: String) {
        if scene.frames.count < 2 {
            applyBackground(bgName)
            return
        }
        pendingRangeBg = bgName
    }

    private func applyBackground(_ bgName: String) {
        switch navMode {
        case .frames:
            let index = scene.currentIndex
            applyBackground(bgName, to: index...index)
        case .range:
            applyBackground(bgName, to: range)
        }
    }

    /// Android `applyBackground`: every frame in the span gets the name and the fitted move.
    private func applyBackground(_ bgName: String, to span: ClosedRange<Int>) {
        if span.lowerBound < 0 || span.upperBound >= scene.frames.count {
            fatalError("BgAnimatorScreen range \(span) out of \(scene.frames.count)")
        }
        let move: PictureMove
        if bgName.hasPrefix("#") {
            rememberColor(bgName)
            move = .identity
        } else {
            move = BackgroundResolver.fittedMove(
                image: backgrounds.image(for: bgName),
                sceneWidth: scene.width,
                sceneHeight: scene.height
            )
        }
        if !tempBackgrounds.contains(bgName) {
            tempBackgrounds.append(bgName)
        }
        for index in span {
            scene.frames[index].bgName = bgName
            scene.frames[index].bgMove = move
        }
    }

    private func applyBgMove(_ move: PictureMove) {
        let span: ClosedRange<Int>
        switch navMode {
        case .frames:
            let index = scene.currentIndex
            span = index...index
        case .range:
            span = range
        }
        if span.lowerBound < 0 || span.upperBound >= scene.frames.count {
            fatalError("BgAnimatorScreen range \(span) out of \(scene.frames.count)")
        }
        for index in span {
            scene.frames[index].bgMove = move
        }
    }

    private func resetBackground() {
        applyBackground(SolidBackgrounds.reset)
    }

    private var currentIndexBinding: Binding<Int> {
        Binding(
            get: { scene.currentIndex },
            set: { newIndex in
                if newIndex < 0 || newIndex >= scene.frames.count {
                    fatalError("BgAnimatorScreen currentIndex \(newIndex) out of \(scene.frames.count)")
                }
                scene.currentIndex = newIndex
            }
        )
    }

    private var unitBinding: Binding<StickmanUnit> {
        Binding(
            get: {
                let frame = scene.currentFrame
                guard let first = frame.units.first else {
                    fatalError("BgAnimatorScreen frame \(frame.id) read unit")
                }
                return first
            },
            set: { _ in
                fatalError("BgAnimatorScreen canvas is not an editor")
            }
        )
    }
}

private struct BackgroundStrip: View {
    static let colorWidth: CGFloat = 52
    static let pictureWidth: CGFloat = 88
    private static let colorSwatch: CGFloat = 36
    private static let pictureSwatch: CGFloat = 72

    var names: [String]
    var pictureMode: Bool
    var backgrounds: BackgroundAssets
    var selected: String?
    var onPick: (String) -> Void
    var onLongPress: (String) -> Void
    var onAdd: () -> Void

    static func width(pictureMode: Bool) -> CGFloat {
        pictureMode ? pictureWidth : colorWidth
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(names, id: \.self) { name in
                    let side = pictureMode ? Self.pictureSwatch : Self.colorSwatch
                    swatch(name)
                        .frame(width: side, height: side)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(
                                    isSelected(name) ? Color.white : Color(white: 0.25),
                                    lineWidth: isSelected(name) ? 3 : 1
                                )
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .onTapGesture {
                            onPick(name)
                        }
                        .onLongPressGesture(minimumDuration: 0.35, perform: {
                            onLongPress(name)
                        })
                        .accessibilityLabel(name)
                        .accessibilityAddTraits(.isButton)
                }
                if !pictureMode {
                    let side = Self.colorSwatch
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .font(.system(size: side * 0.4, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: side, height: side)
                            .overlay {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .stroke(Color.white.opacity(0.7), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add color")
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
        }
        .frame(width: Self.width(pictureMode: pictureMode))
        .frame(maxHeight: .infinity)
        .background(Color.black.opacity(0.35))
        .accessibilityIdentifier("background colors")
    }

    @ViewBuilder
    private func swatch(_ name: String) -> some View {
        if name.hasPrefix("#") {
            let rgba = HexRGB.parse(name)
            Color(red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a)
        } else {
            Image(decorative: backgrounds.image(for: name), scale: 1)
                .resizable()
                .scaledToFill()
        }
    }

    private func isSelected(_ name: String) -> Bool {
        guard let selected else {
            return false
        }
        if !name.hasPrefix("#") || !selected.hasPrefix("#") {
            return name == selected
        }
        let a = HexRGB.parse(name)
        let b = HexRGB.parse(selected)
        return a.r == b.r && a.g == b.g && a.b == b.b && a.a == b.a
    }
}

private struct FlexColorPickerSheet: UIViewControllerRepresentable {
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
        picker.navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Apply",
            style: .done,
            target: context.coordinator,
            action: #selector(Coordinator.apply)
        )
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
            onApply(confirmedColor)
        }

        @objc func apply() {
            guard let picker else {
                fatalError("FlexColorPickerSheet Apply with no picker")
            }
            onApply(picker.selectedColor)
        }

        @objc func cancel() {
            navigation?.dismiss(animated: true)
        }
    }
}
