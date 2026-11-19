import AppKit
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

public struct ImageEngine: Sendable {
    private let runner: ProcessExecuting

    public init(runner: ProcessExecuting = ProcessRunner()) {
        self.runner = runner
    }

    public func convertImage(
        source: URL,
        to action: WheelAction,
        preset: CompressionPreset,
        targetFileSize: TargetFileSize = .auto,
        toolPaths: ToolPaths
    ) async throws -> URL {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw WheelError.invalidFile("File not found: \(source.lastPathComponent)")
        }

        switch action {
        case .toJPG:
            let dest = OutputPathResolver.uniqueFileURL(beside: source, newExtension: "jpg")
            try encodeImage(source: source, destination: dest, utType: .jpeg, quality: 0.92, maxPixelEdge: nil)
            return dest

        case .toPNG:
            let dest = OutputPathResolver.uniqueFileURL(beside: source, newExtension: "png")
            try encodeImage(source: source, destination: dest, utType: .png, quality: 1.0, maxPixelEdge: nil)
            return dest

        case .toPDF:
            let dest = OutputPathResolver.uniqueFileURL(beside: source, newExtension: "pdf")
            let doc = PDFDocument()
            guard let page = makePDFPage(fromImageURL: source) else {
                throw WheelError.invalidFile("Unable to read image: \(source.lastPathComponent)")
            }
            doc.insert(page, at: 0)
            guard doc.write(to: dest) else {
                throw WheelError.processFailed("Failed to write PDF at \(dest.lastPathComponent)")
            }
            return dest

        case .toWEBP:
            guard let magick = toolPaths.magick else {
                throw WheelError.missingDependency("ImageMagick (magick) is required to convert to WEBP.")
            }
            let dest = OutputPathResolver.uniqueFileURL(beside: source, newExtension: "webp")
            let result = try await runner.run(executableURL: magick, arguments: [source.path, "-quality", "88", dest.path])
            guard result.exitCode == 0 else {
                throw WheelError.processFailed(result.stderr.isEmpty ? "ImageMagick failed with exit \(result.exitCode)" : result.stderr)
            }
            return dest

        case .compress:
            if let maxBytes = targetFileSize.maxBytes {
                return try compressImageToTargetBytes(source: source, maxBytes: maxBytes, suffix: targetFileSize.fileSuffix)
            }
            return try await compressImage(source: source, preset: preset, toolPaths: toolPaths)

        default:
            throw WheelError.unsupportedAction("Unsupported image action: \(action.label)")
        }
    }

    public func mergeToPDF(sources: [URL]) async throws -> URL {
        guard !sources.isEmpty else {
            throw WheelError.invalidFile("No files provided to Merge PDF.")
        }
        let dest = OutputPathResolver.uniqueFileURL(beside: sources[0], suffix: " Merged", newExtension: "pdf")
        let merged = PDFDocument()
        var pageIndex = 0

        for url in sources {
            let category = FileClassifier.category(for: url)
            if category == .pdf {
                guard let pdf = PDFDocument(url: url), pdf.pageCount > 0 else {
                    throw WheelError.invalidFile("Invalid or empty PDF: \(url.lastPathComponent)")
                }
                for idx in 0..<pdf.pageCount {
                    if let page = pdf.page(at: idx) {
                        merged.insert(page, at: pageIndex)
                        pageIndex += 1
                    }
                }
            } else if category == .image {
                guard let page = makePDFPage(fromImageURL: url) else {
                    throw WheelError.invalidFile("Unable to read image: \(url.lastPathComponent)")
                }
                merged.insert(page, at: pageIndex)
                pageIndex += 1
            } else {
                throw WheelError.unsupportedAction("Merge PDF supports images and PDFs only (\(url.lastPathComponent)).")
            }
        }

        guard pageIndex > 0, merged.write(to: dest) else {
            throw WheelError.processFailed("Failed to write merged PDF.")
        }
        return dest
    }

    private func compressImageToTargetBytes(source: URL, maxBytes: Int64, suffix: String) throws -> URL {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil) else {
            throw WheelError.invalidFile("Cannot open image: \(source.lastPathComponent)")
        }

        let edgeCandidates: [Int?] = [nil, 2560, 1920, 1440, 1080, 800, 600, 420, 300]
        var smallestFallback: Data?

        for edge in edgeCandidates {
            guard let cgImage = decodeCGImage(from: imageSource, maxPixelEdge: edge) else { continue }

            // Quick check at lowest acceptable quality for this resolution before binary searching.
            guard let minData = encodeJPEGMemory(cgImage, quality: 0.18) else { continue }
            if smallestFallback == nil || minData.count < smallestFallback!.count {
                smallestFallback = minData
            }
            if Int64(minData.count) > maxBytes {
                continue
            }

            // Binary search for highest quality that stays <= maxBytes.
            var low: CGFloat = 0.18
            var high: CGFloat = 0.92
            var bestData = minData
            for _ in 0..<6 {
                let mid = (low + high) / 2.0
                if let candidate = encodeJPEGMemory(cgImage, quality: mid) {
                    if Int64(candidate.count) <= maxBytes {
                        bestData = candidate
                        low = mid
                    } else {
                        high = mid
                    }
                }
            }

            let dest = OutputPathResolver.uniqueFileURL(beside: source, suffix: suffix, newExtension: "jpg")
            try bestData.write(to: dest, options: .atomic)
            return dest
        }

        guard let fallback = smallestFallback else {
            throw WheelError.processFailed("Unable to compress image \(source.lastPathComponent)")
        }
        let dest = OutputPathResolver.uniqueFileURL(beside: source, suffix: suffix, newExtension: "jpg")
        try fallback.write(to: dest, options: .atomic)
        return dest
    }

    private func decodeCGImage(from imageSource: CGImageSource, maxPixelEdge: Int?) -> CGImage? {
        if let maxPixelEdge {
            let thumbOpts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelEdge
            ]
            return CGImageSourceCreateThumbnailAtIndex(imageSource, 0, thumbOpts as CFDictionary)
        } else {
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            return CGImageSourceCreateThumbnailAtIndex(imageSource, 0, opts as CFDictionary)
                ?? CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        }
    }

    private func encodeJPEGMemory(_ image: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    private func compressImage(source: URL, preset: CompressionPreset, toolPaths: ToolPaths) async throws -> URL {
        let ext = source.pathExtension.lowercased()
        let (quality, maxEdge): (CGFloat, Int?) = switch preset {
        case .balanced: (0.80, 2560)
        case .small: (0.65, 1920)
        case .highQuality: (0.90, nil)
        }

        if ext == "webp", let magick = toolPaths.magick {
            let dest = OutputPathResolver.uniqueFileURL(beside: source, suffix: " (compressed)", newExtension: "webp")
            var args = [source.path]
            if let maxEdge {
                args += ["-resize", "\(maxEdge)x\(maxEdge)>"]
            }
            args += ["-quality", "\(Int(quality * 100))", dest.path]
            let res = try await runner.run(executableURL: magick, arguments: args)
            guard res.exitCode == 0 else {
                throw WheelError.processFailed(res.stderr)
            }
            return dest
        }

        let targetType: UTType
        let targetExt: String
        switch ext {
        case "png":
            targetType = .png
            targetExt = "png"
        case "heic", "heif":
            targetType = .heic
            targetExt = "heic"
        default:
            targetType = .jpeg
            targetExt = "jpg"
        }

        let dest = OutputPathResolver.uniqueFileURL(beside: source, suffix: " (compressed)", newExtension: targetExt)
        try encodeImage(source: source, destination: dest, utType: targetType, quality: quality, maxPixelEdge: maxEdge)

        // If a lossless PNG didn't shrink even after downscaling, re-encode as JPEG when it has no alpha or smaller size is needed.
        if targetType == .png {
            let origSize = fileSize(source)
            let newSize = fileSize(dest)
            if origSize > 0, newSize >= origSize {
                let jpgDest = OutputPathResolver.uniqueFileURL(beside: source, suffix: " (compressed)", newExtension: "jpg")
                try encodeImage(source: source, destination: jpgDest, utType: .jpeg, quality: quality, maxPixelEdge: maxEdge)
                if fileSize(jpgDest) < newSize {
                    try? FileManager.default.removeItem(at: dest)
                    return jpgDest
                } else {
                    try? FileManager.default.removeItem(at: jpgDest)
                }
            }
        }
        return dest
    }

    private func encodeImage(
        source: URL,
        destination: URL,
        utType: UTType,
        quality: CGFloat,
        maxPixelEdge: Int?
    ) throws {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil) else {
            throw WheelError.invalidFile("Cannot open image: \(source.lastPathComponent)")
        }

        let cgImage: CGImage?
        if let maxPixelEdge {
            let thumbOpts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelEdge
            ]
            cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, thumbOpts as CFDictionary)
        } else {
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, opts as CFDictionary)
                ?? CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        }

        guard let finalImage = cgImage else {
            throw WheelError.invalidFile("Failed to decode image: \(source.lastPathComponent)")
        }
        guard let dest = CGImageDestinationCreateWithURL(destination as CFURL, utType.identifier as CFString, 1, nil) else {
            throw WheelError.processFailed("Cannot create destination image: \(destination.lastPathComponent)")
        }

        let props: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(dest, finalImage, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw WheelError.processFailed("Failed to write image: \(destination.lastPathComponent)")
        }
    }

    private func makePDFPage(fromImageURL url: URL) -> PDFPage? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, opts as CFDictionary)
                ?? CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return nil
        }
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        return PDFPage(image: nsImage)
    }

    private func fileSize(_ url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
    }
}
