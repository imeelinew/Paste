import CoreGraphics
import SwiftUI

/// Semantic names for Lucide vector icons used across the palette interface.
/// Sourced directly from https://lucide.dev/icons
public enum LucideIconName: String, CaseIterable, Equatable, Sendable {
    case copy
    case pencil
    case pin
    case pinOff = "pin-off"
    case bookmark
    case bookmarkMinus = "bookmark-minus"
    case folder
    case trash2 = "trash-2"
    case info
    case refreshCw = "refresh-cw"
    case settings
    case power
    case pictureInPicture2 = "picture-in-picture-2"

    /// Generates the vector path on Lucide's standard 24x24 coordinate grid.
    public var path: Path {
        let cgPath = CGMutablePath()
        switch self {
        case .copy:
            cgPath.addRoundedRect(in: CGRect(x: 8, y: 8, width: 14, height: 14), cornerWidth: 2, cornerHeight: 2)
            SVGPathParser.addPath("M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2", to: cgPath)
        case .pencil:
            SVGPathParser.addPath("M21.174 6.812a1 1 0 0 0-3.986-3.987L3.842 16.174a2 2 0 0 0-.5.83l-1.321 4.352a.5.5 0 0 0 .623.622l4.353-1.32a2 2 0 0 0 .83-.497z", to: cgPath)
            SVGPathParser.addPath("m15 5 4 4", to: cgPath)
        case .pin:
            SVGPathParser.addPath("M12 17v5", to: cgPath)
            SVGPathParser.addPath("M9 10.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24V16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V7a1 1 0 0 1 1-1 2 2 0 0 0 0-4H8a2 2 0 0 0 0 4 1 1 0 0 1 1 1z", to: cgPath)
        case .pinOff:
            SVGPathParser.addPath("M12 17v5", to: cgPath)
            SVGPathParser.addPath("M15 9.34V7a1 1 0 0 1 1-1 2 2 0 0 0 0-4H7.89", to: cgPath)
            SVGPathParser.addPath("m2 2 20 20", to: cgPath)
            SVGPathParser.addPath("M9 9v1.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24V16a1 1 0 0 0 1 1h11", to: cgPath)
        case .bookmark:
            SVGPathParser.addPath("M17 3a2 2 0 0 1 2 2v15a1 1 0 0 1-1.496.868l-4.512-2.578a2 2 0 0 0-1.984 0l-4.512 2.578A1 1 0 0 1 5 20V5a2 2 0 0 1 2-2z", to: cgPath)
        case .bookmarkMinus:
            SVGPathParser.addPath("M15 10H9", to: cgPath)
            SVGPathParser.addPath("M17 3a2 2 0 0 1 2 2v15a1 1 0 0 1-1.496.868l-4.512-2.578a2 2 0 0 0-1.984 0l-4.512 2.578A1 1 0 0 1 5 20V5a2 2 0 0 1 2-2z", to: cgPath)
        case .folder:
            SVGPathParser.addPath("M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z", to: cgPath)
        case .trash2:
            SVGPathParser.addPath("M10 11v6", to: cgPath)
            SVGPathParser.addPath("M14 11v6", to: cgPath)
            SVGPathParser.addPath("M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6", to: cgPath)
            SVGPathParser.addPath("M3 6h18", to: cgPath)
            SVGPathParser.addPath("M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2", to: cgPath)
        case .info:
            cgPath.addEllipse(in: CGRect(x: 2, y: 2, width: 20, height: 20))
            SVGPathParser.addPath("M12 16v-4", to: cgPath)
            SVGPathParser.addPath("M12 8h.01", to: cgPath)
        case .refreshCw:
            SVGPathParser.addPath("M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8", to: cgPath)
            SVGPathParser.addPath("M21 3v5h-5", to: cgPath)
            SVGPathParser.addPath("M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16", to: cgPath)
            SVGPathParser.addPath("M8 16H3v5", to: cgPath)
        case .settings:
            SVGPathParser.addPath("M9.671 4.136a2.34 2.34 0 0 1 4.659 0 2.34 2.34 0 0 0 3.319 1.915 2.34 2.34 0 0 1 2.33 4.033 2.34 2.34 0 0 0 0 3.831 2.34 2.34 0 0 1-2.33 4.033 2.34 2.34 0 0 0-3.319 1.915 2.34 2.34 0 0 1-4.659 0 2.34 2.34 0 0 0-3.32-1.915 2.34 2.34 0 0 1-2.33-4.033 2.34 2.34 0 0 0 0-3.831A2.34 2.34 0 0 1 6.35 6.051a2.34 2.34 0 0 0 3.319-1.915", to: cgPath)
            cgPath.addEllipse(in: CGRect(x: 9, y: 9, width: 6, height: 6))
        case .power:
            SVGPathParser.addPath("M12 2v10", to: cgPath)
            SVGPathParser.addPath("M18.4 6.6a9 9 0 1 1-12.77.04", to: cgPath)
        case .pictureInPicture2:
            SVGPathParser.addPath("M21 9V6a2 2 0 0 0-2-2H4a2 2 0 0 0-2 2v10c0 1.1.9 2 2 2h4", to: cgPath)
            cgPath.addRoundedRect(in: CGRect(x: 12, y: 13, width: 10, height: 7), cornerWidth: 2, cornerHeight: 2)
        }
        return Path(cgPath)
    }
}

