import SwiftUI

struct SeekFramesBarScreen: View, RangeDialogPresenting {
    @State private var mode: DualNavigation.Mode = .frames
    @State private var currentIndex = 0
    @State private var range = 0...12
    @State private var isRangeDialogPresented = false

    private let frameCount = 100

    var body: some View {
        NavigationStack {
            ZStack(alignment: .trailing) {
                Color(white: 0.92)
                DualNavigationChrome(
                    frameCount: frameCount,
                    currentIndex: $currentIndex,
                    range: $range,
                    mode: $mode
                )
                HStack(spacing: 8) {
                    rangeButton
                    NavigationLink("Skeleton") {
                        SkeletonScreen(title: "Skeleton", unit: ItemConstructor.spider())
                    }
                    .buttonStyle(.borderedProminent)
                    NavigationLink("Terrence") {
                        TerrenceScreen()
                    }
                    .buttonStyle(.borderedProminent)
                    NavigationLink("Ter2") {
                        Ter2Screen()
                    }
                    .buttonStyle(.borderedProminent)
                    NavigationLink("Stonedummy") {
                        StonedummyScreen()
                    }
                    .buttonStyle(.borderedProminent)
                    NavigationLink("Dino") {
                        DemoSceneScreen(resource: "demo_lil_dino")
                    }
                    .buttonStyle(.borderedProminent)
                    NavigationLink("Saved") {
                        SavedScenesScreen()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding()
            }
            .sheet(isPresented: $isRangeDialogPresented) {
                RangeDialogSheet(frameCount: frameCount, range: $range)
            }
        }
    }

    func showRangeDialog() {
        isRangeDialogPresented = true
    }

    private var rangeButton: some View {
        Button("Range") {
            showRangeDialog()
        }
        .buttonStyle(.borderedProminent)
    }
}

#Preview {
    SeekFramesBarScreen()
}
