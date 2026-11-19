import AppKit
import MacWheelCore
import SwiftUI

enum DogSpriteRenderer {
    /// Renders a crisp 28x18pt template NSImage for the macOS Menu Bar.
    static func menuBarImage(for pose: DogPose) -> NSImage {
        let size = NSSize(width: 28, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.saveGState()

            // Center-bottom anchor inside 28x18 menu bar canvas with safe top headroom
            let bob = min(pose.headBobY * 0.55, 1.4)
            let baseY: CGFloat = 1.0 + bob
            let ink = NSColor.black

            // 1. Fluffy wagging tail (rear left of body)
            ctx.saveGState()
            ctx.translateBy(x: 6.4, y: baseY + 5.8)
            ctx.rotate(by: (22 + pose.tailAngleDeg) * .pi / 180.0)
            let tail = NSBezierPath()
            tail.move(to: NSPoint(x: 0, y: 0))
            tail.curve(to: NSPoint(x: -4.0, y: 4.4),
                       controlPoint1: NSPoint(x: -2.6, y: 0.5),
                       controlPoint2: NSPoint(x: -4.4, y: 2.8))
            tail.lineWidth = 2.4
            tail.lineCapStyle = .round
            ink.setStroke()
            tail.stroke()
            ctx.restoreGState()

            // 2. Plump oval body
            let bodyRect = NSRect(x: 5.8, y: baseY + 3.0, width: 10.6, height: 5.8)
            let body = NSBezierPath(roundedRect: bodyRect, xRadius: 2.8, yRadius: 2.8)
            ink.setFill()
            body.fill()

            // 3. Four stubby puppy legs firmly attached underneath the body (x: 6.4 ... 15.6)
            let swing = pose.stridePhase * 1.9
            drawLeg(x: 6.5 - swing * 0.65, y: baseY + max(0, -swing * 0.35), height: 4.5, ink: ink)
            drawLeg(x: 8.8 + swing * 0.45, y: baseY + max(0, swing * 0.25), height: 4.4, ink: ink)
            drawLeg(x: 12.1 - swing * 0.45, y: baseY + max(0, -swing * 0.25), height: 4.4, ink: ink)
            drawLeg(x: 14.1 + swing * 0.65, y: baseY + max(0, swing * 0.40), height: 4.5, ink: ink)

            // 4. Cute round puppy head & neck overlapping body chest cleanly
            let headCenter = NSPoint(x: 16.2, y: baseY + 8.3)
            let headRect = NSRect(x: headCenter.x - 4.0, y: headCenter.y - 3.6, width: 8.0, height: 7.2)
            let head = NSBezierPath(roundedRect: headRect, xRadius: 3.5, yRadius: 3.4)
            ink.setFill()
            head.fill()

            // 5. Cute snout + rounded tip (facing right)
            let snoutRect = NSRect(x: headCenter.x + 2.2, y: headCenter.y - 2.3, width: 3.4, height: 3.0)
            let snout = NSBezierPath(roundedRect: snoutRect, xRadius: 1.4, yRadius: 1.4)
            snout.fill()

            // 6. Two bouncy puppy ears well inside y <= 16.8 headroom
            ctx.saveGState()
            ctx.translateBy(x: headCenter.x - 1.3, y: headCenter.y + 2.4)
            ctx.rotate(by: pose.earBounceDeg * .pi / 180.0)
            let frontEar = NSBezierPath(roundedRect: NSRect(x: -1.4, y: -0.4, width: 2.7, height: 3.5), xRadius: 1.3, yRadius: 1.3)
            frontEar.fill()
            ctx.restoreGState()

            ctx.saveGState()
            ctx.translateBy(x: headCenter.x + 0.9, y: headCenter.y + 2.5)
            ctx.rotate(by: (-pose.earBounceDeg * 0.45) * .pi / 180.0)
            let backEar = NSBezierPath(roundedRect: NSRect(x: -1.2, y: -0.3, width: 2.4, height: 3.1), xRadius: 1.1, yRadius: 1.1)
            backEar.fill()
            ctx.restoreGState()

            // 7. Expressive eye cutout (clear compositing so template icon shows crisp eye)
            ctx.saveGState()
            NSGraphicsContext.current?.compositingOperation = .clear
            if pose.isBlinking {
                let blink = NSBezierPath()
                blink.move(to: NSPoint(x: headCenter.x + 1.0, y: headCenter.y + 0.3))
                blink.line(to: NSPoint(x: headCenter.x + 2.5, y: headCenter.y + 0.3))
                blink.lineWidth = 1.1
                blink.lineCapStyle = .round
                blink.stroke()
            } else {
                let eye = NSBezierPath(ovalIn: NSRect(x: headCenter.x + 1.1, y: headCenter.y - 0.1, width: 1.4, height: 1.4))
                eye.fill()
            }
            ctx.restoreGState()

            // 8. Cute floating heart beside puppy face when celebrating
            if pose.showHeart {
                let hx: CGFloat = 24.4
                let hy: CGFloat = baseY + 10.2
                let heart = NSBezierPath()
                heart.move(to: NSPoint(x: hx, y: hy))
                heart.curve(to: NSPoint(x: hx - 2.1, y: hy + 2.2),
                            controlPoint1: NSPoint(x: hx - 1.6, y: hy + 0.8),
                            controlPoint2: NSPoint(x: hx - 2.3, y: hy + 1.6))
                heart.curve(to: NSPoint(x: hx, y: hy + 1.8),
                            controlPoint1: NSPoint(x: hx - 1.8, y: hy + 3.0),
                            controlPoint2: NSPoint(x: hx - 0.3, y: hy + 2.8))
                heart.curve(to: NSPoint(x: hx + 2.1, y: hy + 2.2),
                            controlPoint1: NSPoint(x: hx + 0.3, y: hy + 2.8),
                            controlPoint2: NSPoint(x: hx + 1.8, y: hy + 3.0))
                heart.curve(to: NSPoint(x: hx, y: hy),
                            controlPoint1: NSPoint(x: hx + 2.3, y: hy + 1.6),
                            controlPoint2: NSPoint(x: hx + 1.6, y: hy + 0.8))
                heart.close()
                ink.setFill()
                heart.fill()
            }

            ctx.restoreGState()
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawLeg(x: CGFloat, y: CGFloat, height: CGFloat, ink: NSColor) {
        let leg = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 2.1, height: height), xRadius: 1.0, yRadius: 1.0)
        ink.setFill()
        leg.fill()
    }
}