/// Vector shape scaling a 24x24 Lucide icon path proportionally into the target bounds.
public struct LucideIconShape: Shape {
    public let name: LucideIconName

    public init(name: LucideIconName) {
        self.name = name
    }

    public func path(in rect: CGRect) -> Path {
        let base = name.path
        let scale = min(rect.width / 24.0, rect.height / 24.0)
        let dx = (rect.width - 24.0 * scale) / 2.0
        let dy = (rect.height - 24.0 * scale) / 2.0
        let transform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: scale, y: scale)
        return base.applying(transform)
    }
}

/// SwiftUI view rendering a resolution-independent Lucide icon.
public struct LucideIcon: View {
    public let name: LucideIconName
    public var size: CGFloat = 16
    public var strokeWidth: CGFloat = 1.35

    public init(name: LucideIconName, size: CGFloat = 16, strokeWidth: CGFloat = 1.35) {
        self.name = name
        self.size = size
        self.strokeWidth = strokeWidth
    }

    public var body: some View {
        LucideIconShape(name: name)
            .stroke(style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .frame(width: Theme.Size.menuIcon, height: Theme.Size.menuIcon)
    }
}

/// Lightweight parser converting SVG path definition strings into `CGPath` commands.
enum SVGPathParser {
    static func addPath(_ pathString: String, to path: CGMutablePath) {
        var cursor = CGPoint.zero
        var startPoint = CGPoint.zero
        var lastControlPoint: CGPoint? = nil

        let scanner = Scanner(string: pathString)
        scanner.charactersToBeSkipped = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))

        var currentCommand: Character? = nil

