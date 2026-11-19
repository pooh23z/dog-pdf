import Foundation
import NaturalLanguage
import Translation

public struct SRTCue: Equatable, Sendable {
    public let index: String
    public let timestamp: String
    public let textLines: [String]

    public init(index: String, timestamp: String, textLines: [String]) {
        self.index = index
        self.timestamp = timestamp
        self.textLines = textLines
    }
}

public enum TranslationLanguage: String, Sendable, Equatable {
    case th
    case en

    public var outputSuffix: String {
        switch self {
        case .th: return " TH"
        case .en: return " EN"
        }
    }

    public var sourceCode: String {
        switch self {
        case .th: return "en"
        case .en: return "th"
        }
    }
}

public protocol TextTranslating: Sendable {
    func translate(_ texts: [String], to target: TranslationLanguage) async throws -> [String]
}

public struct AppleTranslationProvider: TextTranslating {
    public init() {}

    public func translate(_ texts: [String], to target: TranslationLanguage) async throws -> [String] {
        guard !texts.isEmpty else { return [] }

        if #available(macOS 26.0, *) {
            let detectedSource = detectSourceLanguage(in: texts, target: target)
            let sourceLang = Locale.Language(identifier: detectedSource)
            let targetLang = Locale.Language(identifier: target.rawValue)

            if detectedSource == target.rawValue {
                return texts
            }

            let availability = LanguageAvailability()
            let status = await availability.status(from: sourceLang, to: targetLang)
            guard status == .installed else {
                throw WheelError.missingTranslationPack(
                    "Offline translation pack (\(detectedSource.uppercased()) → \(target.rawValue.uppercased())) is not downloaded. Go to System Settings → General → Language & Region → Translation Languages and download Thai & English."
                )
            }

            // Reuse a single TranslationSession for all batches of this file.
            let session = TranslationSession(installedSource: sourceLang, target: targetLang)
            var results = texts

            var batchIndices: [Int] = []
            var batchRequests: [TranslationSession.Request] = []
            var batchChars = 0

            func flushBatch() async throws {
                guard !batchRequests.isEmpty else { return }
                let responses = try await session.translations(from: batchRequests)
                for (offset, response) in responses.enumerated() {
                    if let cid = response.clientIdentifier, let exactIndex = Int(cid), exactIndex >= 0, exactIndex < results.count {
                        results[exactIndex] = response.targetText
                    } else if offset < batchIndices.count {
                        results[batchIndices[offset]] = response.targetText
                    }
                }
                batchIndices.removeAll(keepingCapacity: true)
                batchRequests.removeAll(keepingCapacity: true)
                batchChars = 0
            }

            for (idx, text) in texts.enumerated() {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    results[idx] = text
                    continue
                }
                if !batchRequests.isEmpty && (batchChars + text.count > 1500 || batchRequests.count >= 20) {
                    try await flushBatch()
                }
                batchIndices.append(idx)
                batchRequests.append(TranslationSession.Request(sourceText: text, clientIdentifier: "\(idx)"))
                batchChars += text.count
            }
            try await flushBatch()
            return results
        } else {
            throw WheelError.missingTranslationPack("Offline Apple Translation requires macOS 26 or newer.")
        }
    }

    private func detectSourceLanguage(in texts: [String], target: TranslationLanguage) -> String {
        let sample = texts.prefix(12).joined(separator: "\n").prefix(2000)
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(sample))
        if let dominant = recognizer.dominantLanguage, dominant != .undetermined {
            let code = dominant.rawValue
            if !code.isEmpty {
                return code
            }
        }
        return target.sourceCode
    }
}

public struct TranslationEngine: Sendable {
    private let pdfEngine: PDFEngine
    private let documentEngine: DocumentEngine
    private static let maxChunkLength = 1400

    public init(pdfEngine: PDFEngine = PDFEngine(), documentEngine: DocumentEngine = DocumentEngine()) {
        self.pdfEngine = pdfEngine
        self.documentEngine = documentEngine
    }

    public static func parseSRT(_ raw: String) -> [SRTCue] {
        var cleaned = raw
        if cleaned.hasPrefix("\u{FEFF}") {
            cleaned.removeFirst()
        }
        let normalized = cleaned
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // Split into blocks separated by lines that are empty or whitespace-only.
        var blocks: [[String]] = []
        var current: [String] = []
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !current.isEmpty {
                    blocks.append(current)
                    current.removeAll(keepingCapacity: true)
                }
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty {
            blocks.append(current)
        }

        var cues: [SRTCue] = []
        for arr in blocks {
            guard arr.count >= 2 else { continue }
            if arr[1].contains("-->") {
                let textLines = arr.count > 2 ? Array(arr[2...]) : []
                cues.append(SRTCue(index: arr[0].trimmingCharacters(in: .whitespaces), timestamp: arr[1], textLines: textLines))
            }
        }
        return cues
    }

