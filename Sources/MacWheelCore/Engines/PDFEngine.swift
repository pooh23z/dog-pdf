import AppKit
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

public struct PDFEngine: Sendable {
    public init() {}

    public func exportPagesAsImages(pdfURL: URL, format: WheelAction) async throws -> URL {
        let doc = try loadPDF(at: pdfURL)
        let (utType, ext): (UTType, String) = switch format {
        case .toJPG: (.jpeg, "jpg")
        case .toPNG: (.png, "png")
        default: throw WheelError.unsupportedAction("Unsupported PDF image export format: \(format.label)")
        }

        if doc.pageCount == 1, let page = doc.page(at: 0) {
            let dest = OutputPathResolver.uniqueFileURL(beside: pdfURL, newExtension: ext)
            let cgImage = try renderPage(page, dpi: 200)
            try writeCGImage(cgImage, to: dest, utType: utType, quality: 0.92)
            return dest
        }

        let folder = OutputPathResolver.uniqueDirectoryURL(beside: pdfURL, folderSuffix: "_pages")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        for idx in 0..<doc.pageCount {
            guard let page = doc.page(at: idx) else { continue }
            let fileName = String(format: "page_%03d.%@", idx + 1, ext)
            let dest = folder.appendingPathComponent(fileName)
            let cgImage = try renderPage(page, dpi: 200)
            try writeCGImage(cgImage, to: dest, utType: utType, quality: 0.92)
        }
        return folder
    }

    public func extractTextOrOCR(pdfURL: URL) async throws -> String {
        let doc = try loadPDF(at: pdfURL)
        var pageTexts: [String] = []
        pageTexts.reserveCapacity(doc.pageCount)

        for idx in 0..<doc.pageCount {
            guard let page = doc.page(at: idx) else { continue }
            let embedded = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !embedded.isEmpty {
                pageTexts.append(embedded)
            } else {
                let image = try renderPage(page, dpi: 200)
                let ocr = try recognizeText(in: image)
                if !ocr.isEmpty {
                    pageTexts.append(ocr)
                }
            }
        }

        return pageTexts.joined(separator: "\n\n")
    }

    public func exportPDFToTXT(pdfURL: URL) async throws -> URL {
        let text = try await extractTextOrOCR(pdfURL: pdfURL)
        let dest = OutputPathResolver.uniqueFileURL(beside: pdfURL, newExtension: "txt")
        try text.write(to: dest, atomically: true, encoding: .utf8)
        return dest
    }

    public func exportPDFToDOCX(pdfURL: URL) async throws -> URL {
        let text = try await extractTextOrOCR(pdfURL: pdfURL)
        let dest = OutputPathResolver.uniqueFileURL(beside: pdfURL, newExtension: "docx")
        let attributed = NSAttributedString(
            string: text,
            attributes: [.font: NSFont.systemFont(ofSize: 12)]
        )
        let range = NSRange(location: 0, length: attributed.length)
        let data = try attributed.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]
        )
        try data.write(to: dest, options: .atomic)
        return dest
    }

    public func compressPDF(pdfURL: URL, preset: CompressionPreset) async throws -> URL {
        let doc = try loadPDF(at: pdfURL)
        let (dpi, quality): (CGFloat, CGFloat) = switch preset {
        case .balanced: (150, 0.75)
        case .small: (110, 0.60)
        case .highQuality: (220, 0.85)
        }

        let dest = OutputPathResolver.uniqueFileURL(beside: pdfURL, suffix: " (compressed)", newExtension: "pdf")
        let outDoc = PDFDocument()

        for idx in 0..<doc.pageCount {
            guard let page = doc.page(at: idx) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let rendered = try renderPage(page, dpi: dpi)
            let jpegData = try encodeJPEGData(rendered, quality: quality)
            guard let nsImg = NSImage(data: jpegData) else {
                throw WheelError.processFailed("Failed to re-encode PDF page \(idx + 1)")
            }
            nsImg.size = bounds.size
            if let compressedPage = PDFPage(image: nsImg) {
                outDoc.insert(compressedPage, at: outDoc.pageCount)
            }
        }

        guard outDoc.pageCount > 0, outDoc.write(to: dest) else {
            throw WheelError.processFailed("Failed to write compressed PDF: \(dest.lastPathComponent)")
        }
        return dest
    }

    private func loadPDF(at url: URL) throws -> PDFDocument {
        guard FileManager.default.fileExists(atPath: url.path),
              let doc = PDFDocument(url: url),
              doc.pageCount > 0 else {
            throw WheelError.invalidFile("Invalid or unreadable PDF: \(url.lastPathComponent)")
        }
        if doc.isLocked {
            throw WheelError.invalidFile("PDF is password-locked: \(url.lastPathComponent)")
        }
        return doc
    }

    private func renderPage(_ page: PDFPage, dpi: CGFloat) throws -> CGImage {
        let bounds = page.bounds(for: .mediaBox)
        let scale = dpi / 72.0
        let width = max(1, Int((bounds.width * scale).rounded()))
        let height = max(1, Int((bounds.height * scale).rounded()))
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw WheelError.processFailed("Failed to create PDF render context")
        }

        ctx.setFillColor(CGColor.white)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
        page.draw(with: .mediaBox, to: ctx)

        guard let cgImage = ctx.makeImage() else {
            throw WheelError.processFailed("Failed to render PDF page")
        }
        return cgImage
    }

    private func recognizeText(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["th-TH", "en-US"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        let lines = (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first?.string
        }
        return lines.joined(separator: "\n")
    }

    private func writeCGImage(_ image: CGImage, to url: URL, utType: UTType, quality: CGFloat) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, utType.identifier as CFString, 1, nil) else {
            throw WheelError.processFailed("Cannot create image destination for \(url.lastPathComponent)")
        }
        let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw WheelError.processFailed("Failed to finalize image \(url.lastPathComponent)")
        }
    }

    private func encodeJPEGData(_ image: CGImage, quality: CGFloat) throws -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw WheelError.processFailed("Failed to create JPEG encoder")
        }
        let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw WheelError.processFailed("Failed to encode JPEG data")
        }
        return data as Data
    }
}
