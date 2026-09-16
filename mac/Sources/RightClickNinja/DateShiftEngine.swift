import Foundation
import ImageIO
import AVFoundation
import CoreServices
import Darwin

struct DateShiftOffset: Equatable {
    var days: Int = 0
    var hours: Int = 0
    var minutes: Int = 0

    var timeInterval: TimeInterval {
        TimeInterval(days * 86_400 + hours * 3_600 + minutes * 60)
    }

    var isZero: Bool { days == 0 && hours == 0 && minutes == 0 }

    var display: String {
        let sign = timeInterval >= 0 ? "+" : ""
        return "\(sign)\(days)d \(hours)h \(minutes)m"
    }

    /// ExifTool `+=` body: `0:0:D H:M:0` or `-0:0:D H:M:0` from the net duration.
    var exifShift: String {
        var interval = timeInterval
        let negative = interval < 0
        if negative { interval = -interval }
        let totalMinutes = Int((interval / 60).rounded())
        let shiftDays = totalMinutes / (24 * 60)
        let shiftHours = (totalMinutes % (24 * 60)) / 60
        let shiftMinutes = totalMinutes % 60
        let body = "0:0:\(shiftDays) \(shiftHours):\(shiftMinutes):0"
        return negative ? "-\(body)" : body
    }
}

struct DateShiftTargets: Equatable {
    var created = true
    var modified = true
    var accessed = false
    var embedded = true

    var noneSelected: Bool { !created && !modified && !accessed && !embedded }

    var summary: String {
        var parts: [String] = []
        if embedded { parts.append("Embedded") }
        if created { parts.append("Created") }
        if modified { parts.append("Modified") }
        if accessed { parts.append("Accessed") }
        return parts.isEmpty ? "(nothing checked)" : parts.joined(separator: ", ")
    }
}

struct EmbeddedDate {
    var value: Date?
    var kind: String
    var display: String
}

struct FileDateSnapshot {
    let path: String
    let name: String
    let created: Date
    let modified: Date
    let accessed: Date
    let embedded: EmbeddedDate
}

struct DateShiftApplyResult {
    var updated: Int = 0
    var failed: Int = 0
    var exifWarning: String?
}

enum DateShiftEngine {
    static func collect(paths: [String]) -> [String] {
        var files: [String] = []
        var seen = Set<String>()
        let fm = FileManager.default
        for raw in paths {
            let path = (raw as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                if let enumerator = fm.enumerator(atPath: path) {
                    for case let relative as String in enumerator {
                        let full = (path as NSString).appendingPathComponent(relative)
                        var innerDir: ObjCBool = false
                        if fm.fileExists(atPath: full, isDirectory: &innerDir), !innerDir.boolValue {
                            if seen.insert(full).inserted { files.append(full) }
                        }
                    }
                }
            } else if fm.fileExists(atPath: path) {
                if seen.insert(path).inserted { files.append(path) }
            }
        }
        return files
    }

    static func snapshot(path: String) throws -> FileDateSnapshot {
        let url = URL(fileURLWithPath: path)
        let values = try url.resourceValues(forKeys: [
            .creationDateKey, .contentModificationDateKey, .contentAccessDateKey, .nameKey
        ])
        let created = values.creationDate ?? Date()
        let modified = values.contentModificationDate ?? created
        let accessed = values.contentAccessDate ?? modified
        return FileDateSnapshot(
            path: path,
            name: values.name ?? url.lastPathComponent,
            created: created,
            modified: modified,
            accessed: accessed,
            embedded: readEmbeddedDate(url: url)
        )
    }

    static func preview(_ date: Date, offset: DateShiftOffset) -> Date {
        date.addingTimeInterval(offset.timeInterval)
    }

    static func format(_ date: Date) -> String {
        Self.stamp.string(from: date)
    }

    static func apply(paths: [String],
                      offset: DateShiftOffset,
                      targets: DateShiftTargets,
                      exiftoolPath: String?) throws -> DateShiftApplyResult {
        var result = DateShiftApplyResult()
        if targets.embedded {
            if let exiftoolPath, FileManager.default.isExecutableFile(atPath: exiftoolPath)
                || FileManager.default.fileExists(atPath: exiftoolPath) {
                if let warning = runExifShift(paths: paths, shift: offset.exifShift, exiftoolPath: exiftoolPath) {
                    result.exifWarning = warning
                }
            } else {
                result.exifWarning = "Embedded media dates need ExifTool next to this app."
            }
        }

        for path in paths {
            do {
                let snap = try snapshot(path: path)
                var url = URL(fileURLWithPath: path)
                var values = URLResourceValues()
                if targets.created {
                    values.creationDate = preview(snap.created, offset: offset)
                }
                if targets.modified {
                    values.contentModificationDate = preview(snap.modified, offset: offset)
                }
                try url.setResourceValues(values)
                if targets.accessed {
                    try setAccessDate(url, preview(snap.accessed, offset: offset))
                }
                result.updated += 1
            } catch {
                result.failed += 1
            }
        }
        return result
    }

