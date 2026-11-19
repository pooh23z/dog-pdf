import AppKit
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
        registerTask3Tests(runner)
        registerTask4Tests(runner)
        registerTask5Tests(runner)
        registerTask6Tests(runner)
        registerTask7Tests(runner)

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


func registerTask3Tests(_ runner: TestSuiteRunner) {
    runner.test("Task3", "PDFEngine exports 2-page PDF to PNG folder and TXT") {
        let dir = try makeTempDirectory("Task3Export")
        defer { try? FileManager.default.removeItem(at: dir) }

        let pdfURL = dir.appendingPathComponent("text_sample.pdf")
        try TestFixtures.createTextPDF(at: pdfURL, pages: ["Hello Page One", "Second Page Content"])

        let engine = PDFEngine()
        let pagesDir = try await engine.exportPagesAsImages(pdfURL: pdfURL, format: .toPNG)
        try assertEqual(pagesDir.lastPathComponent, "text_sample_pages")
        let files = try FileManager.default.contentsOfDirectory(atPath: pagesDir.path)
        try assertEqual(files.filter { $0.hasSuffix(".png") }.count, 2)

        let txtURL = try await engine.exportPDFToTXT(pdfURL: pdfURL)
        try assertEqual(txtURL.lastPathComponent, "text_sample.txt")
        let txt = try String(contentsOf: txtURL, encoding: .utf8)
        try assertTrue(txt.contains("Hello Page One"))
        try assertTrue(txt.contains("Second Page Content"))

        let docxURL = try await engine.exportPDFToDOCX(pdfURL: pdfURL)
        try assertEqual(docxURL.lastPathComponent, "text_sample.docx")
        try assertTrue(FileManager.default.fileExists(atPath: docxURL.path))
    }

    runner.test("Task3", "PDFEngine runs Vision OCR on scanned image-only PDF") {
        let dir = try makeTempDirectory("Task3OCR")
        defer { try? FileManager.default.removeItem(at: dir) }

        let scannedURL = dir.appendingPathComponent("scanned_sample.pdf")
        try TestFixtures.createScannedImagePDF(at: scannedURL, text: "MacWheel Offline OCR Test")
        try assertEqual(PDFDocument(url: scannedURL)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "", "")

        let engine = PDFEngine()
        let extracted = try await engine.extractTextOrOCR(pdfURL: scannedURL)
        try assertTrue(extracted.range(of: "MacWheel", options: .caseInsensitive) != nil, "OCR output was: \(extracted)")
    }

    runner.test("Task3", "PDFEngine rejects zero-byte PDF with WheelError.invalidFile") {
        let dir = try makeTempDirectory("Task3Broken")
        defer { try? FileManager.default.removeItem(at: dir) }

        let brokenURL = dir.appendingPathComponent("broken.pdf")
        try Data().write(to: brokenURL)

        let engine = PDFEngine()
        try await assertThrowsAsync(WheelError.invalidFile("Invalid or unreadable PDF: broken.pdf")) {
            _ = try await engine.extractTextOrOCR(pdfURL: brokenURL)
        }
    }

    runner.test("Task3", "PDFEngine compresses large image PDF smaller") {
        let dir = try makeTempDirectory("Task3Compress")
        defer { try? FileManager.default.removeItem(at: dir) }

        let imgURL = dir.appendingPathComponent("huge.png")
        try TestFixtures.createTestImage(at: imgURL, width: 2800, height: 1800, utType: .png, noisy: true)
        let pdfURL = try await ImageEngine().convertImage(source: imgURL, to: .toPDF, preset: .balanced, toolPaths: OutputPathResolver.discoverTools())
        let origSize = (try FileManager.default.attributesOfItem(atPath: pdfURL.path)[.size] as? NSNumber)?.int64Value ?? 0

        let compressed = try await PDFEngine().compressPDF(pdfURL: pdfURL, preset: .small)
        try assertEqual(compressed.lastPathComponent, "huge (compressed).pdf")
        let newSize = (try FileManager.default.attributesOfItem(atPath: compressed.path)[.size] as? NSNumber)?.int64Value ?? 0
        try assertTrue(newSize > 0 && newSize < origSize, "Expected compressed PDF \(newSize) < original \(origSize)")
        try assertEqual(PDFDocument(url: compressed)?.pageCount ?? 0, 1)
    }
}


