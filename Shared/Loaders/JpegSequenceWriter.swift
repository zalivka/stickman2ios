import Foundation
import UIKit

enum JpegSequenceWriter {
    static let directoryName = "export_jpegs"
    private static let queue = DispatchQueue(label: "jpeg.sequence")

    static func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(directoryName, isDirectory: true)
    }

    static func fileName(index: Int) -> String {
        if index < 0 {
            fatalError("JpegSequenceWriter index \(index)")
        }
        return String(format: "frame%04d.jpeg", index)
    }

    static func fileURL(index: Int) -> URL {
        directory().appendingPathComponent(fileName(index: index), isDirectory: false)
    }

    static func write(
        scene: StickmanScene,
        assets: UnitAssets,
        backgrounds: BackgroundAssets,
        progress: @escaping (Int) -> Void,
        completion: @escaping (Int) -> Void
    ) {
        if scene.frames.count < 2 {
            fatalError("JpegSequenceWriter needs at least 2 keyframes, got \(scene.frames.count)")
        }
        MovieGenerator.generate(
            scene: scene,
            assets: assets,
            progress: { value in
                progress(min(max(value * 40 / 100, 0), 40))
            },
            completion: { movie in
                queue.async {
                    let count = writeJpegs(movie: movie, assets: assets, backgrounds: backgrounds, progress: progress)
                    DispatchQueue.main.async {
                        completion(count)
                    }
                }
            }
        )
    }

    private static func writeJpegs(
        movie: StickmanScene,
        assets: UnitAssets,
        backgrounds: BackgroundAssets,
        progress: @escaping (Int) -> Void
    ) -> Int {
        if movie.frames.isEmpty {
            fatalError("JpegSequenceWriter movie has no frames")
        }
        let dir = directory()
        let fm = FileManager.default
        if fm.fileExists(atPath: dir.path) {
            do {
                try fm.removeItem(at: dir)
            } catch {
                fatalError("JpegSequenceWriter could not wipe \(dir.path): \(error)")
            }
        }
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            fatalError("JpegSequenceWriter could not create \(dir.path): \(error)")
        }
        let total = movie.frames.count
        for index in movie.frames.indices {
            autoreleasepool {
                let cgImage = FrameRasterizer.render(
                    frame: movie.frames[index],
                    assets: assets,
                    backgrounds: backgrounds,
                    sceneWidth: movie.width,
                    sceneHeight: movie.height
                )
                let uiImage = UIImage(cgImage: cgImage, scale: 1, orientation: .up)
                guard let data = uiImage.jpegData(compressionQuality: 0.95), !data.isEmpty else {
                    fatalError("JpegSequenceWriter frame \(index) JPEG encode failed")
                }
                let url = fileURL(index: index)
                do {
                    try data.write(to: url, options: .atomic)
                } catch {
                    fatalError("JpegSequenceWriter write \(url.lastPathComponent): \(error)")
                }
                if !fm.fileExists(atPath: url.path) {
                    fatalError("JpegSequenceWriter missing \(url.lastPathComponent) after write")
                }
            }
            let raster = 40 + ((index + 1) * 60 / total)
            DispatchQueue.main.async {
                progress(min(max(raster, 40), 100))
            }
        }
        return total
    }
}
