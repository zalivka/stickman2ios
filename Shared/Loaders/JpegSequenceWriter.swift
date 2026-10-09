import Foundation
import UIKit

final class JpegWriteStop: @unchecked Sendable {
    private nonisolated(unsafe) let lock = NSLock()
    private nonisolated(unsafe) var cancelled = false

    nonisolated func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    nonisolated var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

enum JpegWriteError: Error, CustomStringConvertible {
    case cancelled
    case failed(String)

    var description: String {
        switch self {
        case .cancelled:
            return "Export cancelled"
        case .failed(let message):
            return message
        }
    }
}

enum JpegSequenceWriter {
    static let directoryName = "export_jpegs"
    private static let queue = DispatchQueue(label: "jpeg.sequence")

    static func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(directoryName, isDirectory: true)
    }

    static func fileName(index: Int) throws -> String {
        if index < 0 {
            throw JpegWriteError.failed("JpegSequenceWriter index \(index)")
        }
        return String(format: "frame%04d.jpeg", index)
    }

    static func fileURL(index: Int) throws -> URL {
        try directory().appendingPathComponent(fileName(index: index), isDirectory: false)
    }

    /// Removes the intermediate-frame directory if present. Cleanup failure
    /// must never crash a finished export, so errors are only logged.
    static func clean() {
        let dir = directory()
        guard FileManager.default.fileExists(atPath: dir.path) else { return }
        do {
            try FileManager.default.removeItem(at: dir)
        } catch {
            print("JpegSequenceWriter clean \(dir.path): \(error)")
        }
    }

    static func write(
        scene: StickmanScene,
        assets: UnitAssets,
        backgrounds: BackgroundAssets,
        stop: JpegWriteStop,
        progress: @escaping (Int) -> Void,
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        if scene.frames.count < 2 {
            completion(.failure(JpegWriteError.failed(
                "JpegSequenceWriter needs at least 2 keyframes, got \(scene.frames.count)"
            )))
            return
        }
        clean()
        MovieGenerator.generate(
            scene: scene,
            assets: assets,
            progress: { value in
                progress(min(max(value * 40 / 100, 0), 40))
            },
            failure: { error in
                completion(.failure(error))
            },
            completion: { movie in
                queue.async {
                    if stop.isCancelled {
                        DispatchQueue.main.async {
                            completion(.failure(JpegWriteError.cancelled))
                        }
                        return
                    }
                    do {
                        let count = try writeJpegs(
                            movie: movie,
                            assets: assets,
                            backgrounds: backgrounds,
                            stop: stop,
                            progress: progress
                        )
                        DispatchQueue.main.async {
                            completion(.success(count))
                        }
                    } catch {
                        DispatchQueue.main.async {
                            completion(.failure(error))
                        }
                    }
                }
            }
        )
    }

    private static func writeJpegs(
        movie: StickmanScene,
        assets: UnitAssets,
        backgrounds: BackgroundAssets,
        stop: JpegWriteStop,
        progress: @escaping (Int) -> Void
    ) throws -> Int {
        if movie.frames.isEmpty {
            throw JpegWriteError.failed("JpegSequenceWriter movie has no frames")
        }
        let dir = directory()
        let fm = FileManager.default
        if fm.fileExists(atPath: dir.path) {
            do {
                try fm.removeItem(at: dir)
            } catch {
                throw JpegWriteError.failed("JpegSequenceWriter could not wipe \(dir.path): \(error)")
            }
        }
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            throw JpegWriteError.failed("JpegSequenceWriter could not create \(dir.path): \(error)")
        }
        let total = movie.frames.count
        for index in movie.frames.indices {
            if stop.isCancelled {
                throw JpegWriteError.cancelled
            }
            try autoreleasepool {
                let cgImage = FrameRasterizer.render(
                    frame: movie.frames[index],
                    assets: assets,
                    backgrounds: backgrounds,
                    sceneWidth: movie.width,
                    sceneHeight: movie.height
                )
                let uiImage = UIImage(cgImage: cgImage, scale: 1, orientation: .up)
                guard let data = uiImage.jpegData(compressionQuality: 0.95), !data.isEmpty else {
                    throw JpegWriteError.failed("JpegSequenceWriter frame \(index) JPEG encode failed")
                }
                let url = try fileURL(index: index)
                do {
                    try data.write(to: url, options: .atomic)
                } catch {
                    throw JpegWriteError.failed("JpegSequenceWriter write \(url.lastPathComponent): \(error)")
                }
                if !fm.fileExists(atPath: url.path) {
                    throw JpegWriteError.failed("JpegSequenceWriter missing \(url.lastPathComponent) after write")
                }
            }
            if stop.isCancelled {
                throw JpegWriteError.cancelled
            }
            let raster = 40 + ((index + 1) * 60 / total)
            DispatchQueue.main.async {
                progress(min(max(raster, 40), 100))
            }
        }
        return total
    }
}
