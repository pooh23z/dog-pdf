import Foundation
import MacWheelCore

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