    static func resolvedExiftoolPath() -> String? {
        let candidates: [String] = [
            Bundle.main.resourceURL?.appendingPathComponent("exiftool/exiftool").path,
            Bundle.main.bundleURL
                .appendingPathComponent("Contents/Resources/exiftool/exiftool").path,
            "/opt/homebrew/bin/exiftool",
            "/usr/local/bin/exiftool"
        ].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) || FileManager.default.fileExists(atPath: $0) }
    }

    // MARK: - Embedded preview

    static func readEmbeddedDate(url: URL) -> EmbeddedDate {
        if let date = readExifDate(url: url) {
            return EmbeddedDate(value: date, kind: "Date taken",
                                display: "\(format(date)) (Date taken)")
        }
        if let date = readQuickTimeDate(url: url) {
            return EmbeddedDate(value: date, kind: "Media created",
                                display: "\(format(date)) (Media created)")
        }
        if let date = readSpotlightContentCreation(url: url) {
            return EmbeddedDate(value: date, kind: "Content created",
                                display: "\(format(date)) (Content created)")
        }
        return EmbeddedDate(value: nil, kind: "", display: "(none)")
    }

    private static func readExifDate(url: URL) -> Date? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            for key in [kCGImagePropertyExifDateTimeOriginal, kCGImagePropertyExifDateTimeDigitized] {
                if let raw = exif[key] as? String, let date = parseExif(raw) { return date }
            }
        }
        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
           let raw = tiff[kCGImagePropertyTIFFDateTime] as? String,
           let date = parseExif(raw) {
            return date
        }
        return nil
    }

    private static func readQuickTimeDate(url: URL) -> Date? {
        let asset = AVURLAsset(url: url)
        let items = AVMetadataItem.metadataItems(from: asset.commonMetadata, filteredByIdentifier: .commonIdentifierCreationDate)
        if let date = items.first?.dateValue { return date }
        if let string = items.first?.stringValue, let date = parseExif(string) ?? ISO8601DateFormatter().date(from: string) {
            return date
        }
        return nil
    }

    private static func readSpotlightContentCreation(url: URL) -> Date? {
        guard let item = MDItemCreate(kCFAllocatorDefault, url.path as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemContentCreationDate) as? Date
    }

    static func parseExif(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let formats = [
            "yyyy:MM:dd HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy:MM:dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss"
        ]
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone.current
        for format in formats {
            parser.dateFormat = format
            if let date = parser.date(from: String(trimmed.prefix(19))) { return date }
        }
        return nil
    }

    // MARK: - Filesystem access time

    static func setAccessDate(_ url: URL, _ date: Date) throws {
        var list = attrlist()
        list.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        list.commonattr = attrgroup_t(ATTR_CMN_ACCTIME)
        var ts = timespecFrom(date)
        let status = url.path.withCString { path in
            setattrlist(path, &list, &ts, MemoryLayout<timespec>.size, 0)
        }
        if status != 0 {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
                          userInfo: [NSLocalizedDescriptionKey: "Could not set accessed date"])
        }
    }

    private static func timespecFrom(_ date: Date) -> timespec {
        let seconds = date.timeIntervalSince1970
        var ts = timespec()
        ts.tv_sec = time_t(seconds)
        ts.tv_nsec = Int((seconds - floor(seconds)) * 1_000_000_000)
        return ts
    }

    // MARK: - ExifTool

    static func runExifShift(paths: [String], shift: String, exiftoolPath: String) -> String? {
        let argFile = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rcn-files-\(UUID().uuidString).txt")
        do {
            try paths.joined(separator: "\n").write(to: argFile, atomically: true, encoding: .utf8)
        } catch {
            return "Could not write ExifTool argument file: \(error.localizedDescription)"
        }
        defer { try? FileManager.default.removeItem(at: argFile) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [
            exiftoolPath,
            "-overwrite_original",
            "-P",
            "-AllDates+=\(shift)",
            "-MediaCreateDate+=\(shift)",
            "-MediaModifyDate+=\(shift)",
            "-TrackCreateDate+=\(shift)",
            "-TrackModifyDate+=\(shift)",
            "-charset", "filename=utf8",
            "-@", argFile.path
        ]
        process.currentDirectoryURL = URL(fileURLWithPath: exiftoolPath).deletingLastPathComponent()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return "ExifTool failed: \(error.localizedDescription)"
        }
        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        // 0 = ok, 1 = warnings, 2+ = error
        if process.terminationStatus > 1 {
            return (err + "\n" + out).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