        while !scanner.isAtEnd {
            let initialLocation = scanner.currentIndex
            if let char = scanner.scanCharacter(), char.isLetter {
                currentCommand = char
            } else {
                scanner.currentIndex = initialLocation
            }

            guard let cmd = currentCommand else { break }

            switch cmd {
            case "M":
                guard let x = scanner.scanDouble(), let y = scanner.scanDouble() else { break }
                cursor = CGPoint(x: x, y: y)
                startPoint = cursor
                path.move(to: cursor)
                lastControlPoint = nil
                currentCommand = "L"
            case "m":
                guard let dx = scanner.scanDouble(), let dy = scanner.scanDouble() else { break }
                cursor = CGPoint(x: cursor.x + dx, y: cursor.y + dy)
                startPoint = cursor
                path.move(to: cursor)
                lastControlPoint = nil
                currentCommand = "l"
            case "L":
                guard let x = scanner.scanDouble(), let y = scanner.scanDouble() else { break }
                cursor = CGPoint(x: x, y: y)
                path.addLine(to: cursor)
                lastControlPoint = nil
            case "l":
                guard let dx = scanner.scanDouble(), let dy = scanner.scanDouble() else { break }
                cursor = CGPoint(x: cursor.x + dx, y: cursor.y + dy)
                path.addLine(to: cursor)
                lastControlPoint = nil
            case "H":
                guard let x = scanner.scanDouble() else { break }
                cursor = CGPoint(x: x, y: cursor.y)
                path.addLine(to: cursor)
                lastControlPoint = nil
            case "h":
                guard let dx = scanner.scanDouble() else { break }
                cursor = CGPoint(x: cursor.x + dx, y: cursor.y)
                path.addLine(to: cursor)
                lastControlPoint = nil
            case "V":
                guard let y = scanner.scanDouble() else { break }
                cursor = CGPoint(x: cursor.x, y: y)
                path.addLine(to: cursor)
                lastControlPoint = nil
            case "v":
                guard let dy = scanner.scanDouble() else { break }
                cursor = CGPoint(x: cursor.x, y: cursor.y + dy)
                path.addLine(to: cursor)
                lastControlPoint = nil
            case "C":
                guard let x1 = scanner.scanDouble(), let y1 = scanner.scanDouble(),
                      let x2 = scanner.scanDouble(), let y2 = scanner.scanDouble(),
                      let x = scanner.scanDouble(), let y = scanner.scanDouble() else { break }
                let cp1 = CGPoint(x: x1, y: y1)
                let cp2 = CGPoint(x: x2, y: y2)
                cursor = CGPoint(x: x, y: y)
                path.addCurve(to: cursor, control1: cp1, control2: cp2)
                lastControlPoint = cp2
            case "c":
                guard let dx1 = scanner.scanDouble(), let dy1 = scanner.scanDouble(),
                      let dx2 = scanner.scanDouble(), let dy2 = scanner.scanDouble(),
                      let dx = scanner.scanDouble(), let dy = scanner.scanDouble() else { break }
                let cp1 = CGPoint(x: cursor.x + dx1, y: cursor.y + dy1)
                let cp2 = CGPoint(x: cursor.x + dx2, y: cursor.y + dy2)
                cursor = CGPoint(x: cursor.x + dx, y: cursor.y + dy)
                path.addCurve(to: cursor, control1: cp1, control2: cp2)
                lastControlPoint = cp2
            case "S":
                guard let x2 = scanner.scanDouble(), let y2 = scanner.scanDouble(),
                      let x = scanner.scanDouble(), let y = scanner.scanDouble() else { break }
                let cp1 = lastControlPoint != nil ? CGPoint(x: 2 * cursor.x - lastControlPoint!.x, y: 2 * cursor.y - lastControlPoint!.y) : cursor
                let cp2 = CGPoint(x: x2, y: y2)
                cursor = CGPoint(x: x, y: y)
                path.addCurve(to: cursor, control1: cp1, control2: cp2)
                lastControlPoint = cp2
            case "s":
                guard let dx2 = scanner.scanDouble(), let dy2 = scanner.scanDouble(),
                      let dx = scanner.scanDouble(), let dy = scanner.scanDouble() else { break }
                let cp1 = lastControlPoint != nil ? CGPoint(x: 2 * cursor.x - lastControlPoint!.x, y: 2 * cursor.y - lastControlPoint!.y) : cursor
                let cp2 = CGPoint(x: cursor.x + dx2, y: cursor.y + dy2)
                cursor = CGPoint(x: cursor.x + dx, y: cursor.y + dy)
                path.addCurve(to: cursor, control1: cp1, control2: cp2)
                lastControlPoint = cp2
            case "A", "a":
                guard let rx = scanner.scanDouble(), let ry = scanner.scanDouble(),
                      let xAxisRotation = scanner.scanDouble(),
                      let largeArcFlag = scanner.scanInt(),
                      let sweepFlag = scanner.scanInt(),
                      let endX = scanner.scanDouble(), let endY = scanner.scanDouble() else { break }
                let target = cmd == "A" ? CGPoint(x: endX, y: endY) : CGPoint(x: cursor.x + endX, y: cursor.y + endY)
                addArc(to: path, from: cursor, to: target, rx: rx, ry: ry, xAxisRotation: xAxisRotation, largeArc: largeArcFlag != 0, sweep: sweepFlag != 0)
                cursor = target
                lastControlPoint = nil
            case "Z", "z":
                path.closeSubpath()
                cursor = startPoint
                lastControlPoint = nil
            default:
                break
            }
        }
    }

    private static func addArc(
        to path: CGMutablePath,
        from p1: CGPoint,
        to p2: CGPoint,
        rx: Double,
        ry: Double,
        xAxisRotation: Double,
        largeArc: Bool,
        sweep: Bool
    ) {
        guard rx > 0 && ry > 0 else {
            path.addLine(to: p2)
            return
        }
        guard p1 != p2 else { return }

        let phi = xAxisRotation * .pi / 180.0
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)

        let dx = (p1.x - p2.x) / 2.0
        let dy = (p1.y - p2.y) / 2.0

        let x1Prime = cosPhi * dx + sinPhi * dy
        let y1Prime = -sinPhi * dx + cosPhi * dy

        var rxVal = abs(rx)
        var ryVal = abs(ry)

        let lambda = (x1Prime * x1Prime) / (rxVal * rxVal) + (y1Prime * y1Prime) / (ryVal * ryVal)
        if lambda > 1.0 {
            let sqrtLambda = sqrt(lambda)
            rxVal *= sqrtLambda
            ryVal *= sqrtLambda
        }

        let rxSq = rxVal * rxVal
        let rySq = ryVal * ryVal
        let x1PrimeSq = x1Prime * x1Prime
        let y1PrimeSq = y1Prime * y1Prime

        var radicand = (rxSq * rySq - rxSq * y1PrimeSq - rySq * x1PrimeSq) / (rxSq * y1PrimeSq + rySq * x1PrimeSq)
        radicand = max(0, radicand)
        let factor = (largeArc == sweep ? -1.0 : 1.0) * sqrt(radicand)

        let cxPrime = factor * (rxVal * y1Prime / ryVal)
        let cyPrime = factor * (-ryVal * x1Prime / rxVal)

        let cx = cosPhi * cxPrime - sinPhi * cyPrime + (p1.x + p2.x) / 2.0
        let cy = sinPhi * cxPrime + cosPhi * cyPrime + (p1.y + p2.y) / 2.0

        func angleBetween(u: CGPoint, v: CGPoint) -> Double {
            let dot = u.x * v.x + u.y * v.y
            let len = sqrt(u.x * u.x + u.y * u.y) * sqrt(v.x * v.x + v.y * v.y)
            var angle = acos(max(-1.0, min(1.0, dot / len)))
            if (u.x * v.y - u.y * v.x) < 0 { angle = -angle }
            return angle
        }

        let v1 = CGPoint(x: (x1Prime - cxPrime) / rxVal, y: (y1Prime - cyPrime) / ryVal)
        let v2 = CGPoint(x: (-x1Prime - cxPrime) / rxVal, y: (-y1Prime - cyPrime) / ryVal)

        let theta1 = angleBetween(u: CGPoint(x: 1, y: 0), v: v1)
        var dTheta = angleBetween(u: v1, v: v2)

        if !sweep && dTheta > 0 {
            dTheta -= 2 * .pi
        } else if sweep && dTheta < 0 {
            dTheta += 2 * .pi
        }

        let segments = Int(ceil(abs(dTheta) / (.pi / 2.0)))
        let deltaTheta = dTheta / Double(segments)
        let alpha = sin(deltaTheta) * (sqrt(4 + 3 * tan(deltaTheta / 2) * tan(deltaTheta / 2)) - 1) / 3.0

        var currentTheta = theta1
        for _ in 0..<segments {
            let nextTheta = currentTheta + deltaTheta

            let cosCurrent = cos(currentTheta)
            let sinCurrent = sin(currentTheta)
            let cosNext = cos(nextTheta)
            let sinNext = sin(nextTheta)

            let ep1 = CGPoint(
                x: cosPhi * rxVal * cosCurrent - sinPhi * ryVal * sinCurrent + cx,
                y: sinPhi * rxVal * cosCurrent + cosPhi * ryVal * sinCurrent + cy
            )
            let dEp1 = CGPoint(
                x: -cosPhi * rxVal * sinCurrent - sinPhi * ryVal * cosCurrent,
                y: -sinPhi * rxVal * sinCurrent + cosPhi * ryVal * cosCurrent
            )
            let ep2 = CGPoint(
                x: cosPhi * rxVal * cosNext - sinPhi * ryVal * sinNext + cx,
                y: sinPhi * rxVal * cosNext + cosPhi * ryVal * sinNext + cy
            )
            let dEp2 = CGPoint(
                x: -cosPhi * rxVal * sinNext - sinPhi * ryVal * cosNext,
                y: -sinPhi * rxVal * sinNext + cosPhi * ryVal * cosNext
            )

            let cp1 = CGPoint(x: ep1.x + alpha * dEp1.x, y: ep1.y + alpha * dEp1.y)
            let cp2 = CGPoint(x: ep2.x - alpha * dEp2.x, y: ep2.y - alpha * dEp2.y)

            path.addCurve(to: ep2, control1: cp1, control2: cp2)
            currentTheta = nextTheta
        }
    }
}