/// Cute live-animated full-color puppy mascot shown inside the Dog PDF window, popover, and HUD.
struct AnimatedDogMascotView: View {
    let isBusy: Bool
    var size: CGFloat = 38

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let speed = isBusy ? 11.0 : 4.2
            let wagDeg = sin(t * speed) * (isBusy ? 26.0 : 18.0)
            let bounceY = abs(sin(t * (isBusy ? 8.5 : 3.2))) * (isBusy ? -3.0 : -1.2)
            let tiltDeg = sin(t * (isBusy ? 8.5 : 2.1)) * (isBusy ? 5.5 : 2.5)
            let isBlinking = !isBusy && (t.truncatingRemainder(dividingBy: 3.8) > 3.62)

            Canvas { ctx, canvasSize in
                let scale = min(canvasSize.width, canvasSize.height) / 40.0
                ctx.translateBy(x: canvasSize.width / 2, y: canvasSize.height / 2 + bounceY * scale)
                ctx.scaleBy(x: scale, y: scale)

                let furLight = Color(red: 0.99, green: 0.74, blue: 0.42)
                let furDark = Color(red: 0.90, green: 0.56, blue: 0.24)
                let cream = Color(red: 1.0, green: 0.96, blue: 0.89)
                let coral = Color(red: 0.96, green: 0.36, blue: 0.16)

                // Soft warm badge behind puppy
                ctx.fill(
                    Path(roundedRect: CGRect(x: -18, y: -18, width: 36, height: 36), cornerRadius: 10),
                    with: .linearGradient(
                        Gradient(colors: [Color(red: 1.0, green: 0.95, blue: 0.88), Color(red: 0.99, green: 0.85, blue: 0.68)]),
                        startPoint: CGPoint(x: 0, y: -18),
                        endPoint: CGPoint(x: 0, y: 18)
                    )
                )

                // Wagging tail behind body
                ctx.drawLayer { layer in
                    layer.translateBy(x: -7, y: 9)
                    layer.rotate(by: .degrees(-20 + wagDeg))
                    var tail = Path()
                    tail.move(to: .zero)
                    tail.addQuadCurve(to: CGPoint(x: -6, y: -7), control: CGPoint(x: -8, y: 0))
                    layer.stroke(tail, with: .color(furDark), style: StrokeStyle(lineWidth: 3.4, lineCap: .round))
                }

                // Body
                ctx.fill(Path(roundedRect: CGRect(x: -8, y: 2, width: 16, height: 12), cornerRadius: 6), with: .color(furDark))
                ctx.fill(Path(ellipseIn: CGRect(x: -5, y: 5, width: 10, height: 8)), with: .color(cream))

                // Cute head tilting playfully
                ctx.drawLayer { headLayer in
                    headLayer.translateBy(x: 0, y: -3)
                    headLayer.rotate(by: .degrees(tiltDeg))

                    // Ears
                    var leftEar = Path()
                    leftEar.move(to: CGPoint(x: -9, y: -4))
                    leftEar.addLine(to: CGPoint(x: -11, y: -13))
                    leftEar.addLine(to: CGPoint(x: -3, y: -8))
                    leftEar.closeSubpath()
                    headLayer.fill(leftEar, with: .color(furDark))

                    var rightEar = Path()
                    rightEar.move(to: CGPoint(x: 9, y: -4))
                    rightEar.addLine(to: CGPoint(x: 11, y: -13))
                    rightEar.addLine(to: CGPoint(x: 3, y: -8))
                    rightEar.closeSubpath()
                    headLayer.fill(rightEar, with: .color(furDark))

                    // Face
                    headLayer.fill(Path(ellipseIn: CGRect(x: -10.5, y: -9, width: 21, height: 18)), with: .color(furLight))
                    headLayer.fill(Path(ellipseIn: CGRect(x: -7.5, y: -2, width: 15, height: 10.5)), with: .color(cream))

                    // Round glasses (matching Dog PDF app icon!)
                    let glassStyle = StrokeStyle(lineWidth: 1.4, lineCap: .round)
                    headLayer.stroke(Path(ellipseIn: CGRect(x: -7.8, y: -5.5, width: 6.4, height: 6.4)), with: .color(Color(white: 0.18)), style: glassStyle)
                    headLayer.stroke(Path(ellipseIn: CGRect(x: 1.4, y: -5.5, width: 6.4, height: 6.4)), with: .color(Color(white: 0.18)), style: glassStyle)
                    var bridge = Path()
                    bridge.move(to: CGPoint(x: -1.4, y: -2.4))
                    bridge.addLine(to: CGPoint(x: 1.4, y: -2.4))
                    headLayer.stroke(bridge, with: .color(Color(white: 0.18)), style: glassStyle)

                    // Eyes
                    if isBlinking {
                        var lBlink = Path()
                        lBlink.move(to: CGPoint(x: -5.8, y: -2.3))
                        lBlink.addLine(to: CGPoint(x: -3.2, y: -2.3))
                        var rBlink = Path()
                        rBlink.move(to: CGPoint(x: 3.2, y: -2.3))
                        rBlink.addLine(to: CGPoint(x: 5.8, y: -2.3))
                        headLayer.stroke(lBlink, with: .color(.black), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                        headLayer.stroke(rBlink, with: .color(.black), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                    } else {
                        headLayer.fill(Path(ellipseIn: CGRect(x: -5.6, y: -3.4, width: 2.2, height: 2.4)), with: .color(Color(white: 0.12)))
                        headLayer.fill(Path(ellipseIn: CGRect(x: 3.4, y: -3.4, width: 2.2, height: 2.4)), with: .color(Color(white: 0.12)))
                    }

                    // Nose & happy smile
                    headLayer.fill(Path(ellipseIn: CGRect(x: -1.8, y: -0.2, width: 3.6, height: 2.4)), with: .color(Color(white: 0.15)))
                    var smile = Path()
                    smile.move(to: CGPoint(x: -2.8, y: 3.0))
                    smile.addQuadCurve(to: CGPoint(x: 0, y: 2.2), control: CGPoint(x: -1.4, y: 4.0))
                    smile.addQuadCurve(to: CGPoint(x: 2.8, y: 3.0), control: CGPoint(x: 1.4, y: 4.0))
                    headLayer.stroke(smile, with: .color(Color(white: 0.2)), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
                }

                // Tiny coral PDF collar tag
                ctx.fill(Path(roundedRect: CGRect(x: 6, y: 7, width: 9, height: 6), cornerRadius: 1.5), with: .color(coral))
            }
            .frame(width: size, height: size)
        }
    }
}
