import Foundation

public struct ToolPaths: Sendable, Equatable {
    public let ffmpeg: URL?
    public let magick: URL?
    public let whisperCLI: URL?
    public let soffice: URL?
    public let pandoc: URL?
    public let whisperModelURL: URL?

    public init(
        ffmpeg: URL?,
        magick: URL?,
        whisperCLI: URL?,
        soffice: URL?,
        pandoc: URL?,
        whisperModelURL: URL?
    ) {
        self.ffmpeg = ffmpeg
        self.magick = magick
        self.whisperCLI = whisperCLI
        self.soffice = soffice
        self.pandoc = pandoc
        self.whisperModelURL = whisperModelURL
    }

    public func dependencyStatus() -> DependencyStatus {
        DependencyStatus(
            hasFFmpeg: ffmpeg != nil,
            hasMagick: magick != nil,
            hasWhisperCLI: whisperCLI != nil,
            hasWhisperModel: whisperModelURL != nil,
            hasLibreOffice: soffice != nil,
            hasPandoc: pandoc != nil,
            whisperModelName: whisperModelURL?.lastPathComponent
        )
    }
}

public struct OutputPathResolver {
    public static func uniqueFileURL(
        beside source: URL,
        suffix: String = "",
        newExtension: String? = nil,
        fileManager: FileManager = .default
    ) -> URL {
        let dir = source.deletingLastPathComponent()
        let stem = source.deletingPathExtension().lastPathComponent
        let ext = (newExtension ?? source.pathExtension).trimmingCharacters(in: CharacterSet(charactersIn: "."))

        func candidateURL(counter: Int?) -> URL {
            let counterSuffix = counter.map { " (\($0))" } ?? ""
            let fileName: String
            if ext.isEmpty {
                fileName = "\(stem)\(suffix)\(counterSuffix)"
            } else {
                fileName = "\(stem)\(suffix)\(counterSuffix).\(ext)"
            }
            return dir.appendingPathComponent(fileName)
        }

        let first = candidateURL(counter: nil)
        if !fileManager.fileExists(atPath: first.path) {
            return first
        }

        var index = 2
        while true {
            let next = candidateURL(counter: index)
            if !fileManager.fileExists(atPath: next.path) {
                return next
            }
            index += 1
        }
    }

    public static func uniqueDirectoryURL(
        beside source: URL,
        folderSuffix: String,
        fileManager: FileManager = .default
    ) -> URL {
        let dir = source.deletingLastPathComponent()
        let stem = source.deletingPathExtension().lastPathComponent

        let first = dir.appendingPathComponent("\(stem)\(folderSuffix)", isDirectory: true)
        if !fileManager.fileExists(atPath: first.path) {
            return first
        }

        var index = 2
        while true {
            let next = dir.appendingPathComponent("\(stem)\(folderSuffix) (\(index))", isDirectory: true)
            if !fileManager.fileExists(atPath: next.path) {
                return next
            }
            index += 1
        }
    }

    public static func discoverTools(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> ToolPaths {
        let pathEntries = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let searchDirs = Array(Set(pathEntries + [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/Applications/LibreOffice.app/Contents/MacOS"
        ]))

        func findExecutable(_ names: [String]) -> URL? {
            for name in names {
                for dir in searchDirs {
                    let candidate = URL(fileURLWithPath: dir).appendingPathComponent(name)
                    if fileManager.isExecutableFile(atPath: candidate.path) {
                        return candidate
                    }
                }
            }
            return nil
        }

        let whisperModel = findWhisperModel(fileManager: fileManager)

        return ToolPaths(
            ffmpeg: findExecutable(["ffmpeg"]),
            magick: findExecutable(["magick", "convert"]),
            whisperCLI: findExecutable(["whisper-cli", "whisper-cpp", "main"]),
            soffice: findExecutable(["soffice"]),
            pandoc: findExecutable(["pandoc"]),
            whisperModelURL: whisperModel
        )
    }

    public static func defaultModelsDirectory(fileManager: FileManager = .default) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("MacWheel", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    private static func findWhisperModel(fileManager: FileManager) -> URL? {
        let modelDirs = [
            defaultModelsDirectory(fileManager: fileManager),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".cache/whisper", isDirectory: true),
            URL(fileURLWithPath: "/opt/homebrew/share/whisper-cpp", isDirectory: true)
        ]
        let preferredNames = [
            "ggml-large-v3-turbo.bin",
            "ggml-medium.bin",
            "ggml-small.bin",
            "ggml-base.bin"
        ]

        for dir in modelDirs {
            for name in preferredNames {
                let url = dir.appendingPathComponent(name)
                if fileManager.fileExists(atPath: url.path) {
                    return url
                }
            }
            if let contents = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil),
               let anyModel = contents.first(where: { $0.pathExtension.lowercased() == "bin" && $0.lastPathComponent.hasPrefix("ggml-") }) {
                return anyModel
            }
        }
        return nil
    }
}
