import AppKit
import SceneKit
import SwiftUI
import simd

enum RemotePresentation {
    static func centerY(in availableHeight: CGFloat) -> CGFloat {
        availableHeight / 2 + centerOffset(in: availableHeight)
    }

    static func centerOffset(in availableHeight: CGFloat) -> CGFloat {
        -5 - min(40, availableHeight * 0.07)
    }

    static func height(in availableHeight: CGFloat) -> CGFloat {
        min(430, max(0, availableHeight * 0.76))
    }
}

/// A single orthographic projection drives the camera, button hit areas and outlines.
struct RemoteProjection: Equatable {
    let size: CGSize
    let unit: CGFloat
    let originY: CGFloat

    var cameraScale: Double { Double(max(1, size.height) / (2 * unit)) }
    var cameraZ: CGFloat { (size.height / 2 - originY) / unit }

    func point(_ position: SIMD3<Float>) -> CGPoint {
        CGPoint(x: size.width / 2 + unit * CGFloat(position.x), y: y(at: CGFloat(position.z)))
    }

    func y(at z: CGFloat) -> CGFloat { originY + unit * z }
}

struct RemotePose: Equatable {
    static let detail = Self(yaw: -.pi / 15, pitch: 0)
    var yaw: Double
    var pitch: Double
    var roll: Double = 0

    var orientation: simd_quatf {
        simd_quatf(angle: Float(roll), axis: SIMD3(0, 1, 0))
            * simd_quatf(angle: Float(-yaw), axis: SIMD3(0, 0, 1))
            * simd_quatf(angle: Float(pitch), axis: SIMD3(1, 0, 0))
    }

    func turned(by delta: CGSize) -> Self {
        .init(yaw: (yaw + delta.width * 0.013).truncatingRemainder(dividingBy: 2 * .pi),
              pitch: min(0.62, max(-0.62, pitch + delta.height * 0.009)), roll: roll)
    }

    func swaying(elapsed: TimeInterval) -> Self {
        let t = max(0, elapsed)
        let fade = min(t / 1.15, 1)
        let weight = fade * fade * (3 - 2 * fade)
        let phase = t * 2 * .pi / 7.8
        return .init(yaw: yaw + weight * 0.103 * sin(phase),
                     pitch: pitch + weight * 0.022 * sin(phase + 0.6),
                     roll: roll + weight * 0.029 * sin(phase - 0.20))
    }

    func blended(to target: Self, fraction: Double) -> Self {
        let yawDelta = target.yaw - yaw
        return .init(yaw: yaw + atan2(sin(yawDelta), cos(yawDelta)) * fraction,
                     pitch: pitch + (target.pitch - pitch) * fraction,
                     roll: roll + (target.roll - roll) * fraction)
    }
}

enum RemoteOrbitChange {
    case dragging(RemotePose), inspecting(RemotePose), reset
}

struct RemoteModelView: View {
    let selected: RemoteButton?
    let recentlyPressed: RemoteButton?
    let pose: RemotePose
    let projection: RemoteProjection
    let outlineOpacity: Double
    var mappedButtons: Set<RemoteButton> = []
    let canOrbit: Bool
    let onOrbit: (RemoteOrbitChange) -> Void
    let onSelect: (RemoteButton) -> Void
    var onReady: () -> Void = {}
    @State private var dragOrigin: RemotePose?
    @State private var lastDragEnd = Date.distantPast

