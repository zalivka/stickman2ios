import Compression
import Foundation
import XCTest

/// Minimal ZIP reader for one entry — self-contained so the check does not
/// import app code and cannot cancel its own errors.
private struct TestZipError: Error { let message: String }

private func testU16(_ zip: Data, _ offset: Int) throws -> UInt16 {
    guard offset >= 0, offset + 2 <= zip.count else { throw TestZipError(message: "zip u16 out of range") }
    return UInt16(zip[offset]) | UInt16(zip[offset + 1]) << 8
}

private func testU32(_ zip: Data, _ offset: Int) throws -> UInt32 {
    guard offset >= 0, offset + 4 <= zip.count else { throw TestZipError(message: "zip u32 out of range") }
    return UInt32(zip[offset])
        | UInt32(zip[offset + 1]) << 8
        | UInt32(zip[offset + 2]) << 16
        | UInt32(zip[offset + 3]) << 24
}

private func testData(named name: String, in zip: Data) throws -> Data {
    func eocdOffset() throws -> Int? {
        if zip.count < 22 { return nil }
        var i = zip.count - 22
        let minStart = max(0, zip.count - 22 - 0xFFFF)
        while i >= minStart {
            if try testU32(zip, i) == 0x06054b50 { return i }
            i -= 1
        }
        return nil
    }
    guard let eocd = try eocdOffset() else { throw TestZipError(message: "zip has no EOCD") }
    let cdOffset = Int(try testU32(zip, eocd + 16))
    let cdEntries = Int(try testU16(zip, eocd + 10))
    guard cdOffset >= 0, cdOffset < zip.count, cdEntries > 0 else {
        throw TestZipError(message: "zip central directory invalid")
    }
    var cursor = cdOffset
    for _ in 0..<cdEntries {
        guard try testU32(zip, cursor) == 0x02014b50 else {
            throw TestZipError(message: "zip central directory signature missing")
        }
        let method = try testU16(zip, cursor + 10)
        let compressed = Int(try testU32(zip, cursor + 20))
        let uncompressed = Int(try testU32(zip, cursor + 24))
        let nameLen = Int(try testU16(zip, cursor + 28))
        let extraLen = Int(try testU16(zip, cursor + 30))
        let commentLen = Int(try testU16(zip, cursor + 32))
        let localOff = Int(try testU32(zip, cursor + 42))
        guard cursor + 46 + nameLen <= zip.count else {
            throw TestZipError(message: "zip entry name out of range")
        }
        let entryName = String(decoding: zip.subdata(in: cursor + 46..<cursor + 46 + nameLen), as: UTF8.self)
        cursor += 46 + nameLen + extraLen + commentLen
        guard entryName == name else { continue }
        guard try testU32(zip, localOff) == 0x04034b50 else {
            throw TestZipError(message: "zip local header signature missing")
        }
        let localNameLen = Int(try testU16(zip, localOff + 26))
        let localExtraLen = Int(try testU16(zip, localOff + 28))
        let dataStart = localOff + 30 + localNameLen + localExtraLen
        let dataEnd = dataStart + compressed
        guard dataStart >= 0, dataEnd <= zip.count else {
            throw TestZipError(message: "zip entry data out of range")
        }
        let packed = zip.subdata(in: dataStart..<dataEnd)
        switch method {
        case 0:
            guard packed.count == uncompressed else {
                throw TestZipError(message: "zip stored entry size mismatch")
            }
            return packed
        case 8:
            guard uncompressed > 0 else { throw TestZipError(message: "zip deflate size invalid") }
            var dest = [UInt8](repeating: 0, count: uncompressed)
            let written = packed.withUnsafeBytes { src -> Int in
                guard let srcBase = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return dest.withUnsafeMutableBytes { dst in
                    guard let dstBase = dst.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                    return compression_decode_buffer(
                        dstBase, uncompressed, srcBase, packed.count, nil, COMPRESSION_ZLIB
                    )
                }
            }
            guard written == uncompressed else {
                throw TestZipError(message: "zip deflate wrote \(written) expected \(uncompressed)")
            }
            return Data(dest)
        default:
            throw TestZipError(message: "zip entry method \(method) unsupported")
        }
    }
    throw TestZipError(message: "zip missing '\(name)'")
}

final class CopyFrameUITest: XCTestCase {
    private func frameCount(in atsData: Data?) -> Int? {
        guard let atsData, let xml = try? testData(named: "model.xml", in: atsData) else { return nil }
        var count = 0
        var cursor = 0
        let needle = Data("<frame".utf8)
        while cursor < xml.count {
            let slice = xml[cursor...]
            guard let hit = slice.range(of: needle) else { break }
            count += 1
            // `hit.lowerBound` is already in the original data's coordinates
            // (Data slices keep the original startIndex), so += lowerBound
            // double-counts and skips matches. upperBound is the end of the
            // match in those same coordinates.
            cursor = hit.upperBound
        }
        return count
    }

