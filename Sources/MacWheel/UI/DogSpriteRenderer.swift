import AppKit
import MacWheelCore
import SwiftUI

enum DogSpriteRenderer {
    /// Renders a crisp 28x18pt template NSImage for the macOS Menu Bar for any of the 10 animals.
    static func menuBarImage(for pose: DogPose, character: MascotCharacter = .shiba) -> NSImage {
        let size = NSSize(width: 28, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.saveGState()

            let bob = min(pose.headBobY * 0.55, 1.4)
            let baseY: CGFloat = 1.0 + bob
            let ink = NSColor.black

            switch character {
            case .shiba:
                drawQuadruped(ctx: ctx, baseY: baseY, pose: pose, ink: ink, style: .shiba)
            case .cat:
                drawQuadruped(ctx: ctx, baseY: baseY, pose: pose, ink: ink, style: .cat)
            case .rabbit:
                drawQuadruped(ctx: ctx, baseY: baseY, pose: pose, ink: ink, style: .rabbit)
            case .bear:
                drawQuadruped(ctx: ctx, baseY: baseY, pose: pose, ink: ink, style: .bear)
            case .panda:
                drawQuadruped(ctx: ctx, baseY: baseY, pose: pose, ink: ink, style: .panda)
            case .fox:
                drawQuadruped(ctx: ctx, baseY: baseY, pose: pose, ink: ink, style: .fox)
            case .penguin:
                drawPenguin(ctx: ctx, baseY: baseY, pose: pose, ink: ink)
            case .duck:
                drawDuck(ctx: ctx, baseY: baseY, pose: pose, ink: ink)
            case .frog:
                drawFrog(ctx: ctx, baseY: baseY, pose: pose, ink: ink)
            case .owl:
                drawOwl(ctx: ctx, baseY: baseY, pose: pose, ink: ink)
            }

            if pose.showHeart {
                drawHeart(x: 24.4, y: baseY + 10.2, ink: ink)
            }

            ctx.restoreGState()
            return true
        }
        image.isTemplate = true
        return image
    }

    private enum QuadrupedStyle { case shiba, cat, rabbit, bear, panda, fox }

    private static func drawQuadruped(
        ctx: CGContext,
        baseY: CGFloat,
        pose: DogPose,
        ink: NSColor,
        style: QuadrupedStyle
    ) {
        // 1. Tail
        ctx.saveGState()
        ctx.translateBy(x: 6.4, y: baseY + 5.8)
        ctx.rotate(by: (22 + pose.tailAngleDeg) * .pi / 180.0)
        ink.setFill()
        ink.setStroke()
        switch style {
        case .rabbit, .bear, .panda:
            let puff = NSBezierPath(ovalIn: NSRect(x: -2.8, y: -1.0, width: 3.4, height: 3.4))
            puff.fill()
        case .fox:
            let bushy = NSBezierPath(ovalIn: NSRect(x: -6.2, y: -0.4, width: 6.8, height: 3.8))
            bushy.fill()
        case .cat:
            let tail = NSBezierPath()
            tail.move(to: .zero)
            tail.curve(to: NSPoint(x: -4.2, y: 6.2),
                       controlPoint1: NSPoint(x: -3.2, y: 1.0),
                       controlPoint2: NSPoint(x: -1.4, y: 5.8))
            tail.lineWidth = 1.9
            tail.lineCapStyle = .round
            tail.stroke()
        case .shiba:
            let tail = NSBezierPath()
            tail.move(to: .zero)
            tail.curve(to: NSPoint(x: -4.0, y: 4.4),
                       controlPoint1: NSPoint(x: -2.6, y: 0.5),
                       controlPoint2: NSPoint(x: -4.4, y: 2.8))
            tail.lineWidth = 2.4
            tail.lineCapStyle = .round
            tail.stroke()
        }
        ctx.restoreGState()

        // 2. Body
        let bodyH: CGFloat = (style == .bear || style == .panda) ? 6.6 : 5.8
        let bodyRect = NSRect(x: 5.8, y: baseY + 2.9, width: 10.6, height: bodyH)
        ink.setFill()
        NSBezierPath(roundedRect: bodyRect, xRadius: bodyH / 2.0, yRadius: bodyH / 2.0).fill()

        // 3. Legs
        let swing = pose.stridePhase * (style == .rabbit ? 2.4 : 1.9)
        if style == .rabbit {
            drawLeg(x: 6.5 - swing * 0.6, y: baseY + max(0, -swing * 0.4), width: 3.0, height: 4.2, ink: ink)
            drawLeg(x: 13.6 + swing * 0.6, y: baseY + max(0, swing * 0.5), width: 2.2, height: 4.4, ink: ink)
        } else {
            drawLeg(x: 6.5 - swing * 0.65, y: baseY + max(0, -swing * 0.35), width: 2.1, height: 4.5, ink: ink)
            drawLeg(x: 8.8 + swing * 0.45, y: baseY + max(0, swing * 0.25), width: 2.1, height: 4.4, ink: ink)
            drawLeg(x: 12.1 - swing * 0.45, y: baseY + max(0, -swing * 0.25), width: 2.1, height: 4.4, ink: ink)
            drawLeg(x: 14.1 + swing * 0.65, y: baseY + max(0, swing * 0.40), width: 2.1, height: 4.5, ink: ink)
        }

        // 4. Head
        let headCenter = NSPoint(x: 16.2, y: baseY + 8.3)
        let headW: CGFloat = (style == .bear || style == .panda) ? 8.4 : 7.8
        let headH: CGFloat = (style == .bear || style == .panda) ? 7.4 : 7.0
        NSBezierPath(
            roundedRect: NSRect(x: headCenter.x - headW / 2, y: headCenter.y - headH / 2, width: headW, height: headH),
            xRadius: headH / 2,
            yRadius: headH / 2
        ).fill()

        // 5. Snout
        if style == .fox {
            let snout = NSBezierPath()
            snout.move(to: NSPoint(x: headCenter.x + 2.4, y: headCenter.y + 0.8))
            snout.line(to: NSPoint(x: headCenter.x + 6.4, y: headCenter.y - 0.8))
            snout.line(to: NSPoint(x: headCenter.x + 2.4, y: headCenter.y - 2.3))
            snout.close()
            snout.fill()
        } else if style != .cat {
            let snoutW: CGFloat = (style == .rabbit) ? 2.4 : 3.3
            NSBezierPath(
                roundedRect: NSRect(x: headCenter.x + 2.2, y: headCenter.y - 2.2, width: snoutW, height: 2.9),
                xRadius: 1.3,
                yRadius: 1.3
            ).fill()
        }

        // 6. Ears
        switch style {
        case .rabbit:
            drawRotatedRectEar(ctx: ctx, x: headCenter.x - 1.4, y: headCenter.y + 2.4, angle: 16 + pose.earBounceDeg, w: 2.3, h: 6.2, ink: ink)
            drawRotatedRectEar(ctx: ctx, x: headCenter.x + 0.6, y: headCenter.y + 2.5, angle: 6 - pose.earBounceDeg * 0.5, w: 2.1, h: 5.8, ink: ink)
        case .cat, .fox:
            let earH: CGFloat = style == .fox ? 4.4 : 3.6
            drawPointyEar(ctx: ctx, x: headCenter.x - 1.6, y: headCenter.y + 2.3, angle: pose.earBounceDeg * 0.7, w: 3.0, h: earH, ink: ink)
            drawPointyEar(ctx: ctx, x: headCenter.x + 1.0, y: headCenter.y + 2.3, angle: -pose.earBounceDeg * 0.4, w: 2.8, h: earH, ink: ink)
        case .bear, .panda:
            NSBezierPath(ovalIn: NSRect(x: headCenter.x - 3.8, y: headCenter.y + 2.2, width: 3.2, height: 3.2)).fill()
            NSBezierPath(ovalIn: NSRect(x: headCenter.x + 0.6, y: headCenter.y + 2.2, width: 3.2, height: 3.2)).fill()
        case .shiba:
            drawRotatedRectEar(ctx: ctx, x: headCenter.x - 1.3, y: headCenter.y + 2.4, angle: pose.earBounceDeg, w: 2.7, h: 3.5, ink: ink)
            drawRotatedRectEar(ctx: ctx, x: headCenter.x + 0.9, y: headCenter.y + 2.5, angle: -pose.earBounceDeg * 0.45, w: 2.4, h: 3.1, ink: ink)
        }

        // 7. Eye cutout
        drawEyeCutout(ctx: ctx, x: headCenter.x + 1.4, y: headCenter.y + 0.4, isBlinking: pose.isBlinking, large: style == .panda)
    }

