import Foundation

/// Headless Date Shift checks. Run with `RightClickNinja --dateshift-selftest`.
enum DateShiftSelfTest {
    static func run() -> Int32 {
        var failures = 0
        func check(_ condition: Bool, _ label: String) {
            print("\(condition ? "  ok  " : "  FAIL") \(label)")
            if !condition { failures += 1 }
        }

        let offset = DateShiftOffset(days: 2, hours: -3, minutes: 15)
        check(offset.timeInterval == TimeInterval(2 * 86_400 - 3 * 3_600 + 15 * 60), "offset seconds")
        check(offset.exifShift == "0:0:1 21:15:0", "exif shift uses net duration")

        let negative = DateShiftOffset(days: -1, hours: 0, minutes: 0)
        check(negative.exifShift.hasPrefix("-"), "negative offset prefixes ExifTool shift")

        let parsed = DateShiftEngine.parseExif("2024:03:15 14:30:00")
        check(parsed != nil, "parses EXIF DateTimeOriginal")

        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("rcn-dateshift-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }

            var file = dir.appendingPathComponent("sample.txt")
            try "hello".write(to: file, atomically: true, encoding: .utf8)

            var values = URLResourceValues()
            let original = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14
            values.creationDate = original
            values.contentModificationDate = original
            try file.setResourceValues(values)

            let collected = DateShiftEngine.collect(paths: [dir.path])
            check(collected.contains(file.path), "collects files inside a dropped folder")

            let before = try DateShiftEngine.snapshot(path: file.path)
            check(abs(before.created.timeIntervalSince(original)) < 2, "creation date round-trips")

            let shift = DateShiftOffset(days: 1, hours: 0, minutes: 0)
            let result = try DateShiftEngine.apply(
                paths: [file.path],
                offset: shift,
                targets: DateShiftTargets(created: true, modified: true, accessed: true, embedded: false),
                exiftoolPath: nil
            )
            check(result.updated == 1 && result.failed == 0, "filesystem apply updates one file")

            let after = try DateShiftEngine.snapshot(path: file.path)
            let createdDelta = after.created.timeIntervalSince(before.created)
            let modifiedDelta = after.modified.timeIntervalSince(before.modified)
            check(abs(createdDelta - 86_400) < 2, "created shifted by one day (delta \(Int(createdDelta))s)")
            check(abs(modifiedDelta - 86_400) < 2, "modified shifted by one day (delta \(Int(modifiedDelta))s)")

            if let exif = DateShiftEngine.resolvedExiftoolPath() {
                print("  info ExifTool at \(exif)")
                let jpeg = dir.appendingPathComponent("tiny.jpg")
                try minimalJPEG.write(to: jpeg)
                if let warning = DateShiftEngine.runExifShift(
                    paths: [jpeg.path],
                    shift: "0:0:1 0:0:0",
                    exiftoolPath: exif
                ) {
                    print("  FAIL ExifTool shift: \(warning)")
                    failures += 1
                } else {
                    print("  ok   ExifTool shift ran")
                }
            } else {
                print("  skip ExifTool not bundled in this test binary")
            }
        } catch {
            print("  FAIL \(error)")
            failures += 1
        }

        print(failures == 0 ? "\nDate Shift self-tests passed." : "\n\(failures) Date Shift self-test(s) failed.")
        return failures == 0 ? 0 : 1
    }

    /// 1×1 JPEG so ExifTool has a real file to stamp.
    private static var minimalJPEG: Data {
        Data([
            0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
            0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
            0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07, 0x07, 0x07, 0x09,
            0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D, 0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12,
            0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E, 0x1D, 0x1A, 0x1C, 0x1C, 0x20,
            0x24, 0x2E, 0x27, 0x20, 0x22, 0x2C, 0x23, 0x1C, 0x1C, 0x28, 0x37, 0x29,
            0x2C, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1F, 0x27, 0x39, 0x3D, 0x38, 0x32,
            0x3C, 0x2E, 0x33, 0x34, 0x32, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01,
            0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x14, 0x00, 0x01,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x09, 0xFF, 0xC4, 0x00, 0x14, 0x10, 0x01, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00,
            0x7F, 0xFF, 0xD9
        ])
    }
}
