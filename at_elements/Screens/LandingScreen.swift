#if DEBUG
import BonePaper
#endif
import SwiftUI

/// Android `LandingActivity` + `MakeFragment` — MAKE/LOAD shell, no WATCH/settings/autosave.
struct LandingScreen: View {
    private enum Tab {
        case make
        case load
    }

    @State private var tab: Tab = .make

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                ZStack {
                    switch tab {
                    case .make:
                        MakePane()
                    case .load:
                        SavedScenesGrid(showsChrome: false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                tabRail
            }
            .background(Self.pane.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
        }
    }

    private var tabRail: some View {
        VStack(spacing: 0) {
            tabButton("MAKE", selected: tab == .make) { tab = .make }
            tabButton("LOAD", selected: tab == .load) { tab = .load }
        }
        .padding(5)
        .frame(width: Self.railWidth)
        .frame(maxHeight: .infinity)
        .background(Self.rail)
    }

    private func tabButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(selected ? Self.tabSelected : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    static let pane = Color(red: 0x3d / 255, green: 0x3e / 255, blue: 0x4c / 255)
    static let rail = Color(red: 0x24 / 255, green: 0x25 / 255, blue: 0x30 / 255)
    static let tabSelected = Color.white.opacity(0.14)
    static let railWidth: CGFloat = 100
}

private struct MakePane: View {
    @State private var cartoonSize: CGSize = .zero
    @State private var itemsSize: CGSize = .zero
    @State private var openCartoon = false
    @State private var openItems = false
    #if DEBUG
    @State private var openDesert = false
    @State private var openVillage = false
    @State private var openBoil = false
    #endif

    var body: some View {
        GeometryReader { proxy in
            let dividerX = proxy.size.width * 0.6
            ZStack(alignment: .topLeading) {
                versionLabel
                    .padding(.leading, 8)
                    .padding(.top, 8)

                #if DEBUG
                VStack(alignment: .leading, spacing: 6) {
                    Button("DEBUG: desert road") { openDesert = true }
                    Button("DEBUG: snowy village") { openVillage = true }
                    Button("DEBUG: boil demo") { openBoil = true }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)
                .padding(.leading, 8)
                .padding(.top, 32)
                #endif

                Rectangle()
                    .fill(Color(red: 0xee / 255, green: 0xee / 255, blue: 0xee / 255))
                    .frame(width: 1, height: 160)
                    .position(x: dividerX, y: proxy.size.height / 2)

                Button {
                    openCartoon = true
                } label: {
                    Text("New\nCartoon")
                }
                .buttonStyle(
                    LandingHexButtonStyle(
                        idle: Self.cartoonIdle,
                        pressed: Self.cartoonPressed,
                        color: Color(red: 0x6c / 255, green: 0xae / 255, blue: 0),
                        fontSize: 16
                    )
                )
                .background(SizeReader(size: $cartoonSize))
                .position(
                    Self.center(
                        in: CGRect(x: 0, y: 0, width: dividerX, height: proxy.size.height),
                        size: cartoonSize,
                        horizontalBias: 0.764,
                        verticalBias: 0.5
                    )
                )

                Button {
                    openItems = true
                } label: {
                    Text("Items\nconstructor")
                }
                .buttonStyle(
                    LandingHexButtonStyle(
                        idle: Self.itemsIdle,
                        pressed: Self.itemsPressed,
                        color: Color(red: 0, green: 0xb6 / 255, blue: 1),
                        fontSize: 12
                    )
                )
                .background(SizeReader(size: $itemsSize))
                .position(
                    Self.center(
                        in: CGRect(x: dividerX, y: 0, width: proxy.size.width - dividerX, height: proxy.size.height),
                        size: itemsSize,
                        horizontalBias: 0.172,
                        verticalBias: 0.148
                    )
                )
            }
            .navigationDestination(isPresented: $openCartoon) {
                if UserDefaults.standard.bool(forKey: SceneEditorScreen.tutorialDoneKey) {
                    SceneEditorScreen(
                        scene: .empty(),
                        assets: UnitAssets(),
                        backgrounds: BackgroundAssets()
                    )
                } else {
                    DemoSceneScreen(resource: "intro", subdirectory: "tutorial", tutorial: true)
                }
            }
            .navigationDestination(isPresented: $openItems) {
                CustomItemsListScreen()
            }
            #if DEBUG
            .navigationDestination(isPresented: $openDesert) {
                BonePaperPlayerScreen(session: Self.testSession("desert_road"))
            }
            .navigationDestination(isPresented: $openVillage) {
                BonePaperPlayerScreen(session: Self.testSession("snowy_village"))
            }
            .navigationDestination(isPresented: $openBoil) {
                BoilDemoScreen()
            }
            #endif
        }
    }

    #if DEBUG
    private static func testSession(_ name: String) -> Data {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "testdata") else {
            fatalError("LandingScreen missing testdata/\(name).json")
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            fatalError("LandingScreen could not read \(url.path): \(error)")
        }
    }
    #endif

    private var versionLabel: some View {
        Text("Drawing Cartoons 2 (\(Self.versionName))")
            .font(.system(size: 14))
            .foregroundStyle(Color(white: 0x88 / 255))
            .lineLimit(1)
    }

    /// Android ConstraintLayout leftover-space bias; `position` is the view center.
    private static func center(
        in box: CGRect,
        size: CGSize,
        horizontalBias: CGFloat,
        verticalBias: CGFloat
    ) -> CGPoint {
        let margin: CGFloat = 8
        let originX = box.minX + margin + horizontalBias * (box.width - margin * 2 - size.width)
        let originY = box.minY + margin + verticalBias * (box.height - margin * 2 - size.height)
        return CGPoint(x: originX + size.width / 2, y: originY + size.height / 2)
    }

    private static let versionName: String = {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !value.isEmpty
        else {
            fatalError("LandingScreen missing CFBundleShortVersionString")
        }
        return value
    }()

    private static let cartoonIdle = chromeImage("landing_hex2")
    private static let cartoonPressed = chromeImage("landing_hex_pressed2")
    private static let itemsIdle = chromeImage("landing_hex_items")
    private static let itemsPressed = chromeImage("landing_hex_items_pressed")

    /// xxxhdpi raster — 4px per pt, matching Android density.
    private static func chromeImage(_ name: String) -> CGImage {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "chrome")
            ?? Bundle.main.url(forResource: name, withExtension: "png")
        else {
            fatalError("LandingScreen missing chrome/\(name).png")
        }
        do {
            let data = try Data(contentsOf: url)
            return PNGImage.cgImage(from: data, name: "chrome/\(name).png")
        } catch {
            fatalError("LandingScreen could not read \(url.path): \(error)")
        }
    }
}

/// Android `drawableTop` hex + label; `state_pressed` swaps the bitmap only.
private struct LandingHexButtonStyle: ButtonStyle {
    let idle: CGImage
    let pressed: CGImage
    let color: Color
    let fontSize: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 4) {
            Image(decorative: configuration.isPressed ? pressed : idle, scale: 4)
                .interpolation(.high)
            configuration.label
                .font(.system(size: fontSize))
                .foregroundStyle(color)
                .multilineTextAlignment(.center)
        }
        .contentShape(Rectangle())
    }
}

private struct SizeReader: View {
    @Binding var size: CGSize

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: SizePreferenceKey.self, value: proxy.size)
        }
        .onPreferenceChange(SizePreferenceKey.self) { size = $0 }
    }
}

private struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
