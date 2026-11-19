import Foundation

public struct JobResult: Sendable, Equatable {
    public let outputURLs: [URL]
    public let summary: String

    public init(outputURLs: [URL], summary: String) {
        self.outputURLs = outputURLs
        self.summary = summary
    }
}

public actor JobExecutor {
    private let imageEngine: ImageEngine
    private let pdfEngine: PDFEngine
    private let documentEngine: DocumentEngine
    private let mediaEngine: MediaEngine
    private let translationEngine: TranslationEngine
    private let translator: TextTranslating

    public init(
        runner: ProcessExecuting = ProcessRunner(),
        translator: TextTranslating = AppleTranslationProvider()
    ) {
        self.imageEngine = ImageEngine(runner: runner)
        self.pdfEngine = PDFEngine()
        self.documentEngine = DocumentEngine(runner: runner)
        self.mediaEngine = MediaEngine(runner: runner)
        self.translationEngine = TranslationEngine(pdfEngine: self.pdfEngine, documentEngine: self.documentEngine)
        self.translator = translator
    }

    public func execute(
        urls: [URL],
        action: WheelAction,
        settings: AppSettings,
        toolPaths: ToolPaths = OutputPathResolver.discoverTools(),
        progress: @Sendable (String) -> Void
    ) async throws -> JobResult {
        guard !urls.isEmpty else {
            throw WheelError.invalidFile("No files selected.")
        }

        if action == .mergePDF {
            progress("Merging \(urls.count) files into PDF…")
            let merged = try await imageEngine.mergeToPDF(sources: urls)
            return JobResult(outputURLs: [merged], summary: "Merged \(urls.count) files → \(merged.lastPathComponent)")
        }

        var outputs: [URL] = []
        for (idx, url) in urls.enumerated() {
            try Task.checkCancellation()
            let prefix = urls.count > 1 ? "(\(idx + 1)/\(urls.count)) " : ""
            progress("\(prefix)\(action.label): \(url.lastPathComponent)…")

            if action == .translateTH || action == .translateEN {
                let lang: TranslationLanguage = action == .translateTH ? .th : .en
                let out = try await translationEngine.translateFile(
                    source: url,
                    to: lang,
                    translator: translator,
                    toolPaths: toolPaths
                )
                outputs.append(out)
                continue
            }

            if action == .transcribe {
                let result = try await mediaEngine.transcribeMedia(
                    source: url,
                    language: settings.whisperLanguage,
                    toolPaths: toolPaths
                )
                outputs.append(result.txtURL)
                outputs.append(result.srtURL)
                continue
            }

            let category = FileClassifier.category(for: url)
            switch category {
            case .image:
                let out = try await imageEngine.convertImage(
                    source: url,
                    to: action,
                    preset: settings.compressionPreset,
                    targetFileSize: settings.targetFileSize,
                    toolPaths: toolPaths
                )
                outputs.append(out)

            case .pdf:
                let out: URL
                switch action {
                case .toJPG, .toPNG:
                    out = try await pdfEngine.exportPagesAsImages(pdfURL: url, format: action)
                case .toTXT:
                    out = try await pdfEngine.exportPDFToTXT(pdfURL: url)
                case .toDOCX:
                    out = try await pdfEngine.exportPDFToDOCX(pdfURL: url)
                case .compress:
                    out = try await pdfEngine.compressPDF(
                        pdfURL: url,
                        preset: settings.compressionPreset,
                        targetFileSize: settings.targetFileSize
                    )
                default:
                    throw WheelError.unsupportedAction("Action \(action.label) is not supported for PDF.")
                }
                outputs.append(out)

            case .document, .subtitle:
                let out = try await documentEngine.convertDocument(
                    source: url,
                    to: action,
                    toolPaths: toolPaths
                )
                outputs.append(out)

            case .video, .audio:
                let out = try await mediaEngine.convertOrCompressMedia(
                    source: url,
                    action: action,
                    preset: settings.compressionPreset,
                    toolPaths: toolPaths
                )
                outputs.append(out)

            case .unknown:
                throw WheelError.unsupportedAction("Unsupported file type: \(url.lastPathComponent)")
            }
        }

        let summary: String
        if outputs.count == 1 {
            if action == .compress, urls.count == 1,
               let inBytes = fileSize(urls[0]), let outBytes = fileSize(outputs[0]) {
                summary = "\(outputs[0].lastPathComponent) (\(formatReadableByteCount(inBytes)) → \(formatReadableByteCount(outBytes)))"
            } else {
                summary = "Saved \(outputs[0].lastPathComponent)"
            }
        } else {
            summary = "Saved \(outputs.count) items"
        }
        return JobResult(outputURLs: outputs, summary: summary)
    }

    private func fileSize(_ url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }
}
