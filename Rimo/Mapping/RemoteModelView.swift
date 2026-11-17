import AppKit
import SceneKit
import SwiftUI
import simd

enum RemotePresentation {
    static func centerOffset(in availableHeight: CGFloat) -> CGFloat {
        -5 - min(40, availableHeight * 0.07)
    }

    static func height(in availableHeight: CGFloat) -> CGFloat {
        min(430, max(0, availableHeight * 0.76))
    }
}

/// A single orthographic projection drives the camera, hotspot hit areas and callouts.
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
    let calloutOpacity: Double
    let compactCallout: Bool
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
                    let callout = isSelected && calloutOpacity > 0
                        ? hotspot.callout(in: projection, pose: pose, placement: placement, compact: compactCallout)
                        : nil
                    KeyButton(button: hotspot.id, placement: placement, callout: callout,
                              calloutOpacity: calloutOpacity, selected: isSelected,
                              recentlyPressed: recentlyPressed == hotspot.id) {
                        guard dragOrigin == nil, lastDragEnd.timeIntervalSinceNow < -0.12 else { return }
                        onSelect(hotspot.id)
                    }
                    .zIndex(isSelected ? 1 : 0)
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
        .accessibilityHint(canOrbit ? "点击实体按键放大编辑，也可以拖动旋转。" : "选择标签或实体按键来编辑映射。")
        .accessibilityActions {
            if canOrbit {
                Button("向左旋转") { turn(-28) }
                Button("向右旋转") { turn(28) }
                Button("回到默认角度") { onOrbit(.reset) }
            }
        }
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

    // Preserve the focused camera framing and leave room for a label on either side.
    nonisolated static let calloutMargins: CGFloat = 192

    private struct Callout {
        let title: String
        let label: CGRect
        let fontSize: CGFloat
    }

    private struct ActiveCallout: View {
        let callout: Callout
        let origin: CGPoint
        @Environment(\.colorScheme) private var scheme

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 4)
            Text(callout.title)
                .font(.system(size: callout.fontSize))
                .foregroundStyle(RimoStyle.assignmentInk)
                .lineLimit(1)
                .frame(width: callout.label.width, height: callout.label.height)
                .background(RimoStyle.assignmentAccent, in: shape)
                .overlay { shape.strokeBorder(RimoStyle.assignmentBorder, lineWidth: 1) }
                .shadow(color: .black.opacity(scheme == .dark ? 0.20 : 0.10), radius: 10, x: 6, y: 6)
                .position(x: callout.label.midX - origin.x, y: callout.label.midY - origin.y)
        }
    }

    private struct KeyButton: View {
        let button: RemoteButton
        let placement: Hotspot.Placement
        let callout: Callout?
        let calloutOpacity: Double
        let selected: Bool
        let recentlyPressed: Bool
        let action: () -> Void
        @FocusState private var focused: Bool
        private let selectionOutline = Color(red: 99.0 / 255, green: 102.0 / 255, blue: 241.0 / 255)

        var body: some View {
            let frame = callout.map { placement.bounds.union($0.label) } ?? placement.bounds
            let hitArea = placement.hitArea.path.offsetBy(dx: placement.bounds.minX - frame.minX,
                                                         dy: placement.bounds.minY - frame.minY)
            Button(action: action) {
                ZStack(alignment: .topLeading) {
                    placement.outline.fill(.clear)
                        .overlay {
                            if callout != nil {
                                placement.outline
                                    .stroke(selectionOutline, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                                    .shadow(color: selectionOutline.opacity(0.22), radius: 3)
                                    .opacity(calloutOpacity)
                                    .allowsHitTesting(false)
                            } else if recentlyPressed || focused {
                                placement.outline.edge(.white, width: 2)
                                    .allowsHitTesting(false)
                            }
                        }
                        .frame(width: placement.bounds.width, height: placement.bounds.height)
                        .position(x: placement.bounds.midX - frame.minX, y: placement.bounds.midY - frame.minY)

                    if let callout {
                        ActiveCallout(callout: callout, origin: frame.origin)
                            .opacity(calloutOpacity)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: frame.width, height: frame.height)
                .contentShape(ProjectedShape(path: Path { path in
                    path.addPath(hitArea)
                    if let callout, calloutOpacity >= 0.75 {
                        path.addRoundedRect(in: callout.label.offsetBy(dx: -frame.minX, dy: -frame.minY),
                                            cornerSize: CGSize(width: 4, height: 4))
                    }
                }))
            }
            .buttonStyle(.plain)
            .focused($focused)
            .accessibilityLabel(button.title)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .help(selected ? "\(button.title) · 关闭编辑" : "\(button.title) · 点击编辑")
            .position(x: frame.midX, y: frame.midY)
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
             contour: Contour = .rounded) {
            self.id = id; self.x = x; self.z = z
            self.width = width; self.height = height; self.radius = radius
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
                let inner: CGFloat = 0.887
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
            let center = viewport.point(rotation.act(SIMD3(x, side ? 0.082 : 0.49, z)))
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

        func callout(in viewport: RemoteProjection, pose: RemotePose, placement: Placement, compact: Bool) -> Callout {
            let title: String = switch id {
            case .home: "主屏幕"
            case .playPause: "播放/暂停"
            case .siri: "Siri 侧键"
            default: id.title
            }
            let isLeft = [RemoteButton.left, .select, .down, .back, .playPause, .mute].contains(id)
            let key = placement.outlineBounds
            let markerOffset: CGFloat = switch id {
            case .power, .back, .home, .playPause, .mute, .volumeUp, .volumeDown: key.width * 0.42
            case .left, .right: key.width * 0.26
            default: 0
            }
            let marker = CGPoint(x: key.midX + (isLeft ? -markerOffset : markerOffset), y: key.midY)
            let fontSize: CGFloat = compact ? 11 : 14
            let textWidth = (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: fontSize)]).width
            let width = ceil(textWidth) + (compact ? 18 : 26)
            let height: CGFloat = compact ? 28 : 42
            let x: CGFloat
            let y: CGFloat
            switch id {
            case .up:
                x = marker.x - width / 2
                y = marker.y - 20 - height
            case .select, .down:
                // Keep the label off the surrounding direction keys.
                let body = RemoteModelView.bodyBounds(in: viewport, pose: pose)
                x = body.minX - 12 - width
                y = marker.y - height / 2
            case .right:
                let body = RemoteModelView.bodyBounds(in: viewport, pose: pose)
                x = max(marker.x + 24, body.maxX + 14)
                y = marker.y - height / 2
            default:
                x = isLeft ? marker.x - 20 - width : marker.x + 24
                y = marker.y - height / 2
            }
            let frame = CGRect(x: max(4, min(x, viewport.size.width - width - 4)),
                               y: max(4, min(y, viewport.size.height - height - 4)), width: width, height: height)
            return Callout(title: title, label: frame, fontSize: fontSize)
        }

        static let all: [Self] = [
            .init(.power, 1.015, -6.08, 0.62, 0.62, 0.31),
            .init(.up, -0.034, -3.944, 0, 0, 0, contour: .ring(-.pi / 2)),
            .init(.left, -0.034, -3.944, 0, 0, 0, contour: .ring(.pi)),
            .init(.select, -0.034, -3.944, 1.774, 1.774, 0.887),
            .init(.right, -0.034, -3.944, 0, 0, 0, contour: .ring(0)),
            .init(.down, -0.034, -3.944, 0, 0, 0, contour: .ring(.pi / 2)),
            .init(.back, -0.786, -1.647, 1.228, 1.228, 0.614),
            .init(.home, 0.716, -1.647, 1.228, 1.228, 0.614),
            .init(.playPause, -0.786, -0.168, 1.228, 1.228, 0.614),
            .init(.volumeUp, 0.716, -0.115, 1.168, 1.340, 0.584, contour: .rocker(top: true)),
            .init(.mute, -0.786, 1.312, 1.228, 1.228, 0.614),
            .init(.volumeDown, 0.716, 1.225, 1.168, 1.340, 0.584, contour: .rocker(top: false)),
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
