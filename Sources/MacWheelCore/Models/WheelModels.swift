import Foundation

public enum AppBranding {
    public static let displayName = "Dog PDF"
    public static let bundleIdentifier = "com.personal.dogpdf"
    public static let menuBarSymbolName = "dog.fill"
}

public enum FileCategory: String, CaseIterable, Sendable {
    case image
    case pdf
    case document
    case video
    case audio
    case subtitle
    case unknown
}

public enum WheelAction: String, CaseIterable, Sendable, Identifiable {
    case toJPG
    case toPNG
    case toWEBP
    case toPDF
    case mergePDF
    case toDOCX
    case toTXT
    case toRTF
    case toHTML
    case toMP4
    case toMOV
    case toMP3
    case toM4A
    case toWAV
    case toGIF
    case transcribe
    case compress
    case translateTH
    case translateEN

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .toJPG: return "JPG"
        case .toPNG: return "PNG"
        case .toWEBP: return "WEBP"
        case .toPDF: return "PDF"
        case .mergePDF: return "Merge PDF"
        case .toDOCX: return "DOCX"
        case .toTXT: return "TXT"
        case .toRTF: return "RTF"
        case .toHTML: return "HTML"
        case .toMP4: return "MP4"
        case .toMOV: return "MOV"
        case .toMP3: return "MP3"
        case .toM4A: return "M4A"
        case .toWAV: return "WAV"
        case .toGIF: return "GIF"
        case .transcribe: return "Transcribe"
        case .compress: return "Compress"
        case .translateTH: return "→TH"
        case .translateEN: return "→EN"
        }
    }

    public var symbolName: String {
        switch self {
        case .toJPG, .toPNG, .toWEBP: return "photo"
        case .toPDF: return "doc.richtext"
        case .mergePDF: return "square.stack.3d.up"
        case .toDOCX, .toTXT, .toRTF: return "doc.text"
        case .toHTML: return "chevron.left.forwardslash.chevron.right"
        case .toMP4, .toMOV: return "film"
        case .toMP3, .toM4A, .toWAV: return "waveform"
        case .toGIF: return "sparkles.rectangle.stack"
        case .transcribe: return "captions.bubble"
        case .compress: return "arrow.down.right.and.arrow.up.left"
        case .translateTH, .translateEN: return "character.book.closed"
        }
    }
}

public enum CompressionPreset: String, CaseIterable, Sendable, Codable, Identifiable {
    case balanced
    case small
    case highQuality

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .balanced: return "Balanced"
        case .small: return "Small"
        case .highQuality: return "High Quality"
        }
    }
}

public enum ModifierTrigger: String, CaseIterable, Sendable, Codable, Identifiable {
    case shift
    case option
    case control

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .shift: return "Shift ⇧"
        case .option: return "Option ⌥"
        case .control: return "Control ⌃"
        }
    }
}

public struct AppSettings: Sendable, Codable, Equatable {
    public var isEnabled: Bool
    public var trigger: ModifierTrigger
    public var compressionPreset: CompressionPreset
    public var whisperLanguage: String
    public var showMainWindowOnLaunch: Bool

    public init(
        isEnabled: Bool = true,
        trigger: ModifierTrigger = .shift,
        compressionPreset: CompressionPreset = .balanced,
        whisperLanguage: String = "auto",
        showMainWindowOnLaunch: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.trigger = trigger
        self.compressionPreset = compressionPreset
        self.whisperLanguage = whisperLanguage
        self.showMainWindowOnLaunch = showMainWindowOnLaunch
    }

    enum CodingKeys: String, CodingKey {
        case isEnabled
        case trigger
        case compressionPreset
        case whisperLanguage
        case showMainWindowOnLaunch
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.trigger = try container.decodeIfPresent(ModifierTrigger.self, forKey: .trigger) ?? .shift
        self.compressionPreset = try container.decodeIfPresent(CompressionPreset.self, forKey: .compressionPreset) ?? .balanced
        self.whisperLanguage = try container.decodeIfPresent(String.self, forKey: .whisperLanguage) ?? "auto"
        self.showMainWindowOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .showMainWindowOnLaunch) ?? true
    }
}

public struct DependencyStatus: Sendable, Equatable {
    public let hasFFmpeg: Bool
    public let hasMagick: Bool
    public let hasWhisperCLI: Bool
    public let hasWhisperModel: Bool
    public let hasLibreOffice: Bool
    public let hasPandoc: Bool
    public let whisperModelName: String?

    public init(
        hasFFmpeg: Bool,
        hasMagick: Bool,
        hasWhisperCLI: Bool,
        hasWhisperModel: Bool,
        hasLibreOffice: Bool,
        hasPandoc: Bool,
        whisperModelName: String?
    ) {
        self.hasFFmpeg = hasFFmpeg
        self.hasMagick = hasMagick
        self.hasWhisperCLI = hasWhisperCLI
        self.hasWhisperModel = hasWhisperModel
        self.hasLibreOffice = hasLibreOffice
        self.hasPandoc = hasPandoc
        self.whisperModelName = whisperModelName
    }
}

public enum WheelError: Error, LocalizedError, Equatable, Sendable {
    case invalidFile(String)
    case unsupportedAction(String)
    case missingDependency(String)
    case missingTranslationPack(String)
    case processFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidFile(let msg): return msg
        case .unsupportedAction(let msg): return msg
        case .missingDependency(let msg): return msg
        case .missingTranslationPack(let msg): return msg
        case .processFailed(let msg): return msg
        case .cancelled: return "Cancelled"
        }
    }
}