    private static func drawPenguin(ctx: CGContext, baseY: CGFloat, pose: DogPose, ink: NSColor) {
        let cx: CGFloat = 14.0
        ink.setFill()
        // Plump upright body + head
        NSBezierPath(ovalIn: NSRect(x: cx - 5.2, y: baseY + 1.6, width: 10.4, height: 11.4)).fill()
        NSBezierPath(ovalIn: NSRect(x: cx - 4.0, y: baseY + 8.6, width: 8.0, height: 7.0)).fill()
        // Pointed beak facing right
        let beak = NSBezierPath()
        beak.move(to: NSPoint(x: cx + 3.2, y: baseY + 12.6))
        beak.line(to: NSPoint(x: cx + 6.4, y: baseY + 11.4))
        beak.line(to: NSPoint(x: cx + 3.2, y: baseY + 10.3))
        beak.close()
        beak.fill()
        // Flapping flipper
        ctx.saveGState()
        ctx.translateBy(x: cx - 3.6, y: baseY + 8.6)
        ctx.rotate(by: (22 + pose.tailAngleDeg * 0.9) * .pi / 180.0)
        NSBezierPath(roundedRect: NSRect(x: -3.2, y: -4.2, width: 2.8, height: 5.2), xRadius: 1.3, yRadius: 1.3).fill()
        ctx.restoreGState()
        // Waddling feet
        let waddle = pose.stridePhase * 1.4
        NSBezierPath(roundedRect: NSRect(x: cx - 3.6, y: baseY + max(0, waddle), width: 3.0, height: 1.8), xRadius: 0.8, yRadius: 0.8).fill()
        NSBezierPath(roundedRect: NSRect(x: cx + 0.8, y: baseY + max(0, -waddle), width: 3.0, height: 1.8), xRadius: 0.8, yRadius: 0.8).fill()
        // Belly & eye cutout
        ctx.saveGState()
        NSGraphicsContext.current?.compositingOperation = .clear
        NSBezierPath(ovalIn: NSRect(x: cx - 1.2, y: baseY + 3.2, width: 4.8, height: 6.2)).fill()
        ctx.restoreGState()
        drawEyeCutout(ctx: ctx, x: cx + 1.5, y: baseY + 12.6, isBlinking: pose.isBlinking, large: false)
    }

