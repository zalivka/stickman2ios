import SwiftUI
import UIKit

struct JpegsScreen: View {
    let source: StickmanScene
    let assets: UnitAssets
    var backgrounds: BackgroundAssets = BackgroundAssets()

    @State private var phase: Phase = .generating
    @State private var percent = 0
    @State private var fileCount = 0
    @State private var currentIndex = 0
    @State private var generation = UUID()

    private static let frameNumber = Color(red: 0xfd / 255, green: 0xda / 255, blue: 0x0d / 255)
    private static let frameNumberBack = Color(white: 0.16, opacity: 0.88)

    private enum Phase {
        case generating, ready
    }

    var body: some View {
        ZStack {
            SkeletonCanvas.previewBackdrop
            if phase == .ready {
                jpegView
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    PreviewSeekBar(progress: progressBinding)
                        .frame(maxHeight: .infinity)
                        .padding(16)
                }
            }
            if phase == .generating {
                ReplayOverlay(text: "JPEGS… \(percent)%", onTap: {})
            }
        }
        .background(SkeletonCanvas.previewBackdrop)
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) {
            FullscreenBackButton(besideMainPanel: false)
        }
        .overlay(alignment: .top) {
            if phase == .ready {
                Text("JPEGS")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.top, 18)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if phase == .ready {
                indexBadge(current: currentIndex + 1)
                    .padding(.leading, 16)
                    .padding(.bottom, 20)
                    .allowsHitTesting(false)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear(perform: startWrite)
        .onDisappear(perform: dismissWrite)
    }

    private var jpegView: some View {
        GeometryReader { geo in
            let image = currentJPEG()
            let availW = max(geo.size.width - PreviewSeekBar.width - 32, 1)
            let availH = max(geo.size.height, 1)
            let scale = min(availW / image.size.width, availH / image.size.height)
            let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            Image(uiImage: image)
                .resizable()
                .frame(width: drawn.width, height: drawn.height)
                .position(x: availW / 2, y: availH / 2)
        }
    }

    private func currentJPEG() -> UIImage {
        if fileCount < 1 {
            fatalError("JpegsScreen has no JPEG files")
        }
        if currentIndex < 0 || currentIndex >= fileCount {
            fatalError("JpegsScreen index \(currentIndex) out of \(fileCount)")
        }
        let url = JpegSequenceWriter.fileURL(index: currentIndex)
        if !FileManager.default.fileExists(atPath: url.path) {
            fatalError("JpegsScreen missing \(url.lastPathComponent)")
        }
        guard let image = UIImage(contentsOfFile: url.path) else {
            fatalError("JpegsScreen could not read \(url.lastPathComponent)")
        }
        return image
    }

    private func indexBadge(current: Int) -> some View {
        if fileCount < 1 {
            fatalError("JpegsScreen badge has no files")
        }
        let digits = String(fileCount).count
        let probe = String(repeating: "8", count: digits)
        return ZStack {
            Text(probe)
                .hidden()
            Text("\(current)")
        }
        .font(.system(size: 22, weight: .medium, design: .rounded).monospacedDigit())
        .foregroundStyle(Self.frameNumber)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Self.frameNumberBack, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var progressBinding: Binding<Double> {
        Binding(
            get: {
                if fileCount < 1 {
                    fatalError("JpegsScreen seek with no files")
                }
                return Double(currentIndex) / Double(fileCount)
            },
            set: { value in
                if fileCount < 1 {
                    fatalError("JpegsScreen seek with no files")
                }
                let index = Int(Double(fileCount) * value)
                currentIndex = min(max(index, 0), fileCount - 1)
            }
        )
    }

    private func startWrite() {
        let token = UUID()
        generation = token
        phase = .generating
        percent = 0
        fileCount = 0
        currentIndex = 0
        JpegSequenceWriter.write(
            scene: source,
            assets: assets,
            backgrounds: backgrounds,
            progress: { value in
                guard generation == token else { return }
                percent = value
            },
            completion: { count in
                guard generation == token else { return }
                if count < 1 {
                    fatalError("JpegsScreen write produced \(count) files")
                }
                fileCount = count
                currentIndex = 0
                phase = .ready
            }
        )
    }

    private func dismissWrite() {
        generation = UUID()
        phase = .generating
    }
}
