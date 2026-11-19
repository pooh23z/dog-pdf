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

    public init(
        mode: DogAnimationMode,
        frameIndex: Int,
        headBobY: CGFloat,
        tailAngleDeg: CGFloat,
        earBounceDeg: CGFloat,
        stridePhase: CGFloat,
        isBlinking: Bool,
        showHeart: Bool
    ) {
        self.mode = mode
        self.frameIndex = frameIndex
        self.headBobY = headBobY
        self.tailAngleDeg = tailAngleDeg
        self.earBounceDeg = earBounceDeg
        self.stridePhase = stridePhase
        self.isBlinking = isBlinking
        self.showHeart = showHeart
    }
}

public struct DogAnimationController: Sendable {
    public private(set) var mode: DogAnimationMode = .idle
    private var tick: Int = 0
    private var celebrationRemainingTicks: Int = 0
    private var wasBusy: Bool = false

    public init() {}

    public var frameInterval: TimeInterval {
        switch mode {
        case .idle: return 0.22
        case .working: return 0.10
        case .celebrating: return 0.13
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
        } else if wasBusy {
            mode = .celebrating
            celebrationRemainingTicks = 15
            tick = 0
        } else if mode == .paused {
            mode = .idle
        }
        wasBusy = isBusy
    }

    @discardableResult
    public mutating func stepFrame() -> DogPose {
        tick += 1

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
                showHeart: false
            )

        case .working:
            let idx = tick % 6
            let strideMap: [CGFloat] = [-1.0, -0.4, 0.35, 1.0, 0.4, -0.35]
            let bobMap: [CGFloat] = [0.0, 0.8, 1.5, 0.6, 0.0, 1.1]
            let tailMap: [CGFloat] = [18, 28, 36, 22, 12, 26]
            let earMap: [CGFloat] = [-8, 6, 14, 4, -10, 8]
            return DogPose(
                mode: .working,
                frameIndex: idx,
                headBobY: bobMap[idx],
                tailAngleDeg: tailMap[idx],
                earBounceDeg: earMap[idx],
                stridePhase: strideMap[idx],
                isBlinking: false,
                showHeart: false
            )

        case .celebrating:
            if celebrationRemainingTicks > 0 {
                celebrationRemainingTicks -= 1
            } else {
                mode = .idle
                tick = 0
                return currentIdlePose(frame: 0)
            }
            let idx = tick % 4
            let jumpMap: [CGFloat] = [0.0, 2.2, 2.8, 1.0]
            let tailMap: [CGFloat] = [-25, 35, -28, 38]
            let earMap: [CGFloat] = [6, 16, 12, -4]
            return DogPose(
                mode: .celebrating,
                frameIndex: idx,
                headBobY: jumpMap[idx],
                tailAngleDeg: tailMap[idx],
                earBounceDeg: earMap[idx],
                stridePhase: 0.45,
                isBlinking: false,
                showHeart: idx == 1 || idx == 2
            )

        case .idle:
            return currentIdlePose(frame: tick % 12)
        }
    }

    private func currentIdlePose(frame idx: Int) -> DogPose {
        let bobMap: [CGFloat] = [0.0, 0.4, 0.7, 0.4, 0.0, 0.3, 0.6, 0.3, 0.0, 0.4, 0.6, 0.2]
        let tailMap: [CGFloat] = [-20, -4, 18, 32, 16, -6, -22, -4, 18, 32, 14, -8]
        let earMap: [CGFloat] = [0, 3, 6, 3, 0, -2, 0, 4, 7, 3, 0, -2]
        return DogPose(
            mode: .idle,
            frameIndex: idx,
            headBobY: bobMap[idx],
            tailAngleDeg: tailMap[idx],
            earBounceDeg: earMap[idx],
            stridePhase: 0,
            isBlinking: idx == 10,
            showHeart: false
        )
    }
}