    private static func drawDuck(ctx: CGContext, baseY: CGFloat, pose: DogPose, ink: NSColor) {
        ink.setFill()
        // Duck body + raised tail
        NSBezierPath(ovalIn: NSRect(x: 6.2, y: baseY + 2.8, width: 11.2, height: 6.6)).fill()
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 7.4, y: baseY + 6.8))
        tail.line(to: NSPoint(x: 3.8, y: baseY + 9.2 + pose.earBounceDeg * 0.06))
        tail.line(to: NSPoint(x: 8.6, y: baseY + 4.4))
        tail.close()
        tail.fill()
        // Head + duck bill
        let hx: CGFloat = 15.8
        let hy: CGFloat = baseY + 10.2
        NSBezierPath(ovalIn: NSRect(x: hx - 3.6, y: hy - 3.4, width: 7.2, height: 6.8)).fill()
        NSBezierPath(roundedRect: NSRect(x: hx + 2.4, y: hy - 1.6, width: 4.2, height: 2.3), xRadius: 1.1, yRadius: 1.1).fill()
        // Feet
        let step = pose.stridePhase * 1.6
        drawLeg(x: 9.8 - step * 0.6, y: baseY + max(0, -step * 0.3), width: 1.8, height: 3.6, ink: ink)
        drawLeg(x: 12.6 + step * 0.6, y: baseY + max(0, step * 0.3), width: 1.8, height: 3.6, ink: ink)
        // Wing cutout hint + eye
        ctx.saveGState()
        NSGraphicsContext.current?.compositingOperation = .clear
        let wing = NSBezierPath()
        wing.move(to: NSPoint(x: 9.2, y: baseY + 6.2))
        wing.curve(to: NSPoint(x: 13.8, y: baseY + 5.8 + pose.tailAngleDeg * 0.03),
                   controlPoint1: NSPoint(x: 10.8, y: baseY + 4.2),
                   controlPoint2: NSPoint(x: 12.8, y: baseY + 4.6))
        wing.lineWidth = 1.2
        wing.stroke()
        ctx.restoreGState()
        drawEyeCutout(ctx: ctx, x: hx + 1.0, y: hy + 0.8, isBlinking: pose.isBlinking, large: false)
    }

    private static func drawFrog(ctx: CGContext, baseY: CGFloat, pose: DogPose, ink: NSColor) {
        let cx: CGFloat = 14.0
        ink.setFill()
        // Plump frog body
        NSBezierPath(ovalIn: NSRect(x: cx - 7.0, y: baseY + 2.0, width: 14.0, height: 9.2)).fill()
        // Perched eyes on top of head
        NSBezierPath(ovalIn: NSRect(x: cx - 5.2, y: baseY + 9.0, width: 4.6, height: 4.6)).fill()
        NSBezierPath(ovalIn: NSRect(x: cx + 0.6, y: baseY + 9.0, width: 4.6, height: 4.6)).fill()
        // Hopping feet
        let hop = abs(pose.stridePhase) * 1.8
        NSBezierPath(roundedRect: NSRect(x: cx - 8.2, y: baseY + 0.4 + hop * 0.4, width: 4.4, height: 2.3), xRadius: 1.1, yRadius: 1.1).fill()
        NSBezierPath(roundedRect: NSRect(x: cx + 3.8, y: baseY + 0.4 + hop * 0.4, width: 4.4, height: 2.3), xRadius: 1.1, yRadius: 1.1).fill()
        // Eye cutouts & smile
        drawEyeCutout(ctx: ctx, x: cx - 2.9, y: baseY + 11.4, isBlinking: pose.isBlinking, large: false)
        drawEyeCutout(ctx: ctx, x: cx + 2.9, y: baseY + 11.4, isBlinking: pose.isBlinking, large: false)
        ctx.saveGState()
        NSGraphicsContext.current?.compositingOperation = .clear
        let smile = NSBezierPath()
        smile.move(to: NSPoint(x: cx - 3.0, y: baseY + 6.4))
        smile.curve(to: NSPoint(x: cx + 3.0, y: baseY + 6.4),
                    controlPoint1: NSPoint(x: cx - 1.2, y: baseY + 4.8),
                    controlPoint2: NSPoint(x: cx + 1.2, y: baseY + 4.8))
        smile.lineWidth = 1.2
        smile.lineCapStyle = .round
        smile.stroke()
        ctx.restoreGState()
    }

    private static func drawOwl(ctx: CGContext, baseY: CGFloat, pose: DogPose, ink: NSColor) {
        let cx: CGFloat = 14.0
        ink.setFill()
        // Round plump owl body
        NSBezierPath(ovalIn: NSRect(x: cx - 5.6, y: baseY + 1.8, width: 11.2, height: 12.4)).fill()
        // Ear tufts
        drawPointyEar(ctx: ctx, x: cx - 3.6, y: baseY + 12.2, angle: 18, w: 3.0, h: 3.4, ink: ink)
        drawPointyEar(ctx: ctx, x: cx + 3.6, y: baseY + 12.2, angle: -18, w: 3.0, h: 3.4, ink: ink)
        // Flapping wings
        let flap = pose.tailAngleDeg * 0.9
        ctx.saveGState()
        ctx.translateBy(x: cx - 4.8, y: baseY + 8.6)
        ctx.rotate(by: (18 + flap) * .pi / 180.0)
        NSBezierPath(ovalIn: NSRect(x: -3.2, y: -3.8, width: 3.4, height: 5.4)).fill()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.translateBy(x: cx + 4.8, y: baseY + 8.6)
        ctx.rotate(by: (-18 - flap) * .pi / 180.0)
        NSBezierPath(ovalIn: NSRect(x: -0.2, y: -3.8, width: 3.4, height: 5.4)).fill()
        ctx.restoreGState()
        // Big owl eyes cutout
        drawEyeCutout(ctx: ctx, x: cx - 2.3, y: baseY + 10.2, isBlinking: pose.isBlinking, large: true)
        drawEyeCutout(ctx: ctx, x: cx + 2.3, y: baseY + 10.2, isBlinking: pose.isBlinking, large: true)
    }

    private static func drawLeg(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, ink: NSColor) {
        ink.setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: height), xRadius: width / 2, yRadius: width / 2).fill()
    }

    private static func drawRotatedRectEar(ctx: CGContext, x: CGFloat, y: CGFloat, angle: CGFloat, w: CGFloat, h: CGFloat, ink: NSColor) {
        ctx.saveGState()
        ctx.translateBy(x: x, y: y)
        ctx.rotate(by: angle * .pi / 180.0)
        ink.setFill()
        NSBezierPath(roundedRect: NSRect(x: -w / 2, y: -0.4, width: w, height: h), xRadius: w / 2, yRadius: w / 2).fill()
        ctx.restoreGState()
    }

    private static func drawPointyEar(ctx: CGContext, x: CGFloat, y: CGFloat, angle: CGFloat, w: CGFloat, h: CGFloat, ink: NSColor) {
        ctx.saveGState()
        ctx.translateBy(x: x, y: y)
        ctx.rotate(by: angle * .pi / 180.0)
        let tri = NSBezierPath()
        tri.move(to: NSPoint(x: -w / 2, y: -0.4))
        tri.line(to: NSPoint(x: 0, y: h))
        tri.line(to: NSPoint(x: w / 2, y: -0.4))
        tri.close()
        ink.setFill()
        tri.fill()
        ctx.restoreGState()
    }

    private static func drawEyeCutout(ctx: CGContext, x: CGFloat, y: CGFloat, isBlinking: Bool, large: Bool) {
        ctx.saveGState()
        NSGraphicsContext.current?.compositingOperation = .clear
        if isBlinking {
            let blink = NSBezierPath()
            blink.move(to: NSPoint(x: x - 0.9, y: y))
            blink.line(to: NSPoint(x: x + 0.9, y: y))
            blink.lineWidth = 1.1
            blink.lineCapStyle = .round
            blink.stroke()
        } else {
            let d: CGFloat = large ? 2.0 : 1.5
            NSBezierPath(ovalIn: NSRect(x: x - d / 2, y: y - d / 2, width: d, height: d)).fill()
        }
        ctx.restoreGState()
    }

    private static func drawHeart(x: CGFloat, y: CGFloat, ink: NSColor) {
        let heart = NSBezierPath()
        heart.move(to: NSPoint(x: x, y: y))
        heart.curve(to: NSPoint(x: x - 2.1, y: y + 2.2),
                    controlPoint1: NSPoint(x: x - 1.6, y: y + 0.8),
                    controlPoint2: NSPoint(x: x - 2.3, y: y + 1.6))
        heart.curve(to: NSPoint(x: x, y: y + 1.8),
                    controlPoint1: NSPoint(x: x - 1.8, y: y + 3.0),
                    controlPoint2: NSPoint(x: x - 0.3, y: y + 2.8))
        heart.curve(to: NSPoint(x: x + 2.1, y: y + 2.2),
                    controlPoint1: NSPoint(x: x + 0.3, y: y + 2.8),
                    controlPoint2: NSPoint(x: x + 1.8, y: y + 3.0))
        heart.curve(to: NSPoint(x: x, y: y),
                    controlPoint1: NSPoint(x: x + 2.3, y: y + 1.6),
                    controlPoint2: NSPoint(x: x + 1.6, y: y + 0.8))
        heart.close()
        ink.setFill()
        heart.fill()
    }
}