func registerTask4Tests(_ runner: TestSuiteRunner) {
    runner.test("Task4", "DocumentEngine converts Thai+English TXT to RTF, HTML, DOCX, PDF and back") {
        let dir = try makeTempDirectory("Task4Docs")
        defer { try? FileManager.default.removeItem(at: dir) }

        let txtURL = dir.appendingPathComponent("note.txt")
        let sampleText = "สวัสดี MacWheel\nOffline document conversion test."
        try sampleText.write(to: txtURL, atomically: true, encoding: .utf8)

        let engine = DocumentEngine()
        let tools = OutputPathResolver.discoverTools()

        let rtfOut = try await engine.convertDocument(source: txtURL, to: .toRTF, toolPaths: tools)
        try assertEqual(rtfOut.lastPathComponent, "note.rtf")
        try assertTrue(FileManager.default.fileExists(atPath: rtfOut.path))

        let htmlOut = try await engine.convertDocument(source: txtURL, to: .toHTML, toolPaths: tools)
        try assertEqual(htmlOut.lastPathComponent, "note.html")
        try assertTrue(FileManager.default.fileExists(atPath: htmlOut.path))

        let docxOut = try await engine.convertDocument(source: txtURL, to: .toDOCX, toolPaths: tools)
        try assertEqual(docxOut.lastPathComponent, "note.docx")
        try assertTrue(FileManager.default.fileExists(atPath: docxOut.path))

        let pdfOut = try await engine.convertDocument(source: txtURL, to: .toPDF, toolPaths: tools)
        try assertEqual(pdfOut.lastPathComponent, "note.pdf")
        try assertTrue((PDFDocument(url: pdfOut)?.pageCount ?? 0) >= 1)

        let roundTripTXT = try await engine.convertDocument(source: docxOut, to: .toTXT, toolPaths: tools)
        let extracted = try String(contentsOf: roundTripTXT, encoding: .utf8)
        try assertTrue(extracted.contains("สวัสดี"))
        try assertTrue(extracted.contains("MacWheel"))

        let docxPDF = try await engine.convertDocument(source: docxOut, to: .toPDF, toolPaths: tools)
        try assertEqual(docxPDF.lastPathComponent, "note (2).pdf")
        let pdfExtracted = PDFDocument(url: docxPDF)?.string ?? ""
        try assertTrue(pdfExtracted.contains("MacWheel"), "PDF text was: \(pdfExtracted)")
    }
}


private actor StubWhisperRunner: ProcessExecuting {
    private let realRunner = ProcessRunner()
    private(set) var recordedCommands: [(String, [String])] = []

    func run(executableURL: URL, arguments: [String]) async throws -> ProcessResult {
        recordedCommands.append((executableURL.lastPathComponent, arguments))

        if executableURL.lastPathComponent == "whisper-cli" {
            if let ofIdx = arguments.firstIndex(of: "-of"), ofIdx + 1 < arguments.count {
                let base = arguments[ofIdx + 1]
                try "Hello transcribed text".write(toFile: base + ".txt", atomically: true, encoding: .utf8)
                try "1\n00:00:00,000 --> 00:00:01,500\nHello transcribed text\n".write(toFile: base + ".srt", atomically: true, encoding: .utf8)
            }
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }
        return try await realRunner.run(executableURL: executableURL, arguments: arguments)
    }

    func hasWhisperCallWithTxtAndSrt() -> Bool {
        recordedCommands.contains { name, args in
            name == "whisper-cli" && args.contains("-otxt") && args.contains("-osrt")
        }
    }
}

