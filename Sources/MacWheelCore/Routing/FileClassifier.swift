import Foundation

public struct WheelResolution: Equatable, Sendable {
    public let categorySummary: String
    public let slices: [WheelAction]
    public let hasSharedActions: Bool

    public init(categorySummary: String, slices: [WheelAction], hasSharedActions: Bool) {
        self.categorySummary = categorySummary
        self.slices = slices
        self.hasSharedActions = hasSharedActions
    }
}

public struct FileClassifier {
    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "webp", "heic", "heif", "tiff", "tif", "bmp", "gif"
    ]
    private static let pdfExtensions: Set<String> = ["pdf"]
    private static let documentExtensions: Set<String> = [
        "docx", "doc", "rtf", "txt", "html", "htm", "md", "markdown"
    ]
    private static let subtitleExtensions: Set<String> = ["srt"]
    private static let videoExtensions: Set<String> = [
        "mov", "mp4", "mkv", "m4v", "webm", "avi"
    ]
    private static let audioExtensions: Set<String> = [
        "mp3", "m4a", "wav", "aac", "flac", "ogg"
    ]

    public static func category(for url: URL) -> FileCategory {
        let ext = url.pathExtension.lowercased()
        if imageExtensions.contains(ext) { return .image }
        if pdfExtensions.contains(ext) { return .pdf }
        if documentExtensions.contains(ext) { return .document }
        if subtitleExtensions.contains(ext) { return .subtitle }
        if videoExtensions.contains(ext) { return .video }
        if audioExtensions.contains(ext) { return .audio }
        return .unknown
    }

    public static func resolveWheel(for urls: [URL]) -> WheelResolution {
        guard !urls.isEmpty else {
            return WheelResolution(categorySummary: "No Files", slices: [], hasSharedActions: false)
        }

        let categories = urls.map { category(for: $0) }
        if categories.contains(.unknown) {
            return WheelResolution(categorySummary: "Unsupported", slices: [], hasSharedActions: false)
        }

        let uniqueCategories = Set(categories)
        let countLabel = urls.count == 1 ? urls[0].pathExtension.uppercased() : "\(urls.count) files"

        if uniqueCategories.count == 1, let singleCategory = uniqueCategories.first {
            let slices = actions(forSingleCategory: singleCategory, count: urls.count)
            let summary = urls.count == 1 ? (countLabel.isEmpty ? singleCategory.rawValue.uppercased() : countLabel) : "\(urls.count) \(singleCategory.rawValue.uppercased())s"
            return WheelResolution(categorySummary: summary, slices: Array(slices.prefix(7)), hasSharedActions: !slices.isEmpty)
        }

        if uniqueCategories == [.image, .pdf] {
            let slices: [WheelAction] = [.mergePDF, .compress, .toJPG, .toPNG]
            return WheelResolution(categorySummary: "\(urls.count) Mixed", slices: slices, hasSharedActions: true)
        }

        // Strict intersection for other mixed types.
        let orderedCanonical: [WheelAction] = [
            .compress, .transcribe, .toMP4, .toMOV, .toMP3, .toM4A, .toWAV, .toGIF,
            .toJPG, .toPNG, .toWEBP, .toPDF, .toDOCX, .toTXT, .toRTF, .toHTML,
            .translateTH, .translateEN
        ]
        var intersection = Set(actions(forSingleCategory: categories[0], count: 1))
        for cat in categories.dropFirst() {
            intersection.formIntersection(actions(forSingleCategory: cat, count: 1))
        }
        let slices = Array(orderedCanonical.filter { intersection.contains($0) }.prefix(7))
        let summary = slices.isEmpty ? "Mixed" : "\(urls.count) Mixed"
        return WheelResolution(categorySummary: summary, slices: slices, hasSharedActions: !slices.isEmpty)
    }

    private static func actions(forSingleCategory category: FileCategory, count: Int) -> [WheelAction] {
        switch category {
        case .video:
            return [.toMP4, .toMOV, .toMP3, .toM4A, .toGIF, .transcribe, .compress]
        case .audio:
            return [.toMP3, .toM4A, .toWAV, .transcribe, .compress]
        case .image:
            if count >= 2 {
                return [.mergePDF, .toJPG, .toPNG, .toWEBP, .compress]
            }
            return [.toJPG, .toPNG, .toWEBP, .toPDF, .compress]
        case .pdf:
            if count >= 2 {
                return [.mergePDF, .compress, .toJPG, .toPNG, .toDOCX, .toTXT, .translateTH]
            }
            return [.compress, .toJPG, .toPNG, .toDOCX, .toTXT, .translateTH, .translateEN]
        case .document:
            return [.toPDF, .toDOCX, .toTXT, .toRTF, .toHTML, .translateTH, .translateEN]
        case .subtitle:
            return [.translateTH, .translateEN, .toTXT]
        case .unknown:
            return []
        }
    }
}