/// Live-animated full-color mascot supporting all 10 animal characters.
struct AnimatedDogMascotView: View {
    let character: MascotCharacter
    let isBusy: Bool
    var size: CGFloat = 40

    init(character: MascotCharacter = .shiba, isBusy: Bool, size: CGFloat = 40) {
        self.character = character
        self.isBusy = isBusy
        self.size = size
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let speed = isBusy ? 11.5 : 4.2
            let wagDeg = sin(t * speed) * (isBusy ? 26.0 : 16.0)
            let bounceY = abs(sin(t * (isBusy ? 8.5 : 3.0))) * (isBusy ? -3.0 : -1.2)
            let tiltDeg = sin(t * (isBusy ? 8.5 : 2.1)) * (isBusy ? 6.0 : 2.6)
            let isBlinking = !isBusy && (t.truncatingRemainder(dividingBy: 3.8) > 3.62)

            Canvas { ctx, canvasSize in
                let scale = min(canvasSize.width, canvasSize.height) / 42.0
                ctx.translateBy(x: canvasSize.width / 2, y: canvasSize.height / 2 + bounceY * scale)
                ctx.scaleBy(x: scale, y: scale)

                let bgPalette = backgroundColors(for: character)
                ctx.fill(
                    Path(roundedRect: CGRect(x: -19, y: -19, width: 38, height: 38), cornerRadius: 11),
                    with: .linearGradient(
                        Gradient(colors: bgPalette),
                        startPoint: CGPoint(x: 0, y: -19),
                        endPoint: CGPoint(x: 0, y: 19)
                    )
                )

                drawMascot(ctx: &ctx, character: character, wagDeg: wagDeg, tiltDeg: tiltDeg, isBlinking: isBlinking)
            }
            .frame(width: size, height: size)
        }
    }

    private func backgroundColors(for c: MascotCharacter) -> [Color] {
        switch c {
        case .shiba: return [Color(red: 1.0, green: 0.95, blue: 0.87), Color(red: 0.99, green: 0.85, blue: 0.68)]
        case .cat: return [Color(red: 1.0, green: 0.93, blue: 0.90), Color(red: 0.99, green: 0.82, blue: 0.74)]
        case .rabbit: return [Color(red: 1.0, green: 0.93, blue: 0.96), Color(red: 0.98, green: 0.82, blue: 0.89)]
        case .bear: return [Color(red: 0.97, green: 0.92, blue: 0.86), Color(red: 0.90, green: 0.80, blue: 0.69)]
        case .penguin: return [Color(red: 0.88, green: 0.96, blue: 1.0), Color(red: 0.73, green: 0.89, blue: 0.99)]
        case .duck: return [Color(red: 1.0, green: 0.98, blue: 0.84), Color(red: 0.99, green: 0.90, blue: 0.58)]
        case .panda: return [Color(red: 0.91, green: 0.98, blue: 0.92), Color(red: 0.76, green: 0.93, blue: 0.80)]
        case .fox: return [Color(red: 1.0, green: 0.93, blue: 0.85), Color(red: 0.99, green: 0.79, blue: 0.60)]
        case .frog: return [Color(red: 0.90, green: 0.99, blue: 0.88), Color(red: 0.74, green: 0.94, blue: 0.72)]
        case .owl: return [Color(red: 0.94, green: 0.91, blue: 0.99), Color(red: 0.83, green: 0.78, blue: 0.96)]
        }
    }

    private func drawMascot(ctx: inout GraphicsContext, character: MascotCharacter, wagDeg: Double, tiltDeg: Double, isBlinking: Bool) {
        let blush = Color(red: 1.0, green: 0.52, blue: 0.56, opacity: 0.45)

        switch character {
        case .shiba, .cat, .fox:
            let primary: Color
            let secondary: Color
            let belly = Color(red: 1.0, green: 0.97, blue: 0.91)
            switch character {
            case .shiba:
                primary = Color(red: 0.98, green: 0.72, blue: 0.38)
                secondary = Color(red: 0.88, green: 0.54, blue: 0.22)
            case .cat:
                primary = Color(red: 0.99, green: 0.76, blue: 0.54)
                secondary = Color(red: 0.87, green: 0.52, blue: 0.28)
            default:
                primary = Color(red: 0.94, green: 0.45, blue: 0.16)
                secondary = Color(red: 0.78, green: 0.30, blue: 0.10)
            }

            // Wagging tail
            ctx.drawLayer { layer in
                layer.translateBy(x: -7, y: 10)
                layer.rotate(by: .degrees(-20 + wagDeg))
                var tail = Path()
                tail.move(to: .zero)
                tail.addQuadCurve(to: CGPoint(x: -7, y: -8), control: CGPoint(x: -9, y: 0))
                layer.stroke(tail, with: .color(character == .fox ? primary : secondary), style: StrokeStyle(lineWidth: character == .fox ? 5.2 : 3.4, lineCap: .round))
                if character == .fox {
                    layer.fill(Path(ellipseIn: CGRect(x: -9.5, y: -10.5, width: 4.5, height: 4.5)), with: .color(.white))
                }
            }

            // Body
            ctx.fill(Path(roundedRect: CGRect(x: -8, y: 3, width: 16, height: 12), cornerRadius: 6), with: .color(secondary))
            ctx.fill(Path(ellipseIn: CGRect(x: -5, y: 5, width: 10, height: 8)), with: .color(belly))

            // Head
            ctx.drawLayer { h in
                h.translateBy(x: 0, y: -2.5)
                h.rotate(by: .degrees(tiltDeg))
                drawTriangleEar(in: &h, x: -7.5, y: -6, tipX: -10.5, tipY: character == .fox ? -14.5 : -13, color: secondary)
                drawTriangleEar(in: &h, x: 7.5, y: -6, tipX: 10.5, tipY: character == .fox ? -14.5 : -13, color: secondary)
                h.fill(Path(ellipseIn: CGRect(x: -10.5, y: -8.5, width: 21, height: 17.5)), with: .color(primary))
                h.fill(Path(ellipseIn: CGRect(x: -7.5, y: -1.5, width: 15, height: 10)), with: .color(belly))
                h.fill(Path(ellipseIn: CGRect(x: -9.0, y: 0.5, width: 3.4, height: 2.2)), with: .color(blush))
                h.fill(Path(ellipseIn: CGRect(x: 5.6, y: 0.5, width: 3.4, height: 2.2)), with: .color(blush))

                if character == .shiba {
                    let g = StrokeStyle(lineWidth: 1.3, lineCap: .round)
                    h.stroke(Path(ellipseIn: CGRect(x: -7.8, y: -5.4, width: 6.2, height: 6.2)), with: .color(Color(white: 0.18)), style: g)
                    h.stroke(Path(ellipseIn: CGRect(x: 1.6, y: -5.4, width: 6.2, height: 6.2)), with: .color(Color(white: 0.18)), style: g)
                    var br = Path()
                    br.move(to: CGPoint(x: -1.6, y: -2.3))
                    br.addLine(to: CGPoint(x: 1.6, y: -2.3))
                    h.stroke(br, with: .color(Color(white: 0.18)), style: g)
                }
                if character == .cat {
                    // Cat whiskers
                    let wStyle = StrokeStyle(lineWidth: 0.9, lineCap: .round)
                    for dy in [-0.2, 1.8] {
                        var lw = Path(); lw.move(to: CGPoint(x: -6.5, y: dy)); lw.addLine(to: CGPoint(x: -11.5, y: dy + (dy > 0 ? 0.8 : -0.6)))
                        var rw = Path(); rw.move(to: CGPoint(x: 6.5, y: dy)); rw.addLine(to: CGPoint(x: 11.5, y: dy + (dy > 0 ? 0.8 : -0.6)))
                        h.stroke(lw, with: .color(Color(white: 0.35)), style: wStyle)
                        h.stroke(rw, with: .color(Color(white: 0.35)), style: wStyle)
                    }
                }
                drawCuteEyes(in: &h, xOffset: 4.5, y: -2.2, isBlinking: isBlinking)
                drawCuteNoseAndSmile(in: &h, y: 0.4)
            }

        case .rabbit:
            ctx.fill(Path(roundedRect: CGRect(x: -7.5, y: 4, width: 15, height: 11), cornerRadius: 5.5), with: .color(.white))
            ctx.drawLayer { h in
                h.translateBy(x: 0, y: -1)
                h.rotate(by: .degrees(tiltDeg))
                // Long bouncing bunny ears
                h.drawLayer { e in
                    e.translateBy(x: -5, y: -6)
                    e.rotate(by: .degrees(-10 + wagDeg * 0.35))
                    e.fill(Path(roundedRect: CGRect(x: -2.5, y: -10.5, width: 5, height: 11.5), cornerRadius: 2.5), with: .color(.white))
                    e.fill(Path(roundedRect: CGRect(x: -1.3, y: -9, width: 2.6, height: 8.5), cornerRadius: 1.3), with: .color(Color(red: 1.0, green: 0.72, blue: 0.80)))
                }
                h.drawLayer { e in
                    e.translateBy(x: 5, y: -6)
                    e.rotate(by: .degrees(10 - wagDeg * 0.35))
                    e.fill(Path(roundedRect: CGRect(x: -2.5, y: -10.5, width: 5, height: 11.5), cornerRadius: 2.5), with: .color(.white))
                    e.fill(Path(roundedRect: CGRect(x: -1.3, y: -9, width: 2.6, height: 8.5), cornerRadius: 1.3), with: .color(Color(red: 1.0, green: 0.72, blue: 0.80)))
                }
                h.fill(Path(ellipseIn: CGRect(x: -10, y: -7.5, width: 20, height: 16.5)), with: .color(.white))
                h.fill(Path(ellipseIn: CGRect(x: -8.2, y: 1.0, width: 3.4, height: 2.2)), with: .color(blush))
                h.fill(Path(ellipseIn: CGRect(x: 4.8, y: 1.0, width: 3.4, height: 2.2)), with: .color(blush))
                drawCuteEyes(in: &h, xOffset: 4.2, y: -1.4, isBlinking: isBlinking)
                h.fill(Path(ellipseIn: CGRect(x: -1.6, y: 0.8, width: 3.2, height: 2.1)), with: .color(Color(red: 1.0, green: 0.58, blue: 0.68)))
                drawSmileOnly(in: &h, y: 3.4)
            }

        case .bear, .panda:
            let isPanda = (character == .panda)
            let fur = isPanda ? Color.white : Color(red: 0.64, green: 0.42, blue: 0.25)
            let earColor = isPanda ? Color(white: 0.16) : Color(red: 0.52, green: 0.33, blue: 0.19)
            let muzzle = isPanda ? Color.white : Color(red: 0.94, green: 0.84, blue: 0.72)

            ctx.fill(Path(roundedRect: CGRect(x: -8.5, y: 3.5, width: 17, height: 12), cornerRadius: 6), with: .color(earColor))
            ctx.fill(Path(ellipseIn: CGRect(x: -5.5, y: 5.5, width: 11, height: 8)), with: .color(fur))
            ctx.drawLayer { h in
                h.translateBy(x: 0, y: -2)
                h.rotate(by: .degrees(tiltDeg))
                h.fill(Path(ellipseIn: CGRect(x: -11, y: -11.5, width: 6.4, height: 6.4)), with: .color(earColor))
                h.fill(Path(ellipseIn: CGRect(x: 4.6, y: -11.5, width: 6.4, height: 6.4)), with: .color(earColor))
                h.fill(Path(ellipseIn: CGRect(x: -10.5, y: -8.5, width: 21, height: 17.5)), with: .color(fur))
                if isPanda {
                    h.fill(Path(ellipseIn: CGRect(x: -7.8, y: -4.8, width: 5.8, height: 5.2)), with: .color(Color(white: 0.16)))
                    h.fill(Path(ellipseIn: CGRect(x: 2.0, y: -4.8, width: 5.8, height: 5.2)), with: .color(Color(white: 0.16)))
                    drawCuteEyes(in: &h, xOffset: 4.8, y: -2.2, isBlinking: isBlinking, color: .white)
                } else {
                    h.fill(Path(ellipseIn: CGRect(x: -5.4, y: -1.0, width: 10.8, height: 7.6)), with: .color(muzzle))
                    drawCuteEyes(in: &h, xOffset: 4.6, y: -2.4, isBlinking: isBlinking)
                }
                h.fill(Path(ellipseIn: CGRect(x: -9.0, y: 1.0, width: 3.2, height: 2.0)), with: .color(blush))
                h.fill(Path(ellipseIn: CGRect(x: 5.8, y: 1.0, width: 3.2, height: 2.0)), with: .color(blush))
                drawCuteNoseAndSmile(in: &h, y: 0.6)
            }

        case .penguin:
            let dark = Color(red: 0.16, green: 0.20, blue: 0.28)
            let orange = Color(red: 0.99, green: 0.56, blue: 0.14)
            // Flapping flippers
            ctx.drawLayer { l in
                l.translateBy(x: -9, y: 2)
                l.rotate(by: .degrees(18 + wagDeg * 0.9))
                l.fill(Path(ellipseIn: CGRect(x: -4, y: -2, width: 5, height: 10)), with: .color(dark))
            }
            ctx.drawLayer { r in
                r.translateBy(x: 9, y: 2)
                r.rotate(by: .degrees(-18 - wagDeg * 0.9))
                r.fill(Path(ellipseIn: CGRect(x: -1, y: -2, width: 5, height: 10)), with: .color(dark))
            }
            // Feet
            ctx.fill(Path(ellipseIn: CGRect(x: -7, y: 12, width: 5.5, height: 3)), with: .color(orange))
            ctx.fill(Path(ellipseIn: CGRect(x: 1.5, y: 12, width: 5.5, height: 3)), with: .color(orange))
            // Body
            ctx.fill(Path(ellipseIn: CGRect(x: -10.5, y: -11, width: 21, height: 24.5)), with: .color(dark))
            ctx.fill(Path(ellipseIn: CGRect(x: -7.5, y: -5.5, width: 15, height: 17.5)), with: .color(.white))
            ctx.fill(Path(ellipseIn: CGRect(x: -8.0, y: -1.5, width: 3.0, height: 2.0)), with: .color(blush))
            ctx.fill(Path(ellipseIn: CGRect(x: 5.0, y: -1.5, width: 3.0, height: 2.0)), with: .color(blush))
            drawCuteEyes(in: &ctx, xOffset: 4.0, y: -4.2, isBlinking: isBlinking)
            var beak = Path()
            beak.move(to: CGPoint(x: -3.2, y: -2.0))
            beak.addLine(to: CGPoint(x: 3.2, y: -2.0))
            beak.addLine(to: CGPoint(x: 0, y: 1.8))
            beak.closeSubpath()
            ctx.fill(beak, with: .color(orange))

        case .duck:
            let yellow = Color(red: 1.0, green: 0.84, blue: 0.24)
            let orange = Color(red: 0.99, green: 0.52, blue: 0.14)
            ctx.drawLayer { l in
                l.translateBy(x: -9, y: 4)
                l.rotate(by: .degrees(14 + wagDeg * 0.8))
                l.fill(Path(ellipseIn: CGRect(x: -4, y: -2, width: 5.5, height: 8)), with: .color(yellow))
            }
            ctx.drawLayer { r in
                r.translateBy(x: 9, y: 4)
                r.rotate(by: .degrees(-14 - wagDeg * 0.8))
                r.fill(Path(ellipseIn: CGRect(x: -1.5, y: -2, width: 5.5, height: 8)), with: .color(yellow))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: -10, y: -9, width: 20, height: 22)), with: .color(yellow))
            // Little head tuft
            ctx.fill(Path(ellipseIn: CGRect(x: -2, y: -12.5, width: 4, height: 5)), with: .color(yellow))
            ctx.fill(Path(ellipseIn: CGRect(x: -8.2, y: -0.2, width: 3.2, height: 2.1)), with: .color(blush))
            ctx.fill(Path(ellipseIn: CGRect(x: 5.0, y: -0.2, width: 3.2, height: 2.1)), with: .color(blush))
            drawCuteEyes(in: &ctx, xOffset: 4.2, y: -3.2, isBlinking: isBlinking)
            ctx.fill(Path(roundedRect: CGRect(x: -4.2, y: -0.4, width: 8.4, height: 4.0), cornerRadius: 2.0), with: .color(orange))

        case .frog:
            let green = Color(red: 0.44, green: 0.82, blue: 0.36)
            let belly = Color(red: 0.85, green: 0.96, blue: 0.72)
            ctx.drawLayer { h in
                h.rotate(by: .degrees(tiltDeg))
                // Perched eye bumps
                h.fill(Path(ellipseIn: CGRect(x: -9.5, y: -12, width: 7.4, height: 7.4)), with: .color(green))
                h.fill(Path(ellipseIn: CGRect(x: 2.1, y: -12, width: 7.4, height: 7.4)), with: .color(green))
                h.fill(Path(ellipseIn: CGRect(x: -8.3, y: -10.8, width: 5.0, height: 5.0)), with: .color(.white))
                h.fill(Path(ellipseIn: CGRect(x: 3.3, y: -10.8, width: 5.0, height: 5.0)), with: .color(.white))
                // Body & face
                h.fill(Path(ellipseIn: CGRect(x: -12, y: -6.5, width: 24, height: 19)), with: .color(green))
                h.fill(Path(ellipseIn: CGRect(x: -8, y: 1.5, width: 16, height: 9.5)), with: .color(belly))
                h.fill(Path(ellipseIn: CGRect(x: -9.5, y: -1.5, width: 3.6, height: 2.2)), with: .color(blush))
                h.fill(Path(ellipseIn: CGRect(x: 5.9, y: -1.5, width: 3.6, height: 2.2)), with: .color(blush))
                drawCuteEyes(in: &h, xOffset: 5.8, y: -8.3, isBlinking: isBlinking)
                var smile = Path()
                smile.move(to: CGPoint(x: -4.2, y: -0.6))
                smile.addQuadCurve(to: CGPoint(x: 4.2, y: -0.6), control: CGPoint(x: 0, y: 2.6))
                h.stroke(smile, with: .color(Color(red: 0.16, green: 0.36, blue: 0.16)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
            }

        case .owl:
            let plum = Color(red: 0.52, green: 0.38, blue: 0.64)
            let cream = Color(red: 0.96, green: 0.93, blue: 0.99)
            let gold = Color(red: 0.99, green: 0.72, blue: 0.18)
            // Flapping wings
            ctx.drawLayer { l in
                l.translateBy(x: -9.5, y: 2)
                l.rotate(by: .degrees(18 + wagDeg * 0.95))
                l.fill(Path(ellipseIn: CGRect(x: -4.2, y: -2, width: 5.4, height: 10)), with: .color(plum))
            }
            ctx.drawLayer { r in
                r.translateBy(x: 9.5, y: 2)
                r.rotate(by: .degrees(-18 - wagDeg * 0.95))
                r.fill(Path(ellipseIn: CGRect(x: -1.2, y: -2, width: 5.4, height: 10)), with: .color(plum))
            }
            drawTriangleEar(in: &ctx, x: -7.5, y: -7.5, tipX: -10.5, tipY: -13.5, color: plum)
            drawTriangleEar(in: &ctx, x: 7.5, y: -7.5, tipX: 10.5, tipY: -13.5, color: plum)
            ctx.fill(Path(ellipseIn: CGRect(x: -10.5, y: -10.5, width: 21, height: 24)), with: .color(plum))
            ctx.fill(Path(ellipseIn: CGRect(x: -7, y: 1, width: 14, height: 11)), with: .color(cream))
            // Big owl eye rings
            ctx.fill(Path(ellipseIn: CGRect(x: -8.5, y: -7.5, width: 7.8, height: 7.8)), with: .color(cream))
            ctx.fill(Path(ellipseIn: CGRect(x: 0.7, y: -7.5, width: 7.8, height: 7.8)), with: .color(cream))
            drawCuteEyes(in: &ctx, xOffset: 4.6, y: -3.6, isBlinking: isBlinking)
            var beak = Path()
            beak.move(to: CGPoint(x: -2.0, y: -1.4))
            beak.addLine(to: CGPoint(x: 2.0, y: -1.4))
            beak.addLine(to: CGPoint(x: 0, y: 1.8))
            beak.closeSubpath()
            ctx.fill(beak, with: .color(gold))
        }
    }

    private func drawTriangleEar(in ctx: inout GraphicsContext, x: CGFloat, y: CGFloat, tipX: CGFloat, tipY: CGFloat, color: Color) {
        var ear = Path()
        ear.move(to: CGPoint(x: x - 2.6, y: y + 2))
        ear.addLine(to: CGPoint(x: tipX, y: tipY))
        ear.addLine(to: CGPoint(x: x + 2.6, y: y))
        ear.closeSubpath()
        ctx.fill(ear, with: .color(color))
    }

    private func drawCuteEyes(in ctx: inout GraphicsContext, xOffset: CGFloat, y: CGFloat, isBlinking: Bool, color: Color = Color(white: 0.12)) {
        if isBlinking {
            var l = Path(); l.move(to: CGPoint(x: -xOffset - 1.4, y: y)); l.addLine(to: CGPoint(x: -xOffset + 1.4, y: y))
            var r = Path(); r.move(to: CGPoint(x: xOffset - 1.4, y: y)); r.addLine(to: CGPoint(x: xOffset + 1.4, y: y))
            let style = StrokeStyle(lineWidth: 1.3, lineCap: .round)
            ctx.stroke(l, with: .color(color), style: style)
            ctx.stroke(r, with: .color(color), style: style)
        } else {
            ctx.fill(Path(ellipseIn: CGRect(x: -xOffset - 1.2, y: y - 1.3, width: 2.4, height: 2.6)), with: .color(color))
            ctx.fill(Path(ellipseIn: CGRect(x: xOffset - 1.2, y: y - 1.3, width: 2.4, height: 2.6)), with: .color(color))
        }
    }

    private func drawCuteNoseAndSmile(in ctx: inout GraphicsContext, y: CGFloat) {
        ctx.fill(Path(ellipseIn: CGRect(x: -1.7, y: y - 0.8, width: 3.4, height: 2.2)), with: .color(Color(white: 0.15)))
        drawSmileOnly(in: &ctx, y: y + 2.2)
    }

    private func drawSmileOnly(in ctx: inout GraphicsContext, y: CGFloat) {
        var smile = Path()
        smile.move(to: CGPoint(x: -2.6, y: y))
        smile.addQuadCurve(to: CGPoint(x: 0, y: y - 0.8), control: CGPoint(x: -1.3, y: y + 1.0))
        smile.addQuadCurve(to: CGPoint(x: 2.6, y: y), control: CGPoint(x: 1.3, y: y + 1.0))
        ctx.stroke(smile, with: .color(Color(white: 0.2)), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
    }
}
