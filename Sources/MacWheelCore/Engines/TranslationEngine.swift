import Foundation
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
            let sourceLang = Locale.Language(identifier: target.sourceCode)
            let targetLang = Locale.Language(identifier: target.rawValue)
            let availability = LanguageAvailability()
            let status = await availability.status(from: sourceLang, to: targetLang)
            guard status == .installed else {
                throw WheelError.missingTranslationPack(
                    "Offline translation pack (\(target.sourceCode.uppercased()) → \(target.rawValue.uppercased())) is not downloaded. Go to System Settings → General → Language & Region → Translation Languages and download Thai & English."
                )
            }

            let session = TranslationSession(installedSource: sourceLang, target: targetLang)
            var results = Array(repeating: "", count: texts.count)

            var batchIndices: [Int] = []
            var batchRequests: [TranslationSession.Request] = []
            var batchChars = 0

            func flushBatch() async throws {
                guard !batchRequests.isEmpty else { return }
                let responses = try await session.translations(from: batchRequests)
                for (offset, response) in responses.enumerated() {
                    if offset < batchIndices.count {
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
}

public struct TranslationEngine: Sendable {
    private let pdfEngine: PDFEngine
    private let documentEngine: DocumentEngine

    public init(pdfEngine: PDFEngine = PDFEngine(), documentEngine: DocumentEngine = DocumentEngine()) {
        self.pdfEngine = pdfEngine
        self.documentEngine = documentEngine
    }

    public static func parseSRT(_ raw: String) -> [SRTCue] {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")
        var cues: [SRTCue] = []

        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                .drop(while: { $0.trimmingCharacters(in: .whitespaces).isEmpty })
            let arr = Array(lines)
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
            let raw = try String(contentsOf: source, encoding: .utf8)
            let cues = Self.parseSRT(raw)
            let allLines = cues.flatMap { $0.textLines }
            let translatedLines = try await translateInChunks(allLines, to: target, translator: translator)

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

        let trimmed = extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw WheelError.invalidFile("No readable text found in \(source.lastPathComponent).")
        }

        let normalized = extractedText.replacingOccurrences(of: "\r\n", with: "\n")
        let paragraphs = normalized.components(separatedBy: "\n\n")
        let translatedParagraphs = try await translateInChunks(paragraphs, to: target, translator: translator)

        let dest = OutputPathResolver.uniqueFileURL(beside: source, suffix: target.outputSuffix, newExtension: "txt")
        try translatedParagraphs.joined(separator: "\n\n").write(to: dest, atomically: true, encoding: .utf8)
        _ = toolPaths
        return dest
    }

    private func translateInChunks(
        _ items: [String],
        to target: TranslationLanguage,
        translator: TextTranslating
    ) async throws -> [String] {
        var output: [String] = []
        output.reserveCapacity(items.count)

        var currentBatch: [String] = []
        var currentChars = 0

        func flush() async throws {
            guard !currentBatch.isEmpty else { return }
            let translated = try await translator.translate(currentBatch, to: target)
            output.append(contentsOf: translated)
            currentBatch.removeAll(keepingCapacity: true)
            currentChars = 0
        }

        for item in items {
            if !currentBatch.isEmpty && (currentChars + item.count > 1500 || currentBatch.count >= 25) {
                try await flush()
            }
            currentBatch.append(item)
            currentChars += item.count
        }
        try await flush()
        return output
    }
}
