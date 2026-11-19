import AppKit
import CoreGraphics
import CoreText
import Foundation

public struct DocumentEngine: Sendable {
    private let runner: ProcessExecuting

    public init(runner: ProcessExecuting = ProcessRunner()) {
        self.runner = runner
    }

    public func convertDocument(source: URL, to action: WheelAction, toolPaths: ToolPaths) async throws -> URL {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw WheelError.invalidFile("File not found: \(source.lastPathComponent)")
        }

        if action == .toPDF, let soffice = toolPaths.soffice {
            let outDir = source.deletingLastPathComponent()
            let dest = OutputPathResolver.uniqueFileURL(beside: source, newExtension: "pdf")
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("macwheel-soffice-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            let result = try await runner.run(
                executableURL: soffice,
                arguments: ["--headless", "--convert-to", "pdf", "--outdir", tmpDir.path, source.path]
            )
            let produced = tmpDir.appendingPathComponent(source.deletingPathExtension().lastPathComponent + ".pdf")
            if result.exitCode == 0, FileManager.default.fileExists(atPath: produced.path) {
                try FileManager.default.moveItem(at: produced, to: dest)
                return dest
            }
            _ = outDir
        }

        let attributed = try loadAttributedString(from: source)

        switch action {
        case .toTXT:
            let dest = OutputPathResolver.uniqueFileURL(beside: source, newExtension: "txt")
            try attributed.string.write(to: dest, atomically: true, encoding: .utf8)
            return dest

        case .toRTF:
            let dest = OutputPathResolver.uniqueFileURL(beside: source, newExtension: "rtf")
            let data = try attributed.data(
                from: NSRange(location: 0, length: attributed.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
            try data.write(to: dest, options: .atomic)
            return dest

        case .toHTML:
            let dest = OutputPathResolver.uniqueFileURL(beside: source, newExtension: "html")
            let data = try attributed.data(
                from: NSRange(location: 0, length: attributed.length),
                documentAttributes: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ]
            )
            try data.write(to: dest, options: .atomic)
            return dest

        case .toDOCX:
            let dest = OutputPathResolver.uniqueFileURL(beside: source, newExtension: "docx")
            let data = try attributed.data(
                from: NSRange(location: 0, length: attributed.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]
            )
            try data.write(to: dest, options: .atomic)
            return dest

        case .toPDF:
            let dest = OutputPathResolver.uniqueFileURL(beside: source, newExtension: "pdf")
            try renderAttributedStringToPDF(attributed, destination: dest)
            return dest

        default:
            throw WheelError.unsupportedAction("Unsupported document action: \(action.label)")
        }
    }

    public func extractPlainText(from source: URL) throws -> String {
        try loadAttributedString(from: source).string
    }

    public static func sanitizeHTMLForOffline(_ html: String) -> String {
        var cleaned = html
        let patterns = [
            #"(?is)<script\b[^>]*>.*?</script>"#,
            #"(?is)<link\b[^>]*>"#,
            #"(?i)\b(?:src|href|poster|data)\s*=\s*(?:"(?:https?:|//)[^"]*"|'(?:https?:|//)[^']*')"#,
            #"(?i)url\(\s*["']?(?:https?:|//)[^)]*\)"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(cleaned.startIndex..., in: cleaned)
                cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: "")
            }
        }
        return cleaned
    }

    private func loadAttributedString(from source: URL) throws -> NSAttributedString {
        let ext = source.pathExtension.lowercased()
        if ext == "txt" || ext == "md" || ext == "markdown" || ext == "srt" {
            var enc: String.Encoding = .utf8
            let raw: String
            do {
                raw = try String(contentsOf: source, usedEncoding: &enc)
            } catch {
                throw WheelError.invalidFile("Unable to read text file \(source.lastPathComponent): \(error.localizedDescription)")
            }
            return NSAttributedString(
                string: raw,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12),
                    .foregroundColor: NSColor.black
                ]
            )
        }

        if ext == "html" || ext == "htm" {
            var enc: String.Encoding = .utf8
            guard let rawHTML = try? String(contentsOf: source, usedEncoding: &enc) else {
                throw WheelError.invalidFile("Unable to read HTML file \(source.lastPathComponent)")
            }
            let sanitized = Self.sanitizeHTMLForOffline(rawHTML)
            let tmpHTML = FileManager.default.temporaryDirectory
                .appendingPathComponent("macwheel-html-\(UUID().uuidString).html")
            let tmpRTF = FileManager.default.temporaryDirectory
                .appendingPathComponent("macwheel-html-\(UUID().uuidString).rtf")
            defer {
                try? FileManager.default.removeItem(at: tmpHTML)
                try? FileManager.default.removeItem(at: tmpRTF)
            }
            try sanitized.write(to: tmpHTML, atomically: true, encoding: .utf8)

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
            proc.arguments = ["-convert", "rtf", "-output", tmpRTF.path, tmpHTML.path]
            proc.standardInput = FileHandle.nullDevice
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            try proc.run()
            proc.waitUntilExit()

            if proc.terminationStatus == 0,
               let attr = try? NSAttributedString(
                   url: tmpRTF,
                   options: [.documentType: NSAttributedString.DocumentType.rtf],
                   documentAttributes: nil
               ) {
                return attr
            }
            // Pure offline tag-strip fallback if textutil fails
            let stripped = sanitized.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return NSAttributedString(
                string: stripped,
                attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.black]
            )
        }

        let docType: NSAttributedString.DocumentType? = switch ext {
        case "rtf": .rtf
        case "docx": .officeOpenXML
        case "doc": .docFormat
        default: nil
        }

        var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        if let docType {
            options[.documentType] = docType
        }

        do {
            return try NSAttributedString(url: source, options: options, documentAttributes: nil)
        } catch {
            throw WheelError.invalidFile("Unable to read document \(source.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private func renderAttributedStringToPDF(_ attributed: NSAttributedString, destination: URL) throws {
        let normalized = ensureRenderableAttributes(attributed)
        var mediaBox = CGRect(x: 0, y: 0, width: 595, height: 842)
        let contentRect = CGRect(x: 48, y: 48, width: 595 - 96, height: 842 - 96)

        guard let consumer = CGDataConsumer(url: destination as CFURL),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw WheelError.processFailed("Cannot create PDF output at \(destination.lastPathComponent)")
        }

        let framesetter = CTFramesetterCreateWithAttributedString(normalized as CFAttributedString)
        var location = 0
        let totalLength = normalized.length

        if totalLength == 0 {
            ctx.beginPDFPage(nil)
            ctx.endPDFPage()
            ctx.closePDF()
            return
        }

        while location < totalLength {
            ctx.beginPDFPage(nil)
            ctx.setFillColor(CGColor.white)
            ctx.fill(mediaBox)

            let path = CGMutablePath()
            path.addRect(contentRect)
            let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(location, 0), path, nil)
            CTFrameDraw(frame, ctx)
            let visibleRange = CTFrameGetVisibleStringRange(frame)
            ctx.endPDFPage()

            if visibleRange.length <= 0 {
                break
            }
            location += visibleRange.length
        }

        ctx.closePDF()
    }

    private func ensureRenderableAttributes(_ input: NSAttributedString) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: input)
        let fullRange = NSRange(location: 0, length: mutable.length)
        mutable.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            if value == nil {
                mutable.addAttribute(.font, value: NSFont.systemFont(ofSize: 12), range: range)
            }
        }
        mutable.enumerateAttribute(.foregroundColor, in: fullRange) { value, range, _ in
            if value == nil {
                mutable.addAttribute(.foregroundColor, value: NSColor.black, range: range)
            }
        }
        return mutable
    }
}