func registerTask5Tests(_ runner: TestSuiteRunner) {
    runner.test("Task5", "MediaEngine converts and compresses real MOV via ffmpeg") {
        let dir = try makeTempDirectory("Task5Media")
        defer { try? FileManager.default.removeItem(at: dir) }

        let tools = OutputPathResolver.discoverTools()
        guard let ffmpeg = tools.ffmpeg else {
            throw TestFailure(message: "ffmpeg must be installed on this Mac")
        }

        let movURL = dir.appendingPathComponent("sample.mov")
        let gen = try await ProcessRunner().run(
            executableURL: ffmpeg,
            arguments: [
                "-y", "-f", "lavfi", "-i", "testsrc=size=640x360:rate=24:duration=1",
                "-f", "lavfi", "-i", "sine=frequency=440:duration=1",
                "-c:v", "h264_videotoolbox", "-c:a", "aac", movURL.path
            ]
        )
        try assertEqual(gen.exitCode, 0, "ffmpeg fixture creation failed: \(gen.stderr)")

        let engine = MediaEngine()
        for (action, ext) in [
            (WheelAction.toMP4, "mp4"),
            (WheelAction.toMP3, "mp3"),
            (WheelAction.toM4A, "m4a"),
            (WheelAction.toGIF, "gif")
        ] {
            let out = try await engine.convertOrCompressMedia(source: movURL, action: action, preset: .balanced, toolPaths: tools)
            try assertEqual(out.pathExtension.lowercased(), ext)
            let size = (try FileManager.default.attributesOfItem(atPath: out.path)[.size] as? NSNumber)?.int64Value ?? 0
            try assertTrue(size > 0, "Empty output for \(action.label)")
        }

        let compressed = try await engine.convertOrCompressMedia(source: movURL, action: .compress, preset: .balanced, toolPaths: tools)
        try assertEqual(compressed.lastPathComponent, "sample (compressed).mp4")
        try assertTrue(FileManager.default.fileExists(atPath: compressed.path))
    }

    runner.test("Task5", "MediaEngine transcribes via whisper-cli, cleans temp wav, and errors when missing") {
        let dir = try makeTempDirectory("Task5Whisper")
        defer { try? FileManager.default.removeItem(at: dir) }

        let realTools = OutputPathResolver.discoverTools()
        guard let ffmpeg = realTools.ffmpeg else {
            throw TestFailure(message: "ffmpeg missing")
        }

        let movURL = dir.appendingPathComponent("talk.mov")
        _ = try await ProcessRunner().run(
            executableURL: ffmpeg,
            arguments: ["-y", "-f", "lavfi", "-i", "testsrc=size=320x240:rate=15:duration=1", "-f", "lavfi", "-i", "sine=frequency=440:duration=1", movURL.path]
        )

        let fakeWhisper = dir.appendingPathComponent("whisper-cli")
        let fakeModel = dir.appendingPathComponent("ggml-medium.bin")
        try Data("#!/bin/sh\n".utf8).write(to: fakeWhisper)
        try Data("model".utf8).write(to: fakeModel)

        let stubTools = ToolPaths(ffmpeg: ffmpeg, magick: realTools.magick, whisperCLI: fakeWhisper, soffice: nil, pandoc: nil, whisperModelURL: fakeModel)
        let stubRunner = StubWhisperRunner()
        let engine = MediaEngine(runner: stubRunner)

        let res = try await engine.transcribeMedia(source: movURL, language: "auto", toolPaths: stubTools)
        try assertEqual(res.txtURL.lastPathComponent, "talk.txt")
        try assertEqual(res.srtURL.lastPathComponent, "talk.srt")
        try assertTrue(FileManager.default.fileExists(atPath: res.txtURL.path))
        try assertTrue(FileManager.default.fileExists(atPath: res.srtURL.path))

        let hasCall = await stubRunner.hasWhisperCallWithTxtAndSrt()
        try assertTrue(hasCall)

        let dirContents = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        try assertTrue(!dirContents.contains(where: { $0.hasSuffix(".wav") }), "Temp wav was not cleaned up")

        let missingTools = ToolPaths(ffmpeg: ffmpeg, magick: nil, whisperCLI: nil, soffice: nil, pandoc: nil, whisperModelURL: nil)
        try await assertThrowsAsync(WheelError.missingDependency("whisper-cli is not installed. Run Setup Dependencies from the menu bar.")) {
            _ = try await engine.transcribeMedia(source: movURL, language: "auto", toolPaths: missingTools)
        }
    }
}