    var body: some View {
        ZStack(alignment: .topLeading) {
            RemoteScene(pose: pose, projection: projection, onReady: onReady)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            if canOrbit {
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { onOrbit(.reset) }
                    .help("拖动旋转 · 点击实体按键放大编辑")
                    .accessibilityHidden(true)
            }

            ForEach(Hotspot.all) { hotspot in
                if let placement = hotspot.placement(in: projection, pose: pose) {
                    let isSelected = selected == hotspot.id
                    KeyButton(button: hotspot.id, placement: placement,
                              outlineOpacity: outlineOpacity, selected: isSelected,
                              mapped: mappedButtons.contains(hotspot.id),
                              recentlyPressed: recentlyPressed == hotspot.id) {
                        guard dragOrigin == nil, lastDragEnd.timeIntervalSinceNow < -0.12 else { return }
                        onSelect(hotspot.id)
                    }
                    .zIndex(isSelected ? 1 : 0)
                    if isSelected, outlineOpacity > 0 {
                        selectedLabel(for: hotspot.id, placement: placement)
                            .opacity(outlineOpacity)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                            .zIndex(2)
                    }
                }
            }
        }
        .simultaneousGesture(DragGesture(minimumDistance: 5)
            .onChanged { value in
                if dragOrigin == nil { dragOrigin = pose }
                if let dragOrigin { onOrbit(.dragging(dragOrigin.turned(by: value.translation))) }
            }
            .onEnded { _ in
                if dragOrigin != nil { onOrbit(.reset) }
                dragOrigin = nil
                lastDragEnd = Date()
            }, including: canOrbit ? .all : .none)
        .onChange(of: canOrbit) { if !$0 { dragOrigin = nil } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("A2540 遥控器")
        .accessibilityHint(canOrbit ? "点击实体按键放大编辑，也可以拖动旋转。" : "选择实体按键来编辑映射。")
        .accessibilityActions {
            if canOrbit {
                Button("向左旋转") { turn(-28) }
                Button("向右旋转") { turn(28) }
                Button("回到默认角度") { onOrbit(.reset) }
            }
        }
    }

    private func selectedLabel(for button: RemoteButton, placement: Hotspot.Placement) -> some View {
        let title: String = switch button {
        case .home: "主屏幕"
        case .playPause: "播放/暂停"
        case .siri: "Siri 侧键"
        default: button.title
        }
        let mapped = mappedButtons.contains(button)
        let key = placement.outlineBounds
        let width = ceil((title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 14)]).width) + 24
        let height: CGFloat = 36
        let center: CGPoint
        switch button {
        case .up:
            center = CGPoint(x: key.midX, y: key.minY - 12 - height / 2)
        case .down:
            center = CGPoint(x: key.midX, y: key.maxY + 12 + height / 2)
        case .left, .select, .back, .playPause, .mute:
            let left = button == .select ? Self.bodyBounds(in: projection, pose: pose).minX : key.minX
            center = CGPoint(x: left - 12 - width / 2, y: key.midY)
        default:
            center = CGPoint(x: key.maxX + 12 + width / 2, y: key.midY)
        }
        return Text(title)
            .font(.system(size: 14))
            .foregroundStyle(mapped ? RimoStyle.assignmentInk : Color.black)
            .frame(width: width, height: height)
            .background(mapped ? RimoStyle.assignmentAccent : .white, in: RoundedRectangle(cornerRadius: 4))
            .shadow(color: .black.opacity(0.10), radius: 10, x: 6, y: 6)
            .position(x: min(max(width / 2 + 4, center.x), projection.size.width - width / 2 - 4),
                      y: min(max(height / 2 + 4, center.y), projection.size.height - height / 2 - 4))
    }

    func turn(_ amount: CGFloat) {
        onOrbit(.inspecting(pose.turned(by: CGSize(width: amount, height: 0))))
    }

    static func focusBounds(for button: RemoteButton, in projection: RemoteProjection, pose: RemotePose) -> CGRect? {
        Hotspot.all.first { $0.id == button }?.placement(in: projection, pose: pose)?.outlineBounds
    }

    nonisolated static func bodyBounds(in projection: RemoteProjection, pose: RemotePose) -> CGRect {
        let rotation = pose.orientation
        let points = [-1.78, 1.78].flatMap { x in
            [-0.49, 0.49].flatMap { y in
                [-6.76, 6.76].map { z in
                    projection.point(rotation.act(SIMD3(Float(x), Float(y), Float(z))))
                }
            }
        }
        return points.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
    }

    // Preserve the existing focused camera framing.
    nonisolated static let focusedHorizontalInset: CGFloat = 192

    private struct KeyButton: View {
        let button: RemoteButton
        let placement: Hotspot.Placement
        let outlineOpacity: Double
        let selected: Bool
        let mapped: Bool
        let recentlyPressed: Bool
        let action: () -> Void
        @FocusState private var focused: Bool

        var body: some View {
            Button(action: action) {
                placement.outline.fill(.clear)
                    .overlay {
                        if outlineOpacity > 0 {
                            placement.outline
                                .stroke(mapped ? RimoStyle.assignmentAccent : .white,
                                        style: StrokeStyle(lineWidth: selected || focused ? 3 : 2, lineJoin: .round))
                                .opacity(outlineOpacity)
                                .allowsHitTesting(false)
                        } else if focused {
                            placement.outline.edge(.white, width: 2)
                                .allowsHitTesting(false)
                        }
                        if recentlyPressed {
                            placement.outline.fill(.white.opacity(0.20))
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(width: placement.bounds.width, height: placement.bounds.height)
                    .contentShape(placement.hitArea)
            }
            .buttonStyle(.plain)
            .focused($focused)
            .accessibilityLabel(button.title)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .help(selected ? "\(button.title) · 正在编辑" : "\(button.title) · 点击编辑")
            .position(x: placement.bounds.midX, y: placement.bounds.midY)
        }
    }

    private struct ProjectedShape: Shape {
        let path: Path
        func path(in rect: CGRect) -> Path { path }

        func edge(_ color: Color, width: CGFloat) -> some View {
            stroke(color, style: StrokeStyle(lineWidth: width, lineJoin: .round))
                .mask { fill(.white) }
        }
    }

    // Project the button planes with the same orientation and orthographic camera as SceneKit.
    private struct Hotspot: Identifiable {
        let id: RemoteButton
        let x: Float
        let z: Float
        let width: CGFloat
        let height: CGFloat
        let radius: CGFloat
        let surfaceY: Float
        let contour: Contour


        enum Contour {
            case rounded, ring(Double), rocker(top: Bool)
        }

        struct Placement {
            let bounds: CGRect
            let outline: ProjectedShape
            let hitArea: ProjectedShape

            var outlineBounds: CGRect {
                outline.path.boundingRect.offsetBy(dx: bounds.minX, dy: bounds.minY)
            }
        }

        init(_ id: RemoteButton, _ x: Float, _ z: Float, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat,
             surfaceY: Float = 0.49, contour: Contour = .rounded) {
            self.id = id; self.x = x; self.z = z
            self.width = width; self.height = height; self.radius = radius
            self.surfaceY = surfaceY
            self.contour = contour
        }

        private var localPath: Path {
            switch contour {
            case .rounded:
                let frame = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
                // The circular keys are circles, not continuous/cubic rounded rectangles.
                return width == height && radius == width / 2
                    ? Path(ellipseIn: frame) : Path(roundedRect: frame, cornerRadius: radius)
            case .ring(let angle):
                let outer: CGFloat = 1.548
                let inner: CGFloat = 0.876
                let span = Double.pi / 4
                let start = Angle.radians(angle - span)
                let end = Angle.radians(angle + span)
                var path = Path()
                path.addArc(center: .zero, radius: outer, startAngle: start, endAngle: end, clockwise: false)
                path.addLine(to: CGPoint(x: inner * cos(end.radians), y: inner * sin(end.radians)))
                path.addArc(center: .zero, radius: inner, startAngle: end, endAngle: start, clockwise: true)
                path.closeSubpath()
                return path
            case .rocker(let top):
                let capRadius = width / 2
                var path = Path()
                path.addArc(center: CGPoint(x: 0, y: capRadius - height / 2), radius: capRadius,
                            startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
                path.addLine(to: CGPoint(x: capRadius, y: height / 2))
                path.addLine(to: CGPoint(x: -capRadius, y: height / 2))
                path.closeSubpath()
                return top ? path : path.applying(CGAffineTransform(scaleX: 1, y: -1))
            }
        }

        func placement(in viewport: RemoteProjection, pose: RemotePose) -> Placement? {
            let rotation = pose.orientation
            let side = id == .siri
            let facing = rotation.act(side ? SIMD3(1, 0, 0) : SIMD3(0, 1, 0)).y
            // Give the narrow side key some tolerance near an edge-on view.
            guard facing > (side ? -0.16 : 0.16) else { return nil }
            let unit = viewport.unit
            let center = viewport.point(rotation.act(SIMD3(x, side ? 0.082 : surfaceY, z)))
            let tangent = rotation.act(side ? SIMD3(0, -1, 0) : SIMD3(1, 0, 0))
            let vertical = rotation.act(SIMD3(0, 0, 1))
            // From straight ahead the side button is seen edge-on.
            let horizontal = side ? max(0.07, CGFloat(tangent.x)) : CGFloat(tangent.x)
            var projection = CGAffineTransform(
                a: unit * horizontal,
                b: unit * CGFloat(tangent.z),
                c: unit * CGFloat(vertical.x),
                d: unit * CGFloat(vertical.z),
                tx: center.x,
                ty: center.y
            )
            let local = localPath
            let path = local.applying(projection)
            if side { projection.a = max(projection.a, unit * 0.58) }
            let hitArea = side ? local.applying(projection) : path
            let bounds = path.boundingRect.union(hitArea.boundingRect)
            guard bounds.width > 0, bounds.height > 0 else { return nil }
            return Placement(bounds: bounds,
                             outline: .init(path: path.offsetBy(dx: -bounds.minX, dy: -bounds.minY)),
                             hitArea: .init(path: hitArea.offsetBy(dx: -bounds.minX, dy: -bounds.minY)))
        }

        static let all: [Self] = [
            // Centers, rims and face heights follow the bundled mesh, rather than an evenly spaced grid.
            .init(.power, 1.021, -6.068, 0.600, 0.600, 0.300, surfaceY: 0.447),
            .init(.up, -0.034, -3.934, 0, 0, 0, contour: .ring(-.pi / 2)),
            .init(.left, -0.034, -3.934, 0, 0, 0, contour: .ring(.pi)),
            .init(.select, -0.034, -3.934, 1.752, 1.752, 0.876, surfaceY: 0.432),
            .init(.right, -0.034, -3.934, 0, 0, 0, contour: .ring(0)),
            .init(.down, -0.034, -3.934, 0, 0, 0, contour: .ring(.pi / 2)),
            .init(.back, -0.788, -1.653, 1.228, 1.228, 0.614),
            .init(.home, 0.720, -1.652, 1.228, 1.228, 0.614),
            .init(.playPause, -0.788, -0.185, 1.228, 1.228, 0.614),
            .init(.volumeUp, 0.720, -0.123, 1.186, 1.344, 0.593, contour: .rocker(top: true)),
            .init(.mute, -0.788, 1.281, 1.224, 1.224, 0.612),
            .init(.volumeDown, 0.720, 1.221, 1.186, 1.344, 0.593, contour: .rocker(top: false)),
            .init(.siri, 1.782, -3.934, 0.370, 1.510, 0.185)
        ]
    }
}

private struct RemoteScene: NSViewRepresentable {
    let pose: RemotePose
    let projection: RemoteProjection
    let onReady: () -> Void

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        let scene = Bundle.main.url(forResource: "SiriRemote", withExtension: "usdz")
            .flatMap { try? SCNScene(url: $0, options: nil) } ?? SCNScene()
        let pivot = SCNNode()
        for child in scene.rootNode.childNodes { pivot.addChildNode(child) }
        scene.rootNode.addChildNode(pivot)
        context.coordinator.pivot = pivot
        // The source shell is nearly white. Grade only the aluminum under
        // studio light so its silhouette and top-to-bottom falloff stay visible.
        pivot.enumerateChildNodes { node, _ in
            for material in node.geometry?.materials ?? [] where material.name == "lCkxUhaVSHJkAPH" {
                material.shaderModifiers = [.fragment: """
                    float height = saturate((_surface.position.y + 6.76f) / 13.52f);
                    _output.color.rgb = min(_output.color.rgb, float3(1.0f)) * mix(0.60f, 0.92f, height);
                    """]
            }
        }

        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = projection.cameraScale
        camera.projectionDirection = .vertical
        camera.zNear = 0.1
        camera.zFar = 80
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 22, projection.cameraZ)
        cameraNode.eulerAngles.x = -.pi / 2
        scene.rootNode.addChildNode(cameraNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 315
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let key = SCNLight()
        key.type = .directional
        key.intensity = 420
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-1.1, -0.5, -0.25)
        scene.rootNode.addChildNode(keyNode)

        let fill = SCNLight()
        fill.type = .directional
        fill.intensity = 165
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.eulerAngles = SCNVector3(-1.15, 0.65, 0.35)
        scene.rootNode.addChildNode(fillNode)

        let highlight = SCNLight()
        highlight.type = .omni
        highlight.intensity = 480
        highlight.attenuationStartDistance = 1
        highlight.attenuationEndDistance = 16
        highlight.attenuationFalloffExponent = 1.8
        let highlightNode = SCNNode()
        highlightNode.light = highlight
        highlightNode.position = SCNVector3(-3, 9, -6)
        scene.rootNode.addChildNode(highlightNode)

        view.scene = scene
        view.pointOfView = cameraNode
        pivot.simdOrientation = pose.orientation
        let coordinator = context.coordinator
        coordinator.onReady = onReady
        coordinator.view = view
        // Prepare geometry, textures and shaders before declaring the scene ready.
        view.prepare([scene]) { success in
            guard success else { return }
            Task { @MainActor in
                coordinator.prepared = true
                view.delegate = coordinator
                view.isPlaying = true
            }
        }
        return view
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func updateNSView(_ view: SCNView, context: Context) {
        let orientation = pose.orientation
        let scale = projection.cameraScale
        let z = projection.cameraZ
        guard let pivot = context.coordinator.pivot, let cameraNode = view.pointOfView,
              pivot.simdOrientation.vector != orientation.vector
                || cameraNode.camera?.orthographicScale != scale || cameraNode.position.z != z else { return }
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        pivot.simdOrientation = orientation
        cameraNode.camera?.orthographicScale = scale
        cameraNode.position.z = z
        SCNTransaction.commit()
    }

    @MainActor final class Coordinator: NSObject, SCNSceneRendererDelegate {
        weak var view: SCNView?
        var pivot: SCNNode?
        var onReady: (() -> Void)?
        var prepared = false
        private var delivered = false

        nonisolated func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
            Task { @MainActor [weak self] in
                guard let self, prepared, !delivered else { return }
                delivered = true
                view?.delegate = nil
                view?.isPlaying = false
                onReady?()
            }
        }
    }
}