    public static func formatSRT(_ cues: [SRTCue]) -> String {
        cues.map { cue in
            ([cue.index, cue.timestamp] + cue.textLines).joined(separator: "\n")
        }.joined(separator: "\n\n") + "\n"
    }

    public func translateFile(
        source: URL,
        to target: TranslationLanguage,
        translator: TextTranslating,
        toolPaths: ToolPaths
    ) async throws -> URL {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw WheelError.invalidFile("File not found: \(source.lastPathComponent)")
        }

        let ext = source.pathExtension.lowercased()
        if ext == "srt" {
            let raw = try readTextWithFallbackEncoding(from: source)
            let cues = Self.parseSRT(raw)
            guard !cues.isEmpty else {
                throw WheelError.invalidFile("No valid subtitle cues found in \(source.lastPathComponent).")
            }
            let allLines = cues.flatMap { $0.textLines }
            let translatedLines = try await translator.translate(allLines, to: target)

            var cursor = 0
            var newCues: [SRTCue] = []
            for cue in cues {
                let count = cue.textLines.count
                let slice = Array(translatedLines[cursor..<min(cursor + count, translatedLines.count)])
                cursor += count
                newCues.append(SRTCue(index: cue.index, timestamp: cue.timestamp, textLines: slice))
            }

            let dest = OutputPathResolver.uniqueFileURL(beside: source, suffix: target.outputSuffix, newExtension: "srt")
            try Self.formatSRT(newCues).write(to: dest, atomically: true, encoding: .utf8)
            return dest
        }

        let extractedText: String
        if FileClassifier.category(for: source) == .pdf {
            extractedText = try await pdfEngine.extractTextOrOCR(pdfURL: source)
        } else {
            extractedText = try documentEngine.extractPlainText(from: source)
        }

        var normalized = extractedText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if normalized.hasPrefix("\u{FEFF}") {
            normalized.removeFirst()
        }

        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WheelError.invalidFile("No readable text found in \(source.lastPathComponent).")
        }

        let (chunks, separators) = splitDocumentIntoBoundedChunks(normalized, maxChars: Self.maxChunkLength)
        let translatedChunks = try await translator.translate(chunks, to: target)

        var rebuilt = ""
        for idx in 0..<translatedChunks.count {
            rebuilt += translatedChunks[idx]
            if idx < separators.count {
                rebuilt += separators[idx]
            }
        }

        let dest = OutputPathResolver.uniqueFileURL(beside: source, suffix: target.outputSuffix, newExtension: "txt")
        try rebuilt.write(to: dest, atomically: true, encoding: .utf8)
        _ = toolPaths
        return dest
    }

    private func readTextWithFallbackEncoding(from url: URL) throws -> String {
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            return utf8
        }
        var detected: String.Encoding = .utf8
        if let decoded = try? String(contentsOf: url, usedEncoding: &detected) {
            return decoded
        }
        throw WheelError.invalidFile("Unable to decode text file \(url.lastPathComponent).")
    }

    /// Splits a document into chunks each <= `maxChars` while preserving paragraph (`\n\n`)
    /// and line (`\n`) separators so single-newline PDFs/DOCXs never produce giant requests.
    private func splitDocumentIntoBoundedChunks(_ text: String, maxChars: Int) -> (chunks: [String], separators: [String]) {
        let paragraphs = text.components(separatedBy: "\n\n")
        var chunks: [String] = []
        var separators: [String] = []

        for (pIndex, paragraph) in paragraphs.enumerated() {
            let subChunks = splitOversizedParagraph(paragraph, maxChars: maxChars)
            for (sIndex, sub) in subChunks.enumerated() {
                chunks.append(sub)
                if sIndex + 1 < subChunks.count {
                    separators.append("\n")
                } else if pIndex + 1 < paragraphs.count {
                    separators.append("\n\n")
                }
            }
        }
        return (chunks, separators)
    }

    private func splitOversizedParagraph(_ paragraph: String, maxChars: Int) -> [String] {
        guard paragraph.count > maxChars else { return [paragraph] }

        let lines = paragraph.components(separatedBy: "\n")
        var result: [String] = []
        var current = ""

        for line in lines {
            if line.count > maxChars {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
                result.append(contentsOf: hardWrapLine(line, maxChars: maxChars))
                continue
            }
            let candidate = current.isEmpty ? line : (current + "\n" + line)
            if candidate.count > maxChars {
                result.append(current)
                current = line
            } else {
                current = candidate
            }
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    private func hardWrapLine(_ line: String, maxChars: Int) -> [String] {
        var pieces: [String] = []
        var start = line.startIndex
        while start < line.endIndex {
            let end = line.index(start, offsetBy: maxChars, limitedBy: line.endIndex) ?? line.endIndex
            if end < line.endIndex, let space = line[start..<end].lastIndex(of: " "), space > start {
                pieces.append(String(line[start..<space]))
                start = line.index(after: space)
            } else {
                pieces.append(String(line[start..<end]))
                start = end
            }
        }
        return pieces
    }
}