private struct MockTranslator: TextTranslating {
    func translate(_ texts: [String], to target: TranslationLanguage) async throws -> [String] {
        let prefix = target == .th ? "[TH] " : "[EN] "
        return texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? $0 : prefix + $0 }
    }
}

func registerTask6Tests(_ runner: TestSuiteRunner) {
    runner.test("Task6", "TranslationEngine preserves SRT cue numbers and timestamps across multi-line cues") {
        let dir = try makeTempDirectory("Task6SRT")
        defer { try? FileManager.default.removeItem(at: dir) }

        let srtURL = dir.appendingPathComponent("video.srt")
        let srtBody = """
        1
        00:00:01,000 --> 00:00:03,500
        Hello world
        Second line here

        2
        00:00:04,000 --> 00:00:06,250
        Goodbye now
        """
        try srtBody.write(to: srtURL, atomically: true, encoding: .utf8)

        let engine = TranslationEngine()
        let out = try await engine.translateFile(
            source: srtURL,
            to: .th,
            translator: MockTranslator(),
            toolPaths: OutputPathResolver.discoverTools()
        )
        try assertEqual(out.lastPathComponent, "video TH.srt")
        let translated = try String(contentsOf: out, encoding: .utf8)
        try assertTrue(translated.contains("1\n00:00:01,000 --> 00:00:03,500\n"))
        try assertTrue(translated.contains("[TH] Hello world"))
        try assertTrue(translated.contains("[TH] Second line here"))
        try assertTrue(translated.contains("2\n00:00:04,000 --> 00:00:06,250\n[TH] Goodbye now"))
    }

    runner.test("Task6", "TranslationEngine translates TXT and scanned PDF into TH/EN .txt files") {
        let dir = try makeTempDirectory("Task6Docs")
        defer { try? FileManager.default.removeItem(at: dir) }

        let txtURL = dir.appendingPathComponent("memo.txt")
        try "First paragraph.\n\nSecond paragraph.".write(to: txtURL, atomically: true, encoding: .utf8)

        let scannedPDF = dir.appendingPathComponent("scan.pdf")
        try TestFixtures.createScannedImagePDF(at: scannedPDF, text: "Hello Scan Document")

        let engine = TranslationEngine()
        let tools = OutputPathResolver.discoverTools()

        let txtOut = try await engine.translateFile(source: txtURL, to: .th, translator: MockTranslator(), toolPaths: tools)
        try assertEqual(txtOut.lastPathComponent, "memo TH.txt")
        let txtContent = try String(contentsOf: txtOut, encoding: .utf8)
        try assertTrue(txtContent.contains("[TH] First paragraph."))
        try assertTrue(txtContent.contains("[TH] Second paragraph."))

        let pdfOut = try await engine.translateFile(source: scannedPDF, to: .en, translator: MockTranslator(), toolPaths: tools)
        try assertEqual(pdfOut.lastPathComponent, "scan EN.txt")
        let pdfContent = try String(contentsOf: pdfOut, encoding: .utf8)
        try assertTrue(pdfContent.contains("[EN]"))
        try assertTrue(pdfContent.range(of: "Hello", options: .caseInsensitive) != nil)
    }

    runner.test("Task6", "JobExecutor merges 2 images into 1 PDF and batch-converts 2 TXT files to HTML") {
        let dir = try makeTempDirectory("Task6Executor")
        defer { try? FileManager.default.removeItem(at: dir) }

        let img1 = dir.appendingPathComponent("p1.png")
        let img2 = dir.appendingPathComponent("p2.jpg")
        try TestFixtures.createTestImage(at: img1, width: 400, height: 300, utType: .png)
        try TestFixtures.createTestImage(at: img2, width: 400, height: 300, utType: .jpeg)

        let executor = JobExecutor(translator: MockTranslator())
        let mergeResult = try await executor.execute(urls: [img1, img2], action: .mergePDF, settings: AppSettings()) { _ in }
        try assertEqual(mergeResult.outputURLs.count, 1)
        try assertEqual(PDFDocument(url: mergeResult.outputURLs[0])?.pageCount ?? 0, 2)

        let t1 = dir.appendingPathComponent("a.txt")
        let t2 = dir.appendingPathComponent("b.txt")
        try "One".write(to: t1, atomically: true, encoding: .utf8)
        try "Two".write(to: t2, atomically: true, encoding: .utf8)

        let batchResult = try await executor.execute(urls: [t1, t2], action: .toHTML, settings: AppSettings()) { _ in }
        try assertEqual(batchResult.outputURLs.count, 2)
        try assertTrue(batchResult.outputURLs.allSatisfy { $0.pathExtension.lowercased() == "html" })
    }
}


