import Foundation

public enum DogAnimationMode: String, Sendable, Equatable {
    case idle
    case working
    case celebrating
    case paused
}

public struct DogPose: Equatable, Sendable {
    public let mode: DogAnimationMode
    public let frameIndex: Int
    public let headBobY: CGFloat
    public let tailAngleDeg: CGFloat
    public let earBounceDeg: CGFloat
    public let stridePhase: CGFloat
    public let isBlinking: Bool
    public let showHeart: Bool
    public let xOffset: CGFloat
    public let facingRight: Bool
    public let bodyTiltDeg: CGFloat
    public let dustPhase: CGFloat

    public init(
        mode: DogAnimationMode,
        frameIndex: Int,
        headBobY: CGFloat,
        tailAngleDeg: CGFloat,
        earBounceDeg: CGFloat,
        stridePhase: CGFloat,
        isBlinking: Bool,
        showHeart: Bool,
        xOffset: CGFloat = 0,
        facingRight: Bool = true,
        bodyTiltDeg: CGFloat = 0,
        dustPhase: CGFloat = 0
    ) {
        self.mode = mode
        self.frameIndex = frameIndex
        self.headBobY = headBobY
        self.tailAngleDeg = tailAngleDeg
        self.earBounceDeg = earBounceDeg
        self.stridePhase = stridePhase
        self.isBlinking = isBlinking
        self.showHeart = showHeart
        self.xOffset = xOffset
        self.facingRight = facingRight
        self.bodyTiltDeg = bodyTiltDeg
        self.dustPhase = dustPhase
    }
}

public struct DogAnimationController: Sendable {
    public private(set) var mode: DogAnimationMode = .idle
    private var tick: Int = 0
    private var celebrationRemainingTicks: Int = 0
    private var wasBusy: Bool = false
    private var xPos: CGFloat = 0
    private var direction: CGFloat = 1.0
    private var pauseTicksRemaining: Int = 0

    public init() {}

    public var frameInterval: TimeInterval {
        switch mode {
        case .idle: return 0.18
        case .working: return 0.068
        case .celebrating: return 0.085
        case .paused: return 0.50
        }
    }

    public mutating func update(isBusy: Bool, isEnabled: Bool) {
        if !isEnabled {
            mode = .paused
            wasBusy = false
            celebrationRemainingTicks = 0
            return
        }

        if isBusy {
            mode = .working
            celebrationRemainingTicks = 0
            pauseTicksRemaining = 0
        } else if wasBusy {
            mode = .celebrating
            celebrationRemainingTicks = 20
            tick = 0
        } else if mode == .paused {
            mode = .idle
        }
        wasBusy = isBusy
    }

    @discardableResult
    public mutating func stepFrame() -> DogPose {
        tick += 1
        let t = Double(tick)

        switch mode {
        case .paused:
            return DogPose(
                mode: .paused,
                frameIndex: 0,
                headBobY: -0.6,
                tailAngleDeg: -10,
                earBounceDeg: -6,
                stridePhase: 0,
                isBlinking: true,
                showHeart: false,
                xOffset: 0,
                facingRight: true,
                bodyTiltDeg: 0,
                dustPhase: 0
            )

        case .working:
            let maxRunway: CGFloat = 7.5
            xPos += direction * 1.4
            if xPos >= maxRunway {
                xPos = maxRunway
                direction = -1.0
            } else if xPos <= -maxRunway {
                xPos = -maxRunway
                direction = 1.0
            }
            let runCycle = t * 1.15
            let stride = CGFloat(sin(runCycle))
            let bob = CGFloat(abs(sin(runCycle)) * 2.2)
            let tilt = CGFloat(cos(runCycle) * 8.5)
            let tail = CGFloat(22.0 + sin(runCycle * 1.3) * 26.0)
            let ear = CGFloat(-cos(runCycle) * 16.0)
            let dust = CGFloat((t * 0.28).truncatingRemainder(dividingBy: 1.0))

            return DogPose(
                mode: .working,
                frameIndex: tick % 6,
                headBobY: bob,
                tailAngleDeg: tail,
                earBounceDeg: ear,
                stridePhase: stride,
                isBlinking: false,
                showHeart: false,
                xOffset: xPos,
                facingRight: direction > 0,
                bodyTiltDeg: tilt,
                dustPhase: dust
            )

        case .celebrating:
            if celebrationRemainingTicks > 0 {
                celebrationRemainingTicks -= 1
            } else {
                mode = .idle
                tick = 0
                return stepIdleFrame()
            }
            let idx = tick % 4
            let jumpMap: [CGFloat] = [0.0, 2.3, 2.9, 1.1]
            let tailMap: [CGFloat] = [-25, 35, -28, 38]
            let earMap: [CGFloat] = [6, 16, 12, -4]
            return DogPose(
                mode: .celebrating,
                frameIndex: idx,
                headBobY: jumpMap[idx],
                tailAngleDeg: tailMap[idx],
                earBounceDeg: earMap[idx],
                stridePhase: idx % 2 == 0 ? 0.65 : -0.65,
                isBlinking: false,
                showHeart: idx == 1 || idx == 2,
                xOffset: xPos,
                facingRight: direction > 0,
                bodyTiltDeg: idx % 2 == 0 ? 6.0 : -6.0,
                dustPhase: 0.5
            )

        case .idle:
            return stepIdleFrame()
        }
    }

    private mutating func stepIdleFrame() -> DogPose {
        let maxRunway: CGFloat = 6.2
        let isPaused: Bool
        if pauseTicksRemaining > 0 {
            pauseTicksRemaining -= 1
            isPaused = true
        } else {
            isPaused = false
            xPos += direction * 0.65
            if xPos >= maxRunway {
                xPos = maxRunway
                direction = -1.0
                pauseTicksRemaining = 7
            } else if xPos <= -maxRunway {
                xPos = -maxRunway
                direction = 1.0
                pauseTicksRemaining = 7
            }
        }

        let t = Double(tick)
        let walkCycle = t * 0.85
        let stride = isPaused ? 0 : CGFloat(sin(walkCycle) * 0.55)
        let bob = isPaused ? CGFloat(abs(sin(t * 0.4)) * 0.45) : CGFloat(abs(sin(walkCycle)) * 1.1)
        let tilt = isPaused ? CGFloat(sin(t * 0.35) * 1.6) : CGFloat(cos(walkCycle) * 3.0)
        let tail = CGFloat(sin(t * 0.75) * 24.0)
        let ear = CGFloat(sin(walkCycle + 0.5) * (isPaused ? 4.0 : 9.0))
        let facingRight = pauseTicksRemaining > 0 ? (xPos < 0) : (direction > 0)

        return DogPose(
            mode: .idle,
            frameIndex: tick % 12,
            headBobY: bob,
            tailAngleDeg: tail,
            earBounceDeg: ear,
            stridePhase: stride,
            isBlinking: (tick % 16 == 10),
            showHeart: false,
            xOffset: xPos,
            facingRight: facingRight,
            bodyTiltDeg: tilt,
            dustPhase: 0
        )
    }
}
