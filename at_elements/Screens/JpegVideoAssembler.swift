import Foundation
import Photos
import ffmpegkit

enum JpegVideoAssembler {
    static let fps = 60

    static func outputURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("export.mp4", isDirectory: false)
    }

    static func cancel() {
        FFmpegKit.cancel()
    }

    static func assemble(frameCount: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        if frameCount < 1 {
            fatalError("JpegVideoAssembler frameCount \(frameCount)")
        }
        let first = JpegSequenceWriter.fileURL(index: 0)
        if !FileManager.default.fileExists(atPath: first.path) {
            fatalError("JpegVideoAssembler missing \(first.path)")
        }
        let pattern = JpegSequenceWriter.directory()
            .appendingPathComponent("frame%04d.jpeg", isDirectory: false)
            .path
        let out = outputURL()
        let fm = FileManager.default
        if fm.fileExists(atPath: out.path) {
            do {
                try fm.removeItem(at: out)
            } catch {
                completion(.failure(error))
                return
            }
        }
        let duration = Double(frameCount) / Double(fps) + 1
        let args = [
            "-y",
            "-f", "image2",
            "-framerate", "\(fps)",
            "-start_number", "0",
            "-i", pattern,
            "-c:v", "mpeg4",
            "-qscale:v", "1",
            "-an",
            "-t", String(format: "%.2f", duration),
            out.path,
        ]
        FFmpegKit.execute(withArgumentsAsync: args, withCompleteCallback: { session in
            guard let session else {
                completion(.failure(AssemblerError.ffmpegFailed(-1)))
                return
            }
            let code = session.getReturnCode()
            if ReturnCode.isCancel(code) {
                return
            }
            guard ReturnCode.isSuccess(code) else {
                completion(.failure(AssemblerError.ffmpegFailed(Int(code?.getValue() ?? -1))))
                return
            }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: out.path, isDirectory: &isDir), !isDir.boolValue else {
                completion(.failure(AssemblerError.missingOutput))
                return
            }
            saveToPhotos(url: out, completion: completion)
        })
    }

    private static func saveToPhotos(url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                completion(.failure(AssemblerError.photosDenied))
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }, completionHandler: { success, error in
                if let error {
                    completion(.failure(error))
                    return
                }
                if !success {
                    completion(.failure(AssemblerError.photosSaveFailed))
                    return
                }
                completion(.success(()))
            })
        }
    }

    enum AssemblerError: Error {
        case ffmpegFailed(Int)
        case missingOutput
        case photosDenied
        case photosSaveFailed
    }
}