func registerTask7Tests(_ runner: TestSuiteRunner) {
    runner.test("Task7", "WheelGeometry returns cancel inside inner hub or outside ring") {
        let center = CGPoint(x: 130, y: 130)
        try assertEqual(
            WheelGeometry.hitTest(point: CGPoint(x: 130, y: 130), center: center, innerRadius: 42, outerRadius: 126, sliceCount: 6),
            .cancel
        )
        try assertEqual(
            WheelGeometry.hitTest(point: CGPoint(x: 150, y: 130), center: center, innerRadius: 42, outerRadius: 126, sliceCount: 6),
            .cancel
        )
        try assertEqual(
            WheelGeometry.hitTest(point: CGPoint(x: 260, y: 130), center: center, innerRadius: 42, outerRadius: 126, sliceCount: 6),
            .cancel
        )
        try assertEqual(
            WheelGeometry.hitTest(point: CGPoint(x: 130, y: 200), center: center, innerRadius: 42, outerRadius: 126, sliceCount: 0),
            .cancel
        )
    }

    runner.test("Task7", "WheelGeometry maps top/clockwise ring points in AppKit coordinates to slices") {
        let center = CGPoint(x: 130, y: 130)
        // AppKit coordinates: +y is UP (top = slice 0), +x is RIGHT (3 o'clock = slice 1 for 4 slices), -y is DOWN (6 o'clock = slice 2), -x is LEFT (9 o'clock = slice 3).
        try assertEqual(
            WheelGeometry.hitTest(point: CGPoint(x: 130, y: 210), center: center, innerRadius: 42, outerRadius: 126, sliceCount: 4),
            .slice(0)
        )
        try assertEqual(
            WheelGeometry.hitTest(point: CGPoint(x: 210, y: 130), center: center, innerRadius: 42, outerRadius: 126, sliceCount: 4),
            .slice(1)
        )
        try assertEqual(
            WheelGeometry.hitTest(point: CGPoint(x: 130, y: 50), center: center, innerRadius: 42, outerRadius: 126, sliceCount: 4),
            .slice(2)
        )
        try assertEqual(
            WheelGeometry.hitTest(point: CGPoint(x: 50, y: 130), center: center, innerRadius: 42, outerRadius: 126, sliceCount: 4),
            .slice(3)
        )
    }

    runner.test("Task7", "ModifierTrigger matches only the configured modifier flag") {
        try assertTrue(ModifierTrigger.shift.matches(flags: [.shift]))
        try assertTrue(!ModifierTrigger.shift.matches(flags: []))
        try assertTrue(!ModifierTrigger.shift.matches(flags: [.option]))

        try assertTrue(ModifierTrigger.option.matches(flags: [.option]))
        try assertTrue(!ModifierTrigger.option.matches(flags: [.shift]))

        try assertTrue(ModifierTrigger.control.matches(flags: [.control]))
        try assertTrue(!ModifierTrigger.control.matches(flags: [.command]))
    }
}
