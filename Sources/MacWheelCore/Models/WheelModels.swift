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

public enum TargetFileSize: String, CaseIterable, Sendable, Codable, Identifiable {
    case auto
    case mb2
    case mb1
    case kb500
    case kb200
    case kb100

    public var id: String { rawValue }

    public var maxBytes: Int64? {
        switch self {
        case .auto: return nil
        case .mb2: return 2_000_000
        case .mb1: return 1_000_000
        case .kb500: return 500_000
        case .kb200: return 200_000
        case .kb100: return 100_000
        }
    }

    public var displayName: String {
        switch self {
        case .auto: return "อัตโนมัติ"
        case .mb2: return "≤ 2 MB"
        case .mb1: return "≤ 1 MB"
        case .kb500: return "≤ 500 KB"
        case .kb200: return "≤ 200 KB"
        case .kb100: return "≤ 100 KB"
        }
    }

    public var fileSuffix: String {
        switch self {
        case .auto: return " (compressed)"
        case .mb2: return " (≤2MB)"
        case .mb1: return " (≤1MB)"
        case .kb500: return " (≤500KB)"
        case .kb200: return " (≤200KB)"
        case .kb100: return " (≤100KB)"
        }
    }
}

public enum MascotCharacter: String, CaseIterable, Sendable, Codable, Identifiable {
    case shiba
    case cat
    case rabbit
    case bear
    case penguin
    case duck
    case panda
    case fox
    case frog
    case owl

    public var id: String { rawValue }

    public var thaiName: String {
        switch self {
        case .shiba: return "น้องหมาชิบะ"
        case .cat: return "น้องแมว"
        case .rabbit: return "น้องกระต่าย"
        case .bear: return "น้องหมี"
        case .penguin: return "น้องเพนกวิน"
        case .duck: return "น้องเป็ด"
        case .panda: return "น้องแพนด้า"
        case .fox: return "น้องจิ้งจอก"
        case .frog: return "น้องกบ"
        case .owl: return "น้องนกฮูก"
        }
    }

    public var emoji: String {
        switch self {
        case .shiba: return "🐶"
        case .cat: return "🐱"
        case .rabbit: return "🐰"
        case .bear: return "🐻"
        case .penguin: return "🐧"
        case .duck: return "🦆"
        case .panda: return "🐼"
        case .fox: return "🦊"
        case .frog: return "🐸"
        case .owl: return "🦉"
        }
    }
}

public func formatReadableByteCount(_ bytes: Int64) -> String {
    if bytes >= 1_000_000 {
        return String(format: "%.1f MB", Double(bytes) / 1_000_000.0)
    } else if bytes >= 1_000 {
        return String(format: "%.0f KB", Double(bytes) / 1_000.0)
    } else {
        return "\(bytes) B"
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
    public var targetFileSize: TargetFileSize
    public var whisperLanguage: String
    public var showMainWindowOnLaunch: Bool
    public var animateMenuBarDog: Bool
    public var mascot: MascotCharacter

    public init(
        isEnabled: Bool = true,
        trigger: ModifierTrigger = .shift,
        compressionPreset: CompressionPreset = .balanced,
        targetFileSize: TargetFileSize = .auto,
        whisperLanguage: String = "auto",
        showMainWindowOnLaunch: Bool = true,
        animateMenuBarDog: Bool = true,
        mascot: MascotCharacter = .shiba
    ) {
        self.isEnabled = isEnabled
        self.trigger = trigger
        self.compressionPreset = compressionPreset
        self.targetFileSize = targetFileSize
        self.whisperLanguage = whisperLanguage
        self.showMainWindowOnLaunch = showMainWindowOnLaunch
        self.animateMenuBarDog = animateMenuBarDog
        self.mascot = mascot
    }

    enum CodingKeys: String, CodingKey {
        case isEnabled
        case trigger
        case compressionPreset
        case targetFileSize
        case whisperLanguage
        case showMainWindowOnLaunch
        case animateMenuBarDog
        case mascot
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.trigger = try container.decodeIfPresent(ModifierTrigger.self, forKey: .trigger) ?? .shift
        self.compressionPreset = try container.decodeIfPresent(CompressionPreset.self, forKey: .compressionPreset) ?? .balanced
        self.targetFileSize = try container.decodeIfPresent(TargetFileSize.self, forKey: .targetFileSize) ?? .auto
        self.whisperLanguage = try container.decodeIfPresent(String.self, forKey: .whisperLanguage) ?? "auto"
        self.showMainWindowOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .showMainWindowOnLaunch) ?? true
        self.animateMenuBarDog = try container.decodeIfPresent(Bool.self, forKey: .animateMenuBarDog) ?? true
        self.mascot = try container.decodeIfPresent(MascotCharacter.self, forKey: .mascot) ?? .shiba
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
