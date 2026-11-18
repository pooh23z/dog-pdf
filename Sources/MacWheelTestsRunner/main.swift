import Foundation
import MacWheelCore
import PDFKit
import UniformTypeIdentifiers

@main
struct MacWheelTestsMain {
    static func main() async {
        let args = CommandLine.arguments
        var filter: String? = nil
        if let idx = args.firstIndex(of: "--filter"), idx + 1 < args.count {
            filter = args[idx + 1]
        }

        let runner = TestSuiteRunner()
        registerTask1Tests(runner)
        registerTask2Tests(runner)

        let code = await runner.run(filter: filter)
        exit(code)
    }
}

func registerTask1Tests(_ runner: TestSuiteRunner) {
    runner.test("Task1", "Single MOV resolves expected slices") {
        let res = FileClassifier.resolveWheel(for: [URL(fileURLWithPath: "/tmp/clip.MOV")])
        try assertTrue(res.hasSharedActions)
        try assertEqual(res.slices, [.toMP4, .toMOV, .toMP3, .toM4A, .toGIF, .transcribe, .compress])
    }

    runner.test("Task1", "Single JPG resolves expected slices") {
        let res = FileClassifier.resolveWheel(for: [URL(fileURLWithPath: "/tmp/photo.jpg")])
        try assertTrue(res.hasSharedActions)
        try assertEqual(res.slices, [.toJPG, .toPNG, .toWEBP, .toPDF, .compress])
    }

    runner.test("Task1", "Multiple JPGs add Merge PDF first") {
        let res = FileClassifier.resolveWheel(for: [
            URL(fileURLWithPath: "/tmp/a.jpg"),
            URL(fileURLWithPath: "/tmp/b.png")
        ])
        try assertTrue(res.hasSharedActions)
        try assertEqual(res.slices, [.mergePDF, .toJPG, .toPNG, .toWEBP, .compress])
    }

    runner.test("Task1", "Mixed JPG and PDF resolve strict intersection with Merge PDF") {
        let res = FileClassifier.resolveWheel(for: [
            URL(fileURLWithPath: "/tmp/a.jpg"),
            URL(fileURLWithPath: "/tmp/doc.pdf")
        ])
        try assertTrue(res.hasSharedActions)
        try assertEqual(res.slices, [.mergePDF, .compress, .toJPG, .toPNG])
    }

    runner.test("Task1", "Incompatible MOV and DOCX yield no shared actions") {
        let res = FileClassifier.resolveWheel(for: [
            URL(fileURLWithPath: "/tmp/clip.mov"),
            URL(fileURLWithPath: "/tmp/note.docx")
        ])
        try assertTrue(!res.hasSharedActions)
        try assertEqual(res.slices, [])
    }

    runner.test("Task1", "OutputPathResolver preserves Thai multi-dot stem and deduplicates") {
        let dir = try makeTempDirectory("Task1Path")
        defer { try? FileManager.default.removeItem(at: dir) }

        let src = dir.appendingPathComponent("รายงาน.v1.final.pdf")
        try Data("orig".utf8).write(to: src)

        let first = OutputPathResolver.uniqueFileURL(beside: src, suffix: " (compressed)")
        try assertEqual(first.lastPathComponent, "รายงาน.v1.final (compressed).pdf")

        try Data("taken".utf8).write(to: first)
        let second = OutputPathResolver.uniqueFileURL(beside: src, suffix: " (compressed)")
        try assertEqual(second.lastPathComponent, "รายงาน.v1.final (compressed) (2).pdf")
    }
}


func registerTask2Tests(_ runner: TestSuiteRunner) {
    runner.test("Task2", "ImageEngine converts PNG to JPG, PNG, WEBP, and PDF") {
        let dir = try makeTempDirectory("Task2Convert")
        defer { try? FileManager.default.removeItem(at: dir) }

        let src = dir.appendingPathComponent("test_photo.png")
        try TestFixtures.createTestImage(at: src, width: 800, height: 600, utType: .png)
        let tools = OutputPathResolver.discoverTools()
        let engine = ImageEngine()

        let jpgOut = try await engine.convertImage(source: src, to: .toJPG, preset: .balanced, toolPaths: tools)
        try assertEqual(jpgOut.lastPathComponent, "test_photo.jpg")
        try assertTrue(FileManager.default.fileExists(atPath: jpgOut.path))

        let pngOut = try await engine.convertImage(source: src, to: .toPNG, preset: .balanced, toolPaths: tools)
        try assertEqual(pngOut.lastPathComponent, "test_photo (2).png")
        try assertTrue(FileManager.default.fileExists(atPath: pngOut.path))

        let webpOut = try await engine.convertImage(source: src, to: .toWEBP, preset: .balanced, toolPaths: tools)
        try assertEqual(webpOut.lastPathComponent, "test_photo.webp")
        try assertTrue(FileManager.default.fileExists(atPath: webpOut.path))

        let pdfOut = try await engine.convertImage(source: src, to: .toPDF, preset: .balanced, toolPaths: tools)
        try assertEqual(pdfOut.lastPathComponent, "test_photo.pdf")
        let pdfDoc = PDFDocument(url: pdfOut)
        try assertEqual(pdfDoc?.pageCount ?? 0, 1)
    }

    runner.test("Task2", "ImageEngine compresses high-res noisy PNG to smaller file") {
        let dir = try makeTempDirectory("Task2Compress")
        defer { try? FileManager.default.removeItem(at: dir) }

        let src = dir.appendingPathComponent("big_noisy.png")
        try TestFixtures.createTestImage(at: src, width: 3000, height: 2000, utType: .png, noisy: true)
        let origSize = (try FileManager.default.attributesOfItem(atPath: src.path)[.size] as? NSNumber)?.int64Value ?? 0

        let engine = ImageEngine()
        let out = try await engine.convertImage(source: src, to: .compress, preset: .small, toolPaths: OutputPathResolver.discoverTools())
        try assertTrue(out.lastPathComponent.hasPrefix("big_noisy (compressed)."))
        let newSize = (try FileManager.default.attributesOfItem(atPath: out.path)[.size] as? NSNumber)?.int64Value ?? 0
        try assertTrue(newSize > 0 && newSize < origSize, "Expected compressed \(newSize) < original \(origSize)")
    }

    runner.test("Task2", "ImageEngine merges PNG, JPG, and 1-page PDF into 3-page PDF") {
        let dir = try makeTempDirectory("Task2Merge")
        defer { try? FileManager.default.removeItem(at: dir) }

        let pngURL = dir.appendingPathComponent("1_img.png")
        let jpgURL = dir.appendingPathComponent("2_pic.jpg")
        let pdfURL = dir.appendingPathComponent("3_doc.pdf")
        try TestFixtures.createTestImage(at: pngURL, width: 800, height: 600, utType: .png)
        try TestFixtures.createTestImage(at: jpgURL, width: 400, height: 300, utType: .jpeg)
        try TestFixtures.createTextPDF(at: pdfURL, pages: ["Page Three"])

        let engine = ImageEngine()
        let merged = try await engine.mergeToPDF(sources: [pngURL, jpgURL, pdfURL])
        try assertEqual(merged.lastPathComponent, "1_img Merged.pdf")
        let doc = PDFDocument(url: merged)
        try assertEqual(doc?.pageCount ?? 0, 3)
    }
}