    /// The UI test bundle cannot read the app's own container directly (the
    /// runner is a separate app). On the simulator the app's data lives under
    /// the shared CoreSimulator Devices tree, so enumerate it and pick the
    /// newest copy of the file. This reads the bytes the app actually wrote.
    private func savedData(named name: String) -> Data? {
        let root = URL(fileURLWithPath: "/Users/zalivka/Library/Developer/CoreSimulator/Devices")
        let fm = FileManager.default
        guard let devices = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        var bestURL: URL?
        var bestDate = Date.distantPast
        for device in devices {
            let candidate = device.appendingPathComponent("data/Containers/Data/Application", isDirectory: true)
            for appContainer in (try? fm.contentsOfDirectory(at: candidate, includingPropertiesForKeys: nil, options: [])) ?? [] {
                let file = appContainer.appendingPathComponent("Library/Application Support/at_elements/saved/\(name).ats")
                guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                      let date = values.contentModificationDate, date > bestDate,
                      (try? Data(contentsOf: file)) != nil
                else { continue }
                bestURL = file
                bestDate = date
            }
        }
        guard let url = bestURL else { return nil }
        return try? Data(contentsOf: url)
    }


    private func saveAsUITestSeed(_ app: XCUIApplication) {
        let menuButton = app.buttons["menu_button"]
        XCTAssertTrue(menuButton.waitForExistence(timeout: 5), "Menu button must exist")
        menuButton.tap()

        let menuSave = app.buttons["menu_save"]
        XCTAssertTrue(menuSave.waitForExistence(timeout: 5), "Save project row must exist")
        menuSave.tap()

        let saveField = app.textFields["save_name_field"]
        XCTAssertTrue(saveField.waitForExistence(timeout: 5), "Save name field must exist")
        if saveField.exists {
            saveField.tap()
            // The field is pre-filled with a generated Cartoon name; delete
            // every character so the save is exactly UITestSeed.
            let prefill = saveField.value as? String ?? ""
            for _ in prefill {
                app.keys["delete"].tap()
            }
            saveField.typeText("UITestSeed")
        }

        let confirm = app.buttons["save_confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Save confirm must exist")
        confirm.tap()
    }


    /// Save writes asynchronously (thumbnail rendering); poll the file until
    /// it holds the expected count, or fail after 10s. Proves the check can
    /// see a file that grows — a fresh reader every poll, no cached state.
    private func waitForFrameCount(_ expected: Int, named name: String) -> Int? {
        let deadline = Date().addingTimeInterval(10)
        var last: Int?
        while Date() < deadline {
            last = frameCount(in: savedData(named: name))
            if last == expected { return last }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return last
    }



    func test_copyFrame3_fourTimes() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-seed"]
        app.launch()

        let load = app.buttons["landing_load"]
        XCTAssertTrue(load.waitForExistence(timeout: 30), "LOAD tab must exist")
        load.tap()

        let cell = app.buttons["savedScene_UITestSeed"]
        XCTAssertTrue(cell.waitForExistence(timeout: 30), "Seeded scene cell must be listed")
        cell.tap()

        let canvas = app.otherElements["editor_canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 30), "Editor canvas must appear after load")

        // If the first-run tutorial is still up, skip it so the frame rail appears.
        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 3) {
            skip.tap()
        }

        // Navigate to frame 3 (index 2)
        let next = app.buttons["frame_next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5), "Next frame button must exist")
        next.tap()
        next.tap()

        // Open EDIT FRAME panel
        let editFrame = app.buttons["main_edit_frame"]
        XCTAssertTrue(editFrame.waitForExistence(timeout: 5), "EDIT FRAME must exist")
        if !editFrame.isSelected { editFrame.tap() }

        // Copy
        let copy = app.buttons["frame_ops_copy"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5), "Copy button must exist")
        copy.tap()

        // 2 pastes, save, count frames in the file.
        let paste = app.buttons["frame_ops_paste"]
        XCTAssertTrue(paste.waitForExistence(timeout: 5), "Paste button must exist after copy")
        XCTAssertTrue(paste.isEnabled, "Paste must be enabled after Copy")
        for _ in 0..<2 {
            paste.tap()
        }
        saveAsUITestSeed(app)
        let framesAfter2 = waitForFrameCount(11, named: "UITestSeed")
        XCTAssertEqual(framesAfter2, 11, "After 2 pastes the file must hold 9 + 2 frames")

        // 2 more pastes (total 4). The save closed the panel; reopen it.
        XCTAssertTrue(editFrame.waitForExistence(timeout: 5), "EDIT FRAME must still exist")
        if !editFrame.isSelected { editFrame.tap() }
        let pasteAgain = app.buttons["frame_ops_paste"]
        XCTAssertTrue(pasteAgain.waitForExistence(timeout: 5), "Paste must exist after reopening EDIT FRAME")
        for _ in 0..<2 {
            pasteAgain.tap()
        }
        saveAsUITestSeed(app)
        let frames = waitForFrameCount(13, named: "UITestSeed")
        XCTAssertEqual(frames, 13, "Saved file must hold 9 original + 4 pasted frames")

        // Validation: screenshot artifact
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "after_paste_4x"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(shot.pngRepresentation.count > 0, "Screenshot must be non-empty")
    }
}
