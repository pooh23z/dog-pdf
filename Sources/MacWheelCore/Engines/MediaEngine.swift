import Foundation

public struct TranscriptionResult: Equatable, Sendable {
    public let txtURL: URL
    public let srtURL: URL

    public init(txtURL: URL, srtURL: URL) {
        self.txtURL = txtURL
        self.srtURL = srtURL
    }
}

public struct MediaEngine: Sendable {
    private let runner: ProcessExecuting

    public init(runner: ProcessExecuting = ProcessRunner()) {
        self.runner = runner
    }

    public func convertOrCompressMedia(
        source: URL,
        action: WheelAction,
        preset: CompressionPreset,
        toolPaths: ToolPaths
    ) async throws -> URL {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw WheelError.invalidFile("File not found: \(source.lastPathComponent)")
        }
        guard let ffmpeg = toolPaths.ffmpeg else {
            throw WheelError.missingDependency("ffmpeg is required for media conversion and compression.")
        }

        let isAudioOnly = FileClassifier.category(for: source) == .audio
        let dest: URL
        let args: [String]

        switch action {
        case .toMP4:
            dest = OutputPathResolver.uniqueFileURL(beside: source, newExtension: "mp4")
            args = ["-y", "-i", source.path, "-c:v", "h264_videotoolbox", "-q:v", "65", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", dest.path]

        case .toMOV:
            dest = OutputPathResolver.uniqueFileURL(beside: source, newExtension: "mov")
            args = ["-y", "-i", source.path, "-c:v", "h264_videotoolbox", "-q:v", "65", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", dest.path]

        case .toMP3:
            dest = OutputPathResolver.uniqueFileURL(beside: source, newExtension: "mp3")
            args = ["-y", "-i", source.path, "-vn", "-c:a", "libmp3lame", "-q:a", "2", dest.path]

        case .toM4A:
            dest = OutputPathResolver.uniqueFileURL(beside: source, newExtension: "m4a")
            args = ["-y", "-i", source.path, "-vn", "-c:a", "aac", "-b:a", "192k", dest.path]

        case .toWAV:
            dest = OutputPathResolver.uniqueFileURL(beside: source, newExtension: "wav")
            args = ["-y", "-i", source.path, "-vn", "-c:a", "pcm_s16le", dest.path]

        case .toGIF:
            dest = OutputPathResolver.uniqueFileURL(beside: source, newExtension: "gif")
            args = [
                "-y", "-i", source.path,
                "-vf", "fps=12,scale=640:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse",
                dest.path
            ]

        case .compress:
            if isAudioOnly {
                let ext = source.pathExtension.lowercased() == "mp3" ? "mp3" : "m4a"
                let bitrate = switch preset {
                case .highQuality: "192k"
                case .balanced: "128k"
                case .small: "96k"
                }
                let codec = ext == "mp3" ? "libmp3lame" : "aac"
                dest = OutputPathResolver.uniqueFileURL(beside: source, suffix: " (compressed)", newExtension: ext)
                args = ["-y", "-i", source.path, "-vn", "-c:a", codec, "-b:a", bitrate, dest.path]
            } else {
                let (quality, scaleFilter): (String, String?) = switch preset {
                case .highQuality: ("65", nil)
                case .balanced: ("50", "scale='min(1920,iw)':-2")
                case .small: ("38", "scale='min(1280,iw)':-2")
                }
                dest = OutputPathResolver.uniqueFileURL(beside: source, suffix: " (compressed)", newExtension: "mp4")
                var built = ["-y", "-i", source.path]
                if let scaleFilter {
                    built += ["-vf", scaleFilter]
                }
                built += [
                    "-c:v", "hevc_videotoolbox", "-tag:v", "hvc1", "-q:v", quality,
                    "-c:a", "aac", "-b:a", preset == .small ? "96k" : "128k",
                    "-movflags", "+faststart",
                    dest.path
                ]
                args = built
            }

        default:
            throw WheelError.unsupportedAction("Unsupported media action: \(action.label)")
        }

        let result = try await runner.run(executableURL: ffmpeg, arguments: args)
        guard result.exitCode == 0, FileManager.default.fileExists(atPath: dest.path) else {
            throw WheelError.processFailed("ffmpeg failed (\(result.exitCode)): \(result.stderr.suffix(400))")
        }
        return dest
    }

    public func transcribeMedia(
        source: URL,
        language: String = "auto",
        toolPaths: ToolPaths
    ) async throws -> TranscriptionResult {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw WheelError.invalidFile("File not found: \(source.lastPathComponent)")
        }
        guard let ffmpeg = toolPaths.ffmpeg else {
            throw WheelError.missingDependency("ffmpeg is required to extract audio for transcription.")
        }
        guard let whisperCLI = toolPaths.whisperCLI else {
            throw WheelError.missingDependency("whisper-cli is not installed. Run Setup Dependencies from the menu bar.")
        }
        guard let modelURL = toolPaths.whisperModelURL, FileManager.default.fileExists(atPath: modelURL.path) else {
            throw WheelError.missingDependency("Whisper GGML model is missing. Run Setup Dependencies from the menu bar.")
        }

        let tempWav = FileManager.default.temporaryDirectory
            .appendingPathComponent("macwheel-whisper-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: tempWav) }

        let extractRes = try await runner.run(
            executableURL: ffmpeg,
            arguments: ["-y", "-i", source.path, "-vn", "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", tempWav.path]
        )
        guard extractRes.exitCode == 0, FileManager.default.fileExists(atPath: tempWav.path) else {
            throw WheelError.processFailed("Audio extraction failed: \(extractRes.stderr.suffix(300))")
        }

        let (txtURL, srtURL) = uniqueTranscriptPair(beside: source)
        let outputBase = txtURL.deletingPathExtension().path

        let whisperRes = try await runner.run(
            executableURL: whisperCLI,
            arguments: ["-m", modelURL.path, "-f", tempWav.path, "-l", language, "-otxt", "-osrt", "-of", outputBase]
        )
        guard whisperRes.exitCode == 0 else {
            throw WheelError.processFailed("whisper-cli failed (\(whisperRes.exitCode)): \(whisperRes.stderr.suffix(400))")
        }

        return TranscriptionResult(txtURL: txtURL, srtURL: srtURL)
    }

    private func uniqueTranscriptPair(beside source: URL) -> (URL, URL) {
        let dir = source.deletingLastPathComponent()
        let stem = source.deletingPathExtension().lastPathComponent
        let fm = FileManager.default

        var counter = 0
        while true {
            let suffix = counter == 0 ? "" : " (\(counter + 1))"
            let txt = dir.appendingPathComponent("\(stem)\(suffix).txt")
            let srt = dir.appendingPathComponent("\(stem)\(suffix).srt")
            if !fm.fileExists(atPath: txt.path) && !fm.fileExists(atPath: srt.path) {
                return (txt, srt)
            }
            counter += 1
        }
    }
}
