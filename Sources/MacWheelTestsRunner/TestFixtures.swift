import AppKit
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

enum TestFixtures {
    static func createTestImage(
        at url: URL,
        width: Int,
        height: Int,
        utType: UTType,
        noisy: Bool = false
    ) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TestFailure(message: "Failed to create CGContext")
        }

        if noisy, let data = ctx.data {
            let ptr = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
            var state: UInt64 = 0x123456789ABCDEF
            for i in stride(from: 0, to: width * height * 4, by: 4) {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                ptr[i] = UInt8((state >> 56) & 0xFF)
                ptr[i + 1] = UInt8((state >> 48) & 0xFF)
                ptr[i + 2] = UInt8((state >> 40) & 0xFF)
                ptr[i + 3] = 255
            }
        } else {
            ctx.setFillColor(CGColor(red: 0.95, green: 0.55, blue: 0.15, alpha: 1.0))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            ctx.setFillColor(CGColor(red: 0.15, green: 0.35, blue: 0.85, alpha: 1.0))
            ctx.fill(CGRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2))
        }

        guard let cgImage = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, utType.identifier as CFString, 1, nil) else {
            throw TestFailure(message: "Failed to create image destination for \(url.path)")
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        if !CGImageDestinationFinalize(dest) {
            throw TestFailure(message: "Failed to finalize image at \(url.path)")
        }
    }

    static func createTextPDF(at url: URL, pages: [String]) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw TestFailure(message: "Failed to create PDF context")
        }

        for pageText in pages {
            ctx.beginPDFPage(nil)
            let nsContext = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsContext
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 22),
                .foregroundColor: NSColor.black
            ]
            NSString(string: pageText).draw(in: CGRect(x: 50, y: 650, width: 500, height: 100), withAttributes: attrs)
            NSGraphicsContext.restoreGraphicsState()
            ctx.endPDFPage()
        }
        ctx.closePDF()
    }
}
