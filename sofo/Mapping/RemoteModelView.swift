import SceneKit
import SwiftUI

struct RemoteModelView: View {
    let selected: RemoteButton?
    let recentlyPressed: RemoteButton?
    var onSelect: (RemoteButton) -> Void
    @State private var cameraTurn = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let unit = geometry.size.height / 14
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            ZStack(alignment: .topLeading) {
                RemoteScene(turn: cameraTurn)
                    .accessibilityHidden(true)
                    .gesture(DragGesture(minimumDistance: 4)
                        .onChanged { cameraTurn = min(0.40, max(-0.40, $0.translation.width / 180)) }
                        .onEnded { _ in
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) { cameraTurn = 0 }
                        })


                ForEach(Hotspot.all) { point in
                    Button { onSelect(point.id) } label: {
                        Color.clear
                            .frame(width: unit * point.width, height: unit * point.height)
                            .overlay {
                                if selected == point.id || recentlyPressed == point.id {
                                    let outline = RoundedRectangle(cornerRadius: unit * point.radius)
                                    outline
                                        .fill(.white.opacity(recentlyPressed == point.id ? 0.30 : 0.12))
                                        .overlay { outline.strokeBorder(SofoStyle.surface, lineWidth: 3.5) }
                                        .overlay { outline.strokeBorder(SofoStyle.ink, lineWidth: 1.4) }
                                        .allowsHitTesting(false)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(point.id.title)
                    .accessibilityAddTraits(selected == point.id ? .isSelected : [])
                    .help(point.id.title)
                    .position(x: center.x + unit * (point.x * cos(cameraTurn) + point.elevation * sin(cameraTurn)),
                              y: center.y + unit * point.y)
                }
            }
        }
    }

    // SceneKit world positions for the supplied USDZ, with -Z toward the top.
    private struct Hotspot: Identifiable {
        let id: RemoteButton
        let x: Double
        let y: Double
        let width: CGFloat
        let height: CGFloat
        let radius: CGFloat
        var elevation: Double { id == .siri ? 0.12 : 0.5 }

        init(_ id: RemoteButton, _ x: Double, _ y: Double, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat) {
            self.id = id; self.x = x; self.y = y
            self.width = width; self.height = height; self.radius = radius
        }

        static let all: [Self] = [
            .init(.power, 1.02, -6.08, 0.66, 0.65, 0.36),
            .init(.up, -0.03, -5.25, 1.43, 0.61, 0.28),
            .init(.left, -1.32, -3.95, 0.58, 1.44, 0.27),
            .init(.select, -0.03, -3.95, 1.76, 1.76, 0.9),
            .init(.right, 1.25, -3.95, 0.58, 1.44, 0.27),
            .init(.down, -0.03, -2.60, 1.43, 0.61, 0.28),
            .init(.back, -0.79, -1.65, 1.24, 1.24, 0.63),
            .init(.home, 0.72, -1.65, 1.24, 1.24, 0.63),
            .init(.playPause, -0.79, -0.18, 1.24, 1.24, 0.63),
            .init(.volumeUp, 0.72, -0.18, 1.18, 1.37, 0.58),
            .init(.mute, -0.79, 1.30, 1.24, 1.24, 0.63),
            .init(.volumeDown, 0.72, 1.30, 1.18, 1.37, 0.58),
            .init(.siri, 1.86, -3.93, 0.46, 1.55, 0.25)
        ]
    }
}

private struct RemoteScene: NSViewRepresentable {
    let turn: Double

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
        camera.orthographicScale = 7
        camera.projectionDirection = .vertical
        camera.zNear = 0.1
        camera.zFar = 80
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 22, 0)
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
        return view
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func updateNSView(_ view: SCNView, context: Context) {
        context.coordinator.pivot?.eulerAngles.z = CGFloat(-turn)
    }

    final class Coordinator { var pivot: SCNNode? }
}
