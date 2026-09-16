import BonePaper
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
                    NavigationLink("Dino") {
                        DemoSceneScreen(resource: "demo_lil_dino")
                    }
                    .buttonStyle(.borderedProminent)
                    NavigationLink("Saved Scenes") {
                        SavedScenesScreen()
                    }
                    .buttonStyle(.borderedProminent)
                    NavigationLink("Custom Items") {
                        CustomItemsListScreen()
                    }
                    .buttonStyle(.borderedProminent)
                    NavigationLink("Draw") {
                        BonePaperScreen()
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
